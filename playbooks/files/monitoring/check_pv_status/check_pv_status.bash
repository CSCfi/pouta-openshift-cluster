#!/usr/bin/env bash
#
# A wrapper Bash script to handle Python virtualenv and oc login for the
# check_pv_status.py Python script.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# create a temporary KUBECONFIG to avoid polluting the global environment
export KUBECONFIG=$(mktemp)

if [[ ! -d $HOME/check_pv_status ]]; then
  python3 -m venv $HOME/check_pv_status &> /dev/null
  source $HOME/check_pv_status/bin/activate
  pip3 install -r $SCRIPT_DIR/requirements.txt &> /dev/null
else
  source $HOME/check_pv_status/bin/activate
fi

if [[ ! -f /dev/shm/secret/testuser_credentials ]]; then
  echo "Cannot find test user credentials in /dev/shm/secret/testuser_credentials"
  exit 1
fi

IFS='|' read -r api_url username password < /dev/shm/secret/testuser_credentials
oc login $api_url --username $username --password $password &> /dev/null
python3 $SCRIPT_DIR/check_pv_status.py $@
ret=$?

#source $HOME/check_pv_status/bin/deactivate
deactivate
rm -f $KUBECONFIG

exit $ret

