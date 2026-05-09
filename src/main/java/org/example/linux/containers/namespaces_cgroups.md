# Namespaces & cgroups – Container Primitives

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Overview – Linux Container Primitives

### What – Container là gì ở mức kernel?
Container **không phải là feature của kernel**. Container = tập hợp các kernel features kết hợp:
- **Namespaces**: isolation (mỗi container thấy thế giới riêng)
- **cgroups**: resource limits (giới hạn CPU, memory, I/O)
- **Union filesystems**: layered filesystem (overlay2)
- **Capabilities**: fine-grained privilege control
- **seccomp**: syscall filtering

### How – Container vs VM

```
Virtual Machine:
  Hardware → Hypervisor → Guest OS Kernel → Applications
  Isolation: Full (separate kernel)
  Overhead: High (~seconds to start, 100MB+ overhead)

Container:
  Hardware → Host OS Kernel → Namespaces/cgroups → Applications
  Isolation: Logical (shared kernel)
  Overhead: Low (~milliseconds to start, MBs overhead)
```

---

## 2. Namespaces – Deep Dive

### What – Namespaces là gì?
**Namespaces** wrap global kernel resources, cho mỗi process "thấy" phiên bản riêng của resource đó. Không thay đổi kernel internals, chỉ thay đổi **perspective**.

### How – PID Namespace

```bash
# PID namespace: process thấy process tree của riêng nó
# Process đầu tiên trong namespace = PID 1 (bên trong)
# Trên host: process đó có PID khác (e.g., 12345)

# Tạo PID namespace mới
unshare --pid --fork --mount-proc bash
  ps aux                           # chỉ thấy bash (PID 1) và ps
  echo $$                          # 1

# Từ host: xem PID thực
pstree -p $(pgrep -f "unshare.*bash")

# Nested PID namespaces (container trong container)
# PID host  | PID ns1  | PID ns2
#   1000    |    1     |    -
#   1001    |    2     |    1
#   1002    |    3     |    2

# /proc/<PID>/ns/pid – namespace reference (inode)
ls -li /proc/1/ns/pid /proc/self/ns/pid   # so sánh inode
```

### How – Network Namespace

```bash
# Net namespace: mỗi namespace có interfaces, routing, iptables riêng

# Tạo named net namespace
ip netns add container1
ip netns list

# Tạo veth pair (virtual ethernet cable)
ip link add veth0 type veth peer name veth1

# Move veth1 vào namespace
ip link set veth1 netns container1

# Configure host side
ip addr add 10.0.0.1/24 dev veth0
ip link set veth0 up

# Configure container side
ip netns exec container1 ip addr add 10.0.0.2/24 dev veth1
ip netns exec container1 ip link set veth1 up
ip netns exec container1 ip link set lo up
ip netns exec container1 ip route add default via 10.0.0.1

# NAT cho internet access
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o eth0 -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward

# Test connectivity
ip netns exec container1 ping 8.8.8.8
ip netns exec container1 curl -s https://example.com

# Xem interfaces trong namespace
ip netns exec container1 ip addr show

# Delete
ip netns delete container1
```

### How – Mount Namespace

```bash
# Mount namespace: mỗi namespace có mount table riêng
# Cho phép container có filesystem riêng mà không ảnh hưởng host

# Tạo mount namespace
unshare --mount bash
  mount --bind /tmp/container-root /mnt
  ls /mnt                          # chỉ thấy container-root
  # Host không thấy mount này

# pivot_root – thay đổi root filesystem
# (dùng bởi container runtimes)

# Chuẩn bị rootfs
mkdir -p /container/rootfs
tar -xzf ubuntu-22.04-base.tar.gz -C /container/rootfs/

# Setup trong unshare
unshare --mount bash
  mount --bind /container/rootfs /container/rootfs  # bind-mount
  cd /container/rootfs
  mkdir -p old_root
  pivot_root . old_root             # swap / with current dir
  umount -l /old_root               # unmount old root
  rmdir /old_root
  ls /                              # now seeing container's /

# overlay2 filesystem (thực tế Docker dùng)
mkdir -p /tmp/overlay/{lower,upper,work,merged}
echo "base content" > /tmp/overlay/lower/file.txt
mount -t overlay overlay \
    -o lowerdir=/tmp/overlay/lower,upperdir=/tmp/overlay/upper,workdir=/tmp/overlay/work \
    /tmp/overlay/merged

# Reads from lower (unchanged) or upper (modified)
# Writes go to upper only
cat /tmp/overlay/merged/file.txt    # "base content"
echo "modified" >> /tmp/overlay/merged/file.txt
cat /tmp/overlay/upper/file.txt     # "modified" (only in upper)
cat /tmp/overlay/lower/file.txt     # "base content" (unchanged)
```

