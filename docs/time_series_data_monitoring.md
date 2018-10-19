# Time series data monitoring

POC can deploy:

  * Prometheus for scraping various metrics about the OpenShift installation.
  * InfluxDB for long term storage of data scraped by Prometheus.
  * Grafana for visualizing the data from Prometheus and InfluxDB.

The playbook that deploys all of these is `playbooks/deploy_monitoring.yml`
which runs during the post-install phase.

This document is intended as a high level overview of the time series data
setup. For more detail, please refer to the code and configuration referenced
here.

## Overview

Prometheus scrapes data from various sources and is configured with the
`remote_write` option to write this data into InfluxDB. The InfluxDB pod has a
sidecar container that runs a Prometheus remote storage adapter that receives
data from Prometheus and writes it to InfluxDB.

Grafana is configured with data sources for both Prometheus (short term data)
and InfluxDB (long term data). Some Grafana dashboards are also added that use
these data sources and provide data on the OpenShift cluster's state.

## Configuring Prometheus

Prometheus runs as a normal OpenShift application. The YAML to deploy Prometheus
is under `playbooks/templates/prometheus.yaml.j2`. 

The main configuration file for Prometheus is called `prometheus.yml` (not to be
confused with the template under the playbooks directory). This is stored in a
ConfigMap in OpenShift. There are some noteworthy customizations made to this
file to enable integration with InfluxDB:

  * `remote_write`: This configures Prometheus to write its metrics into a
    remote URL. There is also an optional whitelist of metrics to be written
    (`prometheus_metrics_to_archive`) to limit the amount of data that needs to
    be stored.
  * `rule_files`: Prometheus supports precalculating metrics based on other
    metrics. It is sometimes necessary to do this when using Prometheus in
    conjunction with InfluxDB as the InfluxDB query language doesn't support all
    the same operations as the Prometheus query language. Composite metrics to
    be consumed by InfluxDB are listed in a separate file specified here.

## Configuring InfluxDB

InfluxDB is configured to run on its own node with local storage. According to
the documentation for InfluxDB, local SSD storage is the only supported storage
option.

The deployment YAMLs of InfluxDB are under `playbooks/templates/influxdb`. In
addition to InfluxDB itself, a backup CronJob is also configured there. This is
used to regularly take backups of the data in InfluxDB.

InfluxDB is intended as long term storage, so there is support for configuring
continuous queries and retention policies for data downsampling. These can be
specified as additional queries in an optional variable called
`influxdb_additional_queries` that can be set per environment.

## Configuring Grafana

The Grafana deployment is described in `playbooks/templates/grafana.yaml.j2`.
Dashboards and data sources are inserted in `deploy_monitoring.yml`.
