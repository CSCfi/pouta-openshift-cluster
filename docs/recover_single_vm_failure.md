# Recover from a single VM failure

## Preface

This page describes the actions to recover a single VM from failure that requires reinstallation
and to bring it back to the cluster. The cases are listed per VM role, from easiest to hardest.

All operations are intended to be run in poc deployment container in directory
'/opt/deployment/poc/playbooks'.

The scaleup playbook location in openshift-ansible differs between OpenShift versions,
so there are several versions of the site_scaleup playbook. Use the most recent one if
a playbook isn't available for your specific version.

## Replacing VMs from multiple groups

If VMs from multiple groups need to be replaced, you will need to prepare them all at the same time and
include the possible custom extra variables (-e ...) for all of them.

To check which hosts will be included in scaleup, run

```bash
cd ~/poc/playbooks
ansible all -o -m shell -a 'if [[ ! -f /var/lib/POC_INSTALLED ]]; then echo "POC installation flag not found"; fi'
```

## Replacing a VM

### Rebuild

A corrupted VM can be reinitialized with the `openstack server rebuild` command.

```bash
openstack server rebuild [server-name]
```

You can optionally specify the image to use with `--image <image name>` in the
command above, but this is unnecessary in most cases. If no image is specified,
the same image is used that was used to build the server initially.

In some cases it may be necessary to run `nova evacuate` on the server instead:
```bash
nova evacuate [server-name]
```

This will rebuild the server in some cases where rebuild fails. However, the
evacuate command needs admin access to the OpenStack APIs.

If the VM has state on disk, too, you will need to remove the LV hosting docker images, too.

```bash
ssh [host]
sudo lvremove vg_data/docker-pool
```

Don't delete and recreate servers - this can lead to Heat stacks going into a
state that requires OpenStack admin intervention to fix.

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

A failed node can be configured simply by running site_scaleup_<version>.yml.
For example for OpenShift 3.9:

```bash
ansible-playbook -v site_scaleup_3.9.yml
```

## Masters

Restore etc/origin from backups

```bash
export HOST_TO_REPLACE=$ENV_NAME-master-X
scp $ENV_NAME-bastion:backup/$HOST_TO_REPLACE/etc-origin-$HOST_TO_REPLACE-*.tar.gz /tmp/
latest_backup=$(ls /tmp/etc-origin-$HOST_TO_REPLACE*.tar.gz | sort | tail -1)
scp $latest_backup $HOST_TO_REPLACE:/tmp/etc-origin-backup.latest.tar.gz

# extract the backup
ssh $HOST_TO_REPLACE sudo tar xvf /tmp/etc-origin-backup.latest.tar.gz -C /etc
```

Then run scaleup. Here we are running OpenShift 3.9:

```bash
# second and third master
ansible-playbook -v site_scaleup_3.9.yml
```

For the first master there is an additional safety in place because running scaleup against
an empty master-1 will create a new CA and result in a conflict between new and old CAs. Make sure
the backup has been extracted properly before running this.

```bash
# primary master
ansible-playbook -v -e allow_first_master_scaleup=1 site_scaleup_3.9.yml
```

Check the node state on the master after running the playbook and set it schedulable
if necessary. Also remove the 'compute' node label that may be added:

```bash
ssh $ENV_NAME-master-1
oc get nodes
oc adm manage-node [host] --schedulable=true
oc label node [host] node-role.kubernetes.io/compute-
```

## Load balancers

Load balancers are infra nodes that run HAProxy routers for customer traffic. They also forward
traffic to the API on masters. First, recover the node part:

```bash
ansible-playbook -v site_scaleup_3.9.yml
```

After this, application traffic should already work on the lb. However, to forward API traffic too,
we need to apply the 'openshift_load_balancer' -role. Currently this is done by
running 'byo/config.yaml' -playbook with a tag selector 'loadbalancer'. The downside is that while the role
is successfully applied, the playbook execution fails later on. A cleaner solution should be introduced
in the future.

```bash
ansible-playbook -v -t loadbalancer ../../openshift-ansible/playbooks/byo/config.yml
```

## Etcd-2 and etcd-3

Etcd recovery is fairly straight forward. Etcd-1 is a bit more involved, see below.

Remove the faulty node from etcd-cluster by logging in to a surviving member and using etcdctl
there (install etcd to obtain 'etcdctl' if necessary):

```bash
ssh $ENV_NAME-etcd-1
sudo yum install -y etcd

sudo etcdctl -endpoints https://[cluster-name]-etcd-1:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  cluster-health

sudo etcdctl -endpoints https://[cluster-name]-etcd-1:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  member remove [id_of_the_failed_member]
```

Then run site_scaleup_<version>.yml, e.g.:

```bash
ansible-playbook -v site_scaleup_3.9.yml
```

## Etcd-1

Openshift-ansible uses etcd-1 as 'etcd_ca_host' by default, creating certificates for all hosts
and clients (=masters) there. In that case, you will need to restore the certificates from backups, place them
on a surviving host and pass that host to the scaleup playbook.

First restore /etc/etcd from backup to etcd-1 and etcd-2, that will work as a temporary certificate host

```bash
# copy /etc/etcd backups to deployment container, then copy the latest to etcd-1 and etcd-2
scp $ENV_NAME-bastion:backup/$ENV_NAME-etcd-1/etc-etcd-$ENV_NAME-etcd-1*.tar.gz /tmp/
latest_backup=$(ls /tmp/etc-etcd-$ENV_NAME-etcd-1*.tar.gz | sort | tail -1)
scp $latest_backup $ENV_NAME-etcd-1:/tmp/etc-etcd-1.latest.tar.gz
scp $latest_backup $ENV_NAME-etcd-2:/tmp/etc-etcd-1.latest.tar.gz

# extract the whole archive in etcd-1
ssh $ENV_NAME-etcd-1 sudo tar xvf /tmp/etc-etcd-1.latest.tar.gz -C /etc
# extract the CA files and generated certificates on etcd-2
ssh $ENV_NAME-etcd-2 sudo tar xvf /tmp/etc-etcd-1.latest.tar.gz etcd/ca etcd/generated_certs -C /etc
```

Then remove the old member entry for etcd-1 from the cluster (install etcd to obtain 'etcdctl' if necessary)
```bash
ssh $ENV_NAME-etcd-2
sudo yum install -y etcd

sudo etcdctl -endpoints https://[cluster-name]-etcd-2:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  cluster-health

sudo etcdctl -endpoints https://[cluster-name]-etcd-2:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  member remove [id_of_the_failed_member]

```

Then run site_scaleup.yml, pointing the playbook to use etcd-2 as the cluster endpoint and the source
for certificates:

```bash
ansible-playbook -v site_scaleup_3.9.yml -e etcd_ca_host=$ENV_NAME-etcd-2
```

# Notes

Rebuild servers right before running site_scaleup, otherwise they may be autoupdated before our
repository locking code is run.
