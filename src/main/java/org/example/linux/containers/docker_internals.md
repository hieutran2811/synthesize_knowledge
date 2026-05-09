# Docker Internals – Linux Layer

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Docker Architecture Overview

### What – Docker Internals là gì?
Docker là tập hợp các tools xây dựng trên Linux kernel primitives: **containerd** (runtime manager), **runc** (OCI runtime), **overlay2** (filesystem), **veth pairs + iptables** (networking).

### How – Component Architecture

```
Docker CLI (docker)
        ↓ REST API (Unix socket /var/run/docker.sock)
Docker Daemon (dockerd)
        ↓ gRPC
containerd (container lifecycle)
        ↓ fork/exec
containerd-shim (per container)
        ↓
runc (create namespace, cgroups, exec process)
        ↓
Container Process (PID 1 inside namespace)
```

### How – docker inspect Deep Dive

```bash
# Full container info
docker inspect mycontainer | jq '.[0]'

# Networking
docker inspect mycontainer | jq '.[0].NetworkSettings'
# IPAddress: 172.17.0.2
# MacAddress: 02:42:ac:11:00:02
# Gateway: 172.17.0.1
# Ports: ...

# Mounts
docker inspect mycontainer | jq '.[0].Mounts'

# Config
docker inspect mycontainer | jq '.[0].Config'
# Env, Cmd, Image, ...

# State
docker inspect mycontainer | jq '.[0].State'
# Pid, Status, StartedAt, ...

# HostConfig (resource limits)
docker inspect mycontainer | jq '.[0].HostConfig'
# Memory, CpuShares, Devices, ...
```

---

## 2. overlay2 Filesystem

### What – overlay2 là gì?
**overlay2** là union filesystem driver (dùng kernel overlayfs) cho phép Docker layers. Multiple read-only layers + 1 writable layer = unified view.

### How – Image Layers

```bash
# Xem image layers
docker image inspect nginx | jq '.[0].RootFS.Layers'
# Mỗi RootFS layer là một SHA256 hash

# Xem layer storage
ls /var/lib/docker/overlay2/
# Mỗi thư mục = 1 layer

# Layer structure
ls /var/lib/docker/overlay2/<layer-id>/
# diff/     – files changed in this layer
# link      – short ID
# lower     – parent layers (colon-separated short IDs)
# merged/   – unified view (only for running containers)
# work/     – overlayfs work directory

# Xem diff của container layer (writable)
docker diff mycontainer
# A /var/log/nginx/access.log   (added)
# C /etc/nginx/nginx.conf        (changed)

# Theo dõi overlay mounts
cat /proc/mounts | grep overlay
# overlay /var/lib/docker/overlay2/<id>/merged overlay
# rw,lowerdir=<id>/diff:<id>/diff,upperdir=<id>/diff,workdir=<id>/work
```

### How – Copy-on-Write Mechanics

```bash
# Image layers (read-only):
Layer 0 (base): /bin /lib /etc/hosts
Layer 1:        /usr/bin/nginx
Layer 2:        /etc/nginx/nginx.conf (default config)

# Container layer (read-write):
Container:      /etc/nginx/nginx.conf (modified → copied here first)
                /var/log/nginx/ (new files)

# Read: look from top layer down
# First time read /etc/nginx/nginx.conf → found in layer 2 (read-only)
# After modification → file copied to container layer (upperdir), then modified

# This is CoW: copy file on first write
# Large files = large copy on first modification!

# Inspect overlay from host
CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' mycontainer)
cat /proc/$CONTAINER_PID/mounts | grep overlay
```

### How – layer caching trong builds

```dockerfile
# Dockerfile: layer order matters for cache
# Thay đổi ở layer N → tất cả layers sau N phải rebuild

# BAD: code thay đổi sẽ invalidate npm install
FROM node:18
COPY . .                              # code thay đổi
RUN npm install                       # phải chạy lại!

# GOOD: npm install cached (package.json không thay đổi)
FROM node:18
COPY package*.json ./                 # ít thay đổi
RUN npm install                       # cached!
COPY . .                              # code thay đổi: chỉ COPY chạy lại

# Multi-stage để minimize layers
FROM golang:1.21 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o server .

FROM alpine:3.18                      # tiny final image
COPY --from=builder /app/server /
CMD ["/server"]
```

