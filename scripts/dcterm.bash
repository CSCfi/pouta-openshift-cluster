#!/usr/bin/env bash

#
# This script acts as a wrapper around run_deployment_container, and opens
# a session for an environment either in a new or existing deployment container.
# The name of the environment is extracted from active tmux session name or from
# the first shell arg.
#
# If you are using mac then you can use greadlink through: brew install coreutils
# or use inline function to emulate same behavior.

# Give basic usage info if no arguments given
if (( $# < 1 )); then
   echo "Usage: dcterm.bash [environment-name]"
   exit 1
fi

# get sudo rights if we do not have them already
[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

# OSX readlink -f substitute without external dependencies
# https://stackoverflow.com/questions/1055671/how-can-i-get-the-behavior-of-gnus-readlink-f-on-a-mac
function inline_osx_readlink() {
   TARGET_FILE=$2
   cd `dirname $TARGET_FILE`
   TARGET_FILE=`basename $TARGET_FILE`
   # Iterate down a (possible) chain of symlinks
   while [ -L "$TARGET_FILE" ]
   do
      TARGET_FILE=`readlink $TARGET_FILE`
      cd `dirname $TARGET_FILE`
      TARGET_FILE=`basename $TARGET_FILE`
   done
   # Compute the canonicalized name by finding the physical path 
   # for the directory we're in and appending the target file.
   PHYS_DIR=`pwd -P`
   RESULT=$PHYS_DIR/$TARGET_FILE
   echo $RESULT
}

# Check the OS
OS="$(uname -s)"

# figure out where we live to find run_deployment_container.bash
if [[ $OS == "Darwin" ]]; then
   if hash greadlink &> /dev/null; then
      # Let's use greadlink if we have it installed
      readlink_cmd="greadlink"
   else
      # Otherwise use our inline function
      readlink_cmd="inline_osx_readlink"
    fi
else
   # With Linux we can use native readlink which supports '-f' option
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
