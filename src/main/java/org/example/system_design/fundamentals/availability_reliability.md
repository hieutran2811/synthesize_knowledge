# Availability & Reliability – Tính sẵn sàng và Độ tin cậy

## What – Định nghĩa

- **Availability**: % thời gian hệ thống **đang hoạt động** và phục vụ được request. `Uptime / (Uptime + Downtime)`
- **Reliability**: Xác suất hệ thống **hoạt động đúng** trong khoảng thời gian nhất định.
- **Durability**: Khả năng **không mất dữ liệu** (thường dùng cho storage).
- **Fault Tolerance**: Hệ thống vẫn hoạt động khi có **component bị lỗi**.

---

## SLA, SLO, SLI – Tam giác cam kết

### SLI (Service Level Indicator)
Metric đo thực tế: `success_rate = successful_requests / total_requests`

### SLO (Service Level Objective)
Mục tiêu nội bộ: "API success rate ≥ 99.9%"

### SLA (Service Level Agreement)
Cam kết với khách hàng (có penalty nếu vi phạm): "Uptime ≥ 99.9%, nếu không refund 30%"

```
SLO ≥ SLA (luôn set SLO nghiêm ngặt hơn SLA)
SLO = 99.95%, SLA = 99.9% → buffer 0.05% error budget
```

### Bảng Availability (The Nines)

| Availability | Downtime/Year | Downtime/Month | Downtime/Day |
|-------------|--------------|----------------|--------------|
| 99% (2 nines) | 3.65 ngày | 7.2 giờ | 14.4 phút |
| 99.9% (3 nines) | 8.7 giờ | 43.8 phút | 1.44 phút |
| 99.99% (4 nines) | 52.6 phút | 4.38 phút | 8.64 giây |
| 99.999% (5 nines) | 5.26 phút | 26.3 giây | 0.86 giây |

**Thực tế:** Đạt 99.999% cực kỳ tốn kém. Hầu hết SaaS nhắm 99.9-99.99%.

---

## CAP Theorem

Trong **Distributed System**, chỉ có thể đảm bảo **2 trong 3**:

```
         Consistency
            /\
           /  \
          /    \
         /  CA  \
        /────────\
       /    |    \
  CP  /     |     \ AP
     /   (no P)    \
    /________________\
Partition            Availability
Tolerance
```

| Combination | Mô tả | Ví dụ |
|-------------|-------|-------|
| **CP** | Consistent + Partition Tolerant; sacrifice Availability | HBase, Zookeeper, etcd |
| **AP** | Available + Partition Tolerant; sacrifice Consistency | Cassandra, CouchDB, DynamoDB (by default) |
| **CA** | Consistent + Available; không chịu được Partition | Truyền thống RDBMS (single node) |

**Thực tế:** Network partition **luôn xảy ra**. Phải chọn CP hoặc AP. CA chỉ tồn tại trong single-node.

### Consistency Levels (từ strong đến weak)

```
Strong Consistency ──────────────────→ Eventual Consistency
      │                                        │
  Read luôn thấy      Read có thể thấy    Sẽ hội tụ
  write mới nhất      stale data          cuối cùng
      │                    │                   │
   Zookeeper          Read-your-writes      Cassandra
   etcd               Monotonic Read        DynamoDB
```

---

## PACELC Theorem (Extension của CAP)

CAP chỉ xét khi có Partition. PACELC xét **cả khi không có**:

```
IF Partition: choose A or C
ELSE: choose Latency or Consistency
```

| System | Partition | No Partition | Classification |
|--------|-----------|-------------|----------------|
| DynamoDB | A | L | PA/EL |
| Cassandra | A | L | PA/EL |
| MySQL (async replica) | A | L | PA/EL |
| HBase | C | C | PC/EC |
| Spanner | C | C | PC/EC |

**Ý nghĩa:** Ngay cả khi mạng ổn định, nếu muốn Consistency → phải trả giá bằng Latency (vì phải đồng bộ các replica trước khi trả lời).

---

## Failure Modes & Resilience Patterns

### 1. Circuit Breaker Pattern

Ngăn cascade failure khi một dependency bị chậm/lỗi.

```
CLOSED state (normal):
Request → Service B → OK
         Count failures...

OPEN state (after threshold):
Request → Circuit Breaker → Fail Fast (không gọi B)
          (wait timeout)

HALF-OPEN state (probe):
Request → Send 1 request → If OK → CLOSED
                          → If fail → OPEN
```

**Implementation với Resilience4j (Java):**
```java
CircuitBreakerConfig config = CircuitBreakerConfig.custom()
    .failureRateThreshold(50)          // 50% lỗi → OPEN
    .waitDurationInOpenState(30s)       // chờ 30s trước HALF-OPEN
    .permittedNumberOfCallsInHalfOpenState(3)
    .slidingWindowSize(10)             // tính trên 10 requests gần nhất
    .build();

CircuitBreaker cb = CircuitBreakerRegistry.of(config).circuitBreaker("paymentService");

// Wrap call
Supplier<Payment> decorated = CircuitBreaker.decorateSupplier(cb, () -> paymentService.charge(amount));
Try.ofSupplier(decorated).recover(throwable -> fallbackPayment());
```

