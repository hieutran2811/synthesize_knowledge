# Elasticsearch – Tổng hợp kiến thức

> Trang này là bản đồ tra cứu. Mỗi bài con đi từ mental model đến failure mode,
> runbook và câu hỏi phỏng vấn thay vì chỉ liệt kê API.

**Phiên bản mục tiêu:** Elasticsearch 9.4

**Trạng thái chuẩn hóa:** 7/7 chủ đề – hoàn thành (2026-07-31)

---

## 1. Elasticsearch trong một câu

Elasticsearch là search và analytics engine phân tán xây trên Apache Lucene:

```text
JSON document
    ↓ mapping + analysis
term/vector/doc values
    ↓
Lucene segments trong shard
    ↓
distributed query + fetch / aggregation
    ↓
search response
```

Elasticsearch thường phù hợp làm search/read model. Nếu dữ liệu nghiệp vụ gốc nằm
ở database hoặc event log, hệ thống nên có khả năng rebuild index và reconcile.

---

## 2. Bản đồ chủ đề

| Lớp | Chủ đề | Câu hỏi phải trả lời |
|---|---|---|
| Nền tảng | [Architecture](fundamentals/architecture.md) | Document nằm ở shard nào, write/read chạy ra sao và cluster hỏng thế nào? |
| Nền tảng | [Indexing & Mapping](fundamentals/indexing_mapping.md) | JSON được biến thành term/field nào và mapping được version thế nào? |
| Truy vấn | [Query DSL](fundamentals/query_dsl.md) | Filter, scoring, pagination và search consistency hoạt động ra sao? |
| Phân tích | [Aggregations](advanced/aggregations.md) | Bucket/metric được tính ở từng shard và reduce thế nào? |
| Hiệu năng | [Optimization](performance/optimization.md) | Bottleneck nằm ở shard, query, heap, CPU, disk hay workload model? |
| Vận hành | [Cluster Management](operations/cluster_management.md) | Allocation, recovery, snapshot và rolling upgrade được chạy thế nào? |
| Bảo mật | [Security](operations/security.md) | Ai được tìm/ghi/quản lý dữ liệu nào và kết nối được bảo vệ ra sao? |

---

## 3. Chuỗi phụ thuộc quan trọng

```text
Mapping/analyzer
      │
      ├──► term được lưu ──► query match gì ──► relevance
      │
      └──► field structure ─► aggregation/sort memory

Shard strategy
      │
      ├──► indexing parallelism + merge
      ├──► search fan-out + tail latency
      └──► recovery time + availability

Replica/failure domains
      │
      ├──► write cost
      ├──► read capacity
      └──► node/zone failure behavior
```

Vì vậy không thể tối ưu query độc lập với mapping và shard design.

---

## 4. Chọn đúng công cụ

| Nhu cầu | Elasticsearch phù hợp? | Ghi chú |
|---|---:|---|
| Full-text relevance, autocomplete, faceting | Có | Thế mạnh cốt lõi |
| Filter/aggregation gần real-time | Có | Cần mapping và capacity đúng |
| Vector/hybrid search | Có | Benchmark model, dimension, recall và latency |
| Transaction nhiều record với constraint mạnh | Không phải lựa chọn chính | Giữ database giao dịch làm source of truth |
| Join tùy ý như relational database | Không tối ưu | Thường denormalize khi index |
| Queue/event log bền vững | Không | Dùng Kafka/RabbitMQ phù hợp hơn |
| Backup duy nhất bằng replica | Không | Cần snapshot hoặc nguồn rebuild |

---

## 5. Tra cứu theo triệu chứng

