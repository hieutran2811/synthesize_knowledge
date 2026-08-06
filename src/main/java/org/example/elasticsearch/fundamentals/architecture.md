# Elasticsearch Architecture – từ document đến distributed search

> Elasticsearch không chỉ là “database có ô tìm kiếm”. Mỗi index được chia thành
> các shard, mỗi shard là một Lucene index, còn cluster phải điều phối metadata,
> bản sao, recovery và truy vấn phân tán. Hiểu đúng các lớp này giúp tránh ba lỗi
> production phổ biến: tạo quá nhiều shard, nhầm refresh với durability và xử lý
> cluster `yellow`/`red` theo cảm tính.

Tài liệu này dùng Elasticsearch 9.4 làm phiên bản tham chiếu. Với Elastic Cloud
Serverless, một số khái niệm hạ tầng như node role, ILM hay refresh mặc định được
dịch vụ quản lý hoặc có giá trị khác; luôn kiểm tra tài liệu của deployment đang dùng.

---

## 1. Elasticsearch giải quyết bài toán gì?

Elasticsearch là search và analytics engine phân tán xây trên Apache Lucene. Dữ
liệu được gửi vào dưới dạng JSON document, sau đó được phân tích thành cấu trúc
tối ưu cho:

- full-text search và relevance ranking;
- filter theo field, range, geo và vector;
- aggregation trên tập dữ liệu lớn;
- search gần real-time trên nhiều node.

Mental model ngắn:

```text
Ứng dụng
   │ HTTP/JSON
   ▼
Elasticsearch cluster
   ├── index / data stream       ← namespace logic
   ├── primary + replica shards  ← đơn vị phân tán và HA
   └── Lucene segments           ← cấu trúc tìm kiếm bất biến trên đĩa
```

Elasticsearch thường là **search projection** được dựng từ database hoặc event
stream, không mặc nhiên là system of record duy nhất:

```text
PostgreSQL ── outbox/CDC ──► Kafka ──► Elasticsearch
    ▲                                      │
    └──────── source of truth              └── search/read model
```

Khi có thể rebuild index từ nguồn chuẩn, việc thay mapping, reindex hoặc phục hồi
sự cố an toàn hơn nhiều.

---

## 2. Bộ từ vựng tối thiểu

| Khái niệm | Cách hiểu thực tế |
|---|---|
| Cluster | Tập node cùng tham gia một cluster và chia sẻ cluster state |
| Node | Một tiến trình Elasticsearch, đảm nhiệm một hoặc nhiều role |
| Document | Đơn vị JSON được index và truy vấn |
| Index | Namespace logic chứa document và cấu hình mapping/settings |
| Data stream | Tên logic trỏ tới chuỗi backing index, phù hợp dữ liệu append-only theo thời gian |
| Primary shard | Bản shard nhận và sắp thứ tự write |
| Replica shard | Bản sao của primary, phục vụ HA và có thể phục vụ read |
| Replication group | Một primary cùng các replica của shard đó |
| Lucene segment | Tệp/index con bất biến, nơi search thực sự diễn ra |
| Cluster state | Metadata về node, index, mapping, setting và shard routing |
| Elected master | Node điều phối thay đổi cluster state; không phải “master của mọi query” |
| Coordinating node | Node nhận request, fan-out và hợp nhất kết quả; mọi node đều có khả năng này |

Ba từ “index” dễ bị lẫn:

```text
Elasticsearch index  = namespace gồm nhiều shard
Lucene index         = nội dung của một shard
Inverted index       = cấu trúc term → danh sách document
```

---

## 3. Cluster state và elected master

Cluster state chứa metadata để toàn cluster hiểu cùng một topology:

- node nào đang tham gia;
- index, mapping, template và setting nào tồn tại;
- primary/replica shard nằm ở đâu;
- shard nào đang initializing, relocating hoặc unassigned.

Elected master chịu trách nhiệm cho các thao tác cluster-wide nhẹ như:

- publish cluster state mới;
- tạo/xóa index;
- theo dõi node join/leave;
- quyết định shard allocation.

