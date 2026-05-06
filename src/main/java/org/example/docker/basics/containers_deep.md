# Docker Containers – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Container Runtime Stack

### What – Runtime Stack là gì?
**Container runtime** là thành phần tạo và quản lý container ở mức hệ thống. Docker dùng stack nhiều tầng: `dockerd → containerd → containerd-shim → runc`.

### How – Runtime Architecture

```
docker CLI
    ↓ /var/run/docker.sock (Unix socket / REST API)
dockerd (Docker daemon)
    ↓ gRPC (containerd.sock)
containerd
    ↓ fork+exec
containerd-shim-runc-v2  ← process này tồn tại suốt vòng đời container
    ↓ OCI Runtime Spec (config.json)
runc
    ↓ Linux syscalls
Container process (PID 1 trong namespace)
```

**Vai trò của containerd-shim:**
- Cho phép `containerd` restart mà container không bị ảnh hưởng
- Quản lý stdin/stdout/stderr của container
- Report exit status khi container kết thúc
- Giữ `runc` chỉ cần tồn tại trong quá trình create

```bash
# Xem process tree
pstree -p $(pgrep dockerd)
# dockerd(1234)─┬─containerd(1256)─┬─containerd-shim(5678)─┬─nginx(5700)
#               │                  │                         └─nginx(5701)
#               │                  └─containerd-shim(6789)─┬─node(6800)
#               └─...
```

---

## 2. Linux Namespaces – Chi Tiết

### What – Namespaces
Namespaces cung cấp **isolated view** của các tài nguyên hệ thống. Container có 7 namespace riêng.

### How – PID Namespace

```bash
# PID namespace: container có process tree riêng
# PID 1 trong container = process khởi động đầu tiên (ENTRYPOINT)

# Trong container
docker exec myapp ps aux
# PID  USER  COMMAND
#   1  app   node server.js       ← PID 1!
#  23  app   worker thread
#  24  app   worker thread

# Trên host
ps aux | grep node
# 15234 app node server.js        ← PID khác trên host

# Tìm host PID của container PID 1
docker inspect myapp | jq '.[0].State.Pid'  # → 15234

# Xem namespace của container từ host
ls -la /proc/15234/ns/
# pid → pid:[4026532456]   (namespace ID của container)
# vs
ls -la /proc/1/ns/
# pid → pid:[4026531836]   (host namespace)

# Share PID namespace giữa containers (debug)
docker run -d --name app myapp
docker run --rm -it --pid=container:app ubuntu  # thấy processes của 'app'
```

### How – Network Namespace

```bash
# Mỗi container có network stack riêng (interfaces, routing, iptables)

# Tạo network namespace thủ công (để hiểu cơ chế)
ip netns add myns
ip netns exec myns ip addr show     # chỉ có lo (loopback)

# Docker tự động:
# 1. Tạo network namespace cho container
# 2. Tạo veth pair (virtual ethernet cable)
#    veth-host ←→ eth0 (trong container namespace)
# 3. Đặt veth-host vào bridge docker0 (hoặc custom network)
# 4. Assign IP cho eth0 trong container

# Xem veth pairs
ip link show type veth
# 10: vethXXXXXX@if9: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
#     link/ether aa:bb:cc:dd:ee:ff

# Xem network namespace của container
CPID=$(docker inspect --format '{{.State.Pid}}' myapp)
ip netns identify $CPID              # nsenter tương đương

# Exec lệnh trong network namespace của container
nsenter -t $CPID --net -- ip addr show
nsenter -t $CPID --net -- ss -tlnp
nsenter -t $CPID --net -- tcpdump -i eth0 -n
```

### How – Mount Namespace & pivot_root

```bash
# Mount namespace: container có filesystem view riêng
# Cơ chế: pivot_root (thay đổi root filesystem)

# Docker flow để tạo container filesystem:
# 1. Tạo mount namespace mới
# 2. Mount OverlayFS tại /var/lib/docker/overlay2/<container>/merged
# 3. pivot_root: đặt merged/ thành / của container
# 4. Mount /proc, /sys, /dev như mới

# Xem mounts trong container
docker exec myapp cat /proc/mounts
# overlay / overlay rw,relatime,lowerdir=...,upperdir=...,workdir=... 0 0
# tmpfs /dev tmpfs rw,nosuid,size=65536k,mode=755 0 0
# proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0

# Trên host: xem container mount
CPID=$(docker inspect --format '{{.State.Pid}}' myapp)
cat /proc/$CPID/mounts

# nsenter vào mount namespace
nsenter -t $CPID --mount -- ls /   # thấy filesystem của container
```

