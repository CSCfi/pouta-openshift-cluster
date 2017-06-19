#!/usr/bin/env bash

# This script creates a new buildconfig in OpenShift for oso-default-www
# Login to the desired cluster and project first.

echo "Building oso-default-www. You are logged in as:"
echo
oc whoami -c
echo
echo "If that does not look right, hit CTRL-C now."
sleep 5

oc new-build \
    openshift/python:3.5~https://github.com/CSCfi/pouta-ansible-cluster.git \
    --context-dir container-src/oso-default-www \
    --name oso-default-www

echo "By default, a build is started from the sources in master branch."
echo "To build from local sources, run"
echo
echo " oc start-build --from-dir ../.. oso-default-www"
echo
