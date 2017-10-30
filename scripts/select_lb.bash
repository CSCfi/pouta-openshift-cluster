#!/usr/bin/env bash

# Proof of concept script to check that OpenStack API responds and
# assign floating ip to another load balancer in case it does not.
# It assumes that there are two load balancers called
# ${ENV_NAME}-lb-{1,2}
#
# NOTE: This code has been used for developing scaleup playbooks.
#       It has not been tested in other scenarios. Use with caution.
#

if [ -z $PUBLIC_IP ]; then
    echo "Set PUBLIC_IP before running the script"
    sleep 1
    exit 1
fi

set -e

date

if ! curl -s -k -o /dev/null --connect-timeout 5 https://$PUBLIC_IP:8443; then

    current_lb=$(openstack server list -c Name -c Networks | grep $PUBLIC_IP | sed -e "s/ //g" | cut -d "|" -f 2)
    echo "Currently active LB: '$current_lb'"
    current_idx=${current_lb:(-1)}
    new_idx=$(( current_idx%2 + 1 ))
    new_host=${ENV_NAME}-lb-$new_idx

    echo "curl failed, re-assigning floating ip to $new_host"
    openstack server add floating ip $new_host $PUBLIC_IP
fi
