# Process & Resource Management Advanced – Deep Dive

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. cgroups v2 – Control Groups

### What – cgroups là gì?
**cgroups (Control Groups)** là Linux kernel feature cho phép **giới hạn, đo lường, và kiểm soát** tài nguyên (CPU, memory, disk I/O, network) của nhóm processes. Đây là nền tảng của Docker, Kubernetes resource limits.

### How – cgroups v1 vs v2

```
cgroups v1 (legacy):
  Mỗi subsystem (cpu, memory, blkio...) là hierarchy riêng biệt
  /sys/fs/cgroup/cpu/
  /sys/fs/cgroup/memory/
  /sys/fs/cgroup/blkio/
  Vấn đề: phức tạp, incoherent giữa subsystems

cgroups v2 (unified, Linux 4.5+, default từ kernel 5.x):
  1 hierarchy duy nhất cho tất cả subsystems
  /sys/fs/cgroup/                     (unified mount point)
  Cải thiện: thread-level granularity, PSI (Pressure Stall Information)
```

### How – Kiểm tra cgroups

```bash
# Kiểm tra version đang dùng
stat -f -c %T /sys/fs/cgroup/        # "cgroup2fs" = v2; "tmpfs" = v1 mixed

# Xem cgroup hierarchy
ls /sys/fs/cgroup/
# (v2): cgroup.controllers, cgroup.procs, memory.stat, cpu.stat...

# Xem cgroup của process hiện tại
cat /proc/$$/cgroup
# 0::/user.slice/user-1000.slice/session-1.scope  (v2)
# 12:blkio:/user.slice   (v1)

# Systemd sử dụng cgroups
systemd-cgls                         # xem cgroup tree
systemd-cgtop                        # real-time cgroup resource usage
cat /sys/fs/cgroup/system.slice/sshd.service/memory.current  # memory usage của sshd
```

### How – Tạo và quản lý cgroups (v2)

```bash
# Tạo cgroup mới
mkdir /sys/fs/cgroup/my_group

# Thêm process vào cgroup
echo $$ > /sys/fs/cgroup/my_group/cgroup.procs

# Enable controllers
echo "+cpu +memory +io" > /sys/fs/cgroup/my_group/cgroup.subtree_control

# Giới hạn memory (bytes)
echo $((512 * 1024 * 1024)) > /sys/fs/cgroup/my_group/memory.max  # 512MB
echo $((256 * 1024 * 1024)) > /sys/fs/cgroup/my_group/memory.high  # soft limit

# Giới hạn CPU
echo "100000 1000000" > /sys/fs/cgroup/my_group/cpu.max  # 10% CPU (100ms per 1000ms)
# format: quota period
echo "200000 1000000" > /sys/fs/cgroup/my_group/cpu.max  # 20% CPU

# Giới hạn I/O
# major:minor rbps wbps riops wiops
echo "8:0 10485760 10485760 max max" > /sys/fs/cgroup/my_group/io.max  # 10MB/s

# Xem stats
cat /sys/fs/cgroup/my_group/memory.stat
cat /sys/fs/cgroup/my_group/cpu.stat
cat /sys/fs/cgroup/my_group/io.stat
```

### How – systemd & cgroups

```bash
# systemd tự động tạo cgroup cho mỗi service
# Giới hạn tài nguyên trong unit file:
# /etc/systemd/system/myapp.service:
# [Service]
# MemoryMax=512M
# MemoryHigh=400M
# CPUQuota=20%
# IOWeight=50
# TasksMax=100

# Set limits tạm thời (không restart service)
systemctl set-property myapp.service MemoryMax=512M

# Xem resource usage
systemctl status myapp.service
cat /proc/$(systemctl show myapp.service -p MainPID --value)/status

# Transient cgroup (một lần chạy)
systemd-run --scope --property=MemoryMax=100M /path/to/program
```

### How – PSI (Pressure Stall Information) – v2 only

```bash
# PSI: đo mức độ "áp lực" tài nguyên
cat /sys/fs/cgroup/my_group/memory.pressure
# some avg10=0.00 avg60=0.00 avg300=0.00 total=0
# full avg10=0.00 avg60=0.00 avg300=0.00 total=0
# some = ít nhất 1 task stalled
# full = tất cả tasks stalled
# avg10/60/300 = % thời gian trong 10s/60s/300s

cat /proc/pressure/cpu
cat /proc/pressure/memory
cat /proc/pressure/io
```

---

## 2. Namespaces – Linux Isolation

### What – Namespaces là gì?
**Namespaces** là kernel feature wrap các global resources thành abstraction riêng biệt, cho phép mỗi process "thấy" một cái nhìn độc lập về hệ thống. Đây là nền tảng của containers.

