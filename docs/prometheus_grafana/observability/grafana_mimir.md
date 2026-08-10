---
title: "Grafana Mimir Deep Dive – Distributed Metrics, Tenancy và Production Operations"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 21
---
# Grafana Mimir Deep Dive – Distributed Metrics, Tenancy và Production Operations

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là hiểu Grafana Mimir như một distributed metrics backend:
> dữ liệu đi qua write/read path nào, thành phần nào sở hữu state, Kafka và object
> storage bảo đảm điều gì, tenant được cô lập ra sao và vận hành production bằng
> capacity/limits/runbook như thế nào.
>
> Baseline tham chiếu ngày 2026-07-29: **Grafana Mimir 3.1.x**. Từ Mimir 3.0,
> **ingest storage architecture** dùng Kafka đã stable và là kiến trúc được ưu tiên;
> kiến trúc classic vẫn được hỗ trợ nhưng có write/read quorum khác.
>
> Điều kiện đầu vào: đã hiểu Prometheus TSDB, remote write, PromQL, HA và metric
> cardinality. Xem [Prometheus Fundamentals](../prometheus/prometheus_fundamentals.md),
> [Prometheus Production](../prometheus/prometheus_production.md),
> [Metrics Design](metrics_design.md) và
> [Full Observability Stack](stack_integration.md).

---

## 1. Grafana Mimir giải quyết bài toán gì?

Một Prometheus server rất phù hợp để:

- scrape targets;
- evaluate rules gần workload;
- lưu TSDB cục bộ;
- query một phạm vi hệ thống;
- vận hành độc lập trong failure domain nhỏ.

Khi số cluster, tenant, retention hoặc active series tăng, cần thêm:

```text
nhiều Prometheus/Alloy
  → một write endpoint có thể scale ngang
  → durable long-term object storage
  → global PromQL query
  → multi-tenant limits và isolation
  → HA cho ingest/query/rules
```

Mimir cung cấp backend đó cho Prometheus và OpenTelemetry metrics.

Mimir không thay Prometheus scrape targets. Thông thường:

```text
Prometheus/Alloy scrape ở edge
  → remote write
  → Mimir lưu/query dài hạn
```

---

## 2. Prometheus và Mimir không phải hai lựa chọn loại trừ

| Trách nhiệm | Prometheus | Mimir |
|---|---|---|
| Pull/scrape target | Chính | Không phải vai trò chính |
| Local TSDB | Có | Distributed TSDB backend |
| Remote write sender | Có | Receiver |
| PromQL | Có | Prometheus-compatible API |
| Long retention | Giới hạn bởi local disk | Object storage |
| Multi-tenancy native | Không | Có |
| Scale ngang storage/query | Không trực tiếp | Có |
| Failure domain | Một server/HA pair | Nhiều component/zone |

Kiến trúc thường:

```text
cluster A Prometheus ─┐
cluster B Prometheus ─┼──▶ Mimir ──▶ global query
cluster C Alloy ──────┘
```

Giữ local retention đủ xử lý sự cố remote write hoặc backend. Không xóa local TSDB
chỉ vì Mimir đã tồn tại.

---

## 3. Mental model: ba lớp state

Trong Mimir 3.1 ingest storage:

```text
Recent durable log:
  Kafka

Recent queryable state:
  ingester memory + WAL/WBL + local TSDB

Long-term durable state:
  object storage blocks
```

Ba lớp có vai trò khác nhau:

- Kafka xác nhận write và giữ backlog gần đây;
- ingester consume để recent data query được và tạo block;
- object storage là long-term source cho blocks;
- store-gateway phục vụ index/chunks của blocks;
- compactor tối ưu blocks và enforce retention.

Nếu chỉ nhìn “object storage còn sống” chưa đủ kết luận recent writes query được.

---

## 4. Một binary, nhiều component

Mimir build các component vào cùng một binary. `-target` quyết định process chạy
vai trò nào:

```text
mimir -target=all
mimir -target=distributor
mimir -target=ingester
mimir -target=querier
...
```

Component chính:

| Path | Component |
|---|---|
| Write | distributor, Kafka, ingester |
| Read | query-frontend, query-scheduler, querier |
| Long-term | store-gateway, compactor, object storage |
| Rules | ruler |
| Alerts | Alertmanager |
| Control/limits | rings, runtime config, overrides-exporter |

Một binary giúp version nhất quán; không có nghĩa mọi component nên chung một
process trong production lớn.

---

## 5. Monolithic và microservices deployment mode

### Monolithic

```text
Mimir process target=all
  + filesystem hoặc object storage
```

Phù hợp:

- lab;
- development;
- workload nhỏ;
- học API/data flow.

### Microservices

```text
gateway
  ├── write → distributors → Kafka
  └── read  → query-frontends → schedulers → queriers

ingesters → object storage
store-gateways ← object storage
compactors ↔ object storage
```

Phù hợp production cần scale/failure isolation riêng từng component.

Không lấy cấu hình monolithic filesystem trong quickstart để chạy production.

---

## 6. Hai architecture từ Mimir 3.0

| Đặc điểm | Ingest storage – ưu tiên | Classic |
|---|---|---|
| Write durable tại | Kafka | quorum ingesters |
| Distributor ghi tới | Kafka partitions | ingesters |
| Ingester trong write path | Không | Có |
| Recent read | ingester consume Kafka | ingester nhận trực tiếp |
| Replication write | Kafka | Mimir ingester RF |
| Recovery gap | catch up Kafka | replica down bỏ lỡ writes |
| Read quorum | một healthy ingester/partition | quorum replicas |

Đây là khác biệt nền tảng. Khi đọc tài liệu/runbook cũ phải hỏi:

```text
cluster này dùng ingest storage hay classic?
```

Không áp dụng `replication_factor=3` của classic vào cách hiểu replication của
ingest storage.

---

## 7. Topology ingest storage end-to-end

