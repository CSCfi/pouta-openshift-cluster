#!/usr/bin/python3

# This script implements the data deletion process as described in :
# https://wiki.eduuni.fi/pages/viewpage.action?spaceKey=CscABCD&title=Data+Deletion+Process+Integration+Instructions+for+Services
import time

import requests
import logging
import sys
import os
import argparse
from datetime import datetime
from kubernetes import client, config
from openshift.dynamic import DynamicClient
from rahtiClient import RahtiClient

from openshift.dynamic.exceptions import NotFoundError

logging.basicConfig(stream=sys.stdout,
                    level=logging.INFO,
                    format='%(asctime)s %(levelname)s %(message)s')

PROJECT_GRACE_PERIOD = 90
PVS_GRACE_PERIOD = 30
REQUESTS_INTERVAL_INCREMENT = 5
REQUESTS_RETRIES_NUMBER = 5

def get_projects_by_state(service_url, sub_state, open=None):
    """
    Retrieve the list of projects in the data deletion process with specific state.
    @param service_url: the URL of the data deletion microservice used to retrieve the list of projects.
    @param sub_state: the CSCPrjSubState of projects to be retrieved, can be 'grace', 'deletedata', or 'none'.
    @param open: set to true to filter projects with CSCPrjState set to 'open'.
    @return: list of csc projects numbers.
    """

    if open is None:
        url = service_url + '/projects?services=RAHTI&states='+sub_state
    elif open:
        url = service_url + '/projects?services=RAHTI&states=' + sub_state+'&open=true'
    else:
        url = service_url + '/projects?services=RAHTI&states=' + sub_state+'&open=false'

    to_return = []

    try:
        response = requests.get(url)
        if response.status_code == 200:
            for project in response.json():
                to_return.append(project['number'])
            return to_return
        else:
            return None
    except Exception as e:
        logging.error(e)
        return None


def report_project_deletion(project_id, service_url, service_token, dry_run=True):
    """
    Report data deletion for one CSC project.
    @param project_id: the ID of CSC project for which the data was deleted.
    @param service_url: the URL of the data deletion microservice used to report the data deletion.
    @param service_token: the secret token used to report the data deletion.
    @param dry_run: whether the request will trigger IDM workflow or not.
    @return: ID of the started workflow.
    """

    if dry_run:
        url = service_url + '/report?service=RAHTI&project=' + project_id + '&action=datadeleted&token='+service_token\
              + '&dryrun=true'
    else:
        url = service_url + '/report?service=RAHTI&project=' + project_id + '&action=datadeleted&token=' + service_token
    try:
        retry_count = 1
        sleep_time = 0
        response = requests.post(url)
        while response.status_code != 200 and retry_count < REQUESTS_RETRIES_NUMBER:
            sleep_time += REQUESTS_INTERVAL_INCREMENT
            logging.error("Not able to report data deletion for project %s, trying again in %s s" % (project_id, sleep_time))
            time.sleep(sleep_time)
            response = requests.post(url)
            retry_count += 1

        if response.status_code == 200:
            workflow_id = response.json()['workflow']
            logging.info("Data deletion for project %s reported successfully, triggered workflow ID is %s" % (project_id, workflow_id))
            return workflow_id
        else:
            logging.error("Failed to report data deletion for project %s, not trying again" % project_id)
            return None
    except Exception as e:
        logging.error(e)
        return None


