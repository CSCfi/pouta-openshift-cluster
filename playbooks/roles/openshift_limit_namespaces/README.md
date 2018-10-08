# Limit the number of self-provisioned projects per user

This role adds an Openshift project number limit policy under the master configuration file.
It uses the ProjectRequestLimit admission control plug-in which takes a list of user label 
selectors and the associated maximum project requests.

For selector namespace_quota=unlimited, no maxProjects is specified. This means that users 
with this label will not have a maximum of project requests.

## Default values
Currently, the default limit is 5 Openshift projects per user.

## How to override
In order to override the default project limit, the label **namespace_quota=unlimited** needs 
to be set on the user Openshift object:
```bash
oc label user $USER_NAME namespace_quota=unlimited
```
