#!/usr/bin/env bash

# Script to run a temporary deployment container. Should be executed in
# playbooks/openshift directory. Use sudo if that is required for
# launching docker. Further sessions can be opened by running
#
#  docker exec -it [environment_name]-deployer bash

# Source local variables
shopt -s expand_aliases
source $HOME/.bashrc

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

print_usage_and_exit()
{
    me=$(basename "$0")
    echo
    echo "Usage: $me [options] [container arguments]"
    echo "  where options are"
    echo "  -p vault_password_file   path to file containing vault password"
    echo "                           mounted to /dev/shm/secrets/vaultpass"
    echo "  -P vault_password_file   path to file containing vault password"
    echo "                           exposed as environment variable VAULT_PASS"
    echo "  -e environment_name      environment to deploy"
    echo "  -o openshift_ansible_dir mount openshift-ansible from host. Use absolute path"
    echo "  -c container_image       use custom container image (default cscfi/poc-deployer)"
    echo "  -s                       skip ssh config generation (useful when debugging broken installations)"
    exit 1
}

docker_opts='-it'
container_image='cscfi/poc-deployer'

while getopts "p:P:e:o:c:sh" opt; do
    case $opt in
        p)
            passfile=$OPTARG
            if [[ ! -e $passfile ]]; then
                echo "vault password file $passfile does not exist"
                exit 1
            fi
            docker_opts="$docker_opts -v $passfile:/dev/shm/secret/vaultpass:ro"
            ;;
        P)
            passfile=$OPTARG
            if [[ ! -e $passfile ]]; then
                echo "vault password file $passfile does not exist"
                exit 1
            fi
            docker_opts="$docker_opts -e VAULT_PASS=$(cat $passfile)"
            ;;
        o)
            osa_dir=$OPTARG
            if [[ ! -d $osa_dir ]]; then
                echo "Error: openshift-ansible directory '$osa_dir' does not exist or is not a directory"
                exit 1
            fi
            docker_opts="$docker_opts -v $osa_dir:/opt/deployment/openshift-ansible:ro"
            ;;
        e)
            env_name=$OPTARG
            docker_opts="$docker_opts -e ENV_NAME=$env_name"
            ;;
        c)  container_image=$OPTARG
            echo "  using custom image $container_image"
            ;;
        s)
            docker_opts="$docker_opts -e SKIP_SSH_CONFIG=1"
            ;;
        *)
            print_usage_and_exit
            ;;
    esac
done
shift "$((OPTIND-1))"

docker run --rm \
    -v $SCRIPT_DIR/../../openshift-environments:/opt/deployment/openshift-environments:ro,Z \
    -v $SCRIPT_DIR/../../poc:/opt/deployment/poc:ro,Z \
    --name ${env_name}-deployer \
    $docker_opts \
    $container_image $*