```text
Prometheus / Alloy / OTel Collector
          │ write + tenant identity
          ▼
Authenticating gateway
          ▼
Distributor pool
          │ shard series
          ▼
Kafka topic partitions
          │ consume per partition/zone
          ▼
Ingester replicas
   ├── recent query
   └── TSDB blocks ──▶ object storage
                            │
              compactor ◀──┼──▶ store-gateway
                                      │
Grafana ──▶ query-frontend ──▶ scheduler ──▶ querier
                                      │        ├── ingester
                                      └────────└── store-gateway
```

Gateway ở sơ đồ là reverse proxy/auth layer, không nhất thiết là một Mimir
component.

---

## 8. Write path từng bước

Một remote-write request:

1. gateway xác thực client và gắn tenant ID;
2. distributor nhận request;
3. distributor validate samples/labels/metadata/exemplars;
4. enforce per-tenant limits;
5. shard series sang Kafka partitions;
6. Kafka persist/replicate theo cấu hình broker;
7. distributor trả success khi records được Kafka xác nhận;
8. ingesters consume partitions;
9. recent samples trở thành queryable;
10. ingester tạo block rồi upload object storage.

Điểm quan trọng:

```text
write success
  = Kafka đã xác nhận
  ≠ ingester đã consume xong
  ≠ block đã upload object storage
```

Đó là lý do cần theo dõi Kafka lag và recent-read consistency.

---

## 9. Distributor

Distributor là stateless write entry point. Nó:

- nhận Prometheus remote write, OTLP metrics và protocol được hỗ trợ;
- validate dữ liệu;
- enforce tenant limits;
- xử lý HA dedup khi bật;
- shard series;
- ghi Kafka hoặc ingesters tùy architecture.

Scale distributor theo:

- samples/second;
- requests/second;
- bytes/second;
- label validation cost;
- number of active tenants.

Vì stateless, distributor dễ scale ngang nhưng rate limiter toàn cluster dựa vào
số healthy distributors. Load balancing không đều sẽ làm một replica throttle
trước các replica khác.

---

## 10. Ingestion protocol và semantic

Mimir distributor hỗ trợ các đường ingest như:

- Prometheus remote write v1;
- Prometheus remote write v2;
- OTLP metrics;
- Influx protocol tương ứng.

Protocol không xóa khác biệt semantic:

```text
OTLP resource attributes
  → translation
  → Prometheus labels/metric names
```

Trước rollout OTLP cần kiểm tra:

- naming translation;
- resource attribute allowlist;
- temporality;
- histogram type;
- unit/suffix;
- start timestamp;
- duplicate với Prometheus scrape.

Đừng gửi cùng metric qua scrape và OTLP nếu không có dedup contract.

---

## 11. Validation và partial ingestion

Distributor kiểm tra:

- metric/label name;
- số labels;
- label name/value length;
- timestamp quá xa;
- exemplar structure;
- metadata length;
- per-tenant limits.

Một request có cả entry đúng và sai có thể ingest phần hợp lệ.

Response khác theo protocol:

- remote write/Influx có invalid data thường trả HTTP 400;
- OTLP tuân theo partial-success semantics nên có thể trả HTTP 200 với chi tiết
  rejected data trong body.

Vì thế không monitor OTLP chỉ bằng HTTP status:

```text
HTTP 200
  ≠ toàn bộ datapoints đã được nhận
```

Phải monitor rejected datapoints và sender logs.

---

## 12. Rate limit và HTTP 429

Distributor có limit theo tenant:

- request rate/burst;
- ingestion samples rate/burst;
- active series và validation limits khác.

Khi vượt rate, thường trả HTTP 429.

Các bước xử lý:

1. xác định tenant;
2. xem spike do deploy, scrape duplication hay legitimate growth;
3. kiểm tra distributor load balance;
4. xem sender retry/queue;
5. tăng limit chỉ khi capacity có headroom;
6. sửa cardinality nếu series explosion.

Tăng limit không tạo thêm CPU, memory, Kafka throughput hoặc object-storage budget.

---

## 13. Load balancing distributor

Mimir phân chia per-tenant global rate limit thành local limit theo số healthy
distributors. Điều này giả định request được phân phối tương đối đều.

Rủi ro:

- Kubernetes Service balance TCP connection, không balance từng HTTP request;
- remote-write shard reuse keep-alive connection;
- ít sender shards làm traffic dồn vào vài pods;
- L4 LB tạo skew.

Quan sát:

```text
rate(requests per distributor)
rate(samples per distributor)
CPU per distributor
429 per distributor/tenant
```

Giải pháp có thể là L7 load balancing hoặc điều chỉnh remote-write shards, sau khi
đo connection/request distribution thật.

---

## 14. Prometheus remote write queue

Sender side quyết định reliability đầu tiên:

```yaml
remote_write:
  - url: https://mimir.example/api/v1/push
    authorization:
      credentials_file: /etc/secrets/mimir-token
    queue_config:
      capacity: 10000
      min_shards: 4
      max_shards: 50
      max_samples_per_send: 2000
```

Các giá trị chỉ minh họa, không phải default production.

Theo dõi tại sender:

- pending samples;
- failed/retried samples;
- dropped samples;
- shard count;
- highest sent timestamp;
- remote storage lag;
- WAL disk.

Queue quá nhỏ mất khả năng hấp thụ outage ngắn; quá lớn tốn memory và kéo dài thời
gian recovery.

---

## 15. HA deduplication

Hai Prometheus replicas có thể scrape cùng targets và remote write cùng series.
Mimir HA tracker chọn replica authoritative theo:

- cluster label;
- replica label;
- heartbeat/failover state.

```text
Prometheus A labels: cluster=prod-a, replica=a
Prometheus B labels: cluster=prod-a, replica=b
                 │
                 ▼
Mimir distributor HA tracker
  → accept một replica
  → drop duplicate replica
```

Đây là dedup cho HA pair được cấu hình đúng, không phải general dedup cho mọi
duplicate series.

Nếu cluster/replica label sai, có thể:

- double ingest;
- drop dữ liệu của cluster khác;
- failover chậm;
- active series tăng bất thường.

---

## 16. Tenant identity và `X-Scope-OrgID`

Mimir lấy tenant ID từ HTTP header:

```text
X-Scope-OrgID: tenant-a
```

Header này là routing/tenant context, **không tự là authentication**.

Production pattern:

```text
client credential
  → authenticating reverse proxy
  → authorize credential → tenant
  → xóa header do client tự gửi
  → inject X-Scope-OrgID đáng tin
  → Mimir
```

Không expose distributor/query-frontend trực tiếp ra untrusted network cho phép
client tự chọn tenant header.

---

## 17. Multi-tenancy isolation có nhiều lớp

Tenant isolation cần:

| Lớp | Control |
|---|---|
| Identity | auth proxy inject tenant |
| Data | per-tenant TSDB/block namespace |
| Ingest | rate/series/label limits |
| Query | concurrency/samples/time limits |
| Components | shuffle sharding |
| Rules | namespace/rule limits |
| Alerts | tenant Alertmanager state |
| Cost | usage attribution |

Multi-tenancy không mặc định tạo fairness hoàn hảo. Tenant lớn vẫn có thể gây:

- shared cache eviction;
- object-store throttling;
- scheduler queue pressure;
- compactor backlog;
- Kafka hot partitions;
- network saturation.

Phải kết hợp limits, shuffle sharding và capacity.

---

## 18. Hash rings

Hash ring dùng để:

- service discovery;
- phân ownership/shard;
- theo dõi health/lifecycle;
- zone-aware placement.

Mimir có nhiều ring với mục đích khác nhau, không phải một “global ring” duy nhất:

- partitions ring;
- ingesters ring;
- store-gateway ring;
- compactor ring;
- ruler/Alertmanager ring;
- distributor ring cho rate-limit/HA context;
- query-scheduler ring nếu dùng ring discovery.

Debug phải chỉ rõ ring nào. Một ring healthy không chứng minh ring khác healthy.

---

## 19. Memberlist, Consul và etcd

Mimir hỗ trợ KV backends cho ring:

- memberlist/gossip – default;
- Consul;
- etcd.

Memberlist:

- mỗi process giữ local view;
- gossip truyền update;
- tránh external KV dependency;
- cần network/gossip cluster đúng.

Failure mode:

- network policy chặn gossip;
- hai Mimir clusters vô tình chung memberlist;
- DNS join sai;
- rolling update quá nhanh;
- stale/unhealthy member.

Luôn phân biệt `memberlist cluster membership` với Kubernetes pod readiness.

---

## 20. Partitions ring trong ingest storage

Partitions ring là source of truth cho Kafka partitions Mimir đang dùng.

Write path:

```text
series fingerprint + tenant shard
  → active partition
  → Kafka topic-partition
```

Read path:

```text
partition
  → ingester owner trong từng zone
  → recent samples
```

Một ingester consume đúng một partition; một partition có thể có nhiều ingesters
ở các zone để HA.

Số partitions ảnh hưởng:

- parallelism;
- số ingesters;
- rebalancing/rollout;
- hot partition risk;
- Kafka metadata/operational cost.

Không tăng partition tùy hứng mà không có lifecycle plan.

---

## 21. Kafka trong Mimir không phải message bus chung

Mimir dùng một tập Kafka APIs giới hạn:

- Produce;
- Metadata;
- consumer groups/offset;
- ListOffsets trong một số recovery mode.

Distributor không cần transaction hoặc idempotent producer cho flow chuẩn.

Điều này cho phép một số Kafka-compatible backends, nhưng compatibility phải test:

- auth/TLS;
- replication/acks;
- partition semantics;
- consumer group offsets;
- throughput/latency;
- retention;
- failure/recovery.

Không dùng topic Mimir cho application events hoặc cho consumer tùy ý.

---

## 22. Kafka durability và availability

Trong ingest storage:

```text
Kafka unavailable
  → distributor không xác nhận writes

ingester unavailable
  → writes vẫn có thể vào Kafka
  → recent query thiếu cho partition tới khi consumer healthy
```

Kafka design cần:

- broker replication qua failure domains;
- `min.insync.replicas`/acks phù hợp;
- disk throughput và headroom;
- retention dài hơn maximum recovery window;
- alert consumer lag;
- partition ownership coverage;
- backup/DR theo Kafka strategy.

Kafka không thay object storage retention. Nó là durable ingest log gần đây, không
phải long-term metrics store.

---

## 23. Ingester trong ingest storage

Ingester:

- consume một Kafka partition;
- giữ recent series trong memory;
- ghi WAL/WBL/local TSDB;
- phục vụ recent reads;
- compact head thành blocks;
- upload blocks lên object storage;
- xóa local copy sau upload/retention phù hợp.

Một partition thường có ingester ở nhiều zone. Query recent data chỉ cần một
healthy ingester đã bắt kịp cho partition đó.

Metric quan trọng:

- consume lag/receive delay;
- partitions có consumer;
- active series/memory;
- WAL/WBL replay;
- head compaction;
- block upload;
- query latency/errors;
- disk usage/IO.

---

## 24. Read-after-write và strong consistency

Write success xảy ra khi Kafka xác nhận; ingester có thể chưa consume record.
Default query vì thế có thể chưa thấy sample vừa ghi trong một khoảng ngắn.

Khi cần read-after-write:

```text
X-Read-Consistency: strong
```

Flow:

1. query-frontend lấy latest Kafka offsets;
2. truyền offsets xuống ingesters;
3. mỗi ingester chờ consume tới offset yêu cầu;
4. query mới chạy.

Trade-off:

- thấy mọi write đã commit trước query;
- tăng latency;
- phụ thuộc Kafka offset lookup và consumer catch-up;
- có thể timeout khi lag cao.

Không bật strong consistency cho mọi dashboard nếu không cần.

---

## 25. Ingester trong classic architecture

Classic write:

```text
distributor
  → hash series
  → replicate tới RF ingesters
  → success khi quorum ghi thành công
```

Với RF=3, quorum thường là 2.

Classic ingester:

- tham gia cả write và read;
- replica down không tự nhận lại samples đã bỏ lỡ;
- querier cần read quorum để bảo đảm consistency;
- query pressure và write state cùng hội tụ ở ingester.

