# Roadmap – System Design

> 📖 Tra cứu nhanh: [System Design Glossary](glossary.md) · Tổng quan: [system_design_knowledge.md](system_design_knowledge.md)
>
> **Trạng thái chuẩn hóa (2026-07-31)**: đã hoàn thành 20/21 chủ đề — `fundamentals/` (9/9), `advanced/` (4/4), `case_studies/` (3/3) và `saas/` (4/5). `observability_saas.md` được giữ lại để tôn trọng ưu tiên tạm giảm các chủ đề gần Prometheus/Grafana.

## Cấu trúc thư mục

```text
system_design/
├── roadmap.md                                    ← file này
├── glossary.md                                   ← thuật ngữ A–Z + bảng số liệu tham chiếu
├── system_design_knowledge.md                    ← tổng quan, learning path, bảng tra sự cố
├── fundamentals/
│   ├── interview_framework_estimation.md         ← RESHADED, back-of-envelope, p99, tail amplification
│   ├── scalability.md                            ← Amdahl/USL, vertical vs horizontal, stateless, auto-scaling, cell
│   ├── availability_reliability.md               ← SLI/SLO/error budget, CAP/PACELC, resilience pattern, chaos
│   ├── load_balancing.md                         ← L4/L7, thuật toán, P2C, health check, draining, GLB
│   ├── caching.md                                ← 5 pattern, 3 chế độ hỏng, invalidation, hot key, CDN, multi-tier
│   ├── databases_design.md                       ← SQL/NoSQL, replication, sharding, index, pool, OLTP/OLAP, migration
│   ├── storage_retrieval.md                      ← WAL, B-tree vs LSM, columnar, encoding, schema evolution
│   ├── distributed_systems_theory.md             ← consistency model, consensus, quorum, clock, CRDT, lock
│   └── networking_protocols.md                   ← TCP/UDP, HTTP/1-2-3, TLS, SSE vs WS, DNS, CDN, proxy
├── advanced/
│   ├── microservices.md                          ← boundary, data ownership, resilience, migration
│   ├── event_driven_architecture.md              ← delivery, ordering, idempotency, Outbox, replay
│   ├── distributed_transactions.md               ← invariant, 2PC, Saga, TCC, recovery, reconciliation
│   └── api_design.md                             ← HTTP semantics, compatibility, gRPC, GraphQL, security
├── saas/
│   ├── multi_tenancy.md                          ← isolation, tenant context, RLS, stamps, lifecycle
│   ├── billing_metering.md                       ← usage ledger, rating, invoice, payment, reconciliation
│   ├── rate_limiting.md                          ← algorithms, local/global, cost, fairness, Redis
│   ├── feature_flags.md                          ← rollout, experiment, kill switch, migration, lifecycle
│   └── observability_saas.md                     ← multi-tenant metric, cost attribution, alerting
└── case_studies/
    ├── foundational_designs.md                   ← URL shortener, distributed ID, rate limiter
    ├── realtime_scale_designs.md                 ← news feed, chat, proximity/geo
    └── platform_designs.md                       ← object storage, typeahead, payment/ledger, notification
```

---

## Mục lục

