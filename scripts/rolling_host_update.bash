#!/usr/bin/env bash

# Proof of concept script to test rebuilding hosts one by one.
#
# NOTE:
# - This code has been used for developing scaleup playbooks.
#   It has not been tested in other scenarios. Use with caution.
# - updating first master is not supported, as that requires
#   restoring /etc/origin/master as part of the process
#

set -e

for host in $*; do
    echo
    echo "updating $host"
    echo
    if [ ! -z $CONTROL_HOST ]; then
        echo "draining node"
        ssh $CONTROL_HOST oc adm drain $host --delete-local-data --force --ignore-daemonsets --grace-period=10
    else
        echo "no CONTROL_HOST set, proceeding without draining"
    fi
    echo "rebuilding"
    openstack server rebuild --image $IMAGE $host
    while ! openstack server list | grep $host | grep -q " ACTIVE "; do
        echo "waiting for server to be active"
        sleep 5
    done

    echo "give it time to boot"
    sleep 30

    echo "run pre-install just for $host"
    ansible-playbook -v -l $host pre_install.yml

    echo "run scaleup"
    ansible-playbook -v scaleup.yml

done
