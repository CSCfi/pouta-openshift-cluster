#!/usr/bin/env bash

if [ -z $ANSIBLE_INVENTORY ]; then
    source $HOME/.bashrc
fi

pushd /opt/deployment/poc/playbooks  > /dev/null

echo
echo "-------------------------------------------------------------------------------"
echo
echo " Running ../scripts/projects_lcm.py --mode MANUAL --action LIST-CLOSED-PROJECTS"
echo " for $ENV_NAME"
echo
echo "-------------------------------------------------------------------------------"
echo

python3 ../scripts/projects_lcm.py --mode MANUAL --action LIST-CLOSED-PROJECTS
result=$?


echo
echo "-------------------------------------------------------------------------------"
echo
echo " Running ../scripts/projects_lcm.py --mode AUTO"
echo " for $ENV_NAME"
echo
echo "-------------------------------------------------------------------------------"
echo

python3 ../scripts/projects_lcm.py --mode AUTO
result=$?

popd  > /dev/null
exit $result
