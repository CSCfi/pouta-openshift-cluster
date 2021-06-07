#!/usr/bin/env bash

if [ -z $ANSIBLE_INVENTORY ]; then
    source $HOME/.bashrc
fi

pushd /opt/deployment/poc/playbooks  > /dev/null

echo
echo "-------------------------------------------------------------------------------"
echo
echo " Running ops/restart_csi_cinder.yml"
echo " for $ENV_NAME"
echo
echo "-------------------------------------------------------------------------------"
echo

ansible-playbook ops/restart_csi_cinder.yml
result=$?

popd  > /dev/null
exit $result
