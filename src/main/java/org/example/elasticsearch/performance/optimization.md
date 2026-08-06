# Elasticsearch Performance & Optimization – đo đúng trước khi tuning

> Elasticsearch không có một bộ “best settings” dùng cho mọi hệ thống. Cùng một
> cluster có thể đạt indexing throughput rất cao nhưng search p99 tệ, hoặc search
> nhanh khi cache nóng nhưng sụp khi node restart. Tối ưu đúng nghĩa là đạt SLO
> của workload thật với chi phí chấp nhận được, đồng thời giữ đúng durability,
> consistency và khả năng phục hồi.

Tài liệu dùng Elasticsearch 9.4 làm phiên bản tham chiếu. Một số API, giới hạn
và quyền cấu hình khác nhau giữa Elastic Cloud Hosted, ECK, self-managed và
Serverless; luôn kiểm tra deployment đang chạy trước khi áp dụng.

---

## 1. Performance là một hợp đồng, không phải một con số

Trước khi đổi setting, phải viết rõ:

| Nhóm | Ví dụ mục tiêu | Guardrail không được phá |
|---|---|---|
| Search | p95 < 150 ms, p99 < 400 ms ở 300 RPS | Không giảm recall hoặc trả partial result im lặng |
| Indexing | 20.000 document/s | Search visibility dưới 30 giây |
| Aggregation | dashboard p95 < 2 giây | Sai số cardinality/top-N nằm trong ngưỡng đã công bố |
| Availability | chịu mất một node/zone | Không bỏ replica chỉ để benchmark đẹp |
| Recovery | shard phục hồi dưới 20 phút | Không tạo shard lớn vượt khả năng recovery |
| Cost | tối đa N node hoặc X USD/tháng | Không chuyển tải sang hệ thống khác mà không đo tổng chi phí |

Latency phải có percentile và tải đi kèm:

```text
“Query mất 80 ms”                         → thiếu ngữ cảnh
“p95 180 ms, p99 620 ms ở 250 RPS,
 cache ấm, 2% indexing đồng thời”          → có thể đánh giá
```

Average latency che mất tail latency. Một request fan-out tới nhiều shard thường
phải đợi shard chậm nhất, nên p99 quan trọng hơn con số trung bình.

---

## 2. Lập workload matrix

Không benchmark một query rồi suy rộng cho toàn hệ thống.

| Trục | Cần ghi |
|---|---|
| Dữ liệu | số document, byte nguồn, byte index, số field, nested/vector |
| Phân bố | cardinality, skew, hot tenant/key, tỷ lệ update/delete |
| Search | top query template, filter, sort, aggregation, highlight, pagination |
| Tải | RPS, concurrency, burst, read/write mix, giờ cao điểm |
| Freshness | chấp nhận visibility delay bao lâu |
| Correctness | total hit exact hay threshold; aggregation exact hay approximate |
| Hạ tầng | node role, CPU, RAM, heap, disk, network, zone |
| Vòng đời | rollover, retention, tier, merge, recovery, snapshot |

Nên gắn tên hữu hạn cho từng client/query class qua `X-Opaque-Id`:

```http
GET /orders-read/_search
X-Opaque-Id: checkout-order-search

{
  "query": {
    "term": {
      "customer_id": "c-1042"
    }
  }
}
```

Không tạo `X-Opaque-Id` duy nhất cho từng request. Dùng một tập nhãn ổn định để
slow log, task và deprecation log có thể nhóm theo nguồn tải. Trace riêng có thể
đi qua header W3C `traceparent`.

---

## 3. Quy trình benchmark có thể lặp lại

Một vòng thử nghiệm nên có:

```text
1. Giả thuyết
2. Dataset + mapping + shard topology cố định
3. Warm-up
4. Baseline đủ dài
5. Chỉ đổi một biến
6. Đo throughput + latency + saturation + error
7. Kiểm tra correctness/availability
8. Lặp lại nhiều lần
9. Giữ hoặc rollback
```

Ví dụ nhật ký thí nghiệm:

| Trường | Giá trị mẫu |
|---|---|
| Giả thuyết | tăng refresh 1s → 30s giảm merge pressure |
| Workload | 15k doc/s + 100 search RPS |
| Dataset | 500 GB, 12 primary, 1 replica |
| Baseline | ingest 12k/s, search p99 420 ms |
| Guardrail | visibility ≤ 35s, 429 < 0,1% |
| Kết quả | ingest +22%, p99 không đổi, visibility 31s |
| Quyết định | giữ; tự động rollback nếu p99 > 600 ms |

### 3.1 Cache lạnh, cache ấm và steady state

Đo riêng:

- cold start sau restart hoặc page cache chưa ấm;
- warm cache cho traffic lặp lại;
- steady state có refresh, merge, indexing và snapshot như production;
- recovery state khi replica đang đồng bộ hoặc shard đang relocate.

Không dùng một lần chạy ngắn: nó có thể chỉ đo JIT warm-up, page fault hoặc một
đợt merge ngẫu nhiên.

### 3.2 Dùng Rally khi cần benchmark nghiêm túc

