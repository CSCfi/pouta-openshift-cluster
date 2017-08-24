#!/usr/bin/env bash

# Script to run a temporary deployment container. Should be executed in
# playbooks/openshift directory. Use sudo if that is required for
# launching docker.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

print_usage_and_exit()
{
    me=$(basename "$0")
    echo
    echo "Usage: $me [-p vault_password_file] [-P vault_password_file] [-e environment_name] [-i] [container arguments]"
    echo
    exit 1
}

docker_opts=''

while getopts "p:P:e:ih" opt; do
    case $opt in
        p)
            passfile=$OPTARG
            if [ ! -e $passfile ]; then
                echo "vault password file $passfile does not exist"
                exit 1
            fi
            docker_opts="$docker_opts -v $passfile:/dev/shm/secret/vaultpass:ro"
            ;;
        P)
            passfile=$OPTARG
            if [ ! -e $passfile ]; then
                echo "vault password file $passfile does not exist"
                exit 1
            fi
            docker_opts="$docker_opts -e VAULT_PASS=$(cat $passfile)"
            ;;
        e)
            docker_opts="$docker_opts -e ENV_NAME=$OPTARG"
            ;;
        i)
            docker_opts="$docker_opts -it"
            ;;
        *)
            print_usage_and_exit
            ;;
    esac
done
shift "$((OPTIND-1))"

docker run --rm --name poc-deployer \
    -v $SCRIPT_DIR/../../openshift-environments:/opt/deployment/openshift-environments:ro \
    -v $SCRIPT_DIR/../../poc:/opt/deployment/poc:ro \
    -v $SCRIPT_DIR/../../openshift-ansible:/opt/deployment/openshift-ansible:ro \
    $docker_opts \
    cscfi/poc-deployer $*
