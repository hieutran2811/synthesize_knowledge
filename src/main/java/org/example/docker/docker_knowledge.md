# Tổng Hợp Kiến Thức Docker – Cơ Bản đến Nâng Cao

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Docker Overview

### What – Docker là gì?
**Docker** là nền tảng **container hóa (containerization)** mã nguồn mở, cho phép đóng gói ứng dụng cùng toàn bộ dependencies vào một **container** – đơn vị chạy nhất quán trên mọi môi trường.

### How – Đặc điểm
- **Portable**: "Build once, run anywhere" – container chạy giống nhau trên dev, staging, prod
- **Lightweight**: Dùng chung OS kernel với host, không cần full OS như VM
- **Isolated**: Process, network, filesystem riêng biệt qua Linux namespaces & cgroups
- **Immutable**: Image không thay đổi; mỗi lần chạy là container mới từ image đó
- **Fast startup**: Milliseconds so với VM (seconds – minutes)
- **Layered filesystem**: Image gồm các layers, chia sẻ lại giữa images → tiết kiệm disk

### How – Hoạt động (Architecture)

```
┌─────────────────────────────────────────────────┐
│                   Docker Host                    │
│                                                  │
│  ┌──────────┐     ┌─────────────────────────┐   │
│  │  Docker  │────▶│      Docker Daemon       │   │
│  │  Client  │     │  (dockerd / REST API)    │   │
│  │ (docker) │     └──────────┬──────────────┘   │
│  └──────────┘                │                   │
│                     ┌────────┴────────┐           │
│                     │                 │           │
│             ┌───────▼───┐   ┌────────▼───────┐   │
│             │ Containers │   │  Images Cache  │   │
│             └───────────┘   └────────────────┘   │
└─────────────────────────────────────────────────┘
                              │ push/pull
                    ┌─────────▼──────────┐
                    │   Container Registry│
                    │   (Docker Hub,      │
                    │    ECR, GCR, Harbor)│
                    └────────────────────┘
```

**Flow cơ bản:**
```
Dockerfile
    ↓ docker build
Image (layers)
    ↓ docker run
Container (running instance)
    ↓ docker commit (hiếm dùng)
New Image
```

### Why – Tại sao dùng Docker?
- **"Works on my machine"**: Loại bỏ sự khác biệt môi trường
- **Fast deployment**: CI/CD pipeline build image → deploy container trong giây
- **Microservices**: Mỗi service 1 container, scale độc lập
- **Resource efficiency**: 10x+ containers trên cùng server so với VMs
- **Developer experience**: `docker compose up` → toàn bộ stack chạy ngay

### Components – Thành phần chính

| Thành phần | Vai trò |
|-----------|---------|
| **Docker Client** | CLI (`docker`) giao tiếp với daemon qua REST API |
| **Docker Daemon** (`dockerd`) | Background service quản lý containers, images, networks, volumes |
| **containerd** | Container runtime (OCI-compliant), quản lý container lifecycle |
| **runc** | Low-level runtime tạo container (dùng Linux namespaces/cgroups) |
| **Image** | Read-only template gồm nhiều layers |
| **Container** | Running instance của image (image + writable layer) |
| **Registry** | Kho lưu trữ images (Docker Hub, ECR, GCR, Harbor) |
| **Volume** | Persistent storage ngoài container filesystem |
| **Network** | Virtual network kết nối containers |

### Compare – Docker vs Virtual Machine

| | Container (Docker) | Virtual Machine |
|--|-------------------|----------------|
| **OS** | Dùng chung host kernel | Kernel riêng (full OS) |
| **Size** | MB | GB |
| **Startup** | Milliseconds | Seconds – minutes |
| **Isolation** | Process-level (namespace) | Hardware-level (hypervisor) |
| **Performance** | Near-native | 5-20% overhead |
| **Security** | Kém hơn (shared kernel) | Tốt hơn |
| **Use case** | Microservices, CI/CD | Legacy apps, strong isolation |

### Compare – Docker vs containerd vs podman

| | Docker | containerd | Podman |
|--|--------|-----------|--------|
| Daemon | dockerd (daemon) | containerd | Daemonless |
| Root | Cần root (hoặc group) | Cần root | Rootless native |
| Compose | Docker Compose | Nope | podman-compose |
| K8s runtime | Không (deprecated) | Có (default) | Có |

### Trade-offs
- (+) Developer experience tốt, ecosystem lớn, Docker Compose tiện
- (-) Daemon chạy root → security risk; shared kernel → container escape nếu misconfigured
- (-) Không phù hợp cho GUI apps, kernel modules, nghiên cứu cần kernel riêng

### Real-world Usage
- **Dev environment**: `docker compose up` thay cho cài local DB, Redis, Kafka
- **CI/CD**: GitHub Actions / Jenkins build Docker image → push ECR → deploy ECS/K8s
- **Microservices**: Mỗi service 1 image, deploy độc lập, scale theo nhu cầu
- **Batch jobs**: `docker run` → chạy xong → container tự cleanup

### Ghi chú – Chủ đề tiếp theo
> Docker Images – Dockerfile, layers, build cache, tagging, multi-stage builds

---

## 2. Docker Images

### What – Image là gì?
**Docker Image** là template **read-only** gồm nhiều **layers** xếp chồng nhau, định nghĩa filesystem và metadata cần thiết để chạy container. Image được build từ **Dockerfile**.

### How – Image Layers

```
┌─────────────────────────────┐
│  Writable Layer (Container) │ ← chỉ tồn tại khi container chạy
├─────────────────────────────┤
│  COPY . /app                │ Layer 4 (read-only)
├─────────────────────────────┤
│  RUN npm install            │ Layer 3
├─────────────────────────────┤
│  WORKDIR /app               │ Layer 2
├─────────────────────────────┤
│  FROM node:18-alpine        │ Layer 1 (base image)
└─────────────────────────────┘
```

- Mỗi instruction trong Dockerfile tạo 1 layer mới
- Layers **shared** giữa images → tiết kiệm disk & network
- Union filesystem (OverlayFS) merge các layers thành 1 view duy nhất

### How – Dockerfile

```dockerfile
# ─── Cơ bản ───────────────────────────────────────────────────
FROM ubuntu:22.04                    # base image

# Metadata
LABEL maintainer="team@example.com"
LABEL version="1.0"

# Biến môi trường
ENV APP_HOME=/app \
    PORT=8080 \
    NODE_ENV=production

# Working directory (tạo nếu chưa có)
WORKDIR $APP_HOME

# Copy files
COPY package*.json ./                # copy cụ thể trước (cache-friendly)
COPY . .                             # copy toàn bộ source

# Chạy lệnh khi BUILD (tạo layer mới)
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*   # cleanup trong cùng RUN để giảm layer size

# Expose port (chỉ là documentation, không thực sự bind)
EXPOSE 8080

# Volume mount point
VOLUME ["/data"]

# Lệnh chạy khi CONTAINER START
CMD ["node", "server.js"]

# ENTRYPOINT + CMD pattern
ENTRYPOINT ["node"]
CMD ["server.js"]
# docker run myapp server.js   → node server.js  (default)
# docker run myapp other.js    → node other.js   (override CMD)
```

### How – CMD vs ENTRYPOINT

```dockerfile
# CMD only: hoàn toàn override được khi docker run
CMD ["nginx", "-g", "daemon off;"]
# docker run myimage bash → chạy bash, không chạy nginx

# ENTRYPOINT only: không override được (chỉ thêm args)
ENTRYPOINT ["nginx"]
# docker run myimage -g "daemon off;" → nginx -g "daemon off;"

# ENTRYPOINT + CMD: best practice cho executable images
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
# docker run myimage                         → nginx -g "daemon off;"
# docker run myimage -c /etc/nginx/nginx.conf → nginx -c /etc/nginx/nginx.conf
# docker run --entrypoint bash myimage       → bash (override entrypoint)
```

### How – Build Commands

```bash
# Build image
docker build -t myapp:1.0 .               # tag = name:version
docker build -t myapp:latest -f Dockerfile.prod .  # custom Dockerfile
docker build --no-cache -t myapp:1.0 .    # bỏ qua cache
docker build --build-arg ENV=prod .       # truyền ARG

# List images
docker images                              # tất cả images
docker images myapp                        # filter theo name
docker image ls -a                         # kể cả intermediate images

# Inspect
docker inspect myapp:1.0                   # full metadata
docker history myapp:1.0                   # xem các layers
docker image inspect --format '{{.Size}}' myapp:1.0  # image size

# Tag & Push
docker tag myapp:1.0 registry.example.com/team/myapp:1.0
docker push registry.example.com/team/myapp:1.0

# Pull
docker pull nginx:alpine
docker pull --platform linux/amd64 nginx   # specify platform

# Remove
docker rmi myapp:1.0                       # xóa image
docker image prune                         # xóa dangling images (<none>)
docker image prune -a                      # xóa tất cả unused images
```

