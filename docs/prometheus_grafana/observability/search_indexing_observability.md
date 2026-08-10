---
title: "Search & Indexing Observability – Từ Source Event đến Relevant Result"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 7
---
# Search & Indexing Observability – Từ Source Event đến Relevant Result

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là quan sát toàn bộ search lifecycle: dữ liệu nguồn được ingest,
> analyze, index, refresh, merge và phân phối tới shard; query được parse, fan-out, rank rồi
> trả kết quả đúng, mới, liên quan và an toàn cho người dùng.
>
> Baseline tham chiếu: OpenTelemetry Semantic Conventions 1.43 cho database/Elasticsearch,
> Elastic monitoring/production guidance và OpenSearch monitoring, Performance Analyzer,
> Query Insights hiện hành. Elasticsearch conventions đang ở trạng thái Development nên phải
> pin schema, đặc biệt trước khi thu query text.
>
> Search query, document, field, index và click event có thể chứa PII, secret hoặc dữ liệu
> tenant. Không ghi raw query/document mặc định; dùng fingerprint/template, redaction,
> sampling, access control và retention phù hợp.
>
> Nên đọc trước:
> [Storage & Object Storage Observability](storage_object_storage_observability.md),
> [Data Pipeline & ETL Observability](data_pipeline_etl_observability.md),
> [Business & Product Observability](business_product_observability.md) và
> [Elasticsearch architecture](../../elasticsearch/fundamentals/architecture.md).

---

## 1. Cluster xanh nhưng search vẫn có thể hỏng

Shard được allocate không chứng minh:

- document mới đã searchable;
- analyzer/mapping đúng;
- kết quả có liên quan;
- user chỉ thấy tài liệu được phép;
- zero-result rate bình thường;
- query p99 trong SLO;
- vector/embedding cùng version.

Search observability phải nối system health với result quality.

## 2. Hai plane: indexing và search

```text
source → ingest/indexing plane → index/segments
user   → query/search plane   → rank/results
```

Indexing khỏe nhưng query lỗi, hoặc query nhanh trên index stale, đều là incident. Dashboard
phải hiển thị hai plane và điểm hội tụ freshness.

## 3. Lifecycle end-to-end

```text
change event → transform → analyze → write primary
             → replicate → refresh/visible → query
             → retrieve → rank → render → outcome
```

Mỗi stage có timestamp/version/outcome để tìm lag và mismatch.

## 4. Năm mục tiêu

1. **Availability:** query/index được phục vụ.
2. **Performance:** latency/throughput trong SLO.
3. **Freshness:** source change xuất hiện đúng hạn.
4. **Correctness/security:** đúng document/quyền.
5. **Relevance/product outcome:** kết quả hữu ích.

Không gộp thành một “cluster health”.

## 5. Identity contract

Dimension bounded:

- cluster/service;
- index/data-stream alias class;
- operation/query type;
- source/pipeline;
- schema/analyzer/model version;
- region/tier;
- outcome/reason.

Document/query/user/tenant ID là chi tiết event/trace, không phải metric label mặc định.

## 6. SLI và SLO

Ví dụ:

```text
good search =
  response successful
  ∧ latency ≤ 500 ms
  ∧ index freshness ≤ 2 min
  ∧ authorization correct
```

Performance, freshness, correctness và relevance thường cần SLI riêng vì measurement/owner/
window khác nhau.

## 7. Source lineage

Truy được:

```text
source record/version → pipeline run
→ index/document version → searchable timestamp
```

Không dùng search index làm source of truth nếu kiến trúc không cam kết. Reconciliation cần
source ID/version nhưng phải giữ ngoài metric cardinality cao.

## 8. Indexing pipeline

Theo dõi extract/transform/enrich/analyze/bulk/write/retry/DLQ:

- records/bytes;
- duration;
- success/reject;
- lag;
- schema error;
- version conflict;
- retry amplification;
- data loss/duplicate.

Pipeline “completed” chưa chứng minh document visible.

## 9. Ingest rate

Tách offered, accepted, indexed và visible rate:

```text
offered ≥ accepted ≥ indexed ≥ visible
```

Chênh lệch là queue/retry/reject/refresh lag. Đếm logical document riêng attempt.

## 10. Backpressure

Khi cluster index chậm, producer phải nhận tín hiệu qua bounded queue, rate limit hoặc retry
with backoff. Nếu không, memory/DLQ tăng hoặc retry storm.

