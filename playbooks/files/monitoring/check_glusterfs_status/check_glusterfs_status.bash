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

IFS='|' read -r api_url username password < /dev/shm/secret/testuser_credentials
# oc login $api_url --username $username --password $password &> /dev/null

CLUSTER_NAME="$(hostname | sed -e 's/-bastion//')"

# First get the list of volumes from openshift and gluster
OPENSHIFT_VOLUME_FILE=$TMPDIR/volumes.openshift
GLUSTERFS_VOLUME_FILE=$TMPDIR/volumes.glusterfs

ssh $CLUSTER_NAME-master-2 "oc get pv -o json | jq '.items[] | .spec.glusterfs.path' -r | grep -v null" > $OPENSHIFT_VOLUME_FILE

case $CLUSTER_NAME in
  rahti-int)
    ssh $CLUSTER_NAME-master-2 "oc -n glusterfs rsh ds/glusterfs-storage gluster volume list" > $GLUSTERFS_VOLUME_FILE
    ;;
  rahti|varda|oso-qa|oso-devel-2-mm)
    ssh $CLUSTER_NAME-glusterfs-1 "sudo gluster volume list" > $GLUSTERFS_VOLUME_FILE
    ;;
  *)
    echo "default value"
    ssh $CLUSTER_NAME-master-2 "oc -n glusterfs rsh ds/glusterfs-storage gluster volume list" > $GLUSTERFS_VOLUME_FILE
    ;;
esac


# Debug
#cat $OPENSHIFT_VOLUME_FILE | wc -l
#cat $GLUSTERFS_VOLUME_FILE | wc -l

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
#EXTRA_VOLUMES_ON_OPENSHIFT=
#EXTRA_VOLUMES_ON_GLUSTERFS=

if [ "${EXTRA_VOLUMES_ON_OPENSHIFT}" = "${EXTRA_VOLUMES_ON_GLUSTERFS}" ]; then
  echo "volumes are in sync"
  CHECK_STATUS=$NAGIOS_STATE_OK
else
  echo "volumes are not in sync"
  CHECK_STATUS=$NAGIOS_STATE_WARNING
  echo "openshift exlusive volumes: $(diff $OPENSHIFT_VOLUME_FILE.sorted $GLUSTERFS_VOLUME_FILE.sorted --changed-group-format='%<' --unchanged-group-format='' | wc -l)"
  echo "glusterfs exclusive volumes: $(diff $OPENSHIFT_VOLUME_FILE.sorted $GLUSTERFS_VOLUME_FILE.sorted --changed-group-format='%>' --unchanged-group-format='' | wc -l)"
  echo "common volumes: $(comm -1 -2 $OPENSHIFT_VOLUME_FILE.sorted $GLUSTERFS_VOLUME_FILE.sorted | wc -l)"
fi

ret=$CHECK_STATUS

rm -f $KUBECONFIG
rm $TMPDIR/*
rmdir $TMPDIR

exit $ret