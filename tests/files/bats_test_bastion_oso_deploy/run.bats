#!/usr/bin/env bats

skip_if_sc_is_inactive() {
  if [[ ",$ACTIVE_STORAGE_CLASSES," != *,$1,* ]]; then
    skip "Storage class $1 is not active"
  fi
}

@test "test minimal deployment on openshift" {
  run /usr/lib64/nagios/plugins/check_oso_deploy/check_oso_deploy.bash --timeout 100
  [ $status -eq 0 ]
}

# We want to test with no storage class specified to ensure that there is a
# working default storage class.
@test "test deployment with a pvc on openshift (default storage class)" {
  run /usr/lib64/nagios/plugins/check_oso_deploy/check_oso_deploy.bash --use_pvc --pvc_delay 10 --timeout 150
  [ $status -eq 0 ]
}

@test "test deployment with a pvc on openshift (standard-rwo storage class)" {
  skip_if_sc_is_inactive standard-rwo
  run /usr/lib64/nagios/plugins/check_oso_deploy/check_oso_deploy.bash --use_pvc --timeout 150 --storage_class standard-rwo
  [ $status -eq 0 ]
}

@test "test deployment with a pvc on openshift (glusterfs-storage storage class)" {
  skip_if_sc_is_inactive glusterfs-storage
  run /usr/lib64/nagios/plugins/check_oso_deploy/check_oso_deploy.bash --use_pvc --pvc_delay 10 --timeout 150 --storage_class glusterfs-storage
  [ $status -eq 0 ]
}
