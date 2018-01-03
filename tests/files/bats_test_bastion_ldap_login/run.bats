#!/usr/bin/env bats

@test "test login with test user credentials" {
    # read api end point and credentials from a pre populated files
    IFS='|' read -r api_url username password < /dev/shm/secret/testuser_credentials

    # create a temporary KUBECONFIG to avoid polluting the global environment
    export KUBECONFIG=$(mktemp)

    # then test logging in
    run oc login $api_url --username $username --password $password

    # remove the temporary KUBECONFIG
    rm -f $KUBECONFIG

    # check that 'run oc login ...' was successful
    [ $status -eq 0 ]
}
