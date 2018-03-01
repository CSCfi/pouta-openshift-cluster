#!/usr/bin/env bash

# Read a vault pass from the clipboard and write it to a file on RAM disk. The
# access rights for the file are set so that it is accessible from a deployment
# container.

# Create a directory on ramdisk
mkdir -p /dev/shm/secret
chmod 750 /dev/shm/secret

# Prepare the password file
touch /dev/shm/secret/vaultpass
chmod 640 /dev/shm/secret/vaultpass
chcon -Rt svirt_sandbox_file_t /dev/shm/secret/vaultpass

# Change the group to match the gid of user 'deployer' in the container
sudo chgrp -R 29295 /dev/shm/secret

echo "Make sure the vault pass is in the clipboard, then press enter."
read

# Populate the password from a password manager with xclip:
xclip -o > /dev/shm/secret/vaultpass

# Clear the vault pass from the clipboard
echo -n "empty" | xclip -selection clipboard
echo -n "empty" | xclip -selection primary
echo -n "empty" | xclip -selection secondary

echo "Wrote the vaultpass onto RAM disk and cleared it from the clipboard."
echo "Happy deployments!"
