#!/usr/bin/env bats

@test "test minimal deployment on openshift" {

  # test deployment
  run /usr/lib64/nagios/plugins/check_oso_deploy/check_oso_deploy.bash --timeout 60

  # check that the deployment was successful
  [ $status -eq 0 ]
}

@test "test deployment with a pvc on openshift" {

  # test deployment with pvc
  run /usr/lib64/nagios/plugins/check_oso_deploy/check_oso_deploy.bash --use_pvc --pvc_delay 10 --timeout 90

  # check that the deployment was successful
  [ $status -eq 0 ]
}
