# System Design – Roadmap

## Tiến độ tổng hợp

### Fundamentals (Cơ bản)
| File | Topic | Status |
|------|-------|--------|
| `fundamentals/scalability.md` | Vertical vs Horizontal, Stateless, Auto-scaling | ✅ Done |
| `fundamentals/availability_reliability.md` | CAP, PACELC, SLA/SLO/SLI, Circuit Breaker | ✅ Done |
| `fundamentals/load_balancing.md` | L4/L7, Algorithms, Global LB, Health checks | ✅ Done |
| `fundamentals/caching.md` | Cache patterns, CDN, Redis, Invalidation | ✅ Done |
| `fundamentals/databases_design.md` | SQL/NoSQL, Sharding, Replication, Connection pool | ✅ Done |

### Advanced (Nâng cao)
| File | Topic | Status |
|------|-------|--------|
| `advanced/microservices.md` | Decomposition, Service Mesh, API Gateway | ✅ Done |
| `advanced/event_driven_architecture.md` | Event Sourcing, CQRS, Choreography vs Orchestration | ✅ Done |
| `advanced/distributed_transactions.md` | 2PC, SAGA, Outbox Pattern, Idempotency | ✅ Done |
| `advanced/api_design.md` | REST, GraphQL, gRPC, Versioning, Gateway | ✅ Done |

### SaaS Thực chiến
| File | Topic | Status |
|------|-------|--------|
| `saas/multi_tenancy.md` | Silo/Pool/Bridge, Data isolation, Tenant routing | ✅ Done |
| `saas/billing_metering.md` | Usage metering, Stripe, Revenue recognition | ✅ Done |
| `saas/rate_limiting.md` | Token bucket, Leaky bucket, Sliding window, Redis | ✅ Done |
| `saas/feature_flags.md` | Feature toggles, A/B testing, Canary, LaunchDarkly | ✅ Done |
| `saas/observability_saas.md` | Multi-tenant metrics, Cost attribution, Alerting | ✅ Done |

### Bổ sung 2026-06 – Lấp gap chuyên gia (4 cụm)
| File | Topic | Status |
|------|-------|--------|
| `fundamentals/distributed_systems_theory.md` | Consistency models, Consensus (Raft/Paxos/ZAB), Quorum (R+W>N), Lamport/Vector clock, CRDT, distributed lock (fencing token), leader election, gossip, 8 fallacies | ✅ Done |
| `fundamentals/interview_framework_estimation.md` | RESHADED chi tiết, functional vs non-functional, **back-of-envelope** (QPS/storage/bandwidth/server), latency numbers, p99/p999 tail latency, bottleneck analysis, communication | ✅ Done |
| `fundamentals/networking_protocols.md` | TCP/UDP, HTTP/1.1-2-3 (QUIC), WebSocket vs SSE vs long-polling, DNS/GeoDNS, CDN (pull/push), forward/reverse proxy, API gateway, gRPC | ✅ Done |
| `case_studies/foundational_designs.md` | **URL shortener**, **distributed ID (Snowflake)**, **rate limiter** (design angle) — áp dụng RESHADED | ✅ Done |
| `case_studies/realtime_scale_designs.md` | **News feed** (fan-out push/pull/hybrid, celebrity), **chat** (WebSocket/presence/ordering), **proximity/geo** (geohash/quadtree/S2/Redis GEO) | ✅ Done |

---

## Dependency Map

```
Fundamentals (cơ bản)
    ├── scalability → load_balancing, databases_design
    ├── availability_reliability → caching, load_balancing
    └── caching → databases_design

Advanced
    ├── microservices → event_driven_architecture
    ├── event_driven_architecture → distributed_transactions
    └── api_design → microservices

SaaS
    ├── multi_tenancy → databases_design, caching, rate_limiting
    ├── billing_metering → event_driven_architecture, caching
    ├── rate_limiting → caching (Redis)
    ├── feature_flags → multi_tenancy, api_design
    └── observability_saas → multi_tenancy, microservices
```

---

## Tổng: 19 file / 19 file ✅ (14 gốc + 5 bổ sung 2026-06: distributed theory, interview/estimation, networking, 2 case-study)
