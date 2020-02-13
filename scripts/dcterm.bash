#!/usr/bin/env bash

#
# This script acts as a wrapper around run_deployment_container, and opens
# a session for an environment either in a new or existing deployment container.
# The name of the environment is extracted from active tmux session name or from
# the first shell arg.
#
# If you are using mac then please install greadlink through: brew install coreutils

# get sudo rights if we do not have them already
[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

# Check the OS
OS="$(uname -s)"

# figure out where we live to find run_deployment_container.bash
if [[ $OS == "Darwin" ]]; then
   readlink_cmd="greadlink"
else
   readlink_cmd="readlink"
fi

script_dir="$(dirname "$(${readlink_cmd} -f "$0")")"

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

case "${OS}" in
    Darwin*)
      vaultpass_dir="/Volumes/rRAMDisk/secret"
      ;;
    Linux*)
      vaultpass_dir="/dev/shm/secret"
      ;;
    *)
      echo "Only Darwin and Linux supported"
      exit 1
      ;;
esac

# check if a deployment container is already running
if docker ps | grep -q ${env_name}-deployer; then
    echo
    echo "Launching a new shell in existing container '${env_name}-deployer'"
    echo
    docker exec -it ${env_name}-deployer bash
else
    echo
    echo "Launching a new deployment container '${env_name}-deployer'"
    if [[ -e "${vaultpass_dir}/vaultpass-${env_name}" ]]; then
        vaultpass_path="${vaultpass_dir}/vaultpass-${env_name}"
        echo "    using environment specific vaultpass-${env_name}"
    else
        vaultpass_path="${vaultpass_dir}/vaultpass"
    fi
    echo

    ${script_dir}/run_deployment_container.bash -p $vaultpass_path -e $env_name
fi
