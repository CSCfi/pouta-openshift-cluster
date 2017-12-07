#!/usr/bin/env bash

set -e

env_name=$ENV_NAME

echo "Initializing environment for $env_name"
echo

if [ ! -e /dev/shm/secret/vaultpass ]; then
    mkdir -p /dev/shm/secret/
    touch /dev/shm/secret/vaultpass
    chmod 600 /dev/shm/secret/vaultpass
    if [ -z $VAULT_PASS ]; then
        read -s -p "vault password: " VAULT_PASS
        echo
    fi
    echo $VAULT_PASS > /dev/shm/secret/vaultpass
    echo "Wrote vault password to /dev/shm/secret/vaultpass"
    unset VAULT_PASS
fi

export ANSIBLE_INVENTORY=$HOME/openshift-environments/$env_name
echo "ANSIBLE_INVENTORY set to $ANSIBLE_INVENTORY"
echo

export ANSIBLE_LIBRARY="/usr/share/ansible:\
$HOME/openshift-ansible/roles/lib_utils/library:\
$HOME/openshift-ansible/roles/lib_openshift/library"
echo "ANSIBLE_LIBRARY set to $ANSIBLE_LIBRARY"

pushd /opt/deployment/poc/playbooks > /dev/null

echo "Installing galaxy-roles"
echo
ansible-galaxy install -f -p $HOME/galaxy-roles -r requirements.yml

echo "Initializing ramdisk contents"
echo
SKIP_DYNAMIC_INVENTORY=1 ansible-playbook initialize_ramdisk.yml
source /dev/shm/$env_name/openrc.sh

if [ "$SKIP_SSH_CONFIG" == "1" ]; then
    echo
    echo "Skipping ssh config generation"
    echo
else
    echo
    echo "Generating ssh config entries"
    echo
    ansible-playbook generate_ssh_config.yml
fi

popd > /dev/null

set +e
