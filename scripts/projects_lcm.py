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
from openshift.dynamic.exceptions import NotFoundError

logging.basicConfig(stream=sys.stdout,
                    level=logging.INFO,
                    format='%(asctime)s %(levelname)s %(message)s')

PROJECT_GRACE_PERIOD = 90
PVS_GRACE_PERIOD = 30
REQUESTS_INTERVAL_INCREMENT = 5
REQUESTS_RETRIES_NUMBER = 5


def suspend_project(dyn_client, csc_project_id):
    """
    Suspend one CSC project in Rahti.
    @param dyn_client: DynamicClient object used to interact with OpenShift API.
    @param csc_project_id: the ID of CSC project to be suspended.
    @return: None.
    """
    v1_namespaces = dyn_client.resources.get(api_version='v1', kind='Namespace')
    v1_quotas = dyn_client.resources.get(api_version='v1', kind='ResourceQuota')
    v1_pods = dyn_client.resources.get(api_version='v1', kind='Pod')

    # Get namespaces associated with the CSC project to be suspended
    namespaces = v1_namespaces.get(label_selector='csc_project=' + csc_project_id)
    logging.info("Suspending %s namespaces for CSC project: %s" % (len(namespaces.items), csc_project_id))

    for ns in namespaces.items:
        # Suspend only the not suspended namespaces
        if 'suspended' not in dict(ns.metadata.labels) or ns.metadata.labels.suspended != 'true':

            # Retrieve the Pods quota of the namespace
            ns_quota = v1_quotas.get(name='compute-resources', namespace=ns.metadata.name)
            # Set namespace pods quota to zero
            # Save original pods quota (before suspension)
            # If Pod quota already set 0 and there is an already saved original pods quota
            if ('annotations' in dict(ns_quota.metadata)) and \
                    ('original_pods_quota' in dict(ns_quota.metadata.annotations)) and \
                    (ns_quota.spec.hard.pods == '0'):
                original_pods_quota = ns_quota.metadata.annotations.original_pods_quota
            else:  # set the original pods quota to the current hard pods quota
                original_pods_quota = ns_quota.spec.hard.pods

            # Save original pods quota as annotations, set pods quota to 0.
            quota_patch_body = {
                'metadata': {
                    'annotations': {
                        'original_pods_quota': original_pods_quota
                    },
                    'name': 'compute-resources'
                },
                'spec': {
                    'hard': {
                        'pods': '0'
                    }
                }
            }
            v1_quotas.patch(body=quota_patch_body, namespace=ns.metadata.name)

            # Delete all pods
            try:
                v1_pods.delete(field_selector='metadata.namespace=' + ns.metadata.name, namespace=ns.metadata.name)
            except TypeError:
                # This exception is raised when there are No pods to be deleted.
                pass

            # Mark namespace as suspended
            suspension_time = datetime.strftime(datetime.now(), '%d/%m/%y %H:%M:%S')
            # suspension_time = '10/07/22 13:38:21'
            ns_patch_body = {
                'metadata': {
                    'annotations': {
                        'suspension_time': suspension_time
                    },
                    'labels': {
                        'suspended': 'true'
                    }
                }
            }
            v1_namespaces.patch(body=ns_patch_body, name=ns.metadata.name)
            logging.info("     %s suspended" % ns.metadata.name)

        else:
            logging.info("     %s already suspended" % ns.metadata.name)


