---
title: "Prometheus Fundamentals – Từ `/metrics` đến quyết định vận hành"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 20
---
# Prometheus Fundamentals – Từ `/metrics` đến quyết định vận hành

> Thuật ngữ: [Glossary](../glossary.md).

> Phiên bản mục tiêu: **Prometheus 3.13.x**.
> Mục tiêu của bài: hiểu đúng một sample đi từ ứng dụng đến PromQL, chọn metric type hợp lý và tự chẩn đoán được lỗi scrape/cardinality cơ bản.

---

## 1. Prometheus giải quyết bài toán gì?

Khi hệ thống chậm, câu hỏi hữu ích không phải chỉ là “server còn sống không?” mà còn là:

- request đang tăng hay giảm?
- lỗi tập trung ở service, route hoặc status nào?
- p95 latency có vượt SLO không?
- queue còn bao nhiêu phần tử và có đang phình ra?
- target nào Prometheus không thu thập được?

**Prometheus** là hệ thống monitoring và alerting mã nguồn mở, thu thập các phép đo dạng time series, lưu chúng trong TSDB và cho phép truy vấn bằng PromQL.

Mental model ngắn gọn:

```text
Ứng dụng / exporter
    │ expose HTTP /metrics
    ▼
Prometheus
    ├── phát hiện target
    ├── định kỳ scrape
    ├── ghi sample vào local TSDB
    ├── chạy PromQL và rules
    └── gửi alert đang firing sang Alertmanager
             │
             └── route / group / deduplicate / notify
```

Ví dụ đời thường:

- `/metrics` giống bảng đồng hồ được đặt trước cửa từng cửa hàng;
- Prometheus giống nhân viên đi đọc đồng hồ theo lịch;
- TSDB là sổ ghi lại mỗi lần đọc;
- PromQL là cách hỏi sổ;
- alerting rule là điều kiện cần báo động;
- Alertmanager là tổng đài quyết định gộp và gửi báo động cho ai.

Prometheus chủ yếu trả lời **“điều gì đang xảy ra theo thời gian?”**. Nó không thay thế:

| Nhu cầu | Công cụ phù hợp hơn |
|---|---|
| Nội dung chi tiết của một request/event | Logs |
| Đường đi của một request qua nhiều service | Distributed tracing |
| Phân tích nghiệp vụ tùy ý trên dữ liệu thô | Data warehouse / analytics system |
| Lưu metric dài hạn, global query, multi-tenant ở quy mô lớn | Remote storage hoặc hệ thống mở rộng quanh Prometheus |

---

## 2. Năm khái niệm phải phân biệt

| Khái niệm | Cách hiểu thực hành |
|---|---|
| **Metric** | Đại lượng muốn đo, ví dụ tổng request hoặc thời gian xử lý. |
| **Label** | Chiều dùng để cắt/lọc metric, ví dụ `method="GET"`. |
| **Time series** | Một metric name cộng với **một bộ label duy nhất**. |
| **Sample** | Giá trị của một time series tại một thời điểm. |
| **Target** | HTTP endpoint mà Prometheus sẽ scrape. |

Ví dụ:

```text
http_requests_total{job="api", instance="api-1:8080", method="GET", status="200"} 4312
```

Trong đó:

- metric name: `http_requests_total`;
- label set: `job`, `instance`, `method`, `status`;
- sample value: `4312`;
- timestamp thường do Prometheus gắn tại thời điểm scrape;
- toàn bộ metric name + label set xác định một time series.

Đổi bất kỳ label value nào sẽ tạo series khác:

```text
http_requests_total{method="GET",  status="200"}  # series A
http_requests_total{method="GET",  status="500"}  # series B
http_requests_total{method="POST", status="200"}  # series C
```

### Cardinality là phép nhân

Giả sử một metric có:

- 10 giá trị `service`;
- 20 giá trị `instance`;
- 8 giá trị `route`;
- 5 giá trị `status`.

Số series tối đa gần đúng:

```text
10 × 20 × 8 × 5 = 8.000 series
```

