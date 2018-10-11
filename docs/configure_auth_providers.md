# Configure auth providers

## Preface

This document describes the steps to configure authentication sources. See 
[OpenShift documentation on configuring authentication](https://docs.okd.io/latest/install_config/configuring_authentication.html)

## Common variables

All auth provider methods support setting the method of mapping identities to users. See 
[OpenShift docs on mapping identities to users](https://docs.okd.io/latest/install_config/configuring_authentication.html#identity-providers_parameters).
The variables for controlling the mapping method are prefixed with the auth provider type, and are as follows:

- local_auth_mapping_method 
- github_auth_mapping_method
- gitlab_auth_mapping_method
- ldap_auth_mapping_method

The default value for all auth providers is 'claim'.

OpenID Connect auth provider supports setting up multiple providers and the mapping method can be selected per
provider. See the chapter for OpenID Connect below.  

## Note on identity provider names

It is important to pay attention to selecting a good name for your identity provider. The names are visible to end 
users in the Web UI login page. They also end up in OAuth callback URLs, thus changing them could be a hassle.

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

See [OpenShift docs on configuring GitHub auth](https://docs.okd.io/latest/install_config/configuring_authentication.html#GitHub)
for instructions and [configuration task in POC](/playbooks/roles/openshift_auth_providers/tasks/main.yml) 
for value mapping details. 

Basically the process involves:
- create an Organization in GitHub (or use an existing one, admin rights needed)
  - for 'Authorization callback URL', use https://[CLUSTER_API_HOSTNAME]:8443/oauth2callback/GitHub
- create an OAuth application the organization
- copy Client ID and Client Secret into inventory, see below.

Here is a configuration example. The actual values provided by GitHub OAuth Application registration process are placed 
in a vault file and referred to here:

```yaml
deploy_github_auth: true
github_oauth_client_id: "{{ github_oauth_client_id_vault }}"
github_oauth_client_secret: "{{ github_oauth_client_secret_vault }}"
github_allowed_auth_orgs: "{{ github_allowed_auth_orgs_vault }}"
```

## Configuring GitLab

TBA

## Configuring LDAP authentication and group syncing


### LDAP authentication

See [OpenShift docs on configuring LDAP](https://docs.okd.io/latest/install_config/configuring_authentication.html#LDAPPasswordIdentityProvider)
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

### Syncing groups from LDAP 

See [OpenShift docs on synchronizing groups from LDAP](https://docs.okd.io/latest/install_config/syncing_groups_with_ldap.html)

The sync process in POC can be enabled by setting *enable_ldap_group_sync* to true. The basic configuration is taken 
from LDAP auth provider settings. In addition, *ldap_group_sync_schema_params* variable has to be set to match the 
respective configuration block for LDAP server schema (rfc2307, activeDirectory or augmentedActiveDirectory) as 
described in the OpenShift documentation.

See [configuration task in POC](/playbooks/roles/openshift_auth_providers/tasks/main.yml) and 
[openshift_master role](/playbooks/roles/openshift_master/tasks/main.yml) for technical details.


### Note on network access and firewalls on OpenStack

The route for outgoing traffic in OpenStack depends on whether the source VM has a public IP or not. Therefore, the
source address for the queries executed on masters can be either the master's floating IP (if it has one) or the 
IP of the OpenStack router associated with the cluster network. Also note that in the latter case traffic from customer
PODs will originate from the same IP.

## Configuring OpenID Connect

See [OpenShift docs on configuring OpenID Connect](https://docs.okd.io/latest/install_config/configuring_authentication.html#OpenID)
info on the configuration values and [configuration task in POC](/playbooks/roles/openshift_auth_providers/tasks/main.yml) 
for value mapping details.

Basically the process involves:
- Create a client in your OIDC provider
- Set up the inventory (see an example below)
  - Client ID
  - Client Secret
  - URLs for authorize, token and user_info endpoints
  - Mapping of claims
  - Extra scopes, if needed
  
POC supports setting up multiple OpenID Connect providers. Here is an example of vaulted configuration for a single
provider:  
```yaml
openid_connect_auth_providers_vault:
  - name: "OIDC example"
    mapping_method: "claim"
    client_id: "8cfabffc-0de8-4c77-99ee-81fdea3acd53"
    client_secret: "1ac6028d126c782fa204d957d3ea06978b346e68640e47a4"
    authorize_url: "https://example.org/oauth/authorization"
    token_url: "https://example.org/oauth/token"
    user_info_url: "https://example.org/openid/userinfo"
    claims:
      id:
      - sub
      preferredUsername:
      - email
      name:
      - name
      email:
      - email
    extra_scopes:
      - email
      - profile
```
