# Heat stack templates for clouds with floating IPs

These are Heat stack templates used to provision POC on clusters with
floating IPs for external connectivity (for example cPouta).

## base.yml

This is the template for base resources in for cluster. It creates
- common security groups
- internal network + router interface
- bastion host

The output is used as input for subsequent Heat stacks.

## etcd.yml

This stack installs etcd cluster hosts in their own server group.

## cluster.yml

This template creates
- a VIP port for keepalived failover
- load balancer VMs with VIP added to allowed address pairs and their server group 
- master VMs and their server group
- nfs servers (not actively used)

## glusterfs.yml

This template creates a heat stack for dedicated glusterfs nodes, placed in their
own server group. The VMs have extra dedicated cinder volumes to be used as
storage block devices by glusterfs.


## compute-nodes.yml

This template creates one compute node stack along with their server group. The template 
can be called multiple times by the provisioning playbook.


## minimal.yml

This template creates a master VM and related security groups for a single master setup, 
where the master acts as the load balancer and runs a single node etcd.
