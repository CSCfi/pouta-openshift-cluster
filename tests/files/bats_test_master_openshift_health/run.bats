#!/usr/bin/env bats

@test "test default namespace pod health" {
    all_pods_count=$(oc get pods -n default -o json | jq '[.items[].status.phase]|length')
    running_pods_count=$(oc get pods -n default -o json | jq '[.items[].status.phase|select(. == "Running")]|length')

    [ $all_pods_count -eq $running_pods_count ]
}