Elected master **không trực tiếp thực thi mọi search hoặc write**. Data node mới
là nơi xử lý CRUD, search và aggregation.

### 3.1 Voting configuration

Thay đổi cluster state và bầu master cần đa số node trong voting configuration:

```text
3 master-eligible nodes
majority = 2

M1 + M2 sống, M3 lỗi  → vẫn có majority
chỉ M1 sống           → không đủ majority, dừng thay đổi cluster state
```

Production HA thường cần ít nhất ba master-eligible node, trong đó ít nhất hai
node không phải `voting_only`. Không dừng một nửa hoặc nhiều hơn voting
configuration cùng lúc.

### 3.2 Tại sao phải mất availability khi mất majority?

Nếu hai phía network partition đều tự nhận mình là cluster hợp lệ, chúng có thể
phân bổ primary và chấp nhận write xung đột. Dừng phía không có majority là lựa
chọn bảo vệ consistency của metadata.

Không “chữa” mất quorum bằng cách tự ý bootstrap lại cluster. Bootstrap sai có
thể tạo một cluster mới có cùng tên nhưng cluster UUID khác.

---

## 4. Node roles

Một node có thể mang nhiều role. Nếu tự khai báo `node.roles`, phải liệt kê đầy
đủ các role mà deployment cần.

| Role | Trách nhiệm chính |
|---|---|
| `master` | Tham gia election và cluster-state publication |
| `voting_only` | Bỏ phiếu nhưng không trở thành elected master |
| `data` | Giữ shard cho mọi loại dữ liệu |
| `data_content` | Nội dung dài hạn như product/article catalog |
| `data_hot` | Time-series đang ghi và truy vấn nhiều |
| `data_warm` | Time-series ít cập nhật hơn |
| `data_cold` | Dữ liệu truy vấn thưa, ưu tiên chi phí |
| `data_frozen` | Searchable snapshot truy vấn rất hiếm |
| `ingest` | Chạy ingest pipeline |
| `ml` | Machine-learning workloads |
| `transform` | Chạy continuous/batch transforms |
| `remote_cluster_client` | Cross-cluster search/replication |

### 4.1 Coordinating không phải role có thể tắt

Mọi node đều có thể nhận request và phối hợp thực thi. `node.roles: []` chỉ tạo
coordinating-only node:

```text
Client → coordinating node
           ├─► shard copy trên data node A
           ├─► shard copy trên data node B
           └─► shard copy trên data node C
                     │
            merge/reduce kết quả
                     ▼
                  Client
```

Coordinating-only node không phải mặc định bắt buộc. Thêm quá nhiều node loại này
cũng làm cluster-state publication tốn công hơn. Chỉ tách riêng khi benchmark cho
thấy scatter/gather hoặc bulk coordination đang là bottleneck.

### 4.2 Topology theo quy mô

Lab hoặc cluster nhỏ:

```yaml
# Một node có nhiều role; đơn giản và tận dụng tài nguyên tốt.
node.roles: [ master, data, ingest ]
```

Cluster lớn:

```yaml
# Dedicated master-eligible
node.roles: [ master ]

# Content node
node.roles: [ data_content ]

# Hot time-series node
node.roles: [ data_hot, ingest ]
```

Không sao chép topology “3 master + N data + 2 coordinating” như công thức. Số
node và role phải đi từ workload, failure domain, latency và capacity test.

---

## 5. Index, primary shard và replica shard

Một Elasticsearch index được chia thành các primary shard:

```text
index products-v1

P0 ── replica R0
P1 ── replica R1
P2 ── replica R2
```

Mỗi `P` hoặc `R` là một bản sao đầy đủ của Lucene index cho shard tương ứng.

- Số primary shard quyết định cách dữ liệu được phân vùng.
- Số replica quyết định số bản sao bổ sung.
- Primary và replica cùng replication group không nằm trên cùng một node.
- Replica hỗ trợ failover và có thể tăng read capacity, nhưng cũng tăng chi phí
  indexing, storage, merge và recovery.

Ví dụ:

```http
PUT /products-v1
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  }
}
```

Tổng cộng có 3 primary + 3 replica = 6 shard copies.

