# Configure auth providers

## Preface

This document describes the steps to configure authentication sources. See 
[OpenShift documentation on configuring authentication](https://docs.openshift.org/latest/install_config/configuring_authentication.html)

## Common variables

All auth provider methods support setting the method of mapping identities to users. See 
[OpenShift docs on mapping identities to users](https://docs.openshift.org/latest/install_config/configuring_authentication.html#mapping-identities-to-users).
The variables for controlling the mapping method are prefixed with the auth provider type, and are as follows:

- local_auth_mapping_method 
- github_auth_mapping_method
- gitlab_auth_mapping_method
- ldap_auth_mapping_method

The default value for all auth providers is 'claim'.

## Using local htpasswd file

OpenShift can use an htpasswd file on master hosts as identity source. To populate this during installation, set 
'openshift_master_htpasswd_users' to a dict containing htpasswd entries. You probably want to store the
actual value of the dict in Ansible Vault file and retrieve the value by referencing the vaulted variable, e.g.
```yaml
openshift_master_htpasswd_users: "{{ openshift_master_htpasswd_users_vault }}"
```

The format of the variable is as follows:
```yaml
openshift_master_htpasswd_users_vault:
  user1: "$apr1$..."
  user2: "$apr1$..."
```
where each user is a key and the value is the htpasswd file hash for the password. 

## Configuring GitHub

TBA

## Configuring GitLab

TBA

## Configuring LDAP

See [OpenShift docs on configuring LDAP](https://docs.openshift.org/latest/install_config/configuring_authentication.html#LDAPPasswordIdentityProvider)
info on the configuration values and [configuration task in POC](/playbooks/roles/openshift_auth_providers/tasks/main.yml) 
for value mapping details.

The following values are taken from Ansible inventory variables: 

- ldap_auth_provider_name
  - maps to 'name' in config
  - unique name for the provider, also visible in UI login page

- ldap_bind_account_dn
  - maps to 'bindDN' in config
  - DN for the user for connecting to LDAP

- ldap_bind_account_password
  - maps to 'bindPassword' in config
  - DN for the user for connecting to LDAP

- ldap_user_query
  - maps to 'url' in config  
  - query string for obtaining the users

- ldap_attribute_map
  - maps to 'attributes' in config
  - a dictionary mapping LDAP entries to OpenShift user attributes

### Note on network access and firewalls on OpenStack

The route for outgoing traffic in OpenStack depends on whether the source VM has a public IP or not. Therefore, the
source address for the queries executed on masters can be either the master's floating IP (if it has one) or the 
IP of the OpenStack router associated with the cluster network. Also note that in the latter case traffic from customer
PODs will originate from the same IP.