### How – User Namespace (Rootless)

```bash
# User namespace: map UID/GID của container → UID/GID khác trên host
# root (uid=0) trong container → uid=100000 trên host

# Bật user namespace remapping trong Docker
# /etc/docker/daemon.json:
# { "userns-remap": "default" }

# Kiểm tra mapping
cat /proc/$(docker inspect --format '{{.State.Pid}}' myapp)/uid_map
# 0       100000      65536
# container_uid  host_uid  count
# → uid 0 trong container = uid 100000 trên host
# → uid 1 trong container = uid 100001 trên host

# Kết quả: file tạo bởi container root thuộc về uid 100000 trên host
ls -la /var/lib/docker/100000.100000/volumes/  # user-remapped storage
```

---

## 3. cgroups v2 – Resource Control Chi Tiết

### What – cgroups v2
**Control Groups v2** (unified hierarchy) là cơ chế Linux kiểm soát và giám sát tài nguyên (CPU, memory, I/O) của nhóm processes. Docker dùng cgroups để enforce resource limits.

### How – cgroups v2 Hierarchy

```bash
# Unified hierarchy (v2): tất cả controllers trong 1 tree
# /sys/fs/cgroup/

ls /sys/fs/cgroup/
# cgroup.controllers  cgroup.max.depth  cpu.stat  io.stat  memory.stat ...

# Docker container cgroup path
CONTAINER_ID=$(docker inspect --format '{{.Id}}' myapp)
ls /sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope/
# cgroup.controllers  cpu.max  cpu.stat  io.max  memory.current
# memory.high  memory.max  memory.swap.max  pids.max

# Xem resource usage
cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope/memory.current
# 52428800  (50MB)

cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope/cpu.stat
# usage_usec 1234567
# user_usec  900000
# system_usec 334567
```

### How – CPU Control (v2)

```bash
# cpu.max: quota period
cat /sys/fs/cgroup/.../cpu.max
# 100000 100000   → 100ms quota per 100ms period = 1 CPU
# 50000 100000    → 50ms quota = 0.5 CPU
# max 100000      → unlimited

# Docker: --cpus=1.5 → quota=150000, period=100000
docker run --cpus=1.5 myapp

# cpu.weight (chia sẻ relative, v2 thay cpu.shares)
# 100 = default; 200 = gấp đôi weight
echo 200 > /sys/fs/cgroup/.../cpu.weight

# cpu.cpuset: pin to specific CPUs
docker run --cpuset-cpus="0,1" myapp
cat /sys/fs/cgroup/.../cpuset.cpus
# 0-1
```

### How – Memory Control (v2)

```bash
# memory.max: hard limit → OOM kill nếu vượt
# memory.high: soft limit → throttle trước khi OOM (v2 new!)
# memory.swap.max: swap limit (v2 thay memory.memsw.limit_in_bytes)

# Docker mapping:
# --memory=512m        → memory.max = 536870912
# --memory-swap=1g     → memory.swap.max = 536870912 (swap only, không phải total)

docker run --memory=512m --memory-swap=1g myapp
# → RAM: 512MB hard limit
# → Swap: 512MB additional swap (total = 1GB - 512MB RAM = 512MB swap)
# → --memory-swap == --memory: NO SWAP

# Xem memory usage
docker stats --no-stream myapp | awk '{print $4}'

# OOM events
cat /sys/fs/cgroup/.../memory.events
# low 0
# high 0
# max 3           ← số lần hit max limit
# oom 1           ← số OOM events
# oom_kill 1      ← số lần OOM killer kích hoạt

# Xem OOM kill từ kernel
dmesg | grep -i "out of memory"
dmesg | grep -i "oom_kill"
```

### How – I/O Control (v2)