> Replica không phải backup. Xóa index, mapping sai hoặc thao tác xấu thường được
> nhân sang replica. Backup cần snapshot ở repository độc lập và phải restore thử.

---

## 6. Routing: document đi vào shard nào?

Elasticsearch dùng routing value để chọn primary shard:

```text
routing value mặc định = document _id
hash(routing value)     → một primary shard
```

Chi tiết phép tính còn phụ thuộc `number_of_routing_shards`, vì vậy không nên tự
viết client routing bằng công thức `% number_of_shards`.

Custom routing có thể gom dữ liệu của cùng tenant/customer vào một shard:

```http
PUT /orders-v1/_doc/o-101?routing=tenant-42
{
  "tenant_id": "tenant-42",
  "total": 125000
}
```

Khi đọc cũng phải truyền cùng routing:

```http
GET /orders-v1/_search?routing=tenant-42
{
  "query": {
    "term": { "tenant_id": "tenant-42" }
  }
}
```

Trade-off:

- query theo tenant chạm ít shard hơn;
- quên routing có thể không tìm thấy document theo ID hoặc tạo bản ghi “trùng”;
- tenant lớn tạo hot shard;
- đổi routing strategy thường cần reindex.

Custom routing là quyết định data model, không phải tối ưu nhỏ thêm sau.

---

## 7. Lucene segment: nơi search thực sự diễn ra

Mỗi shard là một Lucene index gồm nhiều segment bất biến:

```text
Shard
├── segment_1  ← immutable
├── segment_2  ← immutable
├── segment_3  ← immutable
├── in-memory indexing buffer
└── translog
```

Document update không sửa trực tiếp segment cũ. Phiên bản cũ được đánh dấu deleted,
phiên bản mới được ghi vào segment mới. Background merge dần:

- hợp nhất segment nhỏ;
- loại document đã bị đánh dấu deleted;
- giảm số cấu trúc phải đọc khi search.

Merge tiêu thụ disk I/O và CPU. Quá nhiều shard nhỏ tạo rất nhiều segment và
metadata, làm cả heap, file handle, search và recovery đắt hơn.

---

## 8. Refresh, flush, translog và merge không giống nhau

| Cơ chế | Mục tiêu | Có làm searchable? | Vai trò durability |
|---|---|---:|---:|
| Refresh | Mở segment mới cho search | Có | Không phải Lucene commit |
| Translog fsync | Giữ operation để recovery | Không quyết định search visibility | Có |
| Flush | Lucene commit và bắt đầu translog generation mới | Không phải cơ chế NRT chính | Có |
| Merge | Hợp nhất segment bất biến | Segment mới thay segment cũ | Không phải acknowledgment boundary |

Luồng đơn giản:

```text
index request
   ├──► indexing buffer
   └──► translog ── fsync theo durability policy

refresh
   └──► segment mới được mở → search nhìn thấy document

flush
   └──► Lucene commit + translog generation mới
```

Mặc định `index.translog.durability=request`: request chỉ được báo thành công sau
khi translog đã fsync/commit trên primary và các in-sync replica được cấp phát.
Chuyển sang `async` chấp nhận nguy cơ mất một phần acknowledged writes khi crash.

Flush tự chạy nền; hiếm khi cần gọi thủ công. Không dùng flush để “ép document
xuất hiện trong search”.

---

## 9. Near real-time và read-after-write

Write thành công không đồng nghĩa search ngay lập tức thấy document:

```text
T0: PUT document → acknowledged
T1: GET document by ID → thường thấy ngay (real-time GET)
T2: _search trước refresh → có thể chưa thấy
T3: refresh → _search thấy document
```

Trên Elastic Stack, index đang được search thường có refresh định kỳ khoảng một
giây theo mặc định. Elastic Cloud Serverless có thể dùng mặc định khác.

Các lựa chọn:

```http
# Chờ refresh kế tiếp; phù hợp workflow cần search thấy write vừa xong
PUT /products-v1/_doc/p-1?refresh=wait_for
{
  "name": "Bàn phím cơ"
}
```

