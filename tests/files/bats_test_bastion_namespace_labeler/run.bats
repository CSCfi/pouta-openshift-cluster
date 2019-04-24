#!/usr/bin/env bats

oc_login() {

    # read api end point and credentials from a pre populated files
    IFS='|' read -r api_url username password < /dev/shm/secret/testuser_credentials

    # create a temporary KUBECONFIG to avoid polluting the global environment
    export KUBECONFIG=$(mktemp)

    # login using the test user
    oc login $api_url --username $username --password $password

}

oc_logout() {

    # remove the temporary KUBECONFIG
    rm -f $KUBECONFIG

}

create_project() {
    export project_name="labeled-namespace-$(date '+%Y%m%d%H%M%S')-$(openssl rand -hex 6)"

    # attempt to create the project
    run oc new-project $project_name --description="$1"

    if [ $status -eq 0 ]; then
      oc delete project $project_name
    fi
}

@test "test creating a namespace using the default CSC project" {

    oc_login
    create_project "This is just a normal description"
    oc_logout
    [ $status -eq 0 ]

}

@test "test creating a namespace using a set and correct CSC project" {

    oc_login
    create_project "csc_project: $CSC_PROJECT_CODE"
    oc_logout
    [ $status -eq 0 ]

}

@test "test creating a namespace using a wrong CSC project" {

    oc_login
    create_project "csc_project: 2000xxx"
    oc_logout
    [ $status -eq 1 ]

}
