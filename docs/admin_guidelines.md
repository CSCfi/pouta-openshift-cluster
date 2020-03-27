# Admin Credential Holders

This is a list of admin credential holders on the pouta production systems. Any changes to this list needs to be approved by the group manager of the team running the service. The available accounts should be reviewed against this list.

In practice openstack admin credentials are granted by project_2000651 membership. Please make a ticket to idm-support for changes, as the SUI admin sub-account process does not work as intended.

System access by code automation.

## Access to the vault key of Rahti environments 

*Person* | *Reason*
--- | ---
João da Silva | System administrator 
Ahsan Feroz | System administrator
Kalle Happonen | System administrator / group manager
Álvaro González | End-user support
Olli Tourunen | Backup system administrator

## Access to the vault key of Valinor environments

*Person* | *Reason*
--- | ---
João da Silva | System administrator
Ahsan Feroz | System administrator
Kalle Happonen | System administrator / group manager
Olli Tourunen | Backup system administrator

## Access to the Rahti OpenStack environment

*Person* | *Reason* | *Comment*
--- | --- | ---
m2m_rahti | Automation account | All users with the vault key can use this account
Ahsan Feroz | System administrator |
João da Silva | System administrator |

## Access to the Valinor OpenStack environment

*Person* | *Reason* | *Comment*
--- | --- | ---
m2mvardarahti | Automation account | All users with the vault key can use this account
Ahsan Feroz | System administrator |
João da Silva | System administrator |

## Process for adding or removing admin accounts

1. Get preliminary approval from the group manager.
2. Create a branch of this repo
3. Add changes to admin accounts in the sections.
4. Do a merge request, assing the group manager as the reviewer
5. Get group manager to merge the MR.
6. Deploy the changes.

# Admin credential guidelines

## Purpose

Everybody makes mistakes. The purpose of these guidelines is to reduce impact of operational mistakes and guarantee a level of commonly agreed upon security practices when performing system administration tasks. This document complements the CSC guidance (https://wiki.csc.fi/Security) when it comes to administering the Rahti services.

Follow CSC's instructions in https://rahti.csc.fi/agreements/terms_of_use/ and https://www.csc.fi/general-terms-of-use

## General

Laptops in this context means any computer that is used to administer the Rahti systems, regardless if it's actually a laptop or a workstation.

There are common security practices to be taken into account.

   * Your laptop must be secured with a password, and must require a password to unlock.
   * Your laptop must always be locked when it is unattended.
   * If you leave your laptop unattended outside the offices (e.g. hotel room, airport security, etc.), power it off completely. Otherwise disk encryption keys remain in memory.
   * You may not store any secrets (passwords, keys) unencrypted on your laptop.
   * You may not store any secrets which give you admin access to the systems on your personal devices, or cloud services e.g. google drive, even encrypted. The exception is to have a backup of your encrypted data on a non-internet connected device, e.g. a USB hard-disk for backups.
   * You may never transmit secrets (passwords, secret keys) in plain text over the network.
   * The passwords used for administrative access must be unique, and not in use anywhere else.
   * If you need to run a destructive command on the command line (deprovision a production server, remove customer namespace, etc.), remove it from your command line history. The recommended way to do is
      * history
      * history -d linenumber
   * Some tools may require you to enter a password on the command line. Always clear the history of passwords.
   * Never run commands that may delete user data unless you are sure what the outcome of the command is.
   * If you are unsure about running a potentially destructive command, verify with a colleague rather than guessing it will be ok.
   * Never access a customers pods or data. The exceptions are:
      * The data available on the pod logs, and you are debugging that pod.
      * You're debugging a very difficult problem, and get explicit written permission from the customer (as an e-mail to the ticket).
      * There is a security incident ongoing, and you have to access that specific pod or data to shut down/limit the incident. 
