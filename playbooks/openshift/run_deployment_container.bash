#!/usr/bin/env bash

# Script to run a temporary deployment container. Should be executed in
# playbooks/openshift directory. Use sudo if that is required for
# launching docker.

docker run -it --rm --name poc-deployer \
    -v $PWD/../../../openshift-environments:/opt/deployment/openshift-environments:ro \
    -v $PWD/../../../poc:/opt/deployment/poc:ro \
    -v $PWD/../../../openshift-ansible:/opt/deployment/openshift-ansible:ro \
    cscfi/poc-deployer
