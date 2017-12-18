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

@test "test default namespace pod health" {
    all_pods_count=$(oc get pods -n default -o json | jq '[.items[].status.phase]|length')
    running_pods_count=$(oc get pods -n default -o json | jq '[.items[].status.phase|select(. == "Running")]|length')

    [ $all_pods_count -eq $running_pods_count ]
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
    run check_route_url default-www default-www-admin

    [ $status -eq 0 ]

    run check_route_url default-www default-www-default

    [ $status -eq 0 ]

    run check_route_url default-www default-www-www

    [ $status -eq 0 ]
}

@test "test that heketi-metrics-exporter responds and authorization is required" {
    run check_route_url glusterfs heketi-metrics-exporter "Authorization Required"

    [ $status -eq 0 ]
}