def list_closed_projects(old_rahti_client, new_rahti_client):
    """
    Print the list of namespaces to be suspended or to be deleted.
    @param dyn_client: DynamicClient object used to interact with OpenShift API.
    @return: None.
    """

    print("Contacting the data retention service at %s" % SERVICE_URL)
    # Collect the list of namespaces to be suspended
    old_rahti_grace_namespaces = {}
    new_rahti_grace_namespaces = {}
    grace_namespaces_count = 0
    grace_projects = get_projects_by_state(SERVICE_URL, 'grace', open=False)
    for csc_project_id in grace_projects:
        old_rahti_namespaces = old_rahti_client.get_project_namespaces(csc_project_id)
        new_rahti_namespaces = new_rahti_client.get_project_namespaces(csc_project_id)
        old_rahti_grace_namespaces[csc_project_id] = old_rahti_namespaces
        new_rahti_grace_namespaces[csc_project_id] = new_rahti_namespaces

        grace_namespaces_count += len(old_rahti_namespaces) + len(new_rahti_namespaces)

    # Collect the list of namespaces to be deleted
    old_rahti_delete_data_namespaces = {}
    new_rahti_delete_data_namespaces = {}
    delete_data_namespaces_count = 0
    delete_data_projects = get_projects_by_state(SERVICE_URL, 'deletedata')
    for csc_project_id in delete_data_projects:
        old_rahti_namespaces = old_rahti_client.get_project_namespaces(csc_project_id)
        new_rahti_namespaces = new_rahti_client.get_project_namespaces(csc_project_id)

        old_rahti_delete_data_namespaces[csc_project_id] = old_rahti_namespaces
        new_rahti_delete_data_namespaces[csc_project_id] = new_rahti_namespaces
        delete_data_namespaces_count += len(old_rahti_namespaces) + len(new_rahti_namespaces)

    total_ns = grace_namespaces_count + delete_data_namespaces_count
    total_csc_projects = len(grace_projects) + len(delete_data_projects)

    # Print collected information
    print("Summary: %s CSC projects in grace state, %s CSC projects in delete data state, a total of %s"
          % (len(grace_projects), len(delete_data_projects), total_csc_projects))

    print("Summary: %s Namespaces in grace state, %s Namespaces in delete data state, a total of %s"
          % (grace_namespaces_count, delete_data_namespaces_count, total_ns))

    print("Namespaces in grace state in old Rahti")
    for csc_project_id in old_rahti_grace_namespaces:
        print("  CSC project: %s" % csc_project_id)
        for namespace in old_rahti_grace_namespaces[csc_project_id]:
            print("      Namespace: %s" % namespace)

    print("Namespaces in grace state in new Rahti")
    for csc_project_id in new_rahti_grace_namespaces:
        print("  CSC project: %s" % csc_project_id)
        for namespace in new_rahti_grace_namespaces[csc_project_id]:
            print("      Namespace: %s" % namespace)

    print("Namespaces in delete data state in old rahti")
    for csc_project_id in old_rahti_delete_data_namespaces:
        print("  CSC project: %s" % csc_project_id)
        for namespace in old_rahti_delete_data_namespaces[csc_project_id]:
            print("      Namespace: %s" % namespace)

    print("Namespaces in delete data state in new rahti")
    for csc_project_id in new_rahti_delete_data_namespaces:
        print("  CSC project: %s" % csc_project_id)
        for namespace in new_rahti_delete_data_namespaces[csc_project_id]:
            print("      Namespace: %s" % namespace)


