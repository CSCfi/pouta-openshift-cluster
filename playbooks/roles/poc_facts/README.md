# Ansible role poc_facts

This role sets facts used by POC in further steps of deployment. 

## Setting environment variables based on context 

File: environment_context.yml

Sets host variables to localhost based on current environment.

### Input/Output

Sources a directory in Ansible inventory format and sets variables based on 
environment name and installation type (single/multimaster). It uses
Ansible 'include_vars' as the actual mechanism.

http://docs.ansible.com/ansible/latest/include_vars_module.html
 
## Generate IP address whitelists

File: access_whitelists.yml 

Generates IP address whitelists for security group rules and route whitelisting.

### Input

IP address generation will take `common_ip_address_data` and 
`extra_ip_address_data` arrays as input for generating the whitelists. Every
entry in the array has the following keys:

Key             | Description
----------------| -----------
address         | single IP or CIDR
assign_to       | optional server to assign this floating IP to. 'address' needs to be a single IP in this case.
allow_access_to | optional array of access list targets (see below)  
comment         | optional comment for the entry

Valid allow_access_to targets:

Target     | Description
-------    | -----------
monitoring | monitoring API route whitelist 
heketi     | storage provisioning API route whitelist
api        | OpenShift API port sec group rule
lb         | OpenShift application traffic sec group rule
bastion    | bastion firewall access

Here is an example of the expected structure for IP address data:
```yaml
common_ip_address_data:
  - address: "10.0.0.1"
    assign_to: "{{ cluster_name }}-master-3"
    allow_access_to:
      - monitoring
      - api
      - lb
      - heketi
  - address: "{{ openshift_router_ip }}"
    allow_access_to:
      - heketi
      - monitoring
  - address: "192.30.252.0/22"
    comment: "GitHub webhooks CIDR 1"http://docs.ansible.com/ansible/latest/include_vars_module.html
    allow_access_to:
      - api
```

### Output

The following facts are set:

Variable                        | Description 
------------------------------  | -----------
ip_address_data                 | union of common and extra ip data 
ip_address_data_for_whitelists  | ip data entries that include 'allow_access_to'
ip_whitelist_bastion            | list of IPs with bastion access 
ip_whitelist_monitoring         | list of IPs with monitoring access
ip_whitelist_api                | list of IPs with api access
ip_whitelist_heketi             | list of IPs with heketi access
ip_whitelist_lb                 | list of IPs with lb access
