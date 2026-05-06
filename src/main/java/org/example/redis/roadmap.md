# Roadmap Tổng Hợp Kiến Thức Redis

## Cấu trúc thư mục
```
redis/
├── roadmap.md                    ← file này
├── redis_fundamentals.md        ← What/Why, Data Types, Commands, Persistence
├── redis_ha.md                  ← Replication, Sentinel, Cluster
├── redis_performance.md         ← Memory, Eviction, Pipelining, Lua, Monitoring
└── redis_patterns.md            ← Design Patterns: caching, pub/sub, streams, rate limiting
```

---

## Mục lục

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Redis Fundamentals – What/Why, kiến trúc single-thread, data types (String/List/Hash/Set/ZSet/Stream/HLL/Bitmap/Geo), commands, TTL/expiry, Persistence (RDB/AOF) | redis_fundamentals.md | ✅ |
| 2 | Redis High Availability – Master-Replica replication, Redis Sentinel (auto-failover), Redis Cluster (hash slots, sharding, gossip protocol) | redis_ha.md | ✅ |
| 3 | Redis Performance & Internals – Memory model, eviction policies, pipelining, Lua scripting, MULTI/EXEC transactions, RESP3 protocol, keyspace notifications, monitoring | redis_performance.md | ✅ |
| 4 | Redis Design Patterns – Caching strategies (Cache-Aside/Write-Through/Write-Behind), Pub/Sub, Streams (consumer groups), Rate Limiting, Session store, Distributed locks (Redlock), Leaderboard, Job Queue | redis_patterns.md | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành – đã có nội dung
- 🔄 Đang làm
- ⬜ Chưa làm

## Quick Reference: Redis Use Cases

| Use Case | Pattern | Redis Feature |
|---------|---------|--------------|
| Session Store | Key-Value với TTL | String + EXPIRE |
| Caching | Cache-Aside / Write-Through | String / Hash |
| Rate Limiting | Sliding window / Token bucket | INCR + EXPIRE / Sorted Set |
| Pub/Sub Messaging | Fan-out messages | PUBLISH/SUBSCRIBE |
| Event Streaming | Durable, consumer groups | XADD/XREAD/XACK |
| Leaderboard | Sorted by score | Sorted Set (ZADD/ZRANK) |
| Distributed Lock | Mutual exclusion | SET NX PX / Redlock |
| Job Queue | FIFO, reliable | List (LPUSH/BRPOP) |
| Full-text Search | Index + query | RediSearch (Redis Stack) |
| Bloom Filter | Probabilistic membership | RedisBloom |
| Time Series | Metrics storage | RedisTimeSeries |
| Geo Index | Proximity search | GEO commands |
| Analytics | Unique count | HyperLogLog |