### How – UTS Namespace

```bash
# UTS namespace: hostname và NIS domain name riêng

unshare --uts bash
  hostname mycontainer              # set hostname
  hostname                          # mycontainer
  # Host hostname không thay đổi

# Verify from host
cat /proc/$(pgrep -f "unshare.*bash")/uts  # (not directly readable)
nsenter --target $(pgrep -f "unshare.*bash") --uts hostname
```

### How – User Namespace

```bash
# User namespace: UID/GID mapping
# Non-privileged user có thể là UID 0 (root) bên trong namespace!

# Tạo user namespace (không cần root!)
unshare --user bash
  id                                # uid=65534(nobody) – unmapped

# Setup UID/GID mapping
echo "0 1000 1" > /proc/self/uid_map   # inside-uid outside-uid count
echo "0 1000 1" > /proc/self/gid_map

# Better: với newuidmap/newgidmap
unshare --user --map-root-user bash
  id                                # uid=0(root) gid=0(root)
  # CÓ THỂ làm nhiều thứ "root" nhưng trong namespace isolated

# /etc/subuid và /etc/subgid
grep alice /etc/subuid               # alice:100000:65536
# alice có thể map UID 100000-165535 thành 0-65535 bên trong namespace

# Docker rootless mode dùng user namespaces
```

### How – IPC Namespace

```bash
# IPC namespace: System V IPC và POSIX message queues riêng

# Xem IPC objects
ipcs -a                             # shared memory, semaphores, message queues

# Tạo shared memory trong host
python3 -c "
import sysv_ipc
mem = sysv_ipc.SharedMemory(12345, sysv_ipc.IPC_CREAT, 0o644, size=1024)
mem.write(b'hello from host')
"

# Trong IPC namespace mới: không thấy host IPC objects
unshare --ipc bash
  ipcs -a                           # empty
  # Có thể tạo IPC objects riêng mà không conflict
```

---

## 3. cgroups v2 – Resource Control Deep Dive

### What – cgroups v2 là gì?
**cgroups version 2** là unified resource control hierarchy. Tất cả controllers trong 1 tree thay vì các hierarchies riêng biệt như v1.

### How – cgroups v2 Hierarchy

```
/sys/fs/cgroup/              ← root cgroup
├── cgroup.controllers       ← available controllers
├── cgroup.subtree_control   ← enabled controllers for children
├── cgroup.procs             ← PIDs in this cgroup
├── cpu.stat
├── memory.stat
├── io.stat
│
├── system.slice/            ← systemd's slice
│   ├── docker.service/      ← docker daemon
│   └── nginx.service/       ← nginx
│
└── user.slice/              ← user processes
    └── user-1000.slice/
        └── session-1.scope/
```

### How – Memory Controller v2

```bash
# File: memory.max, memory.min, memory.high, memory.low
# hierarchy: min < low < high < max

# memory.min = hard minimum; never reclaimed under pressure
# memory.low = soft minimum; try to keep, but can reclaim
# memory.high = throttling threshold; slow processes when exceeded
# memory.max = hard maximum; OOM kill when exceeded

# Setup cgroup v2
mkdir /sys/fs/cgroup/myapp
echo "+cpu +memory +io" > /sys/fs/cgroup/myapp/cgroup.subtree_control

# Memory limits
echo $((512 * 1024 * 1024)) > /sys/fs/cgroup/myapp/memory.max    # 512MB max
echo $((384 * 1024 * 1024)) > /sys/fs/cgroup/myapp/memory.high   # 384MB high
echo $((256 * 1024 * 1024)) > /sys/fs/cgroup/myapp/memory.low    # 256MB low
echo $((64 * 1024 * 1024)) > /sys/fs/cgroup/myapp/memory.min     # 64MB min

# Add process
echo $$ > /sys/fs/cgroup/myapp/cgroup.procs

# Monitor
cat /sys/fs/cgroup/myapp/memory.current   # current usage
cat /sys/fs/cgroup/myapp/memory.stat      # detailed stats
# anon: anonymous memory (heap, stack)
# file: page cache
# slab: kernel slab caches
# sock: socket buffers

# OOM events
cat /sys/fs/cgroup/myapp/memory.events
# low: times below low
# high: times above high  
# max: times at max (throttled)
# oom: times OOM killer invoked
# oom_kill: times process was OOM killed
```

