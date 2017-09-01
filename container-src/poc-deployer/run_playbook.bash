#!/usr/bin/env bash

if [ -z $ANSIBLE_INVENTORY ]; then
    source $HOME/.bashrc
fi

pushd /opt/deployment/poc/playbooks  > /dev/null

echo
echo "-------------------------------------------------------------------------------"
echo
echo " Running $* for $ENV_NAME"
echo
branch-info
echo
echo "-------------------------------------------------------------------------------"
echo

ansible-playbook $*
result=$?

popd  > /dev/null
exit $result
