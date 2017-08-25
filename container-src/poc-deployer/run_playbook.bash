#!/usr/bin/env bash

if [ -z $ANSIBLE_INVENTORY ]; then
    source $HOME/.bashrc
fi

POC_BRANCH=$(cd /opt/deployment/poc && parse_git_branch)
OE_BRANCH=$(cd /opt/deployment/openshift-environments && parse_git_branch)
OA_BRANCH=$(cd /opt/deployment/openshift-ansible && parse_git_branch)

pushd /opt/deployment/poc/playbooks

echo
echo "-------------------------------------------------------------------------------"
echo
echo " Running $* for $ENV_NAME"
echo
echo " POC branch: $POC_BRANCH"
echo "  OE branch: $OE_BRANCH"
echo "  OA branch: $OA_BRANCH"
echo
echo "-------------------------------------------------------------------------------"
echo

ansible-playbook $*
result=$?

popd
exit $result