### How – Các loại Namespace

```
PID namespace  – process có PID riêng; container PID 1 ≠ host PID 1
NET namespace  – network interfaces, routing tables, firewall rules riêng
MNT namespace  – filesystem mount points riêng
UTS namespace  – hostname và NIS domain name riêng
IPC namespace  – System V IPC, POSIX message queues riêng
USER namespace – UID/GID mapping; unprivileged user có thể là root bên trong
TIME namespace – boottime/monotonic clock offsets riêng (Linux 5.6+)
CGROUP ns      – cgroup root view riêng
```

### How – Làm việc với Namespaces

```bash
# Xem namespaces của process
ls -la /proc/$$/ns/
# lrwxrwxrwx 1 root root 0 /proc/1234/ns/pid -> 'pid:[4026531836]'
# lrwxrwxrwx 1 root root 0 /proc/1234/ns/net -> 'net:[4026531992]'

# lsns – list namespaces
lsns                              # tất cả namespaces
lsns -t net                       # chỉ net namespaces
lsns -p 1234                      # namespaces của PID 1234

# unshare – tạo namespace mới
unshare --pid --fork /bin/bash    # new PID namespace
unshare --net /bin/bash           # new network namespace
unshare --user --map-root-user bash  # new user namespace (thành root bên trong)
unshare --mount --pid --net --uts --ipc --fork bash  # full isolation

# Xem PID trong namespace mới
unshare --pid --fork bash
  echo $$   # 1 (bên trong PID namespace mới)

# nsenter – enter existing namespace
nsenter -t 1234 --net /bin/bash   # join network namespace của PID 1234
nsenter -t 1234 --all             # join tất cả namespaces của process
# Dùng để debug containers:
nsenter --target $(docker inspect --format={{.State.Pid}} container_name) --mount --uts --ipc --net --pid

# ip netns – manage named network namespaces
ip netns add mynet                # tạo named net namespace
ip netns list                     # list
ip netns exec mynet ip addr show  # chạy lệnh trong namespace
ip netns delete mynet             # xóa
```

### How – Container Internals với Namespaces

```bash
# Docker sử dụng namespaces như thế nào
docker run --name myapp nginx

# Xem PID của container process trên host
docker inspect --format '{{.State.Pid}}' myapp

# Xem namespaces của container
ls -la /proc/$(docker inspect --format '{{.State.Pid}}' myapp)/ns/

# Container thấy PID 1, host thấy PID thực
# PID namespace: container init = PID 1 bên trong
# HOST: container init = PID 12345

# Network namespace isolation
ip netns exec mynet_ns ip addr   # container có interface riêng
```

---

## 3. ulimit – User Resource Limits

### What – ulimit là gì?
`ulimit` kiểm soát **tài nguyên** mà một shell và các child processes của nó có thể sử dụng. Ngăn một process/user chiếm hết tài nguyên hệ thống.

### How – Sử dụng

```bash
# Xem tất cả limits
ulimit -a                          # tất cả soft limits
ulimit -aH                         # hard limits

# Limits quan trọng
ulimit -n                          # open files (file descriptors)
ulimit -u                          # max user processes
ulimit -v                          # virtual memory (KB)
ulimit -m                          # max memory (KB)
ulimit -s                          # stack size (KB)
ulimit -c                          # core dump size (0 = disabled)
ulimit -t                          # CPU time (seconds)
ulimit -f                          # max file size (512-byte blocks)

# Set limits
ulimit -n 65536                    # tăng open files lên 65536
ulimit -n unlimited                # không giới hạn
ulimit -c unlimited                # enable core dumps (debug)
ulimit -v $((1024*1024))           # giới hạn virtual memory 1GB

# Soft vs Hard limits
ulimit -Sn 32768                   # set soft limit (có thể tăng đến hard)
ulimit -Hn                         # xem hard limit (chỉ root mới tăng được)
```

### How – Cấu hình Permanent

```bash
# /etc/security/limits.conf – persistent limits
# Format: <domain> <type> <item> <value>
# domain: username, @groupname, * (all), %groupname

# /etc/security/limits.conf hoặc /etc/security/limits.d/*.conf
*    soft  nofile  65536      # tất cả users, soft, open files
*    hard  nofile  65536      # hard limit
root hard  nofile  65536
@developers soft nproc 512   # nhóm developers, max processes

# Phổ biến cho production servers
*    soft  nofile  65536
*    hard  nofile  65536
*    soft  nproc   32768
*    hard  nproc   32768

# Kiểm tra limits của process đang chạy
cat /proc/1234/limits

# systemd service limits (override /etc/security/limits.conf)
# [Service]
# LimitNOFILE=65536
# LimitNPROC=32768
```