Nếu thêm `user_id` có 1.000.000 giá trị, chi phí có thể bùng nổ. Mỗi series mới đều tiêu tốn RAM, CPU, disk, network và làm query/index nặng hơn.

Quy tắc:

```text
Label tốt:
  service, method, route-template, status_code, region, result

Label nguy hiểm:
  user_id, email, request_id, trace_id, raw_url, exception_message
```

`route="/orders/{id}"` là label hợp lý; `path="/orders/928374"` thường không hợp lý.

---

## 3. Pull model và một vòng scrape

Prometheus dùng pull model qua HTTP trong luồng phổ biến:

```text
1. Service discovery trả về danh sách target tiềm năng
2. Relabeling giữ, bỏ hoặc sửa target/label
3. Prometheus GET http://target/metrics
4. Target trả exposition format
5. Metric relabeling có thể giữ/bỏ/sửa sample
6. Sample hợp lệ được append vào TSDB
7. Prometheus sinh metric up cho lần scrape đó
```

Ví dụ exposition text:

```text
# HELP shop_orders_created_total Total number of created orders.
# TYPE shop_orders_created_total counter
shop_orders_created_total{channel="web"} 120
shop_orders_created_total{channel="mobile"} 87

# HELP shop_pending_orders Current number of pending orders.
# TYPE shop_pending_orders gauge
shop_pending_orders 14
```

### `job`, `instance` và `up`

Prometheus thường gắn:

- `job`: nhóm target có cùng mục đích scrape;
- `instance`: địa chỉ target, trừ khi config relabel thành giá trị khác;
- `up`: kết quả lần scrape, `1` là thành công và `0` là thất bại.

Ba trạng thái không giống nhau:

```text
up{job="api"} == 1
  → target được discover và scrape thành công

up{job="api"} == 0
  → target được discover nhưng scrape thất bại

không có up{job="api"}
  → có thể target không còn được discover, bị relabel drop,
    config sai hoặc Prometheus chưa có series phù hợp
```

Vì vậy `absent(up{job="api"})` và `up{job="api"} == 0` trả lời hai câu hỏi khác nhau.

### Pull không có nghĩa là “không cần network rule”

Prometheus vẫn phải kết nối được tới endpoint của target. Cần cho phép traffic **từ Prometheus đến metrics port**, đồng thời bảo vệ endpoint và Prometheus UI/API khỏi truy cập không mong muốn.

---

## 4. Bốn metric type

Instrumentation library cung cấp bốn type cốt lõi. Prometheus server lưu hầu hết type cổ điển thành các float time series; native histogram là sample dạng cấu trúc riêng.

| Type | Giá trị | Dùng khi | Query điển hình |
|---|---|---|---|
| **Counter** | Chỉ tăng, có thể reset khi process restart | tổng request, lỗi, byte đã xử lý | `rate()`, `increase()` |
| **Gauge** | Tăng hoặc giảm | queue size, connection hiện tại, nhiệt độ | đọc trực tiếp, `avg_over_time()` |
| **Histogram** | Đếm phân phối quan sát theo bucket | latency, request size | `histogram_quantile()` |
| **Summary** | Tính quantile ở client trong sliding window | trường hợp quantile cục bộ đặc biệt | đọc quantile đã xuất |

### 4.1 Counter

```text
shop_orders_created_total 0 → 4 → 9 → 2
                                    ↑ process restart/reset
```

Không lấy trung bình trực tiếp giá trị counter:

```promql
# Sai ý nghĩa: giá trị tích lũy phụ thuộc tuổi process
avg(shop_orders_created_total)

# Đúng: tốc độ tăng trung bình mỗi giây
sum by (channel) (
  rate(shop_orders_created_total[5m])
)
```

`rate()` hiểu counter reset. Tự lấy `last - first` có thể biến reset thành số âm.

### 4.2 Gauge

```promql
# Số order đang chờ hiện tại
shop_pending_orders

# Giá trị lớn nhất trong 30 phút
max_over_time(shop_pending_orders[30m])

# Dung lượng còn trống theo phần trăm
100 *
node_filesystem_avail_bytes{mountpoint="/"}
/
node_filesystem_size_bytes{mountpoint="/"}
```

