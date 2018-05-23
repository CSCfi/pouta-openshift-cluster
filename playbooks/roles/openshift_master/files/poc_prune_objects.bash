#!/usr/bin/env bash

# Script to prune old objects from OpenShift.
#
# Ref: https://docs.openshift.org/3.6/admin_guide/pruning_resources.html

export PATH="${PATH}:/usr/local/bin/"

for object in builds deployments; do
    echo "pruning $object"
    oc adm prune $object --orphans --keep-complete=5 --keep-failed=1 --keep-younger-than=168h --confirm
done
