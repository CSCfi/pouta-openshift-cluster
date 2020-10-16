#!/usr/bin/env bash
#
# A wrapper Bash script to handle Python virtualenv and oc login for the
# check_oso_deploy.py Python script.

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


if [[ ! -d $HOME/check_cinder ]]; then
  virtualenv $HOME/check_cinder &> /dev/null
  source $HOME/check_cinder/bin/activate
  pip install -r $SCRIPT_DIR/requirements.txt &> /dev/null
else
  source $HOME/check_cinder/bin/activate
fi

if [[ ! -f /dev/shm/secret/openrc.sh  ]]; then
  echo "Cannot find openrc credentials in /dev/shm/secret/openrc.sh"
  exit 1
fi

source /dev/shm/secret/openrc.sh 

python $SCRIPT_DIR/check_cinder.py $@
ret=$?

deactivate

exit $ret