---

## 3. Docker Networking Internals

### How – Bridge Network (default)

```bash
# Docker default: bridge network (docker0)
ip addr show docker0
# docker0: 172.17.0.1/16

# Mỗi container kết nối qua veth pair
# Container side: eth0 (trong net namespace)
# Host side: vethXXXXXX

# Xem veth pairs
ip link show type veth
# veth4a1b2c3d@if6: ...  (host end → interface 6 trong container)

# Find container's veth
CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' mycontainer)
nsenter -t $CONTAINER_PID --net ip link show
# 6: eth0@if11  ← index 11 = veth on host

ip link show | grep "11:"
# 11: veth4a1b2c3d@if6  ← this is the host-side veth

# Bridge connectivity
bridge link show docker0
# veth4a1b2c3d master docker0  ← veth is bridged

# Full path: Container eth0 ↔ veth pair ↔ docker0 bridge ↔ host routing
```

### How – iptables NAT (Docker networking)

```bash
# Docker tạo iptables rules tự động

# Xem rules
iptables -t nat -L DOCKER -n -v
iptables -t filter -L DOCKER -n -v
iptables -t filter -L DOCKER-ISOLATION-STAGE-1 -n -v

# Port mapping: host:8080 → container:80
# When docker run -p 8080:80
iptables -t nat -L DOCKER -n
# DNAT tcp -- 0.0.0.0/0  0.0.0.0/0  tcp dpt:8080 to:172.17.0.2:80

# Inter-container: DOCKER chain allows forwarding
# iptables -A DOCKER-USER -i docker0 -j RETURN  (allow internal)

# Container outbound: MASQUERADE
iptables -t nat -L POSTROUTING -n
# MASQUERADE all -- 172.17.0.0/16 !172.17.0.0/16  (NAT outbound)

# Khi container dùng --network=host: bypass toàn bộ
```

### How – Custom Networks

```bash
# User-defined bridge: có DNS (container name resolution)
docker network create mynet

docker run --network mynet --name app1 myapp
docker run --network mynet --name db1 postgres

# app1 có thể connect bằng "db1" hostname
# Docker internal DNS: 127.0.0.11 (trong container)

# Xem network config
docker network inspect mynet | jq '.[0]'

# Xem DNS trong container
docker exec app1 cat /etc/resolv.conf
# nameserver 127.0.0.11  ← Docker embedded DNS
# options ndots:0

# macvlan: container có MAC và IP trên LAN trực tiếp
docker network create -d macvlan \
    --subnet=192.168.1.0/24 \
    --gateway=192.168.1.1 \
    -o parent=eth0 \
    macvlan_net

docker run --network macvlan_net --ip=192.168.1.100 nginx

# ipvlan: similar but L3 routing, no new MAC
docker network create -d ipvlan \
    --subnet=192.168.1.0/24 \
    --gateway=192.168.1.1 \
    -o parent=eth0 \
    -o ipvlan_mode=l3 \
    ipvlan_net
```

---

## 4. cgroups trong Docker

### How – Resource Limits

```bash
# CPU limits
docker run --cpus="1.5" nginx            # 1.5 CPUs
docker run --cpu-shares=512 nginx        # relative weight (default 1024)
docker run --cpu-period=100000 --cpu-quota=50000 nginx  # 50% CPU
docker run --cpuset-cpus="0,1" nginx     # pin to CPU 0,1

# Memory limits
docker run -m 512m nginx                  # 512MB memory limit
docker run --memory=512m --memory-swap=1g nginx  # memory + swap
docker run --memory-reservation=256m nginx  # soft limit

# I/O limits
docker run --device-write-bps /dev/sda:10mb nginx  # 10MB/s write
docker run --device-read-iops /dev/sda:1000 nginx  # 1000 IOPS

# Verify via cgroups
CONTAINER_ID=$(docker inspect --format '{{.Id}}' mycontainer)
cat /sys/fs/cgroup/memory/docker/$CONTAINER_ID/memory.limit_in_bytes
cat /sys/fs/cgroup/cpu/docker/$CONTAINER_ID/cpu.cfs_quota_us

# Or v2:
cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope/memory.max
cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope/cpu.max
```

