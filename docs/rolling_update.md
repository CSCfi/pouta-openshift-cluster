# Rolling host update

Here we have an example procedure for running a rolling OS package update for OSO 3.7.2, installed on CentOS 7.4 to
latest CentOS 7.5 packages. The updates include packages that cause container restarts, like 'docker', and need
draining of nodes as well as extra care with infra services. Remember to synchronize your 'docker_version' variable
in the inventory with the actual docker package that was installed during the update.

## Status script

To get visibility to how nodes and pods behave during the update, you can run a status script in a separate
terminal window. The following works at least for smaller clusters.

```bash
ssh $ENV_NAME-master-1
watch "oc get nodes; oc get pods --all-namespaces | grep -v 'build.*Completed'"
```

## Update version locked repository reference (optional)
If this update includes a CentOS minor release upgrade and you are using OS minor release locking
('lock_os_minor_version' is set in the inventory), set the new release and run site.yml first to update the repository
references:

Set new release in config:

```yaml
lock_os_minor_version: true
os_version: 7.5.1804
```

Update the repos using the appropriate version of site.yml:

```bash
cd ~/poc/playbooks
ansible-playbook -v site_3.7.yml
```

If your inventory does not have 'lock_os_minor_version' set, then latest minor release packages are automatically
installed and you do not need to do update the repository references.

## Update nodes
```bash
cd ~/poc/playbooks
../scripts/rolling_host_update.bash -a update -dup -c $ENV_NAME-master-1 $ENV_NAME-ssdnode-{1..4}
```

If draining is blocked by pods stuck in 'Terminating' state, ghost busting may help:

```bash
../scripts/umount_ghost_volumes.bash
```

## Update load balancers

```bash
cd ~/poc/playbooks
../scripts/rolling_host_update.bash -a update -dup -c $ENV_NAME-master-1 $ENV_NAME-lb-1
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

## Update masters

Update masters

```bash
cd ~/poc/playbooks
../scripts/rolling_host_update.bash -a update -s origin-master-api -s origin-master-controllers -dup -c $ENV_NAME-master-1 $ENV_NAME-master-{1..3}
```

During master updates, on 3.7.2, daemon set pods may get stuck to error state. This is due to
https://github.com/openshift/origin/issues/19138

Remove hanging containers with

```bash
cd ~/poc/playbooks
ansible masters -m shell -a 'docker rm $(docker ps -qa --no-trunc --filter "status=exited")'
```

Remember to restart your status script after the host it is running on has been restarted.

## Update etcds

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

## Update glusterfs nodes

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
ansible-playbook site_3.7.yml
```
