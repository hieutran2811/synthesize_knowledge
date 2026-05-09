# Performance Tuning – Linux

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. CPU Performance Tuning

### What – CPU Tuning là gì?
Tối ưu CPU performance gồm: CPU governor, NUMA topology, process affinity, CPU isolation, interrupt handling.

### How – CPU Governor & Frequency Scaling

```bash
# Xem CPU frequency scaling
cat /sys/bus/cpu/drivers/acpi-cpufreq/*/cpufreq/scaling_governor
# hoặc:
cpupower frequency-info                # cần: apt install linux-tools-common

# Governors:
# performance  – luôn dùng max frequency (server: production)
# powersave    – luôn dùng min frequency (tiết kiệm điện)
# schedutil    – kernel scheduler-based (modern default)
# ondemand     – tăng frequency khi cần (desktop)
# conservative – tăng chậm hơn ondemand

# Set governor (tất cả CPUs)
cpupower frequency-set -g performance

# Persistent (grub)
echo 'GRUB_CMDLINE_LINUX="cpufreq.default_governor=performance"' >> /etc/default/grub
update-grub

# Disable TurboBoost (nếu cần consistent latency)
echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo

# C-states (sleep states) – disable cho low latency
for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
    echo 1 > "$cpu"
done
```

### How – NUMA (Non-Uniform Memory Access)

```bash
# Xem NUMA topology
numactl --hardware                     # NUMA nodes, CPUs, memory
numactl --show                         # current NUMA policy
numactl -l ls                          # local allocation
lscpu | grep "NUMA node"

# Bind process to NUMA node
numactl --cpunodebind=0 --membind=0 ./myapp    # pin to node 0
numactl --physcpubind=0,1,2,3 ./myapp          # pin to specific CPUs

# NUMA-aware memory allocation
numactl --interleave=all ./myapp               # interleave memory across nodes

# Check NUMA stats
numastat                               # per-node memory stats
numastat -c <process>                  # per-process NUMA stats

# NUMA balancing (kernel auto-migration)
echo 1 > /proc/sys/kernel/numa_balancing
```

### How – CPU Affinity & Isolation

```bash
# taskset – set/get CPU affinity
taskset -cp 0,1 1234                   # pin PID 1234 to CPUs 0,1
taskset -c 0 ./myapp                   # run myapp on CPU 0
taskset -p 1234                        # show current affinity (hex mask)

# CPU isolation (grub parameter)
# GRUB_CMDLINE_LINUX="isolcpus=2,3 nohz_full=2,3 rcu_nocbs=2,3"
# CPUs 2,3 reserved for specific workloads

# systemd CPU affinity
# /etc/systemd/system/myapp.service
# [Service]
# CPUAffinity=0 1                      # pin to CPU 0,1

# IRQ affinity – direct hardware interrupts to specific CPUs
cat /proc/interrupts                   # xem interrupt distribution
echo "ff" > /proc/irq/24/smp_affinity  # all CPUs handle IRQ 24
echo "01" > /proc/irq/24/smp_affinity  # only CPU 0

# irqbalance – automatic IRQ balancing
systemctl stop irqbalance              # disable before manual tuning
```

---

## 2. Memory Performance Tuning

### How – Memory Parameters

```bash
# /proc/sys/vm – Virtual Memory subsystem
# Xem tất cả
sysctl -a | grep "^vm\."

# Swappiness (0-200, mặc định 60)
# 0: avoid swap, prefer OOM kill; 100: swap aggressively
sysctl -w vm.swappiness=10             # server: minimize swap
# Persistent:
echo "vm.swappiness=10" >> /etc/sysctl.d/99-performance.conf

# Dirty page limits
sysctl vm.dirty_ratio                  # % RAM before blocking writes (default: 20)
sysctl vm.dirty_background_ratio       # % RAM to start background writeback (default: 10)

# Cho database servers (minimize dirty pages)
cat >> /etc/sysctl.d/99-performance.conf << 'EOF'
vm.dirty_ratio = 5
vm.dirty_background_ratio = 2
vm.dirty_writeback_centisecs = 500     # flush every 5 seconds
vm.dirty_expire_centisecs = 1000       # expire after 10 seconds
EOF

# Transparent Huge Pages (THP)
cat /sys/kernel/mm/transparent_hugepage/enabled
# [always] madvise never

# Disable THP (recommended cho databases: Redis, MongoDB, MySQL)
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag

# Persistent THP disable
cat > /etc/systemd/system/disable-thp.service << 'EOF'
[Unit]
Description=Disable Transparent Huge Pages

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable --now disable-thp

# Overcommit memory
# 0: heuristic (default)
# 1: always allow (risk OOM)
# 2: never overcommit beyond swap + percentage
sysctl vm.overcommit_memory
sysctl vm.overcommit_ratio             # percentage (default 50)
```

