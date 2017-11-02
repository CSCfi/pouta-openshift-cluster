#!/usr/bin/env bash

# Script to run a temporary deployment container. Should be executed in
# playbooks/openshift directory. Use sudo if that is required for
# launching docker. Further sessions can be opened by running
#
#  docker exec -it [environment_name]-deployer bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

print_usage_and_exit()
{
    me=$(basename "$0")
    echo
    echo "Usage: $me [options] [container arguments]"
    echo "  where options are"
    echo "  -p vault_password_file  path to file containing vault password"
    echo "                          mounted to /dev/shm/secrets/vaultpass"
    echo "  -P vault_password_file  path to file containing vault password"
    echo "                          exposed as environment variable VAULT_PASS"
    echo "  -e environment_name     environment to deploy"
    echo "  -i                      open interactive session"
    echo "  -s                      skip ssh config generation (useful when debugging broken installations)"
    exit 1
}

docker_opts=''

while getopts "p:P:e:ish" opt; do
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
            env_name=$OPTARG
            docker_opts="$docker_opts -e ENV_NAME=$env_name"
            ;;
        i)
            docker_opts="$docker_opts -it"
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
    -v $SCRIPT_DIR/../../openshift-environments:/opt/deployment/openshift-environments:ro \
    -v $SCRIPT_DIR/../../poc:/opt/deployment/poc:ro \
    -v $SCRIPT_DIR/../../openshift-ansible:/opt/deployment/openshift-ansible:ro \
    --name ${env_name}-deployer \
    $docker_opts \
    cscfi/poc-deployer $*
