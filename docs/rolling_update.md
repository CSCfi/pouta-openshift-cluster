# Rolling host updates

- [Rolling host updates](#rolling-host-updates)
  - [Overview](#overview)
  - [Common](#common)
    - [Status script](#status-script)
    - [Update version locked repository reference (optional)](#update-version-locked-repository-reference-optional)
  - [Update procedure by role](#update-procedure-by-role)
    - [Compute nodes](#compute-nodes)
    - [Load balancers](#load-balancers)
      - [Method 1: Update packages](#method-1-update-packages)
      - [Method 2: Rebuild](#method-2-rebuild)
    - [Masters](#masters)
      - [Method 1: Update packages](#method-1-update-packages-1)
      - [Method 2: Rebuild](#method-2-rebuild-1)
    - [Etcds](#etcds)
    - [Glusterfs](#glusterfs)
  - [Post update actions](#post-update-actions)

## Overview

Here we have an example procedure for running a rolling OS package update for OKD 3.10, installed on CentOS 7.5 to
latest CentOS 7.6 packages. The updates include packages that cause container restarts, like 'docker', and need
draining of nodes as well as extra care with infra services. Remember to synchronize your 'docker_version' variable
in the inventory with the actual docker package that was installed during the update.

## Common

### Status script

To get visibility to how nodes and pods behave during the update, you can run a status script in a separate
terminal window. The following works at least for smaller clusters.

```bash
ssh $ENV_NAME-master-1
watch "oc get nodes; oc get pods --all-namespaces | grep -v 'build.*Completed'"
```

### Update version locked repository reference (optional)

If this update includes a CentOS minor release upgrade and you are using OS minor release locking
('lock_os_minor_version' is set in the inventory), set the new release and run site.yml first to update the repository
references:

Set new release in config:

```yaml
lock_os_minor_version: true
os_version: 7.6.1810
```

Update the repos using the appropriate version of site.yml:

```bash
cd ~/poc/playbooks
ansible-playbook -v site.yml
```

If your inventory does not have 'lock_os_minor_version' set, then latest minor release packages are automatically
installed and you do not need to do update the repository references.

## Update procedure by role

### Compute nodes

```bash
cd ~/poc/playbooks
../scripts/rolling_host_update.bash -a update -dup -c $ENV_NAME-master-1 $ENV_NAME-ssdnode-{1..4}
```

If draining is blocked by pods stuck in 'Terminating' state, ghost busting may help:

```bash
../scripts/umount_ghost_volumes.bash
```

### Load balancers

#### Method 1: Update packages


Update packages on lb-1 first. We also explicitly stop keepalived on the host to let go of the virtual IP, keepalived
can still sometimes keep it during package updates even if the load balancer is not running. It will be started after
reboot again.

```bash
cd ~/poc/playbooks
../scripts/rolling_host_update.bash -a update -s keepalived -dup -c $ENV_NAME-master-1 $ENV_NAME-lb-1
```

Wait for router to be deployed again on lb-1. Check that both router pods are running.

```bash
ssh $ENV_NAME-master-1
oc get pods -l router
```

Proceed to lb-2.

```bash
cd ~/poc/playbooks
../scripts/rolling_host_update.bash -a update -dup -c $ENV_NAME-master-1 $ENV_NAME-lb-2
```

#### Method 2: Rebuild

Rebuild and update the VMs one by one.

```bash
# first, export the name to be reused in the following commands
export HOST_TO_REPLACE=$ENV_NAME-lb-X

# then, drain and cordon it
ansible $ENV_NAME-master-1 -a "oc adm drain --ignore-daemonsets --delete-local-data $HOST_TO_REPLACE"

# then rebuild
openstack server rebuild $HOST_TO_REPLACE
```

Optionally update and reboot the host. If you are using repositories locked to a minor OS release version,
you will have to do updating after running pre_install.yml playbook to install the locked repositories instead
of this.

```bash
ssh $HOST_TO_REPLACE uname -a
ansible $HOST_TO_REPLACE -a 'yum update -y'
openstack server reboot $HOST_TO_REPLACE
ssh $HOST_TO_REPLACE uname -a
```

Follow recovery instructions in [recover_single_vm_failure.md]. Remember to clean any data on the persistent volume,
the load balancers usually run on standard flavors with a Cinder volume for docker storage.

### Masters

#### Method 1: Update packages

```bash
cd ~/poc/playbooks
../scripts/rolling_host_update.bash -a update -dup -c $ENV_NAME-master-1 $ENV_NAME-master-{1..3}
```

Remember to restart your status script after the host it is running on has been restarted.

#### Method 2: Rebuild

Repeat the procedure for all masters.

Drain the master in question:

```bash
# first, export the name to be reused in the following commands
export HOST_TO_REPLACE=$ENV_NAME-master-X

# then, drain and cordon it
ansible $ENV_NAME-master-1 -a "oc adm drain --ignore-daemonsets --delete-local-data $HOST_TO_REPLACE"
```

Rebuild the VM

```bash
openstack server rebuild $HOST_TO_REPLACE
```

Optionally update and reboot the host. If you are using repositories locked to a minor OS release version,
you will have to do updating after running pre_install.yml playbook to install the locked repositories instead
of this.

```bash
ssh $HOST_TO_REPLACE uname -a
ansible $HOST_TO_REPLACE -a 'yum update -y'
openstack server reboot $HOST_TO_REPLACE
ssh $HOST_TO_REPLACE uname -a
```

Follow recovery instructions in [recover_single_vm_failure.md].

### Etcds

Etcds are best updated one by one, checking cluster health and unreachable members in between.
We do not need to drain the hosts, they are not acting as nodes.

```bash
cd ~/poc/playbooks
../scripts/rolling_host_update.bash -a update -p $ENV_NAME-etcd-1

ansible etcd[0] -m shell -a "etcdctl -endpoints https://$ENV_NAME-etcd-1:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  cluster-health"

../scripts/rolling_host_update.bash -a update -p $ENV_NAME-etcd-2

ansible etcd[0] -m shell -a "etcdctl -endpoints https://$ENV_NAME-etcd-1:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  cluster-health"

../scripts/rolling_host_update.bash -a update -p $ENV_NAME-etcd-3

ansible etcd[0] -m shell -a "etcdctl -endpoints https://$ENV_NAME-etcd-1:2379 \
  --ca-file=/etc/etcd/ca.crt --cert-file /etc/etcd/peer.crt --key-file /etc/etcd/peer.key \
  cluster-health"
```

### Glusterfs

Finally update storage nodes.

These instructions are for case where volumes do not stay online when one of the servers goes down, so we
take the storage down for a while. This is far from optimal and to be improved in the future.

First make sure client quorum is set for all volumes.

```bash
ssh $ENV_NAME-master-1
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo {}; gluster volume get {} cluster.quorum-type; echo'"
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo {}; gluster volume set {} cluster.quorum-type auto; echo'"
```

Then stop volumes

```bash
ssh $ENV_NAME-master-1
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster --mode=script volume stop {}'"
```

Then update and reboot the glusterfs nodes in parallel to minimize downtime

```bash
ansible glusterfs -a "yum update -y"
ansible glusterfs -m shell -a '( /bin/sleep 5 ; shutdown -r now "Ansible triggered reboot" ) &'
```

Remove glusterfs-storage pods to restart them and check that glusterfs comes up

```bash
ssh $ENV_NAME-master-1
oc -n glusterfs delete pods -l glusterfs=storage-pod
oc -n glusterfs get pods
```

Then start volumes again

```bash
ssh $ENV_NAME-master-1
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster --mode=script volume start {}'"
```

Check that everything is ok.

```bash
ssh $ENV_NAME-master-1
oc -n glusterfs get pods
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster volume heal {} info'"
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster volume heal {} info' | egrep -v '/brick$|Status: Connected|Number of entries: 0|^$'"
```

## Post update actions

1. Remember to check that the docker version in inventory matches what is installed on the hosts.

2. Apply the appropriate version of site.yml to configure any remaining deviations from the desired state

```bash
cd ~/poc/playbooks
ansible-playbook site.yml
```