if __name__ == "__main__":

    parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter)

    # Adding optional argument

    parser.add_argument('--mode', dest='mode', default='MANUAL',
                        help='How you want to run the LCM script, can be: '
                             '\n  - MANUAL (default): the script will use the --action and --csc-project arguments'
                             ' to perform an LCM operation (SUSPEND, UNSUSPEND, or DELETE) on one CSC project.'
                             '\n  - AUTO: the script will use IDA Microservice to retrieve the list of CSC projects to '
                             'be suspended and deleted.'
                        )

    parser.add_argument('--action', dest='action',
                        help='Action you want the LCM script to perform, can be: '
                             '\n  - SUSPEND: to suspend CSC projects in grace period.'
                             '\n  - UNSUSPEND: to unsuspend a reopened CSC projects.'
                             '\n  - DELETE: to delete and report data deletion for CSC projects in data deletion phase.'
                             '\n  - CLEAN-PVS: to delete stale PVs.'
                             '\n  - LIST-CLOSED-PROJECTS: to list closed projects (grace and deletedata) .'
                        )

    parser.add_argument('--csc-project', dest='csc_project',
                        help='The number of CSC project to be suspended, unsuspended, or deleted depending on the '
                             '--action parameter.')

    parser.add_argument('--test', dest='test', default='false',
                        help='used to specify whether to use the test Microservice or not, can be:'
                             '\n  - true: to use the test microservice.'
                             '\n  - false: to use the production microservice.'
                        )

    args = parser.parse_args()

    try:
        # Create old Rahti client
        kubeconfig_path = "~/.kube/rahti_3_kubeconfig.yml"
        old_rahti_client = RahtiClient('rahti-3', PROJECT_GRACE_PERIOD, PVS_GRACE_PERIOD, kubeconfig_path=kubeconfig_path)
        # Create new Rahti client
        auth_parameters = {
            "host": os.environ['NEW_CLUSTER_VERSION_URL'],
            "token": os.environ['NEW_CLUSTER_VERSION_TOKEN']
        }
        new_rahti_client = RahtiClient('rahti-4', PROJECT_GRACE_PERIOD, PVS_GRACE_PERIOD, auth_parameters=auth_parameters)
    except Exception as e:
        logging.error("Not able to instantiate openshift client hahaha")
        print(e)
        exit(1)

    if args.test == 'false':
        # Use the production data deletion microservice
        SERVICE_TOKEN = os.environ['PRODUCTION_MICROSERVICE_TOKEN']
        SERVICE_URL = os.environ['PRODUCTION_MICROSERVICE_URL']

    elif args.test == 'true':
        # Use the test data deletion microservice
        SERVICE_TOKEN = os.environ['TEST_MICROSERVICE_TOKEN']
        SERVICE_URL = os.environ['TEST_MICROSERVICE_URL']
    else:
        print("Wrong usage, please check usage instructions")
        parser.print_help()

    if args.mode == 'MANUAL':
        if args.action is not None:
            if args.action == 'CLEAN-PVS':
                old_rahti_client.clean_pvs()
                new_rahti_client.clean_pvs()
            elif args.action == 'LIST-CLOSED-PROJECTS':
                list_closed_projects(old_rahti_client, new_rahti_client)
            else:
                if args.csc_project is not None:
                    if args.action == 'SUSPEND':
                        old_rahti_client.suspend_project(args.csc_project)
                        new_rahti_client.suspend_project(args.csc_project)
                    elif args.action == 'UNSUSPEND':
                        old_rahti_client.unsuspend_project(args.csc_project)
                        new_rahti_client.unsuspend_project(args.csc_project)
                    elif args.action == 'DELETE':
                        ret_old_rahti = old_rahti_client.delete_project(args.csc_project)
                        ret_new_rahti = new_rahti_client.delete_project(args.csc_project)
                        if ret_old_rahti == 0 and ret_new_rahti == 0:
                            report_project_deletion(args.csc_project, SERVICE_URL, SERVICE_TOKEN, dry_run=False)
                    else:
                        print("Wrong usage, please check usage instructions")
                        parser.print_help()
                else:
                    print("Wrong usage, please check usage instructions")
                    parser.print_help()
        else:
            print("Wrong usage, please check usage instructions")
            parser.print_help()

    elif args.mode == 'AUTO':

        # Suspend projects with 'grace' substate and 'closed' state.
        logging.info("Suspending closed projects")
        to_be_suspended_projects = get_projects_by_state(SERVICE_URL, sub_state='grace', open=False)
        for csc_project in to_be_suspended_projects:
            old_rahti_client.suspend_project(csc_project)
            new_rahti_client.suspend_project(csc_project)

        # Unsuspend temporarily reopened projects if any
        # These projects have 'grace' substate and 'open' state
        logging.info("Unsuspending temporarily reopened projects")
        to_be_unsuspended_projects = get_projects_by_state(SERVICE_URL, sub_state='grace', open=True)
        for csc_project in to_be_unsuspended_projects:
            old_rahti_client.unsuspend_project(csc_project)
            new_rahti_client.unsuspend_project(csc_project)

        # Unsuspend permanently reopened projects if any
        # These projects have 'none' substate and 'open' state
        logging.info("Unsuspending permanently reopened projects")
        to_be_unsuspended_projects = get_projects_by_state(SERVICE_URL, sub_state='none', open=True)
        for csc_project in to_be_unsuspended_projects:
            old_rahti_client.unsuspend_project(csc_project)
            new_rahti_client.unsuspend_project(csc_project)

        # Delete projects with 'deletedata' substate
        logging.info("Delete permanently closed projects")
        to_be_deleted_projects = get_projects_by_state(SERVICE_URL, sub_state='deletedata')
        for csc_project in to_be_deleted_projects:
            ret_old_rahti = old_rahti_client.delete_project(csc_project)
            ret_new_rahti = new_rahti_client.delete_project(csc_project)
            if ret_old_rahti == 0 and ret_new_rahti == 0:
                report_project_deletion(csc_project, SERVICE_URL, SERVICE_TOKEN, dry_run=False)

    else:
        print("Wrong usage, please check usage instructions")
        parser.print_help()
