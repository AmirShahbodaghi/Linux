Cgroups and Namespaces

Cgroups allow administrators to limit and distribute resources among different groups of processes. They do this by grouping processes together and then applying resource limits to those groups. This can be used to ensure that no one process or group of processes consumes too many resources, which can lead to performance problems or even system instability.

Namespaces create isolated environments for processes, separating them from the host system and other processes. This can be used to protect processes from each other and to prevent them from interfering with each other's resources.

Config Cgroup:

1. Configuring cgroups
cgroups allow you to limit and allocate resources (CPU, memory, disk I/O) for processes.

Step 1: Enable cgroups (if not enabled)
Check if cgroups are mounted:

bash
Copy
Edit
mount | grep cgroup
If not, manually mount them:

bash
Copy
Edit
mkdir -p /sys/fs/cgroup/cpu /sys/fs/cgroup/memory
mount -t cgroup -o cpu none /sys/fs/cgroup/cpu
mount -t cgroup -o memory none /sys/fs/cgroup/memory
Step 2: Create a cgroup
bash
Copy
Edit
mkdir /sys/fs/cgroup/cpu/mygroup
mkdir /sys/fs/cgroup/memory/mygroup
Step 3: Assign CPU limits
Limit CPU usage to 50%:

bash
Copy
Edit
echo 50000 > /sys/fs/cgroup/cpu/mygroup/cpu.cfs_quota_us
echo 100000 > /sys/fs/cgroup/cpu/mygroup/cpu.cfs_period_us
Step 4: Assign Memory limits
Limit memory usage to 256MB:

bash
Copy
Edit
echo 268435456 > /sys/fs/cgroup/memory/mygroup/memory.limit_in_bytes
Step 5: Add a process to the cgroup
Find the PID of a process:

bash
Copy
Edit
ps aux | grep myprocess
Add it to the cgroup:

bash
Copy
Edit
echo <PID> > /sys/fs/cgroup/cpu/mygroup/cgroup.procs

