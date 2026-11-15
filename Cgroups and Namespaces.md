# Linux Cgroups and Namespaces

A practical guide to Linux resource management and process isolation, with cgroup v2, legacy cgroup v1, systemd, and namespace examples.

> **Safety:** Run the hands-on examples in a disposable Linux VM. Several commands require root and change resource limits or networking. Do not remount cgroup filesystems, move system services, or modify systemd-owned cgroups on a production host. Containers, WSL environments, and managed systems may restrict these operations.

## Table of contents

1. [Overview](#1-overview)
2. [Corrections to the original example](#2-corrections-to-the-original-example)
3. [Prerequisites and system inspection](#3-prerequisites-and-system-inspection)
4. [Cgroup v1 versus v2](#4-cgroup-v1-versus-v2)
5. [Recommended approach: systemd](#5-recommended-approach-systemd)
6. [Manual cgroup v2 laboratory](#6-manual-cgroup-v2-laboratory)
7. [Legacy cgroup v1 configuration](#7-legacy-cgroup-v1-configuration)
8. [Linux namespace types](#8-linux-namespace-types)
9. [Namespace laboratories](#9-namespace-laboratories)
10. [Using cgroups and namespaces together](#10-using-cgroups-and-namespaces-together)
11. [Monitoring and troubleshooting](#11-monitoring-and-troubleshooting)
12. [Security and operational considerations](#12-security-and-operational-considerations)
13. [Quick reference](#13-quick-reference)
14. [References](#14-references)

## 1. Overview

### What are cgroups?

**Control groups**, usually called **cgroups**, organize processes into hierarchical groups for resource accounting and control.

Depending on available kernel controllers, administrators can:

- Limit CPU time.
- Set memory limits and reclaim thresholds.
- Control block-device I/O bandwidth and relative priority.
- Restrict the number of tasks.
- Restrict CPU and NUMA-node placement.
- Monitor resource consumption for a workload.

Limits generally apply to the group's combined workload, not independently to every process. Ancestor limits also constrain descendants.

### What are namespaces?

**Namespaces** give processes separate views of particular kernel resources, such as process IDs, network interfaces, mount points, and hostnames.

A process belongs to one namespace of each supported type. Two processes can share a network namespace while having different mount namespaces, for example.

Namespaces do not automatically limit resource consumption or create a complete security sandbox.

### How do they differ?

| Feature | Cgroups | Namespaces |
|---|---|---|
| Main purpose | Resource control and accounting | Isolation of views and identities |
| Typical question | How much CPU or memory can this workload use? | Which processes, mounts, or network interfaces can it see? |
| Example | Limit a service to 256 MiB of memory | Give a process a separate network stack |
| Complete container by itself? | No | No |

Container runtimes combine these mechanisms with filesystem setup, capabilities, seccomp, and other security controls. Containers still share the host kernel.

## 2. Corrections to the original example

The original explanation is a useful starting point, but its commands need these qualifications:

1. **The commands are for cgroup v1.** Files such as `cpu.cfs_quota_us` and `memory.limit_in_bytes` are not the cgroup v2 interface.
2. **Do not blindly mount controllers.** First detect the existing setup. On systemd systems, the service manager normally mounts and manages cgroups.
3. **The process must join both v1 hierarchies.** Adding a PID only to the CPU group's `cgroup.procs` does not add it to the separate memory group.
4. **A CPU quota of 50% means half of one logical CPU's time.** It does not mean half of all CPU capacity on a multicore machine.
5. **268435456 bytes is 256 MiB**, not 256 decimal MB.
6. **`<PID>` is a placeholder, not literal shell syntax.** Use an actual PID or a variable such as `PID=12345`.
7. **Namespace isolation is resource-specific.** A network namespace does not isolate the filesystem, and a PID namespace does not set CPU or memory limits.
8. **Root redirection matters.** `sudo echo VALUE > FILE` usually fails because your current shell opens the file without sudo. Use a root shell or `printf '%s\n' VALUE | sudo tee FILE`.

## 3. Prerequisites and system inspection

### Requirements

- Linux with the relevant cgroup controllers and namespaces enabled.
- Bash for the command examples.
- `util-linux` tools such as `unshare`, `nsenter`, `findmnt`, and `lsns`.
- `procps` tools such as `ps`.
- `iproute2` for network namespace examples.
- Root access for most manual laboratories.
- Optional: `stress-ng` for controlled load testing.

Package names vary by distribution. Install tools using your distribution's package manager.

### Inspect the system

```bash
uname -r
findmnt -R /sys/fs/cgroup
stat -fc %T /sys/fs/cgroup
cat /proc/self/cgroup
cat /proc/cgroups
lsns
```

Interpretation:

- `cgroup2fs` at `/sys/fs/cgroup` indicates a v2 mount there.
- A v1 layout commonly has controller-specific mounts such as `/sys/fs/cgroup/cpu` or `/sys/fs/cgroup/cpu,cpuacct`.
- A hybrid layout has both v1 and v2 mounts. Inspect `findmnt`; do not assume controller paths.
- A typical v2 membership line is `0::/some/path`.
- `/proc/cgroups` lists kernel controller information; for v2 availability at a specific hierarchy level, inspect `cgroup.controllers` instead.

On a conventional unified v2 system:

```bash
cat /sys/fs/cgroup/cgroup.controllers
cat /sys/fs/cgroup/cgroup.subtree_control
```

`cgroup.controllers` lists controllers available for distribution to children. `cgroup.subtree_control` lists controllers currently enabled for children.

## 4. Cgroup v1 versus v2

| Property | v1 | v2 |
|---|---|---|
| Layout | Controllers can have separate hierarchies | Unified hierarchy |
| CPU bandwidth | `cpu.cfs_quota_us`, `cpu.cfs_period_us` | `cpu.max` |
| CPU relative weight | `cpu.shares` | `cpu.weight` |
| Memory hard limit | `memory.limit_in_bytes` | `memory.max` |
| Memory reclaim threshold | No direct equivalent to v2 `memory.high` | `memory.high` |
| Swap limit | Often combined memory+swap through `memory.memsw.limit_in_bytes` | Separate `memory.swap.max` |
| I/O control | `blkio.*` | `io.*` |
| Task limit | `pids.max`, where available | `pids.max` |
| Process assignment | One assignment per relevant hierarchy | One assignment into the unified hierarchy |

Use v2 for new configurations where supported. Do not mix v1 filenames with a v2 filesystem.

### Important v2 hierarchy rules

- Controllers must be enabled in a parent's `cgroup.subtree_control` before being used by its children.
- A controller cannot be enabled below an ancestor that has not made it available.
- For ordinary domain-controller setups, a non-root cgroup cannot contain processes while distributing those controllers to children. This is the **no-internal-process constraint**. The root and threaded configurations have special rules.
- A useful layout is an empty organizational parent with workloads in leaf groups.
- Child settings cannot override a tighter ancestor limit.

## 5. Recommended approach: systemd

On a systemd-managed host, prefer service properties over manually changing systemd's cgroup tree.

### Start a temporary limited workload

```bash
sudo systemd-run \
  --unit=cgroup-demo \
  --property=CPUQuota=50% \
  --property=MemoryMax=256M \
  --property=TasksMax=64 \
  /usr/bin/sleep 600
```

This starts a transient service with:

- Up to half of one CPU's time in aggregate.
- A 256 MiB memory limit.
- A maximum of 64 tasks, including threads.

The sleeping workload is intentionally harmless and will not demonstrate CPU throttling.

### Inspect the service

```bash
systemctl status cgroup-demo.service
systemctl show cgroup-demo.service \
  -p ControlGroup -p CPUQuotaPerSecUSec -p MemoryMax -p TasksMax
systemd-cgls
systemd-cgtop
```

On a conventional unified v2 host, inspect its kernel counters:

```bash
CG=$(systemctl show cgroup-demo.service -p ControlGroup --value)
sudo cat "/sys/fs/cgroup${CG}/cpu.stat"
sudo cat "/sys/fs/cgroup${CG}/memory.current"
sudo cat "/sys/fs/cgroup${CG}/memory.events"
```

Stop the demonstration:

```bash
sudo systemctl stop cgroup-demo.service
```

### Make limits persistent for an existing service

For a real service named `myapp.service`:

```bash
sudo systemctl edit myapp.service
```

Add:

```ini
[Service]
CPUQuota=50%
MemoryHigh=200M
MemoryMax=256M
TasksMax=128
```

Then apply during an appropriate maintenance window:

```bash
sudo systemctl daemon-reload
sudo systemctl restart myapp.service
```

`MemoryHigh` encourages reclaim and throttles allocations under pressure. `MemoryMax` is the hard limit. Restarting a service interrupts its workload.

## 6. Manual cgroup v2 laboratory

> Use an isolated VM where you control the hierarchy. The following intentionally changes root-level controller enablement and is not a replacement for systemd management or formal delegation. If systemd owns the hierarchy, prefer Section 5.

### Step 1: Enter a root shell and check the filesystem

```bash
sudo -i

stat -fc %T /sys/fs/cgroup
cat /sys/fs/cgroup/cgroup.controllers
```

Continue only with a unified v2 mount and available `cpu`, `memory`, and `pids` controllers. If a controller is unavailable, investigate kernel support and ancestor configuration rather than attempting to mount v1 over v2.

### Step 2: Enable controllers and create a fresh leaf group

```bash
printf '+cpu +memory +pids\n' > /sys/fs/cgroup/cgroup.subtree_control
mkdir /sys/fs/cgroup/cgroup-demo
CG=/sys/fs/cgroup/cgroup-demo
```

Use a fresh group name. If `mkdir` fails because it exists, stop and inspect it rather than reusing a potentially active group.

### Step 3: Set a CPU quota

```bash
printf '50000 100000\n' > "$CG/cpu.max"
```

The fields are:

```text
QUOTA_IN_MICROSECONDS PERIOD_IN_MICROSECONDS
```

Here the group can consume 50,000 microseconds of CPU time per 100,000-microsecond period, aggregated across its tasks and CPUs.

- `50000 100000`: approximately half of one CPU.
- `100000 100000`: approximately one CPU.
- `200000 100000`: approximately two CPUs, if available.
- `max 100000`: no quota at this group level; ancestors may still impose one.

This is a bandwidth limit, not CPU affinity or an exclusive CPU reservation.

Optionally set relative CPU weight:

```bash
printf '100\n' > "$CG/cpu.weight"
```

Weights determine relative shares among competing sibling groups. They are not hard limits. The ordinary v2 weight range is 1–10000, with a default of 100.

### Step 4: Set memory and task limits

```bash
# 200 MiB reclaim/throttling threshold.
printf '209715200\n' > "$CG/memory.high"

# 256 MiB hard memory limit.
printf '268435456\n' > "$CG/memory.max"

# Optional: prohibit swap for this group, if this interface is available.
if [ -f "$CG/memory.swap.max" ]; then
  printf '0\n' > "$CG/memory.swap.max"
fi

# Limit tasks, including threads.
printf '64\n' > "$CG/pids.max"
```

`memory.max` does not simply add a matching swap cap. Swap is controlled separately. If reclaim cannot satisfy the hard memory limit, allocations may fail or a cgroup-local OOM kill may occur. This is not necessarily an immediate kill when usage first approaches the configured value.

### Step 5: Start a process inside the group

```bash
bash -c 'printf "%s\n" "$$" > "$1/cgroup.procs"; exec sleep 600' _ "$CG" &
DEMO_PID=$!
```

The child shell joins the cgroup before executing the workload. Its future children inherit membership.

For an already-running process, the general form is:

```bash
# Replace with the PID of a disposable process you own.
PID=12345
# Run only after verifying that PID:
# printf '%s\n' "$PID" > "$CG/cgroup.procs"
```

Moving a process does not automatically move its existing descendants. Existing resource charges, particularly memory allocated before migration, may remain attributed to the original group. Starting workloads inside the intended group is preferable.

### Step 6: Verify membership and limits

```bash
cat "/proc/$DEMO_PID/cgroup"
cat "$CG/cgroup.procs"
cat "$CG/cpu.max"
cat "$CG/cpu.stat"
cat "$CG/memory.current"
cat "$CG/memory.events"
cat "$CG/pids.current"
cat "$CG/pids.events"
```

For a short optional CPU-load test, if `stress-ng` is installed:

```bash
bash -c 'printf "%s\n" "$$" > "$1/cgroup.procs"; exec stress-ng --cpu 2 --timeout 15s' _ "$CG" &
LOAD_PID=$!
wait "$LOAD_PID"
cat "$CG/cpu.stat"
```

Under sustained load, `nr_throttled` and `throttled_usec` should increase when the quota throttles the group. Do not deliberately trigger OOM or fork-bomb tests on a shared machine.

### Optional: Limit block-device I/O

The `io` controller must be available and enabled in the parent:

```bash
cat /sys/fs/cgroup/cgroup.controllers
printf '+io\n' > /sys/fs/cgroup/cgroup.subtree_control
lsblk -o NAME,MAJ:MIN,TYPE,MOUNTPOINTS
```

After identifying the correct underlying device, a sample limit is:

```bash
# EXAMPLE ONLY: replace 8:0 with the actual device major:minor.
# printf '8:0 rbps=10485760 wbps=5242880\n' > "$CG/io.max"
```

This example sets 10 MiB/s read and 5 MiB/s write limits for that device. Device-mapper layers, filesystem writeback support, and page caching affect observed results. Cached reads do not necessarily generate block-device I/O.

### Step 7: Clean up

After the optional load test finishes:

```bash
kill "$DEMO_PID"
wait "$DEMO_PID" 2>/dev/null || true
cat "$CG/cgroup.events"
rmdir "$CG"
exit
```

If the group is still populated, identify and stop its remaining workloads before removal. On supporting kernels, writing `1` to `cgroup.kill` kills the entire group and its descendants; use it only for a verified disposable group.

Use `rmdir`, not `rm -rf`, for cgroup directories. Do not disable root controllers during cleanup: other workloads may now depend on them. Manual settings are not persistent across reboot.

## 7. Legacy cgroup v1 configuration

> Use this section only on a system actually using v1 for these controllers. Mount paths vary, and CPU may be mounted together with `cpuacct`.

### Step 1: Discover controller mounts

```bash
findmnt -t cgroup
cat /proc/self/cgroup
```

Do not create new controller mounts on an already-managed system. On a deliberately unmanaged v1 test system only, with no existing mounts or conflicting controller use, a root administrator might mount them as follows:

```bash
# Optional unmanaged-v1 setup ONLY; normally skip this block.
# mkdir -p /sys/fs/cgroup/cpu /sys/fs/cgroup/memory
# mount -t cgroup -o cpu none /sys/fs/cgroup/cpu
# mount -t cgroup -o memory none /sys/fs/cgroup/memory
```

### Step 2: Create groups and configure limits

Run in a root Bash shell. Adjust both mount paths to the actual system:

```bash
sudo -i

CPU_MOUNT=/sys/fs/cgroup/cpu
MEM_MOUNT=/sys/fs/cgroup/memory

mkdir "$CPU_MOUNT/cgroup-demo"
mkdir "$MEM_MOUNT/cgroup-demo"

printf '100000\n' > "$CPU_MOUNT/cgroup-demo/cpu.cfs_period_us"
printf '50000\n' > "$CPU_MOUNT/cgroup-demo/cpu.cfs_quota_us"
printf '268435456\n' > "$MEM_MOUNT/cgroup-demo/memory.limit_in_bytes"
```

### Step 3: Start a process in both groups

```bash
bash -c '
  printf "%s\n" "$$" > "$1/cgroup-demo/cgroup.procs"
  printf "%s\n" "$$" > "$2/cgroup-demo/cgroup.procs"
  exec sleep 600
' _ "$CPU_MOUNT" "$MEM_MOUNT" &
DEMO_PID=$!
```

For an existing, verified PID, write that PID into **both** `cgroup.procs` files. This corrects the omission in the original example.

### Step 4: Inspect and clean up

```bash
cat "/proc/$DEMO_PID/cgroup"
cat "$CPU_MOUNT/cgroup-demo/cpu.stat"
cat "$MEM_MOUNT/cgroup-demo/memory.usage_in_bytes"
cat "$MEM_MOUNT/cgroup-demo/memory.failcnt"

kill "$DEMO_PID"
wait "$DEMO_PID" 2>/dev/null || true
rmdir "$CPU_MOUNT/cgroup-demo"
rmdir "$MEM_MOUNT/cgroup-demo"
exit
```

The v1 memory limit is not necessarily a total memory-plus-swap limit. Where supported, `memory.memsw.limit_in_bytes` controls combined memory and swap; it is not equivalent to v2's swap-only `memory.swap.max`.

## 8. Linux namespace types

| Namespace | Isolates | Typical tool or flag |
|---|---|---|
| Mount | Mount table and mount relationships | `unshare --mount` |
| PID | Process-ID numbering and visibility | `unshare --pid --fork` |
| Network | Interfaces, routes, port space, firewall rules, network stack | `unshare --net`, `ip netns` |
| UTS | Hostname and NIS domain name | `unshare --uts` |
| IPC | System V IPC and POSIX message queues | `unshare --ipc` |
| User | User/group ID mappings and capability scope | `unshare --user --map-root-user` |
| Cgroup | View of cgroup membership paths and cgroup mount roots | `unshare --cgroup` |
| Time | Offsets for monotonic and boot-time clocks | `unshare --time` |

Important qualifications:

- A mount namespace does not copy file contents or automatically provide a new root filesystem.
- A PID namespace does not hide its processes from ancestor PID namespaces.
- A user namespace's UID 0 is not automatically host root.
- A cgroup namespace changes the view of cgroups; it does not itself impose resource limits or grant control over the host hierarchy.
- Time namespaces do not virtualize every clock; notably, they do not provide an independent `CLOCK_REALTIME` wall clock.

### Inspect namespace membership

```bash
ls -l /proc/self/ns
lsns

# Replace 12345 with a real PID:
ls -l /proc/12345/ns
readlink /proc/12345/ns/net
```

Matching namespace identifiers for the same namespace type indicate shared membership.

Kernel APIs include `clone()`/`clone3()`, `unshare()`, and `setns()`. The command-line tools expose common operations built on these mechanisms.

## 9. Namespace laboratories

Run each example separately. Entering a namespace shell does not make that shell a secure container.

### A. UTS: use a separate hostname

Record the host hostname:

```bash
hostname
sudo unshare --uts /bin/bash
```

Inside the new shell:

```bash
hostname namespace-demo
hostname
exit
```

Back on the host:

```bash
hostname
```

The host hostname should be unchanged. Do not edit `/etc/hostname`: this example still shares the host filesystem.

### B. PID and mount: create an isolated process view

```bash
sudo unshare --pid --fork --mount --mount-proc /bin/bash
```

Inside:

```bash
echo "My PID is $$"
ps -ef
sleep 60 &
ps -ef
exit
```

The shell is PID 1 in the new PID namespace. `--fork` is necessary because a new PID namespace affects children created after the namespace operation. A new procfs mount provides the matching process view.

PID 1 has special signal and child-reaping responsibilities. When it exits, the kernel terminates remaining processes in that PID namespace. Production containers should use an entrypoint that handles signals and reaps children correctly.

### C. Mount: create a mount visible only inside a namespace

Create a temporary directory on the host and pass its path into the new shell:

```bash
DEMO_DIR=$(mktemp -d /tmp/mount-ns-demo.XXXXXX)
sudo env DEMO_DIR="$DEMO_DIR" unshare --mount /bin/bash
```

Inside:

```bash
# Explicitly prevent mount propagation back to other namespaces.
mount --make-rprivate /
mount -t tmpfs -o size=16m tmpfs "$DEMO_DIR"
printf 'namespace-only file\n' > "$DEMO_DIR/example.txt"
findmnt --mountpoint "$DEMO_DIR"
ls "$DEMO_DIR"
umount "$DEMO_DIR"
exit
```

Back on the host:

```bash
ls -la "$DEMO_DIR"
rmdir "$DEMO_DIR"
```

The file was stored on the temporary tmpfs, not in the host's underlying directory. Ordinary writes to shared underlying files would still affect the host.

### D. Network: build a host-to-namespace link

This example creates a named network namespace and a virtual Ethernet pair. Ensure the names and subnet are unused first.

```bash
sudo ip netns add net-demo
sudo ip link add veth-host type veth peer name veth-ns
sudo ip link set veth-ns netns net-demo

sudo ip addr add 192.0.2.1/30 dev veth-host
sudo ip link set veth-host up

sudo ip -n net-demo addr add 192.0.2.2/30 dev veth-ns
sudo ip -n net-demo link set veth-ns up
sudo ip -n net-demo link set lo up
```

Test connectivity:

```bash
sudo ip netns exec net-demo ip addr
sudo ip netns exec net-demo ip route
sudo ip netns exec net-demo ping -c 3 192.0.2.1
```

This provides only the directly connected link, not Internet access. External connectivity requires routing, suitable firewall rules, often NAT, and DNS configuration. Host firewall rules can also block the ping.

Cleanup after all commands finish:

```bash
sudo ip netns pids net-demo
# If any processes are listed, identify and stop them first.
sudo ip link del veth-host
sudo ip netns del net-demo
```

Deleting one end of a veth pair deletes the pair. Deleting a namespace name alone does not terminate processes still using that namespace.

### E. User: map yourself to namespace root

Run as a regular user:

```bash
id
unshare --user --map-root-user /bin/bash
```

Inside:

```bash
id
cat /proc/self/uid_map
cat /proc/self/gid_map
exit
```

Your identity appears as root inside the new user namespace, but maps to your unprivileged host identity. This does not grant unrestricted access to host files or host-owned namespaces.

Unprivileged user namespaces may be disabled or restricted by distribution policy, security modules, or container runtime settings. Do not weaken production security policy merely to run this example.

### F. Enter an existing namespace with nsenter

For a verified target process:

```bash
PID=12345
sudo nsenter --target "$PID" --uts hostname
sudo nsenter --target "$PID" --net ip addr
```

A broader diagnostic shell can be started with:

```bash
sudo nsenter --target "$PID" --mount --uts --ipc --net --pid /bin/bash
```

This does not automatically join the target's resource-control cgroup, reproduce its credentials, or reproduce its security policy. Even joining a cgroup namespace is different from joining a resource-control group.

## 10. Using cgroups and namespaces together

A simplified container startup sequence is:

1. Create a cgroup and configure resource limits.
2. Place the workload in that cgroup before it allocates significant resources or forks.
3. Create the required namespaces.
4. Configure user mappings, networking, mounts, and a root filesystem.
5. Drop capabilities and apply seccomp and security-module policy.
6. Start an init/entrypoint process that handles signals and reaps children.

For an educational demonstration on systemd:

```bash
sudo systemd-run --scope \
  --property=CPUQuota=50% \
  --property=MemoryMax=256M \
  --property=TasksMax=64 \
  unshare --uts --pid --fork --mount --mount-proc /bin/bash
```

Inside, inspect:

```bash
echo "PID: $$"
ps -ef
cat /proc/self/cgroup
exit
```

The workload has resource limits plus selected namespace isolation. **This is not a secure container:** it still shares the host network and underlying filesystem, runs with substantial privileges, and lacks a complete sandbox policy.

Use a mature container runtime rather than turning these demonstration commands into a production container system.

## 11. Monitoring and troubleshooting

### Useful v2 files

| File | Purpose |
|---|---|
| `cgroup.procs` | Process membership for this group, not a recursive listing |
| `cgroup.controllers` | Controllers available for child enablement |
| `cgroup.subtree_control` | Controllers enabled for children |
| `cgroup.events` | State such as whether the subtree is populated |
| `cpu.stat` | CPU usage and bandwidth-throttling counters |
| `memory.current` | Current accounted memory usage |
| `memory.events` | Threshold, limit, and OOM events |
| `memory.stat` | Detailed memory accounting |
| `memory.swap.current` | Current swap usage, where supported |
| `pids.current` | Current task count |
| `pids.events` | Task-limit events |
| `io.stat` | Block-device I/O accounting |
| `cpu.pressure`, `memory.pressure`, `io.pressure` | Pressure stall information, where supported |

### Common problems

| Symptom | Likely cause or action |
|---|---|
| `Permission denied` while writing limits | Use appropriate root privileges or a properly delegated subtree; check shell redirection |
| `Read-only file system` | The runtime or host mounted cgroupfs read-only; configure limits through the manager |
| `cpu.max` or `memory.max` missing | Wrong cgroup version, controller unavailable, or controller not enabled in the parent |
| `Device or resource busy` enabling controllers | Check the v2 no-internal-process constraint and hierarchy state |
| Controller missing from `cgroup.controllers` | Check kernel support, ancestor enablement, and whether v1 owns it |
| CPU usage looks higher than expected | Check tool percentage conventions, aggregation, sample duration, and actual membership |
| Memory test seems unaffected | Verify membership, allocation timing, ancestors, actual touched memory, and swap configuration |
| Process was killed | Inspect `memory.events` and system logs for OOM evidence; do not assume every exit is OOM |
| Fork or thread creation fails | Check `pids.max`, ancestor limits, and other task/resource limits |
| `ps` shows host processes | Use a PID namespace together with an appropriate procfs mount |
| Mounts affect the host | Check shared mount propagation and use a private mount namespace |
| `unshare: Operation not permitted` | Missing capabilities, disabled user namespaces, seccomp, or security-module policy |
| Network namespace has no connectivity | Bring up loopback/interfaces; inspect routes, firewall rules, and DNS |
| Cannot remove a cgroup | Stop remaining processes and remove child cgroups before `rmdir` |

## 12. Security and operational considerations

- **Shared kernel:** namespaces do not provide a separate kernel, and kernel vulnerabilities can undermine isolation.
- **Least privilege:** drop unnecessary capabilities, especially broad administrative privileges.
- **Filesystem protection:** use a controlled root filesystem and carefully selected read-only or writable mounts. A mount namespace alone does not protect host files.
- **Additional controls:** consider seccomp, SELinux/AppArmor, `no_new_privs`, and runtime security defaults.
- **Device access:** filesystem and namespace isolation do not automatically make dangerous devices safe. V2 device-access control commonly uses cgroup BPF through a runtime or manager, not a v1-style `devices.*` controller interface.
- **Network bandwidth:** a network namespace isolates the network stack but does not cap bandwidth. Traffic shaping typically uses tools such as `tc` or higher-level network policy mechanisms.
- **CPU placement:** use cpusets or manager CPU-affinity controls when placement matters; a CPU quota is not pinning.
- **Memory sizing:** allow headroom for startup, caches, and workload peaks; monitor pressure and OOM events.
- **Delegation:** allowing an unprivileged manager to control a subtree requires correct delegation and permissions. Do not recursively make the host cgroup hierarchy writable.
- **Persistence:** direct cgroupfs writes and ad hoc namespace setup are generally temporary. Use service configuration or a runtime for reproducible setup and cleanup.
- **Lifecycle:** namespace membership, open namespace file descriptors, and bind mounts can keep namespaces alive. Named network namespaces are one example of explicit persistence.

## 13. Quick reference

```text
Cgroups                  Resource accounting and limits
Namespaces               Resource-specific isolated views

v2 CPU quota             cpu.max: "50000 100000" = half of one CPU
v2 CPU weight            cpu.weight: relative share under contention
v2 memory hard limit     memory.max: 268435456 = 256 MiB
v2 memory pressure       memory.high: reclaim/throttling threshold
v2 swap-only limit       memory.swap.max
v2 task limit            pids.max: includes threads
v2 process assignment    write a PID to cgroup.procs

Inspect cgroup mounts    findmnt -R /sys/fs/cgroup
Inspect membership       cat /proc/PID/cgroup
Inspect namespaces       ls -l /proc/PID/ns
List namespaces          lsns
Create namespace         unshare
Enter namespace          nsenter
Named network namespace  ip netns
Managed resource limits  systemd-run / systemctl set-property
```

## 14. References

Authoritative documentation for details and kernel/version-specific behavior:

- [Linux kernel: cgroup v2](https://docs.kernel.org/admin-guide/cgroup-v2.html)
- [Linux kernel: cgroup v1](https://docs.kernel.org/admin-guide/cgroup-v1/index.html)
- [cgroups(7)](https://man7.org/linux/man-pages/man7/cgroups.7.html)
- [namespaces(7)](https://man7.org/linux/man-pages/man7/namespaces.7.html)
- [user_namespaces(7)](https://man7.org/linux/man-pages/man7/user_namespaces.7.html)
- [pid_namespaces(7)](https://man7.org/linux/man-pages/man7/pid_namespaces.7.html)
- [mount_namespaces(7)](https://man7.org/linux/man-pages/man7/mount_namespaces.7.html)
- [time_namespaces(7)](https://man7.org/linux/man-pages/man7/time_namespaces.7.html)
- [unshare(1)](https://man7.org/linux/man-pages/man1/unshare.1.html)
- [nsenter(1)](https://man7.org/linux/man-pages/man1/nsenter.1.html)
- [ip-netns(8)](https://man7.org/linux/man-pages/man8/ip-netns.8.html)
- [systemd resource control](https://www.freedesktop.org/software/systemd/man/latest/systemd.resource-control.html)
- [systemd-run](https://www.freedesktop.org/software/systemd/man/latest/systemd-run.html)

Examples assume the stated environment and have not been executed against your host. Check local manual pages and available kernel interfaces before applying them.