### How – Multi-stage Build

```dockerfile
# Stage 1: Builder
FROM maven:3.9-eclipse-temurin-21 AS builder
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline -B          # cache dependencies layer
COPY src ./src
RUN mvn package -DskipTests -B

# Stage 2: Runtime (chỉ giữ artifact cần thiết)
FROM eclipse-temurin:21-jre-alpine AS runtime
WORKDIR /app

# Tạo non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

COPY --from=builder /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

```bash
# Build chỉ đến stage cụ thể (debug)
docker build --target builder -t myapp-builder .

# Multi-stage kết quả: image chỉ chứa JRE + jar (không có Maven, source)
# Java app: builder ~600MB → runtime ~200MB
# Node.js:  builder ~1GB   → runtime ~100MB (nginx serve static)
```

### How – .dockerignore

```
# .dockerignore
node_modules/
.git/
.env
*.log
target/
build/
dist/
**/*.test.js
**/__tests__/
.DS_Store
README.md
```
> Tương tự `.gitignore` – tránh copy files không cần vào build context, giảm build time và image size.

### How – Build Cache

```dockerfile
# Sắp xếp instructions từ ÍT THAY ĐỔI → THAY ĐỔI NHIỀU để tận dụng cache

# BAD: copy source trước → npm install không cache được
COPY . .
RUN npm install

# GOOD: copy package.json trước → npm install được cache
COPY package*.json ./
RUN npm install          # cache layer này nếu package.json không đổi
COPY . .                 # thay đổi source không invalidate npm install
```

### Compare – ADD vs COPY

| | COPY | ADD |
|--|------|-----|
| Chức năng | Copy local files | COPY + extract tar + URL support |
| Khuyến nghị | **Luôn dùng COPY** | Chỉ dùng khi cần extract tar |
| Ví dụ | `COPY src/ /app/src/` | `ADD app.tar.gz /app/` |

### Trade-offs
- Multi-stage: image nhỏ hơn nhiều nhưng build time lâu hơn
- Nhiều RUN commands: nhiều layers nhỏ (dễ cache) vs ít RUN (ít layers)
- Base image: `ubuntu` (lớn, quen thuộc) vs `alpine` (5MB, nhưng dùng musl libc có thể gây compat issues)

### Real-world Usage
```bash
# Kiểm tra image size trước deploy
docker images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}" | sort -k2 -h

# Dive tool – phân tích image layers
dive myapp:1.0

# Scan vulnerabilities
docker scout cves myapp:1.0
# hoặc
trivy image myapp:1.0
```

### Ghi chú – Chủ đề tiếp theo
> Container lifecycle, docker run options, exec, logs, resource limits

---

## 3. Docker Containers

### What – Container là gì?
**Container** là **running instance** của một image. Container = image layers (read-only) + **writable layer** trên đỉnh. Khi container bị xóa, writable layer mất theo.

### How – Container Lifecycle

```
Created ──► Running ──► Paused
                │            │
                ▼            ▼
             Stopped ◄── Unpaused
                │
                ▼
             Removed (docker rm)
```

### How – docker run (Cơ bản → Nâng cao)

```bash
# Cơ bản
docker run nginx                           # run foreground, Ctrl+C để stop
docker run -d nginx                        # detached (background)
docker run -d --name web nginx             # đặt tên container
docker run --rm nginx                      # tự xóa khi stop

# Port mapping
docker run -d -p 8080:80 nginx            # host:container
docker run -d -p 127.0.0.1:8080:80 nginx # bind specific interface
docker run -d -P nginx                     # auto-assign random host ports

# Environment variables
docker run -d -e DB_HOST=postgres -e DB_PORT=5432 myapp
docker run -d --env-file .env myapp       # từ file

# Volumes
docker run -d -v mydata:/var/lib/mysql mysql     # named volume
docker run -d -v /host/path:/container/path nginx # bind mount
docker run -d -v $(pwd)/config:/etc/nginx/conf.d:ro nginx  # read-only

# Network
docker run -d --network mynetwork myapp           # custom network
docker run -d --network host nginx                # host network

# Resource limits
docker run -d --memory="512m" --cpus="1.5" myapp  # limit RAM và CPU
docker run -d --memory="512m" --memory-swap="512m" myapp  # swap = memory (no swap)

# Interactive
docker run -it ubuntu bash                 # interactive terminal
docker run -it --rm python:3.11 python    # interactive Python shell
```

### How – Quản lý Container

```bash
# List
docker ps                                  # đang chạy
docker ps -a                               # tất cả (kể cả stopped)
docker ps -q                               # chỉ IDs
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Ports}}"

# Start / Stop / Restart
docker start web                           # start stopped container
docker stop web                            # graceful stop (SIGTERM → SIGKILL sau 10s)
docker stop -t 30 web                      # wait 30s trước khi SIGKILL
docker restart web

# Pause / Unpause (freeze process, không kill)
docker pause web
docker unpause web

# Execute command trong container đang chạy
docker exec web ls /etc/nginx
docker exec -it web bash                   # interactive shell
docker exec -it web sh                     # nếu không có bash
docker exec -u root web apt install curl   # chạy với user cụ thể

# Logs
docker logs web                            # tất cả logs
docker logs -f web                         # follow
docker logs --tail 100 web                # 100 dòng gần nhất
docker logs --since 1h web               # 1 giờ gần nhất
docker logs --timestamps web              # kèm timestamp

# Copy files
docker cp web:/etc/nginx/nginx.conf ./    # container → host
docker cp ./nginx.conf web:/etc/nginx/    # host → container

# Inspect
docker inspect web                         # full JSON metadata
docker inspect -f '{{.NetworkSettings.IPAddress}}' web  # IP của container
docker inspect -f '{{.State.Status}}' web  # trạng thái

# Stats
docker stats                               # real-time resource usage
docker stats --no-stream                   # snapshot
docker stats web db cache                  # nhiều containers

# Remove
docker rm web                              # xóa stopped container
docker rm -f web                           # force (kể cả đang chạy)
docker container prune                     # xóa tất cả stopped containers
```

### How – Container Internals

```
Container = Linux Namespaces + cgroups + OverlayFS

Namespaces (isolation):
├── PID namespace   → process tree riêng (PID 1 = process chính)
├── NET namespace   → network interface riêng (eth0, lo)
├── MNT namespace   → filesystem view riêng
├── UTS namespace   → hostname riêng
├── IPC namespace   → IPC resources riêng
└── USER namespace  → UID/GID mapping

cgroups (resource limits):
├── cpu     → CPU quota/period
├── memory  → memory limit + OOM killer
├── blkio   → disk I/O throttle
└── pids    → max processes

OverlayFS (layered filesystem):
├── lowerdir  → image layers (read-only)
├── upperdir  → container writable layer
├── workdir   → OverlayFS internal
└── merged    → view thống nhất mà container thấy
```

### How – Health Check

```dockerfile
# Trong Dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# CMD wget --quiet --tries=1 --spider http://localhost:8080/health || exit 1
```

```bash
# Khi docker run
docker run -d \
  --health-cmd="curl -f http://localhost/health || exit 1" \
  --health-interval=30s \
  --health-timeout=5s \
  --health-retries=3 \
  myapp

# Xem health status
docker ps  # STATUS: healthy / unhealthy / starting
docker inspect --format='{{.State.Health.Status}}' web
docker inspect --format='{{json .State.Health}}' web | jq
```

### How – Restart Policies

```bash
docker run -d --restart=always nginx       # luôn restart (kể cả reboot)
docker run -d --restart=unless-stopped nginx  # restart trừ khi stop thủ công
docker run -d --restart=on-failure:5 myapp    # restart tối đa 5 lần khi fail
docker run -d --restart=no myapp           # không restart (default)
```

### Compare – ENTRYPOINT với PID 1

```dockerfile
# BAD: shell form – ENTRYPOINT chạy trong shell, PID 1 = sh
ENTRYPOINT java -jar app.jar
# → SIGTERM gửi đến sh, không đến java → graceful shutdown không hoạt động

