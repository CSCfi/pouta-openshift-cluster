#!/usr/bin/env bash

# Script to run a temporary deployment container. Should be executed in
# playbooks/openshift directory. Use sudo if that is required for
# launching docker.

print_usage_and_exit()
{
    me=$(basename "$0")
    echo
    echo "Usage: $me [-p vault_password_file] [-e environment_name] [container arguments]"
    echo
    exit 1
}

docker_opts=''

while getopts "p:e:h" opt; do
    case $opt in
        p)
            passfile=$OPTARG
            if [ ! -e $passfile ]; then
                echo "vault password file $passfile does not exist"
                exit 1
            fi
            docker_opts="$docker_opts -v $passfile:/dev/shm/secret/vaultpass"
            ;;
        e)
            docker_opts="$docker_opts -e ENV_NAME=$OPTARG"
            ;;

        *)
            print_usage_and_exit
            ;;
    esac
done
shift "$((OPTIND-1))"

if [ ! -z "$docker_opts" ]; then
    echo
    echo "using docker opts:$docker_opts"
    echo
fi

docker run -it --rm --name poc-deployer \
    -v $PWD/../../../openshift-environments:/opt/deployment/openshift-environments:ro \
    -v $PWD/../../../poc:/opt/deployment/poc:ro \
    -v $PWD/../../../openshift-ansible:/opt/deployment/openshift-ansible:ro \
    $docker_opts \
    cscfi/poc-deployer $*