### Fundamentals – nền tảng

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 1 | Interview Framework & Estimation – RESHADED, functional vs non-functional, back-of-envelope, công suất một node, latency numbers, percentile, **tail latency amplification**, hot key, cách nói trade-off | [fundamentals/interview_framework_estimation.md](fundamentals/interview_framework_estimation.md) | ✅ Chuẩn hóa | Cơ bản |
| 2 | Scalability – Amdahl & **USL**, vertical vs horizontal, stateless (JWT vs session store), auto-scaling + 4 cái bẫy, scale cube, **cell-based**, bottleneck theo tầng | [fundamentals/scalability.md](fundamentals/scalability.md) | ✅ Chuẩn hóa | Cơ bản |
| 3 | Availability & Reliability – SLI/SLO/SLA, **error budget**, phép nhân availability, CAP/PACELC, **failure mode** (gray failure, node chậm), timeout & deadline propagation, retry budget, circuit breaker, bulkhead, load shedding, split-brain, chaos | [fundamentals/availability_reliability.md](fundamentals/availability_reliability.md) | ✅ Chuẩn hóa | Trung cấp |
| 4 | Load Balancing – L4/L7 + **cái bẫy gRPC qua L4**, thuật toán (**P2C**), consistent hashing, liveness/readiness/startup, connection draining, canary, global LB, LB là SPOF | [fundamentals/load_balancing.md](fundamentals/load_balancing.md) | ✅ Chuẩn hóa | Trung cấp |
| 5 | Caching – 5 pattern, eviction (LRU vs LFU), **3 chế độ hỏng** (stampede/penetration/avalanche), invalidation & versioned key, hot key, CDN (`stale-if-error`), cache nhiều tầng | [fundamentals/caching.md](fundamentals/caching.md) | ✅ Chuẩn hóa | Trung cấp |
| 6 | Databases Design – chọn theo access pattern, replication & 3 vấn đề lag, **thứ tự loại trừ trước khi shard**, shard key, index (ESR), connection pool, OLTP vs OLAP, **migration expand–contract** | [fundamentals/databases_design.md](fundamentals/databases_design.md) | ✅ Chuẩn hóa | Trung cấp |
| 7 | Storage & Retrieval – WAL & durability, **B-tree vs LSM**, 3 amplification, compaction, row vs columnar, encoding (Avro/Protobuf/Parquet), **schema evolution** | [fundamentals/storage_retrieval.md](fundamentals/storage_retrieval.md) | ✅ **Mới 2026-07** | Nâng cao |
| 8 | Distributed Systems Theory – 8 fallacies, FLP & Two Generals, consistency model + **client-centric guarantee**, Raft/Paxos/ZAB, quorum R+W>N, xung đột & CRDT, clock, **fencing token**, gossip | [fundamentals/distributed_systems_theory.md](fundamentals/distributed_systems_theory.md) | ✅ Chuẩn hóa | Nâng cao |
| 9 | Networking & Protocols – TCP/UDP + chi phí handshake, HTTP/1-2-3, TLS, **SSE vs WebSocket**, DNS (+ bẫy JVM DNS cache), CDN, proxy/gateway, chọn kiểu giao tiếp | [fundamentals/networking_protocols.md](fundamentals/networking_protocols.md) | ✅ Chuẩn hóa | Trung cấp |

### Advanced – nâng cao

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 10 | Microservices – modular monolith trước, DDD/bounded context, data ownership, sync vs async, gateway/BFF, discovery/mesh, resilience, contract, Strangler migration | [advanced/microservices.md](advanced/microservices.md) | ✅ Chuẩn hóa | Nâng cao |
| 11 | Event-Driven Architecture – event vs command, delivery/ordering, idempotency, retry/DLQ, Outbox/Inbox, Saga, CQRS, event sourcing, replay và schema evolution | [advanced/event_driven_architecture.md](advanced/event_driven_architecture.md) | ✅ Chuẩn hóa | Nâng cao |
| 12 | Distributed Transactions – invariant, unknown outcome, 2PC, Saga/isolation, state machine, idempotency, Outbox/Inbox, TCC, reservation và reconciliation | [advanced/distributed_transactions.md](advanced/distributed_transactions.md) | ✅ Chuẩn hóa | Nâng cao |
| 13 | API Design – consumer journey, HTTP semantics, Problem Details, idempotency/ETag, pagination, async/webhook, compatibility, gRPC, GraphQL và API security | [advanced/api_design.md](advanced/api_design.md) | ✅ Chuẩn hóa | Trung cấp |

### SaaS – thực chiến

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 14 | Multi-tenancy – tenant identity, isolation theo tầng, silo/pool/bridge, stamps, tenant context, RLS, cache/search/event scope, noisy neighbor và lifecycle | [saas/multi_tenancy.md](saas/multi_tenancy.md) | ✅ Chuẩn hóa | Nâng cao |
| 15 | Billing & Metering – billable metric, immutable usage ledger, rating/catalog version, invoice/payment lifecycle, Stripe adapter, correction và reconciliation | [saas/billing_metering.md](saas/billing_metering.md) | ✅ Chuẩn hóa | Nâng cao |
| 16 | Rate Limiting – fixed/sliding/token/GCRA, weighted cost, concurrency, hierarchical local/global limit, Redis atomicity, failure mode và fairness | [saas/rate_limiting.md](saas/rate_limiting.md) | ✅ Chuẩn hóa | Trung cấp |
| 17 | Feature Flags – flag category, control/evaluation plane, trusted context, deterministic rollout, kill switch, experiment, data migration, OpenFeature và lifecycle debt | [saas/feature_flags.md](saas/feature_flags.md) | ✅ Chuẩn hóa | Trung cấp |
| 18 | SaaS Observability – multi-tenant metric, cost attribution, alerting | [saas/observability_saas.md](saas/observability_saas.md) | 🟡 Chờ chuẩn hóa | Nâng cao |

