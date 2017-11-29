# Recovering the embedded BoltDB database in Heketi

## Background

Heketi is a component in OpenShift that is responsible for providing a REST API
to a GlusterFS cluster. It is used for managing volumes. It has an embedded DB
based on BoltDB. If this database gets corrupted, then Heketi will no longer
start and it will not be possible to create new volumes or manage existing ones.

## Recovery

Backups of BoltDB are taken in the same process as other backups and copied over
to the bastion host. You can find the Heketi backup in the normal backup
location on the bastion.

First, copy the backup file from the bastion to one of the master nodes:
```bash
scp backup/<first-master-hostname>/heketi*.db <first-master-hostname>:~/
```

Then on the first master:
```bash
cd ~
# We need a directory because oc rsync likes to do things that way
mkdir heketi
mv <latest-heketi-dump>.db heketi/heketi.db
oc get pods -n glusterfs
oc rsync heketi/ <heketi-storage-pod>:/var/lib/heketi -n glusterfs
oc delete pod <heketi-storage-pod> -n glusterfs
```

If the heketi-storage pod is in CrashLoopBackOff or an Error state, launch a
debug container first and make the rsync through that:
```bash
oc debug <heketi-storage-pod> -n glusterfs
# In a different terminal on the master
oc rsync heketi/ <heketi-storage-debug-pod>:/var/lib/heketi -n glusterfs
oc delete pod <heketi-storage-pod> -n glusterfs
```

After this the Heketi storage pod should start again and it should be possible
to manage storage again.