```bash
# io.max: rate limit theo device
# Format: MAJOR:MINOR rbps=<bytes/s> wbps=<bytes/s> riops=<iops> wiops=<iops>

cat /sys/fs/cgroup/.../io.max
# 8:0 rbps=10485760 wbps=10485760   → 10MB/s read+write cho /dev/sda

# Docker: --device-read-bps, --device-write-bps
docker run \
  --device-read-bps /dev/sda:10mb \
  --device-write-bps /dev/sda:5mb \
  --device-read-iops /dev/sda:1000 \
  myapp

# io.stat: actual I/O statistics
cat /sys/fs/cgroup/.../io.stat
# 8:0 rbytes=12345678 wbytes=23456789 rios=1000 wios=2000
```

### How – PIDs Control

```bash
# pids.max: giới hạn số processes (fork bomb protection)
docker run --pids-limit=100 myapp

cat /sys/fs/cgroup/.../pids.max
# 100
cat /sys/fs/cgroup/.../pids.current
# 3
```

---

## 4. Container Filesystem – OverlayFS Chi Tiết

### How – Copy-on-Write (CoW) Mechanics

```bash
# Đọc file từ lower layer → zero overhead (direct read)
# Ghi file từ lower layer → copy lên upper layer trước (one-time cost)

# Demo:
docker run --rm -it alpine sh -c "
  # Đọc file từ base image (lower layer)
  cat /etc/hostname          # fast, từ lower

  # Sửa file → CoW: copy lên upper layer
  echo 'modified' > /etc/hostname

  # Kiểm tra: file mới ở upper layer
  ls -la /etc/hostname
"

# Trên host: xem upper layer của container
CONTAINER_ID=$(docker inspect --format '{{.GraphDriver.Data.UpperDir}}' myapp)
ls $CONTAINER_ID/etc/
# hostname    ← file đã được copy-up

# Xem lower layers (read-only image layers)
docker inspect --format '{{.GraphDriver.Data.LowerDir}}' myapp | tr ':' '\n'
```

### How – Container Writable Layer Size

```bash
# Writable layer (UpperDir) chứa:
# 1. Files được sửa (copy-on-write)
# 2. Files mới tạo
# 3. Whiteout files (xóa)

# Xem size của writable layer
docker ps -s                         # SIZE column: container layer size
docker ps --format "{{.Names}}\t{{.Size}}"

# Dọn dẹp: xóa files lớn trong container
docker exec myapp sh -c "find /tmp -size +100M -delete"
docker exec myapp sh -c "find /var/log -name '*.log' -mtime +7 -delete"

# Export container state → image (snapshot)
docker commit myapp myapp:snapshot   # writable → new layer
```

---

## 5. Container Process Management

### How – Signal Handling & PID 1

```bash
# PID 1 trong container nhận signals khác thường:
# - Kernel KHÔNG gửi SIGCHLD đến PID 1 (zombie processes không được reap)
# - SIGTERM không có default handler trong PID 1 nếu không set up

# Vấn đề: shell script làm PID 1
# script.sh PID=1 → java PID=2
# docker stop → SIGTERM gửi đến PID=1 (script.sh)
# script.sh không forward → java không graceful shutdown

# GIẢI PHÁP 1: exec trong script (thay thế script process)
#!/bin/sh
exec java -jar app.jar            # exec: java trở thành PID 1

# GIẢI PHÁP 2: dumb-init (signal proxy)
FROM node:20-alpine
RUN apk add --no-cache dumb-init
ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "server.js"]
# dumb-init làm PID 1: forward signals, reap zombies

# GIẢI PHÁP 3: tini (tương tự dumb-init)
FROM ubuntu
ENV TINI_VERSION v0.19.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
RUN chmod +x /tini
ENTRYPOINT ["/tini", "--"]
CMD ["my-app"]

# Docker có --init flag (dùng tini)
docker run --init myapp
```

### How – Container Tracing & Debugging

```bash
# strace: trace system calls của container process
CPID=$(docker inspect --format '{{.State.Pid}}' myapp)
strace -p $CPID -f -e trace=network  # chỉ network syscalls
strace -p $CPID -f -c               # summary sau Ctrl+C

# Attach debugger từ host vào container process
# gdb: attach đến process
sudo gdb -p $CPID

# perf: performance profiling
sudo perf top -p $CPID
sudo perf record -p $CPID -g -- sleep 30
sudo perf report

# Ephemeral debug container (K8s style trong Docker)
docker run -it --rm \
  --pid=container:myapp \
  --network=container:myapp \
  --cap-add SYS_PTRACE \
  nicolaka/netshoot  # network debug tools

# nsenter: enter namespaces của container
CPID=$(docker inspect --format '{{.State.Pid}}' myapp)
nsenter -t $CPID --all             # vào tất cả namespaces
nsenter -t $CPID --net -- ss -tlnp # chỉ network namespace
nsenter -t $CPID --pid -- ps aux   # chỉ PID namespace
```

