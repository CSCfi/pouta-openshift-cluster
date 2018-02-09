#!/usr/bin/env bash

if [ -z $ANSIBLE_INVENTORY ]; then
    source $HOME/.bashrc
fi

pushd /opt/deployment/poc/playbooks  > /dev/null

# Select the appropriate backup playbook
if [[ $OPENSHIFT_RELEASE == "3.6" ]]; then
    backup_playbook=backup_36.yml
else
    backup_playbook=backup.yml
fi

echo
echo "-------------------------------------------------------------------------------"
echo
echo " Running $backup_playbook for $ENV_NAME"
echo
branch-info
echo
echo "-------------------------------------------------------------------------------"
echo


ansible-playbook $backup_playbook
result=$?

popd  > /dev/null
exit $result
