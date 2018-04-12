# Upgrading from OpenShift 3.7.0 to 3.7.2

This document describes the process for upgrading an OpenShift Origin cluster
installed with pouta-openshift-cluster from version 3.7.0 to 3.7.2. Most of the work
is done by an upgrade playbook from openshift-ansible, but there are some
caveats to take into account during the upgrade. Most notably GlusterFS mounts
tend to get stuck while nodes are being drained. These need to be constantly
cleaned up during the upgrade to ensure the upgrade does not get stuck.

## Status display

If you like, you can launch a status display for the upgrade like this:
```bash
sudo bash scripts/run_deployment_container.bash \
-e <env-to-upgrade> -i -p <vault pass file> bash
watch "oc get nodes; oc get pods --all-namespaces|grep -v 'Complete'"
```

## Upgrade steps

1. Launch a deployment container

```bash
sudo bash scripts/run_deployment_container.bash \
-e <env-to-upgrade> -i -p <vault pass file> bash
```

2. Run the backup playbook from the deployment container to ensure up-to-date
backups:
```bash
cd ~/poc/playbooks
ansible-playbook backup.yml
```
3. Update version information for OpenShift for the environment. Set these:
```yaml
openshift_release: 3.7
openshift_image_tag: v3.7.2
```

4. Open a second shell in the deployment container in a different terminal:
```bash
sudo docker exec -it <env-to-upgrade>-deployer bash
```

5. In one of the deployment container shells, run this to periodically check
for stuck volume mounts and clean them up (we run this from the playbooks
directory to make use of inventory caching):
```bash
cd ~/poc/playbooks
while true; do ../scripts/umount_ghost_volumes.bash ; sleep 60; done
```

6. At the same time in the other deployment container shell, upgrade the control
plane. We'll have to skip etcd upgrade, or the installation will fail when trying
to pull a newer etcd image. https://github.com/openshift/openshift-ansible/issues/6931

```bash
cd ~/poc/playbooks
ansible-playbook ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_7/upgrade_control_plane.yml -e openshift_etcd_upgrade=false
```
Wait for the upgrade to finish.

7. Apply post_install to make registry work again

```bash
ansible-playbook -v post_install.yml
```

8. If Heketi goes into a bad state, new persistent volumes will get stuck in "pending" when created. To fix this,
restart heketi-storage and and heketi-metrics-exporter. Run this in the deployment
container:
```bash
ssh $ENV_NAME-master-1 oc -n glusterfs delete pods -l heketi=storage-pod
ssh $ENV_NAME-master-1 oc -n glusterfs delete pods -l app=heketi-metrics-exporter
```
After the pods are recreated this should make it possible to create volumes again.

9. Make sure the environment still works properly, fix problems if needed.

10. Once the control plane is upgraded, it is time to upgrade
the nodes. First we upgrade glusterfs nodes, taking care that only one node is upgraded at a time and 
the cluster becomes healthy before proceeding. 
```bash
cd ~/poc/playbooks
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_7/upgrade_nodes.yml --limit 'localhost:masters:glusterfs[0]'
```
Wait for the upgrade to finish. Check that the glusterfs pod is ready, and no volume healing operations are in progress

```bash
ssh $ENV_NAME-master-1
oc -n glusterfs get pods -l glusterfs=storage-pod
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster volume heal {} info'"
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster volume heal {} info' | grep 'Number of entries'"
exit
```

You should check that "Number of entries" is zero for all the volumes.

Repeat this for all glusterfs nodes.

11. Update load balancer nodes one by one to minimize downtime
```bash
cd ~/poc/playbooks
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_7/upgrade_nodes.yml --limit 'localhost:masters:lb[0]'
```
Wait for router pods to be deployed on lb-1, then repeat process for lb-2
```bash
# check that all routers are running and ready
ssh $ENV_NAME-master-1 oc -n default get pods -l router=router
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_7/upgrade_nodes.yml --limit 'localhost:masters:lb[1]'
```

12. Upgrade the rest of the nodes
```bash
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_7/upgrade_nodes.yml --limit 'localhost:all:!glusterfs:!lb'
```

13. Stop the ghost volume busting script from running in its loop with Ctrl+C.

14. Apply post_install to make sure configuration is the way we want it   

```bash
ansible-playbook -v post_install.yml
```

15. Make sure the environment is functioning properly after the upgrade.