# GOOD: exec form – process trực tiếp là PID 1
ENTRYPOINT ["java", "-jar", "app.jar"]
# → SIGTERM gửi đến java → graceful shutdown hoạt động
```

### Trade-offs
- Container ephemeral: dữ liệu mất khi xóa → cần volumes cho stateful apps
- Writable layer dùng OverlayFS: I/O chậm hơn volume mount → DB nên dùng volume
- Nhiều containers = nhiều processes nhưng ít overhead hơn VMs

### Real-world Usage
```bash
# Debug container đang chạy
docker exec -it myapp sh -c "ps aux && netstat -tlnp"

# Xem container bị OOM killed không
docker inspect myapp | grep -i oom
dmesg | grep -i "out of memory"

# Export container thành tar (di chuyển sang host khác)
docker export myapp | gzip > myapp-backup.tar.gz
cat myapp-backup.tar.gz | docker import - myapp:backup

# Cleanup toàn bộ (dev machine)
docker system prune -a --volumes    # xóa tất cả: containers, images, volumes, networks
docker system df                    # xem disk usage
```

### Ghi chú – Chủ đề tiếp theo
> Volumes & Bind Mounts – persistent storage, tmpfs, volume drivers

---

## 4. Volumes & Storage

### What – Volume là gì?
**Docker Volume** là cơ chế lưu trữ data **ngoài container filesystem**, giúp data persist khi container bị xóa và chia sẻ data giữa containers.

### How – Ba loại storage

```
┌─────────────────────────────────────────────────────────────┐
│                        Docker Host                           │
│                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐   │
│  │   Volume    │    │ Bind Mount   │    │    tmpfs      │   │
│  │ /var/lib/   │    │ /host/path   │    │  (RAM only)   │   │
│  │ docker/     │    │     ↕        │    │               │   │
│  │ volumes/    │    │ /container/  │    │ /container/   │   │
│  │     ↕       │    │ path         │    │ path          │   │
│  │ /container/ │    │              │    │               │   │
│  │ data        │    │              │    │               │   │
│  └─────────────┘    └──────────────┘    └───────────────┘   │
│  Docker managed     Host managed        Memory only          │
└─────────────────────────────────────────────────────────────┘
```

### How – Named Volumes

```bash
# Tạo volume
docker volume create mydata
docker volume create --driver local --opt type=nfs \
  --opt o=addr=192.168.1.100,rw \
  --opt device=:/exports/data nfs-data     # NFS volume

# List / Inspect / Remove
docker volume ls
docker volume inspect mydata
docker volume rm mydata
docker volume prune                         # xóa orphan volumes

# Mount vào container
docker run -d -v mydata:/var/lib/mysql mysql
docker run -d --mount type=volume,src=mydata,dst=/var/lib/mysql mysql  # verbose form

# Backup volume
docker run --rm \
  -v mydata:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/mydata-backup.tar.gz /data

# Restore volume
docker run --rm \
  -v mydata:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/mydata-backup.tar.gz -C /
```

### How – Bind Mounts

```bash
# Mount thư mục host → container
docker run -d -v /host/data:/container/data nginx
docker run -d -v $(pwd):/app node          # dev: mount source code
docker run -d -v /etc/nginx/nginx.conf:/etc/nginx/nginx.conf:ro nginx  # read-only

# --mount form (verbose, không tạo volume nếu src không tồn tại)
docker run -d --mount type=bind,src=/host/path,dst=/container/path,readonly nginx
```

### How – tmpfs (In-memory)

```bash
# Lưu sensitive data trong RAM, không persist
docker run -d --tmpfs /run:rw,noexec,nosuid,size=100m myapp
docker run -d --mount type=tmpfs,dst=/tmp,tmpfs-size=100m myapp

# Use case: sensitive temp files, session data không cần persist
```

### Compare – Volume vs Bind Mount vs tmpfs

| | Named Volume | Bind Mount | tmpfs |
|--|-------------|-----------|-------|
| Managed by | Docker | Host OS | Docker (RAM) |
| Portability | Cao (Docker managed path) | Thấp (host path cứng) | N/A |
| Performance | Tốt | Tốt (native) | Rất tốt |
| Dev workflow | Ít dùng | Thường dùng (hot reload) | Ít dùng |
| Production | **Khuyến nghị** | OK với cẩn thận | Sensitive data |
| Backup | Docker API | OS tools | Không persist |

### How – Volume trong Docker Compose

```yaml
services:
  db:
    image: postgres:16
    volumes:
      - pgdata:/var/lib/postgresql/data      # named volume
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql  # bind mount (read-only)
      - /etc/localtime:/etc/localtime:ro     # timezone sync

  app:
    image: myapp:latest
    volumes:
      - ./config:/app/config:ro              # bind mount, read-only
      - appdata:/app/data                    # named volume

volumes:
  pgdata:                    # Docker managed
  appdata:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nas.example.com,rw
      device: ":/exports/appdata"
```

### Trade-offs
- Bind mount trong dev: live reload tiện nhưng path coupling với host
- Named volume: portable nhưng không thể mount 1 file (chỉ directory)
- Volume driver: NFS/EFS cho distributed storage nhưng có latency
- tmpfs: nhanh nhưng mất khi container restart

### Real-world Usage
```bash
# PostgreSQL với backup tự động
docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  -v /backup:/backup \
  postgres:16

# Backup hàng ngày
docker exec postgres pg_dump -U postgres mydb | \
  gzip > /backup/mydb_$(date +%Y%m%d).sql.gz
```

### Ghi chú – Chủ đề tiếp theo
> Docker Networking – bridge, host, overlay, DNS, port mapping

---

## 5. Docker Networking

### What – Docker Networking là gì?
Docker tạo **virtual networks** để containers giao tiếp với nhau và với thế giới bên ngoài. Mỗi network là một Linux bridge hoặc overlay network.

### How – Network Drivers

```
Docker Network Drivers:
├── bridge   (default) – virtual switch trên host, containers trong cùng network nói chuyện nhau
├── host     – container dùng trực tiếp network của host (không isolation)
├── overlay  – multi-host networking (Docker Swarm, VXLAN)
├── macvlan  – container có MAC address riêng, appears như physical device
├── ipvlan   – tương tự macvlan nhưng L3
└── none     – không network
```

### How – Default Bridge Network

```bash
# Mặc định khi docker run không chỉ định --network
docker run -d nginx    # vào bridge network "bridge" (172.17.0.0/16)

# VẤN ĐỀ: default bridge không có DNS! Containers liên lạc qua IP tĩnh
docker inspect bridge  # xem subnet, gateway

# GIẢI PHÁP: tạo user-defined bridge network → có DNS tự động
docker network create mynet
docker run -d --name web --network mynet nginx
docker run -d --name app --network mynet myapp
# Bây giờ app container có thể gọi: http://web:80 (dùng tên container làm hostname)
```

### How – Network Commands

```bash
# List / Inspect / Remove
docker network ls
docker network inspect mynet
docker network rm mynet
docker network prune                         # xóa unused networks

# Tạo network tùy chỉnh
docker network create mynet                  # bridge mặc định
docker network create --driver bridge \
  --subnet 172.20.0.0/16 \
  --gateway 172.20.0.1 \
  --ip-range 172.20.240.0/20 \
  mynet

docker network create --driver overlay \
  --attachable \
  --subnet 10.0.0.0/24 \
  swarm-net                                  # Swarm overlay network

# Connect / Disconnect container vào network
docker network connect mynet web             # thêm container vào network
docker network disconnect mynet web          # bỏ container khỏi network
docker run -d --network mynet nginx          # khi chạy

# Container có thể thuộc nhiều networks
docker network connect frontend-net app
docker network connect backend-net app       # app nói chuyện được cả 2 sides
```

### How – Port Mapping

```bash
# -p host_port:container_port
docker run -d -p 8080:80 nginx              # TCP mặc định
docker run -d -p 8080:80/tcp nginx          # TCP explicit
docker run -d -p 5000:5000/udp myapp        # UDP

# Bind specific interface
docker run -d -p 127.0.0.1:8080:80 nginx   # chỉ localhost (không expose ra ngoài)
docker run -d -p 0.0.0.0:8080:80 nginx     # tất cả interfaces (mặc định)

# -P: publish all exposed ports (random host ports)
docker run -d -P nginx                      # 0.0.0.0:32768->80/tcp

# Xem port mapping
docker port web
docker ps --format "{{.Ports}}"
```

### How – DNS & Service Discovery

```
User-defined Bridge Network:
├── Embedded DNS server (127.0.0.11)
├── Container name → IP resolution tự động
├── Network alias: --network-alias
└── Docker Compose: service name = DNS name

Example:
  app container → DB_HOST=postgres → resolves to postgres container IP
