# OpenShift Origin playbooks

These playbooks can be used to assist deploying an OpenShift Origin cluster in cPouta. The bulk of installation
is done with the official [installer playbook](https://github.com/openshift/openshift-ansible).

## Playbooks

### init_ramdisk.yml

- extracts environment specific data to ramdisk for further installation steps

### site.yml

- aggregates all installation steps into a single playbook

### deprovision.yml

- used to tear the cluster resources down

### provision.yml

- takes care of creating the resources in cPouta project
    - VMs
    - volumes
    - security groups
    - networks 
- uses OpenStack Heat for provisioning
- optionally updates existing Heat stacks

### pre_install.yml

- adds basic tools
- installs and configures
    - docker
    - internal DNS
- configures persistent storage

### post_install.yml

- creates persistent volumes for OpenShift
- puts the registry on persistent storage
- customizes the default project template
- optionally deploys default www page and Prometheus based monitoring


### scaleup.yml

Running OpenShift Ansible scaleup playbooks for any host that does not 
have /var/lib/POC_INSTALLED flag on them. The playbooks are
    
    playbooks/byo/openshift-master/scaleup.yml
    playbooks/byo/openshift-node/scaleup.yml
    playbooks/byo/openshift-etcd/scaleup.yml

NOTE: Set flag 'allow_first_master_scaleup' to true to allow 
replacing/recovering first master. This is a special case as the first 
master has the files for local CA, thus you must restore /etc/origin/master 
first from backup before configuring it with scaleup.

The complete process of scaling up would include editing the resource group size 
in the inventory and running provisioning, preinstall and scaleup:

    ansible-playbook -v -e allow_heat_stack_update=1 site_scaleup.yml

## Prerequisites

All that is needed is 
- a working docker installation
- git client
- access to repositories

Clone POC and openshift-ansible -installer.

    mkdir -p ~/git
    cd ~/git
    git clone https://gitlab.csc.fi/c14n/poc
    git clone https://gitlab.csc.fi/c14n/openshift-environments
    git clone https://github.com/openshift/openshift-ansible

Check out a revision of openshift-ansible that matches the version of openshift you are
installing (see https://github.com/openshift/openshift-ansible#getting-the-correct-version)

    cd ~/git/openshift-ansible
    git checkout release-1.5

We have a deployment container with all dependencies preinstalled. To build the container, 
run the build script located in `poc/container-src/poc-deployer`:
 
    cd ~/git/poc/container-src/poc-deployer 
    sudo ./build.bash

If Docker containers can be launched without 'sudo', that can be left out in the commands above.

__Note on SELinux__: If you are running under SELinux enforcing mode, the container processes
may not be able to access the volumes by default. To enable access from containerized 
processes, change the labels on the mounted directories:
 
    cd ~/git
    chcon -Rt svirt_sandbox_file_t poc openshift-ansible openshift-environments

Installation data is contained in the openshift-environments repository. The format of the repository/directory 
is as follows:

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

If you want to automate the process or repeat running single actions containerized, you
can create a vault password file and loopback mount it to the container so that
initialization playbook does not have to ask it interactively:

    # Create a directory on ramdisk
    mkdir -p /dev/shm/secret
    chmod 750 /dev/shm/secret
    
    # Prepare the password file
    touch /dev/shm/secret/vaultpass
    chmod 640 /dev/shm/secret/vaultpass
    chcon -Rt svirt_sandbox_file_t /dev/shm/secret/vaultpass

    # Change the group to match the gid of user 'deployer' in the container
    sudo chgrp -R 29295 /dev/shm/secret
    
    # Populate the password from a password manager with xclip:
    xclip -o > /dev/shm/secret/vaultpass

## Provisioning

Once you have all of this configured, running the actual installation is simple.
To launch a shell in a temporary container for deploying environment 'oso-devel-singlemaster', run

    sudo scripts/run_deployment_container.bash \
      -e oso-devel-singlemaster \
      -p /dev/shm/secret/vaultpass \
      -i

Run site.yml to provision infrastructure on OpenStack and install OpenShift on this infrastructure:
    
    cd poc/playbooks
    ansible-playbook site.yml

Single step alternative for non-interactive runs:

    cd ~/git/poc
    sudo scripts/run_deployment_container.bash -e oso-devel-singlemaster -p /dev/shm/secret/vaultpass \
      ./run_playbook.bash site.yml

If you run the above from terminal locally while developing, add '-i' option to attach the terminal 
to the process for the color coding and ctrl+c to work.

### Heat stack updates

If you want to update an existing Heat stack to, say, add more minion nodes,
then you can set allow_heat_stack_update to true when running the provisioning
or the site playbooks:

    ansible-playbook site.yml -e "allow_heat_stack_update=true"

## Deprovisioning

From the deployment container, run

    cd poc/playbooks
    ansible-playbook deprovision.yml

Partial deletes are not currently supported, as the Heat stack update process
does not nicely replace missing resources. This may be possible in newer
OpenStack versions.

## Recovery

See [docs/full_restore.md](docs/full_restore.md) and 
[docs/recover_single_vm_failure.md](docs/recover_single_vm_failure.md) for recovering from failures.

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