def unsuspend_project(dyn_client, csc_project_id):
    """
    Unsuspend a suspended CSC project in Rahti
    @param dyn_client: DynamicClient object used to interact with OpenShift API.
    @param csc_project_id: the ID of CSC project to be unsuspended.
    @return: None.
    """
    v1_namespaces = dyn_client.resources.get(api_version='v1', kind='Namespace')
    v1_quotas = dyn_client.resources.get(api_version='v1', kind='ResourceQuota')

    # Get the namespaces associated with the CSC project to be unsuspended
    namespaces = v1_namespaces.get(label_selector='csc_project=' + csc_project_id)
    logging.info("Unsuspending namespaces for CSC project: %s" % csc_project_id)
    for ns in namespaces.items:
        # Unsuspend only the namespaces already suspended
        if 'suspended' in dict(ns.metadata.labels) and ns.metadata.labels.suspended == 'true':
            # Retrieve the Pods quota of the namespace
            ns_quota = v1_quotas.get(name='compute-resources', namespace=ns.metadata.name)
            # Get the original pods quota of the namespace
            original_pods_quota = ns_quota.metadata.annotations.original_pods_quota
            # Set the pods quota to its original value
            quota_patch_body = {
                'metadata': {
                    'name': 'compute-resources'
                },
                'spec': {
                    'hard': {
                        'pods': original_pods_quota
                    }
                }
            }

            v1_quotas.patch(body=quota_patch_body, namespace=ns.metadata.name)

            # Mark a namespace as unsuspended
            ns_patch_body = {
                'metadata': {
                    'annotations': {
                        'suspension_time': ''
                    },
                    'labels': {
                        'suspended': 'false'
                    }
                }
            }

            v1_namespaces.patch(body=ns_patch_body, name=ns.metadata.name)
            logging.info("     Namespace %s unsuspended" % ns.metadata.name)
        else:
            logging.info("     Namespace %s already unsuspended" % ns.metadata.name)


def delete_project(dyn_client, csc_project_id):
    """
    Delete a suspended CSC project from Rahti.
    @param dyn_client: DynamicClient object used to interact with OpenShift API.
    @param csc_project_id: the ID of CSC project to be deleted.
    @return: 0 if deletion is successful, 1 otherwise.
    """
    v1_namespaces = dyn_client.resources.get(api_version='v1', kind='Namespace')
    v1_projects = dyn_client.resources.get(api_version='project.openshift.io/v1', kind='Project')
    v1_pvcs = dyn_client.resources.get(api_version='v1', kind='PersistentVolumeClaim')
    v1_pvs = dyn_client.resources.get(api_version='v1', kind='PersistentVolume')

    # Get namespaces associated with the CSC project to be deleted
    namespaces = v1_namespaces.get(label_selector='csc_project=' + csc_project_id)
    all_ns_deleted = True
    logging.info("Deleting %s namespaces for CSC project: %s" % (len(namespaces.items), csc_project_id))

    for ns in namespaces.items:
        # Delete only the suspended namespaces
        if 'suspended' in dict(ns.metadata.labels) and ns.metadata.labels.suspended == 'true' and \
                'suspension_time' in dict(ns.metadata.annotations):

            # Compute the elapsed time since the namespace was suspended
            suspension_time = datetime.strptime(ns.metadata.annotations.suspension_time, '%d/%m/%y %H:%M:%S')
            deletion_time = datetime.now()
            elapsed_time = deletion_time - suspension_time

            # Delete only the namespaces suspended for a period greater than PROJECT_GRACE_PERIOD days.
            if elapsed_time.days > PROJECT_GRACE_PERIOD:
                # Get the list of PVCs in the namespace
                pvcs = v1_pvcs.get(namespace=ns.metadata.name)
                all_pvs_patched = True
                # Change PVs reclaim policy to 'Retain' (to be able to delete the namespace
                # and its PVCs without deleting the PVs)
                for pvc in pvcs.items:
                    if pvc.status.phase == 'Bound':
                        # Patch the PV of the bound to the PVC:
                        #  - Change the reclaim policy to 'Retain'
                        #  - Add metadata labels to track the PV.
                        #  - Add a release timestamp.
                        release_time = datetime.strftime(datetime.now(), '%d/%m/%y %H:%M:%S')
                        # release_time = '10/07/22 13:38:21'

                        pv_patch_body = {
                            'metadata': {
                                'name': pvc.spec.volumeName,

                                'annotations': {
                                    'release_time': release_time
                                },
                                'labels': {
                                    'stale_pv': 'true',
                                    'csc_project': csc_project_id,
                                    'rahti_project': ns.metadata.name,
                                    'pvc_name': pvc.metadata.name
                                }
                            },
                            'spec': {
                                'persistentVolumeReclaimPolicy': 'Retain'
                            }
                        }
                        try:
                            v1_pvs.patch(body=pv_patch_body)
                        except Exception:
                            logging.error("Unable to change persistentVolumeReclaimPolicy of PV %s" %
                                          pvc.spec.volumeName)
                            all_pvs_patched = False

                # Delete the namespace only if all its associated PVs were patched
                if all_pvs_patched:
                    try:
                        # Delete the namespace/project.
                        v1_projects.delete(name=ns.metadata.name)
                        logging.info("     Rahti project %s deleted, suspended since %s days" %
                              (ns.metadata.name, elapsed_time.days))
                    except Exception:
                        logging.error("     Unable to delete Rahti project %s" % ns.metadata.name)
                        all_ns_deleted = False
                else:
                    logging.error("     Skipping Rahti project %s deletion because not all PVs were patched, " %
                                  ns.metadata.name)
                    all_ns_deleted = False
            else:
                logging.info("      Skipping Rahti project %s deletion because it is in grace period, %s days remaining"
                             " , " % (ns.metadata.name, (PROJECT_GRACE_PERIOD-elapsed_time.days)))
                all_ns_deleted = False
        else:
            logging.error("     Rahti project %s associated with CSC project %s is not suspended, please suspend before"
                          " deletion " % (ns.metadata.name, csc_project_id))
            all_ns_deleted = False

    # Return an error code if not all the namespaces were deleted.
    if all_ns_deleted:
        return 0
    else:
        return 1