```

```bash
# Network alias
docker run -d --name db1 --network mynet --network-alias database postgres
docker run -d --name db2 --network mynet --network-alias database postgres
# app có thể gọi "database" – Docker DNS sẽ load-balance (round-robin) giữa db1, db2

# Kiểm tra DNS trong container
docker exec app nslookup postgres
docker exec app ping postgres
docker exec app curl http://web:80
```

### How – host & none network

```bash
# host network: không có network isolation
docker run -d --network host nginx
# → nginx bind port 80 trực tiếp trên host interface
# → không cần -p, nhưng không portable (port conflict với host)

# none network: hoàn toàn isolated
docker run -d --network none myapp
# → container không có network, dùng cho security-sensitive processing
```

### How – Networking trong Docker Compose

```yaml
version: "3.9"
services:
  app:
    image: myapp
    networks:
      - frontend
      - backend

  nginx:
    image: nginx
    ports:
      - "80:80"
    networks:
      - frontend

  db:
    image: postgres
    networks:
      - backend             # db không accessible từ nginx

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true          # không có internet access
```

### Compare – bridge vs host vs overlay

| | bridge | host | overlay |
|--|--------|------|---------|
| Isolation | Có (NAT) | Không | Có (VXLAN) |
| Performance | Nhẹ overhead | Native | Có overhead |
| Multi-host | Không | Không | Có |
| Port mapping | Cần | Không cần | Không cần |
| Khi dùng | Dev, single-host prod | Performance-critical | Swarm / multi-host |

### Trade-offs
- Default bridge: đơn giản nhưng không có DNS → tránh dùng
- Host network: performance tốt nhất nhưng mất isolation, port conflicts
- Overlay: cần Swarm hoặc plugin; overhead VXLAN encapsulation

### Real-world Usage
```bash
# Inspect container networking
docker inspect web | jq '.[0].NetworkSettings.Networks'

# Xem iptables rules Docker tạo
iptables -L DOCKER
iptables -t nat -L DOCKER

# Troubleshoot: test connectivity giữa containers
docker exec app curl -v http://db:5432   # test TCP
docker exec app nc -zv db 5432           # netcat test port
```

### Ghi chú – Chủ đề tiếp theo
> Docker Compose – multi-container apps, YAML syntax, depends_on, profiles, overrides

---

## 6. Docker Compose

### What – Docker Compose là gì?
**Docker Compose** là tool định nghĩa và chạy **multi-container applications** qua file YAML (`docker-compose.yml` / `compose.yaml`). Thay vì nhiều lệnh `docker run`, chỉ cần `docker compose up`.

### How – Cú pháp Compose File

```yaml
# compose.yaml (v3.9+)
name: myproject                      # project name (default: folder name)

services:
  # ─── App Service ──────────────────────────────────────────
  app:
    build:
      context: .                     # build từ Dockerfile
      dockerfile: Dockerfile.prod
      args:
        BUILD_ENV: production
    image: myapp:latest              # tag image sau khi build
    container_name: myapp            # tên cố định (tránh dùng với scale)
    restart: unless-stopped

    ports:
      - "8080:8080"
      - "127.0.0.1:9090:9090"       # metrics chỉ expose localhost

    environment:
      - APP_ENV=production
      - DB_HOST=db                   # service name = DNS name
      - DB_PORT=5432

    env_file:
      - .env
      - .env.prod                    # override

    volumes:
      - ./config:/app/config:ro
      - app-logs:/app/logs

    depends_on:
      db:
        condition: service_healthy   # chờ DB healthy trước khi start
      redis:
        condition: service_started   # chờ started (không cần healthy)

    networks:
      - frontend
      - backend

    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
        reservations:
          memory: 512M

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ─── Database ─────────────────────────────────────────────
  db:
    image: postgres:16-alpine
    restart: always
    environment:
      POSTGRES_DB: mydb
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    volumes:
      - pgdata:/var/lib/postgresql/data
      - ./init-scripts:/docker-entrypoint-initdb.d:ro
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d mydb"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    secrets:
      - db_password

  # ─── Redis ────────────────────────────────────────────────
  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru
    volumes:
      - redis-data:/data
    networks:
      - backend

  # ─── Nginx Reverse Proxy ──────────────────────────────────
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/ssl:/etc/nginx/ssl:ro
      - static-files:/var/www/static:ro
    depends_on:
      - app
    networks:
      - frontend

volumes:
  pgdata:
  redis-data:
  app-logs:
  static-files:

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true

secrets:
  db_password:
    file: ./secrets/db_password.txt
```

### How – Compose Commands

```bash
# Start / Stop
docker compose up                    # start (foreground)
docker compose up -d                 # start (detached)
docker compose up --build            # rebuild images trước khi start
docker compose up app                # chỉ start 1 service

docker compose down                  # stop + remove containers, networks
docker compose down -v               # + remove volumes
docker compose down --rmi all        # + remove images

docker compose start                 # start stopped services
docker compose stop                  # stop (không remove)
docker compose restart app           # restart 1 service

# Build
docker compose build                 # build tất cả
docker compose build --no-cache app  # rebuild service app

# Logs
docker compose logs                  # tất cả services
docker compose logs -f app           # follow logs của app
docker compose logs --tail 50 db     # 50 dòng gần nhất

# Status
docker compose ps                    # trạng thái
docker compose top                   # processes trong containers

# Execute
docker compose exec app bash         # shell vào container
docker compose exec db psql -U admin

# Scale
docker compose up -d --scale app=3  # chạy 3 instances của app (cần port dynamic)

# Run one-off command (container tạm thời)
docker compose run --rm app python manage.py migrate
docker compose run --rm app sh -c "echo test"
```

### How – Multiple Compose Files (Overrides)

```bash
# compose.yaml              – base config
# compose.override.yaml     – dev overrides (auto-merged)
# compose.prod.yaml         – prod overrides

# Dev (auto merge compose.yaml + compose.override.yaml)
docker compose up

# Production
docker compose -f compose.yaml -f compose.prod.yaml up -d

# CI/CD Testing
docker compose -f compose.yaml -f compose.test.yaml run tests
```

```yaml
# compose.override.yaml (dev)
services:
  app:
    build:
      target: development            # dev stage của multi-stage build
    volumes:
      - .:/app                       # mount source code (hot reload)
    environment:
      - DEBUG=true
    ports:
      - "5005:5005"                  # Java debug port

  db:
    ports:
      - "5432:5432"                  # expose DB port ra dev machine
```

### How – Profiles (Optional Services)

```yaml
services:
  app:
    image: myapp

  db:
    image: postgres

  adminer:
    image: adminer
    profiles: ["tools"]              # chỉ start khi --profile tools

  prometheus:
    image: prom/prometheus
    profiles: ["monitoring"]
```

```bash
docker compose --profile tools up    # start app, db, adminer
docker compose up                    # chỉ start app, db
```

### How – Secrets & Configs

```yaml
services:
  app:
    secrets:
      - db_password
      - api_key
    configs:
      - nginx_config

secrets:
  db_password:
    file: ./secrets/db_password.txt  # dev
    # external: true                 # prod (Docker Swarm / Kubernetes)
  api_key:
    environment: API_KEY             # từ env var trên host

configs:
  nginx_config:
    file: ./nginx/nginx.conf
```
> Secrets được mount tại `/run/secrets/<name>` trong container (tmpfs – không ghi disk)

### Compare – depends_on conditions

| Condition | Ý nghĩa |
|-----------|---------|
| `service_started` | Service đã start (không care healthy/not) |
| `service_healthy` | Service healthy (cần định nghĩa healthcheck) |
| `service_completed_successfully` | Service đã exit 0 (dùng cho migration jobs) |

### Trade-offs
- Docker Compose tốt cho dev và single-host; không phải orchestrator (dùng K8s cho multi-host)
- `depends_on` chỉ kiểm soát thứ tự start, không đảm bảo app sẵn sàng nhận request
- Scaling với Compose hạn chế (container_name conflict, port binding issues)

### Real-world Usage
```bash
# Production deployment với zero-downtime (đơn giản)
docker compose pull                  # pull images mới
docker compose up -d --no-deps app  # restart chỉ app service

# Database migration trước khi deploy
docker compose run --rm app python manage.py migrate
docker compose up -d

# Cleanup dev environment
docker compose down -v --rmi local   # xóa containers, volumes, local images
```

### Ghi chú – Chủ đề tiếp theo
> Dockerfile Best Practices – multi-stage, layer optimization, security, build args vs env

---

## 7. Dockerfile Best Practices

### What – Mục tiêu
Viết Dockerfile để tạo image **nhỏ nhất**, **build nhanh nhất**, **bảo mật nhất**, và **dễ maintain**.

### How – Chọn Base Image

```dockerfile
# BAD: lớn (~900MB), nhiều vulnerabilities
FROM ubuntu:latest

