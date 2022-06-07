#!/usr/bin/env python
#
# Create a deployment in an OpenShift cluster and check to see if it
# succeeded.

from __future__ import print_function

import argparse
import datetime
import time
import requests
import sys
import random

from kubernetes import client, config
from openshift.dynamic import DynamicClient

NAGIOS_STATE_OK = 0
NAGIOS_STATE_WARNING = 1
NAGIOS_STATE_CRITICAL = 2
NAGIOS_STATE_UNKNOWN = 3

CHECK_TEXT = 'Now witness the power of this fully armed and operational battle station.'

# Quay.io had some trouble, switched to docker hub
#IMAGE = 'quay.io/bitnami/nginx:1.19'
IMAGE = 'docker.io/bitnami/nginx:1.19'
HTML_DIR_ON_IMAGE = '/opt/bitnami/nginx/html'


class OsoCheckException(Exception):
    msg = 'An unknown exception occured.'

    def __init__(self, **kwargs):
        self.message = self.msg % kwargs

    def __str__(self):
        return self.message


class PollTimeoutException(OsoCheckException):
    msg = 'Timeout while polling the created service.'


def create_nginx(dyn_client, namespace='nrpe-check', use_pvc=False, pvc_delay=5, storage_class=None):
    """
    Create a minimal deployment of nginx. Optionally attach a persistent volume
    and write some data to it.
    """
    project_data = {
        'apiVersion': 'project.openshift.io/v1',
        'kind': 'ProjectRequest',
        'metadata': {
            'name': namespace
        }
    }

    route_data = {
        'apiVersion': 'v1',
        'kind': 'Route',
        'metadata': {
            'name': 'nginx-route'
        },
        'spec': {
            'to': {
                'kind': 'Service',
                'name': 'nginx-service'
            }
        }
    }

    service_data = {
        'kind': 'Service',
        'apiVersion': 'v1',
        'metadata': {
            'name': 'nginx-service'
        },
        'spec': {
            'selector': {
                'app': 'nrpe-check-deployment'
            },
            'ports': [
                {
                    'protocol': 'TCP',
                    'port': '8080',
                    'targetPort': 'nginx-port'
                }
            ]
        }
    }

    # Explicitly set resource limits=requests for guaranteed QoS
    deploymentconfig_data = {
        'kind': 'DeploymentConfig',
        'apiVersion': 'apps.openshift.io/v1',
        'metadata': {
            'name': 'nrpe-check-deployment'
        },
        'spec': {
            'replicas': 1,
            'strategy': {
                'type': 'Recreate',
                'resources': {
                    'limits': {
                        'cpu': '200m'
                    },
                    'requests': {
                        'cpu': '200m'
                    }
                }
            },
            'template': {
                'spec': {
                    'containers': [
                        {
                            'image': IMAGE,
                            'name': 'nginx',
                            'ports': [
                                {
                                    'name': 'nginx-port',
                                    'containerPort': 8080
                                }
                            ]
                        }
                    ]
                },
                'metadata': {
                    'labels': {
                        'app': 'nrpe-check-deployment'
                    }
                }
            }
        }
    }

    v1_projectrequests = dyn_client.resources.get(api_version='project.openshift.io/v1', kind='ProjectRequest')
    v1_projectrequests.create(body=project_data)

    if use_pvc:
        pvc_data = {
            'kind': 'PersistentVolumeClaim',
            'spec': {
                'accessModes': [
                    'ReadWriteOnce'
                ],
                'resources': {
                    'requests': {
                        'storage': '50Mi'
                    }
                }
            },
            'apiVersion': 'v1',
            'metadata': {
                'name': 'nginx-volume'
            }
        }

        if storage_class != None:
            pvc_data['spec']['storageClassName'] = storage_class

        v1_pvc = dyn_client.resources.get(api_version='v1', kind='PersistentVolumeClaim')
        v1_pvc.create(body=pvc_data, namespace=namespace)

        time.sleep(pvc_delay)

        init_container_data = [
            {
                'name': 'init-web-content',
                'image': IMAGE,
                'volumeMounts': [
                    {
                        'mountPath': '/mnt',
                        'name': 'nginx-volume'
                    }
                ],
                'command': ['sh', '-c', 'echo "' + CHECK_TEXT + '" > /mnt/index.html']
            }
        ]

        container_volumemount_data = [
            {
                'mountPath': HTML_DIR_ON_IMAGE,
                'name': 'nginx-volume'
            }
        ]

        volume_data = [
            {
                'name': 'nginx-volume',
                'persistentVolumeClaim': {
                    'claimName': 'nginx-volume'
                }
            }
        ]

        deploymentconfig_data['spec']['template']['spec']['initContainers'] = init_container_data
        deploymentconfig_data['spec']['template']['spec']['containers'][0]['volumeMounts'] = container_volumemount_data
        deploymentconfig_data['spec']['template']['spec']['volumes'] = volume_data

    v1_deploymentconfig = dyn_client.resources.get(api_version='apps.openshift.io/v1', kind='DeploymentConfig')
    v1_deploymentconfig.create(body=deploymentconfig_data, namespace=namespace)

    v1_service = dyn_client.resources.get(api_version='v1', kind='Service')
    v1_service.create(body=service_data, namespace=namespace)

    v1_route = dyn_client.resources.get(api_version='v1', kind='Route')
    route_resp = v1_route.create(body=route_data, namespace=namespace)

    return "http://" + route_resp.spec.host