Không dùng `rate()` cho gauge thông thường: gauge có quyền giảm nên “counter reset correction” không có ý nghĩa.

### 4.3 Classic histogram

Một classic histogram `http_request_duration_seconds` tạo ra:

```text
http_request_duration_seconds_bucket{le="0.1"} ...
http_request_duration_seconds_bucket{le="0.25"} ...
http_request_duration_seconds_bucket{le="0.5"} ...
http_request_duration_seconds_bucket{le="+Inf"} ...
http_request_duration_seconds_sum ...
http_request_duration_seconds_count ...
```

Bucket là **cumulative**: bucket `le="0.5"` đã bao gồm các quan sát nằm trong bucket nhỏ hơn.

Tính p95 theo route:

```promql
histogram_quantile(
  0.95,
  sum by (le, route) (
    rate(http_request_duration_seconds_bucket[5m])
  )
)
```

Tính average latency:

```promql
sum by (route) (rate(http_request_duration_seconds_sum[5m]))
/
sum by (route) (rate(http_request_duration_seconds_count[5m]))
```

Sai lầm phổ biến:

- bucket không phủ được SLO hoặc phân phối thực tế;
- đổi bucket giữa các instance rồi vẫn aggregate chung;
- bỏ label `le` khi aggregate classic histogram;
- coi p95 là “95% request mất đúng từng đó thời gian”.

Đúng hơn: p95 là ước lượng ngưỡng mà khoảng 95% quan sát không vượt quá.

### 4.4 Native histogram trong Prometheus 3

Native histogram là một sample cấu trúc chứa count, sum và sparse buckets. Từ Prometheus 3.8, tính năng này đã stable, nhưng việc scrape vẫn cần bật rõ trong cấu hình:

```yaml
scrape_configs:
  - job_name: api
    scrape_native_histograms: true
    static_configs:
      - targets: ["api:8080"]
```

Nếu remote write native histogram, phía gửi còn cần:

```yaml
remote_write:
  - url: https://metrics.example.com/api/v1/write
    send_native_histograms: true
```

Query p95 native histogram không cần label `le`:

```promql
histogram_quantile(
  0.95,
  sum by (route) (
    rate(http_request_duration_seconds[5m])
  )
)
```

Chỉ bật sau khi kiểm tra client library, scrape path, remote storage và dashboard/rule đều hỗ trợ. “Stable trong Prometheus” không tự động đảm bảo mọi thành phần trong pipeline đã tương thích.

### 4.5 Summary

Summary tính quantile ở phía client:

```text
rpc_duration_seconds{quantile="0.5"} ...
rpc_duration_seconds{quantile="0.95"} ...
rpc_duration_seconds_sum ...
rpc_duration_seconds_count ...
```

Điểm cần nhớ:

- quantile của nhiều instance **không aggregate có ý nghĩa** bằng phép `avg`;
- quantile và error được quyết định khi instrument;
- chi phí tính nằm ở client;
- histogram thường phù hợp hơn khi cần aggregate toàn service.

Không làm:

```promql
# Không tạo ra p95 toàn service
avg(rpc_duration_seconds{quantile="0.95"})
```

---

## 5. Đặt tên metric và label

Một tên metric tốt tự nói được “đo cái gì, đơn vị gì, type gì”:

```text
<namespace>_<subsystem>_<name>_<unit>[_total]

shop_checkout_duration_seconds
shop_orders_created_total
shop_queue_depth
process_cpu_seconds_total
```

Quy ước nên dùng:

- thời gian dùng `seconds`, không trộn milliseconds;
- dung lượng dùng `bytes`;
- ratio dùng giá trị `0..1`, chỉ nhân `100` khi hiển thị;
- counter có hậu tố `_total`;
- một metric chỉ diễn đạt một đại lượng và một đơn vị;
- ưu tiên tên ASCII theo pattern `[a-zA-Z_:][a-zA-Z0-9_:]*` để tương thích hệ sinh thái, dù Prometheus 3 hỗ trợ tên UTF-8 rộng hơn.

