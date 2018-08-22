#!/usr/bin/env bash

#
# This script acts as a wrapper around run_deployment_container, and opens
# a session for an environment either in a new or existing deployment container.
# The name of the environment is extracted from active tmux session name or from
# an environment variable 'POC_ENV_NAME'.

# figure out where we live to find run_deployment_container.bash
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# try to extract session name from tmux
if [[ ! -z $TMUX ]]; then
    env_name=$(tmux display-message -p '#S')
fi

# fallback: extract environment name from POC_ENV_NAME
if [[ -z $env_name ]]; then
    env_name=$POC_ENV_NAME
fi

# check if we have the environment name figured out
if [[ -z $env_name ]]; then
    echo "unable to extract environment name from tmux or POC_ENV_NAME"
    exit 1
fi

# check if a deployment container is already running
if docker ps | grep -q $env_name-deployer; then
    echo
    echo "Launching a new shell in existing container '$env_name-deployer'"
    echo
    docker exec -it $env_name-deployer bash
else
    echo
    echo "Launching a new deployment container '$env_name-deployer'"
    echo
    $script_dir/run_deployment_container.bash -p /dev/shm/secret/vaultpass -i -e $env_name $*
fi
