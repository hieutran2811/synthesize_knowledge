# Prometheus Production – HA, capacity và long-term storage

> Phiên bản mục tiêu: **Prometheus 3.13.x**.
>
> Điều kiện đầu vào: đã đọc [Prometheus Fundamentals](prometheus_fundamentals.md), [PromQL và Rules](prometheus_advanced.md), [Service Discovery và Relabeling](service_discovery.md).

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- phân biệt HA của scrape, query, alert và storage;
- thiết kế cặp Prometheus độc lập mà không dùng chung data directory;
- ước lượng disk từ ingestion rate và retention bằng số liệu thực tế;
- hiểu giới hạn WAL, local TSDB và remote write;
- chọn local HA, Thanos Sidecar hoặc remote-write platform theo yêu cầu;
- vận hành Thanos Query, Store Gateway và Compactor an toàn hơn;
- lập kế hoạch backup/restore, RPO/RTO và diễn tập sự cố;
- phát hiện cardinality, churn, query hoặc remote-write backlog trước khi quá tải.

---

## 2. “Production-ready” không phải một nút bật

Bốn câu hỏi sau giải quyết bốn failure mode khác nhau:

| Mục tiêu | Câu hỏi |
|---|---|
| Scrape/alert HA | Một Prometheus chết thì target còn được scrape và rule còn được evaluate không? |
| Query HA | Grafana còn query được không, và dữ liệu từ các replica có được deduplicate không? |
| Long-term storage | Khi local retention hết, lịch sử có còn ở nơi khác không? |
| Disaster recovery | Xóa nhầm, bucket lỗi hoặc mất cả hai node thì khôi phục bằng gì, trong bao lâu? |

Mental model:

```text
HA replica       ≠ shared database
load balancer    ≠ deduplication
retention        ≠ backup
remote write     ≠ infinite durable queue
object storage   ≠ tự động có DR
```

Không nên bắt đầu bằng câu “dùng Thanos hay sản phẩm nào?”. Hãy bắt đầu bằng:

```text
RPO cho metrics là bao nhiêu?
RTO của query và alert là bao nhiêu?
Cần giữ raw data bao lâu?
Có cần global query / multi-cluster / multi-tenant không?
Đội vận hành chịu được bao nhiêu component?
```

---

## 3. Local TSDB thực sự bảo đảm điều gì?

Prometheus ghi dữ liệu mới vào head block và WAL, sau đó tạo block khoảng hai giờ và compact các block cũ.

```text
scrape
  │
  ▼
Head in memory + chunks_head
  │ crash recovery
  ├────────────── WAL
  │
  ▼
2-hour blocks ── compact ── larger blocks
```

Các giới hạn cần nhớ:

- local TSDB **không clustered và không replicated**;
- mỗi Prometheus sở hữu data directory riêng;
- không mount cùng một data directory cho hai replica;
- NFS, kể cả nhiều triển khai EFS, không được Prometheus hỗ trợ cho local storage;
- retention mặc định là `15d` nếu không đặt time hoặc size;
- khi cùng đặt retention theo time và size, điều kiện đến trước sẽ xóa block cũ;
- xóa block chỉ diễn ra khi toàn block đã hết hạn, nên phải chừa headroom;
- mất node/disk có thể mất local history dù replica còn lại vẫn tiếp tục monitoring.

Ví dụ flags:

```text
--storage.tsdb.path=/prometheus
--storage.tsdb.retention.time=30d
--storage.tsdb.retention.size=400GB
```

Nếu volume có 500 GB, đặt size retention khoảng 400–425 GB phù hợp với khuyến nghị chừa 15–20% cho WAL, head chunks, compaction và dao động tải. Đây là guardrail, không phải bằng chứng volume chắc chắn đủ.

### Điều không nên làm

```text
prometheus-a ─┐
              ├── cùng mount /prometheus   # sai
prometheus-b ─┘
```

Lock file không biến shared filesystem thành clustered TSDB. Tắt lock để ép hai process cùng ghi có thể dẫn tới corruption.

---

## 4. Capacity planning bằng workload thật

### 4.1 Ingestion rate

Ước lượng ban đầu:

```text
samples_per_second
  ≈ số target × series mỗi target ÷ scrape_interval_seconds
```

Ví dụ:

```text
2.000 targets × 1.500 series ÷ 30s
= 100.000 samples/s
```

Đo thực tế:

```promql
sum(rate(prometheus_tsdb_head_samples_appended_total[5m]))
```

Không dùng riêng `scrape_samples_scraped`: recording rules và các đường ingest khác cũng có thể tạo sample.

### 4.2 Disk