# BAD: latest → build không reproducible
FROM node:latest

# GOOD: pin version, dùng slim/alpine
FROM node:20.11-alpine3.19           # ~50MB (thay vì ~1GB full node)
FROM eclipse-temurin:21.0.2_13-jre-alpine  # Java JRE only

# Lưu ý Alpine:
# - dùng musl libc (có thể gây issues với native libs như bcrypt, sharp)
# - Không có bash mặc định (dùng sh hoặc thêm RUN apk add bash)
# - Không có glibc (một số JARs cần: thêm glibc layer hoặc dùng distroless)

# Google Distroless (cực nhỏ, không có shell – production)
FROM gcr.io/distroless/java21-debian12
```

### How – Layer Optimization

```dockerfile
# ❌ BAD: mỗi RUN = 1 layer; cache bị phá khi source thay đổi
FROM node:20-alpine
COPY . .
RUN npm install
RUN npm run build
RUN npm prune --production

# ✅ GOOD: copy dependencies trước, build sau
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production         # ci: reproducible install

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=deps /app/node_modules ./node_modules
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

### How – Giảm Size

```dockerfile
# Combine RUN commands → ít layers
# Clean up trong CÙNG RUN → không bị giữ trong layer trước
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl \
       libpq-dev \
    && rm -rf /var/lib/apt/lists/*   # ← xóa ngay trong cùng RUN!

# Alpine: dùng --no-cache
RUN apk add --no-cache curl postgresql-client

# npm: không cài dev dependencies trên prod
RUN npm ci --omit=dev

# pip: không cache
RUN pip install --no-cache-dir -r requirements.txt

# Maven: offline dependencies tách layer
COPY pom.xml .
RUN mvn dependency:go-offline -B     # cache layer
COPY src ./src
RUN mvn package -DskipTests
```

### How – Security Best Practices

```dockerfile
# 1. Non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
# Alpine:
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

USER appuser                         # switch trước CMD/ENTRYPOINT

# 2. Read-only root filesystem
# docker run --read-only -v /tmp:/tmp myapp
# Cấu hình trong compose.yaml: read_only: true

# 3. Drop capabilities
# docker run --cap-drop ALL --cap-add NET_BIND_SERVICE myapp

# 4. No secrets in Dockerfile / image
# BAD:
ENV DB_PASSWORD=secret               # lộ trong image layers!
ARG DB_PASSWORD                      # ARG cũng lộ trong history!

# GOOD: inject lúc runtime
docker run -e DB_PASSWORD=$DB_PASSWORD myapp
# Hoặc dùng Docker secrets / Vault

# 5. Pin base image digest (reproducible + secure)
FROM node:20.11-alpine3.19@sha256:abc123...

# 6. COPY thay vì ADD (tránh unexpected tar extraction)
COPY app.tar.gz .
RUN tar xzf app.tar.gz && rm app.tar.gz
# Không dùng: ADD app.tar.gz .  (magic behavior)
```

### How – Build Arguments

```dockerfile
# ARG – chỉ available trong build time
ARG APP_VERSION=1.0.0
ARG BUILD_DATE
LABEL version="$APP_VERSION"
LABEL build-date="$BUILD_DATE"

# ENV – available trong container runtime
ENV APP_VERSION=$APP_VERSION         # copy từ ARG sang ENV nếu cần runtime

# Build với args
docker build \
  --build-arg APP_VERSION=2.0.0 \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  -t myapp:2.0.0 .
```

### How – Multi-platform Build (BuildKit)

```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1

# Build cho nhiều platform
docker buildx create --use --name mybuilder
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t myapp:latest \
  --push .                           # push trực tiếp lên registry

# Kiểm tra platform
docker inspect myapp:latest | jq '.[0].Architecture'
```

### How – ONBUILD (Advanced)

```dockerfile
# Base image dùng cho nhiều projects
FROM node:20-alpine
WORKDIR /app
ONBUILD COPY package*.json ./        # chạy khi image này được dùng làm base
ONBUILD RUN npm ci
ONBUILD COPY . .

# Child project Dockerfile
FROM mybase-node:20                  # ONBUILD triggers chạy tự động
CMD ["node", "server.js"]
```

### Checklist Best Practices

```
☑ Pin base image version (không dùng :latest)
☑ Sử dụng multi-stage build
☑ Copy dependencies files trước source code (cache optimization)
☑ Merge RUN commands, cleanup trong cùng layer
☑ Dùng .dockerignore
☑ Chạy với non-root user
☑ ENTRYPOINT ở exec form (["..."])
☑ Định nghĩa HEALTHCHECK
☑ Không hardcode secrets
☑ Scan image vulnerabilities (trivy, docker scout)
```

### Real-world Usage
```bash
# Đo size trước và sau tối ưu
docker images --format "{{.Size}}" myapp:before
docker images --format "{{.Size}}" myapp:after

# Phân tích layers với dive
dive myapp:latest

# Scan vulnerabilities
trivy image --severity HIGH,CRITICAL myapp:latest
docker scout cves myapp:latest
```

### Ghi chú – Chủ đề tiếp theo
> Docker Registry – Docker Hub, private registry, ECR, Harbor, image signing

---

## 8. Docker Registry & Image Management

### What – Registry là gì?
**Container Registry** là kho lưu trữ Docker images theo mô hình **client-server**. Registry lưu images theo format: `registry/namespace/repository:tag`.

### How – Docker Hub

```bash
# Login
docker login                                    # Docker Hub
docker login registry.example.com              # private registry
docker login -u $USER -p $TOKEN registry.io    # non-interactive (CI/CD)
docker logout

# Pull
docker pull nginx                              # nginx:latest từ Docker Hub
docker pull nginx:1.25-alpine                  # specific version
docker pull ubuntu@sha256:abc123...            # specific digest (immutable)

# Push
docker tag myapp:1.0 username/myapp:1.0       # tag với namespace
docker push username/myapp:1.0

# Semantic versioning tags (best practice)
docker tag myapp:1.2.3 myrepo/myapp:1.2.3
docker tag myapp:1.2.3 myrepo/myapp:1.2
docker tag myapp:1.2.3 myrepo/myapp:1
docker tag myapp:1.2.3 myrepo/myapp:latest
# → cho phép pin theo patch, minor, hoặc major
```

### How – Private Registry

```bash
# Chạy private registry đơn giản
docker run -d \
  --name registry \
  -p 5000:5000 \
  -v registry-data:/var/lib/registry \
  registry:2

# Push vào private registry
docker tag myapp:1.0 localhost:5000/myapp:1.0
docker push localhost:5000/myapp:1.0

# Pull từ private registry
docker pull localhost:5000/myapp:1.0

# Registry với authentication & TLS
docker run -d \
  --name registry \
  -p 443:443 \
  -e REGISTRY_HTTP_ADDR=0.0.0.0:443 \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  -v /certs:/certs \
  -v /auth:/auth \
  registry:2
```

### How – AWS ECR (Elastic Container Registry)

```bash
# Authenticate
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin \
  123456789.dkr.ecr.ap-southeast-1.amazonaws.com

# Create repository
aws ecr create-repository --repository-name myapp

# Push
docker tag myapp:1.0 123456789.dkr.ecr.ap-southeast-1.amazonaws.com/myapp:1.0
docker push 123456789.dkr.ecr.ap-southeast-1.amazonaws.com/myapp:1.0

# Lifecycle policy (auto-delete old images)
aws ecr put-lifecycle-policy \
  --repository-name myapp \
  --lifecycle-policy-text file://lifecycle.json
```

### How – Image Tagging Strategy

```
Production strategy:
├── :latest          → không dùng trên production (mutable, không biết version nào)
├── :1.2.3           → semantic version (immutable reference)
├── :1.2             → minor version (updates patch)
├── :main-abc1234    → branch + git commit SHA (CI/CD)
└── @sha256:abc...   → digest (truly immutable, dùng trong k8s production)
```

```yaml
# Kubernetes best practice – pin digest
containers:
  - image: nginx:1.25@sha256:abc123def456...  # không bao giờ thay đổi
```

### How – Image Signing (Cosign)

```bash
# Ký image với cosign (Sigstore)
cosign generate-key-pair                       # tạo key pair
cosign sign --key cosign.key myapp:1.0         # ký

# Verify
cosign verify --key cosign.pub myapp:1.0

# Trong CI/CD pipeline (keyless signing với OIDC)
cosign sign --yes myapp:1.0
```