Classic vẫn hữu ích cho cluster hiện hữu, nhưng capacity/failure analysis phải dùng
đúng quorum model.

---

## 26. WAL và WBL

Ingester dùng:

- WAL – write-ahead log để recover in-memory state;
- WBL – write-behind log khi bật out-of-order ingestion.

WAL không thay replica/Kafka/object storage:

```text
WAL
  → restart recovery của một ingester

Kafka/replication
  → durability và catch-up giữa process/failure

object storage
  → long-term blocks
```

Local disk cần:

- SSD/low latency;
- POSIX semantics;
- đủ capacity cho replay/backlog;
- không dùng NFS/EFS/FUSE filesystem unsupported;
- monitoring IOPS, latency, usage.

---

## 27. TSDB blocks

Mimir dựa trên Prometheus TSDB block format:

```text
block/
  ├── meta.json
  ├── index
  └── chunks/
```

Mỗi tenant có TSDB/block namespace riêng. Default block range ban đầu thường là
hai giờ trước compaction.

Block:

- immutable sau khi hoàn tất;
- có ULID/time range/metadata;
- index labels → series;
- chunks chứa samples;
- được upload object storage;
- có thể được compactor merge thành range lớn hơn.

Immutable blocks giúp object storage phù hợp, nhưng tạo nhu cầu compaction, bucket
index và deletion marker.

---

## 28. Object storage là long-term source

Supported backend gồm:

- Amazon S3/S3-compatible;
- Google Cloud Storage;
- Azure Blob Storage;
- OpenStack Swift;
- filesystem chỉ cho single-node/lab.

Mimir không tạo bucket; infrastructure phải tạo và cấp quyền.

Tách prefix/bucket cho:

- metrics blocks;
- ruler configuration;
- Alertmanager state.

Không cấu hình blocks, ruler và Alertmanager trùng bucket + prefix. Mimir có thể
refuse startup và lifecycle của các object cũng khác nhau.

---

## 29. Thiết kế object storage production

Quyết định cần ghi:

- bucket/prefix layout;
- encryption/KMS;
- IAM theo component;
- TLS/private endpoint;
- versioning;
- lifecycle policy;
- request limits;
- cross-region replication;
- audit logs;
- restore procedure.

Mimir retention do compactor quản lý. Cloud lifecycle rule không được xóa object
sớm hơn Mimir hiểu, nếu không query gặp block thiếu/corrupt view.

Object store “11 số 9 durability” không bảo đảm:

- credential đúng;
- list/get/put latency thấp;
- không throttle;
- operator không xóa nhầm;
- application metadata nhất quán.

---

## 30. Store-gateway

Store-gateway phục vụ data từ blocks trong object storage cho querier.

Nó:

- sở hữu subset tenants/blocks theo ring;
- đồng bộ bucket index;
- giữ index-header trên local disk/memory;
- fetch chunks/index;
- dùng caches để giảm object-store calls;
- stream matching series về querier.

Store-gateway không giữ source data duy nhất; object storage mới là durable source.
Nhưng local disk/cache quyết định startup và query performance.

Scale theo:

- number of active series/blocks;
- long-range query rate;
- index-header size;
- cache hit;
- object-store throughput.

---

## 31. Bucket index

Bucket index là file per tenant:

```text
bucket-index.json.gz
  ├── blocks
  ├── block deletion marks
  └── updated_at
```

Compactor cập nhật nó; querier, store-gateway và ruler dùng để khám phá block thay
vì `list objects` toàn bucket liên tục.

Lợi ích:

- giảm object-store API calls;
- startup/query nhanh hơn;
- view block nhất quán hơn.

Nếu index stale quá ngưỡng, query nên fail thay vì trả partial result âm thầm.

Theo dõi `updated_at`, compactor health và bucket-index refresh errors.

---

## 32. Binary index-header

Prometheus block index có thể lớn. Store-gateway dùng binary index-header để lookup
labels/postings hiệu quả mà không giữ toàn index trong memory.

Trade-off:

- local disk giảm object-store read và memory;
- lazy loading giảm startup/memory;
- first query có cold-start latency;
- disk loss buộc rebuild/download;
- version/schema phải tương thích.

Cache/index-header không phải backup. Có thể xóa/rebuild theo runbook, nhưng phải
ước lượng object-store load và query degradation khi toàn fleet cold start cùng lúc.

---

## 33. Compactor

Compactor:

- nhóm blocks cùng tenant/time range;
- download input blocks;
- merge/deduplicate;
- upload output block;
- mark source blocks để xóa;
- enforce retention;
- cập nhật bucket index.

Compactor là stateless về durable state nhưng cần scratch disk lớn.

Ước lượng scratch:

```text
compaction concurrency
  × largest compaction input/output range
  × khoảng 2
```

Nếu compactor dừng ngắn hạn, ingest/query có thể tiếp tục nhưng block count và query
cost tăng. Nếu nghi compactor gây data-loss, halt trước hard deletion theo runbook.

---

## 34. Soft delete và hard delete

Mimir không xóa block ngay:

```text
compactor quyết định xóa
  → tạo deletion-mark.json
  → chờ deletion delay
  → hard delete object
```

Delay tạo cửa sổ:

- store-gateway refresh view;
- phát hiện vấn đề;
- operator can thiệp trước hard delete.

Không tự xóa marker/block bằng object-store CLI khi chưa hiểu state.

Mọi thao tác manual cần:

- tenant + block ULID chính xác;
- dry-run;
- audit reason;
- backup/version restore;
- kiểm tra compactor đang chạy hay dừng.

---

## 35. Retention

Default object-storage retention có thể là vô hạn nếu không cấu hình.

Global/per-tenant:

```yaml
limits:
  compactor_blocks_retention_period: 1y
```

Runtime override:

```yaml
overrides:
  tenant-a:
    compactor_blocks_retention_period: 90d
  tenant-b:
    compactor_blocks_retention_period: 2y
```

Mimir không hỗ trợ per-series retention hoặc Prometheus Delete Series API.

