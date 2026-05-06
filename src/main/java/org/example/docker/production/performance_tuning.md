# Docker Performance Tuning – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. JVM trong Containers

### What – Vấn đề JVM với Containers
JVM cũ (trước Java 8u191) không nhận biết container resource limits – đọc CPU/memory từ host thay vì cgroup. Dẫn đến heap quá lớn, GC overhead, OOM kill bởi kernel.

### How – JVM Container Awareness

```bash
# Java 8u191+ / Java 11+: UseContainerSupport (mặc định bật)
# JVM tự detect memory limit từ cgroups

# Kiểm tra JVM thấy bao nhiêu RAM
docker run --rm --memory=512m eclipse-temurin:21 java \
  -XX:+PrintFlagsFinal -version 2>&1 | grep MaxHeapSize
# MaxHeapSize = 134217728 (128MB = 512MB / 4 = 25% của container memory)

# Default heap sizing (UseContainerSupport):
# MaxRAMPercentage mặc định = 25% của container memory
# MinRAMPercentage mặc định = 50% (chỉ dùng khi container < 250MB)

# Kiểm tra số CPUs JVM thấy
docker run --rm --cpus=2 eclipse-temurin:21 java \
  -XX:+PrintFlagsFinal -version 2>&1 | grep ActiveProcessorCount
# ActiveProcessorCount = 2 (đúng với --cpus limit)
```

### How – Tuning JVM Heap

```dockerfile
# KHÔNG hardcode -Xmx (không biết container size tại build time)
# BAD:
CMD ["java", "-Xmx512m", "-jar", "app.jar"]

# GOOD: Dùng percentage
CMD ["java", \
     "-XX:MaxRAMPercentage=75.0", \           # 75% cho heap
     "-XX:InitialRAMPercentage=50.0", \        # initial heap = 50%
     "-XX:MinRAMPercentage=50.0", \
     "-jar", "app.jar"]

# GOOD: Tính từ ENV (flexible)
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0"
CMD java $JAVA_OPTS -jar app.jar
```

```yaml
# compose.yaml: set memory limit và JVM tuning
services:
  app:
    image: myapp:latest
    environment:
      JAVA_OPTS: >-
        -XX:MaxRAMPercentage=75.0
        -XX:InitialRAMPercentage=50.0
        -XX:+UseG1GC
        -XX:MaxGCPauseMillis=200
        -XX:+PrintGCDetails
        -Xlog:gc*:stdout:time,uptime,level,tags
        -XX:+HeapDumpOnOutOfMemoryError
        -XX:HeapDumpPath=/dumps/heap.hprof
    volumes:
      - ./dumps:/dumps
    deploy:
      resources:
        limits:
          memory: 1G                 # Container memory = 1GB
        # → JVM heap ≈ 768MB (75%)
```

### How – GC Tuning cho Containers

```bash
# G1GC (default Java 9+): tốt cho latency
java -XX:+UseG1GC \
     -XX:MaxGCPauseMillis=200 \           # target pause time
     -XX:G1HeapRegionSize=16m \           # region size (heap < 256MB → nhỏ hơn)
     -XX:+G1UseAdaptiveIHOP \             # adaptive IHOP
     -jar app.jar

# ZGC (Java 15+): ultra-low latency (<1ms pause)
java -XX:+UseZGC \
     -XX:+ZGenerational \                 # Java 21: generational ZGC
     -jar app.jar

# Shenandoah (OpenJDK): concurrent compaction
java -XX:+UseShenandoahGC -jar app.jar

# Check GC logs
docker logs app 2>&1 | grep -i gc | tail -20
```

### How – JVM Startup Optimization

```bash
# Class Data Sharing (CDS): share class metadata
java -Xshare:dump -jar app.jar        # tạo shared archive
java -Xshare:on -jar app.jar          # dùng shared archive

# Spring Boot: spring-context-indexer
# Thêm vào pom.xml: spring-context-indexer
# Giảm startup time ~50% bằng cách pre-index components

# Virtual Threads (Java 21): không block carrier thread
# → ít threads hơn → ít memory hơn
# Tomcat: server.tomcat.threads.max không cần tăng cao nữa

# GraalVM Native Image: compile thành native binary
# → Startup ms thay vì seconds
# → Memory thấp hơn nhiều
# → Phù hợp serverless / containers
./mvnw -Pnative native:compile
# Docker multi-stage với GraalVM:
FROM ghcr.io/graalvm/native-image:21 AS builder
...
FROM scratch
COPY --from=builder /app/target/myapp /myapp
# Image size: ~20MB thay vì ~200MB JRE
```

---

## 2. CPU Optimization

### How – CPU Limits Thực Tế