---

## 5. Security Internals

### How – seccomp trong Docker

```bash
# Docker default seccomp profile blocks:
# ~44 syscalls (e.g., ptrace, kexec, mount, swapon, reboot...)

# Run without seccomp (insecure!)
docker run --security-opt seccomp=unconfined nginx

# Custom seccomp profile
docker run --security-opt seccomp=/path/to/profile.json nginx

# Xem default profile
docker info | grep -i seccomp
cat /etc/docker/seccomp.json         # default profile location

# Xem syscalls blocked
strace -c docker run busybox sleep 1 2>&1 | grep "Operation not permitted"
```

### How – Capabilities trong Docker

```bash
# Default Docker capabilities (subset of full root)
# Dropped: SYS_MODULE, SYS_RAWIO, SYS_PACCT, SYS_NICE, SYS_RESOURCE,
#          SYS_TIME, SYS_TTY_CONFIG, AUDIT_WRITE, SETFCAP, MAC_OVERRIDE,
#          MAC_ADMIN, NET_ADMIN (and many more)
# Kept: CHOWN, DAC_OVERRIDE, FSETID, FOWNER, MKNOD, NET_RAW, SETGID,
#       SETUID, SETFCAP, SETPCAP, NET_BIND_SERVICE, SYS_CHROOT, KILL, AUDIT_WRITE

# Drop all, add only what's needed (principle of least privilege)
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE nginx

# Privileged container (BAD for security, like running as root)
docker run --privileged nginx   # AVOID in production!

# Xem capabilities của process trong container
docker exec mycontainer cat /proc/self/status | grep Cap
capsh --decode=00000000a80425fb     # decode hex

# Read-only filesystem
docker run --read-only \
    --tmpfs /tmp \
    --tmpfs /var/run \
    nginx                            # nginx only writes to /tmp and /var/run
```

### How – AppArmor trong Docker

```bash
# Docker tự động áp AppArmor profile (nếu AppArmor available)
docker info | grep "Security Options"
# SecurityOptions: apparmor seccomp name_space

# Profile: docker-default
cat /etc/apparmor.d/docker-default
# Denies: /proc/sys/kernel/shmmax, /etc/passwd write, etc.

# Custom AppArmor profile
cat > /etc/apparmor.d/docker-nginx << 'EOF'
#include <tunables/global>
profile docker-nginx flags=(attach_disconnected, mediate_deleted) {
    #include <abstractions/base>
    network inet tcp,
    /var/www/html/** r,
    /etc/nginx/** r,
    /var/log/nginx/** rw,
    deny /etc/passwd r,
    deny /etc/shadow r,
}
EOF
apparmor_parser -r -W /etc/apparmor.d/docker-nginx

docker run --security-opt apparmor=docker-nginx nginx
```

---

## 6. Docker Storage Internals

### How – Volume vs Bind Mount vs tmpfs

```bash
# Named volume (managed by Docker, persisted)
docker volume create mydata
docker run -v mydata:/app/data myapp

# Volume location on host
docker volume inspect mydata | jq '.[0].Mountpoint'
# /var/lib/docker/volumes/mydata/_data

# Bind mount (host path → container path)
docker run -v /host/path:/container/path:ro myapp
docker run -v $(pwd)/config:/etc/myapp/config:ro,Z myapp
# Z = SELinux label

# tmpfs (RAM, ephemeral)
docker run --tmpfs /tmp:size=100m,noexec,nosuid myapp

# Inspect mounts
docker inspect mycontainer | jq '.[0].Mounts'

# Volume plugins (network storage)
docker plugin install vieux/sshfs
docker volume create --driver vieux/sshfs \
    -o sshcmd=user@host:/path \
    -o password=pass \
    sshvolume
```

### How – Container rootfs via overlay2

```bash
# Step by step: what happens when docker run

# 1. Pull image (if needed)
# Download layer tarballs, extract to /var/lib/docker/overlay2/

# 2. Create container
# New upperdir + workdir created
# config.json written (namespaces, capabilities, etc.)
CONTAINER_ID="abc123"
ls /var/lib/docker/overlay2/ | grep -A1 $CONTAINER_ID

# 3. Create mount
# overlayfs mounted at /var/lib/docker/overlay2/<id>/merged
cat /proc/mounts | grep $CONTAINER_ID

# 4. container/config.json
cat /var/lib/docker/containers/$CONTAINER_ID/config.v2.json | jq '{Cmd, Env, Image}'

# 5. During run: all writes go to upperdir
# After stop: upperdir persists
# After rm: upperdir deleted
docker container diff $CONTAINER_ID
```