Vì vậy retention unit là tenant/time, không phải metric cụ thể. Data governance cần
tách tenant nếu retention/compliance khác nhau đáng kể.

---

## 36. Read path từng bước

Grafana query:

1. gateway xác thực và inject tenant;
2. query-frontend nhận PromQL/range;
3. kiểm tra result cache;
4. split/shard query nếu phù hợp;
5. enqueue vào query-scheduler;
6. querier lấy work;
7. querier đọc recent data từ ingesters;
8. querier đọc historical data qua store-gateways;
9. merge/evaluate PromQL;
10. query-frontend merge sub-results/cache;
11. trả response.

Latency tổng:

```text
queue + planning + fetch recent + fetch blocks + PromQL compute
+ merge + network + cache
```

Đừng chỉ alert query duration cuối cùng; cần phase/component metrics.

---

## 37. Query-frontend

Query-frontend là stateless read entry point. Nó:

- expose Prometheus-compatible API;
- split time range;
- shard query;
- cache results;
- enqueue scheduler;
- merge results;
- enforce một số query limits.

Run ít nhất hai replicas cho HA.

Readiness chỉ true sau khi kết nối được scheduler. Load balancer phải dùng `/ready`,
không chỉ process alive.

Scale theo:

- queries/second;
- subqueries generated;
- response size;
- cache operations;
- merge CPU/memory.

---

## 38. Query-scheduler và fairness

Scheduler giữ in-memory queue và phân work cho queriers.

Nó:

- decouple frontend scale khỏi querier;
- round-robin tenants có active queries;
- giảm một tenant chiếm toàn querier pool;
- giúp tách queue cho data sources/path.

Queue in-memory nghĩa là scheduler restart có thể làm in-flight queued requests
fail/retry; nó không phải durable job queue.

Theo dõi:

- queue length/oldest age theo tenant;
- rejected queries;
- connected frontends/queriers;
- scheduler CPU/memory;
- tenant fairness.

---

## 39. Querier

Querier evaluate PromQL:

```text
recent range  → ingesters
older blocks  → store-gateways
              → merge samples
              → execute expression
```

Querier là stateless nhưng mỗi query có thể dùng rất nhiều:

- memory cho intermediate vectors;
- CPU cho aggregation;
- network cho samples;
- concurrency slots;
- object-store/store-gateway capacity.

Scale querier theo query workload, không theo ingest rate duy nhất.

Một dashboard refresh mỗi 5 giây với nhiều panels có thể tạo QPS và fan-out lớn hơn
user tưởng.

---

## 40. Mimir Query Engine – MQE

MQE là alternative PromQL engine của Mimir:

- mục tiêu kết quả tương đương Prometheus engine;
- streaming execution;
- thường giảm memory/CPU;
- có memory estimation/protection;
- hỗ trợ query behavior tùy version.

Rollout engine:

1. kiểm tra function/feature compatibility;
2. chạy shadow/canary queries;
3. so sánh result;
4. đo latency/memory/CPU;
5. xem error category;
6. rollback flag rõ.

Không coi “engine nhanh hơn” là lý do bỏ query limits. Query xấu vẫn có thể rất đắt.

---

## 41. Query splitting

Frontend chia long-range query thành intervals:

```text
30-day query
  → 30 × 1-day subqueries
  → execute parallel
  → merge
```

Lợi ích:

- giới hạn peak memory mỗi subquery;
- parallelism;
- cache reuse.

Trade-off:

- nhiều request nội bộ;
- queue pressure;
- merge overhead;
- object-store/store-gateway fan-out;
- một user query tạo blast radius lớn.

Split interval phải cân bằng block layout, step, cache và query workload.

---

## 42. Query sharding

Một số PromQL expression có thể shard theo series:

```text
sum(rate(http_requests_total[5m]))
  → shard 1 subset series
  → shard 2 subset series
  → ...
  → merge partial aggregates
```

Sharding tăng parallelism và giảm memory per querier, nhưng:

- tổng CPU/network có thể tăng;
- không phải expression nào shard được;
- quá nhiều shards gây overhead;
- fairness/concurrency phải giới hạn.

Đừng đánh giá bằng p50 query latency. Cần đo total samples processed, CPU-seconds và
impact lên tenant khác.

---

## 43. Result, metadata, index và chunks cache

Các cache có mục tiêu khác:

| Cache | Người dùng | Dữ liệu |
|---|---|---|
| Result | query-frontend | partial query results |
| Metadata | querier/store-gateway | bucket index/meta/marks |
| Index | store-gateway | postings/index data |
| Chunks | store-gateway | metric chunks |

Memcached thường được dùng cho production caches.

Cache design:

- cluster riêng theo workload nếu contention;
- memory/eviction/connection limits;
- replication không mặc định;
- cold-cache capacity test;
- key/version isolation;
- không coi cache là durable.

Cache hit cao không chữa query cardinality không bounded.

---

## 44. Query limits và circuit breakers

Per-tenant controls có thể giới hạn:

- query time range;
- samples/chunks/series fetched;
- max concurrency;
- queue length;
- response size;
- estimated memory;
- cardinality endpoints;
- query duration.

Mục tiêu:

```text
bad query
  → fail sớm với error rõ
  ≠ OOM querier
  ≠ làm chậm mọi tenant
```

Limit error nên trả actionable message và được dashboard theo tenant/query source.

Tăng limit cho dashboard quan trọng chỉ sau khi tối ưu recording rules, step, range
và label filter.

---

## 45. Runtime configuration và overrides

Static config đặt global defaults. Runtime config cho phép đổi per-tenant overrides
mà không restart toàn cluster.

```yaml
overrides:
  team-a:
    ingestion_rate: 200000
    max_global_series_per_user: 3000000
  team-b:
    compactor_blocks_retention_period: 2y
```

Tên field/version phải lấy từ docs/config của Mimir 3.1 thực tế.

Operational rules:

- config trong Git;
- schema validation;
- review owner + expiry;
- atomic rollout;
- query `/runtime_config` để xác minh effective state;
- metric từ overrides-exporter;
- không chỉnh tay trong incident rồi quên.