```bash
# --cpus: số CPU cores (quota/period)
docker run --cpus=2.5 myapp          # 2.5 CPUs
# → cpu.max = 250000 100000 (250ms per 100ms period)

# --cpu-shares: relative weight (ưu tiên khi tranh chấp)
docker run --cpu-shares=512 app1     # weight 512 (mặc định 1024)
docker run --cpu-shares=1024 app2    # weight 1024 → gấp đôi
# → Khi cả 2 chạy: app2 nhận 2/3 CPU, app1 nhận 1/3

# --cpuset-cpus: pin đến CPU cụ thể
docker run --cpuset-cpus="0,1" app   # chỉ dùng CPU 0 và 1
docker run --cpuset-cpus="2-5" app   # CPU 2, 3, 4, 5
# → Giảm cache miss, tránh NUMA latency

# Kiểm tra CPU throttling
CONTAINER_ID=$(docker inspect --format '{{.Id}}' myapp)
cat /sys/fs/cgroup/system.slice/docker-${CONTAINER_ID}.scope/cpu.stat
# nr_throttled: X        ← số lần bị throttle
# throttled_usec: Y      ← tổng thời gian bị throttle

# Nếu nr_throttled cao → tăng --cpus hoặc tối ưu code
```

### How – CPU Pinning cho Database Containers

```bash
# PostgreSQL: pin đến NUMA node cùng với storage
# Xem NUMA topology
numactl --hardware
# available: 2 nodes (0-1)
# node 0 cpus: 0 1 2 3 4 5 6 7
# node 1 cpus: 8 9 10 11 12 13 14 15

# Pin PostgreSQL đến node 0 (gần storage)
docker run --cpuset-cpus="0-7" --cpuset-mems="0" postgres:16

# Grafana/Prometheus: node 1 (I/O intensive, xa storage)
docker run --cpuset-cpus="8-15" --cpuset-mems="1" grafana/grafana
```

---

## 3. Memory Optimization

### How – Memory Limits Best Practices

```bash
# Rule of thumb: limit = 2x expected usage

# Kiểm tra memory usage thực tế
docker stats --no-stream myapp | awk '{print $4, $5}'
# 250MiB / 512MiB

# Xem memory breakdown chi tiết
docker exec myapp cat /proc/meminfo
# hoặc trong container:
# free -h

# Set limit = 1.5-2x peak usage trong load test
docker run --memory=512m myapp

# memory-reservation (soft limit): khuyến nghị cho Swarm/K8s scheduling
docker run \
  --memory=1g \                      # hard limit
  --memory-reservation=512m \        # soft limit (khi host cần memory)
  myapp

# Swap: tắt trong production (swap làm chậm đáng kể)
docker run --memory=512m --memory-swap=512m myapp
# memory-swap = memory → no swap (swap = 0)
# memory-swap = -1 → unlimited swap (không recommend)
```

### How – OOM Killer Tuning

```bash
# Khi container bị OOM killed
docker inspect myapp | jq '.[0].State.OOMKilled'  # true

dmesg | grep -i "out of memory"
# kernel: Out of memory: Kill process 12345 (java) score 900 or sacrifice child

# /proc/<pid>/oom_score: 0-1000 (cao hơn = bị kill trước)
# /proc/<pid>/oom_score_adj: -1000 đến 1000 (điều chỉnh score)

# Tránh OOM kill container quan trọng (làm khó bị kill hơn)
docker exec myapp sh -c "echo -500 > /proc/1/oom_score_adj"
# −500: giảm oom_score → bị kill sau các process khác

# PID 1 trong container = process chính
# Docker tự set oom_score_adj = 0 cho container init
```

### How – Memory-efficient Base Images

```dockerfile
# Đo memory usage khi start
docker stats --no-stream myapp

# Alpine vs Debian: Alpine dùng musl → nhỏ hơn, ít overhead
FROM node:20-alpine          # ~50MB base
FROM node:20-debian-slim     # ~100MB base
FROM node:20                 # ~300MB base

# Java: JRE thay JDK
FROM eclipse-temurin:21-jre-alpine   # ~200MB
FROM eclipse-temurin:21-jdk-alpine   # ~400MB

# Chỉ copy deps cần thiết
FROM eclipse-temurin:21 AS jlink-stage
RUN jlink \
  --no-header-files \
  --no-man-pages \
  --compress=2 \
  --add-modules java.base,java.logging,java.sql \
  --output /jre-custom

FROM debian:slim
COPY --from=jlink-stage /jre-custom /opt/jre
# Custom JRE: ~30MB thay vì 200MB!
```

---

## 4. Disk I/O Optimization

### How – Storage Driver Performance

```bash
# Kiểm tra storage driver
docker info | grep "Storage Driver"
# Storage Driver: overlay2

# OverlayFS: best cho hầu hết workloads
# Tránh devicemapper (legacy), btrfs (complex)

# Volumes cho I/O intensive workloads (thay vì container filesystem)
# Container filesystem (OverlayFS) = copy-on-write overhead
# Named volume = direct filesystem, không CoW

# Database LUÔN dùng volume
docker run -v pgdata:/var/lib/postgresql/data postgres:16

# I/O limits
docker run \
  --device-read-bps /dev/sda:50mb \    # max 50MB/s đọc
  --device-write-bps /dev/sda:30mb \   # max 30MB/s ghi
  --device-read-iops /dev/sda:1000 \   # max 1000 IOPS đọc
  --device-write-iops /dev/sda:500 \   # max 500 IOPS ghi
  postgres:16
```

### How – tmpfs cho Temp Data

