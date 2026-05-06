# Database Design – Thiết kế cơ sở dữ liệu cho hệ thống lớn

## What – Database Design là gì trong System Design?

Không phải schema design (ERD), mà là **chiến lược lựa chọn, tổ chức, và scale database** để đáp ứng:
- Throughput (TPS)
- Latency (P99 read/write)
- Consistency requirements
- Data volume (GB → TB → PB)
- Access patterns

---

## SQL vs NoSQL – Khi nào dùng gì?

### SQL (Relational Database)

**Đặc điểm:**
- ACID transactions (Atomicity, Consistency, Isolation, Durability)
- Structured schema (schema-first)
- Powerful JOIN, aggregation
- Vertical scaling tự nhiên; horizontal khó hơn

**Dùng khi:**
- Financial transactions (banking, billing)
- Complex relationships (nhiều JOIN)
- Strong consistency required
- Data analyst cần ad-hoc queries
- Compliance/auditing (ACID guarantees)

**Ví dụ:** PostgreSQL, MySQL, SQL Server, Oracle

### NoSQL (Non-Relational)

**4 loại NoSQL chính:**

| Loại | Model | Ví dụ | Dùng khi |
|------|-------|-------|----------|
| Document | JSON documents | MongoDB, Firestore | Flexible schema, nested data |
| Key-Value | Key → Value | Redis, DynamoDB | Cache, session, simple lookups |
| Wide-Column | Row key + column families | Cassandra, HBase | Time-series, IoT, high write |
| Graph | Nodes + Edges | Neo4j, Amazon Neptune | Social graph, recommendations |

**Dùng khi:**
- Schema thay đổi thường xuyên (product catalog)
- Horizontal scale cần đơn giản
- High write throughput (IoT, logs)
- Specific access patterns (key lookups)

---

## Replication – Sao chép dữ liệu

### Primary-Replica (Master-Slave)

```
Write → Primary (1) → Replica 1 (read-only)
                    → Replica 2 (read-only)
                    → Replica 3 (read-only)
Read → Any Replica
```

**Replication lag:** Async replication → đọc từ replica có thể stale vài ms đến vài giây.

**Giải pháp stale read:**
1. Read from primary for critical data (current user profile)
2. Wait for replication (`WAIT n_replicas timeout`)
3. Read-your-writes consistency: track last write timestamp

**Failover:**
- Manual: DBA promote replica → update DNS → app reconnect
- Automatic: Orchestrator, Patroni (PostgreSQL), MHA (MySQL)

### Multi-Primary (Multi-Master)

```
Write → Primary A ←──sync──→ Primary B ← Write
                              ↓
                        Conflict resolution
```

**Conflict resolution strategies:**
1. Last Write Wins (LWW) – dùng timestamp, simple nhưng có thể mất write
2. Application-level merge (CRDT)
3. Avoid conflicts: route same key → same primary

**Ví dụ:** Cassandra, CockroachDB, AWS Aurora Global Database

---

## Sharding – Phân vùng dữ liệu ngang

### Vấn đề cần giải quyết
Single DB node → giới hạn storage và throughput. Sharding chia data thành nhiều **shard**, mỗi shard trên một node riêng.

### Sharding Strategies

#### 1. Range-Based Sharding
```
Shard 0: user_id 1 – 1,000,000
Shard 1: user_id 1,000,001 – 2,000,000
Shard 2: user_id 2,000,001 – 3,000,000
```

**Ưu:** Đơn giản, range queries hiệu quả
**Nhược:** Hotspot nếu data không đều (shard mới nhất nhận hết writes)

#### 2. Hash-Based Sharding
```
shard_id = hash(user_id) % num_shards
user_id=123 → hash → 0xA3F1... → 3 (shard 3)
```

**Ưu:** Phân phối đều
**Nhược:** Range query không hiệu quả; resharding khi thêm shard rất đau

#### 3. Consistent Hashing
Dùng ring, thêm/bớt shard chỉ ảnh hưởng ~1/N data.

```
Ring:   0 ────────── 2^32
Shards: A(at 100), B(at 200), C(at 300)

key=123 → hash=150 → maps to Shard B (next clockwise)
```

**Add shard D (at 250):** Chỉ data từ 200-250 (B→D range) bị migrate.

#### 4. Directory-Based Sharding
Lookup service biết key → shard mapping.

```
Client → Shard Lookup Service → "user:123 is on Shard 3" → query Shard 3
```

**Ưu:** Flexible, có thể migrate keys dễ
**Nhược:** Lookup service là bottleneck và SPOF

### Sharding trong thực tế

**Vitess (YouTube):** Sharding layer cho MySQL
```
Application → Vitess → MySQL Shard 0
                     → MySQL Shard 1
                     → MySQL Shard N
```

**MongoDB Sharding:**
```
mongos (router) → Config Servers (shard map)
                → Shard A (replica set)
                → Shard B (replica set)
```

### Thách thức khi Shard

| Thách thức | Giải pháp |
|-----------|-----------|
| Cross-shard JOINs | Denormalize, application-side join |
| Cross-shard transactions | SAGA pattern, avoid if possible |
| Rebalancing shards | Consistent hashing, phased migration |
| Hot shard | Sub-shard hot key, add random suffix |

---

## Indexes – Tối ưu query performance

### B-Tree Index (Default)
Phù hợp equality (`=`), range (`>`, `<`), ORDER BY.