### How – /proc/sys – Kernel Parameters

```bash
# Xem tất cả kernel params
sysctl -a | grep net.core

# Network tunables quan trọng
sysctl net.core.somaxconn           # max queued connections (default 128)
sysctl net.ipv4.tcp_max_syn_backlog # SYN backlog
sysctl net.ipv4.ip_local_port_range # ephemeral port range
sysctl fs.file-max                  # system-wide max open files
sysctl vm.swappiness                # swap aggressiveness (0-100)
sysctl vm.overcommit_memory         # memory overcommit policy

# Set tạm thời
sysctl -w net.core.somaxconn=65535

# Set permanent (/etc/sysctl.conf hoặc /etc/sysctl.d/*.conf)
echo "net.core.somaxconn=65535" > /etc/sysctl.d/99-custom.conf
sysctl -p /etc/sysctl.d/99-custom.conf  # apply
```

---

## 4. strace – System Call Tracer

### What – strace là gì?
`strace` trace **system calls** và **signals** của một process. Dùng để debug, hiểu process đang làm gì với OS.

### How – Sử dụng cơ bản

```bash
# Trace process mới
strace ls /tmp
strace -o output.txt ls /tmp        # ghi vào file
strace -c ls /tmp                   # summary thống kê

# Attach vào process đang chạy
strace -p 1234
strace -p 1234 -o trace.log &

# Trace specific syscalls
strace -e trace=open,read,write ls /tmp      # chỉ open/read/write
strace -e trace=network curl https://example.com  # network syscalls
strace -e trace=file ls /tmp                 # file-related syscalls
strace -e trace=process,signal /bin/bash     # process + signal

# Trace child processes
strace -f make                       # follow forks (-f)
strace -ff -o trace make             # trace vào file riêng per PID

# Timestamps
strace -t ls                         # absolute time
strace -T ls                         # time spent in each syscall
strace -tt ls                        # time with microseconds
```

### How – Đọc strace Output

```bash
# Dạng output:
# syscall_name(arg1, arg2, ...) = return_value
openat(AT_FDCWD, "/etc/hosts", O_RDONLY) = 3
read(3, "127.0.0.1 localhost\n...", 4096) = 127
write(1, "output text\n", 12)        = 12
close(3)                             = 0

# Lỗi thường thấy
# open(...) = -1 ENOENT (No such file or directory)
# connect(...) = -1 ECONNREFUSED (Connection refused)
# socket(...) = -1 EPERM (Operation not permitted)

# Debug ví dụ: tại sao app không start?
strace -e trace=file,network -p 1234 2>&1 | grep "ENOENT\|EACCES"

# Xem file nào app đọc lúc startup
strace -e trace=openat java -jar app.jar 2>&1 | grep "O_RDONLY"
```

### How – strace Statistics

```bash
# -c: summary mode (thống kê syscalls)
strace -c -p 1234
# Kết quả:
# % time  seconds  usecs/call  calls  errors  syscall
# ------  -------  ----------  -----  ------  -------
#  39.45  0.001234          1   1234       0  futex
#  15.23  0.000476          2    238      10  read
#   8.12  0.000254          0   3456       0  write

# Xem top syscalls
strace -c command 2>&1 | sort -k1 -rn | head
```

---

## 5. ltrace – Library Call Tracer

### What – ltrace là gì?
`ltrace` trace **dynamic library calls** (không phải syscalls). Hữu ích khi cần biết app gọi function nào của shared libraries.

### How – Sử dụng

```bash
# Basic usage
ltrace ls /tmp
ltrace -o output.txt ls /tmp

# Filter by library function
ltrace -e malloc,free ./myapp       # chỉ malloc/free calls
ltrace -e 'str*' ./myapp            # tất cả string functions

# Attach process
ltrace -p 1234

# Cùng -c stats
ltrace -c ./myapp
```

### Compare – strace vs ltrace

| | strace | ltrace |
|--|--------|--------|
| Trace | Kernel syscalls | Library (userspace) calls |
| Overhead | Trung bình | Cao hơn |
| Dùng khi | Debug I/O, permission, process | Debug library usage, memory |
| Ví dụ | Tại sao file không mở được? | Tại sao memory leak? |

---

## 6. perf – Performance Analysis

### What – perf là gì?
`perf` là Linux performance profiling tool, dùng hardware counters và kernel tracepoints để phân tích CPU performance, cache misses, branch prediction, etc.

### How – Sử dụng