- `refresh=false`: mặc định, throughput tốt.
- `refresh=wait_for`: đợi refresh kế tiếp, không ép refresh riêng.
- `refresh=true`: refresh shard liên quan ngay; dễ tạo nhiều segment nhỏ nếu lạm dụng.

Nếu chỉ cần đọc lại đúng document vừa ghi, ưu tiên GET theo ID thay vì search.

---

## 10. Write path phân tán

Write không được “broadcast cho mọi shard”:

```text
1. Client gửi request đến một node
2. Coordinating stage tính routing → replication group
3. Request được chuyển đến primary shard hiện tại
4. Primary validate và thực thi operation
5. Primary gửi operation cho các in-sync replica
6. Replica thực thi và phản hồi
7. Primary phản hồi coordinating node → client
```

Primary là nơi sắp thứ tự operation của replication group. Elected master duy trì
danh sách in-sync copies và có thể loại một replica lỗi khỏi danh sách.

### 10.1 `wait_for_active_shards`

Đây là precondition về số shard copy active trước khi bắt đầu operation, không
phải lời hứa rằng mọi replica cấu hình đều đã ghi xong:

```http
POST /orders-v1/_doc?wait_for_active_shards=all
{
  "tenant_id": "tenant-42",
  "total": 125000
}
```

Giá trị `all` tăng safety trước một số failure mode nhưng giảm availability khi
replica chưa active. Chọn theo SLA, không bật theo thói quen.

### 10.2 Retry và idempotency

Client có thể timeout dù server đã ghi thành công. Retry với `_id` ổn định giúp
tránh tạo hai document khác ID:

```text
event_id = order-created:o-101
document _id = event_id
```

Nếu concurrent update quan trọng, dùng optimistic concurrency control bằng
`if_seq_no` và `if_primary_term`; không dựa vào “last write wins” ngầm định.

---

## 11. Search path: scatter/gather

Search thường có hai phase:

```text
Query phase
  coordinator → một copy của mỗi shard cần tìm
  mỗi shard trả top document IDs + sort values/scores

Fetch phase
  coordinator → lấy _source/fields của các document thắng
  coordinator hợp nhất → client
```

Hệ quả:

- một query chạm 500 shard tạo fan-out lớn dù mỗi shard ít dữ liệu;
- `size` lớn làm heap ở coordinator và data node tăng;
- deep pagination bằng `from + size` bắt mỗi shard giữ nhiều ứng viên;
- slow shard quyết định tail latency toàn request.

Với pagination sâu, dùng point in time (PIT) + `search_after` thay cho tăng
`index.max_result_window` tùy tiện.

### 11.1 Replica có luôn làm search nhanh hơn?

Không. Replica tạo thêm shard copy để Elasticsearch phân phối read, nhưng:

- cùng lượng RAM/disk mà tăng replica có thể làm cache hit rate giảm;
- aggregation CPU-heavy vẫn cần CPU thật;
- indexing phải nhân thêm operation và merge;
- query vẫn cần một copy của từng primary shard logic.

Chỉ tăng replica sau benchmark đúng concurrency và query mix.

---

## 12. Cluster health: green, yellow, red

```http
GET /_cluster/health
```

| Màu | Ý nghĩa | Tác động |
|---|---|---|
| Green | Tất cả primary và replica được gán | Đủ số bản sao theo cấu hình |
| Yellow | Tất cả primary active, có replica unassigned | Vẫn đọc/ghi được nhưng giảm redundancy |
| Red | Ít nhất một primary unassigned | Một phần dữ liệu/index không khả dụng |

Màu health không nói:

- latency có đạt SLA hay không;
- query trả kết quả đúng business hay không;
- disk có sắp đầy hay không;
- snapshot gần nhất có restore được hay không.

Chẩn đoán theo thứ tự:

```http
GET /_cluster/health?filter_path=status,*_shards
GET /_cat/shards?v&s=state,index
GET /_cluster/allocation/explain
GET /_cat/nodes?v&h=name,roles,heap.percent,ram.percent,cpu,disk.avail
GET /_cluster/pending_tasks
```

