#!/usr/bin/env bash

#
# This script prunes Openshift's registry images which are
# older than $IMAGE_AGE weeks while keeping $KEEP_REVISIONS
# of the latest builds of each image.
#

# Get the service account token
PRUNER_TOKEN="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"
oc login https://$API_URL:8443 --token=$PRUNER_TOKEN

# Prune the registry images
oc adm prune images --keep-tag-revisions=$KEEP_REVISIONS --keep-younger-than=$IMAGE_AGE \
    --registry-url=https://docker-registry.$API_URL --confirm
