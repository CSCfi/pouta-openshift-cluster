# Openshift Origin playbooks

These playbooks can be used to assist deploying an OpenShift Origin cluster in cPouta. The bulk of installation
is done with the official installer playbook.

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
- cPouta credentials and Open
- python virtualenvironment with ansible>=2.0.1, shade and 
- ssh access to the internal network of your project
    - either run this on your bastion host
    - or set up ssh forwarding through your bastion host in your ~/.ssh/config 

For automatic, self-provisioned app routes to work, you will need a wildcard DNS CNAME for your master's public IP.
 
In general, see https://docs.openshift.org/latest/install_config/install/prerequisites.html


### Clone playbooks

Clone the necessary playbooks from GitHub (here we assume they go under ~/git)
    
    cd ~/git
    git clone https://github.com/tourunen/pouta-ansible-cluster
    git clone https://github.com/openshift/openshift-ansible.git
    
The following is a temporary fix for creating NFS volumes

    git clone https://github.com/tourunen/openshift-ansible.git openshift-ansible-tourunen
    cd openshift-ansible-tourunen
    git checkout nfs_fixes

### Create a cluster config

Create a new directory and populate a config file

    $ cd oso-deployment
    $ cat cluster_vars.yaml 
    ssh_key: "openstack_key"
    num_nodes: 4
    cluster_name: "my-oso"
    master_floating_ips: ["your.floating.ip.here"]
    master_auto_ip: no
    boot_from_volume: yes
    master_flavor: "mini"
    node_flavor: "mini"
    network_name: ""
    bastion_secgroup: "bastion"
    master_data_volume_size: 100
    node_data_volume_size: 100
    pvol_volume_size: 200
    openshift_public_hostname: "your.master.hostname.here"

### Run provisioning

First provision the VMs and assosiated resources

    $ ansible-playbook -v -e @cluster_vars.yaml ~/git/pouta-ansible-cluster/playbooks/openshift/provision.yml 

Then prepare the VMs for installation

    $ ansible-playbook -v -i openshift-inventory ~/git/pouta-ansible-cluster/playbooks/openshift/configure.yml
     
Finally run the installer (this will take a while)
     
    $ /usr/bin/ansible-playbook -v -i openshift-inventory ~/git/openshift-ansible/playbooks/byo/config.yml

Also, create the persistent volumes at this point. Edit the playbook to suit your needs, then run it

    $ vi ~/git/openshift-ansible-tourunen/setup_lvm_nfs.yml
    $ /usr/bin/ansible-playbook -v -i openshift-inventory ~/git/openshift-ansible-tourunen/setup_lvm_nfs.yml

### Configure the cluster

First install the real client on your master, replacing the wrapper in /usr/local/bin/oc. 
Download the latest from https://github.com/openshift/origin/releases 

    $ ssh cloud-user@your.masters.internal.ip
    $ tmux
    $ wget        
    $ cd /tmp/
    $ wget THE_URL_FOR_THE_LATEST_LINUX_64BIT_CLIENT_TOOLS
    $ tar xvfz openshift-origin-client-tools*linux-64bit.tar.gz 
    $ sudo cp openshift-origin-client-tools-*-linux-64bit/oc /usr/local/bin/oc


Then redeploy router and registry on the master

    $ oc adm manage-node $HOSTNAME.novalocal --schedulable=true
    $ oc delete svc/router
    $ oc delete dc/router
    $ oc adm registry --selector=region=infra
    $ oc adm router --service-account=router --selector=region=infra

Add a user
    
    $ htpasswd -c /etc/origin/master/htpasswd alice

Add the persistent volumes that were created earlier to OpenShift

    $ cd
    $ for vol in persistent-volume.pvol*; do oc create -f $vol; done

## Further actions

- open security groups
- start testing and learning
- get a proper certificate for master