```bash
# Cài đặt
apt install linux-tools-common linux-tools-$(uname -r)

# perf stat – performance statistics
perf stat ls /tmp                    # CPU cycles, instructions, cache-misses
perf stat -e cpu-cycles,instructions,cache-misses ls /tmp

# perf top – real-time CPU profiling (giống top nhưng per function)
perf top                             # interactive
perf top -p 1234                     # chỉ process 1234

# perf record + report – sampling profiler
perf record -g ./myapp               # record với call graph
perf report                          # interactive report

# perf record -p (attach)
perf record -p 1234 -g -- sleep 30  # profile 30 giây
perf report --stdio                  # non-interactive output

# Flame graph (cần FlameGraph tools)
perf record -F 99 -p 1234 -g -- sleep 30
perf script | stackcollapse-perf.pl | flamegraph.pl > flame.svg
```

---

## 7. Advanced Process Monitoring

### How – /proc Filesystem Deep Dive

```bash
# /proc/<PID>/ – process info
cat /proc/1234/cmdline | tr '\0' ' '     # full command line
cat /proc/1234/status                    # process status (mem, threads, etc.)
cat /proc/1234/maps                      # memory map (virtual addresses)
cat /proc/1234/smaps                     # detailed memory usage per mapping
cat /proc/1234/fd/                       # file descriptors (symlinks)
ls -la /proc/1234/fd/ | wc -l           # số FD đang dùng
cat /proc/1234/net/tcp                  # TCP connections
cat /proc/1234/io                        # I/O stats (read/write bytes)
cat /proc/1234/schedstat                 # scheduler stats

# /proc system-wide
cat /proc/cpuinfo
cat /proc/meminfo
cat /proc/loadavg                        # load average + running/total processes
cat /proc/net/dev                        # network interface stats
cat /proc/diskstats                      # disk I/O stats
cat /proc/sys/vm/                        # VM tuning parameters
```

### How – Memory Analysis

```bash
# smem – memory reporting (cần cài)
smem -r                              # sort by RSS
smem -r -k                          # sort by human-readable
smem -p                             # percentage
smem --pie                          # pie chart

# Xem memory của process
cat /proc/1234/status | grep -E "VmRSS|VmSize|VmSwap"
# VmSize: virtual memory (thường rất lớn)
# VmRSS:  resident set size (RAM thực sự dùng)
# VmSwap: swap đang dùng

# pmap – memory map của process
pmap 1234                           # address, size, permission, path
pmap -x 1234                        # extended (RSS, dirty)
pmap -d 1234                        # device format

# Tổng hợp memory usage
smem -t -k | tail -1               # total system memory usage
```

### Real-world: Production Debugging

```bash
# Scenario: Java app bị OOM (Out of Memory)
# 1. Xem memory usage hiện tại
ps aux --sort=-%mem | head -5
cat /proc/$(pgrep java)/status | grep Vm

# 2. Check GC overhead
strace -e trace=mmap,munmap -p $(pgrep java) -c  # memory allocation pattern

# 3. Enable core dump để phân tích
ulimit -c unlimited
# (sau khi crash)
ls -lh /core.*                      # hoặc /var/core/
file core.1234                      # verify it's a core dump

# Scenario: Too many open files
lsof -p $(pgrep myapp) | wc -l     # đếm FD
cat /proc/$(pgrep myapp)/limits | grep "open files"

# Scenario: High CPU
perf top -p $(pgrep myapp)          # xem hot functions
strace -c -p $(pgrep myapp) -- sleep 10  # syscall distribution

# Scenario: Process không chịu chết
strace -p <PID> 2>&1 | head         # xem đang blocked ở đâu
cat /proc/<PID>/wchan               # kernel function process đang wait
cat /proc/<PID>/status | grep State  # D = uninterruptible sleep (disk I/O)
```

---

## 8. Compare & Trade-offs

### Trade-offs – Monitoring Tools

| Tool | Use case | Overhead | Info level |
|------|----------|----------|------------|
| `top/htop` | Real-time overview | Thấp | Medium |
| `ps` | Snapshot, scripting | Rất thấp | Low |
| `strace` | Debug syscalls | Cao (10-100x) | Chi tiết |
| `ltrace` | Debug library | Rất cao | Chi tiết |
| `perf` | CPU profiling | Thấp (sampling) | Rất chi tiết |
| `systemd-cgtop` | cgroup resource | Thấp | Per-service |

### Trade-offs – Resource Control

- **cgroups v2**: modern, unified, nhưng nhiều distro cũ vẫn dùng v1
- **ulimit**: áp dụng per-shell session, không persistent trừ khi config
- **systemd limits**: clean, per-service, nhưng cần systemd

---

### Ghi chú – Chủ đề tiếp theo
> **11.4 Networking Deep Dive**: tcpdump, iptables/nftables, netfilter, conntrack, VPN basics