def clean_pvs(dyn_client):
    """
    Delete all stale persistent volumes in Rahti.
    @param dyn_client: DynamicClient object used to interact with OpenShift API.
    """
    v1_projects = dyn_client.resources.get(api_version='project.openshift.io/v1', kind='Project')
    v1_pvs = dyn_client.resources.get(api_version='v1', kind='PersistentVolume')

    # Get the list of all stale PVs.
    pvs = v1_pvs.get(label_selector='stale_pv=true')

    for pv in pvs.items:
        # Make sure that the associated Rahti namespace was deleted
        try:
            pv_rahti_project_name = pv.metadata.labels.rahti_project
            v1_projects.get(name=pv_rahti_project_name)
            logging.error("     The project associated with  stale PV %s still exists, not deleting PV" % pv.metadata.name)
        # The associated Rahti project was effectively deleted.
        except NotFoundError:
            # Compute the elapsed time since the PV was released.
            release_time = datetime.strptime(pv.metadata.annotations.release_time, '%d/%m/%y %H:%M:%S')
            deletion_time = datetime.now()
            elapsed_time = deletion_time - release_time
            # Delete the PV only if it was released since at least PVS_GRACE_PERIOD days.
            if elapsed_time.days > PVS_GRACE_PERIOD:
                # TO-DO: check PV is not stuck in Terminating state.
                v1_pvs.delete(name=pv.metadata.name)
                logging.info("     Stale PV %s deleted" % pv.metadata.name)
            else:
                logging.info("     Stale PV %s not deleted, %s days remaining" %
                      (pv.metadata.name, (PVS_GRACE_PERIOD-elapsed_time.days)))


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
            logging.error("Not able to report data deletion for project %s, trying again in %s s" % project_id, sleep_time)
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


def get_project_namespaces(dyn_client, csc_project_id):
    """
    Return the list of namespaces associated with a given CSC project.
    @param dyn_client: DynamicClient object used to interact with OpenShift API.
    @param csc_project_id: the ID of CSC project.
    @return: a list of namespaces.
    """

    v1_namespaces = dyn_client.resources.get(api_version='v1', kind='Namespace')
    # Get namespaces associated with the CSC project
    namespaces = v1_namespaces.get(label_selector='csc_project=' + csc_project_id)
    to_return = []
    for ns in namespaces.items:
        to_return.append(ns.metadata.name)
    return to_return


