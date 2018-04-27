#!/usr/bin/env bash
#
# A wrapper Bash script to handle Python virtualenv and oc login for the
# check_oso_deploy.py Python script.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# create a temporary KUBECONFIG to avoid polluting the global environment
export KUBECONFIG=$(mktemp)

if [[ ! -d $HOME/check_oso_deploy ]]; then
  virtualenv $HOME/check_oso_deploy &> /dev/null
  source $HOME/check_oso_deploy/bin/activate
  pip install -r $SCRIPT_DIR/requirements.txt &> /dev/null
else
  source $HOME/check_oso_deploy/bin/activate
fi

IFS='|' read -r api_url username password < /dev/shm/secret/testuser_credentials
oc login $api_url --username $username --password $password &> /dev/null
python $SCRIPT_DIR/check_oso_deploy.py $@
ret=$?

deactivate
rm -f $KUBECONFIG

exit $ret
