#!/usr/bin/env bash
#
# Glusterfs volume check
# Depends on ssh connectivity between bastion and master node

# Nagios states
NAGIOS_STATE_OK=0
NAGIOS_STATE_WARNING=1
NAGIOS_STATE_CRITICAL=2
NAGIOS_STATE_UNKNOWN=3

CHECK_STATUS=$NAGIOS_STATE_UNKNOWN

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# create a temporary KUBECONFIG to avoid polluting the global environment
export KUBECONFIG=$(mktemp)

# create temp directory
TMPDIR=$(mktemp -d)

if [[ ! -f /dev/shm/secret/testuser_credentials ]]; then
  echo "Cannot find test user credentials in /dev/shm/secret/testuser_credentials"
  exit 1
fi

# login to openshift cluster
IFS='|' read -r api_url username password < /dev/shm/secret/testuser_credentials
oc login $api_url --username $username --password $password &> /dev/null

# First get the list of volumes from openshift and gluster
OPENSHIFT_VOLUME_FILE=$TMPDIR/volumes.openshift
GLUSTERFS_VOLUME_FILE=$TMPDIR/volumes.glusterfs

# get the volumes from openshift
oc get pv -o json | jq '.items[] | .spec.glusterfs.path' -r | grep -v null > $OPENSHIFT_VOLUME_FILE 2>/dev/null

# get the volumes from heketi
oc rsh -n glusterfs deploymentconfig.apps.openshift.io/heketi-storage heketi-cli volume list | awk '{print $NF}' | cut -c 6- | grep -o vol_[a-z0-9]* > $GLUSTERFS_VOLUME_FILE 2>/dev/null

# Sanity check, test if we have volume listings
if [ ! -f $OPENSHIFT_VOLUME_FILE ] || [ ! -f $GLUSTERFS_VOLUME_FILE ]; then
  exit $CHECK_STATUS
fi

# Sort volume lists for easier diff
sort $OPENSHIFT_VOLUME_FILE > $OPENSHIFT_VOLUME_FILE.sorted
sort $GLUSTERFS_VOLUME_FILE > $GLUSTERFS_VOLUME_FILE.sorted

# Get diff on volume listings
EXTRA_VOLUMES_ON_OPENSHIFT="$(diff $OPENSHIFT_VOLUME_FILE.sorted $GLUSTERFS_VOLUME_FILE.sorted --changed-group-format='%<' --unchanged-group-format='')"
EXTRA_VOLUMES_ON_GLUSTERFS="$(diff $OPENSHIFT_VOLUME_FILE.sorted $GLUSTERFS_VOLUME_FILE.sorted --changed-group-format='%>' --unchanged-group-format='')"

# report volume counts as performance metrics
PERF_OPENSHIFT_TOTAL=$(cat $OPENSHIFT_VOLUME_FILE | wc -l)
PERF_GLUSTERFS_TOTAL=$(cat $GLUSTERFS_VOLUME_FILE | wc -l)
PERF_OPENSHIFT_COUNT=$(echo -n "$EXTRA_VOLUMES_ON_OPENSHIFT" | grep -c '^')
PERF_GLUSTERFS_COUNT=$(echo -n "$EXTRA_VOLUMES_ON_GLUSTERFS" | grep -c '^')

if [ "${EXTRA_VOLUMES_ON_OPENSHIFT}" = "${EXTRA_VOLUMES_ON_GLUSTERFS}" ]; then
  echo "OK | openshift_volumes=$PERF_OPENSHIFT_TOTAL, gluster_volumes=$PERF_GLUSTERFS_TOTAL, extra_volumes_openshift=$PERF_OPENSHIFT_COUNT, extra_volumes_gluster=$PERF_GLUSTERFS_COUNT"
  CHECK_STATUS=$NAGIOS_STATE_OK
else
  CHECK_STATUS=$NAGIOS_STATE_WARNING
  # -z requires gnu sed v4.2.2. It's used here to format output nicely.
  #
  # Opsview truncates the output to 1024 characters, which means we can print
  # only about 20 volumes without truncating performance data. To ensure perf
  # data gets delivered even if gluster list is long (more likely than other
  # way around), truncate gluster list to 700 characters.
  EXTRA_VOLUMES_ON_GLUSTERFS_CUT="${EXTRA_VOLUMES_ON_GLUSTERFS::700}, <truncated>"
  echo "volumes unique to openshift: [$EXTRA_VOLUMES_ON_OPENSHIFT] volumes unique to heketi: [$EXTRA_VOLUMES_ON_GLUSTERFS_CUT] | openshift_volumes=$PERF_OPENSHIFT_TOTAL, gluster_volumes=$PERF_GLUSTERFS_TOTAL, extra_volumes_openshift=$PERF_OPENSHIFT_COUNT, extra_volumes_gluster=$PERF_GLUSTERFS_COUNT" | sed -z 's/\n/, /g'
fi

ret=$CHECK_STATUS

rm -f $KUBECONFIG
rm $TMPDIR/*
rmdir $TMPDIR

exit $ret