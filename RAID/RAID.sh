#!/bin/bash

# Define the RAID device and disk list
RAID_DEVICE="/dev/md0"
DISKS=("/dev/sdb" "/dev/sdc" "/dev/sdd" "/dev/sde")

# Install mdadm if not installed
echo "Installing mdadm..."
sudo apt update && sudo apt install -y mdadm

# Ensure disks are not mounted or in use
echo "Stopping any existing RAID setup..."
sudo mdadm --stop $RAID_DEVICE
sudo mdadm --zero-superblock ${DISKS[@]}

# Create RAID 10 array
echo "Creating RAID 10 array..."
sudo mdadm --create --verbose $RAID_DEVICE --level=10 --raid-devices=4 ${DISKS[@]}

# Wait for RAID to initialize
sleep 5

# Verify RAID setup
echo "Verifying RAID setup..."
cat /proc/mdstat

# Format the RAID array with ext4 filesystem
echo "Formatting RAID with ext4..."
sudo mkfs.ext4 $RAID_DEVICE

# Create mount point and mount RAID array
MOUNT_POINT="/mnt/raid10"
echo "Creating mount point at $MOUNT_POINT..."
sudo mkdir -p $MOUNT_POINT
sudo mount $RAID_DEVICE $MOUNT_POINT

# Add to fstab for automatic mounting
echo "Updating /etc/fstab..."
echo "$RAID_DEVICE  $MOUNT_POINT  ext4  defaults,nofail  0  2" | sudo tee -a /etc/fstab

# Save RAID configuration
echo "Saving RAID configuration..."
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u

# Display final RAID status
echo "RAID 10 setup complete!"
sudo mdadm --detail $RAID_DEVICE
