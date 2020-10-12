import argparse
import datetime
import time
import requests
import sys
import random

from kubernetes import client, config
from openshift.dynamic import DynamicClient

k8s_client = config.new_client_from_config()
dyn_client = DynamicClient(k8s_client)

# Nagios states
NAGIOS_STATE_OK = 0
NAGIOS_STATE_WARNING = 1
NAGIOS_STATE_CRITICAL = 2
NAGIOS_STATE_UNKNOWN = 3

pv_total_list = []
pvc_total_list = []
pv_failed_list = []
pvc_failed_list = []

class OsoCheckException(Exception):
    msg = 'An unknown exception occured.'

    def __init__(self, **kwargs):
        self.message = self.msg % kwargs

    def __str__(self):
        return self.message

class PollTimeoutException(OsoCheckException):
    msg = 'Timeout while polling the created service.'

# this function will return all the failed persistent volume claims
def get_pvc_states():
    pvcs = dyn_client.resources.get(api_version='v1', kind='PersistentVolumeClaim')
    pvcs_list = pvcs.get()

    for pvc in pvcs_list.items:
        pvc_total_list.append(pvc.metadata.uid)
        if pvc.status.phase == "Failed":
            pvc_failed_list.append(pvc.metadata.uid)

# this function will return all the failed persistent volumes
def get_pv_states():
    pvs = dyn_client.resources.get(api_version='v1', kind='PersistentVolume')
    pv_list = pvs.get()

    for pv in pv_list.items:
        pv_total_list.append(pv.metadata.uid)
        if pv.status.phase == "Failed":
            pv_failed_list.append(pv.metadata.uid)


def main():
    # global start_time
    # start_time = time.time()
    # print(start_time);
    # print("Get the pv states: ")

    try:
        # check pv states
        get_pv_states()

        # check pvc states
        get_pvc_states()
    except client.rest.ApiException as e:
        print(e)
        sys.exit(NAGIOS_STATE_CRITICAL)
    except PollTimeoutException as e:
        print(e)
        sys.exit(NAGIOS_STATE_CRITICAL)
    except requests.exceptions.ConnectionError as e:
        print(e)
        sys.exit(NAGIOS_STATE_CRITICAL)
    except:
        print('Unexpected error: ', sys.exc_info()[0])
        sys.exit(NAGIOS_STATE_CRITICAL)

    if pv_failed_list or pvc_failed_list:
        print("Failed PVs: %s Failed PVCs: %s | total_pv_count=%s, total_pvc_count=%s, failed_pv_count=%s, failed_pvc_count=%s"
            % (
                str(pv_failed_list), str(pvc_failed_list),
                str(len(pv_total_list)), str(len(pvc_total_list)),
                str(len(pv_failed_list)), str(len(pvc_failed_list))
            ))
        sys.exit(NAGIOS_STATE_CRITICAL)
    else:
        print("Ok | total_pv_count=%s, total_pvc_count=%s, failed_pv_count=%s, failed_pvc_count=%s"
            % (
                str(len(pv_total_list)), str(len(pvc_total_list)),
                str(len(pv_failed_list)), str(len(pvc_failed_list))
            ))
        sys.exit(NAGIOS_STATE_OK)

if __name__ == '__main__':
    main()