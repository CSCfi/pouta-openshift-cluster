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
- cPouta credentials and OpenStack credentials
- python virtualenvironment with ansible>=2.1.0, shade and dnspython
- another python virtualenvironment with ansible==1.9.4 and pyopenssl
- ssh access to the internal network of your project
    - either run this on your bastion host
    - or set up ssh forwarding through your bastion host in your ~/.ssh/config
    - please test ssh manually after provisioning 

For automatic, self-provisioned app routes to work, you will need a wildcard DNS CNAME for your master's public IP.
 
In general, see https://docs.openshift.org/latest/install_config/install/prerequisites.html

### Clone playbooks

Clone the necessary playbooks from GitHub (here we assume they go under ~/git)
    
    cd ~/git
    git clone https://github.com/CSC-IT-Center-for-Science/pouta-ansible-cluster
    git clone https://github.com/openshift/openshift-ansible.git
    
The following is a temporary fix for creating NFS volumes

    git clone https://github.com/tourunen/openshift-ansible.git openshift-ansible-tourunen
    cd openshift-ansible-tourunen
    git checkout nfs_fixes

### Create a cluster config

Create a new directory and populate a config file:

    $ cd oso-deployment
    $ cat cluster_vars.yaml 

    cluster_name: "my-oso"
    
    num_masters: 1
    num_lbs: 0
    num_etcd: 0
    
    master_auto_ip: no
    master_flavor: "standard.medium"
    master_data_volume_size: 100
    master_pv_vg_data: "/dev/vdb"
    
    node_groups:
      - name: oc
        flavor: standard.large
        num_nodes: 4
        data_volume_size: 200
        pv_vg_data: "/dev/vdb"
    
    network_name: ""
        
    bastion_secgroup: "bastion"
    pvol_volume_size: 500
    pv_vg_pvol: "/dev/vdc"
    
    oso_install_containerized: false
    openshift_public_hostname: "your.master.hostname.here"
    openshift_public_ip: "your.master.ip.here"
    
    project_external_ips: ["your.master.ip.here"]
    
    # if you have wildcard certificates, use these
    #certificate_crt: 'path/to/your/certificate.crt'
    #certificate_key: 'path/to/your/certificate.key'
    
    # if you wish to prepopulate htpasswd, use this
    # openshift_master_htpasswd_file: "path/to/your/htpasswd"

### Run provisioning

First provision the VMs and associated resources

    $ workon ansible-2.1
    $ ansible-playbook -v -e @cluster_vars.yaml ~/git/pouta-ansible-cluster/playbooks/openshift/provision.yml 

Then prepare the VMs for installation

    $ ansible-playbook -v -i openshift-inventory ~/git/pouta-ansible-cluster/playbooks/openshift/configure.yml
     
Finally run the installer (this will take a while). The installer does not support ansible 2 yet, so we need to
switch to an older version
    
    $ workon ansible-1.9
    $ ansible-playbook -v -i openshift-inventory ~/git/openshift-ansible/playbooks/byo/config.yml

Also, create the persistent volumes at this point. Edit the playbook to suit your needs, then run it. Note that if you
want to deploy a registry with persistent storage, you will need at least one pvol to hold the data for the registry.

    $ vi ~/git/openshift-ansible-tourunen/setup_lvm_nfs.yml
    $ ansible-playbook -v -i openshift-inventory ~/git/openshift-ansible-tourunen/setup_lvm_nfs.yml

### Configure the cluster

Login to the master, switch to root

    $ ssh cloud-user@your.masters.internal.ip
    $ sudo -i
    
Add the persistent volumes that were created earlier to OpenShift

    $ for vol in persistent-volume.pvol*; do oc create -f $vol; done

Deploy registry with persistent storage. Note that you need a pvol that is at least 200GB for this.

    $ oc delete all --selector=docker-registry=default
    $ oc adm registry --selector=region=infra
    $ oc volume dc/docker-registry --remove --name=registry-storage 
    $ oc volume dc/docker-registry --add --mount-path=/registry --overwrite --name=registry-storage -t pvc --claim-size=200Gi 

    $ oc adm manage-node $HOSTNAME.novalocal --schedulable=true
    $ oc delete svc/router
    $ oc delete dc/router
    $ oc adm router --service-account=router --selector=region=infra

Add a user
    
    $ htpasswd -c /etc/origin/master/htpasswd alice


## Further actions

- open security groups
- start testing and learning
- get a proper certificate for master
