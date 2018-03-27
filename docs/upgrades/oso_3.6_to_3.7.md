# Upgrading from OpenShift 3.6 to 3.7

This document describes the process for upgrading an OpenShift Origin cluster
installed with pouta-openshift-cluster from version 3.6 to 3.7. Most of the work
is done by an upgrade playbook from openshift-ansible, but there are some
caveats to take into account during the upgrade. Most notably GlusterFS mounts
tend to get stuck while nodes are being drained. These need to be constantly
cleaned up during the upgrade to ensure the upgrade does not get stuck.

## Status display

If you like, you can launch a status display for the upgrade like this:
```bash
sudo bash scripts/run_deployment_container.bash \
-e <env-to-upgrade> -i -p <vault pass file> bash
watch "oc get nodes; oc get pods --all-namespaces|egrep -v 'Complete'"
```

## Upgrade steps

1. Launch a deployment container with a 3.6 version of openshift-ansible.
Make sure these are set:
```yaml
openshift_release: 3.6
openshift_image_tag: v3.6.1
```
Then launch the container:
```bash
sudo bash scripts/run_deployment_container.bash \
-e <env-to-upgrade> -i -p <vault pass file> bash
```

2. Run the backup playbook from the deployment container to ensure up-to-date
backups:
```bash
cd ~/poc/playbooks
ansible-playbook backup_36.yml
```
Exit the deployment container after this is done.

3. Update version information for OpenShift for the environment. Set these:
```yaml
openshift_release: 3.7
openshift_image_tag: v3.7.1
```

4. Start a deployment container with the new data for the environment you are
upgrading:
```bash
sudo bash scripts/run_deployment_container.bash \
-e <env-to-upgrade> -i -p <vault pass file> bash
```

5. Open a second shell in the deployment container in a different terminal:
```bash
sudo docker exec -it <env-to-upgrade>-deployer bash
```

6. In one of the deployment container shells, run this to periodically check
for stuck volume mounts and clean them up (we run this from the playbooks
directory to make use of inventory caching):
```bash
cd ~/poc/playbooks
while true; do ../scripts/umount_ghost_volumes.bash ; sleep 60; done
```

7. At the same time in the other deployment container shell, upgrade the control
plane:
```bash
cd ~/poc/playbooks
ansible-playbook ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_7/upgrade_control_plane.yml
```
Wait for the upgrade to finish.

8. Once the upgrade playbook has finished, Heketi will go into a bad state and
new persistent volumes will get stuck in "pending" when created. To fix this,
restart all pods in the glusterfs namespace. Run this in the deployment
container:
```bash
ssh $ENV_NAME-master-1 oc -n glusterfs delete pods --all
```
After the pods are done restarting this should make it possible to create
volumes again.

9. Make sure the environment still works properly, fix problems if needed.

10. Once the control plane is upgraded and Heketi is fixed, it is time to upgrade
the nodes. First we upgrade glusterfs nodes, taking care that only one node is upgraded at a time and 
the cluster becomes healthy before proceeding. 
```bash
cd ~/poc/playbooks
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_7/upgrade_nodes.yml --limit 'localhost:masters:glusterfs[0]'
```
Wait for the upgrade to finish. Check that the glusterfs pod is ready, and no volume healing operations are in progress

```bash
oc -n glusterfs get pods -l glusterfs=storage-pod
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster volume heal {} info'"
```

You should check that "Number of entries" is zero for all the volumes.

Repeat this for all glusterfs nodes.

11. Upgrade the rest of the nodes
```bash
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_7/upgrade_nodes.yml --limit 'localhost:all:!glusterfs'
```

12. Stop the ghost volume busting script from running in its loop with Ctrl+C.

13. Make sure the environment is functioning properly after the upgrade.