---

## 7. Real-world Debugging

### How – Debug Running Container

```bash
# Enter container namespaces (don't install tools in container!)
CONTAINER_PID=$(docker inspect --format '{{.State.Pid}}' mycontainer)

# Network debug
nsenter -t $CONTAINER_PID --net ip addr show
nsenter -t $CONTAINER_PID --net ss -tlnp
nsenter -t $CONTAINER_PID --net curl http://localhost:8080

# Filesystem debug
nsenter -t $CONTAINER_PID --mount ls /app/
nsenter -t $CONTAINER_PID --mount cat /etc/myapp/config.conf

# Process debug
nsenter -t $CONTAINER_PID --pid ps aux
nsenter -t $CONTAINER_PID --all bash   # full shell inside (production DANGEROUS!)

# Copy tools into running container (temp debug)
docker cp /usr/bin/strace mycontainer:/usr/bin/
docker exec mycontainer strace -p $(pgrep myapp)

# Debug from image (ephemeral debug container)
docker run -it --rm \
    --pid=container:mycontainer \
    --network=container:mycontainer \
    --volumes-from=mycontainer \
    ubuntu:22.04 bash

# Use docker debug (Docker Desktop feature)
docker debug mycontainer

# Capture container network traffic
tcpdump -i any -w /tmp/capture.pcap &
nsenter -t $CONTAINER_PID --net tcpdump -i eth0 port 80
```

### How – Performance Analysis

```bash
# cAdvisor – container resource metrics
docker run -d \
    --volume=/var/run:/var/run:ro \
    --volume=/sys:/sys:ro \
    --volume=/var/lib/docker/:/var/lib/docker:ro \
    -p 8080:8080 \
    gcr.io/cadvisor/cadvisor

# docker stats
docker stats --no-stream mycontainer
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"

# Xem cgroup stats trực tiếp
CONTAINER_FULL_ID=$(docker inspect --format '{{.Id}}' mycontainer)
# v1:
cat /sys/fs/cgroup/memory/docker/$CONTAINER_FULL_ID/memory.usage_in_bytes
cat /sys/fs/cgroup/cpuacct/docker/$CONTAINER_FULL_ID/cpuacct.usage
# v2:
cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_FULL_ID}.scope/memory.current
cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_FULL_ID}.scope/cpu.stat
```

---

## 8. Compare & Trade-offs

### Compare – Container Runtimes

| | Docker (containerd+runc) | Podman | containerd | cri-o |
|--|--------------------------|--------|------------|-------|
| Daemon | Yes (dockerd) | No (daemonless) | Yes | Yes |
| Rootless | Yes | Yes (native) | Experimental | Yes |
| Kubernetes CRI | No (via dockershim – deprecated) | No | Yes | Yes |
| Compose support | docker-compose | podman-compose | No | No |
| Security | Good | Better (no daemon) | Good | Good |
| Khi dùng | Dev, CI/CD | Security-focused | K8s node | K8s node |

### Trade-offs

- **overlay2**: tốt nhất cho Docker nhưng không phải tất cả kernels support; devicemapper là alternative
- **bridge networking**: đơn giản nhưng cần NAT cho external; macvlan/ipvlan tốt hơn cho high-performance
- **seccomp/AppArmor**: security overhead nhỏ (~1-3%) nhưng rất đáng; privileged containers là antipattern
- **volume vs bind mount**: volume portable hơn (không phụ thuộc host path); bind mount dễ debug hơn
- **layered fs CoW**: tiết kiệm space, cache tốt nhưng nhiều layers = tăng overhead; squash layers trong production images

---

### Ghi chú – Chủ đề đã hoàn thành
> Tất cả 14 chủ đề Linux deep dive đã hoàn thành!
> Có thể tiếp tục với: Kubernetes internals, eBPF deep dive, hoặc Network performance tuning advanced
