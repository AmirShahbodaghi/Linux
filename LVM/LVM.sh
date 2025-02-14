#!/bin/bash

# Define variables
VG_NAME="my_vg"
LV_NAME="my_lv"
MOUNT_POINT="/mnt/lvm_storage"
DISKS=("/dev/sdb" "/dev/sdc")

# Install LVM if not installed
echo "Installing LVM..."
sudo apt update && sudo apt install -y lvm2

# Create Physical Volumes
echo "Creating Physical Volumes..."
sudo pvcreate ${DISKS[@]}

# Create Volume Group
echo "Creating Volume Group..."
sudo vgcreate $VG_NAME ${DISKS[@]}

# Create Logical Volume
echo "Creating Logical Volume..."
sudo lvcreate -L 50G -n $LV_NAME $VG_NAME

# Format the LV
echo "Formatting Logical Volume..."
sudo mkfs.ext4 /dev/$VG_NAME/$LV_NAME

# Mount the LV
echo "Creating mount point..."
sudo mkdir -p $MOUNT_POINT
sudo mount /dev/$VG_NAME/$LV_NAME $MOUNT_POINT

# Update fstab for auto-mounting
echo "Updating /etc/fstab..."
echo "/dev/$VG_NAME/$LV_NAME  $MOUNT_POINT  ext4  defaults  0  2" | sudo tee -a /etc/fstab

# Display status
echo "LVM Setup Complete!"
sudo lvdisplay
