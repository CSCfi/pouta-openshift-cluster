# Restore system from backup

##Preface

This document describes the actions for catastrophe recovery. It is still work in progress. 

## Restore from backups

To restore cluster from backups, you will need the latest etcd-data and etc backup tarballs, located
on the bastion host. If you have lost bastion too, restore the tarballs to bastion first from offsite 
backup.

Launch deployment container and run

```bash
cd poc/playbooks
restore/full_restore.bash
```

This will provision a fresh cluster and restore etcd data (openshift objects) and generated certificates
on it. The provisioning will be done in pieces, take a look at 
[restore/full_restore.bash](/playbooks/restore/full_restore.bash) for details, comments and troubleshooting.

Note: The current version of the script works with openshift-ansible#release-3.7. For release-3.6, use 
`restore/full_restore_36.bash`