Không nhét dimension vào tên:

```text
# Khó aggregate, sinh tên động
orders_created_web_total
orders_created_mobile_total

# Tốt hơn
orders_created_total{channel="web"}
orders_created_total{channel="mobile"}
```

Nhưng label cũng không phải miễn phí. Trước khi thêm label, trả lời:

1. tập giá trị có bounded không?
2. có thực sự cần filter/aggregate theo chiều này không?
3. cardinality hôm nay và sau một năm là bao nhiêu?
4. có thể dùng log hoặc trace cho dữ liệu chi tiết không?

### Missing không phải zero

```text
0       → có series và giá trị thực sự bằng 0
missing → không có sample phù hợp tại thời điểm query
```

Ép mọi missing thành zero có thể che lỗi discovery/scrape. Chỉ dùng biểu thức như `... or vector(0)` khi business meaning thật sự cho phép “không có series = 0”.

---

## 6. Kiến trúc các component

```text
                         ┌────────────────────┐
                         │ Service discovery  │
                         └─────────┬──────────┘
                                   ▼
App / Exporter ──/metrics──▶ Prometheus server
                              ├── Retrieval/scrape
                              ├── Local TSDB
                              ├── PromQL engine/API
                              └── Rule evaluation
                                      │ firing alerts
                                      ▼
                                 Alertmanager
                                      │
                         email / chat / paging system

Grafana ──PromQL/API──▶ Prometheus
Prometheus ──remote_write──▶ remote storage (tùy chọn)
```

| Component | Trách nhiệm | Không nên hiểu nhầm |
|---|---|---|
| Prometheus server | Discover, scrape, store, query, evaluate rules | Không tự là clustered durable database. |
| Exporter | Chuyển số liệu hệ thống khác thành Prometheus metrics | Không phải nơi giữ toàn bộ monitoring history. |
| Client library | Instrument code và expose metrics | Không nên tạo label value vô hạn. |
| Alertmanager | Group, deduplicate, route, inhibit, silence, notify | Không chạy PromQL và không quyết định condition alert. |
| Pushgateway | Cache metric được push cho use case batch giới hạn | Không phải event bus hoặc push replacement chung. |
| Grafana | Query, visualize, dashboard và có alerting riêng | Không bắt buộc để Prometheus scrape/lưu metric. |

### Exporter hay instrument trực tiếp?

```text
Có quyền sửa application
  → dùng client library/Micrometer để tạo business + application metrics

Không sửa được hệ thống nguồn
  → dùng exporter, ví dụ Node Exporter hoặc Blackbox Exporter

Cần probe từ góc nhìn bên ngoài
  → dùng multi-target exporter như Blackbox Exporter
```

---

## 7. Cấu hình tối thiểu nhưng đúng

`prometheus.yml`:

```yaml
global:
  scrape_interval: 15s
  scrape_timeout: 10s
  evaluation_interval: 15s

  # Chỉ được thêm khi giao tiếp với hệ thống ngoài như federation,
  # remote write hoặc alert. Không phải label ghi vào mọi local series.
  external_labels:
    cluster: local-lab
    replica: prometheus-1

rule_files:
  - rules/*.yml

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: shop-api
    metrics_path: /actuator/prometheus
    static_configs:
      - targets:
          - "shop-api-1:8080"
          - "shop-api-2:8080"
```

Prometheus tự thêm `job="shop-api"` và mặc định dùng target address làm `instance`.

### Chọn interval

Interval ngắn hơn:

- thấy biến động sớm hơn;
- có nhiều sample hơn cho query;
- tăng traffic, ingest, CPU và disk.

Interval dài hơn:

- giảm chi phí;
- có thể bỏ lỡ spike ngắn;
- alert và rate kém nhạy hơn.

Không có một giá trị đúng cho mọi job. Chọn theo SLO, tốc độ thay đổi và cost budget; không giảm interval toàn hệ thống chỉ để sửa một dashboard.

