# Example: replace LBs with a destructive Heat stack update

## Background

We wanted to move ext_access security group from 'cluster' Heat stack
to 'base' stack for making it simple to update security group rules as part
of base stack update in the CI/CD pipeline and for sharing code between
multimaster and singlemaster installations. This meant that the security
group entries in loadbalancer VMs were changed and this triggers Heat to
reprovision the resources.

Thus, a service break and a procedure was needed.

## Procedure

Take a fresh backup
```bash
ansible-playbook -v backup.yml
```

Run site.yml to create the new security group rules under base stack

```bash
ansible-playbook -v site.yml
```

Update the cluster stack. **This will start the downtime**, as Heat will recreate the loadbalancer VMs.

```bash
ansible-playbook -v -e allow_heat_stack_update_cluster=1 provision.yml
```

Wipe old volume contents (docker storage pool) from /dev/vdb on LBs.

```bash
ansible lb -m shell -a "uptime"
ansible lb -m shell -a "dd if=/dev/zero of=/dev/vdb bs=1M count=1k"
ansible lb -m shell -a "shutdown -r 1"
sleep 70
while ! ansible lb -m shell -a "uptime" ; do sleep 10; done
```

Run pre_install for basic OS configuration   

```bash
ansible-playbook -v pre_install.yml
```

Apply loadbalancer role to enable API access

```bash
# this will fail but worry not
ansible-playbook -v -t loadbalancer ../../openshift-ansible/playbooks/byo/config.yml
```

Run site_scaleup_<version>.yml to install node processes on LBs. For example, when
running OpenShift 3.11 you would run:

```bash
ansible-playbook -v site_scaleup.yml
```

## Alternative

We also tried bringing up a third loadbalancer instance outside the Heat
stack, but this brought up some unforeseen complications when removing
the temporary load balancer (pods had to be recreated before they were
detected as healthy).