### Case studies – áp dụng

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 19 | Foundational – **URL shortener** (Zipf, 301 vs 302, song ánh base62), **distributed ID** (Snowflake + 4 vấn đề thật), **rate limiter** (Lua atomic, local bucket, fail-open/closed) | [case_studies/foundational_designs.md](case_studies/foundational_designs.md) | ✅ Chuẩn hóa | Trung cấp |
| 20 | Real-time & Scale – **news feed** (fan-out hybrid, celebrity), **chat** (seq vs timestamp, session registry, presence), **proximity/geo** (geohash + ô lân cận, static vs dynamic) | [case_studies/realtime_scale_designs.md](case_studies/realtime_scale_designs.md) | ✅ Chuẩn hóa | Nâng cao |
| 21 | Platform – **object storage** (erasure coding, failure domain, scrubbing), **typeahead** (precompute, filter-then-rank), **payment/ledger** (idempotency key, double-entry, đối soát), **notification** (3 tầng dedup, tách campaign/transactional) | [case_studies/platform_designs.md](case_studies/platform_designs.md) | ✅ **Mới 2026-07** | Nâng cao |

---

## Learning path

```text
Bước 0 – Phương pháp
  interview_framework_estimation   (học cách đặt câu hỏi và ước lượng trước khi học công cụ)

Bước 1 – Nền tảng mở rộng
  scalability → load_balancing → caching → databases_design

Bước 2 – Nền tảng độ tin cậy
  availability_reliability → distributed_systems_theory

Bước 3 – Nền tảng chiều sâu
  storage_retrieval → networking_protocols

Bước 4 – Kiến trúc
  api_design → microservices → event_driven_architecture → distributed_transactions

Bước 5 – Thực chiến SaaS
  multi_tenancy → rate_limiting → feature_flags → billing_metering → observability_saas

Bước 6 – Áp dụng
  foundational_designs → realtime_scale_designs → platform_designs
```

### Lối đi theo mục tiêu

| Mục tiêu | Thứ tự đề xuất |
|---|---|
| **Chuẩn bị phỏng vấn** | interview_framework_estimation → 3 file case_studies → scalability/caching/databases_design → distributed_systems_theory |
| **Java backend developer** | databases_design → caching → networking_protocols → api_design → distributed_transactions |
| **DevOps / SRE** | availability_reliability → load_balancing → scalability → observability_saas → distributed_systems_theory |
| **Xây SaaS multi-tenant** | multi_tenancy → rate_limiting → billing_metering → feature_flags → observability_saas |
| **Data / platform engineer** | storage_retrieval → databases_design → event_driven_architecture → platform_designs |

---

## Dependency map

```text
interview_framework_estimation  → (nền cho mọi thứ: biết ước lượng trước khi chọn)

scalability ──┬─→ load_balancing
              ├─→ databases_design ──→ storage_retrieval
              └─→ caching ───────────→ databases_design

availability_reliability ──┬─→ distributed_systems_theory
                           └─→ load_balancing (health check, draining)

networking_protocols ──┬─→ load_balancing (L4/L7, TLS)
                       ├─→ caching (CDN, HTTP cache)
                       └─→ api_design (REST/gRPC/GraphQL)

api_design ──→ microservices ──→ event_driven_architecture ──→ distributed_transactions
                                                                      ↑
                                                        storage_retrieval (schema evolution)

multi_tenancy ──┬─→ databases_design, caching
                ├─→ rate_limiting
                └─→ observability_saas
billing_metering ──→ event_driven_architecture
feature_flags ──→ multi_tenancy, api_design

case_studies ──→ áp dụng toàn bộ nhóm trên
```

---

## Key concepts → file