Theo dõi oldest event age, queue depth, rejected bulk, retry delay và source retention headroom.

## 11. Bulk indexing

Batch lớn giảm overhead nhưng tăng latency, memory và retry blast radius. Theo dõi batch docs/
bytes, duration, partial failure, rejected item và retry.

Retry chỉ item thất bại với idempotency/version semantics; retry toàn bulk dễ duplicate work.

## 12. Mapping và schema

Quan sát mapping update, rejected document, dynamic-field growth, field count, type conflict
và schema version.

Dynamic mapping không kiểm soát có thể tạo mapping explosion. Validate contract trước ingest và
alert field/cardinality growth.

## 13. Analyzer

Analyzer gồm tokenizer + filters ở index/search time. Version hóa language, stopword, synonym,
stemming/normalization và test token output.

Index analyzer và search analyzer không tương thích làm relevance xấu dù request 200. Change
analyzer thường cần reindex.

## 14. Data quality

Kiểm tra:

- completeness;
- duplicate/missing document;
- field validity;
- source-index count/hash;
- tombstone/delete;
- authorization field;
- language/encoding;
- distribution.

Searchable dữ liệu sai là correctness incident.

## 15. Freshness

```text
freshness =
  searchable_at - source_changed_at
```

Phân rã source queue, transform, bulk, primary, replication và refresh. Dùng event-time,
watermark và percentile; max age hữu ích cho long tail.

## 16. Refresh và visibility

Refresh làm segment mới visible cho search; không đồng nghĩa durable commit hoặc merge. Refresh
quá thường tăng overhead, quá thưa tăng freshness.

Theo dõi refresh time/count, pending work và source→visible synthetic canary. Không gọi
`refresh=true` trên mọi write để che thiết kế freshness.

## 17. Durability, translog và commit

Search engine có journal/translog và segment commit semantics riêng. ACK write, replicated,
refreshed/searchable và persisted-to-stable-state là các mốc khác nhau.

Pin durability/replica setting; instrument application expectation thay vì suy từ HTTP status.

## 18. Shard là đơn vị scale và failure

Shard quyết định placement, fan-out, recovery và segment. Theo dõi primary/replica state,
docs/bytes, operations, latency và allocation reason.

Shard ID có thể bounded trong cluster nhưng tạo nhiều series; chỉ export khi có budget và
retention.

## 19. Primary và replica

Index thường ghi primary rồi replicate theo policy; search có thể chạy trên nhiều copy. Theo dõi
in-sync/active replica, replication lag, stale/recovery và read preference.

Replica tăng read capacity/durability nhưng tăng write, disk và merge cost.

## 20. Green/yellow/red chưa đủ

Elastic cluster health:

- green: primary và replica allocated;
- yellow: primary có, replica thiếu;
- red: một số primary chưa allocated.

Green không nói latency, freshness, relevance hoặc disk headroom. Yellow có thể vẫn phục vụ
nhưng mất failure tolerance.

## 21. Allocation và recovery

Theo dõi unassigned reason, relocating/initializing shard, recovery stage, bytes/files,
throughput, ETA và throttle.

Rebalance/recovery cạnh traffic có thể làm p99 xấu. Giới hạn concurrency theo SLO và failure
headroom.

## 22. Shard count và size

Quá nhiều shard nhỏ tăng cluster state, heap/file descriptor và fan-out; shard quá lớn làm
recovery/merge chậm.

Không có một kích thước đúng cho mọi workload. Benchmark query/index/recovery và capacity theo
data/mapping/hardware thực.

## 23. Skew và hot shard

Routing key, time partition hoặc tenant lớn gây skew. So docs/bytes/QPS/CPU/latency theo shard
với distribution.

Hot shard không giải quyết bằng thêm node nếu routing vẫn dồn cùng shard. Cần routing/index
design hoặc workload isolation.

## 24. Segment

Lucene-style index gồm immutable segments; refresh tạo segment, merge hợp nhất. Theo dõi segment
count/size, memory, open files và distribution.

Nhiều segment nhỏ tăng search overhead; merge xử lý chúng nhưng tiêu tốn I/O/CPU.

## 25. Merge

Theo dõi merge count/time/current, bytes/docs, throttle và disk temporary space. Merge backlog
có thể làm indexing chậm và disk phình.

Tách merge foreground impact bằng trace/query latency và device I/O.

## 26. Force merge

Force merge là operation nặng, phù hợp chủ yếu cho index không còn ghi theo hướng dẫn sản phẩm
cụ thể. Không dùng định kỳ trên hot index chỉ để giảm segment.