### How – HugePages (Static)

```bash
# HugePages: large memory pages (2MB), reduce TLB pressure
# Good for: databases, JVM with large heap

# Check current
cat /proc/meminfo | grep Huge
# HugePages_Total: 0
# Hugepagesize:    2048 kB

# Calculate pages needed (e.g., 8GB Oracle)
# 8*1024*1024 / 2048 = 4096 pages

# Set HugePages
echo "vm.nr_hugepages=4096" >> /etc/sysctl.d/99-hugepages.conf
sysctl -p /etc/sysctl.d/99-hugepages.conf

# Mount hugetlbfs
mkdir /mnt/hugepages
mount -t hugetlbfs nodev /mnt/hugepages
echo "nodev /mnt/hugepages hugetlbfs defaults 0 0" >> /etc/fstab
```

### How – OOM Killer Tuning

```bash
# OOM score: -1000 (never kill) → 1000 (kill first)
# Xem OOM score
cat /proc/1234/oom_score               # current score
cat /proc/1234/oom_score_adj           # adjustment (-1000 to 1000)

# Protect critical process
echo -1000 > /proc/$(pgrep postgres)/oom_score_adj   # never kill postgres
echo -1000 > /proc/$(pgrep mysqld)/oom_score_adj

# systemd: OOMScoreAdjust
# [Service]
# OOMScoreAdjust=-1000                 # never kill

# Make less likely to be killed
echo 200 > /proc/1234/oom_score_adj    # more likely than default
echo -500 > /proc/1234/oom_score_adj   # less likely

# OOM killer notifications
dmesg | grep "Out of memory"
journalctl -k | grep "OOM"
```

---

## 3. Network Performance Tuning

### How – TCP/IP Stack Tuning

```bash
# High-performance web server settings
cat > /etc/sysctl.d/99-network-performance.conf << 'EOF'
# TCP buffer sizes (read/write)
net.core.rmem_default = 262144
net.core.rmem_max = 16777216           # 16MB
net.core.wmem_default = 262144
net.core.wmem_max = 16777216

# TCP-specific buffers
net.ipv4.tcp_rmem = 4096 87380 16777216   # min default max
net.ipv4.tcp_wmem = 4096 65536 16777216

# Connection queue
net.core.somaxconn = 65535             # listen backlog
net.ipv4.tcp_max_syn_backlog = 65535   # SYN queue

# Time-Wait optimization
net.ipv4.tcp_tw_reuse = 1             # reuse TIME_WAIT sockets
net.ipv4.tcp_fin_timeout = 15         # reduce FIN_WAIT2 timeout

# Port range
net.ipv4.ip_local_port_range = 1024 65535

# TCP keepalive
net.ipv4.tcp_keepalive_time = 300      # idle time before keepalive
net.ipv4.tcp_keepalive_intvl = 30     # interval between probes
net.ipv4.tcp_keepalive_probes = 3     # number of probes

# Connections
net.ipv4.tcp_max_tw_buckets = 1440000  # max TIME_WAIT sockets
net.netfilter.nf_conntrack_max = 524288  # max tracked connections

# BBR congestion control (Linux 4.9+)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# Receive buffer auto-tuning
net.ipv4.tcp_moderate_rcvbuf = 1
EOF

sysctl -p /etc/sysctl.d/99-network-performance.conf

# Verify BBR
sysctl net.ipv4.tcp_congestion_control  # should show bbr
lsmod | grep bbr                         # should show tcp_bbr
```

### How – Network Interface Tuning