Không reroute, xóa index hoặc tăng watermark trước khi đọc allocation explanation.

---

## 13. Shard sizing: không có con số thần kỳ

Các quy tắc kiểu “10–50 GB/shard” hoặc “20 shard/GB heap” chỉ là heuristic lịch
sử, không phải invariant. Kích thước phù hợp phụ thuộc:

- loại query và aggregation;
- indexing rate, update/delete rate;
- segment count và merge pressure;
- thời gian recovery chấp nhận được;
- disk throughput, CPU, heap và filesystem cache;
- số tenant và phân bố hot key;
- thời gian retention.

Quy trình đúng:

```text
1. Ước lượng data/ngày sau index
2. Chọn rollover ban đầu
3. Replay dữ liệu thật vào môi trường gần production
4. Benchmark p50/p95/p99 search + indexing
5. Mô phỏng mất node và đo recovery
6. Điều chỉnh primary count/rollover
```

Primary shard count không thể đổi trực tiếp cho index đang tồn tại. Các đường đổi
thường là split, shrink hoặc reindex sang index mới, mỗi cách có điều kiện và
trade-off riêng.

### 13.1 Oversharding

Triệu chứng:

- hàng nghìn index nhỏ theo customer/day;
- cluster state lớn và publish chậm;
- heap cao dù dung lượng data thấp;
- recovery/rebalance kéo dài;
- search fan-out qua quá nhiều shard.

Giải pháp thường là shared index có `tenant_id`, data stream + rollover, hoặc gom
tenant nhỏ; không mặc định tạo một index cho mỗi tenant.

### 13.2 Hot shard

Custom routing hoặc tenant lớn có thể dồn phần lớn traffic vào một shard. Thêm
node không tự chia nhỏ shard nóng đó. Cần đổi partitioning/routing, dùng routing
partition hoặc tách tenant lớn bằng thiết kế có chủ đích.

---

## 14. Capacity: heap không phải toàn bộ RAM

Lucene tận dụng filesystem cache mạnh, vì vậy cấp hết RAM cho JVM thường làm hiệu
năng tệ đi. Với phiên bản hiện đại:

- ưu tiên automatic JVM heap sizing theo node role và tổng RAM;
- nếu tự đặt heap, giữ `Xms` bằng `Xmx`;
- dành RAM đáng kể cho filesystem cache;
- benchmark thay vì giữ quy tắc cũ “31 GB cho mọi node”;
- không bật swap như một cách mở rộng capacity.

Capacity phải theo ít nhất bốn ngân sách:

```text
storage = primary data × (1 + replicas) × headroom × merge/recovery overhead
heap    = mappings + shard/segment metadata + query/aggregation working set
CPU     = analysis + scoring + aggregation + merge
I/O     = indexing + merge + recovery + snapshot + cache miss
```

Đĩa gần đầy không chỉ là vấn đề storage. Disk allocator có thể ngừng cấp shard,
di chuyển shard và cuối cùng đặt write block ở flood-stage watermark.

---

## 15. Discovery và bootstrap

Self-managed cluster dùng discovery seed để các master-eligible node tìm nhau:

```yaml
cluster.name: search-prod
node.name: es-master-1
node.roles: [ master ]

discovery.seed_hosts:
  - es-master-1.internal
  - es-master-2.internal
  - es-master-3.internal
```

`cluster.initial_master_nodes` chỉ dùng **một lần** khi bootstrap cluster hoàn
toàn mới:

```yaml
# Chỉ trong lần tạo cluster mới, sau đó phải xóa khỏi cấu hình.
cluster.initial_master_nodes:
  - es-master-1
  - es-master-2
  - es-master-3
```

Không đặt lại setting này khi restart, thay master node hay phục hồi sự cố. Node
tham gia cluster hiện hữu phải giữ đúng data path/cluster identity hoặc dùng quy
trình enrollment phù hợp.

---

## 16. Data tiers và data lifecycle

Tách hai loại workload:

```text
Content data
  product/article/catalog → data_content

Time-series data
  hot → warm → cold → frozen → delete
```

Với time-series append-only, data stream tạo lớp tên ổn định trên các backing
index và đơn giản hóa rollover:

