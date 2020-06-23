# Recover from a single VM failure

## Preface

This page describes the actions to recover a single VM from failure that requires reinstallation
and to bring it back to the cluster. The cases are listed per VM role, from easiest to hardest.

All operations are intended to be run in poc deployment container in directory
'/opt/deployment/poc/playbooks'.

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

A failed node can be rebuilt by following these steps:

1. Check for attached volumes (there shouldn't be any external volumes attached), first in the node's terminal, and then on the deployment container's terminal:

```bash
$ lsblk
```

```bash
$ openstack server show [server-name]
```


2. Rebuild the node in question:
```bash
openstack server rebuild [server-name]
```

4. When the rebuild is finished, ssh into the node, run yum update and reboot it:
```bash
$ yum update -y
$ shutdown -r now
```

5. Run pre-install.yml:
```bash
ansible-playbook -v -l [server-name],bastion pre_install.yml
``` 
6. Run site.yml:
```bash
ansible-playbook -v site.yml
```

## Masters

Rebuilding master nodes will require slighty different steps, depending on their being the first (primary), or second and third master (secondary masters). Rebuilding a primary master requires that /etc/origin is restored from backup before running site.yml, whereas rebuilding secondary masters requires running site.yml only.

### Rebuilding a primary master

Restore /etc/origin from backups:

```bash
export HOST_TO_REPLACE=$ENV_NAME-master-X
scp $ENV_NAME-bastion:backup/$HOST_TO_REPLACE/etc-origin-$HOST_TO_REPLACE-*.tar.gz /tmp/
latest_backup=$(ls /tmp/etc-origin-$HOST_TO_REPLACE*.tar.gz | sort | tail -1)
scp $latest_backup $HOST_TO_REPLACE:/tmp/etc-origin-backup.latest.tar.gz

# extract the backup
ssh $HOST_TO_REPLACE sudo tar xvf /tmp/etc-origin-backup.latest.tar.gz -C /etc
```

Then run site. Here we are running OpenShift 3.11:

```bash
ansible-playbook -v site.yml
```

For the first master there is an additional safety in place because running site against
an empty master-1 will create a new CA and result in a conflict between new and old CAs. Make sure
the backup has been extracted properly before running this.

On the primary master, double check that the backup contents were extracted:

```bash
ansible $ENV_NAME-master-1 -a 'ls /etc/origin/master'
```

Run site.yml
```bash
ansible-playbook -v -e allow_first_master_scaleup=1 site.yml
```

Check the node state on the master after running the playbook and set it schedulable
if necessary. Also remove the 'compute' node label that may be added:

```bash
ssh $ENV_NAME-master-1
oc get nodes
oc adm manage-node [host] --schedulable=true
oc label node [host] node-role.kubernetes.io/compute-
```

### Secondary Masters

Ensure that you have an operational primary master first. Then, run site.yml:

```bash
ansible-playbook -v site.yml
```

## Load balancers

Load balancers are infra nodes that run HAProxy routers for customer traffic. They also forward
traffic to the API on masters. First, recover the node part, but leave keepalived disabled so that the recovered node
won't pick up the VIP before all steps have been completed:

```bash
ansible-playbook -v site.yml -e keepalived_skip_restart=1
```

After this, application traffic should already work on the lb. However, to forward API traffic too,
we need to apply the 'openshift_load_balancer' -role.

```bash
ansible-playbook -v ../../openshift-ansible/playbooks/openshift-loadbalancer/config.yml
```

Then start keepalived and check the assignment of the virtual IP (change the interface as needed):

```bash
ansible lb -m systemd -a "name=keepalived state=started"
ansible lb -a "ip a s eth0"
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
ansible-playbook -v site.yml
```

## Etcd-1

Openshift-ansible uses etcd-1 as 'etcd_ca_host' by default, creating certificates for all hosts
and clients (=masters) there. In that case, you will need to restore the certificates from backups, place them
on a surviving host and pass that host to the site playbook.

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

Add following ansible host variable as part of the etcd-2 host_vars:
```bash
etcdctlv2: "/usr/bin/etcdctl -endpoints https://[cluster-name]-etcd-2:2379 --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key"
```

Then run site.yml, pointing the playbook to use etcd-2 as the cluster endpoint and the source
for certificates:

```bash
ansible-playbook -v site.yml -e etcd_ca_host=$ENV_NAME-etcd-2
```

## InfluxDB

Run the site playbook to reconfigure the InfluxDB node:
```bash
ansible-playbook -v site.yml -e influxdb_create_prom_db=0
```

Here we skip the creation of the Prometheus database as this will come from
the backup. If we don't skip it, then the restore process will fail because
the Prometheus database is already in place.

Get the latest backup from the bastion over to the InfluxDB node:
```bash
latest_backup=$(ssh $ENV_NAME-bastion ls -t backup/influxdb/$ENV_NAME-influxdb-1 | head -1)

# You may need to remove known_hosts on the bastion if you've run the following scp
# command before for a different incarnation of the InfluxDB machine
ssh $ENV_NAME-bastion rm .ssh/known_hosts

scp -r \
$ENV_NAME-bastion:backup/influxdb/$ENV_NAME-influxdb-1/$latest_backup/* \
$ENV_NAME-influxdb-1:/mnt/local-storage/disk1/influxdb_backups/

ssh -t $ENV_NAME-influxdb-1 sudo chown influxdb:influxdb /mnt/local-storage/disk1/influxdb_backups/*
```

Run the restore_influxdb playbook:
```bash
cd ~/poc/playbooks
ansible-playbook restore/restore_influxdb.yml
```

## Glusterfs 

Here we cover the case where glusterfs node (or nodes) has to be rebuilt. We assume,
that the volumes with actual data are intact and attached to the VM as before.

To recover glusterfs nodes, we need to first restore /var/lib/glusterd from backup.

```bash
cd ~/poc/playbooks
ansible-playbook restore/restore_glusterfs.yml
```

Then we acquire the current heketi admin key and run restore/site process. We disable 
re-creation of the storage class.

```bash
ssh $ENV_NAME-master-1 oc -n glusterfs get dc/heketi-storage -o yaml | grep -A 1 HEKETI_ADMIN_KEY
export HEKETI_ADMIN_KEY="VALUE_FROM_ABOVE_HERE"

# run recovery
ansible-playbook -v site.yml -e glusterfs_heketi_admin_key="$HEKETI_ADMIN_KEY" -e glusterfs_storage_class=
```

You may need to restart glusterfs after the operation

```bash
ssh $ENV_NAME-master-1
oc -n glusterfs delete pods -l glusterfs=storage-pod
oc -n glusterfs get pods
```

# Notes

## Automatic updates

Rebuild servers right before running site, otherwise they may be autoupdated before our
repository locking code is run.

## Etcd recovery

As of 2018-07-11, etcd scaleup playbook in release-3.9 -branch of openshift-ansible does not complete successfully, but
fails in the last stage when configuring etcd urls in master configs. For recovery, this is not a problem because the
URLs remain the same. Other cases may require editing the master configs manually.

Workaround is to verify that etcd cluster is fully healthy (see etcd sections) and create /var/lib/POC_INSTALLED 
manually after the scaleup has completed:

```bash
ssh RECOVERED_NODE
sudo touch /var/lib/POC_INSTALLED
```

TODO: check the need for this with later releases.