def list_closed_projects(dyn_client):
    """
    Print the list of namespaces to be suspended or to be deleted.
    @param dyn_client: DynamicClient object used to interact with OpenShift API.
    @return: None.
    """

    print(SERVICE_URL)
    # Collect the list of namespaces to be suspended
    grace_namespaces = {}
    grace_namespaces_count = 0
    grace_projects = get_projects_by_state(SERVICE_URL, 'grace', open=False)
    for csc_project_id in grace_projects:
        namespaces = get_project_namespaces(dyn_client, csc_project_id)
        grace_namespaces[csc_project_id] = namespaces
        grace_namespaces_count += len(namespaces)

    # Collect the list of namespaces to be deleted
    delete_data_namespaces = {}
    delete_data_namespaces_count = 0
    delete_data_projects = get_projects_by_state(SERVICE_URL, 'deletedata')
    for csc_project_id in delete_data_projects:
        namespaces = get_project_namespaces(dyn_client, csc_project_id)
        delete_data_namespaces[csc_project_id] = namespaces
        delete_data_namespaces_count += len(namespaces)

    total_ns = grace_namespaces_count + delete_data_namespaces_count
    total_csc_projects = len(grace_projects) + len(delete_data_projects)

    # Print collected information
    print("Summary: %s CSC projects in grace state, %s CSC projects in delete data state, a total of %s"
          % (len(grace_projects), len(delete_data_projects), total_csc_projects))

    print("Summary: %s Namespaces in grace state, %s Namespaces in delete data state, a total of %s"
          % (grace_namespaces_count, delete_data_namespaces_count, total_ns))

    print("Namespaces in grace state")
    for csc_project_id in grace_namespaces:
        print("  CSC project: %s" % csc_project_id)
        for namespace in grace_namespaces[csc_project_id]:
            print("      Namespace: %s" % namespace)

    print("Namespaces in delete data state")
    for csc_project_id in delete_data_namespaces:
        print("  CSC project: %s" % csc_project_id)
        for namespace in delete_data_namespaces[csc_project_id]:
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
        k8s_client = config.new_client_from_config()
        rahti_dyn_client = DynamicClient(k8s_client)
    except:
        logging.error("Not able to instantiate openshift client")
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
                clean_pvs(rahti_dyn_client)
            elif args.action == 'LIST-CLOSED-PROJECTS':
                list_closed_projects(rahti_dyn_client)
            else:
                if args.csc_project is not None:
                    if args.action == 'SUSPEND':
                        suspend_project(rahti_dyn_client, args.csc_project)
                    elif args.action == 'UNSUSPEND':
                        unsuspend_project(rahti_dyn_client, args.csc_project)
                    elif args.action == 'DELETE':
                        ret = delete_project(rahti_dyn_client, args.csc_project)
                        if ret == 0:
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
            suspend_project(rahti_dyn_client, csc_project)

        # Unsuspend temporarily reopened projects if any
        # These projects have 'grace' substate and 'open' state
        logging.info("Unsuspending temporarily reopened projects")
        to_be_unsuspended_projects = get_projects_by_state(SERVICE_URL, sub_state='grace', open=True)
        for csc_project in to_be_unsuspended_projects:
            unsuspend_project(rahti_dyn_client, csc_project)

        # Unsuspend permanently reopened projects if any
        # These projects have 'none' substate and 'open' state
        logging.info("Unsuspending permanently reopened projects")
        to_be_unsuspended_projects = get_projects_by_state(SERVICE_URL, sub_state='none', open=True)
        for csc_project in to_be_unsuspended_projects:
            unsuspend_project(rahti_dyn_client, csc_project)

        # Delete projects with 'deletedata' substate
        logging.info("Delete permanently closed projects")
        to_be_deleted_projects = get_projects_by_state(SERVICE_URL, sub_state='deletedata')
        for csc_project in to_be_deleted_projects:
            ret = delete_project(rahti_dyn_client, csc_project)
            if ret == 0:
                report_project_deletion(csc_project, SERVICE_URL, SERVICE_TOKEN, dry_run=False)

    else:
        print("Wrong usage, please check usage instructions")
        parser.print_help()
