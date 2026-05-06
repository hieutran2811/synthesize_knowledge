# Scalability – Khả năng mở rộng hệ thống

## What – Scalability là gì?

**Scalability** là khả năng của hệ thống xử lý **lượng tải tăng dần** bằng cách thêm tài nguyên, mà không ảnh hưởng đến hiệu năng hoặc yêu cầu viết lại kiến trúc.

Scalability ≠ Performance. Performance là tốc độ xử lý ở tải hiện tại. Scalability là khả năng **duy trì hiệu năng** khi tải tăng.

---

## How – Các chiến lược Scaling

### 1. Vertical Scaling (Scale Up)

Tăng tài nguyên của **một máy** (CPU, RAM, SSD).

```
Before:              After:
┌─────────┐         ┌─────────────┐
│ 4 CPU   │  ──→   │ 32 CPU      │
│ 16 GB   │         │ 128 GB RAM  │
│ 500 GB  │         │ 4 TB NVMe   │
└─────────┘         └─────────────┘
```

**Ưu điểm:**
- Đơn giản – không cần thay đổi app code
- Không có vấn đề distributed (no network latency, no consistency)
- Phù hợp DB, legacy app

**Nhược điểm:**
- Hard limit – không thể thêm mãi
- SPOF (Single Point of Failure)
- Downtime khi nâng cấp hardware
- Chi phí tăng phi tuyến (x2 CPU ≠ x2 performance)

**Khi nào dùng:** Database primary node, legacy monolith, early-stage startup (< 10K users)

---

### 2. Horizontal Scaling (Scale Out)

Thêm nhiều máy chạy **cùng một service**.

```
                    ┌─────────┐
                 ┌─→│ App 1   │
Client → LB ────┤   └─────────┘
                 ├─→│ App 2   │
                 │  └─────────┘
                 └─→│ App 3   │
                    └─────────┘
```

**Ưu điểm:**
- Không có hard limit lý thuyết
- Fault tolerant – một node chết, còn lại vẫn chạy
- Giảm chi phí – dùng commodity hardware

**Nhược điểm:**
- App phải **stateless** (không lưu state trên server)
- Cần Load Balancer, Service Discovery
- Distributed systems complexity (CAP theorem, consistency)
- Session management phức tạp hơn

**Khi nào dùng:** Stateless API servers, microservices, read replicas

---

### 3. Stateless vs Stateful Design

**Stateful (Không scale được):**
```
User A → Server 1 (có session của A)
User A → Server 2 (KHÔNG có session → 401 Unauthorized)
```

**Stateless (Scale được):**
```
User A → Server 1 → validate JWT → OK
User A → Server 2 → validate JWT → OK
         ↑ mỗi request tự chứa đủ thông tin
```

**Kỹ thuật làm stateless:**
| State | Giải pháp |
|-------|-----------|
| HTTP Session | JWT token / Redis session store |
| In-memory cache | Redis / Memcached (external) |
| File uploads | Object Storage (S3, MinIO) |
| WebSocket connections | Sticky sessions tạm thời + pub/sub |

---

### 4. Auto-scaling

Tự động thêm/bớt instance dựa trên metrics.

```
CPU > 70% trong 3 phút → scale out (+2 instances)
CPU < 30% trong 10 phút → scale in (-1 instance)
```

**Các loại auto-scaling:**

| Loại | Trigger | Dùng khi |
|------|---------|----------|
| Reactive (horizontal) | CPU, memory, custom metrics | Workload unpredictable |
| Scheduled | Cron schedule | Biết trước peak (Black Friday) |
| Predictive | ML model dự báo | Có lịch sử traffic đủ lớn |
| KEDA (event-driven) | Queue depth, Kafka lag | Consumer-based workloads |

**Kubernetes HPA example:**
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        averageUtilization: 70
  - type: External
    external:
      metric:
        name: kafka_consumer_lag
      target:
        value: "1000"
