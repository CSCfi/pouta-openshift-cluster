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

1. Increase the size of the GlusterFS host group size in Heat. This is configured by the `glusterfs_vm_group_size` variable.

2. Run a scaleup to add the new GlusterFS nodes to the cluster, e.g.:

   ```bash
   ansible-playbook -e allow_heat_stack_update_glusterfs=1 site.yml
   ```

3. Login to a master node:

   ```bash
   ssh $ENV_NAME-master-1
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

7. Verify that the new node has been added to Heketi:

   ```bash
   # Inside the pod:
   heketi-cli node list
   # For each node:
   heketi-cli node info <node id>
   ```

## Adding more disks to existing storage nodes

It is also possible to add additional disks to existing storage nodes. The Heat
stack for the GlusterFS cluster supports adding *n* extension volumes in
addition to the two volumes that are always added. Volumes are added uniformly
to all cluster nodes to keep the configuration of the nodes as identical as
possible.

For example, if you add two extension volumes of size 100 GiB to a four node
GlusterFS cluster, each of the four nodes will get two additional 100 GiB
volumes. The total added size can thus be calculated as follows:

$`4 * 2 * 100 GiB = 800 GiB`$

If the GlusterFS cluster is configured to replicate all data two times, then the
usable space added by this is:

$`800 GiB / 2 = 400 GiB`$

Steps to configure extension volumes follow. These instructions assume that no
new nodes are added at the same time - only devices to existing cluster nodes:

1. Configure the number and size of the extension volumes to be added:
   - `glusterfs_extension_volume_group_size` controls how many volumes are to be
     added (the default is 0)
   - `glusterfs_extension_volume_size` controls the size of the volumes in GiB.
     All extension volumes will be the same size (the default is 0).

2. Run provisioning with GlusterFS scaleup allowed:

   ```bash
   ansible-playbook -e allow_heat_stack_update_glusterfs=1 provision.yml
   ```

   This will update the appropriate Heat stack and add the volumes.

3. Find out what disks are attached and make note of which ones are the new
   ones:

   ```bash
   ssh $ENV_NAME-glusterfs-1 sudo fdisk -l
   ```

4. Login to a master node:

   ```bash
   ssh $ENV_NAME-master-1
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

7. Find out the ids of the nodes in the cluster:

   ```bash
   # Inside the pod:
   heketi-cli node list
   ```

8. Add the new block devices to all the nodes:

   ```bash
   # Inside the pod:
   heketi-cli device add --name=<dev name> --node=<node id>
   ```

You will most likely want to use for/awk/sed/cut/xargs and similar to do this
in one go. The oneliner is left as an exercise to the reader, as we don't want
to maintain any overly complex commands here. The output of heketi-cli may
change, in which case an outdated oneliner copypasted from this document could
potentially be harmful. If a more automated process is desired, that should be
treated as code when it comes to development, testing and deployment.