```bash
# ethtool – NIC settings
ethtool eth0                           # interface info
ethtool -i eth0                        # driver info
ethtool -S eth0                        # statistics
ethtool -k eth0                        # offload features

# Ring buffer (reduce packet drops)
ethtool -g eth0                        # current ring buffer
ethtool -G eth0 rx 4096 tx 4096        # set ring buffer

# Offloading (usually keep enabled)
ethtool -k eth0 | grep -E "tcp-segmentation|generic-segmentation|large-receive"
ethtool -K eth0 tso on gso on gro on  # enable offloads

# RSS – Receive Side Scaling (multi-queue)
ethtool -l eth0                        # queues info
ethtool -L eth0 combined 4             # 4 combined queues

# CPU-NIC mapping (align with NUMA)
cat /sys/class/net/eth0/queues/rx-0/rps_cpus   # RSS CPU mask

# Persistent: /etc/network/if-up.d/ethtool-tune
# or use NetworkManager dispatcher

# txqueuelen (transmit queue length)
ip link set eth0 txqueuelen 10000      # default 1000; increase for high-throughput

# MTU (Jumbo frames for internal network)
ip link set eth0 mtu 9000             # jumbo frames (9KB)
# Verify all hops support it: ping -M do -s 8972 host
```

---

## 4. Disk I/O Performance Tuning

### How – I/O Scheduler

```bash
# Xem scheduler
cat /sys/block/sda/queue/scheduler
# none [mq-deadline] kyber bfq
# Brackets = current scheduler

# Schedulers:
# none (noop)  – no scheduling, bare metal SSD/NVMe
# mq-deadline  – deadline-based, general purpose
# kyber        – low-latency for fast storage
# bfq          – fair queuing, good for mixed workloads

# Set scheduler (temporary)
echo "none" > /sys/block/nvme0n1/queue/scheduler    # NVMe: none
echo "mq-deadline" > /sys/block/sda/queue/scheduler  # SSD/HDD

# Persistent (udev rule)
cat > /etc/udev/rules.d/60-scheduler.rules << 'EOF'
# NVMe: no scheduler
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
# SSD: mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# HDD: bfq
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

udevadm control --reload-rules && udevadm trigger

# Queue depth & read-ahead
cat /sys/block/sda/queue/nr_requests   # queue depth (default 64)
echo 256 > /sys/block/sda/queue/nr_requests  # increase for HDD

cat /sys/block/sda/queue/read_ahead_kb  # read-ahead (default 128KB)
echo 2048 > /sys/block/sda/queue/read_ahead_kb  # sequential workloads

# rotational flag
cat /sys/block/sda/queue/rotational    # 1=HDD, 0=SSD
```

### How – Filesystem Performance

```bash
# ext4 mount options for performance
mount -o relatime,noatime,data=writeback,barrier=0 /dev/sdb1 /data
# relatime  – update atime only if older than mtime (compromise)
# noatime   – never update access time (best perf, breaks some apps)
# data=writeback – no ordered mode (faster, slight risk)
# barrier=0 – disable write barriers (DANGEROUS without battery backup!)

# XFS mount options
mount -o noatime,logbsize=256k,largeio /dev/sdb1 /data
# logbsize=256k – larger log buffer for high-throughput writes

# tmpfs (RAM-based)
mount -t tmpfs -o size=2G,noatime tmpfs /tmp
echo "tmpfs /tmp tmpfs size=2G,noatime 0 0" >> /etc/fstab

# sync vs async writes
# sync: every write synced to disk immediately (slow)
# async: kernel batches writes (default, fast)
# Specific file: fdatasync(), fsync() from application
```

---

## 5. eBPF – Modern Performance Analysis

### What – eBPF là gì?
**eBPF (extended Berkeley Packet Filter)** cho phép chạy sandboxed programs trong kernel để observe và trace. BCC và bpftrace là frontends phổ biến.

### How – BCC Tools

```bash
# Cài đặt
apt install bpfcc-tools linux-headers-$(uname -r)

# Tracing tools (BCC)
execsnoop                              # trace process executions
opensnoop -p 1234                      # trace file opens per process
tcpconnect                             # trace TCP connections
tcpaccept                              # trace TCP accepts
biolatency                             # block I/O latency histogram
biosnoop                               # block I/O per process
cachestat                              # page cache stats
cachetop                               # top for page cache
filelife -p 1234                       # file lifecycle (create to delete)
fileslower 10                          # file operations > 10ms
dbstat mysql                           # database queries
mysqld_qslower 1                       # MySQL queries > 1ms
profile -F 99 -p 1234 30              # CPU profiling 30s

# runqlat – CPU scheduler latency
runqlat 10                             # 10 second sample
# Histogram of time spent waiting on run queue
```

### How – bpftrace

