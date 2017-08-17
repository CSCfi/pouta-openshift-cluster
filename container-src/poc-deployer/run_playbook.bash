#!/usr/bin/env bash

if [ -z $ANSIBLE_INVENTORY ]; then
    source $HOME/.bashrc
fi

pushd /opt/deployment/poc/playbooks/openshift

echo
echo '-------------------------------------------------------------------------------'
echo
echo " Running $* for $ENV_NAME"
echo
echo '-------------------------------------------------------------------------------'
echo

ansible-playbook $*

popd
