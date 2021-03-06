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
    echo "  -a [rebuild|update|pcycle]"
    echo "                           action(s) to take on hosts. "
    echo "                           - 'rebuild' runs 'openstack server rebuild',"
    echo "                              updates packages on the host,"
    echo "                              power cycles the host"
    echo "                              and runs site playbook"
    echo "                           - 'update' runs 'yum update'"
    echo "                           - 'pcycle' for just a power off/on cycle"
    echo "  -s service               stop service before actions"
    echo "                           can be specified multiple times"
    echo "  -d                       drain nodes before actions using given control host"
    echo "  -u                       uncordon nodes after actions using given control host."
    echo "                           Note: rebuilding automatically activates nodes"
    echo "  -c control-host          control host to use for draining"
    echo "  -p                       power cycle after actions"
    echo "  -w N                     wait N seconds between hosts"
    echo "  -r                       wait for node readiness after actions"
    echo
    echo "Examples:"
    echo "  $me -a update -dup -c \$ENV_NAME-master-1 \$ENV_NAME-node-{1..4}"
    echo "  $me -a rebuild -d -c \$ENV_NAME-master-1 \$ENV_NAME-node-{1..4}"
    echo
    exit 1
}

log() {
    echo "$(date -Iseconds) $*"
}

rebuild_server() {
    host=$1
    log "rebuilding $host"
    openstack server rebuild $host
    while ! openstack server list | grep $host | grep -q " ACTIVE "; do
        log "waiting for server to be active"
        sleep 5
    done
    wait_for_ssh $host
}

power_cycle_server() {
    host=$1
    log "stopping $host"
    openstack server stop $host
    while ! openstack server list | grep $host | grep -q " SHUTOFF "; do
        log "waiting for server to be powered off"
        sleep 5
    done
    log "starting $host"
    openstack server start $host
    while ! openstack server list | grep $host | grep -q " ACTIVE "; do
        log "waiting for server to be active"
        sleep 5
    done
    wait_for_ssh $host
}

update_server() {
    host=$1
    log "updating packages on $host"
    ansible $host -m yum -a 'state=latest name=*'
}

stop_service() {
    host=$1
    service=$2
    ansible $host -m shell -a "systemctl stop $service"
}

drain_server() {
    host=$1
    log "draining node $host"
    ansible $opt_control_host -m shell -a "oc adm drain $host --delete-local-data --ignore-daemonsets"
}

uncordon_server() {
    host=$1
    log "uncordoning node $host"
    ansible $opt_control_host -m shell -a "oc adm uncordon $host"
}

wait_for_ssh() {
    host=$1
    log "waiting for server to respond"
    while ! ansible $host -a "uptime"; do
        log "waiting for server to respond"
        sleep 5
    done
}

wait_for_node_readiness() {
    host=$1
    log "waiting for node to become ready"
    while ! ansible $opt_control_host -m shell -a "oc get node $host | grep ' Ready '" 2>&1 > /dev/null ; do
        log "waiting for node to become ready"
        sleep 5
    done
}

# Option flags
opt_actions=" "
opt_stop_services=" "
opt_drain=
opt_uncordon=
opt_control_host=
opt_power_cycle=
opt_wait_seconds=0
opt_wait_for_node_readiness=

# Process options
while getopts "a:s:c:w:duphr" opt; do
    case $opt in
        a)
            opt_actions="${opt_actions}${OPTARG} "
            ;;
        s)
            opt_stop_services="${opt_stop_services}${OPTARG} "
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
        w)
            opt_wait_seconds="${OPTARG}"
            ;;
        r)
            opt_wait_for_node_readiness=1
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

if [[ (! -z $opt_drain || $opt_uncordon) && -z $opt_control_host ]]; then
    echo "ERROR: need to define control host with drain and uncordon option"
    print_usage_and_exit
fi

# Loop through given hosts
for host in $*; do
    echo
    log "processing $host"
    echo

    for service in $opt_stop_services; do
      log "stopping $service"
      stop_service $host $service
    done

    if [[ $opt_actions =~ ' rebuild ' ]]; then
        log "action: rebuild"
        [[ -n $opt_drain ]] && drain_server $host
        rebuild_server $host
        update_server $host
        power_cycle_server $host
        log "apply site.yml"
        ansible-playbook -v site.yml
        [[ -n $opt_power_cycle ]] && power_cycle_server $host
    fi

    if [[ $opt_actions =~ ' update ' ]]; then
        log "action: update"
        [[ -n $opt_drain ]] && drain_server $host
        update_server $host
        [[ -n $opt_power_cycle ]] && power_cycle_server $host
    fi

    if [[ $opt_actions =~ ' pcycle ' ]]; then
        log "action: pcycle"
        [[ -n $opt_drain ]] && drain_server $host
        power_cycle_server $host
    fi

    [[ -n $opt_uncordon ]] && uncordon_server $host

    if [[ $opt_wait_seconds -ne 0 ]]; then
        echo "waiting $opt_wait_seconds seconds"
        sleep $opt_wait_seconds
    fi

    [[ -n $opt_wait_for_node_readiness ]] && wait_for_node_readiness $host
done