Ghi actor/index/target, estimated temporary disk, duration, abort/rollback limitation và SLO.

## 27. Delete và tombstone

Delete thường đánh dấu trước khi merge reclaim bytes. Theo dõi deleted docs ratio, delete lag,
merge reclaim và source-index reconciliation.

Disk không giảm ngay sau delete là hành vi có thể bình thường; capacity plan phải tính delayed
reclaim.

## 28. Disk watermark và headroom

Search cluster cần free disk cho merge, recovery, relocation, snapshot và growth. Alert trước
write block/watermark.

Headroom theo node/tier/failure scenario, không chỉ cluster average. Một node đầy có thể gây
allocation loop dù tổng còn nhiều.

## 29. Heap và GC

Theo dõi heap used/pressure, allocation rate, GC pause/frequency, circuit breaker, cache và
off-heap/page cache.

“Heap còn trống” không chứng minh đủ capacity; request aggregation/vector có thể tạo burst.
Correlation với query shape và shard fan-out.

## 30. Cache

Query/request/fielddata/page cache có semantics khác. Đo hit/miss, eviction, bytes, build/fill
cost và result correctness.

Hit rate thấp có thể bình thường với query unique; cache lớn có thể cướp heap. Không tối ưu hit
rate đơn lẻ.

## 31. Thread pool, queue và rejection

Theo dõi active/queue/completed/rejected theo search/write/management pool. Queue hấp thụ burst
nhưng tăng latency; rejected sớm có thể bảo vệ cluster.

Client retry cần backoff/jitter và budget; 429 bị retry tức thì tạo feedback loop.

## 32. Search request lifecycle

```text
parse/rewrite → route/fan-out → shard query
→ collect/aggregate → fetch → reduce/rank → serialize
```

Profile/sample từng phase khi cần; profiling mọi query production có overhead.

## 33. Query taxonomy

Phân loại bounded:

- exact/filter;
- full text;
- aggregation;
- autocomplete;
- wildcard/regex;
- geo;
- vector/kNN;
- hybrid;
- admin.

Mỗi loại có SLO và cost profile khác. Không trộn trong một latency histogram duy nhất.

## 34. Latency decomposition

Đo client queue/network, coordinating node, shard query/fetch/reduce, downstream rendering.

```text
end-to-end p99 ≠ tổng p99 từng phase
```

Dùng trace/exemplar cho request mẫu và histogram aggregate.

## 35. Tail latency và fan-out

Query tới nhiều shard bị ảnh hưởng bởi slowest participant. Over-sharding làm tăng xác suất
tail dù mỗi shard nhanh trung bình.

Theo dõi shards requested/successful/skipped/failed, slow shard và partial result semantics.

## 36. Timeout và cancellation

Timeout client không tự hủy server work. Propagate deadline/cancel, theo dõi timed-out/cancelled
task và orphan work.

Phân biệt partial result, timeout và complete result. Không tính partial như success nếu user
contract yêu cầu đầy đủ.

## 37. Slow/top query

Slow log hoặc Query Insights giúp tìm query latency/CPU/memory cao. Dùng sampling/top-N,
retention và access control vì query source nhạy cảm.

Elastic khuyên monitoring production ở cluster riêng để outage search không làm mất công cụ
điều tra và monitoring không cạnh tranh workload.

## 38. Query fingerprint

Normalize cấu trúc:

```text
term(value) + range(value) → term(?) + range(?)
```

Fingerprint/template bounded giúp aggregate query shape mà không lưu literal. Version algorithm
và kiểm tra collision.

## 39. OpenTelemetry Elasticsearch conventions

OTel 1.43 định nghĩa Elasticsearch client operation trên database conventions; status hiện
Development. Các field như `db.operation.name`, `db.collection.name`, response status và
query text có semantics cụ thể.

Pin version; không bật `db.query.text` mặc định nếu chưa redact và đánh giá payload/cardinality.

## 40. Query privacy và security

Query có thể chứa email, token, medical/legal text hoặc document ID. URL cũng có thể chứa
query/credential.

Allowlist operation/fingerprint, redact literal, sample, encrypt và audit. Không đưa raw query
vào alert/chat.

## 41. Result count và zero-result

Theo dõi result-count bucket, zero-result rate, partial/failure và abandonment theo query class/
language/product area.

Zero result có thể hợp lệ với rare query; baseline theo cohort và data freshness. Spike có thể
do analyzer, ingest, filter hoặc inventory.