### Compare – Registry Options

| | Docker Hub | ECR | GCR/GAR | Harbor |
|--|-----------|-----|---------|--------|
| Cost | Free tier / $5+ | Pay per storage | Pay per storage | Self-hosted |
| Scan | Basic (free) | Trivy/Inspector | Container Analysis | Trivy built-in |
| Auth | Docker login | IAM | Workload Identity | LDAP/OIDC |
| Private | 1 repo free | Có | Có | Có |
| Geo-replication | Không | Per region | Global | Plugin |

### Real-world Usage
```bash
# CI/CD pipeline (GitHub Actions)
# - Build image
# - Tag với commit SHA
# - Push to ECR
# - Update Kubernetes deployment

# Cache layers trong CI (BuildKit)
docker buildx build \
  --cache-from type=registry,ref=ecr.../myapp:cache \
  --cache-to type=registry,ref=ecr.../myapp:cache,mode=max \
  --push \
  -t ecr.../myapp:$GIT_SHA .

# Garbage collection (local)
docker image prune -a --filter "until=720h"    # xóa images > 30 ngày
```

### Ghi chú – Chủ đề tiếp theo
> Docker Security – rootless Docker, capabilities, seccomp, AppArmor, image scanning

---

## 9. Docker Security

### What – Docker Security là gì?
Bảo mật Docker bao gồm: **image security** (vulnerabilities), **container isolation** (runtime security), **secrets management**, và **host security** (Docker daemon access).

### How – Container Isolation Security Model

```
Docker Security Layers:
├── Linux Namespaces   → isolation (PID, NET, MNT, UTS, IPC, USER)
├── cgroups            → resource limits (tránh DoS)
├── Capabilities       → giảm quyền root
├── Seccomp            → filter system calls
├── AppArmor/SELinux   → mandatory access control
└── User namespace     → rootless containers
```

### How – Linux Capabilities

```bash
# Container mặc định chạy với một số capabilities (không phải full root):
# CAP_CHOWN, CAP_DAC_OVERRIDE, CAP_SETUID, CAP_SETGID, CAP_NET_BIND_SERVICE, ...

# Drop ALL, thêm chỉ cần thiết (least privilege)
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE nginx

# Xem capabilities cần thiết
docker run --rm -it ubuntu capsh --print

# Privileged mode – trao TOÀN BỘ capabilities (tránh dùng)
docker run --privileged myapp     # nguy hiểm! container có thể access host devices
```

### How – Seccomp (Syscall Filtering)

```bash
# Mặc định Docker áp dụng seccomp profile (~300 syscalls blocked)
# Custom seccomp profile
docker run --security-opt seccomp=/path/to/seccomp.json myapp

# Tắt seccomp (chỉ cho debug)
docker run --security-opt seccomp=unconfined myapp

# Xem default seccomp profile
cat /etc/docker/seccomp.json | jq '.syscalls[].names | length'
```

### How – Rootless Docker

```bash
# Cài rootless Docker (Ubuntu)
dockerd-rootless-setuptool.sh install

# Chạy daemon không cần root
export DOCKER_HOST=unix:///run/user/1000/docker.sock
docker ps

# Ưu điểm: container escape không thể leo thang lên root
# Nhược điểm: một số features bị hạn chế (port < 1024, overlay network)
```

### How – Non-root User trong Container

```dockerfile
# Tạo user và switch
RUN useradd -r -u 1001 -g root appuser
USER 1001                            # dùng UID thay tên (portable hơn)

# Kiểm tra
docker run --rm myapp id             # uid=1001(appuser) gid=0(root)

# docker run override user
docker run -u 1001:1001 myapp
docker run -u nobody myapp
```

### How – Secrets Management

```bash
# ❌ BAD: ENV hoặc ARG trong Dockerfile
ENV DB_PASSWORD=supersecret          # lộ trong docker inspect, image history

# ❌ BAD: biến môi trường đơn giản
docker run -e DB_PASSWORD=$SECRET myapp  # lộ trong ps aux, docker inspect

# ✅ GOOD: Docker Secrets (Swarm)
echo "mysecret" | docker secret create db_password -
docker service create \
  --secret db_password \
  --env DB_PASSWORD_FILE=/run/secrets/db_password \
  myapp
# Đọc trong app: open("/run/secrets/db_password").read()

# ✅ GOOD: External secret manager
# AWS Secrets Manager / HashiCorp Vault / Azure Key Vault
# App chủ động fetch lúc startup, không mount vào environment

# ✅ GOOD: .env file (dev only, không commit)
docker run --env-file .env myapp
# .env vào .gitignore!
```

### How – Image Vulnerability Scanning

```bash
# Trivy (Aqua Security – open source)
trivy image nginx:latest             # scan Docker Hub image
trivy image --severity CRITICAL,HIGH myapp:1.0
trivy image --format json myapp:1.0 > scan-report.json
trivy image --exit-code 1 --severity CRITICAL myapp:1.0  # CI: fail nếu có CRITICAL

# Docker Scout (Docker official)
docker scout cves myapp:latest
docker scout recommendations myapp:latest  # gợi ý base image tốt hơn

# Grype (Anchore)
grype myapp:latest

# Tích hợp CI/CD
# GitHub Actions:
# - uses: aquasecurity/trivy-action@master
#   with:
#     image-ref: myapp:${{ github.sha }}
#     severity: CRITICAL,HIGH
#     exit-code: 1
```

### How – Read-only Container

```bash
# Mount read-only filesystem
docker run --read-only \
  -v /tmp:/tmp \                     # mount writable /tmp
  -v app-logs:/app/logs \            # mount writable logs
  myapp

# Trong compose.yaml
services:
  app:
    read_only: true
    tmpfs:
      - /tmp:size=100m,mode=1777    # tmpfs cho temp files
```

### How – Network Security

```bash
# Chỉ expose port cần thiết, bind localhost
docker run -p 127.0.0.1:8080:8080 myapp   # không expose ra ngoài

# Internal network (không có internet)
docker network create --internal backend-net

# Giới hạn bandwidth (cần tc/iptables)
docker run --device-write-bps /dev/sda:10mb myapp
```

### How – Docker Daemon Security

```bash
# /etc/docker/daemon.json
{
  "icc": false,                      # tắt inter-container communication (default bridge)
  "no-new-privileges": true,         # tránh privilege escalation
  "userns-remap": "default",         # enable user namespace remapping
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true               # containers tiếp tục chạy khi daemon restart
}
```

### Trade-offs
- rootless: an toàn hơn nhưng tính năng bị hạn chế
- --privileged: tiện cho một số use cases (Docker in Docker) nhưng mất isolation
- seccomp: tăng security nhưng có thể break apps dùng unusual syscalls
- Image scanning: quan trọng nhưng base images thường có nhiều CVEs không exploitable

### Real-world Usage
```bash
# Security audit: tìm containers chạy privileged
docker ps --quiet | xargs docker inspect \
  --format '{{.Name}}: Privileged={{.HostConfig.Privileged}}'

# Tìm containers mount Docker socket (nguy hiểm!)
docker ps --quiet | xargs docker inspect \
  --format '{{.Name}}: {{range .Mounts}}{{if eq .Source "/var/run/docker.sock"}}DOCKER SOCKET MOUNTED!{{end}}{{end}}'

# CIS Docker Benchmark (tự động audit)
docker run --rm --net host --pid host --cap-add audit_control \
  -v /etc:/etc:ro -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  docker/docker-bench-security
```

### Ghi chú – Chủ đề tiếp theo
> Docker Internals – namespaces, cgroups, OverlayFS, containerd/runc

---

## 10. Docker Internals

### What – Docker Internals là gì?
Hiểu cách Docker sử dụng **Linux primitives** để tạo containers: **namespaces** (isolation), **cgroups** (resource limits), **OverlayFS** (layered filesystem), và **containerd/runc** (runtime stack).

### How – Linux Namespaces

```bash
# Mỗi container có namespace riêng cho:

# 1. PID namespace: process tree riêng
docker run --rm ubuntu ps aux       # chỉ thấy processes trong container
cat /proc/self/status | grep NSpid  # host vs container PID

# 2. Network namespace: network stack riêng
docker exec myapp ip addr show      # eth0 + lo của container
ls /var/run/docker/netns/           # network namespaces

# 3. Mount namespace: filesystem view riêng
docker exec myapp mount | grep overlay

# 4. UTS namespace: hostname riêng
docker exec myapp hostname          # container ID hoặc --hostname value

# 5. IPC namespace: IPC resources riêng (shared memory, semaphores)
docker run --ipc=host myapp         # share host IPC namespace (database shared memory)

# 6. USER namespace: UID/GID mapping
# uid=0(root) trong container → uid=100000 trên host (rootless mode)
cat /proc/$(docker inspect --format '{{.State.Pid}}' myapp)/uid_map
```