### Validate và reload

```bash
promtool check config prometheus.yml
promtool check rules rules/*.yml
```

Reload bằng `SIGHUP`, hoặc bật rõ `--web.enable-lifecycle` rồi gọi:

```bash
curl -X POST http://localhost:9090/-/reload
```

Không bật `--web.enable-admin-api` chỉ để reload. Admin API có các operation thay đổi/xóa dữ liệu và cần được bảo vệ nghiêm ngặt.

---

## 8. PromQL cơ bản theo câu hỏi vận hành

### 8.1 Instant vector và range vector

```promql
# Instant vector: series gần thời điểm đánh giá
up{job="shop-api"}

# Range vector: các sample trong 5 phút
http_requests_total{job="shop-api"}[5m]
```

Range vector thường là đầu vào cho function như `rate()` hoặc `max_over_time()`, không phải kết quả cuối để cộng trực tiếp.

### 8.2 Label matcher

```promql
http_requests_total{method="GET"}          # bằng
http_requests_total{status!="200"}         # khác
http_requests_total{status=~"2..|3.."}     # regex match
http_requests_total{status!~"4..|5.."}     # regex not match
```

Regex matcher được anchor toàn bộ. `route=~"/api"` không tự mang nghĩa “contains `/api`”; nếu thật sự cần, dùng pattern phù hợp như `".*/api.*"`.

### 8.3 Throughput

```promql
sum by (service) (
  rate(http_requests_total[5m])
)
```

`rate()` trả tốc độ trung bình mỗi giây. `increase(metric[1h])` trả tổng tăng ước lượng trong một giờ và phù hợp để trình bày số lượng theo cửa sổ.

### 8.4 Error ratio

```promql
sum by (service) (
  rate(http_requests_total{status=~"5.."}[5m])
)
/
sum by (service) (
  rate(http_requests_total[5m])
)
```

Kiểm tra label matching ở tử và mẫu. Một bên còn `instance`, bên kia đã aggregate mất `instance` có thể làm kết quả rỗng hoặc ghép sai.

### 8.5 Saturation

```promql
max by (queue) (shop_queue_depth)

1 -
node_filesystem_avail_bytes{mountpoint="/"}
/
node_filesystem_size_bytes{mountpoint="/"}
```

### 8.6 Target down và target biến mất

```promql
# Target tồn tại nhưng scrape fail
up{job="shop-api"} == 0

# Không còn bất kỳ series up nào của job
absent(up{job="shop-api"})
```

### 8.7 Aggregate nhưng giữ chiều cần debug

```promql
# Giữ service, route; loại instance và các label khác
sum by (service, route) (
  rate(http_requests_total[5m])
)

# Bỏ riêng instance, giữ các label còn lại
sum without (instance) (
  rate(http_requests_total[5m])
)
```

`by` và `without` không chỉ khác cú pháp; chúng quyết định contract label của kết quả, ảnh hưởng join, dashboard và alert routing.

### 8.8 `rate()` rồi mới `sum()`

```promql
# Nên dùng: phát hiện reset trên từng input series trước
sum by (service) (
  rate(http_requests_total[5m])
)

# Tránh: aggregate có thể che counter reset của từng instance
rate(
  sum by (service) (http_requests_total)[5m:]
)
```

---

## 9. Local TSDB: hiểu đủ để vận hành

Luồng ghi đơn giản hóa:

```text
sample mới
  → Head (dữ liệu gần hiện tại)
  → WAL bảo vệ dữ liệu chưa thành block bền vững
  → block khoảng 2 giờ
  → background compaction thành block lớn hơn
  → retention xóa block cũ
```

Các thư mục quan trọng:

```text
data/
├── wal/                 # write-ahead log
├── chunks_head/         # memory-mapped chunks của Head
└── <ULID block>/
    ├── chunks/
    ├── index
    ├── meta.json
    └── tombstones
```

Điểm cần nhớ:

