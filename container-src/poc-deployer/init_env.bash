#!/usr/bin/env bash

env_name=$ENV_NAME

echo "Initializing environment for $env_name"

if [ ! -e /dev/shm/secret/vaultpass ]; then
  mkdir -p /dev/shm/secret/
  touch /dev/shm/secret/vaultpass
  chmod 600 /dev/shm/secret/vaultpass
  read -s -p "vault password: " vaultpass
  echo
  echo $vaultpass > /dev/shm/secret/vaultpass
  echo "Wrote vault password to /dev/shm/secret/vaultpass"
  unset vaultpass
fi

export ANSIBLE_INVENTORY=$HOME/openshift-environments/$env_name
echo "ANSIBLE_INVENTORY set to $ANSIBLE_INVENTORY"

pushd /opt/deployment/poc/playbooks

SKIP_DYNAMIC_INVENTORY=1 ansible-playbook initialize_ramdisk.yml

popd

source /dev/shm/$env_name/openrc.sh