---

## 46. Shuffle sharding

Shuffle sharding gán mỗi tenant vào subset component/partitions ổn định:

```text
tenant A → partitions 1, 4, 7, 9
tenant B → partitions 2, 4, 8, 10
tenant C → partitions 1, 3, 6, 10
```

Lợi ích:

- giảm overlap;
- tenant xấu ảnh hưởng subset;
- outage không lan tới mọi tenant;
- predictable ownership.

Hỗ trợ ở partitions/ingesters, query path, store-gateway, ruler, compactor và
Alertmanager tùy config.

Shard quá nhỏ tạo hotspot/capacity ceiling; shard bằng/to hơn toàn pool gần như
không còn isolation.

---

## 47. Zone-aware replication

Zone awareness đặt replicas/owners qua failure domains:

```text
partition 42:
  ingester zone-a
  ingester zone-b
```

Kafka cũng phải replicate qua zones theo policy riêng. Mimir zone-aware ingesters
không tự cấu hình Kafka rack/replication.

Kiểm tra:

- labels zone chính xác;
- topology spread/anti-affinity;
- capacity còn đủ khi mất một zone;
- network cross-zone cost;
- rollout không hạ nhiều zones cùng lúc;
- store-gateway/ingester ring đều zone-aware khi cần.

HA chỉ có ý nghĩa nếu failure domains thực sự độc lập.

---

## 48. Failure matrix ingest storage

| Failure | Write | Recent read | Historical read |
|---|---|---|---|
| Một distributor | LB retry/replica khác | không trực tiếp | không |
| Kafka quorum mất | fail | dữ liệu đã consume còn đọc | không trực tiếp |
| Một ingester | vẫn ghi Kafka | replica cùng partition | không |
| Cả replicas một partition | vẫn có thể ghi | thiếu recent partition | block cũ vẫn đọc |
| Object store lỗi | write Kafka có thể tiếp tục ngắn hạn | recent còn đọc | fail/degrade |
| Store-gateway subset | không | recent không ảnh hưởng | retry/quorum tùy shard |
| Compactor dừng | không ngay | không ngay | chậm dần do nhiều blocks |
| Scheduler mất | không | query path fail/degrade | query path fail/degrade |

“Service up” cần SLO riêng cho write, recent read, historical read, rules và alerts.

---

## 49. Ruler

Ruler evaluate recording/alerting rules per tenant.

Hai mode:

### Internal

- embedded querier;
- gọi ingesters/store-gateways;
- không tận dụng đầy đủ query-frontend acceleration.

### Remote

- delegate evaluation tới query-frontend;
- dùng splitting/sharding/caching/limits;
- cần capacity query path;
- là lựa chọn bắt buộc/phù hợp cho một số ingest-storage setup/tooling.

Rule result được ghi trở lại Mimir, nên recording rule tạo thêm ingestion.

Đo:

- evaluation duration/missed interval;
- failures;
- samples produced;
- alert notification failures;
- query-frontend load do ruler.

---

## 50. Recording rules trong distributed backend

Recording rule đổi:

```text
query đắt, lặp lại
  → series precomputed
  → dashboard/alert query rẻ
```

Nhưng tạo chi phí:

- rule query;
- new series ingest;
- storage/retention;
- dependency graph;
- delayed/failure propagation.

Thiết kế:

- output labels bounded;
- group liên quan cùng interval;
- `query_offset` khi cần tránh partial recent data;
- strong consistency cho dependency trong group khi supported;
- owner và tests;
- không tạo rules “cho mọi dimension có thể”.

---

## 51. Mimir Alertmanager

Optional Mimir Alertmanager cung cấp tenant-aware:

- alert routing;
- grouping;
- deduplication;
- inhibition;
- silences;
- notification integrations.

State/config có storage riêng và replication/ring.

Gateway phải route đúng tenant. Tenant federation cho query không có nghĩa alert
configuration tự federate.

Theo dõi:

- config sync;
- ring ownership;
- firing alerts;
- notification errors/latency;
- silence/state persistence;
- duplicate notification khi migration.

Alertmanager không phát hiện vấn đề; ruler/Prometheus rules tạo alerts.

---

## 52. Tenant federation

Mimir có thể query nhiều tenant khi bật federation và dùng header:

```text
X-Scope-OrgID: tenant-a|tenant-b
```

Use case:

- platform overview;
- global capacity;
- cross-business dependency;
- shared SLO.

Security:

- chỉ trusted proxy/service account được chọn tenant set;
- không cho user tự sửa header;
- audit federated queries;
- query limits tính tới tổng data;
- tránh label collision giữa tenants.

Federated query có blast radius lớn hơn một tenant và cần policy/concurrency riêng.

---

## 53. Native histograms và exemplars

Mimir có thể ingest/query:

- classic histogram series;
- native histograms khi enable/config tương thích;
- exemplars;
- metadata.

Capacity phải tính khác:

- một native histogram sample có nhiều buckets nội tại;
- resolution/schema ảnh hưởng bytes;
- classic + native song song có thể duplicate cost;
- exemplars thêm storage/index context;
- high-cardinality exemplar labels vẫn nguy hiểm.

Rollout:

1. kiểm tra sender/receiver/query/Grafana compatibility;
2. canary metric;
3. so sánh quantiles;
4. đo bytes/sample;
5. xác định migration khỏi classic histogram.

---

## 54. Out-of-order samples

Out-of-order ingestion hữu ích cho:

- delayed collectors;
- backfill giới hạn;
- network buffering;
- multi-source writes.

Đổi lại:

- WBL và recovery phức tạp;
- memory/disk tăng;
- query/compaction behavior khác;
- duplicate/conflict semantics phải hiểu;
- cửa sổ out-of-order cần bounded.

Không bật cửa sổ rất lớn để che sender clock/network lỗi.

Theo dõi rejected old/out-of-order samples và phân biệt:

- legitimate late arrival;
- timestamp bug;
- duplicate pipeline;
- backfill ngoài policy.

---

## 55. Capacity model