- WAL không phải “buffer 2 giờ chỉ nằm trong memory”;
- local storage không cluster và không replicate;
- dùng local filesystem tương thích POSIX; tài liệu Prometheus không hỗ trợ NFS cho local TSDB;
- retention mặc định là `15d` nếu không đặt time/size retention;
- nếu đặt cả time và size, điều kiện chạm trước sẽ loại dữ liệu cũ;
- snapshot/backup và HA là bài toán riêng, không được suy ra từ việc có WAL.

Ước lượng disk sơ bộ:

```text
disk ≈ retention_seconds × samples_per_second × bytes_per_sample
```

Tài liệu Prometheus dùng khoảng 1–2 bytes/sample làm ước lượng ban đầu, nhưng production còn cần headroom cho WAL, Head chunks, index, compaction, growth và filesystem.

Ví dụ cấu hình:

```text
--storage.tsdb.path=/prometheus
--storage.tsdb.retention.time=30d
--storage.tsdb.retention.size=80GB
```

Không đặt size retention bằng 100% volume. Khi disk đầy, Prometheus có thể hỏng trước khi cơ chế cleanup kịp cứu.

---

## 10. Instrument Spring Boot bằng Micrometer

Dependencies:

```groovy
implementation("org.springframework.boot:spring-boot-starter-actuator")
runtimeOnly("io.micrometer:micrometer-registry-prometheus")
```

`application.yml`:

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${APP_ENV:local}
    distribution:
      percentiles-histogram:
        http.server.requests: true
      slo:
        http.server.requests: 50ms,100ms,250ms,500ms,1s
```

Custom counter:

```java
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.stereotype.Service;

@Service
public class OrderMetrics {
    private final MeterRegistry registry;

    public OrderMetrics(MeterRegistry registry) {
        this.registry = registry;
    }

    public void recordCreated(String channel) {
        Counter.builder("shop.orders.created")
            .description("Total number of created orders")
            .tag("channel", normalizeChannel(channel))
            .register(registry)
            .increment();
    }

    private String normalizeChannel(String channel) {
        return switch (channel) {
            case "web", "mobile", "partner" -> channel;
            default -> "other";
        };
    }
}
```

Tại Prometheus registry, tên trên thường được chuẩn hóa thành:

```text
shop_orders_created_total{channel="web", ...}
```

Tại sao phải normalize?

- `channel` có tập giá trị bounded;
- input lạ được gom thành `other`;
- không để dữ liệu người dùng tùy ý tạo series mới.

Tránh code này:

```java
// Mỗi customer tạo một label value mới: cardinality tăng theo dữ liệu nghiệp vụ.
registry.counter("shop.orders.created", "customer_id", customerId).increment();
```

`/actuator/prometheus` có thể lộ topology, version, hostname hoặc business label. Chỉ expose trong mạng monitoring, áp dụng authentication/TLS/network policy phù hợp và không đưa secret/PII vào label.

---

## 11. Lab chạy bằng Docker Compose

`compose.yml`:

```yaml
services:
  prometheus:
    image: prom/prometheus:v3.13.0
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=7d
      - --web.enable-lifecycle
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus_data:/prometheus
    ports:
      - "127.0.0.1:9090:9090"
    restart: unless-stopped

volumes:
  prometheus_data:
```

`prometheus.yml` cho lab:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]
```

Khởi động:

```bash
docker compose up -d
docker compose ps
```

Kiểm tra lần lượt:

```text
http://localhost:9090/-/ready
http://localhost:9090/targets
http://localhost:9090/query?g0.expr=up
```

API:

```bash
curl -fsS "http://localhost:9090/api/v1/query?query=up"
curl -fsS "http://localhost:9090/api/v1/targets"
curl -fsS "http://localhost:9090/api/v1/status/tsdb"
```

Không pin `latest` trong môi trường cần tái lập. Khi nâng version, đọc release notes, validate config/rules và thử rollback trên dữ liệu/snapshot phù hợp.

---

## 12. Pushgateway, remote write và federation

Ba cơ chế này giải quyết ba bài toán khác nhau:

| Cơ chế | Dùng để làm gì | Không phải |
|---|---|---|
| Pushgateway | Nhận metric của service-level batch job không thể scrape | Push ingestion chung cho mọi app |
| Remote write | Gửi sample đã ingest sang remote endpoint | Cách target application push trực tiếp tùy ý |
| Federation | Prometheus cấp trên scrape một tập series từ Prometheus cấp dưới | HA replication của local TSDB |

Pushgateway có các rủi ro:

- trở thành bottleneck/single point;
- mất health signal tự nhiên qua `up` của từng instance;
- series không tự biến mất theo lifecycle của process đã push;
- phải quản lý xóa stale series.

Job gắn với một máy cụ thể thường hợp với Node Exporter textfile collector hơn. Event ngắn nhưng có ý nghĩa nghiệp vụ chi tiết thường nên vào log/event system, không ép thành Pushgateway metric.

---

## 13. Troubleshooting theo tầng

Khi dashboard trống, không đoán ngay “Grafana lỗi”. Đi theo luồng:

```text
1. Application có expose metric?
2. Prometheus có discover target?
3. Target scrape có health=up?
4. Sample có bị relabel/drop?
5. TSDB có series?
6. PromQL có chọn đúng name/label/time?
7. Grafana datasource/time range/variable có đúng?
```

### Bước 1 – kiểm tra endpoint nguồn

```bash
curl -fsS http://shop-api:8080/actuator/prometheus
```

Kiểm tra HTTP status, timeout, TLS/auth và metric name thực tế.

### Bước 2 – kiểm tra target

Mở `/targets` hoặc:

```bash
curl -fsS http://localhost:9090/api/v1/targets
```

Đọc `health`, `lastError`, `lastScrape`, discovered labels và final labels.

### Bước 3 – query từ đơn giản đến phức tạp

```promql
up
up{job="shop-api"}
shop_orders_created_total
rate(shop_orders_created_total[5m])
sum by (channel) (rate(shop_orders_created_total[5m]))
```

Nếu selector đầu đã rỗng, đừng sửa aggregation cuối.

### Bước 4 – kiểm tra config/rules

```bash
promtool check config prometheus.yml
promtool check rules rules/*.yml
```

### Bảng triệu chứng

| Triệu chứng | Nguyên nhân thường gặp | Kiểm tra đầu tiên |
|---|---|---|
| `up == 0` | DNS, timeout, TLS/auth, endpoint lỗi, parse lỗi | `/targets` → `lastError` |
| Không có `up` | discovery/relabel/config không tạo target | Service discovery và discovered labels |
| Metric có ở `/metrics` nhưng không query được | metric relabel drop, parse/sample limit, name khác | target error và scrape config |
| `rate()` có spike sau deploy | query sai type hoặc counter identity đổi | metric type, label set và reset |
| Dashboard chậm | selector rộng, cardinality cao, range/step quá lớn | query stats và series fan-out |
| Prometheus OOM | active series/churn/query quá lớn | `/api/v1/status/tsdb`, process metrics |
| Disk đầy | retention/growth/headroom sai | ingest rate, block/WAL và filesystem |

---

## 14. Những hiểu lầm phổ biến

### “Prometheus HA chỉ cần hai replica dùng chung disk”

Sai. Local TSDB không được thiết kế để hai server cùng ghi vào một data directory. Hai replica thường scrape độc lập và cần lớp query/dedup/remote storage phù hợp nếu muốn một góc nhìn thống nhất.

### “Có replica nên không cần backup”

Sai. Replica có thể cùng ingest dữ liệu sai, cùng chịu config lỗi hoặc cùng mất lịch sử theo retention. HA, long-term retention và backup/recovery là ba yêu cầu khác nhau.

### “Counter hiện tại là số request trong hôm nay”

Sai. Counter là tổng từ lần reset gần nhất, không tự reset theo ngày. Dùng `increase(...[1d])` với semantics thời gian phù hợp hoặc tính báo cáo từ hệ thống nghiệp vụ.

### “p99 của từng pod rồi average là p99 toàn service”

