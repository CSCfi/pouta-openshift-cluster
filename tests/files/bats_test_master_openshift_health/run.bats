#!/usr/bin/env bats

# Make sure the given route returns a good response.
# $1 - the OpenShift namespace of the route
# $2 - the name of the route in the namespace
# $3 - optional string to grep in the output
check_route_url() {
    # OpenShift adds its own CA cert to the CA bundle. For testing, we don't
    # want to have that cert available, so create a copy of the CA bundle
    # without the OpenShift cert added.
    ca_bundle=$(mktemp)
    sed '/openshift-signer/,/^$/d' /etc/ssl/certs/ca-bundle.crt > $ca_bundle

    url=$(oc get route -n $1 -o json -o jsonpath='{.spec.host}' $2)

    url_content=$(curl --cacert $ca_bundle https://$url 2> /dev/null)
    curl_status=$?

    echo $url_content | grep "Application is not available" &> /dev/null
    grep_status=$?

    if [ $grep_status -eq 0 ]; then
        curl_status=1
    fi

    # optionally grep for content
    if [ ! -z "$3" ]; then
        echo $url_content | grep "$3" &> /dev/null
        curl_status=$?
    fi

    rm $ca_bundle

    return $curl_status
}

# Make sure the given namespace contains only healthy pods. Only check
# namespaces that exist.
# $1 - namespace
check_namespace_pod_health() {
    namespace_grep=$(oc get namespaces | grep "$1 ") || true
    if [[ -z $namespace_grep ]]; then
        skip "Namespace $1 does not exist, skipping pod health check"
    fi

    all_pods_count=$(oc get pods -n $1 -o json | jq '[.items[].status.phase]|length')
    running_pods_count=$(oc get pods -n $1 -o json | jq '[.items[].status.phase|select((. == "Running") or (. == "Succeeded"))]|length')

    [ $all_pods_count -eq $running_pods_count ]
}

@test "test default namespace pod health" {
    check_namespace_pod_health default
}

@test "test default-www namespace pod health" {
    check_namespace_pod_health default-www
}

@test "test glusterfs namespace pod health" {
    check_namespace_pod_health glusterfs
}

@test "test kube-public namespace pod health" {
    check_namespace_pod_health kube-public
}

@test "test kube-service-catalog namespace pod health" {
    check_namespace_pod_health kube-service-catalog
}

@test "test kube-system namespace pod health" {
    check_namespace_pod_health kube-system
}

@test "test logging namespace pod health" {
    check_namespace_pod_health logging
}

@test "test management-infra namespace pod health" {
    check_namespace_pod_health management-infra
}

@test "test monitoring-infra namespace pod health" {
    check_namespace_pod_health monitoring-infra
}

@test "test openshift namespace pod health" {
    check_namespace_pod_health openshift
}

@test "test openshift-infra namespace pod health" {
    check_namespace_pod_health openshift-infra
}

@test "test openshift-node namespace pod health" {
    check_namespace_pod_health openshift-node
}

@test "test openshift-web-console namespace pod health" {
    check_namespace_pod_health openshift-web-console
}

@test "test openshift-ansible-service-broker namespace pod health" {
    check_namespace_pod_health openshift-ansible-service-broker
}

@test "test openshift-template-service-broker namespace pod health" {
    check_namespace_pod_health openshift-template-service-broker
}

@test "test poc-housekeeping namespace pod health" {
    check_namespace_pod_health poc-housekeeping
{

@test "test webhooks namespace pod health" {
    check_namespace_pod_health webhooks
}

@test "test connectivity to registry URL" {
    run check_route_url default docker-registry-reencrypt

    [ $status -eq 0 ]
}

@test "test connectivity to registry console URL" {
    run check_route_url default registry-console

    [ $status -eq 0 ]
}

@test "test connectivity to default www app" {
    run check_route_url default-www default-www-admin "container cloud"

    [ $status -eq 0 ]

    run check_route_url default-www default-www-default "container cloud"

    [ $status -eq 0 ]

    run check_route_url default-www default-www-www "container cloud"

    [ $status -eq 0 ]
}

@test "test that heketi-metrics-exporter responds and authorization is required" {
    if [[ $POC_DEPLOY_MONITORING == 'False' ]]; then
        skip "Monitoring deployment is not enabled, skipping check"
    fi

    run check_route_url glusterfs heketi-metrics-exporter "Authorization Required"

    [ $status -eq 0 ]
}

@test "test that InfluxDB responds" {
    if [[ $POC_DEPLOY_MONITORING == 'False' ]]; then
        skip "Monitoring deployment is not enabled, skipping check"
    fi

    run check_route_url monitoring-infra influxdb-route

    [ $status -eq 0 ]
}

@test "test that InfluxDB requires auth" {
    if [[ $POC_DEPLOY_MONITORING == 'False' ]]; then
        skip "Monitoring deployment is not enabled, skipping check"
    fi

    url=$(oc get route -n monitoring-infra -o json -o jsonpath='{.spec.host}' influxdb-route)

    run bash -c "curl -G --data-urlencode 'db=prometheus' --data-urlencode 'q=SELECT * FROM \"1m\".\"machine_cpu_cores\" LIMIT 1' https://$url/query"

    [[ "$output" =~ "{\"error\":\"unable to parse authentication credentials\"}" ]]
}

@test "test query against InfluxDB" {
    if [[ $POC_DEPLOY_MONITORING == 'False' ]]; then
        skip "Monitoring deployment is not enabled, skipping check"
    fi

    token=$(oc get -o template secret monitoring-token --template={{.data.token}} -n monitoring-infra | base64 -d)
    url=$(oc get route -n monitoring-infra -o json -o jsonpath='{.spec.host}' influxdb-route)

    run bash -c "curl -G -u admin:$token --data-urlencode 'db=prometheus' --data-urlencode 'q=SELECT * FROM \"1m\".\"machine_cpu_cores\" LIMIT 1' https://$url/query"

    [[ "$output" =~ "kubernetes_io_hostname" ]]
}
