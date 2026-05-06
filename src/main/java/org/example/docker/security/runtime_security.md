# Docker Runtime Security – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Linux Capabilities

### What – Capabilities là gì?
**Linux capabilities** chia quyền root thành các đơn vị nhỏ hơn. Thay vì "root hoặc không root", process chỉ có đúng capabilities cần thiết (**principle of least privilege**).

### How – Capabilities quan trọng

```
CAP_NET_BIND_SERVICE  → bind ports < 1024 (HTTP:80, HTTPS:443)
CAP_NET_ADMIN         → cấu hình network interfaces, iptables
CAP_NET_RAW           → tạo raw sockets (ping, tcpdump)
CAP_SYS_ADMIN         → mount filesystems, unshare namespaces (nguy hiểm nhất!)
CAP_SYS_PTRACE        → attach debugger đến process khác
CAP_DAC_OVERRIDE      → bypass file permission checks
CAP_SETUID/SETGID     → thay đổi UID/GID
CAP_CHOWN             → thay đổi file ownership
CAP_KILL              → gửi signals đến bất kỳ process nào
CAP_AUDIT_WRITE       → ghi vào kernel audit log
```

### How – Default Docker Capabilities

```bash
# Docker mặc định giữ các capabilities này:
# CAP_CHOWN, CAP_DAC_OVERRIDE, CAP_FSETID, CAP_FOWNER,
# CAP_MKNOD, CAP_NET_RAW, CAP_SETGID, CAP_SETUID,
# CAP_SETFCAP, CAP_SETPCAP, CAP_NET_BIND_SERVICE,
# CAP_SYS_CHROOT, CAP_KILL, CAP_AUDIT_WRITE

# Xem capabilities trong container
docker run --rm ubuntu capsh --print
docker run --rm ubuntu cat /proc/1/status | grep Cap
# CapPrm: 00000000a80425fb
# CapEff: 00000000a80425fb

# Decode capabilities
capsh --decode=00000000a80425fb

# Drop ALL, thêm chỉ cần thiết
docker run --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  nginx:alpine                       # Nginx chỉ cần bind port 80

# --privileged: trao tất cả capabilities (tránh hoàn toàn!)
docker run --privileged myapp        # nguy hiểm: như root thật sự trên host
```

### How – Compose Capabilities

```yaml
services:
  nginx:
    image: nginx:alpine
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE             # bind port 80/443
      - CHOWN                        # change file ownership
      - SETGID
      - SETUID

  tcpdump:
    image: nicolaka/netshoot
    cap_add:
      - NET_ADMIN
      - NET_RAW                      # cần cho tcpdump/ping

  # Absolute minimal
  app:
    image: myapp:latest
    cap_drop:
      - ALL                          # drop everything
    # Nếu app không cần bất kỳ capability nào → không cần cap_add
    security_opt:
      - no-new-privileges:true       # không thể dùng setuid/setgid để leo thang
```

---

## 2. Seccomp – Syscall Filtering

### What – Seccomp là gì?
**Seccomp (Secure Computing Mode)** filter system calls mà container được phép gọi. Docker mặc định áp dụng profile chặn ~44 syscalls nguy hiểm.

### How – Default Seccomp Profile

```bash
# Xem default profile
curl -s https://raw.githubusercontent.com/moby/moby/master/profiles/seccomp/default.json \
  | jq '.syscalls[0]'

# Default profile block một số syscalls nguy hiểm:
# keyctl, add_key, request_key  → kernel keyring
# clock_settime                 → thay đổi system clock
# create_module, init_module    → kernel modules
# kexec_load                    → load new kernel
# mount                         → mount filesystems (trừ khi có CAP_SYS_ADMIN)
# pivot_root, chroot            → change root
# unshare                       → tạo namespaces mới

# Xem container đang dùng seccomp gì
docker inspect myapp | jq '.[0].HostConfig.SecurityOpt'
```

### How – Custom Seccomp Profile

```json
// seccomp-strict.json: chỉ allow syscalls cần thiết cho Go web server
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": [
        "accept4", "bind", "brk", "clone", "close", "connect",
        "epoll_create1", "epoll_ctl", "epoll_wait", "execve",
        "exit", "exit_group", "fcntl", "fstat", "futex",
        "getdents64", "getpid", "getsockname", "getsockopt",
        "listen", "lseek", "madvise", "mmap", "mprotect",
        "munmap", "nanosleep", "open", "openat", "poll",
        "prctl", "pread64", "pwrite64", "read", "readv",
        "recvfrom", "recvmsg", "rt_sigaction", "rt_sigprocmask",
        "rt_sigreturn", "sendmsg", "sendto", "setsockopt",
        "sigaltstack", "socket", "stat", "write", "writev"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

```bash
# Apply custom seccomp profile
docker run --security-opt seccomp=./seccomp-strict.json myapp