def poll_nginx(route_url, string_to_grep, timeout=150):
    """
    Poll the create nginx service until the expected string is returned or
    a timeout is reached. If a timeout is reached, raise a PollTimeoutException.
    """
    poll_start_time = time.time()
    time_now = poll_start_time
    end_by = poll_start_time + timeout

    while time_now < end_by:
        req = requests.get(route_url)
        if string_to_grep in req.text:
            return

        time.sleep(1)
        time_now = time.time()

    raise PollTimeoutException()


def cleanup(dyn_client, namespace):
    try:
        v1_project = dyn_client.resources.get(api_version='project.openshift.io/v1', kind='Project')
        project_to_delete = list(filter(lambda x: x.metadata.name == namespace, v1_project.get().items))
        if len(project_to_delete) == 1:
            v1_project.delete(name=namespace)
    except Exception as e:
        print(e)
        exit_with_stats(NAGIOS_STATE_CRITICAL)


def exit_with_stats(exit_code=NAGIOS_STATE_OK, stats=None):
    """
    Exits with the specified exit_code and outputs any stats in the format
    nagios/opsview expects.
    """
    end_time = time.time() - start_time
    timing_info = {'seconds_used': int(end_time)}

    if stats:
        stats.update(timing_info)
    else:
        stats = timing_info

    if exit_code == NAGIOS_STATE_OK:
        output = 'OK |'
    elif exit_code == NAGIOS_STATE_WARNING:
        output = 'WARNING |'
    else:
        output = 'CRITICAL |'

    for key in stats:
        output += ' ' + key + '=' + str(stats[key])
    print(output)

    sys.exit(exit_code)


def main():
    global start_time
    start_time = time.time()

    parser = argparse.ArgumentParser(description='Nagios check for OpenShift deployments.')
    parser.add_argument('--use_pvc',
                        help='Include adding a PersistentVolumeClaim in the test.',
                        action='store_true',
                        dest='use_pvc',
                        default=False)
    parser.add_argument('--pvc_delay',
                        help='Time in seconds to wait after PVC has been created.',
                        dest='pvc_delay',
                        default=5)
    parser.add_argument('--timeout',
                        help='How long to wait for the test to finish.',
                        dest='timeout',
                        default=300)
    parser.add_argument('--storage_class',
                        help='What storage class to use if a PVC is created.',
                        dest='storage_class',
                        default=None)

    args = parser.parse_args()

    if args.use_pvc:
        string_to_grep = CHECK_TEXT
    else:
        string_to_grep = "Welcome to nginx!"

    timeout = int(args.timeout)
    pvc_delay = int(args.pvc_delay)

    try:
        # read config from kubeconfig that is set up in bash wrapper
        k8s_client = config.new_client_from_config()
        dyn_client = DynamicClient(k8s_client)

        rnd = random.randint(0, 999)
        namespace = 'nrpe-check-{}-{}'.format(datetime.datetime.now().strftime('%y-%m-%d-%H-%M-%S'), rnd)
    except:
        print('Unexpected error:', sys.exc_info()[0])
        exit_with_stats(NAGIOS_STATE_CRITICAL)

    try:
        route_url = create_nginx(dyn_client, namespace, args.use_pvc, pvc_delay, args.storage_class)
        poll_nginx(route_url, string_to_grep, timeout)
    except:
        print('Unexpected error: ', sys.exc_info()[0])
        exit_with_stats(NAGIOS_STATE_CRITICAL)
    finally:
        cleanup(dyn_client, namespace)

    exit_with_stats(NAGIOS_STATE_OK)


if __name__ == '__main__':
    main()
