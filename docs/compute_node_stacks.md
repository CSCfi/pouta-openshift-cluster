# Compute node stacks

You can create multiple different types of compute node stacks of different
sizes and configurations. This is useful if e.g. you want to have a separate
stack of GPU nodes or some other special node type. The `provisioning.yml`
playbook will create these stacks dynamically based on data in the
`compute_node_groups` variable. Stack updates can also be limited to only a
specific group of compute nodes using the `allow_heat_stack_update_node_groups`
variable (see README.md).

## Specifying multiple compute node stacks

Here is an example of how the `compute_node_groups` variable could be set:

```yaml
compute_node_groups:
  - stack_name: "ssdnode"
    heat_parameters:
      env_name: "{{ cluster_name }}"
      key_name: "{{ cluster_name }}"
      name_suffix: "ssdnode"
      compute_node_group_size: 4
      compute_node_image: "{{ default_base_image }}"
      network_prefix: "{{ openshift_network_prefix }}"
      compute_node_resource_group_identifier: "{{ node_ssd_resource_group_identifier }}"
      compute_node_flavor: "io.70GB"
      ansible_group_name: "ssd"
  - stack_name: "comp-io-s1"
    heat_parameters:
      env_name: "{{ cluster_name }}"
      key_name: "{{ cluster_name }}"
      name_suffix: "comp-io-s1"
      compute_node_group_size: 2
      compute_node_image: "{{ default_base_image }}"
      network_prefix: "{{ openshift_network_prefix }}"
      compute_node_resource_group_identifier: "{{ node_comp_io_s1_resource_group_identifier }}"
      compute_node_flavor: "io.70GB"
      ansible_group_name: "ssd"
      use_common_server_group: true
```

Here we set up two compute node stacks called `ssdnode` and `comp-io-s1`. The
size of the `ssdnode` stack is four nodes and the size of the `comp-io-s1` stack
is two nodes. Both types of nodes are placed in an Ansible group called `ssd` in
this case, though we could also use a different group for each type of compute
node.

For the first stack, we do not specify the parameter `use_common_server_group`,
which means that a dedicated server group will be created just for this compute
node stack (the default value for the parameter is "false"). For the second
compute node stack we do specify this parameter, which means a common compute
node server group created in the base stack and passed in as a parameter to the
compute node stack is used instead. Note that moving nodes in a stack between
the common and a dedicated server group will cause all servers in that stack to
be replaced with new ones. This will happen if you change the value of the
`use_common_server_group` for an existing stack.

Another difference worth mentioning is the
`compute_node_resource_group_identifier` parameter. This needs to be set to a
different value for each compute node stack to avoid IP collisions when creating
virtual machines. It is used to determine what IP address to use for each
machine. It is used in a template that determines the IP address of each node.
