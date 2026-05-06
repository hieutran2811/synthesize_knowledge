# Docker Swarm Advanced – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Swarm HA (High Availability)

### What – Swarm HA là gì?
Swarm HA đảm bảo cluster tiếp tục hoạt động khi một số manager nodes bị lỗi, dùng **Raft consensus algorithm** để đồng thuận về cluster state.

### How – Raft Consensus

```
Raft Quorum Rule: cần N/2+1 managers để cluster hoạt động

Ví dụ:
├── 1 manager: 0 fault tolerance (không HA)
├── 3 managers: 1 fault tolerance (quorum = 2)
├── 5 managers: 2 fault tolerance (quorum = 3)
└── 7 managers: 3 fault tolerance (quorum = 4)

Khuyến nghị: 3 hoặc 5 managers (5 cho datacenter HA)
Không dùng số chẵn managers (split-brain risk)
```

```bash
# Setup 3-node manager cluster
# Node 1 (manager 1): khởi tạo Swarm
docker swarm init --advertise-addr 10.0.0.1

# Node 2, 3: join as managers
TOKEN=$(docker swarm join-token manager -q)
# Trên node 2:
docker swarm join --token $TOKEN 10.0.0.1:2377
# Trên node 3:
docker swarm join --token $TOKEN 10.0.0.1:2377

# Kiểm tra cluster status
docker node ls
# ID                       HOSTNAME  STATUS  AVAILABILITY  MANAGER STATUS
# abc123 *                 node1     Ready   Active        Leader
# def456                   node2     Ready   Active        Reachable
# ghi789                   node3     Ready   Active        Reachable

# Xem Raft log
docker node inspect node1 --format '{{json .ManagerStatus}}'

# Promote / Demote
docker node promote node4             # worker → manager
docker node demote node2              # manager → worker
```

### How – Manager Separation từ Worker

```bash
# Best practice: managers không chạy user workloads
docker node update --availability drain manager1
docker node update --availability drain manager2
docker node update --availability drain manager3
# → Tasks chỉ schedule lên workers

# Workers:
docker node update --availability active worker1
# availability: active (nhận tasks), pause (tạm dừng), drain (không nhận task mới)

# Placement constraints: enforce manager/worker separation
docker service create \
  --constraint "node.role == worker" \
  myapp

docker service create \
  --constraint "node.role == manager" \
  monitoring-agent  # tools cần access manager state
```

### How – Disaster Recovery

```bash
# Kịch bản: mất quorum (ví dụ 2/3 managers offline)
# → Cluster bị lock, không thể schedule services

# Khôi phục từ 1 node còn lại (NGUY HIỂM - mất data Raft)
docker swarm init --force-new-cluster \
  --advertise-addr 10.0.0.1

# Backup Raft state thường xuyên
# Manager nodes: /var/lib/docker/swarm/
tar -czf swarm-backup-$(date +%Y%m%d).tar.gz /var/lib/docker/swarm/

# Restore trên node mới
systemctl stop docker
tar -xzf swarm-backup.tar.gz -C /var/lib/docker/
systemctl start docker
docker swarm init --force-new-cluster --advertise-addr <new-ip>
```

---

## 2. Swarm Networking Advanced

### How – Ingress Network (Load Balancing)

```
Swarm Ingress Network:
├── Overlay network tự động tạo: "ingress"
├── Mỗi worker node có ingress-sbox namespace
├── Published ports → routing mesh → IPVS load balancing
└── Bất kỳ node nào cũng có thể nhận traffic cho service

Traffic flow:
Client → worker:80 → ingress overlay → IPVS VIP → container
```

```bash
# Routing mesh: publish port trên tất cả nodes
docker service create \
  --name web \
  --publish mode=ingress,target=80,published=80 \
  nginx

# → Gửi request đến bất kỳ node nào:
curl http://node1:80    # → nginx container (có thể trên node khác)
curl http://node2:80    # → nginx container (cùng VIP, IPVS round-robin)

# Host mode: chỉ publish trên node đang chạy container
docker service create \
  --name web \
  --publish mode=host,target=80,published=80 \
  --mode global \        # 1 replica per node
  nginx
# → curl http://node1:80 chỉ hoạt động nếu container chạy trên node1
```

### How – Service VIP vs DNSRR

```bash
# VIP mode (default): service có 1 Virtual IP, IPVS load balance
docker service create \
  --name app \
  --endpoint-mode vip \            # default
  myapp

# DNSRR mode: DNS round-robin, không có VIP
docker service create \
  --name app \
  --endpoint-mode dnsrr \          # trả về all task IPs
  myapp

# Khi nào dùng DNSRR:
# - Client cần biết tất cả IPs (Elasticsearch discovery)
# - L7 load balancing cần sticky sessions
# - VIP gây issues với DNS caching

# Xem VIP của service
docker service inspect web | jq '.[0].Endpoint.VirtualIPs'
```