### How – CPU Controller v2

```bash
# cpu.max: quota period
# Format: $MAX $PERIOD (microseconds)
echo "100000 1000000" > /sys/fs/cgroup/myapp/cpu.max   # 10% CPU
echo "500000 1000000" > /sys/fs/cgroup/myapp/cpu.max   # 50% CPU
echo "max 1000000" > /sys/fs/cgroup/myapp/cpu.max      # unlimited

# cpu.weight: relative shares (1-10000, default 100)
echo 200 > /sys/fs/cgroup/myapp/cpu.weight  # 2x normal priority
echo 50 > /sys/fs/cgroup/myapp/cpu.weight   # half normal priority

# Monitor
cat /sys/fs/cgroup/myapp/cpu.stat
# usage_usec: total CPU time used
# user_usec: user space time
# system_usec: kernel space time
# throttled_usec: time throttled (quota exceeded)
# nr_throttled: times throttled
```

### How – I/O Controller v2

```bash
# io.max: rate limits
# Format: MAJOR:MINOR rbps wbps riops wiops
# 8:0 = sda; use lsblk to find major:minor

echo "8:0 10485760 10485760 max max" > /sys/fs/cgroup/myapp/io.max
# Read: 10MB/s, Write: 10MB/s, IOPS: unlimited

echo "8:0 max max 1000 1000" > /sys/fs/cgroup/myapp/io.max
# IOPS: 1000 read/write, bandwidth: unlimited

# io.weight: relative I/O priority (1-10000, default 100)
echo "default 50" > /sys/fs/cgroup/myapp/io.weight   # half priority

# Monitor
cat /sys/fs/cgroup/myapp/io.stat
# 8:0 rbytes=xxx wbytes=xxx rios=xxx wios=xxx
```

### How – PSI (Pressure Stall Information)

```bash
# PSI: % time tasks stalled waiting for resource
# "some": at least one task stalled
# "full": ALL tasks stalled

cat /sys/fs/cgroup/myapp/memory.pressure
# some avg10=0.12 avg60=0.08 avg300=0.04 total=12345
# full avg10=0.00 avg60=0.00 avg300=0.00 total=0

# System-wide PSI
cat /proc/pressure/cpu
cat /proc/pressure/memory
cat /proc/pressure/io

# PSI-based auto-scaling trigger
watch -n 1 'cat /proc/pressure/cpu'

# Script: alert khi CPU pressure > 10%
while true; do
    CPU_PRESSURE=$(awk '/^some/ {print $2}' /proc/pressure/cpu | cut -d= -f2)
    if (( $(echo "$CPU_PRESSURE > 10" | bc -l) )); then
        echo "HIGH CPU PRESSURE: $CPU_PRESSURE%"
        # trigger scaling
    fi
    sleep 5
done
```

---

## 4. Container Implementation từ Scratch

### How – Build a Container Manually

```bash
#!/usr/bin/env bash
# Minimal container from scratch

ROOTFS="/tmp/mycontainer"
CONTAINER_CMD="${1:-/bin/bash}"

# 1. Create minimal rootfs
mkdir -p "$ROOTFS"/{bin,lib,lib64,proc,sys,dev,etc,tmp,var}

# Copy binaries and their libraries
copy_with_libs() {
    local bin="$1"
    cp "$bin" "$ROOTFS/bin/"
    # Copy all shared libraries
    ldd "$bin" | grep "=>" | awk '{print $3}' | while read -r lib; do
        [[ -f "$lib" ]] && cp -n "$lib" "$ROOTFS/lib/"
    done
}

copy_with_libs /bin/bash
copy_with_libs /bin/ls
copy_with_libs /bin/cat

# 2. Essential files
echo "root:x:0:0:root:/root:/bin/bash" > "$ROOTFS/etc/passwd"
echo "root:x:0:" > "$ROOTFS/etc/group"

# 3. Launch container with all namespaces
unshare \
    --pid \
    --net \
    --mount \
    --uts \
    --ipc \
    --fork \
    --mount-proc="$ROOTFS/proc" \
    bash -c "
        # Setup hostname
        hostname mycontainer

        # Setup networking (in real case: setup veth pair first)
        ip link set lo up

        # Change root
        cd '$ROOTFS'
        mkdir -p old_root
        pivot_root . old_root
        umount -l /old_root
        rmdir /old_root

        # Execute command
        exec $CONTAINER_CMD
    "
```

