#!/usr/bin/env bash

# Script restart heketi-storage by rolling out the latest deployment
#
export PATH="${PATH}:/usr/local/bin/"

oc -n glusterfs rollout latest heketi-storage