| Triệu chứng | Đọc trước | Điểm kiểm tra |
|---|---|---|
| Write thành công nhưng search chưa thấy | [Architecture §8–9](fundamentals/architecture.md) | Refresh visibility, `refresh=wait_for`, real-time GET |
| Cluster yellow một node | [Architecture §12, §22](fundamentals/architecture.md) | Replica không thể cùng node với primary |
| Cluster red | [Architecture §12, §23](fundamentals/architecture.md) | Primary unassigned, allocation explain, valid copy/snapshot |
| Heap cao dù data ít | [Architecture §13, §18](fundamentals/architecture.md) | Oversharding, field/mapping explosion |
| Search p99 cao | [Architecture §11, §22–23](fundamentals/architecture.md) | Fan-out, slow shard, deep pagination, merge/recovery |
| Tenant lớn làm cluster nóng | [Architecture §6, §13](fundamentals/architecture.md) | Custom routing và hot shard |
| Reindex bị mất write mới | [Architecture §19](fundamentals/architecture.md) | Alias chỉ atomic lúc switch, cần CDC/dual-write/checkpoint |
| Đĩa đầy rồi index read-only | [Architecture §14](fundamentals/architecture.md) | Disk watermarks và flood-stage block |
| Query không match như mong đợi | [Indexing & Mapping §4, §11–14](fundamentals/indexing_mapping.md) | `text`/`keyword`, index/search analyzer, dấu tiếng Việt |
| Aggregate thiếu một số chuỗi dài | [Indexing & Mapping §4](fundamentals/indexing_mapping.md) | `ignore_above`, `_ignored`, giới hạn keyword term |
| Filter mảng object trả false positive | [Indexing & Mapping §7](fundamentals/indexing_mapping.md) | `object` làm mất quan hệ; cân nhắc `nested` |
| Heap/cluster state tăng theo field | [Indexing & Mapping §10](fundamentals/indexing_mapping.md) | Dynamic key và mapping explosion |
| Bulk HTTP 200 nhưng thiếu document | [Indexing & Mapping §25](fundamentals/indexing_mapping.md) | Parse từng item, retry/DLQ và reconciliation |
| Reindex mất write phát sinh | [Indexing & Mapping §27](fundamentals/indexing_mapping.md) | Checkpoint, CDC/dual-write và alias switch |
| `should` không còn bắt buộc sau khi thêm filter | [Query DSL §13](fundamentals/query_dsl.md) | Default `minimum_should_match` đổi từ 1 thành 0 |
| Wildcard/fuzzy làm search p99 tăng | [Query DSL §12, §32](fundamentals/query_dsl.md) | Term expansion và expensive-query guardrail |
| Pagination sâu chậm/OOM | [Query DSL §21–23](fundamentals/query_dsl.md) | PIT + `search_after`, tránh `from` quá lớn |
| Trang sau bị trùng hoặc thiếu hit | [Query DSL §22–23, §33](fundamentals/query_dsl.md) | Unique tie-breaker, refresh và PIT |
| HTTP 200 nhưng search thiếu dữ liệu | [Query DSL §33](fundamentals/query_dsl.md) | Timeout, shard failure và partial-result policy |
| Exact result count làm query chậm | [Query DSL §24](fundamentals/query_dsl.md) | Chọn ngưỡng `track_total_hits` theo use case |
| Top category/revenue đổi khi đổi số shard | [Aggregations §11–12](advanced/aggregations.md) | Candidate theo shard, `shard_size`, cách sort và doc-count error |
| Unique customer lệch số exact trong database | [Aggregations §8](advanced/aggregations.md) | `cardinality` dùng HyperLogLog++ và là giá trị xấp xỉ |
| Composite export bị trùng hoặc thiếu bucket | [Aggregations §19](advanced/aggregations.md) | Dùng đúng `after_key` từ response và giữ query nhất quán |
| `bucket_sort` không cho global top-N đúng | [Aggregations §23](advanced/aggregations.md) | Pipeline chỉ sort bucket mà parent đã trả về |
| Aggregation làm circuit breaker | [Aggregations §3, §27](advanced/aggregations.md) | Tích số bucket, reduce memory và `search.max_buckets` |
| Daily bucket lệch timezone/DST | [Aggregations §14](advanced/aggregations.md) | `calendar_interval`, `fixed_interval`, `time_zone` và bounds |
| Bulk trả 429 khi tăng worker | [Performance §6–7, §22](performance/optimization.md) | Bulk size, concurrency, indexing pressure và backoff có jitter |
| Search p99 cao nhưng CPU thấp | [Performance §4–5, §16, §30](performance/optimization.md) | Queue, disk latency, page-cache miss, network và slow shard |
| Tăng heap nhưng search chậm hơn | [Performance §16, §21](performance/optimization.md) | Heap cạnh tranh filesystem cache; xác định object giữ heap trước |
| Một node nóng hơn các node cùng tier | [Performance §19, §23, §30](performance/optimization.md) | Routing/shard skew, coordinator hotspot và phần cứng không đều |
| Cache hit thấp sau mỗi refresh | [Performance §15](performance/optimization.md) | Request-cache invalidation, query chứa `now` và query cardinality |
| Đổi setting nhanh hơn nhưng mất durability | [Performance §8, §29](performance/optimization.md) | Refresh, replica và translog là ba trade-off semantics khác nhau |
| Replica unassigned dù còn nhiều disk | [Cluster Management §6–8, §27](operations/cluster_management.md) | Allocation decider, tier/filter, awareness và số failure domain |
| Index bị block write vì flood-stage | [Cluster Management §9–10](operations/cluster_management.md) | Giảm ingest, giải phóng/tăng disk và chờ xuống dưới high watermark |
| ILM đứng ở một step | [Cluster Management §13–14](operations/cluster_management.md) | Tier capacity, rollover alias/data stream, shrink prerequisite và retry |
| Snapshot thành công nhưng DR thiếu cấu hình | [Cluster Management §17–19](operations/cluster_management.md) | Coverage, global state, feature state và restore drill |
| Node mới không join khi rolling upgrade | [Cluster Management §21–24](operations/cluster_management.md) | Thứ tự version, plugin/config/TLS và master phải nâng cuối |
| Red vì không còn valid primary copy | [Cluster Management §28–29](operations/cluster_management.md) | Audit in-sync copy/snapshot/source trước thao tác chấp nhận mất dữ liệu |
| Master thay đổi liên tục | [Cluster Management §3, §26, §30](operations/cluster_management.md) | Voting majority, GC/network và cluster-state publication |
| Request trả 401 sau rotation | [Security §17–19, §33](operations/security.md) | Key expiry/invalidation, secret version, realm và proxy header |
| Request authenticate được nhưng trả 403 | [Security §12–15, §33](operations/security.md) | Effective role union, index pattern và privilege tối thiểu của API |
| Tenant đọc được dữ liệu tenant khác | [Security §21–24](operations/security.md) | Role không DLS chồng lên, backing-index access và isolation model |
| Kibana Space vẫn thấy index ngoài phạm vi | [Security §16](operations/security.md) | Space privilege không tự thu hẹp Elasticsearch index privilege |
| Node/client chỉ kết nối khi tắt verify TLS | [Security §3–6, §34](operations/security.md) | SAN, CA/chain, endpoint, clock và trust overlap khi rotation |
| API key bị lộ | [Security §17–19, §35](operations/security.md) | Invalidate, audit blast radius, rotate và sửa nguồn leak |
| Audit không còn sự kiện | [Security §30–32](operations/security.md) | Audit setting từng node, log shipping, subscription và pipeline silence |

