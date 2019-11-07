#!/usr/bin/env bash

#
# This script acts as a wrapper around run_deployment_container, and opens
# a session for an environment either in a new or existing deployment container.
# The name of the environment is extracted from active tmux session name or from
# the first shell arg.
#

# get sudo rights if we do not have them already
[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

# figure out where we live to find run_deployment_container.bash
script_dir="$(dirname "$(readlink -f "$0")")"

# try to extract session name from tmux
if [[ ! -z $TMUX ]]; then
    env_name=$(tmux display-message -p '#S')
fi

# fallback: extract environment name from args
if [[ -z $env_name ]]; then
    env_name=$1
fi

# check if we have the environment name figured out
if [[ -z $env_name ]]; then
    echo "unable to extract environment name from tmux or shell arguments"
    exit 1
fi

# check if a deployment container is already running
if docker ps | grep -q ${env_name}-deployer; then
    echo
    echo "Launching a new shell in existing container '${env_name}-deployer'"
    echo
    docker exec -it ${env_name}-deployer bash
else
    echo
    echo "Launching a new deployment container '${env_name}-deployer'"
    if [[ -e "/dev/shm/secret/vaultpass-${env_name}" ]]; then
        vaultpass_path="/dev/shm/secret/vaultpass-${env_name}"
        echo "    using environment specific vaultpass-${env_name}"
    else
        vaultpass_path="/dev/shm/secret/vaultpass"
    fi
    echo

    ${script_dir}/run_deployment_container.bash -p $vaultpass_path -e $env_name
fi
