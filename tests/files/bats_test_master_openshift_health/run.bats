#!/usr/bin/env bats

check_route_url() {
  # OpenShift adds its own CA cert to the CA bundle. For testing, we don't
  # want to have that cert available, so create a copy of the CA bundle
  # without the OpenShift cert added.
  ca_bundle=$(mktemp)
  sed '/openshift-signer/,/^$/d' /etc/ssl/certs/ca-bundle.crt > $ca_bundle

  url=$(oc get route $1 -o json -o jsonpath='{.spec.host}')

  curl --cacert $ca_bundle https://$url >&2
  curl_status=$?

  rm $ca_bundle

  return $curl_status
}

@test "test default namespace pod health" {
    all_pods_count=$(oc get pods -n default -o json | jq '[.items[].status.phase]|length')
    running_pods_count=$(oc get pods -n default -o json | jq '[.items[].status.phase|select(. == "Running")]|length')

    [ $all_pods_count -eq $running_pods_count ]
}

@test "test connectivity to registry URL" {
    run check_route_url docker-registry-reencrypt

    [ $status -eq 0 ]
}

@test "test connectivity to registry console URL" {
    run check_route_url registry-console

    [ $status -eq 0 ]
}