Tài liệu Prometheus đưa ra ước lượng trung bình khoảng 1–2 byte/sample cho persistent blocks:

```text
disk_raw
  ≈ retention_seconds × samples_per_second × bytes_per_sample
```

Với 100.000 samples/s, giữ 30 ngày và tạm tính 1,5 byte/sample:

```text
100.000 × 2.592.000 × 1,5
≈ 388,8 GB
```

Đây chưa phải dung lượng volume cần cấp. Cần cộng:

- WAL và head chunks;
- index, tombstone và metadata;
- khoảng trống cho compaction;
- spike khi deploy hoặc target tăng;
- filesystem overhead và safety margin.

Quy trình đúng:

1. đo ingestion, active series, churn và dung lượng tăng trong ít nhất một chu kỳ tải đại diện;
2. suy ra bytes/sample từ chính workload;
3. chạy load/canary với retention dự kiến;
4. cảnh báo theo cả free bytes và thời gian dự kiến đến khi đầy;
5. đặt `retention.size` không quá khoảng 80–85% volume.

### 4.3 RAM và CPU

Không có công thức đáng tin kiểu “X GB RAM cho một triệu series” áp dụng cho mọi hệ thống. RAM/CPU còn phụ thuộc:

- active series và độ dài label;
- series churn;
- số chunk đang ở head;
- scrape parsing và relabeling;
- query range, số sample được load và concurrency;
- recording/alerting rule;
- remote-write series cache và số queue shard.

Hai hệ thống cùng số series có thể dùng tài nguyên rất khác nếu một hệ thống thay pod liên tục hoặc chạy query dashboard trên 90 ngày.

### 4.4 Cardinality và churn

```promql
# Active series hiện tại
prometheus_tsdb_head_series

# Tốc độ tạo và loại series khỏi head
sum(rate(prometheus_tsdb_head_series_created_total[15m]))
sum(rate(prometheus_tsdb_head_series_removed_total[15m]))
```

Active series cao là lượng trạng thái phải giữ. Churn cao là liên tục tạo label set mới, thường do pod UID, request ID, path chưa chuẩn hóa hoặc label nghiệp vụ không giới hạn.

API hữu ích:

```text
GET /api/v1/status/tsdb
```

Nó giúp tìm metric name, label name/value có cardinality cao; kết quả vẫn phải được phân tích theo owner và giá trị sử dụng.

---

## 5. Mẫu HA cơ bản: hai Prometheus độc lập

Prometheus chính thức khuyến nghị chạy từ hai server giống nhau cho HA:

```text
                     ┌── Prometheus A ── local TSDB A
targets ── scraped ──┤
                     └── Prometheus B ── local TSDB B

Mỗi replica:
- tự discover target
- tự scrape
- tự chạy rule
- tự gửi alert
```

Điều kiện:

- cùng scrape/rule configuration;
- chạy ở failure domain khác nhau khi có thể;
- mỗi replica có persistent volume riêng;
- cùng label `cluster`, khác label `replica`;
- cả hai scrape toàn bộ target nếu mục tiêu là redundancy;
- rollout có canary, tránh restart cả cặp cùng lúc.

Config rút gọn cho replica A:

```yaml
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  external_labels:
    cluster: prod-ap-southeast
    replica: prometheus-a

alerting:
  # Bỏ nhãn phân biệt replica trước khi gửi để hai alert có cùng identity.
  alert_relabel_configs:
    - action: labeldrop
      regex: replica

  # Gửi trực tiếp đến mọi Alertmanager, không đặt một LB ở giữa.
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager-0.monitoring.svc:9093
            - alertmanager-1.monitoring.svc:9093
            - alertmanager-2.monitoring.svc:9093
```

Replica B chỉ đổi:

```yaml
global:
  external_labels:
    cluster: prod-ap-southeast
    replica: prometheus-b
```

`external_labels` được thêm khi giao tiếp với external systems nếu series/alert chưa có nhãn đó. Không dùng label `replica` cho ý nghĩa khác.

### Vì sao cần `alert_relabel_configs`?

Nếu alert từ A có `replica="prometheus-a"` còn alert từ B có `replica="prometheus-b"`, chúng có identity khác nhau. Alertmanager không thể coi đó là hai bản sao của cùng một alert. Bỏ riêng label replica trước khi gửi cho phép Alertmanager HA deduplicate notification; vẫn giữ `cluster` để không gộp alert của hai cluster khác nhau.

---

## 6. Query HA và dedup là hai việc khác nhau

### Chỉ đặt load balancer trước hai Prometheus

```text
Grafana → LB → Prometheus A hoặc B
```

Kết quả:

- endpoint query vẫn khả dụng khi một replica chết;
- mỗi request chỉ thấy local history của replica được chọn;
- LB không merge hai TSDB;
- kết quả có thể lệch nhẹ do scrape timing hoặc missed scrape;
- sticky/non-sticky routing có trade-off riêng.

### Dùng query layer có dedup

```text
Grafana → Thanos Query
              ├── Sidecar A → Prometheus A
              └── Sidecar B → Prometheus B
```

Thanos Query có thể coi `replica` là nhãn bản sao và merge series trùng:

```text
thanos query \
  --query.replica-label=replica \
  --endpoint=prometheus-a-sidecar:10901 \
  --endpoint=prometheus-b-sidecar:10901
```

Dedup chỉ đúng khi:

- các replica thực sự scrape cùng logical target;
- mọi external label trừ replica nhất quán;
- replica label được khai báo đúng;
- clock và scrape configuration không lệch bất thường.

Có thể dùng `dedup=false` khi chẩn đoán để nhìn riêng từng replica.

---

## 7. HA không đồng nghĩa sharding

| Mô hình | Mục tiêu | Mỗi target được scrape |
|---|---|---:|
| Hai replica giống nhau | HA | 2 lần |
| Hai shard chia target | Scale | 1 lần |
| Hai bộ shard giống nhau | Scale + HA | 2 lần |

Ví dụ hai shard:

```text
targets ── hashmod ──┬── shard 0
                     └── shard 1
```

Nếu shard 0 chết, target thuộc shard 0 không còn được scrape. Muốn cả scale và HA:

```text
replica group A: shard 0A + shard 1A
replica group B: shard 0B + shard 1B
```

Hash key phải ổn định. Thay số shard gây phân bố lại target và có thể tạo khoảng trống/overlap ngắn trong rollout.

---

## 8. Chọn kiến trúc lưu dài hạn

| Phương án | Phù hợp khi | Cần chấp nhận |
|---|---|---|
| Local HA pair | Quy mô vừa, retention vừa, ưu tiên đơn giản | Hai history độc lập; không global dedup/history |
| Thanos Sidecar + object storage | Đã dùng Prometheus, cần global query và block-based long-term storage | Thêm Query, Store, Compactor, bucket và StoreAPI |
| Remote write đến backend | Cần central ingestion, multi-tenant hoặc platform managed | Phụ thuộc receiver, network, quota và semantics dedup |
| Prometheus Agent + remote backend | Edge chỉ scrape/forward, query/rule ở trung tâm | Không local query, rule hoặc alert; buffer hữu hạn |
| Federation | Cần aggregate/chọn series giữa các Prometheus | Không tự cung cấp durable long-term storage hoặc HA dedup |

Đừng chọn bằng bảng benchmark chung. Hãy thử với:

- cardinality và churn thật;
- query mix và retention thật;
- node/AZ/network/bucket failure;
- upgrade, restore và cost model;
- protocol/features thực sự cần như exemplars hoặc native histograms.

---

## 9. Remote write: đường truyền, không phải backup stream vô hạn

Luồng dữ liệu:

```text
Prometheus WAL
   └── remote-write queue shards
          └── HTTP batches
                 └── receiver
```

Prometheus tự điều chỉnh số shard theo rate, backlog và latency. Tăng `max_shards` ngay từ đầu có thể làm receiver quá tải và tăng RAM.

Theo tài liệu tuning hiện tại:

- lỗi có thể được retry mà không mất dữ liệu trong cửa sổ WAL;
- nếu receiver không hoạt động quá khoảng hai giờ, WAL có thể bị compact và sample chưa gửi bị mất;
- remote write tăng RAM, CPU và network;
- churn làm series cache tốn RAM hơn;
- một queue shard đầy có thể chặn việc đọc WAL cho các shard khác của cùng destination.

Config tối thiểu, ưu tiên defaults rồi đo:

```yaml
global:
  external_labels:
    cluster: prod-ap-southeast
    replica: prometheus-a

remote_write:
  - name: central_metrics
    url: https://metrics.example.internal/api/v1/push
    authorization:
      credentials_file: /run/secrets/remote-write-token
    tls_config:
      ca_file: /run/secrets/internal-ca.pem

    queue_config:
      # Chỉ chỉnh sau khi đã đo backlog, receiver latency, RAM và network.
      capacity: 10000
      min_shards: 1
      max_shards: 20
      max_samples_per_send: 2000
```

Lưu ý:

- không commit token vào YAML;
- `write_relabel_configs` chạy **sau** external labels;
- drop ở write relabel chỉ giảm dữ liệu gửi đi, không giảm local scrape/ingestion;
- Remote Write 2.0 gửi metadata, start timestamp và native histogram hiệu quả hơn, nhưng phải kiểm tra receiver hỗ trợ trước khi đổi `protobuf_message`;
- khi cả hai Prometheus cùng remote write, backend phải có contract HA dedup hoặc sẽ lưu hai bản;
- không xóa label replica trước khi hiểu cơ chế HA tracking/dedup của receiver.

Ví dụ chỉ gửi allowlist recording rules:

```yaml
remote_write:
  - name: long_term
    url: https://metrics.example.internal/api/v1/push
    write_relabel_configs:
      - source_labels: [__name__]
        regex: 'job:.*|service:.*|slo:.*'
        action: keep
```

Đây là quyết định dữ liệu: dashboard/forensics cần raw metrics sẽ không truy cập được lịch sử đã drop.

### Prometheus Agent

Agent mode giữ discovery, scrape và remote write nhưng không có local query, rule, alert hay full local TSDB. WAL của Agent chỉ là buffer tạm, hiện cũng giới hạn khoảng hai giờ. Vì vậy Agent phù hợp collector ở edge khi backend trung tâm đủ tin cậy; nó không phải Prometheus HA độc lập.

---

## 10. Thanos Sidecar: kiến trúc block-based

```text
                         recent data
Prometheus A ↔ Sidecar A ─────────────┐
       │                              │
       └── 2h blocks ─┐               │
                      ▼               ▼
                   Object         Thanos Query ← Grafana
                   Storage            ▲
                      ▲                │
Prometheus B ↔ Sidecar B ──────────────┤
       └── 2h blocks ─┘                │
                                      │
                  Store Gateway ───────┘ historical blocks
                         ▲
                         │
                     Object Storage

Compactor ↔ Object Storage: compact + downsample + retention
Query Frontend → Query: optional split/cache cho query range
```

### Trách nhiệm từng component

| Component | Trách nhiệm | Có giữ source of truth? |
|---|---|---|
| Sidecar | Expose recent Prometheus data qua StoreAPI; upload block | Không |
| Query | Fan-out PromQL và deduplicate replica | Stateless |
| Query Frontend | Split, retry, cache query range | Cache không phải source of truth |
| Store Gateway | Đọc block trong bucket và expose StoreAPI | Bucket là source of truth |
| Compactor | Compact, downsample, retention, đánh dấu/xóa block | Có quyền thay đổi/xóa bucket data |
| Ruler | Evaluate rules qua query layer | Rule state/data cần thiết kế HA riêng |
| Receive | Nhận remote write, ghi TSDB và upload block | Ingestion path khác Sidecar |

Không cần deploy mọi component ngay. Sidecar + Query có thể dùng cho global view gần realtime; thêm bucket + Store + Compactor khi cần long-term storage.

---

## 11. Contract quan trọng của Thanos Sidecar

Prometheus phải có external labels duy nhất trong toàn Thanos system:

```yaml
global:
  external_labels:
    cluster: prod-ap-southeast
    replica: prometheus-a
```

Khi Sidecar upload block và dùng Thanos Compactor, tài liệu Thanos yêu cầu tắt local compaction bằng cách đặt min/max block duration bằng nhau, khuyến nghị `2h`:

```text
prometheus \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.min-block-duration=2h \
  --storage.tsdb.max-block-duration=2h \
  --storage.tsdb.retention.time=24h \
  --web.enable-admin-api

thanos sidecar \
  --tsdb.path=/prometheus \
  --prometheus.url=http://127.0.0.1:9090 \
  --objstore.config-file=/etc/thanos/bucket.yml
```

Các điểm vận hành:

- Prometheus và Sidecar phải cùng nhìn đúng TSDB path;
- dùng persistent volume cho Prometheus;
- local retention tối thiểu Thanos khuyến nghị là ba lần block duration, tức 6 giờ với block 2 giờ;
- production thường giữ nhiều hơn 6 giờ để chịu bucket/network outage theo RPO mong muốn;
- Sidecar upload block hoàn tất, không biến head data thành durable object ngay lập tức;
- `--web.enable-admin-api` mở API có khả năng thay đổi dữ liệu, nên chỉ expose nội bộ và bảo vệ bằng network/auth proxy;
- `--web.enable-lifecycle` chỉ cần nếu dùng tính năng reload qua HTTP/Sidecar reloader.

Không copy image tag cũ. Pin Prometheus và Thanos vào version đã test trong deployment, đọc release notes rồi canary từng replica.

---

## 12. Object storage không chỉ là tạo một bucket

Bucket config nên được mount từ secret/config quản lý ngoài repo:

```yaml
# /etc/thanos/bucket.yml – ví dụ cấu trúc, không chứa static key trong Git
type: S3
config:
  bucket: metrics-prod
  endpoint: s3.ap-southeast-1.amazonaws.com
  region: ap-southeast-1
```

Checklist:

- workload identity/IAM role thay cho access key dài hạn;
- Sidecar chỉ cần upload/read cần thiết;
- Store Gateway chỉ read;
- Compactor cần read/write/delete;
- TLS và private endpoint khi phù hợp;
- encryption, audit log và access log;
- bucket versioning/object lock nếu DR policy yêu cầu và đã thử tương thích;
- quota, request rate, egress và lifecycle cost;
- không để provider lifecycle tự xóa block trái với retention/compaction contract;
- giám sát partial upload, upload lag và compactor halt.

Compactor là component duy nhất nên xóa block trong luồng Thanos chuẩn. Xóa object thủ công có thể làm index/metadata và query view không nhất quán.

---

## 13. Store Gateway và Query

Store Gateway đọc metadata/index/chunk từ bucket và dùng local disk/cache để giảm tải. Local cache có thể tái tạo; bucket mới là source of truth.

```text
thanos store \
  --data-dir=/var/thanos/store \
  --objstore.config-file=/etc/thanos/bucket.yml

thanos query \
  --query.replica-label=replica \
  --endpoint=dnssrv+_grpc._tcp.thanos-sidecars.monitoring.svc \
  --endpoint=dnssrv+_grpc._tcp.thanos-stores.monitoring.svc
```

Production:

- chạy nhiều Query replica sau service/LB;
- discovery StoreAPI động thay vì hard-code pod IP;
- cache/index-header disk cho Store Gateway có capacity/latency phù hợp;
- scale Store Gateway bằng cơ chế sharding chính thức, không tự tạo pseudo-label như `__block_id` nếu component không cung cấp;
- đặt query timeout/concurrency theo SLO và capacity;
- quyết định rõ partial response: trả thiếu dữ liệu có warning hay fail toàn query;
- giám sát StoreAPI endpoint health và bucket sync.

Thêm Query Frontend khi query range dài cần split/retry/cache. Cache giúp latency/cost nhưng không sửa query PromQL có cardinality bùng nổ.

---

## 14. Compactor: singleton theo block stream, không phải “một pod cho cả đời”

Compactor compact block, downsample và áp retention:

```text
thanos compact \
  --data-dir=/var/thanos/compact \
  --objstore.config-file=/etc/thanos/bucket.yml \
  --wait \
  --retention.resolution-raw=30d \
  --retention.resolution-5m=180d \
  --retention.resolution-1h=2y
```

Retention trên chỉ là ví dụ. Phải xuất phát từ yêu cầu điều tra, SLO reporting, compliance và chi phí.

Safety rules:

- không chạy đồng thời nhiều Compactor trên cùng một block stream;
- mặc định xem Compactor là singleton đối với bucket;
- nếu cần scale, dùng label sharding/compaction-group design được Thanos hỗ trợ và chứng minh không overlap;
- persistent disk giúp giữ bucket state cache, nhưng dữ liệu trung gian có thể tái tạo;
- cấp disk theo block lớn nhất và concurrency, không theo một con số chung;
- đặt Compactor gần bucket để giảm bandwidth/latency;
- alert ngay khi `thanos_compact_halted == 1`;
- Compactor tạm ngừng thường chưa làm mất ingest, nhưng backlog kéo dài làm nhiều block nhỏ, thiếu downsample và retention không được thực thi.

Downsampling giảm số điểm cho query cũ, không giữ nguyên độ phân giải raw. Hãy thử dashboard/report với từng resolution trước khi xóa raw.

---

## 15. Thanos Receive khác Sidecar

| Sidecar | Receive |
|---|---|
| Đặt cạnh Prometheus full server | Là remote-write receiver |
| Upload block do Prometheus tạo | Tự ghi TSDB rồi upload block |
| Query recent data từ Prometheus | Query recent data từ Receive |
| Phù hợp mở rộng kiến trúc Prometheus hiện có | Phù hợp push/egress-only, central ingestion, multi-tenancy |

Receive có hashring, replication, tenant và limits; nó là một ingestion platform cần capacity, HA và failure testing riêng. HTTP `413` do vượt request limit có thể gây mất toàn request ở client, nên phải thống nhất limits với sender và monitor rejection.

Không thay Sidecar bằng Receive chỉ vì muốn “ít disk local”. Cả hai vẫn cần persistent local storage để giảm mất dữ liệu khi process/node lỗi.

