#!/bin/bash
# This is a one-off update script for replacing the load balancer nodes with
# ones that have keepalived enabled. It isn't necessarily useful for later cases,
# though you could use it as an example.

POC_PLAYBOOK_DIR=/opt/deployment/poc/playbooks
OSA_PLAYBOOK_DIR=/opt/deployment/openshift-ansible/playbooks

set -e

# Update the cluster Heat stack. This will replace the ports for the LB nodes.
# We don't check for SSH connectivity afterwards because the ports won't work
# at first because the LB nodes already have config for the MAC addresses of the
# previous ports. The MAC mismatch will mean the OS refuses to start the
# interface.
ansible-playbook -v -e allow_heat_stack_update_cluster=1 -e check_for_ssh_after_provisioning=0 $POC_PLAYBOOK_DIR/provision.yml

# Rebuild the LB nodes so that the old interface config is wiped out.
# Wait for the nodes to start responding again after rebuild.
openstack server rebuild $ENV_NAME-lb-1
openstack server rebuild $ENV_NAME-lb-2
while ! ansible lb -m shell -a "uptime" ; do sleep 10; done

# Wipe the attached Cinder device that's used for Docker pool storage so that
# there are no remnants of the previous Docker pool. We will configure the LB
# nodes from scratch.
ansible lb -m shell -a "dd if=/dev/zero of=/dev/vdb bs=1M count=1k"
ansible lb -m shell -a "shutdown -r 1"
sleep 70
while ! ansible lb -m shell -a "uptime" ; do sleep 10; done

# Run pre-install here so that keepalived is configured and DNS is updated in
# the cluster.
ansible-playbook -v $POC_PLAYBOOK_DIR/pre_install.yml

# Use openshift-ansible to configure the fresh LB nodes as load balancers.
# The mechanism changes in version 3.7, so we have two alternate playbooks here.
if [[ -d $OSA_PLAYBOOK_DIR/byo/openshift-loadbalancer ]]; then
  # 3.7
  ansible-playbook -v $OSA_PLAYBOOK_DIR/byo/openshift-loadbalancer/config.yml
else
  # 3.6
  ansible-playbook -v -t loadbalancer $OSA_PLAYBOOK_DIR/byo/config.yml
fi

# Finally run site_scaleup.yml
ansible-playbook -v $POC_PLAYBOOK_DIR/site_scaleup.yml