```text
logs-app-default (data stream)
  ├── .ds-logs-app-default-...-000001
  ├── .ds-logs-app-default-...-000002
  └── .ds-logs-app-default-...-000003  ← write index
```

Index Lifecycle Management (ILM) có thể:

- rollover theo primary shard size, document count hoặc age;
- chuyển backing index qua tier;
- shrink hoặc force merge dữ liệu đã read-only;
- dùng searchable snapshot;
- delete theo retention.

Elastic Cloud Serverless không dùng ILM; Data Stream Lifecycle là lựa chọn được
quản lý đơn giản hơn. Đừng sao chép ILM policy từ self-managed sang Serverless.

### 16.1 Rollover theo size tốt hơn lịch cứng khi nào?

Nếu traffic mỗi ngày dao động mạnh, index-per-day tạo shard quá nhỏ vào ngày vắng
và quá lớn vào ngày cao điểm. Rollover theo `max_primary_shard_size` giữ shard
đồng đều hơn; `max_age` có thể làm guardrail cho retention/operability.

---

## 17. Availability và failure domains

Một replica chỉ hữu ích nếu nằm ở failure domain khác:

```text
Zone A: P0, R1
Zone B: P1, R2
Zone C: P2, R0
```

Khi node giữ `P0` lỗi:

```text
R0 được promote thành primary
cluster tạm yellow
replica mới được allocate/recover
cluster trở lại green
```

Thiết kế cần xem đồng thời:

- số zone và allocation awareness;
- số replica;
- voting configuration;
- network latency giữa zone;
- disk/network budget cho recovery;
- khả năng cluster chịu tải trong lúc mất một node/zone.

“Có replica” nhưng cluster còn lại không đủ CPU hoặc disk throughput khi failover
thì HA chỉ tồn tại trên sơ đồ.

---

## 18. Cluster state phải nhỏ và ổn định

Mapping, index, template, alias và shard routing đều góp phần làm cluster state
lớn. Các nguồn phình phổ biến:

- index-per-tenant ở quy mô lớn;
- dynamic field explosion;
- template chồng lấn khó kiểm soát;
- rollover tạo backing index nhưng không có retention;
- mapping update liên tục.

Mọi master-eligible node nằm trên critical path của cluster-state publication.
Dedicated master cần storage bền, network ổn định và không bị client dùng như
coordinating endpoint.

Kiểm soát mapping explosion bằng:

- explicit mapping/index template;
- giới hạn tổng field;
- không biến key động thành field name;
- dùng `flattened` hoặc mô hình key/value khi phù hợp;
- theo dõi cluster state và pending tasks.

---

## 19. Index alias và zero-downtime reindex

Mapping không phải lúc nào cũng sửa in-place được. Dùng versioned index + alias:

```text
products-read  ──► products-v1
products-write ──► products-v1

reindex v1 → v2
validate count/query/checksum
atomic alias switch

products-read  ──► products-v2
products-write ──► products-v2
```

Alias switch:

```http
POST /_aliases
{
  "actions": [
    { "remove": { "index": "products-v1", "alias": "products-read" } },
    { "add":    { "index": "products-v2", "alias": "products-read" } }
  ]
}
```

Thực tế còn phải giải quyết write trong lúc backfill:

- dừng write ngắn;
- dual-write có idempotency/reconciliation;
- replay change log từ checkpoint;
- hoặc rebuild từ event stream.

Alias atomic không tự làm toàn bộ migration atomic.

---

## 20. Security baseline

Một cluster production tối thiểu cần:

- TLS cho HTTP client traffic và transport giữa node;
- authentication, không public port `9200`;
- role/privilege theo least privilege;
- tách quyền đọc, ghi, quản lý index và quản lý cluster;
- API key ngắn hạn/rotate được cho service;
- network policy/firewall;
- audit trail phù hợp yêu cầu;
- secret ngoài source code;
- snapshot repository có quyền và retention độc lập.

Không cho application role quyền `manage`, `all` hoặc wildcard toàn bộ index chỉ
để “chạy cho được”.

---

