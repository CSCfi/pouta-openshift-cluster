# OpenShift Origin playbooks

These playbooks can be used to assist deploying an OpenShift Origin cluster in cPouta. The bulk of installation
is done with the official [installer playbook](https://github.com/openshift/openshift-ansible).

*NOTE:* This document is not a complete guide, but mostly a checklist for persons already knowing
what to do or willing to learn. Do not expect that after completing the steps you have a usable OpenShift environment.

## Playbooks

### provision.yml

- takes care of creating the resources in cPouta project
    - VMs with optionally booting from volume
    - volumes for persistent storage
    - common and master security groups
- uses OpenStack Heat

### pre_install.yml

- adds basic tools
- installs and configures
    - docker
    - internal DNS
- configures persistent storage

### post_install.yml

- creates NFS volumes for OpenShift
- puts the registry on persistent storage
- customizes the default project template

### deprovision.yml

- used to tear the cluster resources down

### site.yml

- aggregates all installation steps after provisioning into a single playbook

## Example installation process

This is a log of an example installation of a proof of concept cluster with

- one master
    - public IP
    - two persistent volumes, one for docker + swap, one for NFS persistent storage
- four nodes
    - one persistent volume for docker + swap

### Prerequisites

TODO: Fix when poc-deployer is updated (repo cloning, vault secret initialization, ...)

We have a deployment container with all dependencies preinstalled. To build the container, 
check out POC git repo (see below) and run the build script located in `container-src/poc-deployer`:
 
    cd ~/git/poc/container-src/poc-deployer 
    sudo ./build.bash
    
To launch a shell in a temporary container for deployment, run

    cd ~/git/poc/playbooks/openshift
    sudo ./run_deployment_container.bash

The script assumes that the environments directory is called openshift-environments and located
in a sibling directory next to POC. If Docker containers can be launched without 'sudo',
that can be left out in the commands above.

__Note on SELinux__: If you are running under SELinux enforcing mode, the container processes
may not be able to access the volumes by default. To enable access from containerized 
processes, change the labels on the mounted directories:
 
    chcon -Rt svirt_sandbox_file_t \
        poc openshift-ansible openshift-environments

### Deployment

You will need to fulfill the prerequisites and clone the same repositories as
mentioned in the example installation instructions above. The recommended way 
is to use the containerized environment. In addition, you will
need to provide installation information via a separate repository/directory
instead of using cluster_vars.yml.

The format of this repository/directory is as follows:

```
environments
├── environment1
│   ├── groups
│   ├── group_vars
│   │   ├── all
│   │   │   ├── tls.yml
│   │   │   ├── vars.yml
│   │   │   ├── vault.yml
│   │   │   └── volumes.yml
│   │   ├── masters.yml
│   │   ├── nfsservers.yml
│   │   ├── node_lbs.yml
│   │   ├── node_masters.yml
│   │   ├── OSEv3
│   │   │   ├── vars.yml
│   │   │   └── vault.yml
│   │   └── ssd.yml
│   ├── hosts -> ../openstack.py
│   └── host_vars
├── openstack.py
└── environment2
    └...
```

Multiple environments are described here, all in their own subdirectory (here
environment1 and environment2, but the names can be whatever). You will need to
fill in the same data as would be filled in in cluster_vars.yml, except using
the standard Ansible group_vars and host_vars structure.

The roles of the files are:
  * groups: inventory file describing host grouping
  * group_vars: directory with config data specific to individual groups
  * host_vars: directory with config data specific to individual hosts
  * group_vars/all: config data relevant to all hosts in the installation
  * masters/nfsservers/node_lbs/node_masters etc.: config data for specific
    host groups in the OpenShift cluster
  * OSEv3: OpenShift installer config data
  * openstack.py: dynamic inventory script for OpenStack provided by the
    Ansible project
  * hosts: symlink to dynamic inventory script under environment specific
    directory
  * vault.yml files: encrypted variables for storing e.g. secret keys

For initialize_ramdisk.yml to work, you will need to populate the following variables:

  * ssh_private_key
  * tls_certificate
  * tls_secret_key
  * tls_ca_certificate
  * openshift_cloudprovider_openstack_auth_url
  * openshift_cloudprovider_openstack_auth_url
  * openshift_cloudprovider_openstack_username
  * openshift_cloudprovider_openstack_domain_name
  * openshift_cloudprovider_openstack_password
  * openshift_cloudprovider_openstack_tenant_id
  * openshift_cloudprovider_openstack_tenant_name
  * openshift_cloudprovider_openstack_region

Once you have all of this configured, running the actual installation is simple.

e when using containerized deployment:

    $ cd /opt/deployment/pouta-ansible-cluster/playbooks/openshift

Extract site specific data under /dev/shm/<cluster-name> by running 

    $ SKIP_DYNAMIC_INVENTORY=1 ansible-playbook initialize_ramdisk.yml \
    -i <path-to-environment-dir> \
    --ask-vault-pass

Source the extracted OpenStack credentials:

    $ source /dev/shm/<cluster-name>/openrc.sh

Then run heat_site.yml to provision infrastructure on OpenStack and install
OpenShift on this infrastructure:

    $ time ansible-playbook heat_site.yml \
    -i <path-to-environment-dir> \
    --ask-vault-pass

## Further actions

- open security groups
- start testing and learning
- get a proper certificate for master

### Deprovisioning

    $ ansible-playbook heat_deprovision.yml \
    -i <inventory directory/file> \
    --ask-vault-pass

Partial deletes are not currently supported, as the Heat stack update process
does not nicely replace missing resources. This may be possible in newer
OpenStack versions.

## Security groups

- common
    - applied to all VMs
    - allow ssh from bastion
- infra
    - applied for all infrastructure VMs (masters, etcd, lb)
    - allow all traffic between infra VMs
- masters
    - applied to all masters
    - allow incoming DNS from common
- nodes
    - applied for all node VMs
    - allow all traffic from infra SG
- lb
    - applied to load balancers/router VMs
    - allow all traffic to router http, https and api port
- nfs
    - applied to NFS server
    - allow nfs v4 from all VMs
