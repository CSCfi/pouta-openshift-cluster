#!/usr/bin/env bash

set -e

env_name=$ENV_NAME

clone_repo_if_not_found() {
    repo_name=$1
    repo_url=$2
    repo_branch=$3

    if [[ -e $HOME/$repo_name ]]; then
        echo
        echo "Using mounted $repo_name"
        echo
    else
        echo
        echo "Checking out $repo_name"
        echo "    Repo: $repo_url"
        echo "  Branch: $repo_branch"
        echo
        git clone --depth=1 -b $repo_branch $repo_url $HOME/$repo_name
    fi
}

echo "Initializing environment for $env_name"
echo

if [[ ! -e /dev/shm/secret/vaultpass ]]; then
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

# If we are in CI pipeline, make a copy of environment and append
# pipeline id to cluster_name to allow parallel pipeline execution
# Detection uses CI_PIPELINE_ID variable that is set by gitlab
if [ -z ${CI_PIPELINE_ID+x} ]; then
    # Normal operation
    export ANSIBLE_INVENTORY=$HOME/openshift-environments/${env_name}
else
    new_env_name="${env_name}-${CI_PIPELINE_ID}"
    echo "CI pipeline detected, change env_name to ${new_env_name}"
    mkdir -p /tmp/ci-ansible-environment
    cp -aR /opt/deployment/openshift-environments/* /tmp/ci-ansible-environment/
    # Replace name in groups file
    sed -i "s/${env_name}/${new_env_name}/g" "/tmp/ci-ansible-environment/${env_name}/groups"
    # Rename directories
    mv /tmp/ci-ansible-environment/${env_name} /tmp/ci-ansible-environment/${new_env_name}
    mv /tmp/ci-ansible-environment/group_vars/${env_name} /tmp/ci-ansible-environment/group_vars/${new_env_name}
    # Set ansible_inventory variable
    export ANSIBLE_INVENTORY=/tmp/ci-ansible-environment/${new_env_name}
    # Set env_name+ENV_NAME (yes, it is case sensitive) to new_env_name
    env_name=${new_env_name}
    ENV_NAME=${new_env_name}
    # Set ANSIBLE_ENVIRONMENT_PATH for os_env_path in initialize_ramdisk.yml
    export ANSIBLE_ENVIRONMENT_PATH=/tmp/ci-ansible-environment
fi

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
echo

echo "Sourcing OpenStack credentials"
source /dev/shm/$env_name/openrc.sh

echo "Sourcing deployment data"
source /dev/shm/$env_name/deployment_data.sh

if [[ "$SKIP_SSH_CONFIG" == "1" ]]; then
    echo
    echo "Skipping ssh config generation"
    echo
else
    echo
    echo "Generating ssh config entries"
    echo
    ansible-playbook generate_ssh_config.yml
fi

clone_repo_if_not_found openshift-ansible $OPENSHIFT_ANSIBLE_REPO $OPENSHIFT_ANSIBLE_BRANCH

popd > /dev/null

set +e