---

## 6. Mental model production

Một request đi qua nhiều correctness boundary:

```text
Client
  │ authn/authz
  ▼
Coordinating stage
  │ routing
  ▼
Primary shard ──► in-sync replicas
  │ translog / segment / refresh
  ▼
Searchable shard copies
  │ scatter/gather
  ▼
Merged response
```

Khi debug, xác định đang lỗi ở boundary nào:

1. client/security;
2. routing/coordinator;
3. primary/replication;
4. refresh/segment/merge;
5. shard allocation/recovery;
6. query/fetch/reduce.

---

## 7. Nguyên tắc xuyên suốt

1. **Đo bằng workload thật** – shard size, replica count và refresh interval không
   có một giá trị đúng cho mọi hệ thống.
2. **Version mọi thứ có semantic** – mapping, analyzer, index template và query
   contract cần đi cùng release.
3. **Replica không thay snapshot** – HA và backup giải quyết hai failure mode khác nhau.
4. **Search visibility không phải durability** – refresh khác translog fsync/flush.
5. **Tính cả failure capacity** – cluster phải đạt SLO khi mất node/zone, không chỉ
   khi mọi thứ xanh.
6. **Giữ cluster state có kiểm soát** – tránh index-per-tenant và field động vô hạn.
7. **Rebuild được search projection** – có checkpoint, idempotency và reconciliation.
8. **Least privilege mặc định** – application không cần quyền quản trị cluster.

---

## 8. Lộ trình học

```text
Tuần 1: architecture + lab 3 node
Tuần 2: mapping/analyzer + reindex bằng alias
Tuần 3: Query DSL + PIT/search_after
Tuần 4: aggregations + profile/benchmark
Tuần 5: shard/capacity/performance
Tuần 6: snapshot/restore + failure drill + security
```

Lab quan trọng hơn việc nhớ API:

- làm cluster từ green → yellow → green;
- tạo mapping sai, sửa bằng versioned index + alias;
- đo search trước/sau refresh;
- benchmark một query trên ít shard và oversharded index;
- restore snapshot sang cluster thử nghiệm;
- chạy application bằng role chỉ có đúng index privilege cần thiết.

---

## 9. Nguồn chính thức

- [Elastic documentation](https://www.elastic.co/docs)
- [Elasticsearch reference](https://www.elastic.co/docs/reference/elasticsearch)
- [Elastic release notes](https://www.elastic.co/docs/release-notes)
- [Roadmap nội bộ](roadmap.md)

---

*Cập nhật lần cuối: 2026-07-31.*
