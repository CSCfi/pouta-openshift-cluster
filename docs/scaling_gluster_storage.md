# Scaling up glusterfs storage

## Preface

Basically there are three options to scale storage up

- add more storage nodes
- add more disks to existing nodes
- resizing existing disks

The option discussed here is the last one, which is possible if you are running
on a virtualized storage stack (OpenStack Cinder, SAN, ...).

## Procedure

For each storage node:
- shut down the storage node
- resize the volume with 'cinder extend {volname} {newsize}'
- start the storage node
- run 'pvresize /dev/vdc'
- check that the storage looks ok
- check that glusterfs is still happy

TODO: write the steps as concrete commands
TODO: create a playbook to automate this