### How – Resource Monitoring Thực Tế

```bash
# docker stats với custom format
docker stats --format \
  "{{.Name}}\tCPU:{{.CPUPerc}}\tMEM:{{.MemUsage}}\tNET:{{.NetIO}}\tI/O:{{.BlockIO}}"

# Xuất metrics thô từ /proc
CPID=$(docker inspect --format '{{.State.Pid}}' myapp)

# CPU usage
cat /proc/$CPID/stat | awk '{print "utime:", $14, "stime:", $15}'

# Memory
cat /proc/$CPID/status | grep -E "VmRSS|VmPeak|VmSwap"

# Open file descriptors
ls /proc/$CPID/fd | wc -l
cat /proc/$CPID/limits | grep "open files"

# Threads
cat /proc/$CPID/status | grep Threads
```

---

## 6. Container Patterns Nâng Cao

### How – Init Container Pattern

```yaml
# Init containers: chạy trước main containers, setup environment
# (Docker Compose không native; cần script hoặc depends_on)

services:
  # Migration container chạy trước app
  migrate:
    image: myapp:latest
    command: ["sh", "-c", "python manage.py migrate && echo done"]
    depends_on:
      db:
        condition: service_healthy

  app:
    image: myapp:latest
    depends_on:
      migrate:
        condition: service_completed_successfully
```

### How – Sidecar Pattern

```yaml
services:
  app:
    image: myapp
    volumes:
      - shared-logs:/var/log/app

  # Sidecar: đọc logs và gửi đến logging backend
  log-shipper:
    image: fluent/fluentd:v1.16-debian-1
    volumes:
      - shared-logs:/var/log/app:ro
      - ./fluentd.conf:/fluentd/etc/fluentd.conf:ro
    depends_on:
      - app

  # Sidecar: metrics exporter
  metrics:
    image: prom/node-exporter
    pid: "host"                      # share host PID namespace để đọc /proc
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro

volumes:
  shared-logs:
```

### How – Ambassador Pattern

```yaml
# Ambassador: proxy cho external service
services:
  app:
    image: myapp
    environment:
      - DB_HOST=db-proxy  # gọi ambassador, không phải DB thật

  db-proxy:               # Ambassador: kiểm soát connection, retry, circuit breaking
    image: haproxy:alpine
    volumes:
      - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
```

### Compare – docker exec vs nsenter

| | docker exec | nsenter |
|--|------------|---------|
| Yêu cầu | Docker daemon | Root trên host |
| Namespace vào | Tất cả namespaces của container | Chọn specific namespaces |
| Khi dùng | Day-to-day debug | Deep system debug, performance profiling |
| Audit | Docker logs | Không audit |

### Trade-offs
- CoW overhead: ghi file lần đầu có overhead; I/O nhiều nên dùng volumes
- PID 1 responsibilities: cần dumb-init/tini cho production
- cgroups v2: powerful nhưng cần kernel >= 4.15; docker v20.10+ support đầy đủ

### Real-world Usage
```bash
# Production: kiểm tra container health thực tế
docker inspect myapp --format '
Container: {{.Name}}
PID: {{.State.Pid}}
OOMKilled: {{.State.OOMKilled}}
ExitCode: {{.State.ExitCode}}
Started: {{.State.StartedAt}}
Restarts: {{.RestartCount}}'

# Leak detection: theo dõi file descriptor growth
watch -n 5 "ls /proc/$(docker inspect --format '{{.State.Pid}}' myapp)/fd | wc -l"

# Memory leak detection
watch -n 10 "cat /sys/fs/cgroup/system.slice/docker-$(docker inspect --format '{{.Id}}' myapp).scope/memory.current | numfmt --to=iec"
```

### Ghi chú – Chủ đề tiếp theo
> Networking Deep Dive – iptables DOCKER chains, veth pairs, VXLAN overlay internals

---

*Cập nhật lần cuối: 2026-05-06*
