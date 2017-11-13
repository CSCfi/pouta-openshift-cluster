# Recover from a single VM failure

## Preface

This page describes the actions to recover a single VM from failure that requires reinstallation 
and to bring it back to the cluster. The cases are listed per VM role, from easiest to hardest.

All operations are intended to be run in poc deployment container in directory 
'/opt/deployment/poc/playbooks'.

## Replacing a VM

### Rebuild

A corrupted VM can be reinitialized with !OpenStack rebuild -command. 

```bash
openstack rebuild --image CentOS-7-c14n-20171012 [server-name]
```

If the VM has state on disk, too, you will need to remove the LV hosting docker images, too.

```bash
ssh [host]
sudo lvremove vg_data/docker-pool
```

### Recreate (not working at the moment)

If the VM (or any other part of the stack) has disappeared completely (this should never happen under normal 
circumstances) you should be able to update the Heat stack with:

```bash
openstack stack check [stack-name]
ansible-playbook -v -e allow_heat_stack_update=1 site.yml
```

*However, this may result in an error* "Fixed IP address is already in use on instance". Looks like static 
IPs are not working completely with OpenStack Newton release of Heat. Currently, one would have to either manually 
create the VM or resurrect the resources in OpenStack using administrative access.

*NOTE*: updating Heat stack can potentially reset all VMs in the stack to their initial states. Use with caution.

### Pre-install configuration

Run pre-install playbook, limiting it to the host we are resurrecting.

```bash
ansible-playbook -v -l [vm_to_replace],bastion pre_install.yml
```

## Nodes

A failed node can be configured simply by running site_scaleup.yml:

```bash
ansible-playbook -v site_scaleup.yml
```

## Secondary and Tertiary masters

Same procedure as for nodes

```bash
ansible-playbook -v site_scaleup.yml
```

Check the node state on the master after running the playbook and set it schedulable
if necessary

```bash
ssh [cluster_name]-master-1
oc get nodes
oc adm manage-node [host] --schedulable=true
```

## Primary master (master-1)

The primary master acts as the CA for the cluster, so there are additional steps when restoring that.
Before running 'site.yml', restore '/etc/origin' from the latest backup.

Then, run ansible with an additional safety flag turned on:

```bash
ansible-playbook -v -e allow_first_master_scaleup=1 site_scaleup.yml
```

The additional safety is in place because running scaleup against an empty master-1 will create
a new CA and result in a conflict between new and old CAs.

## Load balancers

Load balancers are infra nodes that run HAProxy routers for customer traffic. They also forward 
traffic to the API on masters. First, recover the node part: 

```bash
ansible-playbook -v site_scaleup.yml
```

After this, application traffic should already work on the lb. However, to forward API traffic too, 
we need to apply the 'openshift_load_balancer' -role. Currently this is done by 
running 'byo/config.yaml' -playbook with a tag selector 'loadbalancer'. The downside is that while the role 
is successfully applied, the playbook execution fails later on. A cleaner solution should be introduced
in the future.

```bash
ansible-playbook -v -t loadbalancer ../../openshift-ansible/playbooks/byo/config.yml
```

## Etcd

Etcd recovery is fairly straight forward. Etcd-1 is a bit more involved, because
openshift-ansible uses that as 'etcd_ca_host' by default, creating certificates for all hosts
and clients (=masters) there. However, openshift-ansible will create copies on other hosts, too,
and the CSC copy includes a patch to allow setting 'etcd_ca_host' to some other host than
etcd-1.

Remove the faulty node from etcd-cluster by logging in to a surviving member and using etcdctl 
there:

```bash
ssh [cluster-name]-etcd-1

sudo etcdctl -endpoints https://[cluster-name]-etcd-1:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  cluster-health

sudo etcdctl -endpoints https://[cluster-name]-etcd-1:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  member remove [id_of_the_failed_member]
```

Then run site_scaleup.yml:

```bash
ansible-playbook -v site_scaleup.yml
```

If you are replacing etcd-1, change the endpoint host and add 
'-e override_etcd_ca_host=[surviving member]' in the playbook command above.