## 42. Relevance

Relevance hỏi kết quả hữu ích, không chỉ nhanh. Signal:

- click/selection;
- reformulation;
- abandonment;
- successful downstream outcome;
- human judgment;
- explicit feedback.

Các signal có bias; không dùng click-through đơn lẻ làm truth.

## 43. Offline evaluation

Dataset gồm query, candidate corpus, relevance judgment và version. Metric phổ biến:

- precision/recall;
- MRR;
- MAP;
- nDCG;
- hit rate.

Ghi k, aggregation, segment và confidence. Dataset phải đại diện/được governance.

## 44. Online evaluation

A/B/interleaving/canary đo outcome thật với assignment/exposure, guardrail và sample-ratio
check. Theo dõi latency/error/cost cùng relevance.

Không phát hành ranking chỉ vì offline score tốt; distribution/user behavior khác.

## 45. Position và selection bias

Result ở vị trí cao được click nhiều hơn dù relevance tương đương. Logging policy/rank/position
giúp phân tích nhưng tăng privacy.

Dùng experiment hoặc debias method phù hợp; tương quan click không tự là causal relevance.

## 46. Correctness và authorization

Search index có thể stale permission hoặc thiếu tenant filter. Test invariant:

- không trả tài liệu ngoài scope;
- delete/revocation hội tụ trong SLO;
- field masking đúng;
- source/index version tương thích.

Security filter không được chỉ thực thi ở UI.

## 47. Aggregation

Aggregation có thể fan-out lớn, dùng heap/CPU và tạo circuit breaker. Theo dõi bucket count,
memory, execution, cache và rejection theo fingerprint.

Giới hạn size/cardinality, pagination/composite aggregation và workload class. Không cho
dashboard tự do quét toàn cluster.

## 48. Autocomplete/typeahead

SLI cần latency rất thấp, prefix coverage, zero-result, stale suggestion và safety filter.
Theo dõi keystroke sequence dạng aggregate/fingerprint, không raw input mặc định.

Cache/precompute tăng tốc nhưng cần freshness và invalidation.

## 49. Vector search

Ngoài query latency:

- embedding model/version;
- vector dimension;
- index build;
- memory/disk;
- graph/list probe setting;
- candidate count;
- approximate recall;
- filter interaction.

ANN nhanh hơn có thể giảm recall; luôn giữ quality guardrail.

## 50. Embedding pipeline

Theo dõi source changed → embedding generated → indexed → searchable:

- queue/freshness;
- model/provider;
- batch;
- error/retry;
- dimension mismatch;
- duplicate/missing vector;
- cost.

Document text và embedding đều có privacy/residency concern.

## 51. Vector quality

Đánh giá recall@k so exact/curated baseline trên sample, nDCG/MRR/outcome và latency/cost.

Index parameter change hoặc quantization cần version/canary. Approximate algorithm không có một
“accuracy” duy nhất cho mọi corpus.

## 52. Hybrid search

Lexical + vector cần candidate generation, normalization/fusion/rerank version. Theo dõi đóng
góp từng channel, candidate overlap, latency và fallback.

Nếu embedding service lỗi, fallback lexical phải được đánh dấu, không tính success như hybrid
bình thường.

## 53. Pagination

Deep offset pagination tốn công và kết quả có thể đổi khi index refresh. Ưu tiên cursor/
search-after/point-in-time theo product semantics.

Theo dõi depth, abandoned page, token expiry, consistency và cost. Cursor/token không được log
nguyên nếu chứa state nhạy cảm.

## 54. Sorting và scoring

Custom script/sort/score có thể đắt. Theo dõi fingerprint, CPU/memory, cache, timeout và
relevance. Stable tie-breaker giúp pagination deterministic.

Không sort field thiếu doc values/structure phù hợp mà không benchmark.

## 55. Multi-tenancy

Tenant có thể dùng index riêng, routing hoặc shared index/filter. Quan sát isolation, hot
tenant, shard skew, quota, query fairness và authorization.

Không dùng tenant ID không giới hạn làm Prometheus label. Dùng heavy hitter/on-demand trace và
policy-scoped query.

## 56. Schema change và reindex

Reindex state:

```text
plan → build target → backfill → catch up
→ validate → alias cutover → monitor → retire old
```

Theo dõi docs/bytes/rate/ETA, mismatch, throttling, disk, dual-write lag và rollback. Cần
headroom giữ hai index.

