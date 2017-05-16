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
    
- writes an inventory file to be used by later stages

### configure.yml

- adds basic tools
- installs and configures
    - docker
    - internal DNS
- configures persistent storage

### deprovision.yml

- used to tear the cluster resources down

## Example installation process

This is a log of an example installation of a proof of concept cluster with

- one master
    - public IP
    - two persistent volumes, one for docker + swap, one for NFS persistent storage
- four nodes
    - one persistent volume for docker + swap

### Prerequisites

Shell environment with
- OpenStack credentials for cPouta 
- python virtualenv with ansible==2.3, shade, dnspython and pyopenssl
- venv should have latest setuptools and pip (pip install --upgrade pip setuptools)
- metrics needs java keytool on the bastion host: sudo yum install java-1.8.0-openjdk-headless
- if you have SELinux enabled, either disable that or make sure the virtualenv has libselinux-python  
- ssh access to the internal network of your project
    - either run this on your bastion host
    - or set up ssh forwarding through your bastion host in your ~/.ssh/config
    - please test ssh manually after provisioning 

For packages on CentOS-7, see: [Creating a bastion host](../../CREATE_BASTION_HOST.md)

For automatic, self-provisioned app routes to work, you will need a wildcard DNS CNAME for your master's public IP.
 
In general, see https://docs.openshift.org/latest/install_config/install/prerequisites.html

### Clone playbooks

Clone the necessary playbooks from GitHub (here we assume they go under ~/git)
    
    $ mkdir -p ~/git && cd ~/git
    $ git clone https://github.com/CSCfi/pouta-ansible-cluster
    $ git clone https://github.com/tourunen/openshift-ansible.git openshift-ansible-tourunen
    $ cd openshift-ansible-tourunen
    $ git checkout release-1.5-csc

### Create a cluster config

Decide a name for your cluster, create a new directory and copy the example config file and modify that

    $ cd
    $ mkdir YOUR_CLUSTER_NAME
    $ cd YOUR_CLUSTER_NAME
    $ cp ~/git/pouta-ansible-cluster/playbooks/openshift/example_cluster_vars.yaml cluster_vars.yaml

Change at least the following config entries:

    cluster_name: "YOUR_CLUSTER_NAME" 
    ssh_key: "bastion-key"
    openshift_public_hostname: "your.master.hostname.here"
    openshift_public_ip: "your.master.ip.here"
    project_external_ips: ["your.master.ip.here"]
    
If you are deploying the cluster to a non-default network, remember to add and configure an interface to bastion host in
that network. The network also needs to be attached to a router.

### Run provisioning

Source your openstack credentials first

    $ source ~/openrc.bash

Provision the VMs and associated resources

    $ workon ansible-2.3
    $ ansible-playbook -v -e @cluster_vars.yaml ~/git/pouta-ansible-cluster/playbooks/openshift/provision.yml 

Then prepare the VMs for installation

    $ ansible-playbook -v -e @cluster_vars.yaml -i openshift-inventory ~/git/pouta-ansible-cluster/playbooks/openshift/configure.yml
     
Finally run the installer (this will take a while).
    
    $ ansible-playbook -v -b -i openshift-inventory ~/git/openshift-ansible-tourunen/playbooks/byo/config.yml

Also, create the persistent volumes at this point. Edit the playbook to suit your needs, then run it. Note that if you
want to deploy a registry with persistent storage, you will need at least one pvol to hold the data for the registry.

    $ vi ~/git/openshift-ansible-tourunen/setup_lvm_nfs.yml
    $ ansible-playbook -v -i openshift-inventory -e @cluster_vars.yaml ~/git/pouta-ansible-cluster/playbooks/openshift/post_install.yml

### Configure the cluster

Login to the master

    $ ssh cloud-user@your-master-1
    
Add the persistent volumes that were created during post install to OpenShift

    $ for vol in nfs_pv/persistent-volume.pvol*; do oc create -f $vol; done

Re-deploy registry with persistent storage. Note that you need a pvol that is at least 200GB for this.

    $ oc volume dc/docker-registry --add --mount-path=/registry --overwrite --name=registry-storage -t pvc --claim-size=200Gi 

Add the default project request object (before this step no projects can be created)

    $ oc create -f project-request.yaml
    
Add a user
    
    $ sudo htpasswd -c /etc/origin/master/htpasswd alice

## Further actions

- open security groups
- start testing and learning
- get a proper certificate for master

## Deprovisioning

To deprovision all the resources, run

    $ ansible-playbook -v -e @cluster_vars.yaml \
    -e remove_nodes=1 -e remove_node_volumes=1 \
    -e remove_masters=1 -e remove_master_volumes=1 \
    -e remove_etcd=1 \
    -e remove_lbs=1 -e remove_lb_volumes=1 \
    -e remove_nfs=1 -e remove_nfs_volumes=1 \
    -e remove_security_groups=1 \
    ~/git/pouta-ansible-cluster/playbooks/openshift/deprovision.yml

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