```sql
CREATE INDEX idx_user_email ON users(email);
-- Query: SELECT * WHERE email = 'a@b.com' → O(log N)
-- Full scan: O(N) millions rows → catastrophic
```

### Composite Index – thứ tự quan trọng!
```sql
CREATE INDEX idx_tenant_created ON orders(tenant_id, created_at);

-- GOOD: sử dụng index đầy đủ
SELECT * FROM orders WHERE tenant_id = 1 AND created_at > '2024-01-01';

-- PARTIAL: chỉ dùng first column
SELECT * FROM orders WHERE tenant_id = 1;

-- BAD: không dùng composite index này
SELECT * FROM orders WHERE created_at > '2024-01-01';
```

**Leftmost prefix rule:** Composite index (A, B, C) → queries trên A, (A,B), (A,B,C) dùng được index. Query trên B hoặc C alone thì không.

### Covering Index
Index chứa tất cả columns cần → không cần lookup table row.

```sql
CREATE INDEX idx_covering ON users(tenant_id, id, name, email);
SELECT id, name, email FROM users WHERE tenant_id = 5;
-- → "Index Only Scan" – không touch main table
```

### Partial Index
Index chỉ cho subset của data.

```sql
CREATE INDEX idx_active_orders ON orders(user_id)
WHERE status = 'ACTIVE';  -- 10% of rows → smaller index
```

---

## Connection Pooling

Tạo và maintain pool of DB connections thay vì open/close mỗi request.

```
App Servers (20 nodes) → Connection Pool → PostgreSQL (max 200 conn)
Each server: max 10 conn
Total: 200 connections → PostgreSQL handles OK

Without pool: 20 servers × 100 threads = 2000 connections → OOM crash
```

### HikariCP (Java – Fastest connection pool)
```java
HikariConfig config = new HikariConfig();
config.setMaximumPoolSize(10);          // Connections per app instance
config.setMinimumIdle(5);
config.setConnectionTimeout(30_000);   // Wait 30s before error
config.setIdleTimeout(600_000);        // Remove idle after 10 min
config.setMaxLifetime(1_800_000);      // Replace connection after 30 min
config.setLeakDetectionThreshold(2000); // Warn if connection held > 2s

// Thêm cho microservices
config.addDataSourceProperty("prepStmtCacheSize", "250");
config.addDataSourceProperty("prepStmtCacheSqlLimit", "2048");
config.addDataSourceProperty("cachePrepStmts", "true");
```

### PgBouncer (PostgreSQL Connection Pooler)
Nằm giữa app và PostgreSQL, multiplexing connections.

```
1000 app connections → PgBouncer (transaction mode) → 50 real PG connections
```

| Mode | Description | Dùng khi |
|------|-------------|----------|
| Session | 1 app conn = 1 PG conn suốt session | Default, safe |
| Transaction | PG conn chỉ giữ trong transaction | Microservices (most efficient) |
| Statement | PG conn per statement | Không support prepared statements |

---

## Read Replicas vs Caching

| | Read Replica | Cache (Redis) |
|--|-------------|---------------|
| Data freshness | Seconds lag | Configurable TTL |
| Query flexibility | Full SQL | Key-based |
| Consistency | Near-strong | Eventual |
| Cost | Same DB engine cost | Cheaper memory |
| Best for | Complex queries, reports | Simple lookups, hot data |

**Pattern kết hợp:**
```
Hot data → Redis (cache-aside)
Complex reports → Read Replica
Analytical queries → Data Warehouse (BigQuery, Redshift)
```

---

## OLTP vs OLAP

| | OLTP | OLAP |
|--|------|------|
| Purpose | Transactional operations | Analytics |
| Query type | Simple, indexed | Complex aggregations |
| Data size | GB | TB-PB |
| Schema | Normalized (3NF) | Denormalized (Star schema) |
| Technology | PostgreSQL, MySQL | BigQuery, Redshift, ClickHouse |
| Update frequency | Real-time | Batch/hourly |

**Lambda Architecture:**
```
Data → Batch Layer (Spark → HDFS → Hive)
     → Speed Layer (Kafka → Flink → Redis)
           ↓
        Serving Layer (merge batch + speed)
```

---

## Trade-offs

| Decision | Option A | Option B |
|---------|----------|----------|
| Scale | Vertical (simpler) | Horizontal sharding (complex) |
| Consistency | Strong (slow, expensive) | Eventual (fast, cheap) |
| Schema | Fixed SQL (safe) | Flexible NoSQL (agile) |
| Replication | Sync (zero lag, slow write) | Async (fast write, potential lag) |

---

## Real-world Production

### Shopify (Shop Sharding)
- Mỗi shop trên 1 shard MySQL pod
- Pods có thể chứa nhiều shops (bin packing)
- Vitess để manage shards

### Instagram (PostgreSQL)
- Horizontal sharding: user_id-based
- 12 PostgreSQL replicas per shard
- Stored procedures để atomic operations across tables

### GitHub (MySQL → ProxySQL)
- ProxySQL làm connection pooler + read/write splitting
- Blue-Green deployments cho schema migrations

---

## Ghi chú

**Sub-topic tiếp theo:**
- `advanced/microservices.md` – Database per Service pattern, Polyglot persistence
- `advanced/distributed_transactions.md` – Cross-shard transactions, SAGA
- **Keywords:** Event-sourcing DB (EventStoreDB), Time-series DB (InfluxDB, TimescaleDB), NewSQL (CockroachDB, Spanner), Database migration strategies (expand-contract), Zero-downtime schema migration, pg_partman, Table partitioning