---

## 16. Rules đặt ở đâu?

Ba lựa chọn thường gặp:

| Vị trí | Điểm mạnh | Rủi ro |
|---|---|---|
| Prometheus replica | Alert không phụ thuộc global query path; gần dữ liệu scrape | Mỗi replica evaluate riêng; recording series trùng ở global view |
| Thanos Ruler | Rule trên dữ liệu multi-cluster/long-term | Phụ thuộc Query/Store; partial response và duplicate rule state cần xử lý |
| Remote backend ruler | Tập trung, thường hỗ trợ tenant | Phụ thuộc semantics và availability của backend |

Nguyên tắc thực dụng:

- page quan trọng về target/service local nên vẫn hoạt động khi bucket/global query lỗi;
- global SLO/report có thể chạy ở Ruler/backend;
- cùng một alert không được vô tình evaluate ở hai tầng;
- rule owner, source of truth và dedup label phải rõ;
- test failure của query dependency, không chỉ test biểu thức PromQL.

---

## 17. Backup, restore, RPO và RTO

### Local TSDB snapshot

Prometheus khuyến nghị snapshot cho backup. Admin API phải được bật:

```text
POST /api/v1/admin/tsdb/snapshot
```

Snapshot được tạo dưới:

```text
<storage.tsdb.path>/snapshots/<snapshot-name>
```

Luồng an toàn:

1. gọi snapshot qua endpoint chỉ truy cập nội bộ;
2. copy đúng snapshot hoàn tất sang backup storage;
3. ghi version Prometheus, flags, config/rules và checksum;
4. restore vào data directory mới, không ghi đè node đang chạy;
5. khởi động cùng version tương thích;
6. query các khoảng thời gian và kiểm tra rule/dashboard;
7. định kỳ diễn tập, đo RTO thật.

Backup filesystem đang chạy mà không snapshot có thể mất phần dữ liệu gần nhất. Khi backup/restore block mà loại `wal/`, `chunks_head/`, `wbl/`, dữ liệu sẽ nhất quán hơn nhưng mất cửa sổ nằm trong head/WAL.

### Long-term storage DR

Object storage durability không bảo vệ khỏi mọi lỗi:

- credential bị lộ và xóa object;
- Compactor/retention cấu hình sai;
- bucket/prefix bị xóa;
- lỗi ứng dụng ghi block;
- mất quyền hoặc outage theo region;
- restore quá chậm so với RTO.

Cần quyết định:

| Thành phần | Ví dụ quyết định |
|---|---|
| RPO | Chấp nhận mất tối đa 2 giờ block chưa upload hay cần remote write song song? |
| RTO | Query lịch sử phải phục hồi trong 1 giờ hay 1 ngày? |
| Bản sao | Versioning, replication khác account/region hoặc backup độc lập |
| Quyền | Tách role uploader, reader, compactor và backup |
| Kiểm thử | Restore một prefix/bucket thử và chạy query kiểm chứng |

Retention chỉ trả lời “giữ bao lâu”, không trả lời “khôi phục thế nào”.

---

## 18. Monitoring Prometheus

Tên self-metric có thể thay đổi theo version; xác minh trên `/metrics` của binary đang chạy trước khi đưa vào rule.

### Ingestion và cardinality

```promql
prometheus_tsdb_head_series

sum(rate(prometheus_tsdb_head_samples_appended_total[5m]))

sum(rate(prometheus_tsdb_head_series_created_total[15m]))

sum(rate(prometheus_tsdb_head_series_removed_total[15m]))
```

### Process và query

```promql
process_resident_memory_bytes

rate(process_cpu_seconds_total[5m])

histogram_quantile(
  0.99,
  sum by (le) (
    rate(prometheus_engine_query_duration_seconds_bucket[5m])
  )
)
```

Không dùng p99 aggregate trên mọi query để thay query log. Một vài dashboard rất đắt có thể bị che bởi lượng query nhanh.

### Scrape và rule

`scrape_timeout_seconds` là một trong các extra scrape metrics. Bật rõ ràng ở global hoặc scrape job cần theo dõi:

```yaml
global:
  extra_scrape_metrics: true
```

```promql
up == 0

scrape_duration_seconds
  / scrape_timeout_seconds
> 0.8

prometheus_rule_group_last_duration_seconds
  / prometheus_rule_group_interval_seconds
> 0.8
```

### Remote write

```promql
prometheus_remote_storage_samples_pending

sum by (remote_name) (
  rate(prometheus_remote_storage_samples_failed_total[5m])
)

sum by (remote_name) (
  rate(prometheus_remote_storage_samples_retried_total[5m])
)

time()
- min by (remote_name) (
    prometheus_remote_storage_queue_highest_sent_timestamp_seconds
  )
```