### How – Overlay Network Management

```bash
# Tạo encrypted overlay
docker network create \
  --driver overlay \
  --opt encrypted \                # mã hóa data plane (IPsec)
  --subnet 10.0.1.0/24 \
  secure-net

# Network scope
docker network ls
# NETWORK ID   NAME       DRIVER   SCOPE
# abc123       ingress    overlay  swarm     ← swarm scope
# def456       mynet      overlay  local     ← local scope (swarm mode)

# Attach standalone container vào overlay (--attachable)
docker network create --driver overlay --attachable mynet
docker run --network mynet myapp          # standalone container

# Xem network topology
docker network inspect ingress | jq '.[0].Peers'
```

---

## 3. Global Services & Placement

### How – Service Modes

```bash
# Replicated (default): N replicas, scheduler phân bổ
docker service create --replicas 3 --name app myapp

# Global: 1 replica mỗi node (log aggregator, monitoring agent)
docker service create \
  --mode global \
  --name node-exporter \
  prom/node-exporter

# Global với constraints (chỉ workers)
docker service create \
  --mode global \
  --constraint "node.role == worker" \
  --name fluent-bit \
  fluent/fluent-bit
```

### How – Placement Constraints & Preferences

```bash
# Constraints: hard rules (phải thỏa mãn)
docker service create \
  --constraint "node.role == worker" \
  --constraint "node.labels.env == production" \
  --constraint "node.labels.disk == ssd" \
  myapp

# Set node labels
docker node update --label-add env=production node1
docker node update --label-add disk=ssd node1
docker node update --label-add region=ap-southeast-1 node1

# Preferences: soft rules (cố gắng thỏa mãn, spread evenly)
docker service create \
  --replicas 6 \
  --placement-pref spread=node.labels.region \
  # → 3 replicas mỗi region (spread evenly)
  myapp

# Combine constraints + preferences
docker service create \
  --replicas 4 \
  --constraint "node.labels.env == production" \
  --placement-pref spread=node.labels.zone \
  myapp
```

---

## 4. Config Rotation & Zero-Downtime

### How – Rotate Secrets & Configs

```bash
# ── Secret Rotation (Zero-Downtime) ──────────────────────────
# 1. Tạo secret mới (với version suffix)
echo "newpassword123" | docker secret create db_password_v2 -

# 2. Update service: thêm secret mới, giữ secret cũ (để graceful transition)
docker service update \
  --secret-add source=db_password_v2,target=/run/secrets/db_password \
  myapp

# App đọc lại secret file → automatic (nếu app watch file changes)

# 3. Confirm service healthy với secret mới
docker service ps myapp

# 4. Remove secret cũ
docker service update --secret-rm db_password myapp
docker secret rm db_password

# ── Config Rotation ───────────────────────────────────────────
echo "server { listen 80; ... }" | docker config create nginx_config_v2 -

docker service update \
  --config-rm nginx_config \
  --config-add source=nginx_config_v2,target=/etc/nginx/nginx.conf \
  nginx-proxy

docker config rm nginx_config
```

### How – Rolling Update Configuration

```bash
# Rolling update chi tiết
docker service update \
  --image myapp:v2 \
  --update-parallelism 2 \          # 2 containers cùng lúc
  --update-delay 30s \              # đợi 30s giữa batches
  --update-order start-first \      # start mới trước khi stop cũ
  --update-failure-action rollback \# rollback nếu update fail
  --update-monitor 60s \            # monitor 60s sau update
  --update-max-failure-ratio 0.2 \  # fail nếu > 20% containers fail
  myapp

# Rollback tự động (khi update-failure-action=rollback)
# hoặc manual:
docker service rollback myapp

# Rollback config
docker service update \
  --rollback-parallelism 2 \
  --rollback-delay 10s \
  --rollback-failure-action pause \
  myapp

# Xem update status
docker service inspect myapp --pretty | grep -A 10 "UpdateStatus"
docker service ps myapp             # xem từng task
```

---

## 5. Health-based Scheduling

### How – Service Health Integration

```bash
# Swarm sử dụng container health check để scheduling
docker service create \
  --name app \
  --replicas 3 \
  --health-cmd "curl -f http://localhost:8080/health || exit 1" \
  --health-interval 30s \
  --health-timeout 5s \
  --health-retries 3 \
  --health-start-period 60s \       # grace period sau start
  myapp

# Swarm không route traffic đến unhealthy replicas
# Nếu replica unhealthy sau retries → restart automatically

# Xem health của tasks
docker service ps --filter "desired-state=running" myapp
# NAME         NODE    CURRENT STATE      ERROR
# app.1.abc   node1   Running 2 days     
# app.2.def   node2   Running 1 day      
# app.3.ghi   node3   Failed 5 hours     "health check failed"
```

