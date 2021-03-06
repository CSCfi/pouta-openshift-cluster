#!/usr/bin/env bash

PLAYBOOK_BASE=${PLAYBOOK_BASE:-'/opt/deployment/poc/playbooks'}
PAUSE_ON_HEADER=${PAUSE_ON_HEADER:-'0'}
ENABLE_TERMINAL_BELL=${ENABLE_TERMINAL_BELL:-'0'}

header() {
    echo
    echo "==============================================================================="
    echo
    echo "    $*"
    echo
    current_date=$(date -Iseconds)
    current_ts=$(date +%s)
    echo "==============================================================================="
    echo "$current_date  running for $((current_ts - start_ts)) seconds"
    echo

    if [ "$ENABLE_TERMINAL_BELL" == "1" ]; then echo $'\a'; fi
    sleep $PAUSE_ON_HEADER
}

start_ts=$(date +%s)

header Provision a fresh cluster
ansible-playbook -v -e allow_heat_stack_update=1 $PLAYBOOK_BASE/provision.yml
if [ $? != 0 ]; then echo "failed"; exit 1; fi

header Basic configuration with pre_install
ansible-playbook -v $PLAYBOOK_BASE/pre_install.yml
if [ $? != 0 ]; then echo "failed"; exit 1; fi

header Restore backed up /etc/ contents
ansible-playbook $PLAYBOOK_BASE/restore/restore_etc.yml
if [ $? != 0 ]; then echo "failed"; exit 1; fi

header Install containerized etcd with byo
# (the playbook will fail when it is skipping 'hosted' installation, but worry not)
ansible-playbook -v $PLAYBOOK_BASE/../../openshift-ansible/playbooks/byo/openshift-etcd/config.yml

header Stop etcd on all hosts
ansible etcd -b -a "systemctl stop etcd_container"

header Restore etcd data to a single member cluster
ansible-playbook -v $PLAYBOOK_BASE/restore/restore_etcd_to_single_member.yml
if [ $? != 0 ]; then echo "failed"; exit 1; fi

header Run scaleup for etcd
ansible ${ENV_NAME}-etcd-2,${ENV_NAME}-etcd-3 -b \
  -a 'rm -rf /var/lib/etcd/member /etc/etcd/etdc.conf /var/lib/POC_INSTALLED'
ansible-playbook -v $PLAYBOOK_BASE/restore/etcd_scaleup.yml
if [ $? != 0 ]; then echo "failed"; exit 1; fi

header Restore glusterfs config and state
ansible-playbook -v restore/restore_glusterfs.yml

header Run selected pieces of the installer
ansible etcd,nodes -a 'rm -f /var/lib/POC_INSTALLED'
ansible-playbook -v $PLAYBOOK_BASE/restore/config_except_glusterfs.yml
if [ $? != 0 ]; then echo "failed"; exit 1; fi

header Delete old pods from glusterfs namespace, fresh ones will work
ansible ${ENV_NAME}-master-1 -a 'oc delete pods --all -n glusterfs'

header Mark hosts as installed
ansible-playbook -v $PLAYBOOK_BASE/set_install_state.yml

header Finish by running site.yml
ansible-playbook -v $PLAYBOOK_BASE/site.yml
if [ $? != 0 ]; then echo "failed"; exit 1; fi

header Done