Theo dõi thêm dropped samples, current/desired shards, network saturation và receiver-side rejection. Backlog bằng 0 không chứng minh dữ liệu đúng nếu write relabel hoặc receiver đã drop.

### Disk

Dùng node/container filesystem metrics cho volume TSDB:

```promql
node_filesystem_avail_bytes{mountpoint="/prometheus"}
/
node_filesystem_size_bytes{mountpoint="/prometheus"}
< 0.15
```

Đồng thời theo dõi tốc độ giảm free space để cảnh báo theo “giờ còn lại”, không chỉ một ngưỡng phần trăm.

---

## 19. Các failure drill nên chạy

| Drill | Điều cần chứng minh |
|---|---|
| Kill một Prometheus | Replica kia tiếp tục scrape/rule; Grafana/query endpoint còn dùng được |
| Chặn một target từ một replica | Dedup query không che mất việc replica đó đang hỏng |
| Chặn Alertmanager | Queue/retry/notification SLO được quan sát |
| Chặn remote-write receiver hơn buffer | Biết chính xác điểm bắt đầu mất sample và cách phát hiện |
| Chặn object storage | Sidecar backlog còn nằm trên local disk đủ lâu |
| Kill Store Gateway | Query recent/historical có behavior đúng với partial-response policy |
| Dừng Compactor | Có alert; backlog và retention impact được hiểu |
| Full disk canary | Retention/headroom/alert phản ứng trước khi TSDB ngừng ghi |
| Restore snapshot/bucket | Đo RPO/RTO bằng query và dashboard thật |

Failure drill phải có rollback và không chạy thẳng trên toàn production lần đầu.

---

## 20. Rollout và upgrade

```text
1. Pin version + đọc release notes
2. promtool check config/rules
3. Canary một replica/shard
4. So targets, active series, ingestion, rule health
5. So query result giữa old/new
6. Kiểm tra remote-write/Sidecar backlog
7. Đợi ít nhất một block cycle nếu thay storage path
8. Roll replica kế tiếp
9. Giữ rollback artifact và backup tương thích
```

Không upgrade đồng thời:

- cả hai Prometheus replica;
- toàn bộ Query/Store;
- Prometheus và remote backend protocol;
- Compactor cùng retention policy mới.

Thay một biến mỗi lần giúp phân biệt lỗi binary, config, storage format và query semantics.

---

## 21. Anti-patterns

### “Hai replica dùng chung PVC để tiết kiệm disk”

Local TSDB không hỗ trợ clustered/shared write. Dùng hai PVC.

### “Đã có hai Prometheus nên không cần backup”

Hai replica có thể cùng bị xóa bởi automation, credential hoặc failure domain chung.

### “LB trước hai Prometheus là đã dedup”

LB chọn một backend; nó không merge series.

### “Tăng `max_shards` sẽ chữa mọi remote-write lag”

Nút thắt có thể là receiver, network, CPU hoặc churn. Tăng shard còn có thể làm receiver và RAM tệ hơn.

### “Object lifecycle tự chuyển/xóa tùy ý”

Thanos Compactor cần điều phối metadata và deletion mark. Lifecycle ngoài hệ thống có thể phá contract.

### “Giữ mọi raw metric mãi mãi”

Chi phí không chỉ là object bytes mà còn index, query scan, cache và thời gian điều tra. Retention phải theo use case.

### “Một rule global cho mọi page”

Global query path lỗi có thể làm mất alert đúng lúc cần nhất. Giữ alert local quan trọng độc lập khi phù hợp.

---

## 22. Thiết kế tham khảo theo giai đoạn

### Giai đoạn A – workload vừa

```text
2 Prometheus độc lập
3 Alertmanager thành cluster
Grafana → LB → Prometheus replicas
Local retention theo disk budget
Snapshot backup + restore drill
```

Chấp nhận chưa dedup/global history.

### Giai đoạn B – cần global query và long-term

```text
2 Prometheus + 2 Sidecar
Object storage
2+ Query
2+ Store Gateway theo capacity
1 Compactor per block stream
Optional Query Frontend
Grafana → Query Frontend/Query
```

Giữ alert local quan trọng trên Prometheus.

### Giai đoạn C – nhiều cluster/team

```text
Collector/Prometheus/Agent tại cluster
→ remote-write platform hoặc Thanos Receive
→ tenant-aware query/rules
→ quotas + limits + chargeback/capacity ownership
```

Ở giai đoạn này, control plane, tenant isolation, per-tenant limits và upgrade strategy quan trọng không kém TSDB.