Sai. Quantile không aggregate bằng average. Dùng histogram có bucket tương thích hoặc native histogram rồi aggregate distribution trước khi tính quantile.

### “Thêm label giúp query linh hoạt nên càng nhiều càng tốt”

Sai. Mỗi tổ hợp label là một series. Chỉ thêm dimension bounded và thật sự cần cho dashboard, alert hoặc điều tra.

### “`up == 1` nghĩa là ứng dụng khỏe”

Sai. Nó chỉ chứng minh Prometheus vừa scrape endpoint thành công. Business flow vẫn có thể lỗi; cần metric về traffic, errors, latency và saturation.

---

## 15. Checklist production tối thiểu

### Metric design

- [ ] Metric name có đại lượng, base unit và suffix đúng.
- [ ] Counter/Gauge/Histogram/Summary được chọn theo semantics.
- [ ] Mọi label đều có cardinality budget.
- [ ] Không có PII, secret, request ID hoặc raw error message trong label.
- [ ] Histogram bucket/SLO boundary được kiểm thử với phân phối thật.

### Scrape

- [ ] Target discovery và relabeling được kiểm thử.
- [ ] `scrape_timeout < scrape_interval`.
- [ ] Sample/label limits được cân nhắc cho target không tin cậy.
- [ ] Metrics endpoint chỉ mở cho monitoring path cần thiết.
- [ ] Có alert cho scrape failure và target disappearance quan trọng.

### Storage

- [ ] Dùng persistent local filesystem được hỗ trợ.
- [ ] Retention time/size và disk headroom rõ ràng.
- [ ] Theo dõi active series, churn, ingest rate, WAL/compaction và disk.
- [ ] RPO/RTO, snapshot/backup hoặc remote storage được định nghĩa.
- [ ] Không coi local TSDB đơn lẻ là durable distributed storage.

### Query và alert

- [ ] `rate()` áp dụng trước aggregation cho counter.
- [ ] Alert có `for`/routing/ownership/runbook phù hợp.
- [ ] Recording rule dùng cho query lặp lại, đắt và có contract tên rõ.
- [ ] Dashboard không che missing thành zero tùy tiện.
- [ ] Rule/config được kiểm bằng `promtool` trong CI.

---

## 16. Câu hỏi tự kiểm tra

1. Vì sao `method × route × status × instance` tạo nhiều series hơn tổng số label value?
2. `up == 0` khác `absent(up)` ở đâu?
3. Vì sao phải `rate()` trước rồi mới `sum()`?
4. Khi nào Gauge đúng hơn Counter?
5. Vì sao không average p95 của nhiều instance?
6. Classic histogram và native histogram khác nhau ở cách lưu/query thế nào?
7. WAL bảo vệ điều gì và không thay thế điều gì?
8. Tại sao `user_id` phù hợp với log hơn label?
9. Pushgateway hợp với use case nào?
10. Nếu dashboard trống, bạn kiểm tra tầng nào trước?

Nếu chưa trả lời được bằng một ví dụ cụ thể, hãy chạy lab ở mục 11 rồi tự tạo một scrape failure.

---

## 17. Tài liệu chính thức

- [Prometheus overview](https://prometheus.io/docs/introduction/overview/)
- [Data model](https://prometheus.io/docs/concepts/data_model/)
- [Metric types](https://prometheus.io/docs/concepts/metric_types/)
- [Querying basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [Metric and label naming](https://prometheus.io/docs/practices/naming/)
- [Native histograms](https://prometheus.io/docs/specs/native_histograms/)
- [Storage](https://prometheus.io/docs/prometheus/latest/storage/)
- [When to use the Pushgateway](https://prometheus.io/docs/practices/pushing/)
- [Prometheus 3.x changelog](https://github.com/prometheus/prometheus/blob/main/CHANGELOG.md)

---

## Chủ đề tiếp theo

[PromQL nâng cao, Recording Rules và Alerting Rules](prometheus_advanced.md)

---

*Cập nhật lần cuối: 2026-07-29*