[Elastic Rally](https://esrally.readthedocs.io/) giúp version hóa track, corpus,
challenge và metric. Với dữ liệu nhạy cảm, tạo custom track đã khử dữ liệu.

```powershell
# Ví dụ ý tưởng; version track và tham số phải nằm trong source control.
esrally race --track=geonames --challenge=append-no-conflicts
```

Không chạy benchmark phá tải trên cluster production. Nếu buộc phải chạy canary,
giới hạn traffic, có kill switch và quan sát cả tenant khác.

---

## 4. Bản đồ bottleneck

```text
Client
  │ connection pool, retry, serialization, payload
  ▼
Coordinating node
  │ parse, fan-out, merge/reduce, fetch
  ▼
Data node / shard
  │ CPU query, heap bucket, global ordinals
  │ filesystem cache, disk read/write
  ▼
Lucene segment
    postings, BKD, doc values, stored fields, vector graph

Indexing:
client → coordinating → primary → replica → refresh → segment → merge
```

Một triệu chứng không xác định được nguyên nhân:

| Triệu chứng | Có thể là |
|---|---|
| Search p99 cao | slow shard, queue, cache miss, fetch `_source`, GC, network, reduce |
| Indexing chậm | client đơn luồng, bulk quá lớn/nhỏ, 429, refresh, merge, disk |
| Heap cao | aggregation bucket, fielddata, mapping/shard overhead, in-flight request |
| CPU cao | expensive query, ingest script, merge, global ordinals, vector search |
| Disk cao | merge, snapshot/recovery, cache miss, update/delete nhiều |
| Một node nóng | shard/routing skew, hardware lệch, coordinator hotspot |

Vì vậy không “tăng heap” chỉ vì search chậm và không “tăng queue” chỉ vì có 429.

---

## 5. Baseline tối thiểu

Chụp cùng một cửa sổ thời gian trước và sau thay đổi:

```http
GET /_cluster/health
```

```http
GET /_cat/nodes?v=true&s=cpu:desc&h=name,role,master,cpu,load_1m,heap.percent,ram.percent,disk.used_percent
```

```http
GET /_cat/shards?v=true&s=store:desc&h=index,shard,prirep,state,docs,store,node
```

```http
GET /_nodes/stats/os,process,jvm,fs,indices,thread_pool,breaker,indexing_pressure
```

```http
GET /_cat/thread_pool?v=true&h=node_name,name,active,queue,rejected,completed
```

```http
GET /_cluster/pending_tasks
```

Các counter như `rejected`, breaker trip và GC time thường tích lũy từ lúc node
khởi động. So sánh **delta theo thời gian**, không chỉ nhìn số tuyệt đối.

Ở phía client cũng phải đo:

- DNS/TLS/connect time;
- thời gian chờ connection pool;
- request/response byte;
- retry và retry amplification;
- deadline/cancel;
- latency theo query class và status code.

---

## 6. Indexing: tìm kích thước bulk bằng benchmark

Bulk giảm overhead so với gửi từng document, nhưng không có batch size đúng cho
mọi document.

Quy trình:

1. một node, một shard, dataset đại diện;
2. thử 100, 200, 400, 800... document mỗi bulk;
3. dừng tăng khi throughput gần plateau;
4. nếu ngang nhau, chọn batch nhỏ hơn;
5. sau đó tăng worker từ từ đến khi CPU/I/O bão hòa hoặc xuất hiện 429.

```text
POST /_bulk
Content-Type: application/x-ndjson
```

```ndjson
{ "index": { "_index": "orders-write", "_id": "o-1001" } }
{ "customer_id": "c-17", "status": "paid", "amount_minor": 259000, "@timestamp": "2026-07-31T08:30:00Z" }
{ "index": { "_index": "orders-write", "_id": "o-1002" } }
{ "customer_id": "c-18", "status": "pending", "amount_minor": 75000, "@timestamp": "2026-07-31T08:30:01Z" }
```

Bulk là NDJSON: mỗi action/source nằm trên một dòng và payload kết thúc bằng
newline. HTTP 200 không có nghĩa mọi item thành công; phải parse `errors` và từng
item để retry đúng document.

Không giữ công thức cứng như “1.000–5.000 document” hoặc “5–15 MB”. Document lớn,
ingest pipeline, vector và concurrent worker làm memory footprint rất khác nhau.
Tài liệu Elastic khuyên tránh bulk vượt quá vài chục MB ngay cả khi benchmark
đơn lẻ có vẻ nhanh hơn.

---

## 7. Concurrency và backpressure

Một worker thường chưa dùng hết cluster; quá nhiều worker lại làm coordinating,
primary hoặc replica quá tải.

```text
producer rate
    │
    ├── bounded queue
    ├── N workers
    ├── bulk size đã benchmark
    └── 429 → randomized exponential backoff
```

Pseudo-policy:

```text
if HTTP 429:
    retry chỉ item bị reject
    exponential backoff + jitter
    giảm concurrency nếu tỷ lệ 429 duy trì
if timeout/unknown outcome:
    retry phải idempotent hoặc reconcile theo document id/version
if mapping/validation error:
    không retry mù; đưa DLQ và sửa dữ liệu
```

Queue phía producer phải bounded. Queue vô hạn chỉ chuyển backpressure thành OOM
và làm dữ liệu cũ chờ lâu hơn.

Theo dõi:

```http
GET /_nodes/stats?human&filter_path=nodes.*.indexing_pressure
```

```http
GET /_cat/thread_pool/write,write_coordination?v=true&h=node_name,name,active,queue,rejected,completed
```

Từ Elasticsearch 9.1, bulk coordination có `write_coordination` thread pool riêng;
ở version cũ hơn bulk dùng `write`. Dashboard nâng cấp nên hiểu cả hai tên.

---

## 8. Refresh, replica và durability là ba trade-off khác nhau

### 8.1 Refresh interval

Refresh làm document mới searchable và tạo segment mới. Nếu chấp nhận freshness
chậm hơn, tăng interval có thể cải thiện indexing:

```http
PUT /orders-write/_settings

{
  "index": {
    "refresh_interval": "30s"
  }
}
```

Trong initial load không có search:

```http
PUT /orders-v2/_settings

{
  "index": {
    "refresh_interval": "-1"
  }
}
```

Sau load phải khôi phục, refresh và xác minh count:

```http
PUT /orders-v2/_settings

{
  "index": {
    "refresh_interval": "5s"
  }
}
```

```http
POST /orders-v2/_refresh
```

Mặc định hiện nay có tối ưu: index chỉ refresh mỗi giây nếu đã nhận search trong
30 giây gần nhất. Đặt explicit `1s` có thể vô tình bỏ lợi ích này cho workload
chỉ ghi.

### 8.2 Replica

Giảm replica về 0 chỉ phù hợp với initial load có nguồn dữ liệu khác để replay và
chấp nhận mất node phải nạp lại:

```http
PUT /orders-v2/_settings

{
  "index": {
    "number_of_replicas": 0
  }
}
```

Trước khi cutover phải trả replica về policy production và đợi cluster đạt trạng
thái mong muốn. Không áp dụng thủ thuật này cho live write quan trọng.

### 8.3 Translog durability

`index.translog.durability=async` có thể mất acknowledged operation khi crash.
Đây là thay đổi semantics, không phải tuning “miễn phí”. Giữ `request` trừ khi
business đã chấp nhận RPO và có cơ chế replay/reconcile được kiểm thử.

---

## 9. ID, update, mapping và ingest cost

### 9.1 Auto-generated ID

Nếu không cần business ID làm `_id`, auto-generated ID tránh một phần kiểm tra
document đã tồn tại:

```http
POST /orders-write/_doc

{
  "order_id": "o-1001",
  "status": "paid"
}
```

Nếu cần idempotency, explicit `_id` thường đáng giá hơn chút throughput. Không
đổi correctness để lấy benchmark đẹp.

### 9.2 Update không phải in-place

Lucene tạo document mới và đánh dấu bản cũ deleted. Update/delete dày làm tăng:

- segment churn và merge I/O;
- deleted-doc ratio;
- disk tạm thời;
- chi phí lookup theo `_id`.

Với counter thay đổi liên tục, cân nhắc giữ source-of-truth ở database/cache và
định kỳ materialize sang search projection.

### 9.3 Chỉ index thứ cần tìm

Mapping explicit giúp tránh field explosion:

```http
PUT /orders-v2

{
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "order_id": {
        "type": "keyword"
      },
      "description": {
        "type": "text"
      },
      "amount_minor": {
        "type": "long"
      },
      "payload": {
        "type": "object",
        "enabled": false
      }
    }
  }
}
```

- `index: false` khi chỉ cần lấy field từ `_source`;
- tắt `doc_values` nếu không sort/aggregate/script field đó;
- tắt `norms` cho text không cần scoring;
- không bật fielddata trên `text` chỉ để aggregation;
- cân nhắc `match_only_text` cho log cần match nhưng không cần phrase/score đầy đủ;
- đo field usage và disk usage trước khi bỏ cấu trúc.

### 9.4 Ingest pipeline

Grok, script, attachment extraction và inference có thể làm ingest node thành
bottleneck. Đo pipeline riêng, dùng bulk representative và quan sát hot threads.
Không mặc định đẩy mọi phép biến đổi vào cluster.

---

## 10. Segment, merge và force merge

Refresh tạo segment; background merge gộp segment và loại deleted document.
Merge dùng CPU, disk bandwidth và disk tạm thời.

```http
GET /orders-read/_stats?human&filter_path=indices.*.primaries.segments,indices.*.primaries.merges,indices.*.primaries.refresh
```

`_forcemerge` chỉ dành cho index **không còn ghi** hoặc read-only:

```http
POST /orders-2026-06/_forcemerge?max_num_segments=5
```

Không force merge index đang nhận write:

- segment lớn có thể tiếp tục tích deleted document;
- thao tác rất tốn I/O và dung lượng tạm;
- có thể cạnh tranh với search, recovery và snapshot;
- `max_num_segments=1` không mặc định là lựa chọn tốt.

Với time-series, rollover rồi mới force merge generation cũ trong lifecycle phù
hợp hơn.

---

## 11. Search cost = fan-out × work mỗi shard × concurrency

Một search thường chạy một CPU thread trên mỗi shard ở query phase:

```text
cost gần đúng
  = số shard bị chạm
  × chi phí query/aggregation trên mỗi shard
  × số search đồng thời
  + coordinator merge/fetch
```

Do đó:

- một query 20 ms trên một shard không đảm bảo nhanh khi fan-out 500 shard;
- thêm replica có thể tăng search throughput, nhưng cũng chia filesystem cache và
  tăng indexing cost;
- nhiều shard nhỏ thường tệ hơn ít shard vừa vì overhead và thread-pool pressure;
- một shard quá lớn lại làm recovery và một số query chậm.

Tối ưu fan-out bằng index/date target chính xác, routing có kiểm soát và tránh
wildcard alias phủ dữ liệu không liên quan.

---

## 12. Query: giảm công việc trước khi thêm phần cứng

### 12.1 Filter khi không cần score

```http
GET /products-read/_search

{
  "query": {
    "bool": {
      "must": [
        {
          "match": {
            "name": "wireless headphone"
          }
        }
      ],
      "filter": [
        {
          "term": {
            "status": "active"
          }
        },
        {
          "range": {
            "price_minor": {
              "lte": 3000000
            }
          }
        }
      ]
    }
  }
}
```

Filter không tính score và có cơ hội tái sử dụng cache. Nhưng “filter luôn được
cache” là sai: Elasticsearch dùng policy theo tần suất và segment.

### 12.2 Tránh query expansion không giới hạn

Leading wildcard, regex rộng, fuzzy với nhiều expansion và script per-document
có thể đốt CPU:

```http
GET /products-read/_search

{
  "query": {
    "wildcard": {
      "sku": {
        "value": "*-2026-*"
      }
    }
  }
}
```

Không thay bằng prefix một cách máy móc. Thiết kế field theo access pattern:
prefix, edge-ngram, `wildcard` field, search-as-you-type hoặc exact keyword; sau
đó benchmark độ chính xác, disk và latency.

### 12.3 Script và runtime field

Runtime field hữu ích cho khám phá hoặc migration, nhưng phép tính per-document
có thể đắt khi query rộng. Field nóng nên được materialize lúc ingest nếu phép
đo chứng minh có lợi.

### 12.4 Total hits

Nếu UI chỉ cần “hơn 10.000 kết quả”:

```http
GET /orders-read/_search

{
  "track_total_hits": 10000,
  "size": 20,
  "query": {
    "term": {
      "status": "paid"
    }
  }
}
```

Đừng tính exact total cho mọi request nếu product không dùng nó. Kiểm tra
`hits.total.relation`: `eq` hay `gte`.

---

## 13. Fetch phase và payload

Query nhanh nhưng response chậm có thể nằm ở fetch:

- `_source` lớn hoặc compressed block không nằm trong page cache;
- highlight trên field dài;
- inner hits/top hits quá nhiều;
- script field;
- trả quá nhiều hit;
- client deserialize chậm.

Chỉ lấy field cần dùng:

```http
GET /orders-read/_search

{
  "_source": [
    "order_id",
    "status",
    "amount_minor"
  ],
  "size": 20,
  "query": {
    "term": {
      "customer_id": "c-1042"
    }
  }
}
```

`_source` filtering giảm network và deserialize, nhưng không nhất thiết tránh
toàn bộ chi phí đọc/decompress `_source`. Với scalar phù hợp, `fields` có thể lấy
giá trị từ doc values theo mapping.

### 13.1 Pagination

- `from + size` sâu giữ nhiều candidate trên mỗi shard;
- dùng PIT + `search_after` cho phân trang tương tác sâu;
- dùng scroll cho batch/export theo snapshot, không cho UI;
- luôn có unique tie-breaker.

Xem chi tiết tại [Query DSL §21–23](../fundamentals/query_dsl.md).

---

## 14. Aggregation: kiểm soát cardinality và reduce

Aggregation có thể làm data node lẫn coordinating node nóng:

```text
bucket cha × bucket con × shard
    → collection memory
    → shard response
    → coordinator reduce
```

Nguyên tắc:

- filter scope sớm;
- đặt `size: 0` nếu không cần hits;
- tránh lồng nhiều `terms` cardinality cao;
- không tăng `search.max_buckets` để che thiết kế sai;
- dùng `composite` để duyệt key theo trang, không phải global sort arbitrary metric;
- materialize dashboard nặng bằng transform/downsampling/read model;
- hiểu sai số của `terms`, `cardinality`, percentile.

`bucket_sort` và `bucket_selector` chạy sau khi parent bucket đã tạo, nên không
giảm upstream CPU/memory.

Xem [Aggregations §27–33](../advanced/aggregations.md).

---

## 15. Bốn lớp cache thường bị nhầm

| Cache | Nằm ở đâu | Hợp với | Điểm dễ sai |
|---|---|---|---|
| Filesystem/page cache | RAM của OS | Lucene file nóng | Bị cạnh tranh nếu heap chiếm quá nhiều RAM |
| Shard request cache | từng shard | request lặp, thường `size: 0` | Refresh làm invalidation; `now` giảm reuse |
| Node query cache | từng node, per segment | filter context tái dùng | Không phải filter nào cũng được cache |
| Client/CDN/app cache | ngoài ES | response có business key/TTL | Phải xử lý freshness và tenant scope |

Kiểm tra delta hit/miss/eviction:

```http
GET /_stats/query_cache,request_cache,fielddata?human
```

```http
GET /_nodes/stats/indices/query_cache,request_cache,fielddata?human
```

Dashboard ổn định có thể yêu cầu request cache:

```http
GET /orders-read/_search?request_cache=true

{
  "size": 0,
  "query": {
    "range": {
      "@timestamp": {
        "gte": "2026-07-01T00:00:00Z",
        "lt": "2026-08-01T00:00:00Z"
      }
    }
  },
  "aggs": {
    "revenue": {
      "sum": {
        "field": "amount_minor"
      }
    }
  }
}
```

Dùng mốc thời gian đã làm tròn hoặc cố định nếu semantics cho phép. Query chứa
`now` thay đổi liên tục thường khó tái sử dụng request cache.

Không đặt mục tiêu “cache hit > 80%” chung. Search cá nhân hóa hoặc cardinality
cao có hit rate thấp nhưng vẫn khỏe; dashboard lặp lại lại nên có hit rate cao.

Không clear cache định kỳ:

```http
POST /orders-read/_cache/clear
```

API này chỉ dùng khi chẩn đoán có kiểm soát; clear làm cold-cache spike và che
nguyên nhân thật.

---

## 16. Filesystem cache, heap và storage

Elasticsearch/Lucene dựa mạnh vào filesystem cache. Elastic khuyên dành ít nhất
một nửa RAM hệ thống cho page cache trong môi trường tự quản lý; mặc định heap
auto-sizing đã hướng tới nguyên tắc này.

Không giữ quy tắc “heap luôn 30 GB”:

- để Elasticsearch tự sizing khi có thể;
- nếu override, đặt `Xms = Xmx`;
- tính RAM trong container/cgroup, không phải RAM host;
- đo JVM pressure, GC và page-cache miss;
- không đổi collector/JVM flag tùy tiện vì distribution đã có cấu hình được test.

```http
GET /_nodes/stats/jvm,fs,os,process?human
```

Storage:

- SSD local thường có latency tốt hơn remote storage;
- benchmark chính loại volume, IOPS limit, throughput limit và burst credit;
- search random-read nhạy với latency;
- merge/recovery/snapshot có thể tranh bandwidth;
- trên Linux, readahead quá lớn qua RAID/LVM/dm-crypt có thể làm page-cache
  thrashing; giá trị 128 KiB là điểm khởi đầu chính thức, không phải chân lý cho
  mọi thiết bị.

Không dùng swap cho JVM Elasticsearch.

---

## 17. Shard sizing: guideline không phải định luật

Hướng dẫn Elastic hiện tại đưa 10–50 GB và dưới 200 triệu document mỗi shard như
điểm bắt đầu. Quyết định cuối phải dựa trên benchmark production-like.

### 17.1 Vì sao quá nhiều shard chậm?

- mỗi shard/index/segment/field có metadata và heap overhead;
- search fan-out dùng thread pool;
- cluster state và recovery nhiều đơn vị hơn;
- nhiều segment nhỏ làm page cache kém hiệu quả.

### 17.2 Vì sao shard quá lớn cũng chậm?

- recovery/relocation lâu;
- một shard chỉ dùng một thread cho một search;
- merge lớn và disk watermark khó xử lý;
- blast radius khi một copy unavailable lớn hơn.

### 17.3 Capacity theo recovery

Nếu shard 50 GB và effective recovery throughput chỉ 80 MB/s:

```text
50 GiB / 80 MiB/s ≈ 10,7 phút
```

Đây mới chỉ là copy lý tưởng, chưa tính throttle, checksum, concurrent recovery,
network contention và warm-up. Shard size phải thỏa RTO, không chỉ search p95.

Kiểm tra:

```http
GET /_cat/shards?v=true&s=store:desc&h=index,shard,prirep,state,docs,store,node
```

```http
GET /_cluster/stats?human&filter_path=indices.shards,indices.count,indices.mappings.total_deduplicated_mapping_size*
```

Quy tắc cũ “20 shard/GB heap” không còn là sizing model phù hợp. Cluster có hard
limit shard và guideline index metadata, nhưng chúng không bảo đảm performance.

---

## 18. Rollover và lifecycle thay cho dự đoán xa

Với time-series, rollover giúp giữ generation trong khoảng kích thước/tuổi đã
benchmark:

```http
POST /logs-write/_rollover

{
  "conditions": {
    "max_primary_shard_size": "40gb",
    "max_age": "1d",
    "max_docs": 150000000
  }
}
```

Không dùng cả ba ngưỡng chỉ vì ví dụ có cả ba; chọn điều kiện theo workload và
retention. Data stream + lifecycle thường dễ vận hành hơn tự tạo index theo ngày:

- ngày ít traffic không sinh hàng loạt shard nhỏ;
- ngày cao điểm có thể rollover sớm;
- generation cũ có thể move tier, shrink hoặc delete.

Delete cả index giải phóng tài nguyên ngay; delete-by-query chỉ đánh dấu document
và chờ merge.

---

## 19. Routing: giảm fan-out nhưng có thể tạo hot shard

Nếu mọi truy vấn thật sự có `tenant_id`, custom routing có thể giảm số shard:

```http
PUT /orders-v2/_doc/o-1001?routing=tenant-17

{
  "tenant_id": "tenant-17",
  "status": "paid"
}
```

```http
GET /orders-v2/_search?routing=tenant-17

{
  "query": {
    "term": {
      "tenant_id": "tenant-17"
    }
  }
}
```

Nhưng routing theo tenant tạo hot shard nếu tenant lệch lớn. Phải:

- đo phân bố key và tốc độ tăng;
- dùng routing partition hoặc cell/index riêng cho whale tenant khi phù hợp;
- bắt buộc routing ở data access layer;
- kiểm thử update/delete/get đều truyền cùng routing;
- không dùng alias có literal `"routing": "customer_id"` với ý nghĩ ES sẽ đọc
  giá trị field—alias routing là **giá trị cố định**, không phải tên field động.

---

## 20. Replica: availability, throughput và cache trade-off

Replica:

- bảo vệ khi node/shard copy hỏng;
- có thể tăng search concurrency vì request chạy trên nhiều copy;
- tăng write, network và merge cost;
- mỗi copy cạnh tranh RAM page cache.

Ví dụ hai shard trên hai node đã dùng hết CPU/cache tốt có thể không nhanh hơn khi
thêm một replica làm mỗi node giữ hai shard. Benchmark topology thật và không hạ
availability production chỉ để tăng benchmark.

Đọc replica không thay thế PIT/consistency design: các copy có refresh timing và
segment layout khác nhau.

---

## 21. Heap, JVM pressure và circuit breaker

Phân biệt:

```text
RAM host/container
├── JVM heap
│   ├── aggregation/request structures
│   ├── query cache/fielddata
│   ├── cluster + mapping metadata
│   └── indexing buffers/in-flight work
└── native + filesystem cache
```

Heap thấp kéo dài không có nghĩa nên tăng cache. Heap cao có thể do workload tạo
quá nhiều object; tăng heap chỉ kéo dài thời gian tới OOM và làm page cache nhỏ.

```http
GET /_nodes/stats/jvm,breaker?human
```

```http
GET /_nodes/stats/indices/fielddata,query_cache,request_cache,segments?human
```

Breaker là ước lượng để từ chối trước khi OOM, không phải hàng rào tuyệt đối.
Khi breaker trip:

1. xác định breaker/node/query class;
2. xem request đang chạy, bucket/cardinality/payload;
3. giảm concurrency hoặc scope;
4. sửa query/mapping;
5. scale nếu workload hợp lệ vẫn vượt capacity;
6. chỉ đổi breaker limit sau benchmark và risk review.

Không bật fielddata trên `text` rồi tăng fielddata breaker. Dùng `keyword` +
doc values hoặc redesign.

---

## 22. Thread pool, queue và HTTP 429

Thread pool bảo vệ node khỏi concurrency vô hạn:

```text
active < pool size       → chạy
active đầy               → queue
queue đầy                → reject 429
```

```http
GET /_cat/thread_pool?v=true&s=node_name,name&h=node_name,name,pool_size,active,queue,queue_size,rejected,completed
```

`active`/`queue` là snapshot; `rejected`/`completed` là counter tích lũy. Quan sát
rate và duration.

Đừng tăng queue để “hết 429”:

- request chờ lâu hơn và vượt deadline client;
- memory in-flight tăng;
- retry vẫn nhân tải;
- tail latency xấu hơn trước khi reject.

Xử lý theo thứ tự:

1. giảm/bẻ nhỏ burst và thêm jitter;
2. cancel/optimize expensive task;
3. sửa hot spotting và fan-out;
4. giới hạn concurrency theo query class/tenant;
5. scale đúng resource bị bão hòa;
6. chỉ tune thread pool cho trường hợp đặc biệt đã benchmark.

---

## 23. Coordinating node và reduce hotspot

Node nhận search trở thành coordinator dù không có data role. Nó phải:

- fan-out request;
- giữ shard response;
- merge top hits;
- reduce aggregation;
- fetch và dựng response.

Một load balancer dồn traffic vào ít node hoặc một aggregation có quá nhiều bucket
có thể làm coordinator nóng trong khi data node chưa đầy.

Kiểm tra:

- CPU/heap theo role;
- inbound/outbound network;
- request breaker;
- search queue;
- response size;
- hot threads và slow logs;
- phân bố client connection.

Dedicated coordinating-only node không tự động chữa query xấu. Nó thêm network hop
và cần sizing theo reduce/fetch workload.

---

## 24. Slow log, Profile API, task và hot threads

### 24.1 Slow log là sampled evidence

```http
PUT /orders-read/_settings

{
  "index.search.slowlog.threshold.query.warn": "1s",
  "index.search.slowlog.threshold.query.info": "500ms",
  "index.search.slowlog.threshold.fetch.warn": "500ms",
  "index.indexing.slowlog.threshold.index.warn": "1s"
}
```

Ngưỡng phải theo SLO và log volume. Slow log của shard không bằng end-to-end
latency ở client.

### 24.2 Profile API chỉ để chẩn đoán

```http
GET /orders-read/_search

{
  "profile": true,
  "size": 0,
  "query": {
    "bool": {
      "filter": [
        {
          "term": {
            "status": "paid"
          }
        }
      ]
    }
  },
  "aggs": {
    "by_region": {
      "terms": {
        "field": "region",
        "size": 20
      }
    }
  }
}
```

Profile có overhead đáng kể và có thể vô hiệu một số optimization. Không so
latency profile với non-profile baseline. Nó cũng không đo đầy đủ:

- network;
- thời gian đợi queue;
- coordinator merge;
- aggregation reduce;
- global ordinal build;
- client-side latency.

### 24.3 Task và hot threads

```http
GET /_tasks?detailed=true&actions=*search,*bulk,*reindex
```

```http
GET /_nodes/hot_threads?threads=20&ignore_idle_threads=true
```

Hot threads là snapshot stack, không phải profiler lịch sử. Lấy nhiều mẫu cách
nhau vài giây; đối chiếu task, slow log và node metric.

Cancel chỉ khi đã xác định task và hiểu tác động:

```http
POST /_tasks/node-id:task-id/_cancel
```

---

## 25. Index sorting: tối ưu đọc bằng chi phí ghi

Nếu query thường sort cùng một thứ tự, index sorting có thể giúp early termination:

```http
PUT /events-v2

{
  "settings": {
    "index.sort.field": [
      "@timestamp",
      "event_id"
    ],
    "index.sort.order": [
      "desc",
      "asc"
    ]
  },
  "mappings": {
    "properties": {
      "@timestamp": {
        "type": "date"
      },
      "event_id": {
        "type": "keyword"
      }
    }
  }
}
```

Trade-off:

- phải chọn lúc tạo index;
- indexing/merge tốn thêm công;
- chỉ có lợi cho query shape phù hợp;
- exact total hits hoặc aggregation vẫn có thể phải quét;
- không thay thế benchmark.

---

## 26. Vector/kNN có workload riêng

Approximate kNN không nên benchmark như keyword search:

- `num_candidates` tăng thường cải thiện recall nhưng tăng CPU/latency;
- vector dimension/quantization ảnh hưởng RAM và disk;
- filter selectivity có thể đổi execution;
- indexing vector xây cấu trúc ANN và tốn tài nguyên;
- phải đo recall@k so với ground truth cùng p95/p99 và cost.

```http
GET /products-vector/_search

{
  "knn": {
    "field": "embedding",
    "query_vector": [
      0.12,
      -0.31,
      0.88
    ],
    "k": 10,
    "num_candidates": 100,
    "filter": {
      "term": {
        "status": "active"
      }
    }
  },
  "_source": [
    "product_id",
    "name"
  ]
}
```

Chạy ma trận `num_candidates × concurrency × filter selectivity`; không tối ưu
latency bằng cách giảm candidate mà bỏ qua recall.

---

## 27. Cô lập mixed workload

Search, indexing, transform, reindex, snapshot và recovery tranh:

- CPU;
- heap;
- disk bandwidth/IOPS;
- network;
- thread pool.

Các lựa chọn tăng dần:

1. schedule job nền ngoài peak;
2. throttle reindex/recovery;
3. rate/concurrency limit theo workload;
4. tách data tier hoặc ingest/coordinator role khi có bằng chứng;
5. dùng CCR để tách search cluster khỏi indexing cluster cho yêu cầu rất cao;
6. materialize read model cho aggregation nặng.

Tách role không tạo thêm tài nguyên; chỉ cô lập failure/noisy neighbor. Đo tổng
network và cost sau khi tách.

---

## 28. Scale up hay scale out?

| Bottleneck | Hành động có thể phù hợp |
|---|---|
| CPU-bound query trên shard | CPU nhanh hơn, query/mapping tốt hơn |
| Search concurrency | thêm node/copy sau khi fan-out hợp lý |
| Page-cache miss | thêm RAM ngoài heap, giảm working set, tier phù hợp |
| Disk latency/merge | SSD/volume tốt hơn, giảm churn, thêm node |
| Heap aggregation | giảm bucket/concurrency, materialize, thêm heap có kiểm soát |
| Hot shard | đổi routing/shard strategy, isolate key |
| Coordinator reduce | giảm response/bucket, phân tải coordinator |
| Recovery RTO | shard nhỏ hơn, network/disk tốt hơn, thêm failure-domain capacity |

Scale out chỉ hữu ích nếu shard và routing cho phép phân phối. Một hot key luôn về
một shard không tự hết nóng khi thêm node.

---

## 29. Thay đổi performance an toàn

Phân loại:

| Mức | Ví dụ | Cách triển khai |
|---|---|---|
| Request | `track_total_hits`, `_source`, query rewrite | canary theo query class |
| Dynamic index | refresh interval, replica | lưu giá trị cũ, automation rollback |
| New index | mapping, primary shard, index sorting | versioned index + reindex + alias |
| Node/static | heap, storage, thread pool | rolling change, capacity headroom |
| Architecture | routing, tier, CCR | migration plan + dual-read/reconcile |

Mọi thay đổi cần:

- owner và hypothesis;
- before/after dashboard;
- correctness test;
- canary scope;
- rollback cụ thể;
- expiry date cho setting tạm;
- kiểm tra sau restart/failover/recovery.

Không để `refresh_interval=-1`, replica 0 hoặc throttle tạm sống mãi sau migration.

---

## 30. Runbook “cluster chậm”

### Bước 1 – Xác định blast radius

- search, write hay cả hai;
- index/tenant/query class nào;
- một node, một tier hay toàn cluster;
- bắt đầu sau deploy, traffic spike, recovery hay snapshot nào;
- error/timeout/429/partial result có tăng không.

### Bước 2 – Kiểm tra saturation

```http
GET /_cat/nodes?v=true&s=cpu:desc&h=name,role,cpu,load_1m,heap.percent,ram.percent,disk.used_percent
```

```http
GET /_cat/thread_pool?v=true&h=node_name,name,active,queue,rejected,completed
```

```http
GET /_nodes/stats/jvm,fs,breaker,indexing_pressure?human
```

### Bước 3 – Tìm skew và công việc đang chạy

```http
GET /_cat/shards?v=true&s=store:desc&h=index,shard,prirep,state,docs,store,node
```

```http
GET /_tasks?detailed=true
```

```http
GET /_nodes/hot_threads
```

Đối chiếu slow log, client trace và deploy timeline.

### Bước 4 – Giảm tác động

Tùy bằng chứng:

- rate-limit/load-shed request đắt;
- dừng retry storm;
- giảm producer concurrency;
- cancel task cụ thể;
- hoãn snapshot/reindex;
- scale tier thiếu tài nguyên;
- cô lập hot tenant;
- rollback release/query vừa đổi.

### Bước 5 – Sửa nguyên nhân

Không kết thúc incident ở bước “restart node”. Viết lại query/mapping, shard/routing,
capacity model hoặc policy retry; thêm regression benchmark và alert cho leading
indicator.

---

## 31. Bảng chẩn đoán nhanh

| Triệu chứng | Kiểm tra trước | Không nên làm ngay |
|---|---|---|
| Search p99 tăng, CPU cao | slow log, hot threads, query mix, fan-out | tăng queue |
| Search p99 tăng, CPU thấp | queue, disk latency, page cache, network | tăng heap |
| Bulk 429 | write pools, indexing pressure, worker/batch | retry ngay không jitter |
| Breaker trip | breaker type, aggregation/payload/concurrency | nâng breaker limit |
| Heap sawtooth sát trần | GC duration, fielddata, bucket, mapping | đổi GC collector |
| Disk 100% | merge/recovery/snapshot, watermark | force merge active index |
| Một node nóng | shard/routing/traffic skew | thêm node rồi hy vọng tự hết |
| Cache hit thấp | query cardinality, refresh, `now` | clear cache định kỳ |
| Latency xấu sau restart | cold page cache, relocation | kết luận hardware thiếu từ một mẫu |
| Indexing nhanh nhưng search cũ | refresh interval | gọi refresh mỗi document |

---

## 32. Checklist production

### Workload và benchmark

- [ ] Có p50/p95/p99, throughput, error và saturation cùng cửa sổ?
- [ ] Dataset, query mix, concurrency và skew giống production?
- [ ] Đã đo cold, warm, steady state và recovery?
- [ ] Mỗi thử nghiệm chỉ đổi một biến và có rollback?
- [ ] Có correctness/recall/freshness guardrail?

### Indexing

- [ ] Bulk size và worker count được benchmark tăng dần?
- [ ] Parse lỗi từng bulk item?
- [ ] 429 dùng exponential backoff + jitter và bounded retry?
- [ ] Refresh interval phù hợp freshness SLO?
- [ ] Replica/durability không bị giảm ngoài initial load có replay?
- [ ] Update/delete churn và ingest pipeline đã được đo?

### Search

- [ ] Query chỉ chạm index/shard cần thiết?
- [ ] Filter/scoring/mapping đúng access pattern?
- [ ] `track_total_hits`, fetch payload, highlight và pagination có chủ đích?
- [ ] Aggregation bucket/cardinality/reduce nằm trong budget?
- [ ] Profile chỉ dùng chẩn đoán và hiểu phần nó không đo?

### Cluster

- [ ] Shard size/count được benchmark cùng recovery RTO?
- [ ] Không dùng quy tắc “20 shard/GB heap”?
- [ ] Heap không chiếm page cache và swap đã tắt?
- [ ] CPU, heap, disk, network, queue, rejection, breaker theo dõi bằng rate?
- [ ] Có phát hiện hot node, hot shard và hot tenant?
- [ ] Thay đổi tạm có owner/expiry/automatic rollback?

---

## 33. Câu hỏi phỏng vấn

1. Vì sao tăng số primary shard có thể vừa làm nhanh vừa làm chậm search?
2. Bạn tìm bulk size và số worker tối ưu như thế nào?
3. HTTP 429 có ý nghĩa gì, retry thế nào để không tạo retry storm?
4. Refresh, flush, merge và translog khác nhau ra sao?
5. Vì sao replica có thể tăng throughput nhưng làm một số topology chậm hơn?
6. Node query cache, shard request cache và filesystem cache khác nhau thế nào?
7. Profile API không đo những phần latency nào?
8. Tại sao tăng heap có thể làm search chậm?
9. Dấu hiệu nào phân biệt CPU-bound, heap-bound và I/O-bound?
10. Vì sao tăng thread-pool queue thường làm tail latency xấu hơn?
11. Custom routing giảm fan-out nhưng có rủi ro gì?
12. Bạn chứng minh một tuning không làm sai result hoặc giảm availability thế nào?

---

## 34. Nguồn và chủ đề tiếp theo

Nguồn chính thức:

- [Elasticsearch performance optimizations](https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance)
- [Tune for indexing speed](https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/indexing-speed)
- [Tune for search speed](https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/search-speed)
- [Size your shards](https://www.elastic.co/docs/deploy-manage/production-guidance/optimize-performance/size-shards)
- [Profile search requests](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/search-profile)
- [Rejected requests](https://www.elastic.co/docs/troubleshoot/elasticsearch/rejected-requests)
- [Task queue backlog](https://www.elastic.co/docs/troubleshoot/elasticsearch/task-queue-backlog)
- [High CPU usage](https://www.elastic.co/docs/troubleshoot/elasticsearch/high-cpu-usage)
- [Thread pool settings](https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/thread-pool-settings)
- [API conventions và `X-Opaque-Id`](https://www.elastic.co/docs/reference/elasticsearch/rest-apis/api-conventions)

Học tiếp:

1. [Cluster Management](../operations/cluster_management.md) – allocation,
   recovery, snapshot, upgrade và incident response.
2. [Architecture](../fundamentals/architecture.md) – read/write path, shard,
   segment và failure semantics.
3. [Query DSL](../fundamentals/query_dsl.md) – query cost, PIT và pagination.
4. [Aggregations](../advanced/aggregations.md) – accuracy, bucket memory và
   distributed reduce.

---

*Cập nhật lần cuối: 2026-07-31.*
