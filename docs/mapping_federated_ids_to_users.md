# Mapping federated identities to user accounts

There are many ways to manage multiple identity sources in OpenShift. There are
some caveats in all of these methods that we will try to list in this document.
We will also describe one method for mapping federated identities to user
accounts in OpenShift.

## External documentation

Much of this document is based on the following documentation page in the
official OpenShift documentation:

[Configuring Authentication and User Agent](https://docs.openshift.org/latest/install_config/configuring_authentication.html)

## Basic concepts

In OpenShift, there are objects that represent:

  * User accounts (`oc get users`)
  * Identities (`oc get identity`)
  * User to identity mappings (`useridentitymapping` - get operation not supported)

User accounts are *authorized* to access certain data and perform certain
operations in the cluster. For a user to get access to a user account they must
be able to *authenticate* themselves with an *identity provider*. The identity
provider passes on the user's identity to OpenShift. If OpenShift is able to map
that identity to a user account, then the user gets access to that user account.

There are several methods for OpenShift to do the mapping:

  * **claim** - A new user account is automatically created if a user is able
    to authenticate with an identity provider that is connected to OpenShift.
    The user logging in *claims* the user name that comes with the identity.
  * **lookup** - OpenShift will not create any resources during login attempts.
    Instead, an admin has to explicitly map user accounts to specific
    specific identities beforehand. OpenShift will do a *lookup* from this
    pre-created mapping when deciding whether to authorize a user.
  * **generate** - If an identity provider's preferred user name has already
    been taken by another identity from a different identity provider,
    *generate* a new user account instead and give it a similar but not
    identical name.
  * **add** - If an identity provider's preferred user name has already
    been taken by another identity from a different identity provider, *add* the
    new identity to the existing user account.

## Caveats

There are several scenarios in which a user gets access to an account that is
not theirs or a user is not able to login because someone else has already
claimed their user name. We will list some of those scenarios here.

It is possible that some user name belongs to user A in one identity provider
but user B in another identity provider. This is potentially a problem for the
*claim*, *add* and *generate* mapping methods.

The add mapping method should only be used when *all* the identity provider have
the exact same set of users. For example, if user A has the user name "userA"
with identity provider A, they must also have that user name in identity
provider B if both are to be connected to the same OpenShift cluster. At the
very least, user A *must* be the only one who can have a user account named
"userA" on identity provider B. If this is not the case, then it is possible
that user B will be able to get user name "userA" on identity provider B and
then impersonate user A on OpenShift.

The *claim* mapping method has a similar issue. If multiple users share the same
user account on different identity providers, then only the first of them will
be able to get access to OpenShift. That first user will have *claimed* that
user name and nobody else will be able to use that same user name, even if they
legitimately have that user name on a different identity provider.

The *generate* mapping method can lead to the same user getting multiple
different user accounts on the system. It can also cause issues with LDAP group
sync since that process expects user names to be identical between OpenShift and
the LDAP identity provider. Conversely to the add and the claim mapping methods,
the generate mapping method should only be used for identity providers that have
a completely *different* set of users compared to other identity providers in
the system.

Out of all the mapping methods, *lookup* allows an administrator to explicitly
specify which identities should be mapped with which user accounts. This is
potentially safer than using the other mapping methods, as the admin has full
control over how identities are mapped. However, this requires some extra work
as the mapping must be created and then maintained. It is possible to make a
mistake in creating the mapping that will lead to a user getting access to
somebody else's user account.

## Mapping a federated identity to a user account

Since running a user database is a lot of work, this is best left to someone
other than the OpenShift operators. Typically a company LDAP server is used for
this purpose. The simplest thing to do is to use this LDAP server as an
authoritative source of user account information where all users of OpenShift
must have access. Federated identities are then mapped to the LDAP accounts of
users and the federations are only used as an additional authentication source.
It is also possible to provision new user accounts based solely on federated
identities, but this requires additional work in managing authorizations. In
this document we will only cover the simple case where users are required to
have an LDAP (or perhaps AD) account.

Academic identity federations usually have available an attribute called
*eduPersonPrincipalName* for all users. This attribute consists of the user's
preferred user name and their home organisation in the form
*username@homeorg.org*. Since this attribute is widely available and should be
the same between different federations, it is a good basis for mapping OpenShift
user accounts to federated identities. This is best done on the LDAP server
using additional attributes added to a user account. This way the OpenShift
operators only need to worry about setting up the mapping in OpenShift between
user account and federated identities and not e.g. figuring out who a given
eduPersonPrincipalName belongs to.

Once information about user names and their associated is available, the
OpenShift operators can create mappings from user names to federated identities.
This is most likely done by a script of some sort, but here we document the
manual process as an example. You can also find a description of this in the
official OpenShift documentation linked above. Here we describe a slightly
modified version of the process that takes into account the assumptions we've
made so far: that there is an external LDAP server and that that LDAP server is
also the source of mapping information for federated identities and that the
mappings are based on eduPersonPrincipalName.

We are going to assume that the *lookup* mapping method is used here, since we
have outsourced the mapping to the operators of the LDAP server. Using any other
mapping method would mean bypassing the LDAP server as the authoritative source
of this mapping information and would mean some of the *authorization*
responsibility would fall on the OpenShift operators as assumptions about
mappings would be made.

Users are created via LDAP sync, so we don't need to create them. We will only
map identities to users created via LDAP.

We first need to create an identity object based on a federated identity in
OpenShift. This needs to match with what we get from the federation. In our case
this would be:

```bash
oc create identity <identity-provider>:<eduPersonPrincipalName>
```

This is then added to a user account:

```bash
oc create useridentitymapping <identity-provider>:<eduPersonPrincipalName> <user-account-from-ldap>
```

This is done for all user accounts that also have a federated identity
associated with them. The information about what to add is retrieved from LDAP
attributes.

We also need to remove identities if they are no longer mapped to any user
account. This can be done like so:

```bash
# First remove the mapping to a user
oc delete useridentitymapping <identity-provider>:<eduPersonPrincipalName>
# Then remove the identity altogether
oc delete identity <identity-provider>:<eduPersonPrincipalName>
```

Note that order is important here. If you first remove the identity, then you
won't be able to use the other command to remove the mapping anymore.
