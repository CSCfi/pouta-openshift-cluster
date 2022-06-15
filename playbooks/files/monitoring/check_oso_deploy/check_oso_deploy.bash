#!/usr/bin/env bash
#
# A wrapper Bash script to handle Python virtualenv and oc login for the
# check_oso_deploy.py Python script.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# create a temporary KUBECONFIG to avoid polluting the global environment
export KUBECONFIG=$(mktemp)

if [[ ! -d $HOME/check_oso_deploy ]]; then
  python3 -m venv $HOME/check_oso_deploy &> /dev/null
  source $HOME/check_oso_deploy/bin/activate
  pip3 install -r $SCRIPT_DIR/requirements.txt &> /dev/null
else
  source $HOME/check_oso_deploy/bin/activate
fi

if [[ ! -f /dev/shm/secret/testuser_credentials ]]; then
  echo "Cannot find test user credentials in /dev/shm/secret/testuser_credentials"
  exit 1
fi

IFS='|' read -r api_url username password < /dev/shm/secret/testuser_credentials
oc login $api_url --username $username --password $password &> /dev/null

# Set temporary kubeconfig for python libraries
token=$(oc whoami -t)
oc config set-cluster rahti-target &> /dev/null
oc config set-cluster rahti-target --server $api_url &> /dev/null
oc config set-credentials $username --token $token &> /dev/null
oc config set-context rahti-target --cluster rahti-target --user $username &> /dev/null
oc config use-context rahti-target &> /dev/null

python3 $SCRIPT_DIR/check_oso_deploy.py $@
ret=$?

deactivate
rm -f $KUBECONFIG

exit $ret