# Tắt seccomp (debug)
docker run --security-opt seccomp=unconfined myapp

# Compose
services:
  app:
    security_opt:
      - seccomp:./seccomp-strict.json
```

### How – Tìm syscalls mà app cần

```bash
# Dùng strace để profile syscalls
strace -c -f myapp 2>&1 | head -30
# % time   seconds  usecs/call  calls  syscall
# -----   --------  ----------  -----  -------
#  45.12  0.001234    1234      1000   read
#  30.45  0.000832     832       500   write
#  ...

# Trong Docker: bật audit mode để collect syscalls
docker run --security-opt seccomp=unconfined \
  --cap-add SYS_PTRACE \
  myapp &

strace -p $(docker inspect --format '{{.State.Pid}}' myapp) \
  -e trace=all -c -- sleep 60
```

---

## 3. AppArmor & SELinux

### What – MAC (Mandatory Access Control) là gì?
**AppArmor** (Ubuntu/Debian) và **SELinux** (RHEL/Fedora) cung cấp **Mandatory Access Control** – policy trung tâm định nghĩa container được phép làm gì, bất kể DAC permissions.

### How – AppArmor

```bash
# Docker có default AppArmor profile: docker-default
docker run --security-opt apparmor=docker-default nginx

# Xem profile
cat /etc/apparmor.d/docker