### How – runc – OCI Runtime

```bash
# runc là low-level container runtime dùng bởi Docker

# Cài đặt
apt install runc

# Tạo OCI bundle
mkdir -p /mycontainer/rootfs
docker export $(docker create busybox) | tar -C /mycontainer/rootfs -xf -

# Generate config
cd /mycontainer
runc spec                             # tạo config.json template

# Run container
runc run mycontainer                  # create + start
runc create mycontainer               # create only
runc start mycontainer                # start created
runc state mycontainer                # check state
runc kill mycontainer SIGTERM         # send signal
runc delete mycontainer               # cleanup
```

---

## 5. Security Model

### How – Capabilities

```bash
# Capabilities: chia nhỏ quyền "root" thành các privilege riêng
# Container processes thường chạy với limited capabilities

# Xem capabilities
getpcaps $$                           # current process
cat /proc/$$/status | grep Cap        # hex bitmask

# Common capabilities
# CAP_NET_BIND_SERVICE  – bind port < 1024
# CAP_NET_RAW           – raw sockets (ping)
# CAP_SYS_ADMIN         – many admin operations (broad, dangerous)
# CAP_CHOWN             – change file ownership
# CAP_SETUID/SETGID     – change UID/GID
# CAP_SYS_PTRACE        – ptrace (strace, gdb)
# CAP_DAC_OVERRIDE      – bypass file permission checks

# capsh – capability manipulation
capsh --print                          # current capabilities
capsh --drop="cap_net_raw" -- -c "ping 8.8.8.8"  # run without cap_net_raw

# Docker: set capabilities
# docker run --cap-drop ALL --cap-add NET_BIND_SERVICE nginx
```

### How – seccomp – Syscall Filtering

```bash
# seccomp: filter syscalls available to process
# Docker default seccomp profile blocks ~44 syscalls

# Xem seccomp status
cat /proc/self/status | grep Seccomp
# Seccomp: 0 = disabled, 1 = strict, 2 = filter

# Custom seccomp profile (JSON)
cat > /tmp/seccomp.json << 'EOF'
{
    "defaultAction": "SCMP_ACT_ERRNO",
    "architectures": ["SCMP_ARCH_X86_64"],
    "syscalls": [
        {
            "names": ["read", "write", "open", "close", "exit_group", "fstat", "brk", "mmap", "munmap"],
            "action": "SCMP_ACT_ALLOW"
        }
    ]
}
EOF

# Apply via Docker
docker run --security-opt seccomp=/tmp/seccomp.json myimage

# strace để biết syscalls cần whitelist
strace -c ./myapp                     # thống kê syscalls
```

---

## 6. Compare & Trade-offs

### Compare – Namespace Types

| Namespace | Isolates | Container use |
|-----------|---------|---------------|
| PID | Process IDs | Container thinks PID 1 is init |
| NET | Network stack | Container has own IP/ports |
| MNT | Filesystem mounts | Container has own / |
| UTS | Hostname | Container has own hostname |
| USER | UID/GID | Rootless containers |
| IPC | SysV IPC | Prevent IPC interference |
| TIME | Clock offsets | Test time-dependent code |
| CGROUP | cgroup view | Hide host cgroup structure |

### Trade-offs

- **User namespaces**: cho phép rootless containers (secure) nhưng có overhead và complexity; một số features cần real root
- **cgroups v2 vs v1**: v2 unified và feature-rich hơn nhưng cần newer kernel (5.x+); Kubernetes support từ 1.25
- **Shared kernel**: containers nhẹ hơn VM nhưng security isolation kém hơn; kernel vulnerability ảnh hưởng tất cả containers
- **Network namespace + veth**: overhead nhỏ (microseconds) so với physical switching; phù hợp cho hầu hết workloads

---

### Ghi chú – Chủ đề tiếp theo
> **14.2 Docker Internals**: overlay2 filesystem, veth pairs, iptables NAT, image layers, seccomp, capabilities trong Docker context