## 57. Snapshot và restore

Snapshot không tự chứng minh restore. Theo dõi coverage, incremental bytes, repository health,
duration/failure và retention.

Restore drill xác minh cluster version/plugin/analyzer/model, aliases, security và query
correctness/relevance, không chỉ shard green.

## 58. Cost

Driver:

- storage/replica;
- indexing CPU/I/O;
- search CPU/heap;
- merge/recovery;
- snapshots/egress;
- vector memory/build;
- monitoring/query insights;
- over-sharding.

Đo cost per indexed document và successful useful search kèm freshness/relevance guardrail.

## 59. Dashboard

Các tầng:

1. user search SLI/outcome;
2. freshness/data quality;
3. query performance/rejection;
4. indexing/backpressure;
5. shard/segment/allocation;
6. JVM/disk/I/O;
7. relevance/vector quality;
8. capacity/cost.

Overlay release, mapping/model/reindex và node failure.

## 60. Alerting

Page khi:

- search SLO burn/rejection;
- freshness vượt SLO;
- security/correctness invariant fail;
- primary unavailable/data loss risk;
- disk below recovery/merge headroom;
- indexing queue/retry runaway;
- cluster state/GC/merge critical;
- zero-result collapse có quality evidence.

Không page chỉ vì yellow nếu policy/impact chưa phân loại.

## 61. Incident workflow

1. xác định query/index/cohort/impact;
2. kiểm tra freshness/correctness trước performance;
3. dừng reindex/merge/rollout nếu cần;
4. throttle expensive workload;
5. bảo vệ source/snapshot;
6. rollback alias/model/mapping khi an toàn;
7. verify relevance và authorization;
8. reconcile source-index.

## 62. Load và chaos test

Test:

- query mix + indexing đồng thời;
- node/shard failure;
- disk watermark;
- slow storage;
- merge/recovery contention;
- malformed/mapping explosion;
- hot shard/tenant;
- vector build;
- snapshot restore;
- monitoring plane failure.

Abort theo SLO, corruption và cost.

## 63. Governance

Catalog:

- index/alias owner;
- source/schema/analyzer;
- model/ranking;
- freshness/SLO;
- retention/residency;
- authorization;
- shard/replica/tier;
- snapshot/RPO/RTO;
- cost;
- deprecation.

Query logging và relevance datasets cần privacy/access review.

## 64. Workshop, checklist và câu hỏi tự kiểm tra

Workshop: ingest synthetic corpus, đo source→searchable, chạy query set lexical/vector, tạo hot
shard và node failure, rồi reindex/cutover/restore với quality checks.

- [ ] Indexing và query plane tách?
- [ ] Freshness từ source event tới visible?
- [ ] Logical docs khác attempts?
- [ ] Shard/segment/merge/disk headroom?
- [ ] Query fingerprint thay raw text?
- [ ] Zero-result có baseline/data-quality guard?
- [ ] Relevance offline + online?
- [ ] Authorization/delete hội tụ được test?
- [ ] Snapshot restore cùng analyzer/model?

Câu hỏi:

1. Green cluster còn có thể trả search sai thế nào?
2. Refresh, durability và merge khác nhau ra sao?
3. Over-sharding làm p99 tăng vì sao?
4. Zero-result spike có những nguyên nhân nào?
5. Click-through bị bias thế nào?
6. Vector search phải cân bằng latency và recall ra sao?
7. Reindex cutover cần những bước validation nào?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Telemetry và monitoring

- [OpenTelemetry database conventions](https://opentelemetry.io/docs/specs/semconv/db/)
- [OpenTelemetry Elasticsearch conventions](https://opentelemetry.io/docs/specs/semconv/db/elasticsearch/)
- [Elastic monitoring](https://www.elastic.co/docs/deploy-manage/monitor)
- [Elastic performance guidance](https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance)

### OpenSearch

- [OpenSearch cluster monitoring](https://docs.opensearch.org/latest/monitoring-your-cluster/)
- [OpenSearch Performance Analyzer](https://docs.opensearch.org/latest/monitoring-your-cluster/pa/index/)
- [OpenSearch Query Insights](https://docs.opensearch.org/latest/observing-your-data/query-insights/index/)

Chủ đề tiếp theo gợi ý:
**Edge, CDN & Media Delivery Observability** – cache hierarchy, origin shielding, purge,
regional performance, streaming QoE, bitrate, rebuffering và delivery cost.

---

*Cập nhật lần cuối: 2026-07-30*
