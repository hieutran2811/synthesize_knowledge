# System Design – Tổng hợp Kiến thức

## What – System Design là gì?

**System Design** là quá trình định nghĩa kiến trúc, thành phần, module, giao diện và dữ liệu của một hệ thống để thỏa mãn các yêu cầu đặc thù. Đây là cầu nối giữa yêu cầu nghiệp vụ và triển khai kỹ thuật.

Không giống coding (viết code đúng), System Design giải quyết **"Xây cái gì, như thế nào, cho bao nhiêu người dùng, với trade-off nào"**.

---

## Tại sao System Design quan trọng?

| Không có System Design | Có System Design |
|------------------------|-----------------|
| App chạy được 1000 user, sập ở 10,000 | Scale được theo nhu cầu |
| Data mất khi server crash | Dữ liệu bền vững, HA |
| Response time tăng theo data | Latency ổn định |
| Feature mới phá vỡ cái cũ | Modularity, loose coupling |
| Chi phí không kiểm soát được | Cost-efficient architecture |

---

## Các chiều đánh giá hệ thống (SCALABILITY Pillars)

```
┌─────────────────────────────────────────────────────┐
│                   System Quality                     │
│                                                     │
│  Scalability ──── Availability ──── Performance     │
│       │                │                 │           │
│  Reliability ──── Maintainability ── Security       │
│       │                │                 │           │
│  Cost-efficiency ── Observability ── Consistency    │
└─────────────────────────────────────────────────────┘
```

---

## Roadmap học System Design

### Cơ bản (Fundamentals)
1. **Scalability** – Vertical vs Horizontal, Stateless design
2. **Availability & Reliability** – CAP, PACELC, SLA/SLO/SLI
3. **Load Balancing** – Algorithms, L4/L7, Global LB
4. **Caching** – Strategies, CDN, Invalidation patterns
5. **Database Design** – SQL/NoSQL, Sharding, Replication

### Nâng cao (Advanced)
6. **Microservices** – Decomposition, Service Mesh, API Gateway
7. **Event-Driven Architecture** – Event Sourcing, CQRS
8. **Distributed Transactions** – SAGA, Outbox Pattern
9. **API Design** – REST, GraphQL, gRPC

### Thực chiến SaaS
10. **Multi-tenancy** – Isolation models, Data segregation
11. **Billing & Metering** – Usage-based billing pipeline
12. **Rate Limiting** – Token bucket, Redis implementation
13. **Feature Flags** – Toggles, A/B testing, Canary
14. **SaaS Observability** – Multi-tenant metrics, cost attribution

---

## Framework phân tích bài toán System Design

### RESHADED Framework
```
R – Requirements (Functional + Non-functional)
E – Estimation (Traffic, Storage, Bandwidth)
S – Storage Schema (Data model)
H – High-level Design
A – APIs
D – Data Flow
E – Evaluate (Bottlenecks, Trade-offs)
D – Deep Dive (Critical components)
```

### Ví dụ: Design URL Shortener
```
Requirements:
  - Functional: shorten URL, redirect, analytics
  - Non-functional: 100M URLs/day, latency < 100ms, HA 99.99%

Estimation:
  - Write: 100M/day = ~1160 QPS
  - Read: 100:1 ratio = 116,000 QPS
  - Storage: 100M × 500 bytes = 50GB/day

High-level:
  Client → CDN → API Gateway → App Servers → Cache → DB
                                                ↓
                                          Analytics Service
```

---

## Các số "back of envelope" cần nhớ

| Resource | Latency/Throughput |
|----------|--------------------|
| L1 cache hit | 0.5ns |
| L2 cache hit | 7ns |
| RAM read | 100ns |
| SSD random read | 100μs |
| HDD random read | 10ms |
| Network same region | 0.5ms |
| Network cross region | 30–150ms |
| MySQL throughput | ~3,000 TPS (simple queries) |
| Redis throughput | ~100,000 QPS |
| Kafka throughput | ~1,000,000 msg/s |

---

## Ghi chú

**Các sub-topic cần deep dive tiếp theo:**
- `fundamentals/scalability.md` – Vertical vs Horizontal scaling, Auto-scaling, Stateless design
- `fundamentals/availability_reliability.md` – CAP theorem, PACELC, SLA/SLO/SLI, Circuit Breaker
- `fundamentals/load_balancing.md` – Algorithms, L4/L7, Global Load Balancing, Health checks
- `fundamentals/caching.md` – Cache-aside/write-through/write-behind, CDN, Redis, invalidation
- `fundamentals/databases_design.md` – SQL vs NoSQL, Sharding, Replication, Connection pooling
- `advanced/microservices.md` – Decomposition, Service Mesh (Istio), API Gateway patterns
- `advanced/event_driven_architecture.md` – Event Sourcing, CQRS, Choreography vs Orchestration
- `advanced/distributed_transactions.md` – 2PC, SAGA, Outbox Pattern, Idempotency
- `advanced/api_design.md` – REST best practices, GraphQL, gRPC, API versioning
- `saas/multi_tenancy.md` – Silo vs Pool vs Bridge, row-level security, tenant routing
- `saas/billing_metering.md` – Usage metering pipeline, Stripe integration, revenue recognition
- `saas/rate_limiting.md` – Token bucket, Leaky bucket, Sliding window, Redis implementation
- `saas/feature_flags.md` – Feature toggles, LaunchDarkly, A/B testing, Canary releases
- `saas/observability_saas.md` – Multi-tenant metrics, tenant cost attribution, alerting