Đầu vào tối thiểu:

```text
active series
samples/second
bytes/sample theo metric types
number of tenants
largest tenant
write request rate
query rate + concurrency
samples scanned/query
retention
rule evaluations/second
Kafka lag recovery target
```

Sample rate xấp xỉ:

```text
samples/s = active series / scrape interval seconds
```

Ví dụ:

```text
3,000,000 series / 15s = 200,000 samples/s
```

Đây chưa gồm rules, metadata, exemplars, histogram cost và replication.

---

## 56. Official sizing chỉ là điểm bắt đầu

Tài liệu Mimir đưa rough estimates cho general workload, ví dụ:

- toàn cluster khoảng một CPU và 1 GB memory mỗi 25k samples/s;
- ingester sizing theo series in memory;
- querier/store-gateway theo query concurrency;
- compactor theo active series và largest tenant;
- disk theo WAL/index-header/compaction scratch.

Không copy con số thành guarantee vì workload khác nhau ở:

- label length/cardinality;
- histogram;
- query selectivity;
- cache hit;
- retention;
- tenant distribution;
- object-store latency;
- Kafka compression;
- Mimir version.

Benchmark bằng replay/synthetic workload gần production và giữ headroom cho zone
failure.

---

## 57. Scale từng component theo đúng signal

| Component | Scale signal chính |
|---|---|
| Distributor | samples/request/CPU/429 |
| Kafka | produce bytes, broker disk/network, partition latency |
| Ingester | series, memory, consume lag, disk |
| Query-frontend | QPS, merge CPU, cache, response |
| Scheduler | queue length/age, connected workers |
| Querier | concurrency, CPU/memory, samples processed |
| Store-gateway | QPS, index/chunk cache, disk, object calls |
| Compactor | backlog, largest tenant, scratch disk |
| Ruler | evaluations/s, duration, missed intervals |
| Alertmanager | firing alerts/notifications |

Một HPA dùng CPU cho mọi component là quá đơn giản.

Stateful component/partition ownership cần rollout-aware scaling, không chỉ tăng/giảm
replica tức thời.

---

## 58. Autoscaling và downscale

Autoscaling phải tôn trọng:

- partitions/ingester ownership;
- Kafka catch-up;
- ring stability;
- query scheduler workers;
- compactor tenant shard;
- zone balance;
- persistent volume lifecycle.

Downscale nguy hiểm hơn scale-out:

```text
mark/read-only hoặc prepare downscale
  → drain ownership/work
  → chờ ring/consumer ổn định
  → xác minh replicas/partition coverage
  → terminate
```

Không để HPA xóa hàng loạt stateful pods khi traffic giảm vài phút.

Giới hạn scale rate, stabilization window và PodDisruptionBudget theo failure model.

---

## 59. Meta-monitoring

Mimir cung cấp production dashboards, recording rules, alerts và runbooks qua
mimir-mixin.

Nên monitor Mimir bằng failure domain riêng:

```text
monitoring Prometheus/Alloy
  → scrape Mimir components + Kafka + object-store exporter
  → lưu đủ độc lập để debug khi Mimir lỗi
```

Golden signals:

- write availability/latency/rejections;
- query availability/latency;
- Kafka produce/fetch/lag;
- ingester series/memory/block upload;
- scheduler queue;
- store-gateway/object-store errors;
- compactor progress/bucket index age;
- rule/alert delivery.

Đừng chỉ lưu toàn bộ meta-metrics vào chính cluster đang được monitor.

---

## 60. Write-path troubleshooting

Flow điều tra:

```text
remote write lag tăng
  ├── sender queue/WAL?
  ├── gateway auth/tenant?
  ├── distributor 4xx/429/5xx?
  ├── load-balance skew?
  ├── Kafka produce latency/errors/quorum?
  ├── partitions active?
  └── ingester consume lag/block upload?
```

Phân loại response:

- 400: schema/timestamp/label/invalid data;
- 401/403: auth proxy;
- 429: limit/capacity;
- 5xx: service/dependency;
- timeout: network/queue/Kafka/backend.

Không retry vô hạn permanent 400. Sender phải log/drop có metric rõ.

---

## 61. Read-path troubleshooting

Flow:

```text
query chậm/fail
  ├── frontend cache hit/miss?
  ├── generated subqueries/shards?
  ├── scheduler queue theo tenant?
  ├── querier CPU/memory/concurrency?
  ├── recent → ingester lag/coverage?
  ├── historical → store-gateway?
  ├── index/chunks cache?
  ├── object-store latency/throttle?
  └── PromQL cardinality/step/range?
```

Bắt đầu bằng:

- query stats/evaluation stats;
- tenant;
- query fingerprint/text đã redact;
- start/end/step;
- samples/series/chunks processed;
- queue time vs execution time.

Một query 30 ngày step 5s có thể là client misuse, không phải thiếu queriers.

---

## 62. Compactor, block và storage incident

Triệu chứng:

- block upload ngừng;
- compaction backlog;
- bucket index stale;
- object-store 403/429/5xx;
- store-gateway sync fail;
- query historical gap;
- scratch disk đầy.

Thứ tự an toàn:

1. xác minh object-store health/credentials;
2. kiểm tra ingester upload;
3. kiểm tra compactor logs/disk/ring;
4. kiểm tra bucket index age;
5. dừng compactor nếu nghi delete/corruption;
6. không hard-delete manual;
7. dùng official tool + dry-run cho block marker;
8. xác minh query qua known test series.

Object storage console không phải công cụ sửa TSDB thông thường.

---

## 63. Security, upgrade và migration

### Security

- authn/authz ở reverse proxy;
- mTLS nội bộ khi threat model yêu cầu;
- IAM tối thiểu theo bucket/prefix;
- Kafka TLS/SASL;
- secret qua file/secret manager;
- network policy;
- audit tenant/federated/admin APIs;
- không expose `/runtime_config` hoặc ring/admin endpoints công khai.

### Upgrade

- đọc release/deprecation notes;
- một minor step theo support policy;
- canary và rolling update;
- theo dõi readiness/ring/partition coverage;
- tránh rollout nhiều zones cùng lúc;
- kiểm tra config flags bị đổi/xóa.