| Khái niệm | File |
|---|---|
| RESHADED, back-of-envelope, p99, tail amplification | [interview_framework_estimation.md](fundamentals/interview_framework_estimation.md) |
| Amdahl/USL, stateless, auto-scaling, cell-based, scale cube | [scalability.md](fundamentals/scalability.md) |
| SLI/SLO/error budget, CAP/PACELC, circuit breaker, bulkhead, load shedding, chaos | [availability_reliability.md](fundamentals/availability_reliability.md) |
| L4/L7, P2C, consistent hashing, liveness vs readiness, draining, anycast | [load_balancing.md](fundamentals/load_balancing.md) |
| Cache pattern, stampede/penetration/avalanche, invalidation, hot key, CDN | [caching.md](fundamentals/caching.md) |
| SQL/NoSQL, replication lag, sharding, shard key, index, pool, migration | [databases_design.md](fundamentals/databases_design.md) |
| WAL, B-tree vs LSM, columnar, Avro/Protobuf/Parquet, schema evolution | [storage_retrieval.md](fundamentals/storage_retrieval.md) |
| Consistency model, Raft, quorum, CRDT, vector clock, fencing token, gossip | [distributed_systems_theory.md](fundamentals/distributed_systems_theory.md) |
| TCP/HTTP2/HTTP3, TLS, SSE vs WebSocket, DNS, proxy vs gateway | [networking_protocols.md](fundamentals/networking_protocols.md) |
| DDD/bounded context, data ownership, sync/async, resilience, Strangler Fig | [microservices.md](advanced/microservices.md) |
| Event vs command, delivery, ordering, idempotency, Outbox/Inbox, replay, CQRS | [event_driven_architecture.md](advanced/event_driven_architecture.md) |
| Invariant, unknown outcome, 2PC, Saga, TCC, Outbox/Inbox, reconciliation | [distributed_transactions.md](advanced/distributed_transactions.md) |
| HTTP semantics, Problem Details, idempotency, ETag, cursor, gRPC, GraphQL, OAuth | [api_design.md](advanced/api_design.md) |
| Tenant identity/context, silo/pool/bridge, RLS, stamps, data lifecycle | [multi_tenancy.md](saas/multi_tenancy.md) |
| Fixed/sliding/token/GCRA, concurrency, local/global, fairness, Redis atomicity | [rate_limiting.md](saas/rate_limiting.md) |
| Usage ledger, rating, price version, invoice/payment state, correction, reconciliation | [billing_metering.md](saas/billing_metering.md) |
| Release/ops/experiment flag, deterministic rollout, kill switch, migration, OpenFeature | [feature_flags.md](saas/feature_flags.md) |
| Fan-out, celebrity, geohash, message ordering | [realtime_scale_designs.md](case_studies/realtime_scale_designs.md) |
| Erasure coding, precompute, double-entry ledger, dedup nhiều tầng | [platform_designs.md](case_studies/platform_designs.md) |

---

## Chú thích trạng thái

- ✅ **Chuẩn hóa** – đã rewrite sâu (2026-07-30 đến 2026-07-31), có bảng trade-off, checklist, cross-link
- 🟡 **Chờ chuẩn hóa** – có nội dung đầy đủ, chờ rewrite theo cùng chuẩn ở phase tiếp theo
- 🔄 Đang làm
- ⬜ Chưa làm

**Tổng: 21 file** (19 gốc + 2 mới: `storage_retrieval.md`, `platform_designs.md`), trong đó **20/21 đã chuẩn hóa**; ngoài ra có `glossary.md`, `roadmap.md` và `system_design_knowledge.md`.

---

## Liên kết sang package khác

| Chủ đề liên quan | Package |
|---|---|
| Chi tiết Kafka, Debezium, event-driven | [kafka](../kafka/roadmap.md) |
| Redis pattern, cluster, persistence | [redis](../redis/roadmap.md) |
| RDBMS: index, transaction, replication, HA/DR | [sqlserver](../sqlserver/roadmap.md) |
| Document store: schema design, sharding | [mongodb](../mongodb/roadmap.md) |
| Columnar/OLAP engine | [clickhouse](../clickhouse/roadmap.md) |
| Full-text search, geo query | [elasticsearch](../elasticsearch/roadmap.md) |
| WebSocket ở quy mô lớn | [websocket](../websocket/roadmap.md) |
| Metric, dashboard, alert, SLO trong thực tế | [prometheus_grafana](../prometheus_grafana/roadmap.md) |
| Container, orchestration, HPA/KEDA | [docker](../docker/roadmap.md), [kubernetes](../kubernetes/roadmap.md) |
| Resilience4j, Spring Cloud, JPA | [springboot](../springboot/roadmap.md), [java](../java/roadmap.md) |
| TLS/PKI, threat modeling, DevSecOps | [security](../security/roadmap.md) |

---

*Cập nhật lần cuối: 2026-07-31*
