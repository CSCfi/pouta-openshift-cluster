#!/usr/bin/env bash

# This script creates a new buildconfig in OpenShift
# The sources for building the container are assumed to be
# directly under a subdirectory, the name of the
# build matching the name of the subdirectory.
#

set -e

# Process arguments
if (( $# < 1 || $# > 2 )); then
    me=$(basename "$0")
    echo
    echo "Usage: $me name [[builder~]src]"
    echo
    exit 1
fi
name=${1:-foo}
src=${2:-https://github.com/CSCfi/pouta-ansible-cluster.git}

if ! oc project > /dev/null ; then
  echo "Error getting current OpenShift project. Check that you are logged in."
  exit 1
fi

echo "Building $name."
echo
oc project
echo
echo "If that does not look right, hit CTRL-C now."
sleep 5

echo "Creating build"
echo
echo "------------------------------------------------------------------------------"
oc new-build \
    $src \
    --context-dir container-src/$name \
    --name $name

echo "------------------------------------------------------------------------------"
echo
echo "By default, a build is started from the sources in remote repo."
echo "To build from local sources, run"
echo
echo " oc start-build --from-dir [directory for PAC git] $name"
echo