---

## 6. Monitoring Swarm Cluster

### How – Swarm Metrics

```bash
# Visualizer (web UI)
docker service create \
  --name visualizer \
  --publish 8080:8080 \
  --constraint "node.role == manager" \
  --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
  dockersamples/visualizer

# Portainer (comprehensive UI)
docker service create \
  --name portainer \
  --publish 9000:9000 \
  --constraint "node.role == manager" \
  --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
  portainer/portainer-ce:latest \
  --admin-password-file /tmp/portainer_password

# Prometheus Swarm metrics
docker service create \
  --name prometheus \
  --publish 9090:9090 \
  --constraint "node.role == manager" \
  --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
  prom/prometheus

# Docker daemon metrics endpoint
# /etc/docker/daemon.json:
# { "metrics-addr": "0.0.0.0:9323" }

# Scrape config
# - job_name: 'docker-swarm'
#   static_configs:
#     - targets: ['node1:9323', 'node2:9323', 'node3:9323']
```

### How – Useful Swarm Commands

```bash
# Xem cluster tổng quan
docker info | grep -A 20 "Swarm:"

# Xem tất cả services và replicas
docker service ls

# Xem tasks chi tiết
docker service ps --no-trunc myapp

# Filter tasks by state
docker service ps --filter "desired-state=running" myapp
docker service ps --filter "desired-state=shutdown" myapp

# Scale nhiều services cùng lúc
docker service scale app=5 worker=3 scheduler=1

# Force rebalance (redistribute tasks evenly)
docker service update --force myapp

# Kiểm tra network connectivity giữa nodes
docker run --rm --network ingress alpine ping -c 3 <container-ip>

# Xem secret/config
docker secret ls
docker config ls

# Remove orphaned resources
docker service ls -q | xargs docker service rm  # xóa tất cả services
docker network ls -q --filter "scope=swarm" | xargs docker network rm
```

### Compare – Swarm vs Kubernetes (Chi tiết)

| | Docker Swarm | Kubernetes |
|--|-------------|-----------|
| **Setup** | `docker swarm init` (phút) | kubeadm / managed (giờ) |
| **Mental model** | Services, tasks | Pods, Deployments, StatefulSets |
| **Auto-scaling** | Manual scale | HPA, VPA, KEDA |
| **Storage** | Volume mounts | PV/PVC/StorageClass |
| **Config** | Docker configs | ConfigMaps |
| **Secrets** | Docker secrets | Kubernetes Secrets + ESO |
| **Networking** | Overlay + Ingress | CNI + Ingress/Gateway API |
| **Health** | Container healthcheck | Liveness + Readiness + Startup probes |
| **Rollout** | Rolling update | Deployment strategies (RollingUpdate, Blue/Green, Canary) |
| **RBAC** | None (all managers equal) | Fine-grained RBAC |
| **Multi-tenancy** | Difficult | Namespaces + RBAC + Network Policies |
| **Learning curve** | Thấp (~1 tuần) | Cao (~1-3 tháng) |
| **Ecosystem** | Docker tooling | Massive CNCF ecosystem |
| **Best for** | Small teams, < 20 nodes | Large scale, complex requirements |

### Trade-offs
- Swarm: dễ dùng và đủ tốt cho 80% use cases; không cần K8s cho mọi thứ
- Raft quorum: với 3 nodes, mất 1 node vẫn okay; mất 2 nodes = cluster down
- --update-order start-first: cần đủ resource để chạy N+batch replicas cùng lúc
- Global services: tiện cho DaemonSet-like workloads nhưng không control individual tasks

### Real-world Usage
```bash
# Deployment script cho Swarm production
#!/bin/bash
set -euo pipefail

SERVICE="myapp"
NEW_IMAGE="myrepo/myapp:$1"
TIMEOUT=300

echo "Deploying $NEW_IMAGE..."
docker service update \
  --image "$NEW_IMAGE" \
  --update-parallelism 1 \
  --update-delay 30s \
  --update-order start-first \
  --update-failure-action rollback \
  --update-monitor 60s \
  "$SERVICE"

# Chờ update hoàn thành
timeout $TIMEOUT bash -c "
  while ! docker service inspect $SERVICE | \
    jq -r '.[0].UpdateStatus.State' | grep -q 'completed'; do
    echo 'Waiting for update...'
    sleep 10
  done
"
echo "Deployment complete!"

# Kiểm tra version mới
docker service ps $SERVICE --filter 'desired-state=running' \
  --format '{{.Image}}'
```

### Ghi chú – Chủ đề tiếp theo
> Kubernetes Introduction – Pods/Deployments/Services so sánh với Docker concepts, K8s architecture

---

*Cập nhật lần cuối: 2026-05-06*