### How – cgroups (Control Groups)

```bash
# cgroups limit resources cho container
# Docker tạo cgroup hierarchy tại: /sys/fs/cgroup/

# Xem cgroup của container
CONTAINER_ID=$(docker inspect --format '{{.Id}}' myapp)
cat /sys/fs/cgroup/memory/docker/$CONTAINER_ID/memory.limit_in_bytes
cat /sys/fs/cgroup/cpu/docker/$CONTAINER_ID/cpu.quota

# Thay đổi resource limits runtime (không restart)
docker update --memory=1g --cpus=2 myapp

# Xem stats
docker stats myapp --no-stream
# → CPU%, MEM USAGE/LIMIT, NET I/O, BLOCK I/O, PIDs
```

### How – OverlayFS (Layered Filesystem)

```
/var/lib/docker/overlay2/
├── <layer-hash-1>/           ← base image layer
│   └── diff/                 ← filesystem snapshot
├── <layer-hash-2>/
│   ├── diff/
│   └── lower                 ← pointer to parent layers
│
└── <container-id>/
    ├── diff/                 ← writable (upper) layer
    ├── merged/               ← union view (container thấy)
    ├── upper → diff/
    ├── work/                 ← OverlayFS internal
    └── lower                 ← image layers (read-only)
```

```bash
# Xem mount của container
docker inspect myapp | jq '.[0].GraphDriver'
mount | grep overlay | grep myapp

# Copy-on-Write:
# - Đọc file: đọc từ lower layers (nhanh)
# - Ghi file: copy lên upper layer, ghi vào đó (copy-on-write)
# - Xóa file: tạo "whiteout file" che layer bên dưới
```

### How – containerd & runc

```
Docker CLI (docker)
    ↓ REST API
Docker Daemon (dockerd)
    ↓ gRPC
containerd
    ↓ OCI runtime spec
runc (or crun, kata-containers)
    ↓ Linux syscalls (clone, unshare, mount, pivot_root, cgroups...)
Container (Linux process)
```

```bash
# containerd trực tiếp (không cần Docker)
ctr images pull docker.io/library/nginx:alpine
ctr run docker.io/library/nginx:alpine nginx

# nerdctl – Docker-compatible CLI trên containerd
nerdctl run -d -p 80:80 nginx
nerdctl compose up

# runc – thấp nhất
runc spec > config.json               # tạo OCI spec
runc run mycontainer                  # chạy container
```

### How – Docker Build Internals (BuildKit)

```
BuildKit (moby/buildkit) – modern build backend:
├── Parallel build steps (không tuần tự như legacy)
├── Better cache (content-addressable)
├── Secret mounts (không leak vào layers)
├── SSH forwarding (git clone private repos)
└── Multi-platform builds (buildx)
```

```bash
# Bật BuildKit
export DOCKER_BUILDKIT=1

# Mount secrets trong build (không để lại trong image)
docker build \
  --secret id=mysecret,src=./secret.txt \
  -t myapp .

# Trong Dockerfile (BuildKit secret)
RUN --mount=type=secret,id=mysecret \
    cat /run/secrets/mysecret | npm config set //registry.npmjs.org/:_authToken $(cat -)

# SSH forwarding (clone private repo)
docker build --ssh default -t myapp .
# Dockerfile:
# RUN --mount=type=ssh git clone git@github.com:private/repo.git
```

### How – Docker in Docker (DinD)

```bash
# Sử dụng trong CI/CD (Jenkins, GitLab CI)

# Option 1: DinD (chạy daemon trong container – cần privileged)
docker run --privileged docker:dind

# Option 2: Mount host Docker socket (phổ biến hơn, nhưng security risk)
docker run -v /var/run/docker.sock:/var/run/docker.sock docker:latest

# Option 3: Kaniko (build image không cần daemon, không cần privileged)
# Phù hợp Kubernetes CI
docker run --rm \
  -v $(pwd):/workspace \
  gcr.io/kaniko-project/executor:latest \
  --context /workspace \
  --dockerfile /workspace/Dockerfile \
  --destination myrepo/myapp:latest

# Option 4: BuildKit standalone (buildkitd)
```

### Compare – Docker vs Podman Internals

| | Docker | Podman |
|--|--------|--------|
| Architecture | Daemon-based (dockerd) | Daemonless (fork/exec) |
| Root | dockerd chạy root | Daemonless, rootless native |
| Runtime | containerd → runc | crun (default) hoặc runc |
| Compatibility | - | Docker-compatible CLI |
| systemd | Không native | Systemd cgroup v2 integration |

### Real-world Usage
```bash
# Xem tất cả namespaces của container
CPID=$(docker inspect --format '{{.State.Pid}}' myapp)
ls -la /proc/$CPID/ns/

# "Enter" namespace của container từ host (debug)
nsenter -t $CPID --net -- ss -tlnp
nsenter -t $CPID --pid --mount -- ps aux

# Xem OverlayFS usage
du -sh /var/lib/docker/overlay2/
docker system df -v               # chi tiết usage

# Clearn dangling layers
docker system prune --volumes
```

### Ghi chú – Chủ đề tiếp theo
> Docker in Production – logging drivers, monitoring, resource management, CI/CD pipelines

---

## 11. Docker trong Production

### What – Production Considerations
Chạy Docker trên production đòi hỏi xem xét: **logging**, **monitoring**, **resource limits**, **health checks**, **zero-downtime deployment**, và **CI/CD integration**.

### How – Logging Drivers

```bash
# Logging drivers phổ biến
docker run --log-driver json-file \
  --log-opt max-size=10m \
  --log-opt max-file=3 \
  myapp                              # default, lưu /var/lib/docker/containers/

docker run --log-driver syslog myapp           # systemd journal
docker run --log-driver journald myapp         # journald

docker run --log-driver fluentd \
  --log-opt fluentd-address=localhost:24224 \
  myapp                              # EFK stack (Elasticsearch + Fluentd + Kibana)

docker run --log-driver awslogs \
  --log-opt awslogs-group=/app/prod \
  --log-opt awslogs-region=ap-southeast-1 \
  myapp                              # AWS CloudWatch

# /etc/docker/daemon.json – set globally
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5",
    "labels": "service,env",
    "env": "SERVICE_NAME,APP_VERSION"
  }
}
```

### How – Resource Limits (Production)

```bash
# Memory
docker run --memory=512m myapp            # hard limit
docker run --memory=512m \
           --memory-reservation=256m \    # soft limit (khi host cần memory)
           myapp

# CPU
docker run --cpus=1.5 myapp              # 1.5 CPUs (quota/period)
docker run --cpu-shares=512 myapp        # relative weight (1024 = full CPU)
docker run --cpuset-cpus="0,1" myapp     # pin to specific CPUs

# Disk I/O
docker run --device-read-bps /dev/sda:10mb myapp
docker run --device-write-bps /dev/sda:10mb myapp

# Compose production
services:
  app:
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 1G
        reservations:
          cpus: "0.5"
          memory: 512M
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
```

### How – Zero-downtime Deployment

```bash
# Approach 1: Blue-Green (với load balancer)
# 1. Build new image
docker build -t myapp:v2 .
docker push myapp:v2

# 2. Start new containers (green)
docker run -d --name app-green myapp:v2

# 3. Switch load balancer → green
# 4. Remove old containers (blue)
docker rm -f app-blue

# Approach 2: Rolling update với Compose
docker compose pull app              # pull new image
docker compose up -d --no-deps \
  --scale app=4 app                  # scale up (thêm instances mới)
# Sau khi healthy:
docker compose up -d --no-deps \
  --scale app=2 app                  # scale back down (chỉ còn instances mới)

# Approach 3: Docker Swarm rolling update
docker service update \
  --image myapp:v2 \
  --update-parallelism 1 \
  --update-delay 30s \
  --update-failure-action rollback \
  myapp-service
```

### How – Health Check & Readiness

```yaml
# compose.yaml production pattern
services:
  app:
    image: myapp:${VERSION}
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:8080/health | jq .status | grep -q ok"]
      interval: 15s
      timeout: 5s
      retries: 3
      start_period: 60s              # grace period khi start (JVM warmup, etc.)
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped
    stop_grace_period: 30s           # thời gian để graceful shutdown (SIGTERM → SIGKILL)
```

### How – Monitoring

