#!/bin/bash
# With GlusterFS, volumes can sometimes get stuck in a state where they don't
# get properly unmounted from a pod that is being deleted. This leaves the pod
# stuck and unable to terminate. This script helps these pods get unstuck and
# properly terminate by removing stuck volume mounts. This is useful for making
# sure e.g. nodes can be drained for maintenance.

ssh $ENV_NAME-master-1 oc get pods --all-namespaces -o json | jq '.items[] | select(.metadata.deletionTimestamp) | .metadata.uid' | sed -e 's/"//g' > /tmp/terminating_pods

num_pods=$(cat /tmp/terminating_pods | wc -l)
if [[ "$num_pods" -gt "0" ]]; then
  echo "Hanging mounts for these pods will be unmounted:"
  cat /tmp/terminating_pods

  cat /tmp/terminating_pods | xargs --replace ansible ssd,node_masters -m shell -a "if [ -e /var/lib/origin/openshift.local.volumes/pods/{} ]; then umount /var/lib/origin/openshift.local.volumes/pods/{}/volumes/kubernetes.io~glusterfs/*; fi"
  rm -f /tmp/terminating_pods
else
  echo "No pods stuck in termination found."
fi