**States transition:**
```
CLOSED → (failure rate > threshold) → OPEN → (wait) → HALF-OPEN → (success) → CLOSED
                                                                  → (fail) → OPEN
```

### 2. Retry Pattern với Exponential Backoff

```java
// Jitter để tránh thundering herd
long delay = Math.min(
    BASE_DELAY * Math.pow(2, attempt) + random(0, BASE_DELAY),
    MAX_DELAY
);
// attempt=0: 1s, attempt=1: 2s+jitter, attempt=2: 4s+jitter, ...
```

**Khi nào KHÔNG retry:**
- 4xx errors (client error) – retry vô ích
- Non-idempotent operations (POST payment) – cần idempotency key trước

### 3. Bulkhead Pattern

Cách ly resources để lỗi không cascade.

```
Không có Bulkhead:          Có Bulkhead:
┌────────────────┐         ┌────────┐ ┌────────┐
│  Thread Pool   │         │Pool A  │ │Pool B  │
│  (shared 100)  │         │(50)    │ │(50)    │
│ Service A ─────┼→ exhaust│Svc A──►│ │Svc B──►│
│ Service B ─────┼→ starve │OK      │ │OK      │
└────────────────┘         └────────┘ └────────┘
```

### 4. Timeout Pattern

Luôn đặt timeout cho mọi external call:
- Connection timeout: thời gian thiết lập kết nối (2-5s)
- Read timeout: thời gian đợi response (5-30s tùy context)
- Circuit breaker timeout: thời gian OPEN state (30-60s)

### 5. Fallback Pattern

```java
try {
    return recommendationService.getRecommendations(userId);
} catch (Exception e) {
    // Fallback: trả về top products (cached, always available)
    return cacheService.getTopProducts();
}
```

---

## High Availability Patterns

### Active-Passive Failover
```
Primary (active) ──────────────── Standby (passive)
       │                               │
   Serving traffic              Replicating data
       │                               │
   ↓ fails                         promoted
   Health check detects             ↓
   Traffic → Standby              Active
```
**RPO (Recovery Point Objective):** Phụ thuộc replication lag
**RTO (Recovery Time Objective):** 30s-5 phút (thời gian detect + failover)

### Active-Active (Multi-Master)
```
Region A (active) ←──── replication ────→ Region B (active)
      │                                          │
  Traffic A                                Traffic B
```
**Phức tạp hơn:** Conflict resolution, write-write conflicts

### Multi-AZ vs Multi-Region

| | Multi-AZ | Multi-Region |
|--|----------|-------------|
| Latency | < 5ms giữa AZ | 50-200ms giữa region |
| Cost | Thấp hơn | Cao hơn |
| Protection | Datacenter failure | Region failure |
| Consistency | Strong (synchronous) | Eventual (asynchronous) |

---

## Chaos Engineering

**Nguyên tắc:** Chủ động inject failure để test resilience trước khi xảy ra thật.

```
Hypothesis → Blast Radius → Run Experiment → Observe → Improve
    ↑                                                      │
    └──────────────────────────────────────────────────────┘
```

**Ví dụ thực nghiệm:**
```bash
# Kill random pod (Chaos Monkey for Kubernetes)
kubectl delete pod $(kubectl get pods -l app=payment -o name | shuf -n1)

# Simulate network latency
tc qdisc add dev eth0 root netem delay 200ms 50ms distribution normal

# CPU stress
stress --cpu 8 --timeout 60s
```

**Netflix Chaos Monkey** → nền tảng của chaos engineering hiện đại.

---

## Trade-offs

| High Availability | Trade-off |
|-------------------|-----------|
| Multi-AZ/Region | Chi phí x2-x3 |
| Synchronous replication | Tăng write latency |
| Circuit breaker | Complexity, tuning khó |
| Active-Active | Conflict resolution phức tạp |
| Chaos engineering | Cần production readiness trước |

---

## Real-world Production

### AWS RDS Multi-AZ
- Synchronous replication sang standby AZ
- Automatic failover trong 60-120s
- RPO ≈ 0, RTO ≈ 2 phút

### Google Spanner (External Consistency)
- Đạt được CP trong distributed system bằng TrueTime API
- Atomic clock + GPS để sync time với uncertainty < 7ms

### Netflix (Availability)
- 99.99% availability target
- Chaos Engineering với Chaos Monkey, ChAP (Chaos Automation Platform)
- Active-Active trên 3 AWS regions

---

## Ghi chú

**Sub-topic tiếp theo cần deep dive:**
- `load_balancing.md` – Thuật toán LB, health checks, Global Load Balancing
- `caching.md` – Cache patterns và vai trò trong availability (cache fallback)
- **Keywords:** Error budget, Toil, SRE (Site Reliability Engineering), Graceful degradation, Idempotency key, Two-phase commit, Write-ahead log (WAL)
