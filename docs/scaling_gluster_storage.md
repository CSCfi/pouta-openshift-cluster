# Scaling up GlusterFS storage

## Preface

Basically there are three options to scale storage up

- resizing existing disks
- add more storage nodes
- add more disks to existing nodes

## Resizing existing disks

This option is possible if you are running on a virtualized storage stack
(OpenStack Cinder, SAN, ...).

For each storage node:
- shut down the storage node
- resize the volume with 'cinder extend {volname} {newsize}'
- start the storage node
- run 'pvresize /dev/vdc'
- check that the storage looks ok
- check that glusterfs is still happy

TODO: write the steps as concrete commands
TODO: create a playbook to automate this

## Adding more storage nodes manually

1. Increase the size of the GlusterFS host group size in Heat
  * This is configured by the `glusterfs_vm_group_size` variable

2. Run a scaleup to add the new GlusterFS nodes to the cluster:
```bash
ansible-playbook -e allow_heat_stack_update_glusterfs=1 site_scaleup.yml
```

3. Login to a master node:
```bash
ssh $ENV_NAME-master-1
```

4. Label the new GlusterFS node(s):
```bash
# On a master node:
oc label node -l type=glusterfs glusterfs=storage-host
```

5. Open a shell in a Heketi storage pod where heketi-cli is available:
```bash
# On a master node:
oc rsh -n glusterfs dc/heketi-storage
```

6. Add credentials to environment variables that heketi-cli looks at for auth:
```bash
# Inside the pod:
export HEKETI_CLI_USER=admin
export HEKETI_CLI_KEY=$HEKETI_ADMIN_KEY
```

**Note: for the next step, be absolutely sure about the node name and IP
address, as an incorrectly added node will mean that you can no longer provision
storage from GlusterFS until the node with incorrect IP information has been
removed!**

7. Add a new node to GlusterFS via Heketi. Take note of the node id as you will
need it in the next step:
```bash
# Inside the pod:
heketi-cli cluster list # Get the cluster id first
heketi-cli node add \
  --zone=1 \
  --cluster=<cluster id> \
  --management-host-name=<hostname of new node> \
  --storage-host-name=<ip address of new node>
```
Repeat step 7 for all nodes that are to be added.

8. Add a block device on the new node as a device to GlusterFS:
```bash
# Inside the pod:
heketi-cli device add --name=<dev name> --node=<new node id>
```
Repeat step 8 for all devices that are to be added.