# Custom AppArmor profile
# /etc/apparmor.d/docker-nginx:
profile docker-nginx flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>

  network inet tcp,
  network inet udp,
  network inet6 tcp,

  # Allow reads of nginx configs
  /etc/nginx/** r,
  /var/log/nginx/** w,
  /var/run/nginx.pid w,
  /usr/sbin/nginx mr,

  # Deny everything else
  deny @{PROC}/** rw,
  deny /sys/** rw,
}

# Load profile
apparmor_parser -r -W /etc/apparmor.d/docker-nginx

# Apply to container
docker run --security-opt apparmor=docker-nginx nginx

# Unconfined (disable AppArmor)
docker run --security-opt apparmor=unconfined myapp
```

### How – SELinux

```bash
# SELinux modes
getenforce                           # Enforcing / Permissive / Disabled
setenforce 1                         # Enforcing (tạm thời)
# /etc/selinux/config → SELINUX=enforcing (permanent)

# Container label (type enforcement)
docker run --security-opt label=type:container_t myapp
docker run --security-opt label=disable myapp       # disable SELinux cho container

# Compose
services:
  app:
    security_opt:
      - label:type:container_t

# Mount volume với SELinux labels
docker run -v /host/data:/container/data:Z myapp   # :Z = relabel for container use
docker run -v /host/data:/container/data:z myapp   # :z = shared between containers
```

---

## 4. Rootless Docker

### What – Rootless Docker là gì?
**Rootless Docker** chạy cả Docker daemon và containers với quyền của non-root user. Container escape không thể leo thang thành root trên host.

### How – Setup Rootless Docker

```bash
# Prerequisites
apt-get install -y uidmap            # Ubuntu

# Cài rootless Docker
dockerd-rootless-setuptool.sh install

# Hoặc standalone
curl -fsSL https://get.docker.com/rootless | sh

# Cấu hình sau install
export PATH=/usr/bin:$PATH
export DOCKER_HOST=unix:///run/user/1000/docker.sock

# Start rootless daemon
systemctl --user start docker
systemctl --user enable docker

# Kiểm tra
docker info | grep "rootless"
# WARNING: Running in rootless mode.

# Run container (rootless)
docker run --rm -it ubuntu
id                                   # uid=0 trong container
# Trên host: uid=100000 (mapped user)

# Cấu hình trong ~/.config/docker/daemon.json (thay vì /etc/docker/)
{
  "iptables": false,                 # rootless không manage iptables
  "storage-driver": "fuse-overlayfs"
}
```

### How – Limitations của Rootless

```bash
# 1. Ports < 1024 không bind được
docker run -p 80:80 nginx            # lỗi: permission denied
# Giải pháp:
sysctl net.ipv4.ip_unprivileged_port_start=80   # cho phép từ port 80
# Hoặc dùng port >= 1024 + reverse proxy

# 2. Overlay filesystem cần kernel >= 5.13 hoặc fuse-overlayfs
apt-get install fuse-overlayfs

# 3. Networking hạn chế
# - Không dùng được iptables
# - Dùng slirp4netns (user-mode networking, chậm hơn)

# 4. Cgroups
# - cgroups v1: không limit được memory/CPU
# - cgroups v2: full support
```

---

## 5. gVisor – Sandboxed Containers

### What – gVisor là gì?
**gVisor** (Google) là **user-space kernel** implement phần lớn Linux kernel syscalls trong Go. Container chạy trong gVisor sandbox, không trực tiếp gọi host kernel → kernel exploit không thể escape.

### How – gVisor Architecture

```
Without gVisor:
Container process → Linux syscall → Host kernel (direct!)

With gVisor (runsc):
Container process → Linux syscall → gVisor (Sentry, user-space kernel)
                                        ↓ (limited syscalls)
                                    Host kernel
```

### How – Cài & Dùng gVisor

```bash
# Cài gVisor runtime (runsc)
curl -fsSL https://gvisor.dev/archive.key | gpg --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | tee /etc/apt/sources.list.d/gvisor.list
apt-get update && apt-get install -y runsc

# Đăng ký runtime với Docker
runsc install
# → thêm vào /etc/docker/daemon.json:
# {
#   "runtimes": {
#     "runsc": {
#       "path": "/usr/bin/runsc"
#     }
#   }
# }
systemctl restart docker

# Chạy container với gVisor
docker run --runtime=runsc myapp

# Compose
services:
  sensitive-service:
    image: myapp
    runtime: runsc                   # sandbox với gVisor
```

### How – Kata Containers (VM-based)

```bash
# Kata Containers: chạy mỗi container trong lightweight VM (QEMU/Firecracker)
# Cách ly tốt nhất (hardware virtualization), nhưng overhead cao hơn

# Cài Kata
kata-deploy install

# Dùng với Docker
docker run --runtime=kata-runtime myapp

# Nhanh hơn Kata: Firecracker (AWS Lambda dùng)
```

### Compare – Container Runtimes (Security)

| | runc (default) | gVisor | Kata | Firecracker |
|--|--------------|--------|------|------------|
| Isolation | Namespace/cgroup | User-space kernel | VM | MicroVM |
| Kernel attack surface | Full | Minimal | Hardware isolation | Minimal |
| Startup time | ~100ms | ~200ms | ~500ms | ~125ms |
| Performance | Baseline | ~5-15% overhead | ~10-20% overhead | Near-native |
| Memory overhead | Minimal | ~15MB/container | ~50MB+/container | ~5MB |
| K8s support | RuntimeClass | RuntimeClass | RuntimeClass | - |

### Trade-offs
- Capabilities: tốt nhưng mặc định Docker vẫn còn nhiều cap không cần; cần profile từng app
- Seccomp: very effective nhưng khó tạo minimal profile; sai 1 syscall = container crash
- gVisor: excellent security nhưng compatibility issues (một số syscalls chưa implement)
- Rootless: best practice nhưng tính năng bị giới hạn, performance networking kém hơn

### Real-world Usage
```bash
# Audit security config của containers đang chạy
docker inspect $(docker ps -q) | jq '.[] | {
  name: .Name,
  privileged: .HostConfig.Privileged,
  capAdd: .HostConfig.CapAdd,
  capDrop: .HostConfig.CapDrop,
  seccomp: (.HostConfig.SecurityOpt // [] | map(select(startswith("seccomp"))) | .[0]),
  apparmor: (.HostConfig.SecurityOpt // [] | map(select(startswith("apparmor"))) | .[0]),
  user: .Config.User,
  noNewPrivileges: (.HostConfig.SecurityOpt // [] | contains(["no-new-privileges:true"]))
}'

# CIS Docker Benchmark (automated audit)
docker run --rm --net host --pid host \
  --cap-add audit_control \
  -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -v /etc:/etc:ro \
  docker/docker-bench-security 2>&1 | grep -E "WARN|FAIL"
```

### Ghi chú – Chủ đề tiếp theo
> Secrets Management – HashiCorp Vault, AWS Secrets Manager, external-secrets-operator

---

*Cập nhật lần cuối: 2026-05-06*
