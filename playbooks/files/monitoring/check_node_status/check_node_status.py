#!/usr/bin/env python
#
# OpenShift node status checker for Nagios/Opsview
# The node status is queried from kube-state-metrics using the metrics
# server URL and the metric name.
#

import requests
import sys
import time
import argparse
import socket
import re

NAGIOS_STATE_OK = 0
NAGIOS_STATE_WARNING = 1
NAGIOS_STATE_CRITICAL = 2
NAGIOS_STATE_UNKNOWN = 3


def exit_with_stats(exit_code, status):
    """
    Exits with the specified exit_code and outputs any stats in the format
    nagios/opsview expects.
    """
    current_time = time.ctime()

    if exit_code == NAGIOS_STATE_OK:
        output = 'OK | Status: ' + str(status) + ' - ' + str(current_time)
    elif exit_code == NAGIOS_STATE_WARNING:
        output = 'WARNING | Status: ' + str(status) + ' - ' + str(current_time)
    else:
        output = 'CRITICAL | Status: ' + str(status) + ' - ' + str(current_time)

    print(output)

    sys.exit(exit_code)


def main():

    parser = argparse.ArgumentParser(description='Nagios check for OpenShift node status.')
    parser.add_argument('--metrics_url',
                        help='The kube-state-metrics endpoint URL.',
                        dest='metrics_url',
                        default='http://kube-state-metrics.monitoring-infra.svc:8080/metrics')
    parser.add_argument('--metric_name',
                        help='The name of the variable featuring the node status.',
                        dest='metric_name',
                        default='kube_node_status_condition')
    args = parser.parse_args()

    try:
        metrics = requests.get(args.metrics_url)
        node_name = socket.gethostname()
        metric_pattern = args.metric_name + '{node="' + node_name + '",condition="Ready",status="(.*)"} 1'
        status = re.findall(metric_pattern, metrics.text)

        if status:
            if status[0] == 'true':
                node_status = 'Ready'
                exit_with_stats(NAGIOS_STATE_OK, node_status)
            elif status[0] == 'false':
                node_status = 'NotReady'
                exit_with_stats(NAGIOS_STATE_CRITICAL, node_status)
            else:
                node_status = 'Unknown'
                exit_with_stats(NAGIOS_STATE_WARNING, node_status)
        else:
            node_status = 'Node not found'
            exit_with_stats(NAGIOS_STATE_UNKNOWN, node_status)

    except requests.exceptions.RequestException as e:
        exit_with_stats(NAGIOS_STATE_CRITICAL, e)
    except Exception as e:
        exit_with_stats(NAGIOS_STATE_CRITICAL, e)


if __name__ == '__main__':
    main()