## 21. Snapshot, restore và disaster recovery

Snapshot lưu cluster/index state vào repository hỗ trợ. Một chiến lược backup tốt
phải định nghĩa:

| Khái niệm | Câu hỏi |
|---|---|
| RPO | Chấp nhận mất tối đa bao nhiêu phút dữ liệu? |
| RTO | Cần khôi phục search trong bao lâu? |
| Scope | Index/data stream nào là critical? |
| Repository | Có độc lập với cluster/failure domain không? |
| Restore drill | Lần gần nhất restore và kiểm tra query là khi nào? |

Replica xử lý node failure. Snapshot xử lý xóa nhầm, corruption logic, mất cluster
hoặc disaster rộng hơn. Nếu Elasticsearch là derived view, cần thêm runbook rebuild
từ source of truth và ước lượng thời gian catch-up.

---

## 22. Các failure mode thường gặp

### 22.1 Single-node luôn yellow

Replica không thể đặt cùng node với primary. Với lab một node, `number_of_replicas:
1` làm cluster yellow. Production không nên “sửa” bằng cách giảm replica nếu mục
tiêu ban đầu là HA.

### 22.2 Cluster red sau khi node lỗi

Đừng xóa unassigned shard ngay. Kiểm tra:

1. primary nào unassigned;
2. node/data path có quay lại không;
3. allocation explain nói gì;
4. còn valid shard copy hay snapshot không;
5. có cần restore/rebuild không.

### 22.3 Search chậm dù CPU thấp

Có thể do:

- cache miss và disk latency;
- query fan-out quá nhiều shard;
- coordinator giữ top-N lớn;
- một shard/tenant nóng;
- merge/recovery đang dùng I/O;
- fielddata hoặc aggregation tạo memory pressure.

### 22.4 Indexing throughput tụt theo chu kỳ

Thường liên quan merge pressure, refresh quá dày, disk throughput, bulk request
không phù hợp hoặc shard imbalance. Đừng chỉ tăng thread pool/queue vì có thể biến
backpressure thành OOM và latency dài hơn.

### 22.5 Tăng replica nhưng latency không giảm

Workload có thể bị CPU, cache, coordinator, network hoặc shard fan-out giới hạn.
Benchmark concurrency thực và kiểm tra từng phase trước khi thêm bản sao.

---

## 23. Runbook chẩn đoán nhanh

### Tình huống: cluster vừa chuyển yellow/red

```text
1. Xác nhận phạm vi và thời điểm
2. GET _cluster/health
3. GET _cat/shards
4. GET _cluster/allocation/explain
5. Kiểm tra node loss, disk watermark, allocation filter, version
6. Chọn recover node / giải phóng capacity / sửa constraint / restore
7. Theo dõi recovery và tải khách hàng
8. Xác minh snapshot, query và write sau phục hồi
```

### Tình huống: search p99 tăng

```text
1. Tách query nào và index/shard nào chậm
2. Kiểm tra fan-out, rejected task, GC, CPU, disk I/O
3. Kiểm tra merge/recovery/snapshot cùng thời điểm
4. Profile query trên mẫu đại diện
5. So sánh deployment/change gần nhất
6. Giảm tải hoặc rollback trước khi tối ưu dài hạn
```

---

## 24. Những ngộ nhận cần tránh

| Ngộ nhận | Thực tế |
|---|---|
| Elected master xử lý mọi request | Data node xử lý dữ liệu; node nhận request làm coordination |
| Refresh làm dữ liệu bền | Refresh quyết định search visibility; translog/Lucene commit liên quan durability |
| Replica là backup | Replica nhân cả thao tác xấu; backup cần snapshot/nguồn rebuild |
| Nhiều shard luôn nhanh hơn | Shard tăng parallelism nhưng cũng tăng metadata, fan-out và recovery |
| Nhiều replica luôn giảm latency | Chỉ hữu ích nếu workload và tài nguyên cho phép |
| Green nghĩa là hệ thống khỏe | Green chỉ mô tả shard allocation |
| Một index cho mỗi tenant luôn cách ly tốt | Có thể gây oversharding và cluster-state explosion |
| Force merge giúp index đang ghi | Force merge phù hợp index read-only, rất tốn tài nguyên |
| `cluster.initial_master_nodes` dùng cho mọi lần restart | Chỉ dùng khi bootstrap cluster mới |
| GET và `_search` có cùng visibility | GET theo ID có thể real-time; search phụ thuộc refresh |

