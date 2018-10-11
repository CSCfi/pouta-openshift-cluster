#!/usr/bin/env bash

# Script to synchronize groups from LDAP.
#
# Ref: https://docs.okd.io/latest/install_config/syncing_groups_with_ldap.html

set -e

export PATH="${PATH}:/usr/local/bin/"

config_file=${LDAP_GROUP_SYNC_CONFIG:-/etc/origin/master/ldap_group_sync.yaml}

if [[ -e $config_file ]]; then
    echo "synchronizing groups"
    oc adm groups sync --sync-config $config_file $*

    echo "pruning old groups"
    oc adm groups prune --sync-config $config_file $*
fi
