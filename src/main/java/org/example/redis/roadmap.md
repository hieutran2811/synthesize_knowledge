# Roadmap Tổng Hợp Kiến Thức Redis

> 📖 Tra cứu nhanh thuật ngữ: [Redis Glossary](glossary.md)
>
> Learning path đã được chuẩn hóa theo Redis Open Source 8.8: từ mental model và HA đến performance, failure semantics và các design pattern production.

## Cấu trúc thư mục
```
redis/
├── roadmap.md                    ← file này
├── glossary.md                   ← thuật ngữ Redis tra cứu nhanh
├── redis_fundamentals.md        ← Mental model, Data Types Redis 8.8, TTL, Atomicity, Persistence
├── redis_ha.md                  ← Replication, Sentinel, Cluster
├── redis_performance.md         ← Memory, Eviction, Pipelining, Lua, Monitoring
└── redis_patterns.md            ← Design Patterns: caching, pub/sub, streams, rate limiting
```

---

## Mục lục

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Redis Fundamentals – mental model, execution/atomicity, key design, core và Redis 8 data types, TTL/expiration, RDB/AOF, command safety | [redis_fundamentals.md](redis_fundamentals.md) | ✅ Redis 8.8 |
| 2 | Redis High Availability – replication, Sentinel, Cluster, failure mode và failover | [redis_ha.md](redis_ha.md) | ✅ Redis 8.8 |
| 3 | Redis Performance & Internals – memory, eviction, pipeline, scripting, transaction, protocol và monitoring | [redis_performance.md](redis_performance.md) | ✅ Redis 8.8 |
| 4 | Redis Design Patterns – caching, Pub/Sub, Streams, rate limit, session, distributed lock, leaderboard và job queue | [redis_patterns.md](redis_patterns.md) | ✅ Redis 8.8 |

---

## Chú thích trạng thái
- ✅ Hoàn thành – đã refactor theo phiên bản mục tiêu
- 🟡 Đã có nội dung nhưng cần rà soát/version hóa
- 🔄 Đang làm
- ⬜ Chưa làm

## Quick Reference: Redis Use Cases

| Use Case | Pattern | Redis Feature |
|---------|---------|--------------|
| Session Store | Key-Value với TTL | String + EXPIRE |
| Caching | Cache-Aside / Write-Through | String / Hash |
| Rate Limiting | Fixed/sliding window hoặc token bucket | INCREX 8.8 / Sorted Set / Function |
| Pub/Sub Messaging | At-most-once fan-out cho subscriber online | PUBLISH/SUBSCRIBE, SPUBLISH/SSUBSCRIBE |
| Event Streaming | At-least-once, replay, consumer groups | XADD/XREADGROUP/XACK/XAUTOCLAIM/XNACK |
| Leaderboard | Sorted by score | Sorted Set (ZADD/ZRANK) |
| Distributed Coordination | Lease có ownership/fencing khi phù hợp | SET NX PX + DELEX / library đã review |
| Job Queue | At-least-once, retry, DLQ | Streams hoặc List với BLMOVE |
| Full-text Search | Index + query | Redis Search |
| Bloom Filter | Probabilistic membership | RedisBloom |
| Time Series | Metrics storage | RedisTimeSeries |
| Geo Index | Proximity search | GEO commands |
| Analytics | Unique count | HyperLogLog |

> Bảng trên chỉ là gợi ý bắt đầu. Việc chọn Redis còn phụ thuộc consistency, durability, memory budget, hot key, command complexity và failure mode.

*Cập nhật lần cuối: 2026-07-29*
