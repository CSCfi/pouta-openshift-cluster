#!/usr/bin/env bash

# Script to run a temporary deployment container. Should be executed in
# playbooks/openshift directory. Use sudo if that is required for
# launching docker.

docker run -it --rm --name pac-deployer \
    -v $PWD/../../../openshift-environments:/opt/deployment/openshift-environments:ro \
    -v $PWD/../../../pouta-ansible-cluster:/opt/deployment/pouta-ansible-cluster:ro \
    -v $PWD/../../../openshift-ansible:/opt/deployment/openshift-ansible:ro \
    -v $PWD/../../../openshift-ansible-tourunen:/opt/deployment/openshift-ansible-tourunen:ro \
    cscfi/pac-deployer