```bash
# tmpfs: RAM filesystem, nhanh hơn disk nhiều lần
docker run \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m \
  --tmpfs /app/cache:rw,size=512m \
  myapp

# Use cases:
# - Session data (PHP sessions)
# - Compiled templates (Jinja2 cache)
# - JVM temp files (/tmp)
# - Test databases (PostgreSQL trên tmpfs)
docker run \
  --tmpfs /var/lib/postgresql/data:size=1g \
  postgres:16
# → In-memory DB: 10x faster than disk, dùng cho test only
```

---

## 5. Network Performance

### How – Network Performance Tuning

```bash
# host network: tốt nhất cho network-intensive apps
docker run --network host myapp      # không có NAT overhead

# Tăng buffer sizes
# /etc/docker/daemon.json:
{
  "mtu": 9000                        # jumbo frames (nếu network hỗ trợ)
}

# Kernel tuning cho high-connection workloads
sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535
sysctl -w net.core.netdev_max_backlog=65535
sysctl -w net.ipv4.tcp_tw_reuse=1
echo "net.core.somaxconn=65535" >> /etc/sysctl.conf

# Trong container (nếu có CAP_NET_ADMIN):
docker exec --privileged myapp sysctl -w net.core.somaxconn=65535

# Ulimits
docker run \
  --ulimit nofile=65536:65536 \      # open file descriptors
  --ulimit nproc=65536:65536 \       # processes
  nginx

# /etc/docker/daemon.json global ulimits
{
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65536,
      "Soft": 65536
    }
  }
}
```

---

## 6. Profiling & Benchmarking

### How – Benchmark Container Performance

```bash
# sysbench: CPU benchmark
docker run --rm --cpus=2 severalnines/sysbench \
  sysbench cpu --cpu-max-prime=20000 run

# stress-ng: tổng hợp
docker run --rm containerstack/stress \
  stress-ng --cpu 2 --io 1 --vm 1 --vm-bytes 256M --timeout 60s

# fio: disk I/O benchmark
docker run --rm -v /tmp/test:/tmp/test \
  ljishen/fio \
  --name=randread --rw=randread --bs=4k --iodepth=32 \
  --numjobs=4 --runtime=30 --filename=/tmp/test/testfile

# Network benchmark (iperf3)
# Server:
docker run -d --name iperf-server --network mynet networkstatic/iperf3 -s
# Client:
docker run --rm --network mynet networkstatic/iperf3 -c iperf-server -t 30
```

### How – Application Profiling trong Container

```bash
# Java: async-profiler (low overhead, production safe)
docker exec myapp sh -c "
  curl -o /tmp/profiler.jar https://github.com/jvm-profiling-tools/async-profiler/releases/download/v3.0/async-profiler-3.0-linux-x64.tar.gz
  java -agentpath:/tmp/libasyncProfiler.so=start,event=cpu,file=/tmp/cpu.jfr -jar app.jar
"

# Node.js: --inspect profiling
docker run --cap-add SYS_PTRACE \
  -e NODE_ENV=production \
  myapp node --prof app.js

# Python: py-spy
docker exec myapp pip install py-spy
docker exec myapp py-spy top --pid 1

# Perf (kernel-level)
docker run --rm \
  --cap-add SYS_ADMIN \
  --cap-add SYS_PTRACE \
  --pid host \
  debian:latest \
  perf top -p $(docker inspect --format '{{.State.Pid}}' myapp)
```

### Compare – Resource Limit Strategies

| Strategy | Khi dùng | Ưu điểm | Nhược điểm |
|---------|---------|---------|-----------|
| Hard limits only | Simple apps | Simple | OOM kill nếu spike |
| Hard + Reservation | Scheduled workloads | Predictable scheduling | Complex |
| QoS classes (K8s) | Kubernetes | Fine-grained | K8s only |
| No limits | Dev/test | Flexible | Resource starvation |

### Trade-offs
- Quá ít memory limit: OOM kill → downtime
- Quá nhiều memory limit: lãng phí tài nguyên → tốn tiền (Cloud)
- JVM MaxRAMPercentage quá cao: không đủ memory cho metaspace, off-heap, OS → OOM
- cpu-shares: chỉ hiệu quả khi CPU bị tranh chấp; idle host không ảnh hưởng

### Real-world Usage
```bash
# Load test + monitor để xác định limits đúng
# 1. Chạy load test
docker run --rm -it --network mynet \
  grafana/k6 run - <<'EOF'
import http from 'k6/http';
export const options = { vus: 100, duration: '5m' };
export default () => { http.get('http://app:3000/api/data'); };
EOF

# 2. Monitor trong khi load test
docker stats myapp --no-stream | \
  awk 'NR>1 {print strftime("%H:%M:%S"), $4, $5}'

# 3. Set limits = 120% của peak usage
# peak 850MiB → set --memory=1024m

# Kubernetes resource requests/limits từ data thực
# requests = avg usage (guaranteed)
# limits = peak + 20% buffer
```

### Ghi chú – Chủ đề tiếp theo
> Docker Swarm Advanced – HA managers, rolling updates, config rotation, placement constraints

---

*Cập nhật lần cuối: 2026-05-06*
