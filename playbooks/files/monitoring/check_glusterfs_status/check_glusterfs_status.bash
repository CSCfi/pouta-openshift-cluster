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

CLUSTER_NAME="$(hostname | sed -e 's/-bastion//')"

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

OPENSHIFT_EXCLUSIVE=$(diff $OPENSHIFT_VOLUME_FILE.sorted $GLUSTERFS_VOLUME_FILE.sorted --changed-group-format='%<' --unchanged-group-format='' | wc -l)
GLUSTERFS_EXCLUSIVE=$(diff $OPENSHIFT_VOLUME_FILE.sorted $GLUSTERFS_VOLUME_FILE.sorted --changed-group-format='%>' --unchanged-group-format='' | wc -l)

if [ "${EXTRA_VOLUMES_ON_OPENSHIFT}" = "${EXTRA_VOLUMES_ON_GLUSTERFS}" ]; then
  echo "OK"
  CHECK_STATUS=$NAGIOS_STATE_OK
else
  CHECK_STATUS=$NAGIOS_STATE_WARNING
  echo "list of exclusive volumes in openshift: $EXTRA_VOLUMES_ON_OPENSHIFT list of exclusive volumes in glusterfs: $EXTRA_VOLUMES_ON_GLUSTERFS" | tr '\n' ','
fi

ret=$CHECK_STATUS

rm -f $KUBECONFIG
rm $TMPDIR/*
rmdir $TMPDIR

exit $ret