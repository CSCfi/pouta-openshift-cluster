#!/usr/bin/env bash

# Read a vault pass from the clipboard and write it to a file on RAM disk. The
# access rights for the file are set so that it is accessible from a deployment
# container.


# Check the OS
OS="$(uname -s)"

case "${OS}" in
    Darwin*)
        # Create a 10mb RAM disk if it doesn't exist
        if [ ! -d "/Volumes/rRAMDisk" ]; then
            dev=$(hdiutil attach -nomount ram://$((20480)))
            diskutil eraseVolume HFS+ rRAMDisk $dev
        fi
        disk='/Volumes/rRAMDisk'
        ;;
    Linux*)
        disk='/dev/shm'
esac

# Create a directory on ramdisk
mkdir -p $disk/secret
chmod 750 $disk/secret

# Prepare the password file
touch $disk/secret/vaultpass
chmod 640 $disk/secret/vaultpass

# Change the group to match the gid of user 'deployer' in the container
sudo chgrp -R 29295 $disk/secret
echo "Make sure the vault pass is in the clipboard, then press enter."
read

case "${OS}" in
    Darwin*)
        # Populate the password from a password manager with pbpaste:
        pbpaste > /Volumes/rRAMDisk/secret/vaultpass

        # Clear the vault pass from the clipboard
        pbcopy < /dev/null
        ;;
    Linux*)
        # SELinux setting
        chcon -Rt svirt_sandbox_file_t $disk/secret/vaultpass

        # Populate the password from a password manager with xclip:
        xclip -o > /dev/shm/secret/vaultpass

        # Clear the vault pass from the clipboard
        echo -n "empty" | xclip -selection clipboard
        echo -n "empty" | xclip -selection primary
        echo -n "empty" | xclip -selection secondary
esac

echo "Wrote the vaultpass onto RAM disk and cleared it from the clipboard."
echo "Happy deployments!"
