 Why Use LVM?
LVM overcomes the limitations of traditional partitioning systems by providing: ✅ Flexible resizing (expand/shrink partitions without data loss).
✅ Multiple disk management (combine multiple disks into a single volume).
✅ Snapshots (create backups without downtime).
✅ Thin provisioning (allocate storage dynamically).

LVM Architecture
LVM consists of three main layers:

1️⃣ Physical Volumes (PV)
These are actual hard drives or partitions (e.g., /dev/sdb).
Created using pvcreate.
2️⃣ Volume Groups (VG)
Combines multiple physical volumes into a single storage pool.
Created using vgcreate.
3️⃣ Logical Volumes (LV)
Virtual partitions created from the volume group.
Act as traditional partitions (formatted and mounted).
Created using lvcreate.

LVM Workflow
📌 Example Setup (Assume we have /dev/sdb and /dev/sdc as new disks):

1️⃣ Initialize the disks as Physical Volumes (PV)

bash
Copy
Edit
sudo pvcreate /dev/sdb /dev/sdc
✅ Marks them as usable by LVM.

2️⃣ Create a Volume Group (VG)

bash
Copy
Edit
sudo vgcreate my_vg /dev/sdb /dev/sdc
✅ Combines /dev/sdb and /dev/sdc into my_vg.

3️⃣ Create a Logical Volume (LV)

bash
Copy
Edit
sudo lvcreate -L 50G -n my_lv my_vg
✅ Creates a 50GB logical volume named my_lv.

4️⃣ Format the Logical Volume

bash
Copy
Edit
sudo mkfs.ext4 /dev/my_vg/my_lv
✅ Formats it with the ext4 filesystem.

5️⃣ Mount the Logical Volume

bash
Copy
Edit
sudo mkdir /mnt/lvm_storage
sudo mount /dev/my_vg/my_lv /mnt/lvm_storage
✅ The logical volume is now accessible.

6️⃣ Make Mount Permanent (Optional) Edit /etc/fstab:

bash
Copy
Edit
echo "/dev/my_vg/my_lv  /mnt/lvm_storage  ext4  defaults  0  2" | sudo tee -a /etc/fstab
✅ Ensures it mounts automatically on boot.

Advanced LVM Features
🟢 Resizing a Logical Volume
Increase LV Size
bash
Copy
Edit
sudo lvextend -L +10G /dev/my_vg/my_lv
sudo resize2fs /dev/my_vg/my_lv
✅ Increases the LV size by 10GB and resizes the filesystem.

Decrease LV Size (Carefully)
bash
Copy
Edit
sudo umount /mnt/lvm_storage
sudo e2fsck -f /dev/my_vg/my_lv
sudo resize2fs /dev/my_vg/my_lv 30G
sudo lvreduce -L 30G /dev/my_vg/my_lv
sudo mount /dev/my_vg/my_lv /mnt/lvm_storage
✅ Reduces the LV to 30GB (requires unmounting).

🟢 Adding a New Disk to LVM
bash
Copy
Edit
sudo pvcreate /dev/sdd
sudo vgextend my_vg /dev/sdd
✅ Expands storage by adding /dev/sdd to my_vg.

