#!/usr/bin/env bats

# Check given attribute for given value in objects
# $1 - OpenShift namespace
# $2 - object type (ex: pod)
# $3 - label for filtering objects (ex: app=my_app)
# $4 - attribute in objects (ex: spec.nodeSelector.type)
# $5 - expected attribute value ('bigmem')
check_objects_for_attribute() {
    namespace=$1
    type=$2
    label=$3
    attribute=$4
    value=$5
    for res in $(oc get $type -n $namespace -l $label --o=jsonpath='{.items[].$attribute}')
    do
        echo "result was '$res', expected '$value'"
        [ $res == "$value" ]
    done
}

@test "test_registry_console_node_selector" {
    # check that all registry console replicas have infra node nodeSelector
    check_objects_for_attribute default pod app=registry-console spec.nodeSelector.node-role\.kubernetes\.io/infra true
}

@test "test_docker_registry_node_selector" {
    # check that all docker registry replicas have infra node nodeSelector
    check_objects_for_attribute default pod app=docker-registry spec.nodeSelector.node-role\.kubernetes\.io/infra true
}