---

## 23. Checklist production

### Availability

- [ ] Tối thiểu hai Prometheus ở failure domain phù hợp.
- [ ] Mỗi replica có data directory/PVC riêng.
- [ ] Config giống nhau, `replica` khác nhau.
- [ ] Alert replica label được relabel trước Alertmanager.
- [ ] Prometheus gửi trực tiếp đến mọi Alertmanager.
- [ ] Query availability và query dedup được thiết kế riêng.
- [ ] Sharding không bị nhầm với HA.

### Capacity

- [ ] Có số liệu samples/s, active series và churn thực.
- [ ] Disk được tính từ bytes/sample quan sát được.
- [ ] Size retention không chiếm quá khoảng 80–85% volume.
- [ ] Có headroom cho WAL/head/compaction/spike.
- [ ] Query/rule cost được load-test.
- [ ] Có budget và owner cho cardinality.

### Remote write / Thanos

- [ ] Receiver compatibility và dedup contract được ghi rõ.
- [ ] Remote-write lag, retry, failed và dropped được alert.
- [ ] Sidecar external labels duy nhất.
- [ ] Thanos block duration/compaction contract đúng.
- [ ] Local retention chịu được bucket outage mục tiêu.
- [ ] Object-store IAM theo least privilege.
- [ ] Compactor không overlap block stream.
- [ ] Partial-response policy được thống nhất.

### DR và security

- [ ] RPO/RTO được định nghĩa bằng số.
- [ ] Snapshot/bucket restore được diễn tập.
- [ ] Retention không bị coi là backup.
- [ ] Admin API không public.
- [ ] Token/key không nằm trong repo.
- [ ] Network/TLS/audit log được cấu hình.
- [ ] Upgrade từng replica/component và có rollback.

---

## 24. Câu hỏi tự kiểm tra

1. Vì sao hai Prometheus HA không được dùng chung data directory?
2. Load balancer khác query dedup ở đâu?
3. Vì sao cần bỏ label `replica` trước khi gửi alert?
4. Hai shard có thay thế hai HA replica không?
5. Tại sao retention size nên thấp hơn dung lượng volume?
6. Công thức disk ban đầu cần thêm những headroom nào?
7. Vì sao không có một tỷ lệ RAM/active-series đúng cho mọi hệ thống?
8. Remote write có thể mất sample khi receiver down lâu vì sao?
9. `write_relabel_configs` có giảm local ingestion không?
10. Agent mode mất những khả năng nào?
11. Sidecar cần min/max block duration bằng nhau khi nào?
12. Vì sao local retention 6 giờ chỉ là mức tối thiểu của Thanos, không phải mặc định production tốt?
13. Store Gateway local disk có phải source of truth không?
14. Compactor có thể scale ngang tùy ý không?
15. Object storage durability khác backup/DR thế nào?
16. Alert nào nên giữ local thay vì evaluate qua global query?
17. Metric nào cho biết remote write đang tụt lại?
18. Failure drill nào chứng minh RPO/RTO thay vì chỉ chứng minh pod restart?

---

## 25. Tài liệu chính thức

- [Prometheus storage](https://prometheus.io/docs/prometheus/latest/storage/)
- [Prometheus FAQ – High availability](https://prometheus.io/docs/introduction/faq/#can-prometheus-be-made-highly-available)
- [Prometheus remote write tuning](https://prometheus.io/docs/practices/remote_write/)
- [Prometheus remote write configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#remote_write)
- [Prometheus Agent mode](https://prometheus.io/docs/prometheus/latest/prometheus_agent/)
- [Prometheus TSDB Admin APIs và snapshot](https://prometheus.io/docs/prometheus/latest/querying/api/#tsdb-admin-apis)
- [Alertmanager high availability](https://prometheus.io/docs/alerting/latest/alertmanager/#high-availability)
- [Thanos Sidecar](https://thanos.io/tip/components/sidecar.md/)
- [Thanos Query](https://thanos.io/tip/components/query.md/)
- [Thanos Store Gateway](https://thanos.io/tip/components/store.md/)
- [Thanos Compactor](https://thanos.io/tip/components/compact.md/)
- [Thanos Query Frontend](https://thanos.io/tip/components/query-frontend.md/)
- [Thanos Receive](https://thanos.io/tip/components/receive.md/)
- [Thanos object storage](https://thanos.io/tip/thanos/storage.md/)

---

## Chủ đề tiếp theo

[Grafana Fundamentals – datasource, dashboard, panel, variable và Explore](../grafana/grafana_fundamentals.md)

---

*Cập nhật lần cuối: 2026-07-29*