```

---

## Components – Các thành phần hỗ trợ Scaling

### Load Balancer
Phân phối traffic đến nhiều instance. (Chi tiết xem `load_balancing.md`)

### CDN (Content Delivery Network)
Cache static assets gần user, giảm tải origin server.

```
User (Vietnam) → CDN Edge (Singapore) → Cache hit → serve
                                      → Cache miss → Origin (US)
```

### Database Read Replicas
Scale đọc riêng bằng cách thêm replica.

```
Write → Primary (1 node)
Read  → Replica 1, 2, 3 (nhiều node)

Tỷ lệ read:write thường = 7:3 đến 9:1
```

### Message Queue (Async scaling)
Tách producer và consumer, buffer traffic spike.

```
API (fast) → Queue → Consumer (slow)
              ↑
         Absorb traffic spike
```

---

## Scalability Patterns

### 1. Data Partitioning (Sharding)
Chia data thành nhiều shard, mỗi shard trên một DB node.

```
User ID % 4:
  0-24%   → Shard 0 (DB-0)
  25-49%  → Shard 1 (DB-1)
  50-74%  → Shard 2 (DB-2)
  75-100% → Shard 3 (DB-3)
```

### 2. CQRS (Command Query Responsibility Segregation)
Tách read model và write model để scale độc lập.

### 3. Event-Driven / Async Processing
Không block request, trả về ngay và xử lý background.

### 4. Cell-Based Architecture (SaaS)
Chia hệ thống thành nhiều "cell" độc lập, mỗi cell phục vụ subset of tenants.

```
Cell A: Tenant 1-1000   → DB-A, Cache-A, App-A
Cell B: Tenant 1001-2000 → DB-B, Cache-B, App-B
```
Lợi ích: blast radius giới hạn – cell A sập không ảnh hưởng Cell B.

---

## Trade-offs

| Vertical Scaling | Horizontal Scaling |
|------------------|--------------------|
| Simple | Complex |
| Hard limit | Theoretically unlimited |
| SPOF | Fault tolerant |
| Expensive at scale | Cost-efficient |
| No code change | Stateless required |

### The Scale Cube (3D Scaling Model)
```
Z-axis: Cloning by customer (cell-based)
│
│   Y-axis: Decompose by function (microservices)
│  /
│ /
└──────── X-axis: Horizontal duplication (cloning)
```

---

## Real-world Usage (Production)

### Netflix
- **Chaos Engineering** (Chaos Monkey) để test resilience
- Cell-based architecture: chia region thành nhiều cell
- EVCache (Memcached) cho distributed caching

### Shopify
- Horizontal scaling với **shop sharding** – mỗi merchant có dedicated DB shard
- Kubernetes + HPA cho stateless services

### Discord
- Chuyển từ Elixir sang Rust cho Read State service: 1 node xử lý 5M concurrent users
- **Stateless + Redis** cho presence state

### Amazon
- **Service-Oriented Architecture** từ 2002 – mọi team expose service
- Separate scaling cho read (DynamoDB) và write (SQS + Lambda)

---

## Numbers để nhớ

| Scale | Typical Architecture |
|-------|---------------------|
| 0-1K users | Single server, no LB |
| 1K-100K users | LB + 2-5 app servers + DB replica |
| 100K-1M users | CDN + Cache + Read replicas + DB sharding |
| 1M-100M users | Microservices + Kafka + Multiple data centers |
| 100M+ users | Cell-based + Global distribution + Custom infra |

---

## Ghi chú

**Sub-topic tiếp theo cần deep dive:**
- `availability_reliability.md` – CAP theorem, PACELC, SLA/SLO/SLI, Circuit Breaker pattern
- `load_balancing.md` – LB algorithms (Round Robin, Least Connections, Consistent Hashing)
- `databases_design.md` – Sharding strategies, Replication lag, Connection pooling
- **Keywords:** Consistent Hashing, Sticky sessions, Blue-Green deployment, Canary release, Cell-based architecture
