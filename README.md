# OpenShift Origin playbooks

- [OpenShift Origin playbooks](#openshift-origin-playbooks)
  - [Prerequisites for using these playbooks](#prerequisites-for-using-these-playbooks)
    - [Environment specific data](#environment-specific-data)
  - [Provisioning](#provisioning)
    - [Usage in a GitLab pipeline](#usage-in-a-gitlab-pipeline)
    - [Heat stack updates](#heat-stack-updates)
  - [Playbooks](#playbooks)
    - [init_ramdisk.yml](#init_ramdiskyml)
    - [site.yml](#siteyml)
    - [deprovision.yml](#deprovisionyml)
    - [provision.yml](#provisionyml)
    - [pre_install.yml](#pre_installyml)
    - [post_install.yml](#post_installyml)
    - [scaleup_[version].yml and site_scaleup_[version].yml](#scaleup_versionyml-and-site_scaleup_versionyml)
    - [scaledown_nodes.yml](#scaledown_nodesyml)
  - [Deprovisioning](#deprovisioning)
  - [Recovery](#recovery)
  - [Security groups](#security-groups)

These playbooks can be used to assist deploying an OpenShift Origin cluster in
cPouta. The bulk of installation is done with the official [installer
playbook](https://github.com/openshift/openshift-ansible).

## Prerequisites for using these playbooks

All that is needed is

- a working docker installation
- git client
- access to repositories

Clone POC and openshift-ansible -installer.

```bash
mkdir -p ~/git
cd ~/git
git clone https://gitlab.csc.fi/c14n/poc
git clone https://gitlab.csc.fi/c14n/openshift-environments
git clone https://github.com/CSCfi/openshift-ansible
```

Check out a revision of openshift-ansible that matches the version of OpenShift
you are installing (see [openshift-ansible: Getting the correct
version](https://github.com/openshift/openshift-ansible#getting-the-correct-version))
(the current version may be different from the version in the command below):

```bash
cd ~/git/openshift-ansible
git checkout release-3.9-csc
```

We have a deployment container with all dependencies preinstalled. To build the container,
run the build script located in `poc/container-src/poc-deployer`:

```bash
cd ~/git/poc/container-src/poc-deployer
sudo ./build.bash
```

If you're using Buildah, you can also use:
```bash
cd ~/git/poc/container-src/poc-deployer
sudo ./buildah_build.bash
```


If Docker containers can be launched without 'sudo', that can be left out in the commands above.

__Note on SELinux__: If you are running under SELinux enforcing mode, the container processes
may not be able to access the volumes by default. To enable access from containerized
processes, change the labels on the mounted directories:

```bash
cd ~/git
chcon -Rt svirt_sandbox_file_t poc openshift-ansible openshift-environments
```
__Note on RHEL 8__: RHEL 8 comes with Podman instead of Docker.

If you're using RHEL8, easiest way to run the docker-wrapping scripts meantioned on this page (`build.bash`, `dcterm.sh`, and `run_deployment_container.bash`) is to create a global BASH function that returns `podman` every time `docker` is called.

For example:

1. Create a file in /etc/profile.d/ directory:

```$ touch podmanAlias.sh```

2. Edit the file, defining the function to be returned: 

```
docker() {
    /usr/bin/podman "$@"
}
export -f docker
```
3. Take new the global function into effect by exiting your terminal and launching a new one, or by sourcing the the new file:

```
$ source /etc/profile/podmanAlias.sh
```

4. Test the new function: 
```
$ docker --version
podman version 3.3.1
```


### Environment specific data

Installation data is contained in the openshift-environments repository. The format of the repository/directory
is as follows:

```bash
environments
├── environment1
│   ├── groups
│   ├── group_vars
│   │   ├── all
│   │   │   ├── tls.yml
│   │   │   ├── vars.yml
│   │   │   ├── vault.yml
│   │   │   └── volumes.yml
│   │   ├── gpu.yml
│   │   ├── masters.yml
│   │   ├── nfsservers.yml
│   │   ├── node_lbs.yml
│   │   ├── node_masters.yml
│   │   ├── OSEv3
│   │   │   ├── vars.yml
│   │   │   └── vault.yml
│   │   └── ssd.yml
│   ├── hosts -> ../openstack.py
│   └── host_vars
├── openstack.py
└── environment2
    └...
```

Multiple environments are described here, all in their own subdirectory (here
environment1 and environment2, but the names can be whatever). You will need to
fill in the same data as would be filled in in cluster_vars.yml, except using
the standard Ansible group_vars and host_vars structure.

The roles of the files are:

- groups: inventory file describing host grouping
- group_vars: directory with config data specific to individual groups
- host_vars: directory with config data specific to individual hosts
- group_vars/all: config data relevant to all hosts in the installation
- masters/nfsservers/node_lbs/node_masters etc.: config data for specific
  host groups in the OpenShift cluster
- OSEv3: OpenShift installer config data
- openstack.py: dynamic inventory script for OpenStack provided by the
  Ansible project
- hosts: symlink to dynamic inventory script under environment specific
  directory
- vault.yml files: encrypted variables for storing e.g. secret keys

For initialize_ramdisk.yml to work, you will need to populate the following variables:

- ssh_private_key
- tls_certificate
- tls_secret_key
- tls_ca_certificate
- openshift_cloudprovider_openstack_auth_url
- openshift_cloudprovider_openstack_auth_url
- openshift_cloudprovider_openstack_username
- openshift_cloudprovider_openstack_domain_name
- openshift_cloudprovider_openstack_password
- openshift_cloudprovider_openstack_tenant_id
- openshift_cloudprovider_openstack_tenant_name
- openshift_cloudprovider_openstack_region

If you want to automate the process or repeat running single actions containerized, you
can create a vault password file and loopback mount it to the container so that
initialization playbook does not have to ask it interactively. There is a
script called `read_vault_pass_from_clipboard.bash` under the scripts directory
for doing this.

## Provisioning

Store the vault password on RAM disk using the
`read_vault_pass_from_clipboard.bash` script:

```bash
sudo scripts/read_vault_pass_from_clipboard.bash
```

To launch a shell in a temporary container for deploying environment 'oso-devel-singlemaster', run

```bash
# Linux version
sudo scripts/run_deployment_container.bash \
  -e oso-devel-singlemaster \
  -p /dev/shm/secret/vaultpass
```

On MacOS, the required secret file is located in different path (`/Volumes/rRAMDisk/secret/vaultpass`).

```bash
# Mac version
sudo scripts/run_deployment_container.bash \
  -e oso-devel-singlemaster \
  -p /Volumes/rRAMDisk/secret/vaultpass
```

Run site.yml to provision infrastructure on OpenStack and install OpenShift on this infrastructure:

```bash
cd poc/playbooks
ansible-playbook site.yml
```

Single step alternative for non-interactive runs:

```bash
cd ~/git/poc
sudo scripts/run_deployment_container.bash -e oso-devel-singlemaster -p /dev/shm/secret/vaultpass \
  ./run_playbook.bash site.yml
```

If you run the above from terminal locally while developing, add '-i' option to attach the terminal
to the process for the color coding and ctrl+c to work.



### Usage in a GitLab pipeline

The poc-deployer image can be used as the Docker image for a GitLab runner in .gitlab-ci.yml:

```yaml
image:
  name: docker-registry.rahti.csc.fi/rahti-docker-prod/poc-deployer:v1.0.0
```

Here is an example of a job that makes use of the poc-deployer image:

```yaml
deploy_ci_openshift_job:
  stage: ci_env_deploy
  variables:
    ENV_NAME: oso-ci-singlemaster
  except:
    - schedules
  script:
    - ./run_playbook.bash site.yml
  environment:
    name: oso-ci
```

### Heat stack updates

Normally only base stack is updated when running site or provisioning playbooks. In case you need to
update an existing Heat stack, set the corresponding variable (allow_heat_stack_update_*) to true. See
the description for provision.yml for a list of variables

Here is how you would update the stack for ssdnodes, e.g. for scale up purposes:

```bash
ansible-playbook site.yml -e '{allow_heat_stack_update_node_groups: ["ssdnode"]}'
```

Note that some configuration changes like VM image may result in all VMs in the
stack to be reprovisioned. Be careful and test with non-critical resources first.

## Playbooks

### init_ramdisk.yml

- extracts environment specific data to ramdisk for further installation steps

### site.yml

- aggregates all installation and scaleup steps into a single playbook

### deprovision.yml

- used to tear the cluster resources down

### provision.yml

- takes care of creating the resources in cPouta project
  - VMs
  - volumes
  - security groups
  - networks
- uses OpenStack Heat for provisioning
- always updates heat stack for base resources (bastion, networks, basic security groups, ...)
- optionally updates other Heat stacks. The variables are:
  - allow_heat_stack_update_node_groups: list of node groups to update
  - allow_heat_stack_update_cluster: update masters and load balancers
  - allow_heat_stack_update_etcd: update etcd VMs
  - allow_heat_stack_update_glusterfs: update glusterfs hosts

### pre_install.yml

- adds basic tools
- configures
  - persistent storage
  - docker storage by creating docker-storage-setup configuration
  - internal DNS
- docker installation is left to openshift-ansible by default, 'docker_package_name'
  and 'docker_package_state' variables can be set to manually override this and install
  docker during pre-install

### post_install.yml

- creates persistent volumes for OpenShift
- puts the registry on persistent storage
- customizes the default project template
- optionally deploys default www page and Prometheus based monitoring

### scaleup.yml

*scaleup.yml* runs OpenShift Ansible scaleup playbooks. In 3.7 and older, 
the playbooks in openshift-ansible are

- playbooks/byo/openshift-master/scaleup.yml
- playbooks/byo/openshift-node/scaleup.yml
- playbooks/byo/openshift-etcd/scaleup.yml

In 3.9 and newer, the playbooks are

- playbooks/openshift-master/scaleup.yml
- playbooks/openshift-node/scaleup.yml
- playbooks/openshift-etcd/scaleup.yml

### scaledown_nodes.yml

**Note: you can only remove nodes from the end of the compute nodes stack when
scaling down - not from the middle or from the start.**

This playbook can be used to remove nodes from the cluster. You need to provide
a list of nodes to remove as a variable called `nodes_to_remove`, e.g.:

```yaml
nodes_to_remove:
  - oso-devel-ssdnode-3
  - oso-devel-ssdnode-4
```

Put the nodes to remove in a file. Let's put the file in
`/tmp/nodes_to_remove.yaml` in the deployment container:

```bash
vi /tmp/nodes_to_remove.yaml
```

Note that the deployment container has vi but no other editors. You can also
edit the file outside the deployment container if you then put it in a location
that is also mounted on the deployment container (e.g. `~/poc/playbooks` in the
container).

Also set the new number of the type of node you are scaling down by setting
the corresponding Heat resource group size parameter. Nodes are always removed
from the end of the resource group, so if you have four nodes now and want to
remove the last two, put nodes 3 and 4 into nodes_to_remove and set the resource
group size to 2.

You'll also need to set the correct parameters to allow Heat to update the
correct node stacks. In this example we allow Heat to update the "ssdnode" stack
by setting `allow_heat_stack_update_node_groups` accordingly. Set this variable
so that all the stacks with nodes to remove are included.

Once the preparations are done, you can run this to scale the nodes down:

```bash
cd ~/poc/playbooks
ansible-playbook scaledown_nodes.yml \
-e '{allow_heat_stack_update_node_groups: ["ssdnode"]}' \
-e @/tmp/nodes_to_remove.yaml
```

This might fail because one or more of the nodes had pods with local data. We
default to failing if this is the case to be on the safe side, but there is an
option that can be set to also delete local data. If you're sure pod local data
can be removed, run this command instead:

```bash
cd ~/poc/playbooks
ansible-playbook scaledown_nodes.yml \
-e '{allow_heat_stack_update_node_groups: ["ssdnode"]}' \
-e @/tmp/nodes_to_remove.yaml \
-e delete_local_data=1
```

## Deprovisioning

From the deployment container, run

```bash
cd poc/playbooks
ansible-playbook deprovision.yml
```

Partial deletes are not currently supported, as the Heat stack update process
does not nicely replace missing resources. This may be possible in newer
OpenStack versions.

## Recovery

See [docs/full_restore.md](docs/full_restore.md) and
[docs/recover_single_vm_failure.md](docs/recover_single_vm_failure.md) for recovering from failures.

## Security groups

- common
  - applied to all VMs
  - allow ssh from bastion
- infra
  - applied for all infrastructure VMs (masters, etcd, lb)
  - allow all traffic between infra VMs
- masters
  - applied to all masters
  - allow incoming DNS from common
- nodes
  - applied for all node VMs
  - allow all traffic from infra SG
- lb
  - applied to load balancers/router VMs
  - allow all traffic to router http, https and api port
- nfs
  - applied to NFS server
  - allow nfs v4 from all VMs
