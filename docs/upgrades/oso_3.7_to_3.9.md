# Upgrading from OpenShift 3.7.2 to 3.9.0

This document describes the process for upgrading an OpenShift Origin cluster
installed with pouta-openshift-cluster from version 3.7.2 to 3.9.0. Most of the work
is done by an upgrade playbook from openshift-ansible, but there are some
caveats to take into account during the upgrade. Most notably GlusterFS mounts
tend to get stuck while nodes are being drained. These need to be constantly
cleaned up during the upgrade to ensure the upgrade does not get stuck.

## Status display

If you like, you can launch a status display for the upgrade like this:
```bash
sudo bash scripts/run_deployment_container.bash \
-e <env-to-upgrade> -i -p <vault pass file> bash
ssh $ENV_NAME-master-1
watch "oc get nodes; oc get pods --all-namespaces|grep -v 'build.*Completed'"
```

## Upgrade steps

1. Launch a deployment container with a 3.7 version of openshift-ansible.
Make sure these are set:
```yaml
openshift_release: 3.7
openshift_image_tag: v3.7.2
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
ansible-playbook backup.yml
```

3. Install service brokers

We need to install service brokers before running the upgrade, because the health of ansible service broker is checked
whether you install it or not by the upgrade playbook.

Set variables (if not already globally set)

```yaml
ansible_service_broker_install: True
template_service_broker_install: True
template_service_broker_selector:
  type: master
openshift_hosted_infra_selector: type=master
```
and run

```bash
cd ~/poc/playbooks
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/service-catalog.yml
```

Wait for service broker components to start.

Exit the deployment container after this is done.

4. Update version information for OpenShift for the environment. Docker is upgraded to version 1.13, as well.
Set these:
```yaml
openshift_release: 3.9
openshift_image_tag: v3.9.0
docker_version: 1.13.1
```

5. Start a deployment container with the new data for the environment you are
upgrading:
```bash
sudo bash scripts/run_deployment_container.bash \
-e <env-to-upgrade> -i -p <vault pass file> bash
```

6. Open a second shell in the deployment container in a different terminal:
```bash
sudo docker exec -it <env-to-upgrade>-deployer bash
```

7. In one of the deployment container shells, run this to periodically check
for stuck volume mounts and clean them up (we run this from the playbooks
directory to make use of inventory caching):
```bash
cd ~/poc/playbooks
while true; do ../scripts/umount_ghost_volumes.bash ; sleep 60; done
```

8. At the same time in the other deployment container shell, upgrade the control
plane

We need to force the etcd image tag from command line, see
https://github.com/openshift/openshift-ansible/issues/8025#issuecomment-382839803
```bash
cd ~/poc/playbooks
ansible-playbook ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_9/upgrade_control_plane.yml -e r_etcd_upgrade_version=latest
```
Wait for the upgrade to finish.

9. If Heketi goes into a bad state, new persistent volumes will get stuck in "pending" when created. To fix this,
restart heketi-storage and and heketi-metrics-exporter. Run this in the deployment
container:
```bash
ssh $ENV_NAME-master-1 oc -n glusterfs delete pods -l heketi=storage-pod
ssh $ENV_NAME-master-1 oc -n glusterfs delete pods -l app=heketi-metrics-exporter
```

10. Make sure the environment still works properly, fix problems if needed.

11. Once the control plane is upgraded, it is time to upgrade
the nodes. First we upgrade glusterfs nodes.

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

And then upgrade the nodes

```bash
cd ~/poc/playbooks
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_9/upgrade_nodes.yml --limit 'localhost:masters:glusterfs'
```

Remove glusterfs-storage pods to restart them and check that glusterfs comes up.

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

You should check that "Number of entries" is zero for all the volumes.
```bash
ssh $ENV_NAME-master-1
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster volume heal {} info'"
oc -n glusterfs rsh ds/glusterfs-storage bash -c "gluster volume list | xargs --replace bash -c 'echo; echo \"{}\"; gluster volume heal {} info' | egrep -v '/brick$|Status: Connected|Number of entries: 0|^$'"
```

12. Update load balancer nodes one by one to minimize downtime
```bash
cd ~/poc/playbooks
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_9/upgrade_nodes.yml --limit 'localhost:masters:lb[0]'
```
Wait for router pods to be deployed on lb-1, then repeat process for lb-2
```bash
# check that all routers are running and ready
ssh $ENV_NAME-master-1 oc -n default get pods -l router=router
# if routers are running, proceed to lb-2
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_9/upgrade_nodes.yml --limit 'localhost:masters:lb[1]'
```

13. Upgrade the rest of the nodes
```bash
ansible-playbook -v ../../openshift-ansible/playbooks/byo/openshift-cluster/upgrades/v3_9/upgrade_nodes.yml --limit 'localhost:all:!glusterfs:!lb'
```

14. Stop the ghost volume busting script from running in its loop with Ctrl+C.


15. Apply site.yml to make sure configuration is the way we want it

```bash
ansible-playbook -v site.yml
```
16. Make sure the environment is functioning properly after the upgrade.