```bash
# Prometheus + cAdvisor (container metrics)
docker run -d \
  --name cadvisor \
  --volume=/:/rootfs:ro \
  --volume=/var/run:/var/run:ro \
  --volume=/sys:/sys:ro \
  --volume=/var/lib/docker/:/var/lib/docker:ro \
  -p 8080:8080 \
  gcr.io/cadvisor/cadvisor:latest

# Metrics từ cAdvisor → Prometheus → Grafana

# Prometheus scrape config
# - job_name: 'cadvisor'
#   static_configs:
#     - targets: ['cadvisor:8080']

# Docker daemon metrics (Prometheus)
# /etc/docker/daemon.json:
# { "metrics-addr": "0.0.0.0:9323" }
```

### How – CI/CD Pipeline

```yaml
# GitHub Actions example
name: Build and Deploy
on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and Push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ env.ECR_REGISTRY }}/myapp:${{ github.sha }}
          cache-from: type=gha        # GitHub Actions cache
          cache-to: type=gha,mode=max

      - name: Scan for vulnerabilities
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.ECR_REGISTRY }}/myapp:${{ github.sha }}
          severity: CRITICAL
          exit-code: 1

      - name: Deploy to ECS
        run: |
          aws ecs update-service \
            --cluster prod \
            --service myapp \
            --force-new-deployment
```

### How – docker-compose.prod.yaml Pattern

```yaml
# compose.prod.yaml
services:
  app:
    image: ${ECR_REGISTRY}/myapp:${VERSION}   # không build trên prod
    restart: always
    logging:
      driver: awslogs
      options:
        awslogs-group: /prod/myapp
        awslogs-region: ap-southeast-1
    environment:
      - NODE_ENV=production
    secrets:
      - db_password
      - api_key
    deploy:
      resources:
        limits:
          cpus: "2.0"
          memory: 2G
    read_only: true
    tmpfs:
      - /tmp

  nginx:
    image: nginx:1.25-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
    restart: always
```

### Real-world Usage
```bash
# Deployment script
#!/bin/bash
set -euo pipefail

VERSION=$1
export VERSION

echo "Deploying version $VERSION..."

# Pull mới nhất
docker compose -f compose.yaml -f compose.prod.yaml pull

# Run migrations
docker compose -f compose.yaml -f compose.prod.yaml \
  run --rm app npm run migrate

# Deploy với restart
docker compose -f compose.yaml -f compose.prod.yaml \
  up -d --no-deps app nginx

# Wait for healthy
timeout 120 bash -c 'until docker compose ps app | grep -q healthy; do sleep 5; done'
echo "Deployment complete!"
```

### Ghi chú – Chủ đề tiếp theo
> Docker Swarm – orchestration, services, stacks, rolling updates; giới thiệu Kubernetes

---

## 12. Docker Swarm & Orchestration

### What – Docker Swarm là gì?
**Docker Swarm** là orchestration engine tích hợp sẵn trong Docker, cho phép quản lý cluster nhiều Docker hosts, deploy **services** với auto-scaling, rolling updates, và load balancing.

### How – Swarm Architecture

```
┌─────────────────────────────────────────────────┐
│                  Swarm Cluster                   │
│                                                  │
│  ┌──────────────┐    ┌──────────────┐           │
│  │  Manager 1   │    │  Manager 2   │           │
│  │  (Leader)    │◄──►│  (Follower)  │           │
│  └──────┬───────┘    └──────────────┘           │
│         │  Raft consensus (quorum = N/2+1)       │
│         │                                        │
│  ┌──────▼──────────────────────────────┐        │
│  │           Worker Nodes              │        │
│  │  ┌────────┐  ┌────────┐  ┌────────┐│        │
│  │  │Worker 1│  │Worker 2│  │Worker 3││        │
│  │  └────────┘  └────────┘  └────────┘│        │
│  └─────────────────────────────────────┘        │
└─────────────────────────────────────────────────┘
```

### How – Swarm Commands

```bash
# Khởi tạo Swarm
docker swarm init --advertise-addr 192.168.1.100

# Join workers
docker swarm join \
  --token SWMTKN-1-xxx \
  192.168.1.100:2377

# Join managers
docker swarm join-token manager    # lấy manager token
docker node ls                      # xem tất cả nodes
docker node inspect worker1         # chi tiết node
docker node promote worker1         # promote worker → manager
docker node demote manager2         # demote manager → worker
docker node update --availability drain worker1  # maintenance mode

# Services (thay thế docker run trong Swarm)
docker service create \
  --name web \
  --replicas 3 \
  --publish published=80,target=80 \
  --network myoverlay \
  nginx:alpine

docker service ls                   # list services
docker service ps web               # tasks (containers) của service
docker service logs -f web          # logs
docker service inspect web --pretty

# Scale
docker service scale web=5

# Update (rolling)
docker service update \
  --image nginx:1.25 \
  --update-parallelism 1 \          # 1 container tại 1 thời điểm
  --update-delay 30s \              # đợi 30s giữa các updates
  --update-failure-action rollback \ # rollback nếu fail
  web

# Rollback
docker service rollback web

# Remove
docker service rm web
```

### How – Stacks (Compose on Swarm)

```bash
# Deploy stack từ compose file
docker stack deploy -c compose.yaml mystack
docker stack ls                     # list stacks
docker stack ps mystack             # tasks của stack
docker stack services mystack       # services trong stack
docker stack rm mystack             # xóa stack

# compose.yaml cho Swarm (dùng deploy section)
services:
  app:
    image: myapp:1.0                # phải là image (không build trên Swarm)
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 30s
        failure_action: rollback
        order: start-first           # start mới trước khi stop cũ (zero-downtime)
      rollback_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
      placement:
        constraints:
          - node.role == worker
          - node.labels.env == prod
      resources:
        limits:
          cpus: "1.0"
          memory: 512M
    networks:
      - myoverlay

  db:
    image: postgres:16
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.labels.db == true   # pin DB đến node có label db=true
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:

networks:
  myoverlay:
    driver: overlay
    attachable: true
```

### How – Swarm Secrets & Configs

```bash
# Secrets (encrypted at rest, transmitted encrypted)
echo "mysecretpassword" | docker secret create db_password -
docker secret ls
docker secret inspect db_password

# Dùng trong service
docker service create \
  --name db \
  --secret db_password \
  -e POSTGRES_PASSWORD_FILE=/run/secrets/db_password \
  postgres:16

# Configs (non-sensitive config files)
docker config create nginx_config ./nginx.conf
docker service create \
  --name proxy \
  --config src=nginx_config,target=/etc/nginx/nginx.conf \
  nginx:alpine
```

### Compare – Docker Swarm vs Kubernetes

| | Docker Swarm | Kubernetes |
|--|-------------|-----------|
| **Độ phức tạp** | Đơn giản | Phức tạp (học nhiều hơn) |
| **Setup** | `docker swarm init` | kubeadm / managed (EKS, GKE, AKS) |
| **Scaling** | Tốt (manual + auto qua Swarm) | Rất tốt (HPA, VPA, KEDA) |
| **Self-healing** | Basic | Nâng cao |
| **Networking** | Overlay (built-in) | CNI plugins (Calico, Cilium) |
| **Storage** | Volume plugins | StorageClass, PV/PVC |
| **Observability** | Cơ bản | Phong phú (metrics, tracing, logging) |
| **Ecosystem** | Docker | Cực lớn (CNCF) |
| **Khi dùng** | Small-medium teams, simple needs | Large scale, complex requirements |

### Trade-offs
- Swarm: dễ dùng, tích hợp Docker nhưng ít tính năng hơn K8s
- K8s: mạnh mẽ nhưng operational overhead cao, learning curve dốc
- Swarm vs K8s không phải either/or – nhiều team bắt đầu với Swarm rồi migrate sang K8s

### Real-world Usage
```bash
# Drain node để maintenance
docker node update --availability drain worker2
# → Swarm tự move tasks sang nodes khác

# Sau maintenance
docker node update --availability active worker2

# Monitor Swarm
watch docker service ls            # xem replicas running/desired
docker service ps --filter "desired-state=running" web

# Visualizer (xem cluster trực quan)
docker service create \
  --name visualizer \
  --publish 8080:8080 \
  --constraint node.role==manager \
  --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
  dockersamples/visualizer:latest
```

### Ghi chú – Chủ đề tiếp theo
> Kubernetes basics (dùng Docker knowledge làm nền); Container monitoring (Prometheus + Grafana + cAdvisor); Service mesh (Istio, Linkerd)

---

*Cập nhật lần cuối: 2026-05-06*