```bash
# Cài đặt
apt install bpftrace

# Basic bpftrace programs
# Trace all execve syscalls
bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("%s called %s\n", comm, str(args->filename)); }'

# Trace file opens by process
bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args->filename)); }'

# Histogram of read sizes
bpftrace -e 'tracepoint:syscalls:sys_exit_read { @[pid] = hist(args->ret); }'

# Count syscalls per second
bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm] = count(); } interval:s:1 { print(@); clear(@); }'

# Measure function latency
bpftrace -e 'kprobe:do_sys_open { @start[tid] = nsecs; }
             kretprobe:do_sys_open /@start[tid]/ {
                 @ms[comm] = hist((nsecs - @start[tid]) / 1000000);
                 delete(@start[tid]);
             }'
```

---

## 6. Profiling Tools

### How – perf + Flame Graphs

```bash
# CPU profiling với perf
perf record -F 99 -ag -- sleep 30      # sample all processes, 30s
perf report                            # interactive
perf report --stdio | head -40         # text output

# Flame graph generation
git clone https://github.com/brendangregg/FlameGraph
perf record -F 99 -ag -- sleep 30
perf script > out.perf
./FlameGraph/stackcollapse-perf.pl out.perf > out.folded
./FlameGraph/flamegraph.pl out.folded > flame.svg
# Open flame.svg in browser

# perf stat
perf stat -e cpu-cycles,instructions,cache-misses,cache-references \
    -p $(pgrep java) -- sleep 10

# perf top (real-time)
perf top -p $(pgrep myapp)
```

### How – valgrind (Memory profiling)

```bash
# Memory leaks
valgrind --leak-check=full ./myapp

# Cache profiling
valgrind --tool=cachegrind ./myapp
cg_annotate cachegrind.out.*           # annotate results

# Heap profiling
valgrind --tool=massif ./myapp
ms_print massif.out.*                  # analyze

# Thread checking
valgrind --tool=helgrind ./myapp        # race conditions
```

---

## 7. Real-world Production Tuning

### How – Web Server Tuning

```bash
# Nginx performance
cat >> /etc/nginx/nginx.conf << 'EOF'
worker_processes auto;
worker_rlimit_nofile 65536;

events {
    worker_connections 65536;
    multi_accept on;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    client_body_buffer_size 16k;
    client_max_body_size 8m;
    large_client_header_buffers 4 16k;
    gzip on;
    gzip_comp_level 2;
    open_file_cache max=200000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
}
EOF

# Java/JVM tuning
java -Xms2g -Xmx2g \                   # heap size (set equal to avoid resize)
     -XX:+UseG1GC \                    # G1 GC (modern)
     -XX:MaxGCPauseMillis=200 \        # target pause time
     -XX:+AlwaysPreTouch \            # pre-allocate memory
     -XX:+DisableExplicitGC \         # prevent System.gc()
     -Djava.security.egd=file:/dev/urandom \  # faster random
     -jar app.jar
```

### How – Database Tuning (PostgreSQL)

```bash
# postgresql.conf
shared_buffers = 4GB              # 25% of RAM
effective_cache_size = 12GB       # 75% of RAM
work_mem = 64MB                   # per sort/hash operation
maintenance_work_mem = 1GB        # VACUUM, CREATE INDEX
wal_buffers = 64MB
checkpoint_completion_target = 0.9
random_page_cost = 1.1            # SSD (default 4.0 for HDD)
effective_io_concurrency = 200    # SSD (default 1 for HDD)
max_parallel_workers_per_gather = 4
max_worker_processes = 8
max_parallel_workers = 8
```

---

## 8. Compare & Trade-offs

### Compare – Profiling Tools

| Tool | Level | Use case | Overhead |
|------|-------|----------|----------|
| top/htop | High-level | Overview | Minimal |
| perf | Kernel/user | CPU profiling | Low (sampling) |
| eBPF/bpftrace | Kernel | Any tracing | Low |
| strace | Syscall | Debug | High |
| valgrind | Application | Memory analysis | Very high (10-50x) |
| flamegraph | Visual | CPU bottleneck | None (post-process) |

### Trade-offs

- **BBR vs CUBIC**: BBR tốt hơn trên high-latency/lossy links; CUBIC tốt hơn trên low-latency LAN
- **Huge Pages**: giảm TLB miss nhưng có thể cause latency spikes nếu không pre-allocated
- **noatime**: cải thiện I/O performance nhưng một số apps (rsync, mutt) cần atime
- **I/O scheduler none**: tốt nhất cho NVMe nhưng không có fairness between processes
- **THP**: tự động nhưng gây latency spikes; static huge pages tốt hơn cho production

---

### Ghi chú – Chủ đề tiếp theo
> **13.4 Backup & Recovery**: rsync strategies, LVM snapshots, disaster recovery, backup verification
