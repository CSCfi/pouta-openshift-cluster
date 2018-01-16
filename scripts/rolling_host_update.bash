#!/usr/bin/env bash

# Update or rebuild hosts one by one.
#
# NOTE:
# - use with caution
# - rebuilding first master is not supported, as that requires
#   restoring /etc/origin/master as part of the process

set -e

print_usage_and_exit()
{
    me=$(basename "$0")
    echo
    echo "Usage: $me [options] hosts"
    echo "  where options are"
    echo "  -a [rebuild|update]     action(s) to take on hosts, "
    echo "                          can be specified multiple times"
    echo "  -d                      drain nodes before actions using given control host"
    echo "  -u                      uncordon nodes after actions using given control host."
    echo "                          Note: rebuilding automatically activates nodes"
    echo "  -c control-host         control host to use for draining"
    echo "  -p                      power cycle after actions"
    echo "  -i image                image to rebuild on"
    echo
    echo "Example:"
    echo "  $me -a update -dup -c \$ENV_NAME-master-1 \$ENV_NAME-node-{1..4}"
    echo
    exit 1
}

rebuild_server() {
    host=$1
    opt_image=$2
    echo "rebuilding $host with image $opt_image"
    openstack server rebuild --image $opt_image $host
    while ! openstack server list | grep $host | grep -q " ACTIVE "; do
        echo "waiting for server to be active"
        sleep 5
    done
    wait_for_ssh $host
}

power_cycle_server() {
    host=$1
    echo "stopping $host"
    openstack server stop $host
    while ! openstack server list | grep $host | grep -q " SHUTOFF "; do
        echo "waiting for server to be powered off"
        sleep 5
    done
    echo "starting $host"
    openstack server start $host
    while ! openstack server list | grep $host | grep -q " ACTIVE "; do
        echo "waiting for server to be active"
        sleep 5
    done
    wait_for_ssh $host
}

update_server() {
    host=$1
    echo "updating packages on $host"
    ansible $host -m yum -a 'state=latest name=*'
}

drain_server() {
    host=$1
    echo "draining node $host"
    ansible $opt_control_host -m shell -a "oc adm drain $host --delete-local-data --force --ignore-daemonsets --grace-period=10"
}

uncordon_server() {
    host=$1
    echo "uncordoning node $host"
    ansible $opt_control_host -m shell -a "oc adm uncordon $host"
}

wait_for_ssh() {
    host=$1
    echo "waiting for server to respond"
    while ! ansible $host -a "uptime"; do
        echo "waiting for server to respond"
        sleep 5
    done
}

# Option flags
opt_actions=" "
opt_drain=
opt_uncordon=
opt_control_host=
opt_power_cycle=
opt_image=

# Process options
while getopts "a:c:i:duph" opt; do
    case $opt in
        a)
            opt_actions="${opt_actions}${OPTARG} "
            ;;
        d)
            opt_drain=1
            ;;
        u)
            opt_uncordon=1
            ;;
        p)
            opt_power_cycle=1
            ;;
        c)
            opt_control_host="${OPTARG}"
            ;;
        i)
            opt_image="${OPTARG}"
            ;;
        *)
            print_usage_and_exit
            ;;
    esac
done
shift "$((OPTIND-1))"

# Option validity checks
if [[ "$opt_actions" == " " ]]; then
    echo "ERROR: need to define at least one action"
    print_usage_and_exit
fi

if [[ $opt_actions =~ ' rebuild ' && -z $opt_image ]]; then
    echo "ERROR: need to define image for rebuild action"
    print_usage_and_exit
fi

if [[ (! -z $opt_drain || $opt_uncordon) && -z $opt_control_host ]]; then
    echo "ERROR: need to define control host with drain and uncordon option"
    print_usage_and_exit
fi

# Loop through given hosts
for host in $*; do
    echo
    echo "processing $host"
    echo

    if [[ $opt_actions =~ ' rebuild ' ]]; then
        echo "action: rebuild"
        [[ -n $opt_drain ]] && drain_server $host
        rebuild_server $host $opt_image
        echo "run site_scaleup.yml"
        ansible-playbook -v site_scaleup.yml
    fi

    if [[ $opt_actions =~ ' update ' ]]; then
        echo "action: update"
        [[ -n $opt_drain ]] && drain_server $host
        update_server $host
    fi

    [[ -n $opt_power_cycle ]] && power_cycle_server $host

    [[ -n $opt_uncordon ]] && uncordon_server $host
done