---

## 25. Checklist thiết kế

### Data và search

- [ ] Elasticsearch là source of truth hay derived search projection?
- [ ] Có đường rebuild/reindex và checkpoint rõ ràng?
- [ ] Mapping/analyzer được version và test bằng query thật?
- [ ] Dùng index, alias hay data stream đúng loại dữ liệu?
- [ ] Routing strategy có xét tenant skew và hot shard?

### Shard và capacity

- [ ] Primary shard/rollover được chọn bằng benchmark?
- [ ] Có headroom khi mất một node/zone?
- [ ] Heap và filesystem cache đều được tính?
- [ ] Có giới hạn field/index/shard để ngăn explosion?
- [ ] Đã đo recovery time, không chỉ steady-state latency?

### Availability

- [ ] Có ít nhất ba master-eligible node cho HA phù hợp?
- [ ] Replica nằm khác failure domain?
- [ ] Allocation awareness khớp topology?
- [ ] Snapshot có RPO/RTO và restore drill?
- [ ] Runbook cho yellow/red và disk watermark đã thử?

### Security

- [ ] TLS cho HTTP và transport?
- [ ] Application dùng least-privilege role/API key?
- [ ] Cluster không public trực tiếp?
- [ ] Secret rotation và audit trail có quy trình?

---

## 26. Câu hỏi phỏng vấn

### Cơ bản

1. Elasticsearch index, shard và Lucene segment khác nhau thế nào?
2. Primary shard và replica shard làm gì?
3. Vì sao write thành công nhưng `_search` chưa thấy document?
4. Green, yellow và red nghĩa là gì?

### Trung cấp

1. Mô tả write path và search query/fetch path.
2. Refresh, flush, translog và merge khác nhau ra sao?
3. Vì sao oversharding làm cluster chậm?
4. Khi nào custom routing có lợi và có rủi ro gì?
5. Vì sao replica không phải backup?

### Nâng cao

1. Cluster ba zone phải thiết kế voting và shard placement thế nào?
2. Làm sao reindex không downtime mà không mất write phát sinh?
3. Chẩn đoán cluster red nhưng allocation explain nói không có valid shard copy?
4. Tại sao thêm coordinating-only node có thể làm cluster-state publication nặng hơn?
5. Chọn shard count/rollover bằng capacity test như thế nào?

---

## 27. Nguồn và chủ đề tiếp theo

Tài liệu chính thức:

- [Node roles](https://www.elastic.co/docs/deploy-manage/distributed-architecture/clusters-nodes-shards/node-roles)
- [Voting configurations](https://www.elastic.co/docs/deploy-manage/distributed-architecture/discovery-cluster-formation/modules-discovery-voting)
- [Reading and writing documents](https://www.elastic.co/docs/deploy-manage/distributed-architecture/reading-and-writing-documents)
- [Near real-time search](https://www.elastic.co/docs/manage-data/data-store/near-real-time-search)
- [Translog settings](https://www.elastic.co/docs/reference/elasticsearch/index-settings/translog)
- [Data lifecycle](https://www.elastic.co/docs/manage-data/lifecycle)
- [Cluster shard allocation](https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/cluster-level-shard-allocation-routing-settings)
- [Elastic release notes](https://www.elastic.co/docs/release-notes)

Học tiếp:

1. [Indexing, Mapping & Analyzers](indexing_mapping.md) – document được biến thành
   term như thế nào.
2. [Query DSL](query_dsl.md) – filter, scoring và search behavior.
3. [Cluster Management](../operations/cluster_management.md) – vận hành, recovery,
   upgrade và incident.
4. [Performance & Optimization](../performance/optimization.md) – benchmark và
   tối ưu theo evidence.

---

*Cập nhật lần cuối: 2026-07-31.*
