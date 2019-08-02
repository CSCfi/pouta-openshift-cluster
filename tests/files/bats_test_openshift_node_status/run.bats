#!/usr/bin/env bats

@test "check the OpenShift node status" {
    status=0

    if [[ "$POC_DEPLOY_MONITORING" == "True" ]]
    then
      export NAGIOS_PLUGINS_DIR="/usr/lib64/nagios/plugins"
      run $NAGIOS_PLUGINS_DIR/check_nrpe -H localhost -c check_node_status
    fi

    [ "$status" -eq 0 ]
}