### Migration

- Prometheus/Thanos/Cortex → Mimir: inventory rules, labels, tenant, history;
- classic → ingest storage: cluster song song + duplicate writes + chuyển reads;
- tránh hai compactors cạnh tranh không có plan;
- kiểm tra alert duplication;
- chỉ decommission sau retention overlap và query verification.

---

## 64. Production checklist và câu hỏi tự kiểm tra

### Checklist

- [ ] Đã chọn ingest storage hay classic và ghi rõ lý do.
- [ ] Mimir/Kafka/object storage version được pin.
- [ ] Auth proxy inject tenant, client không tự chọn header.
- [ ] Remote-write queue/WAL và retry policy đã test.
- [ ] HA labels/dedup contract đúng.
- [ ] Kafka replication, retention và partition capacity có headroom.
- [ ] Mọi active partition có ingester replicas qua zones.
- [ ] Local disk dùng block storage/POSIX, không dùng NFS/EFS.
- [ ] Blocks/ruler/Alertmanager storage prefix được tách.
- [ ] Retention do compactor quản lý và được xác minh.
- [ ] Limits/runtime overrides có owner, review và expiry.
- [ ] Shuffle sharding cho tenant có blast radius lớn.
- [ ] Query limits bảo vệ memory/concurrency.
- [ ] Cache cold-start đã capacity test.
- [ ] Ruler/Alertmanager được monitor riêng.
- [ ] Mimir mixin dashboards/alerts/runbooks đã cài.
- [ ] Meta-monitoring còn query được khi Mimir outage.
- [ ] Backup/DR đã test restore, không chỉ bật bucket versioning.
- [ ] Upgrade giữ ring/zone/partition quorum.
- [ ] Có synthetic write → query canary end-to-end.

### Câu hỏi tự kiểm tra

1. Mimir bổ sung gì mà Prometheus local TSDB không cung cấp?
2. Ingest storage khác classic ở write acknowledgement nào?
3. Vì sao write success chưa chắc sample query được ngay?
4. `X-Read-Consistency: strong` đánh đổi điều gì?
5. Distributor stateless nhưng vì sao load balancing vẫn quan trọng?
6. HTTP 200 OTLP có luôn nghĩa không reject datapoint không?
7. HA tracker khác general dedup thế nào?
8. `X-Scope-OrgID` có phải authentication không?
9. Partitions ring và ingesters ring khác nhau thế nào?
10. Kafka giữ vai trò gì và không giữ vai trò gì?
11. WAL/WBL khác Kafka/object storage ra sao?
12. Store-gateway phục vụ dữ liệu nào?
13. Bucket index do ai cập nhật?
14. Vì sao stale bucket index nên fail query?
15. Soft delete tạo safety window như thế nào?
16. Mimir hỗ trợ per-series retention không?
17. Query splitting khác query sharding ra sao?
18. Scheduler tạo fairness ở đâu?
19. Shuffle sharding giảm noisy neighbor thế nào?
20. Capacity model cần inputs nào ngoài active series?
21. Vì sao cache không phải durable storage?
22. Compactor dừng ảnh hưởng gì theo thời gian?
23. Meta-monitoring tại sao cần failure domain độc lập?
24. Downscale ingester cần kiểm tra partition coverage nào?
25. Migration classic → ingest storage vì sao cần overlap writes?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Architecture và components

- [Grafana Mimir 3.1 documentation](https://grafana.com/docs/mimir/latest/)
- [Grafana Mimir architecture](https://grafana.com/docs/mimir/latest/get-started/about-grafana-mimir-architecture/)
- [Ingest storage architecture](https://grafana.com/docs/mimir/latest/get-started/about-grafana-mimir-architecture/about-ingest-storage-architecture/)
- [Deployment modes](https://grafana.com/docs/mimir/latest/references/architecture/deployment-modes/)
- [Mimir components](https://grafana.com/docs/mimir/latest/references/architecture/components/)
- [Hash rings](https://grafana.com/docs/mimir/latest/references/architecture/hash-ring/)
- [Bucket index](https://grafana.com/docs/mimir/latest/references/architecture/bucket-index/)
- [Mimir Query Engine](https://grafana.com/docs/mimir/latest/references/architecture/mimir-query-engine/)

### Configuration và operations

- [Configure Mimir](https://grafana.com/docs/mimir/latest/configure/)
- [Kafka backend](https://grafana.com/docs/mimir/latest/configure/configure-kafka-backend/)
- [Object storage](https://grafana.com/docs/mimir/latest/configure/configure-object-storage-backend/)
- [Metrics retention](https://grafana.com/docs/mimir/latest/configure/configure-metrics-storage-retention/)
- [Runtime configuration](https://grafana.com/docs/mimir/latest/configure/about-runtime-configuration/)
- [Shuffle sharding](https://grafana.com/docs/mimir/latest/configure/configure-shuffle-sharding/)
- [Zone-aware replication](https://grafana.com/docs/mimir/latest/configure/configure-zone-aware-replication/)
- [Capacity planning](https://grafana.com/docs/mimir/latest/manage/run-production-environment/planning-capacity/)
- [Hardware requirements](https://grafana.com/docs/mimir/latest/set-up/hardware-requirements/)
- [Mimir dashboards và alerts](https://grafana.com/docs/mimir/latest/manage/monitor-grafana-mimir/installing-dashboards-and-alerts/)
- [Mimir runbooks](https://grafana.com/docs/mimir/latest/manage/mimir-runbooks/)
- [Authentication và authorization](https://grafana.com/docs/mimir/latest/manage/secure/authentication-and-authorization/)

### Chủ đề tiếp theo

Sau Grafana Mimir, chủ đề mở rộng tiếp theo là:

> [**Telemetry Governance & FinOps – ownership, data contracts, cardinality budgets,
> retention, chargeback/showback, privacy và cost controls cho
> observability.**](telemetry_governance_finops.md)

---

*Cập nhật lần cuối: 2026-07-30*
