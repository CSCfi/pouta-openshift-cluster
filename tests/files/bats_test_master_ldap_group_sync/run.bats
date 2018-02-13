#!/usr/bin/env bats

@test "test ldap group sync" {
    sudo /usr/local/bin/poc_sync_ldap_groups.bash | grep -q "openshift.io/ldap.sync-time"
}
