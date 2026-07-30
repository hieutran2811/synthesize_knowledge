# Metrics Design – RED, USE, Golden Signals và metric contract

> Baseline mục tiêu: **Prometheus 3.13.x**.
>
> Điều kiện đầu vào: đã hiểu Prometheus data model, metric types và PromQL cơ
> bản. Xem [Prometheus Fundamentals](../prometheus/prometheus_fundamentals.md).
>
> Bài này tập trung vào việc **thiết kế dữ liệu metric**. SLO burn-rate,
> notification và on-call policy sẽ nằm trong
> [Alerting Strategy](alerting_strategy.md).
>
> Các PromQL dùng label `service` giả định label này được service discovery hoặc
> relabeling thêm vào target. Nếu hệ thống chỉ có `job`, hãy thay bằng contract
> label thực tế; không tự thêm một application label trùng lặp.

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- chọn signal bằng Golden Signals, RED và USE;
- chọn đúng Counter, Gauge, Histogram hoặc Summary;
- đặt tên metric, unit và label nhất quán;
- ước lượng cardinality trước khi instrument;
- thiết kế histogram dựa trên SLO và range thực tế;
- phân biệt classic histogram, native histogram và summary;
- thiết kế metrics cho HTTP, messaging, batch job, cache và resource pool;
- viết metric contract có owner, semantics và lifecycle;
- review instrumentation như review một public API.

Thiết kế metric tốt không phải là thu thập thật nhiều. Nó là thu thập tập dữ
liệu nhỏ nhất vẫn trả lời được câu hỏi vận hành quan trọng.

---

## 2. Metric là một public API

Một metric được dùng bởi nhiều consumer:

```text
Application instrumentation
        │
        ├──▶ Prometheus storage
        ├──▶ Recording rules
        ├──▶ Dashboards
        ├──▶ Alert rules
        ├──▶ Capacity reports
        └──▶ SLO calculations
```

Đổi tên metric, label hoặc ý nghĩa của status có thể làm mọi consumer sai cùng
lúc. Vì vậy metric cần:

- schema;
- semantics;
- unit;
- type;
- label vocabulary;
- owner;
- version/migration plan;
- tests.

Ví dụ contract tối thiểu:

| Field | Giá trị |
|---|---|
| Name | `checkout_http_server_requests_total` |
| Type | Counter |
| Meaning | số request đã hoàn tất |
| Unit | requests |
| Count point | khi response hoàn tất |
| Labels | `method`, `route`, `status_code` |
| Excluded | health check nội bộ |
| Owner | Checkout team |
| Consumers | RED dashboard, availability SLI |

Nếu hai đội hiểu “request total” khác nhau, PromQL đúng cú pháp vẫn có thể trả
về kết quả sai về nghiệp vụ.

---

## 3. Bắt đầu từ câu hỏi, không bắt đầu từ exporter

Trước khi thêm metric, viết câu hỏi cần trả lời:

```text
User có checkout thành công không?
Nếu không, failure ở bước nào?
Latency có vượt cam kết không?
Hệ thống đang gần hết capacity nào?
Batch settlement gần nhất thành công khi nào?
```

Sau đó xác định:

1. user journey;
2. service boundary;
3. valid event;
4. good/bad event;
5. resource có thể saturation;
6. dimensions cần để route ownership;
7. retention và query consumers.

Anti-pattern:

```text
Library expose được 400 metrics
  → scrape cả 400
  → tạo dashboard 80 panels
  → khi incident vẫn không biết checkout có thành công không
```

Metric collection không thay thế model về hệ thống.

---

## 4. Bốn Golden Signals

Google SRE đề xuất bốn signal cho user-facing system:

| Signal | Câu hỏi |
|---|---|
| Latency | Request mất bao lâu? |
| Traffic | Hệ thống đang nhận bao nhiêu work? |
| Errors | Bao nhiêu work thất bại? |
| Saturation | Resource nào sắp không nhận thêm work? |

### Latency

Theo dõi distribution, không chỉ average:

```promql
histogram_quantile(
  0.95,
  sum by (service, le) (
    rate(checkout_http_server_request_duration_seconds_bucket[5m])
  )
)
```

Tách latency của success và error nếu semantics yêu cầu:

```promql
histogram_quantile(
  0.95,
  sum by (service, le) (
    rate(
      checkout_http_server_request_duration_seconds_bucket{
        outcome="success"
      }[5m]
    )
  )
)
```

Error thường trả về nhanh có thể kéo average latency xuống, khiến dashboard có
vẻ “nhanh hơn” đúng lúc service đang hỏng.

### Traffic

```promql
sum by (service) (
  rate(checkout_http_server_requests_total[5m])
)
```

Traffic không chỉ là HTTP request:

- messages/s;
- transactions/s;
- bytes/s;
- jobs/minute;
- concurrent sessions;
- records processed/s.

### Errors

Đếm cả numerator và denominator:

```promql
sum by (service) (
  rate(checkout_http_server_requests_total{outcome="error"}[5m])
)
/
sum by (service) (
  rate(checkout_http_server_requests_total[5m])
)
```

Không ép mẫu số lên `1`: cách đó làm sai ratio khi traffic dưới `1 request/s`.
Nếu mẫu số bằng zero, hãy xử lý no-traffic như một signal riêng theo contract
thay vì diễn giải nó thành tỷ lệ `0`.

“Error” phải theo contract. Không mặc định mọi `4xx` là lỗi service hoặc chỉ
`5xx` mới là lỗi:

- `401` có thể là request không hợp lệ bình thường;
- `429` có thể là service không đáp ứng capacity đã hứa;
- HTTP `200` với payload sai vẫn là lỗi người dùng;
- client timeout trước khi nhận response không xuất hiện như server `5xx`.

### Saturation

Saturation đo work đang chờ hoặc headroom còn lại:

- queue depth/age;
- thread-pool queue;
- connection pool pending;
- CPU run queue;
- memory pressure/swap;
- disk queue;
- quota remaining.

CPU 80% là utilization, chưa tự động là saturation. CPU 80% ổn định nhưng queue
tăng liên tục mới cho thấy demand vượt khả năng phục vụ.

---

## 5. RED cho service

RED là checklist cho request-driven service:

```text
R – Rate:     số request/work mỗi giây
E – Errors:   số/tỷ lệ work thất bại
D – Duration: distribution thời gian xử lý
```

Contract mẫu:

```text
checkout_http_server_requests_total
  labels: method, route, status_code, outcome

checkout_http_server_request_duration_seconds
  labels: method, route, outcome
```

PromQL:

```promql
# Rate
sum by (service, route) (
  rate(checkout_http_server_requests_total[5m])
)
```

```promql
# Error ratio
sum by (service) (
  rate(checkout_http_server_requests_total{outcome="error"}[5m])
)
/
sum by (service) (
  rate(checkout_http_server_requests_total[5m])
)
```

```promql
# Classic histogram p99
histogram_quantile(
  0.99,
  sum by (service, le) (
    rate(checkout_http_server_request_duration_seconds_bucket[5m])
  )
)
```

RED giúp biết service có biểu hiện xấu hay không. Nó không tự trả lời resource
nào là root cause.

---

## 6. USE cho resource

Brendan Gregg mô tả USE:

```text
Với mỗi resource, kiểm tra:
U – Utilization: mức resource đang bận
S – Saturation: work vượt khả năng đang chờ
E – Errors: sự kiện lỗi của resource
```

Resource có thể là:

- CPU;
- memory;
- disk;
- network interface;
- thread pool;
- database connection pool;
- queue/worker pool;
- quota của external API.

### CPU

```promql
# Utilization ratio
1 -
avg by (job, instance) (
  rate(node_cpu_seconds_total{mode="idle"}[5m])
)
```

```promql
# Load per logical CPU: chỉ là proxy, không phải run queue chính xác
node_load1
/
count by (job, instance) (
  node_cpu_seconds_total{mode="idle"}
)
```

CPU errors thường không có một metric phổ quát; có thể cần hardware/VM/kernel
telemetry. `steal` là thời gian hypervisor lấy CPU, không phải “error counter”.

### Memory

```promql
# Utilization ratio
1 -
(
  node_memory_MemAvailable_bytes
  /
  node_memory_MemTotal_bytes
)
```

```promql
# Memory pressure proxy
rate(node_vmstat_pgmajfault[5m])
```

```promql
# OOM kill
increase(node_vmstat_oom_kill[15m])
```

Memory “used” cao có thể do page cache và vẫn khỏe. `MemAvailable`, major page
fault, reclaim, swap và OOM thường có ý nghĩa hơn một phần trăm used đơn lẻ.

### Disk

```promql
# Utilization/busy ratio gần đúng cho từng block device
rate(node_disk_io_time_seconds_total{device!~"loop.*|ram.*"}[5m])
```

```promql
# Weighted I/O time rate: proxy cho average queue depth
rate(
  node_disk_io_time_weighted_seconds_total{
    device!~"loop.*|ram.*"
  }[5m]
)
```

Disk error có thể phải lấy từ device/controller exporter hoặc kernel logs; đừng
bịa một tên metric “disk_errors_total” nếu exporter không cung cấp.

### Network

```promql
# Transmit utilization nếu exporter có interface speed chính xác
rate(node_network_transmit_bytes_total{device!="lo"}[5m])
/
node_network_speed_bytes{device!="lo"}
```

```promql
# Interface errors
rate(node_network_receive_errs_total{device!="lo"}[5m])
+
rate(node_network_transmit_errs_total{device!="lo"}[5m])
```

Speed metric có thể thiếu hoặc sai với virtual interface. Contract phải ghi rõ
nguồn và limitation.

---

## 7. Golden Signals, RED và USE bổ sung cho nhau

| Method | Boundary | Mục đích chính |
|---|---|---|
| Golden Signals | user-facing system | overview về symptom và capacity |
| RED | service/request | health của workload |
| USE | resource | tìm bottleneck/cause |

Một incident điển hình:

```text
Golden Signals:
  checkout latency/error tăng
        │
        ▼
RED:
  route /checkout/{cartId} bị ảnh hưởng
        │
        ▼
USE:
  DB connection pool saturated, pending queue tăng
```

Không cần ba bộ metric trùng nhau. Một metric có thể phục vụ nhiều method.

---

## 8. Xác định service boundary và ownership

Instrument cả hai phía của dependency:

```text
Client service                      Server service
--------------                      --------------
request attempts                    accepted requests
client-observed errors              server response status
end-to-end latency                  handler latency
retry/timeout                       internal processing
```

Hai phía có thể khác:

- client timeout nhưng server vẫn hoàn tất;
- load balancer drop trước server;
- retry làm client attempts lớn hơn server business operations;
- response server thành công nhưng client không nhận được.

Metric names cần thể hiện perspective:

```text
checkout_payment_client_requests_total
payments_http_server_requests_total
```

Không dùng một metric mơ hồ `requests_total` cho cả inbound và outbound.

---

## 9. Chọn metric type

| Type | Giá trị | Ví dụ |
|---|---|---|
| Counter | chỉ tăng, reset khi process restart | requests, failures, bytes |
| Gauge | tăng/giảm tùy ý | queue depth, in-flight, temperature |
| Classic Histogram | counters theo fixed buckets | latency, size |
| Native Histogram | histogram sample có dynamic buckets | latency, size |
| Summary | count/sum và client-side quantiles | use case khó aggregate |

Quy tắc nhanh:

```text
Đếm event tích lũy?          → Counter
Đo trạng thái tại thời điểm? → Gauge
Đo distribution?            → Histogram
Chỉ cần quantile local và không aggregate? → cân nhắc Summary
```

---

## 10. Counter: lưu raw event, derive rate/ratio

Counter:

- không giảm;
- có thể reset về 0 khi restart;
- thường có hậu tố `_total`;
- được query bằng `rate()` hoặc `increase()`.

```text
checkout_orders_total{outcome="success"}
checkout_orders_total{outcome="rejected"}
checkout_orders_total{outcome="error"}
```

Từ raw counters:

```promql
sum(rate(checkout_orders_total{outcome="success"}[5m]))
/
sum(rate(checkout_orders_total[5m]))
```

Ưu tiên export numerator và denominator thay vì export sẵn
`checkout_success_percentage`:

- có thể đổi time window;
- aggregate qua instance;
- kiểm tra volume thấp;
- tính nhiều ratio;
- `rate()` xử lý counter reset.

Không lấy `rate()` của Gauge.

---

## 11. Gauge: trạng thái hiện tại

Gauge phù hợp:

```text
checkout_inflight_requests
checkout_worker_queue_depth
checkout_db_pool_connections{state="active|idle|max"}
checkout_last_success_timestamp_seconds
```

### Export timestamp, không export “age”

Tốt:

```text
checkout_last_success_timestamp_seconds 1.7853012e+09
```

```promql
time() - checkout_last_success_timestamp_seconds
```

Không tốt:

```text
checkout_seconds_since_last_success
```

Nếu updater bị kẹt, “age” có thể đứng yên và nói dối. Timestamp cho phép
Prometheus tự tính age theo thời gian query.

### Gauge duration là ngoại lệ có chủ đích

Duration của **lần batch/collection gần nhất** có thể là Gauge:

```text
checkout_reconciliation_last_duration_seconds
```

Nó mô tả một lần chạy cụ thể, không phải distribution của mọi request.

---

## 12. Classic Histogram

Classic histogram:

```text
checkout_http_server_request_duration_seconds_bucket{le="0.1"}
checkout_http_server_request_duration_seconds_bucket{le="0.3"}
checkout_http_server_request_duration_seconds_bucket{le="1"}
checkout_http_server_request_duration_seconds_bucket{le="+Inf"}
checkout_http_server_request_duration_seconds_sum
checkout_http_server_request_duration_seconds_count
```

Bucket là cumulative counter. Bucket `le="1"` đã bao gồm observation trong
`le="0.3"`.

### Average

```promql
sum(
  rate(checkout_http_server_request_duration_seconds_sum[5m])
)
/
sum(
  rate(checkout_http_server_request_duration_seconds_count[5m])
)
```

### Quantile

```promql
histogram_quantile(
  0.95,
  sum by (service, le) (
    rate(checkout_http_server_request_duration_seconds_bucket[5m])
  )
)
```

Phải giữ label `le` khi aggregate classic buckets.

### Ưu và nhược

- aggregate được qua instance;
- đổi quantile/time window lúc query;
- bucket boundaries phải được thiết kế trước;
- mỗi bucket tạo thêm series;
- khác bucket layout khó aggregate đúng.

---

## 13. Native Histogram trong Prometheus 3.13

Native histogram là first-class composite sample. So với classic histogram:

- sparse buckets;
- resolution cao hơn;
- không cần liệt kê fixed boundaries khi instrument;
- standard schemas có thể merge;
- một histogram sample nằm trong một time series;
- truyền atomically hơn qua protocol hỗ trợ.

Native histogram stable từ Prometheus 3.8, nhưng ở Prometheus 3.13 vẫn phải bật
scrape rõ ràng:

```yaml
scrape_configs:
  - job_name: checkout
    scrape_native_histograms: true
    static_configs:
      - targets: ["checkout:8080"]
```

Remote write cũng cần bật nếu muốn gửi native histogram:

```yaml
remote_write:
  - url: https://metrics.example.com/api/v1/write
    send_native_histograms: true
```

Phải xác nhận toàn bộ đường đi hỗ trợ:

```text
client library
  → exposition protocol
  → Prometheus scrape
  → recording rules
  → remote write/backend
  → Grafana/query tooling
```

### Native histogram PromQL

```promql
histogram_quantile(
  0.95,
  sum by (service) (
    rate(checkout_http_server_request_duration_seconds[5m])
  )
)
```

Không có `le` trong aggregation của standard native histogram.

```promql
# Tỷ lệ observation từ 0 đến 300ms
histogram_fraction(
  0,
  0.3,
  sum by (service) (
    rate(checkout_http_server_request_duration_seconds[5m])
  )
)
```

### Không phải “bật là miễn phí”

Dynamic buckets vẫn cần guardrail:

- distribution bị attacker điều khiển có thể mở rộng bucket range;
- client library cần bucket-count/reset strategy phù hợp;
- storage/backend/query tooling phải được capacity test;
- rollout song song classic + native có thể tăng chi phí tạm thời;
- dashboard/rule cần migration và comparison.

---

## 14. Summary

Summary tính quantile trong application:

```text
checkout_request_duration_seconds{quantile="0.5"}
checkout_request_duration_seconds{quantile="0.95"}
checkout_request_duration_seconds_sum
checkout_request_duration_seconds_count
```

Hạn chế chính:

- quantile/time window cố định tại client;
- không aggregate quantile của nhiều instance;
- client chịu chi phí tính quantile;
- không tính lại p99 nếu ban đầu chỉ cấu hình p95.

```text
avg(p95_instance_a, p95_instance_b) ≠ p95_toàn_service
```

Dùng Summary khi quantile local, fixed window và không cần aggregate thật sự
phù hợp. Với service nhiều replica, Histogram thường linh hoạt hơn.

---

## 15. Thiết kế classic histogram buckets

Bucket phải xuất phát từ:

1. SLO threshold;
2. distribution thực tế;
3. khoảng giá trị cần debug;
4. cardinality budget.

Nếu latency objective là 300 ms:

```text
0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.45, 0.75, 1, 2, 5
```

Phải có bucket đúng tại `0.3` nếu muốn tính chính xác tỷ lệ request ≤ 300 ms:

```promql
sum(
  rate(
    checkout_http_server_request_duration_seconds_bucket{
      outcome="success",
      le="0.3"
    }[5m]
  )
)
/
sum(
  rate(
    checkout_http_server_request_duration_seconds_count[5m]
  )
)
```

Trong contract trên, error không nằm ở numerator nhưng vẫn nằm trong
denominator, nên error được xem là bad event.

### Bucket quá thưa

```text
... 100ms, 1s ...
```

p95 ước lượng trong khoảng rất rộng và có thể gây hiểu nhầm.

### Bucket quá dày

```text
100 buckets × nhiều labels × nhiều instances
```

Cardinality và ingestion tăng mạnh mà không chắc cải thiện quyết định.

### Thay bucket là schema migration

Trong lúc rolling deployment, classic histograms cùng tên nhưng bucket layouts
khác nhau có thể aggregate sai/khó hiểu. Cách an toàn:

- dùng metric name/version mới;
- rollout và so sánh;
- migrate rules/dashboards;
- retire metric cũ sau retention window.

---

## 16. Naming convention cho Prometheus

Prometheus khuyến nghị:

```text
<namespace>_<subsystem>_<name>_<unit>_<type suffix>
```

Ví dụ:

```text
checkout_http_server_requests_total
checkout_http_server_request_duration_seconds
checkout_worker_queue_depth
checkout_payment_client_response_size_bytes
checkout_last_success_timestamp_seconds
checkout_disk_usage_ratio
```

Quy tắc:

- một application/domain prefix rõ ràng;
- một metric chỉ có một quantity và một unit;
- dùng base unit: seconds, bytes, meters;
- ratio ở dạng `0..1`, không phải `0..100`;
- Counter thường kết thúc `_total`;
- không nhét label name vào metric name;
- tổng hoặc average qua tất cả dimensions vẫn phải có ý nghĩa.

Không tốt:

```text
request_count              # thiếu boundary, type convention
latency_ms                 # thiếu subsystem, không dùng seconds
cpu_percent                # 80 hay 0.8?
http_200_requests_total     # status nên là label hữu hạn
payment_value_and_count     # trộn hai quantity
```

### Prometheus và OpenTelemetry naming

Prometheus khuyến nghị unit/type trong tên. OpenTelemetry semantic conventions
có naming/unit model khác và exporter có thể chuyển đổi dấu chấm, unit hoặc
suffix.

Không đoán tên series cuối cùng từ tên OTel instrument. Luôn kiểm tra output
thực tế tại Prometheus sau exporter/collector translation.

---

## 17. Label design

Label tốt có:

- vocabulary hữu hạn;
- semantics ổn định;
- cần thiết cho aggregation/routing/debug;
- không chứa dữ liệu nhạy cảm;
- không do input tùy ý tạo ra.

Ví dụ:

```text
method="GET"
route="/users/{id}"
status_code="200"
outcome="success"
region="ap-southeast-1"
```

Label nguy hiểm:

```text
user_id="u-928371"
request_id="01J..."
trace_id="ab12..."
email="user@example.com"
raw_path="/users/928371"
sql_query="select ..."
exception_message="connection to 10.0.0.7 failed"
```

Các giá trị unique/high-cardinality thuộc logs hoặc traces.

### Route template, không dùng raw path

Tốt:

```text
route="/users/{id}"
```

Không tốt:

```text
path="/users/928371"
```

Framework phải cung cấp matched route template. Nếu không xác định được route,
dùng một giá trị bounded như `route="unknown"` hoặc không gắn label, tùy
contract. Không lấy URI path thay thế.

### Tránh dimensions trùng nghĩa

Nếu `status_code` đã cho phép derive `status_class`, cân nhắc có thật sự cần cả
hai. Nếu `outcome` có business semantics khác HTTP status thì giữ, nhưng phải
document mapping.

---

## 18. Cardinality là phép nhân

Mỗi tổ hợp label values là một series:

```text
series upper bound
  ≈ targets
   × method values
   × route values
   × status values
   × các dimension khác
```

Classic histogram còn nhân với:

```text
bucket count + _sum + _count
```

Ví dụ:

```text
20 instances
× 5 methods
× 50 routes
× 3 outcomes
× (12 buckets + sum + count)
= 210.000 series
```

Đây là upper bound; không phải mọi combination đều xuất hiện. Nhưng nó cho thấy
một histogram tưởng nhỏ có thể rất đắt.

Thêm `user_id` một triệu giá trị làm mô hình mất kiểm soát.

### Cardinality budget

Mỗi metric contract nên có:

| Dimension | Expected | Hard bound | Owner |
|---|---:|---:|---|
| `method` | 5 | 10 | API team |
| `route` | 40 | 100 | API team |
| `status_code` | 8 | 20 | API team |
| `region` | 3 | 6 | Platform |

Nếu dimension không có hard bound đáng tin cậy, không đưa nó vào metric label.

---

## 19. Cardinality và privacy là cùng một review

High-cardinality labels thường cũng là sensitive:

- customer ID;
- email;
- IP;
- session ID;
- order ID;
- message key;
- SQL text.

Metric storage thường có:

- retention dài;
- nhiều reader;
- remote write;
- backup;
- ít redaction hơn logs.

Không hash ID để “giảm cardinality”: hash vẫn gần như unique và còn làm dữ liệu
khó xóa/diễn giải.

---

## 20. Đừng để metric biến mất khi giá trị bằng 0

Series chỉ xuất hiện sau event đầu tiên gây khó phân biệt:

```text
0 errors
hay
instrumentation/scrape bị hỏng?
```

Khởi tạo trước các label values hữu hạn:

```text
checkout_orders_total{outcome="success"} 0
checkout_orders_total{outcome="rejected"} 0
checkout_orders_total{outcome="error"} 0
```

Không pre-initialize dimension lớn/động như mọi route × status × tenant. Chỉ
khởi tạo vocabulary nhỏ đã biết.

Khi query, `or vector(0)` không phải cách chữa tổng quát vì có thể che mất
target bị down hoặc label context.

---

## 21. Count point và retry semantics

Phải định nghĩa đếm khi bắt đầu hay kết thúc.

Prometheus instrumentation guidance thường khuyên online request được đếm khi
kết thúc để count, error và duration thẳng hàng.

```text
Request bắt đầu
  → in-flight gauge +1
  → xử lý
  → request counter +1 khi kết thúc
  → duration observe
  → in-flight gauge -1
```

Retry cần metric riêng:

```text
checkout_payment_client_attempts_total
checkout_payment_operations_total
checkout_payment_retries_total{reason="timeout"}
```

Một business operation có thể tạo ba attempts. Không dùng attempts làm
denominator của business success SLI nếu contract cần operations.

---

## 22. Error taxonomy

Error label phải hữu hạn và actionable:

```text
outcome="success|rejected|error"
error_type="timeout|unavailable|invalid_response|rate_limited|other"
```

Không dùng exception class/message tùy ý nếu vocabulary không kiểm soát.

Contract phải trả lời:

- validation failure là rejected hay error?
- cancellation do client có tính là bad event?
- timeout xảy ra phía nào?
- partial success được tính thế nào?
- retry cuối cùng thành công có che failed attempts không?
- dependency failure map vào owner nào?

Giữ raw counters đủ để thay đổi SLI logic mà không phải deploy lại
instrumentation.

---

## 23. Messaging và stream processing

RED chuyển từ request sang message/work item:

```text
messaging_messages_total{
  operation="publish|process",
  outcome="success|error"
}

messaging_process_duration_seconds
messaging_inflight_messages
messaging_consumer_lag
messaging_oldest_unprocessed_message_age_seconds
```

### Những boundary cần phân biệt

```text
Producer accepted
  → broker persisted
  → consumer fetched
  → handler processed
  → side effect committed
  → offset acknowledged
```

“Consumed” có thể nghĩa khác nhau ở mỗi đội. Metric name/description phải nói
rõ boundary.

### Kafka labels

Thường có thể dùng:

- cluster;
- consumer group;
- topic;
- partition nếu budget cho phép.

Không dùng:

- message key;
- event ID;
- payload field;
- customer ID.

Partition count có bound nhưng vẫn có thể lớn. Đừng đưa partition vào mọi
dashboard/rule nếu chỉ cần tổng theo group/topic.

---

## 24. Offline pipeline

Với mỗi stage:

- items in/out;
- items in progress;
- failures;
- last processed timestamp;
- processing duration;
- queue depth/oldest age;
- heartbeat propagation timestamp.

```text
checkout_events_received_total
checkout_events_processed_total{outcome="success|error"}
checkout_events_inflight
checkout_last_processed_timestamp_seconds
checkout_oldest_pending_event_timestamp_seconds
```

Age:

```promql
time() - checkout_oldest_pending_event_timestamp_seconds
```

Queue depth bằng 0 có thể tốt hoặc pipeline không nhận input. Heartbeat
end-to-end giúp phân biệt.

---

## 25. Batch jobs và Pushgateway

Metric quan trọng nhất của batch job thường là lần thành công gần nhất:

```text
checkout_settlement_last_success_timestamp_seconds
checkout_settlement_last_completion_timestamp_seconds
checkout_settlement_last_duration_seconds
checkout_settlement_last_run_success
checkout_settlement_records_processed
```

`last_run_success` là Gauge `0|1`; không dùng một label `status` khiến series
cũ còn tồn tại song song.

Pushgateway chỉ phù hợp chủ yếu với **service-level short-lived batch jobs**
không thể scrape:

```text
Batch job → Pushgateway ← Prometheus scrape
```

Không dùng Pushgateway như push replacement cho toàn hệ thống vì:

- mất health semantics tự động của `up` cho nguồn;
- Pushgateway thành bottleneck/SPOF;
- stale series không tự biến mất;
- lifecycle/delete phải được quản lý.

Batch chạy vài phút có thể vừa expose endpoint để scrape trong lúc chạy, vừa
persist outcome phù hợp sau khi kết thúc.

---

## 26. Cache, thread pool và connection pool

### Cache

```text
checkout_cache_requests_total{result="hit|miss|error"}
checkout_cache_request_duration_seconds
checkout_cache_entries
checkout_cache_evictions_total{reason="size|ttl"}
```

Hit ratio được derive:

```promql
sum(rate(checkout_cache_requests_total{result="hit"}[5m]))
/
sum(
  rate(checkout_cache_requests_total{result=~"hit|miss"}[5m])
)
```

Không cho `key` vào label.

### Thread/worker pool

```text
checkout_worker_threads{state="active|idle|max"}
checkout_worker_queue_depth
checkout_worker_queue_wait_duration_seconds
checkout_worker_tasks_total{outcome="success|error"}
```

### Database connection pool

```text
checkout_db_pool_connections{state="active|idle|max"}
checkout_db_pool_pending_requests
checkout_db_pool_acquire_duration_seconds
checkout_db_pool_timeouts_total
```

Utilization:

```promql
sum without (state) (
  checkout_db_pool_connections{state="active"}
)
/
sum without (state) (
  checkout_db_pool_connections{state="max"}
)
```

Saturation thể hiện rõ hơn bằng pending requests/acquire latency/timeouts.

---

## 27. Business metrics

Business metrics nối reliability với impact:

```text
checkout_orders_total{outcome="success|rejected|error"}
checkout_payment_amount_usd_total
checkout_cart_conversions_total{outcome="converted|abandoned"}
```

Nguyên tắc:

- đếm event/amount bằng Counter;
- amount chỉ dùng cho operational trend, không thay financial ledger;
- không cộng trực tiếp nhiều currency; dùng metric riêng hoặc giá trị reporting
  currency đã chuẩn hóa có contract rõ;
- không label theo customer/order/product tùy ý;
- định nghĩa rõ event time và deduplication;
- không dùng metric system làm financial ledger;
- kiểm tra privacy/compliance.

Business drop có thể do traffic giảm hợp lệ, seasonality hoặc tracking lỗi.
Luôn xem numerator, denominator và technical signals.

---

## 28. Exemplars: nối metric với trace

Exemplar gắn một trace reference vào observation mà không biến `trace_id`
thành label của mọi series:

```text
Histogram bucket/sample
  └── exemplar → trace ID → Tempo/trace backend
```

Đây là cách phù hợp để đi từ:

```text
p99 tăng
  → chọn exemplar chậm
  → xem distributed trace cụ thể
```

Exemplar cần:

- tracing context;
- client/exposition/backend hỗ trợ;
- sampling phù hợp;
- không chứa sensitive attributes.

Không thêm `trace_id` làm metric label.

---

## 29. OpenTelemetry semantic conventions

Nếu instrument qua OpenTelemetry:

- ưu tiên semantic conventions của protocol/library;
- kiểm tra stability của convention;
- dùng Resource cho identity như `service.name`;
- giữ attributes bounded;
- kiểm tra tên/labels sau khi export sang Prometheus.

Với HTTP server, `http.route` phải là route template do framework xác định.
Raw URL path không được dùng thay thế.

Một migration semantic convention có thể đổi:

- instrument name;
- unit;
- attribute name;
- error semantics;
- histogram boundaries.

Pin instrumentation version và test exposition/queries trong CI hoặc staging.

---

## 30. Metric contract đầy đủ

Template:

```yaml
name: checkout_http_server_request_duration_seconds
owner: team-checkout
type: histogram
unit: seconds
description: >
  Wall-clock duration of completed inbound checkout HTTP requests.
count_point: response_completed
includes:
  - public checkout routes
excludes:
  - /health
labels:
  method:
    allowed: [GET, POST, PUT, DELETE]
  route:
    source: matched_route_template
    expected_cardinality: 20
    hard_limit: 50
  outcome:
    allowed: [success, rejected, error]
classic_buckets: [0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.45, 0.75, 1, 2, 5]
consumers:
  - dashboard: checkout-red
  - sli: checkout-latency
privacy: no_user_data
lifecycle:
  introduced: 2026-07-29
  deprecated: null
```

Contract có thể nằm trong docs/schema registry của organization. Điều quan
trọng là nó được review cùng code và consumer.

---

## 31. Instrumentation review checklist

Trước khi merge:

1. Metric trả lời câu hỏi nào?
2. Có metric chuẩn/framework tương đương chưa?
3. Type đúng không?
4. Count point ở đâu?
5. Unit/base unit đúng không?
6. Có thể derive ratio từ raw parts không?
7. Mỗi label có use case cụ thể không?
8. Cardinality expected/hard bound là bao nhiêu?
9. Input attacker/user có tạo label value mới không?
10. Có PII/secret không?
11. Histogram có bucket tại SLO threshold không?
12. Series zero có cần initialize không?
13. Retry/client/server semantics là gì?
14. Owner và consumer là ai?
15. Migration khi đổi schema thế nào?

“Có thể hữu ích sau này” không đủ để thêm một dimension không bounded.

---

## 32. Kiểm thử metric

### Unit test

Kiểm tra:

- success/error tăng đúng counter;
- duration luôn được observe ở mọi exit path;
- in-flight gauge giảm trong `finally/defer`;
- retry và operation không bị double count;
- status mapping đúng;
- label values nằm trong vocabulary.

### Exposition test

```text
# HELP checkout_http_server_requests_total ...
# TYPE checkout_http_server_requests_total counter
checkout_http_server_requests_total{
  method="POST",
  route="/checkout",
  outcome="success",
  status_code="200"
} 1
```

Kiểm tra:

- HELP/TYPE;
- suffix/unit;
- raw path/user ID không xuất hiện;
- expected zero series;
- classic buckets;
- duplicate registration.

`promtool check metrics` hữu ích với text/OpenMetrics exposition truyền thống,
nhưng tại baseline hiện tại không kiểm tra trực tiếp native histogram exposition
theo cùng cách. Native path cần integration test.

### Integration test

1. scrape application bằng Prometheus test;
2. tạo success/error/timeout;
3. restart application để tạo counter reset;
4. chạy PromQL của dashboard/SLI;
5. xác nhận aggregation qua hai instances;
6. kiểm tra remote-write/native histogram nếu dùng.

---

## 33. Cardinality governance

### Trước deploy

- contract review;
- static label allow-list;
- load test với route/status thực tế;
- ước lượng series;
- test unknown route/error fallback.

### Sau deploy

Có thể kiểm tra số series theo metric:

```promql
topk(
  20,
  count by (__name__) (
    {__name__!=""}
  )
)
```

Query toàn TSDB có thể đắt; dùng trong scope/time phù hợp hoặc TSDB status API
và tooling của backend.

Theo dõi:

- active series;
- series created/removed;
- samples ingested;
- scrape sample count;
- memory/storage growth;
- top metric/label cardinality;
- remote-write queue.

Prometheus scrape limits là guardrail cuối, không thay thế thiết kế:

- `sample_limit`;
- `label_limit`;
- `label_name_length_limit`;
- `label_value_length_limit`;
- `target_limit`.

Nếu scrape vượt limit, toàn scrape có thể fail. Alert vào guardrail breach.

---

## 34. Recording rules và dashboard contract

Raw metrics giữ dimensions cần thiết. Recording rules tạo view ổn định/rẻ hơn:

```yaml
groups:
  - name: checkout-red
    rules:
      - record: service:http_requests:rate5m
        expr: |
          sum by (service) (
            rate(checkout_http_server_requests_total[5m])
          )

      - record: service:http_errors:ratio_rate5m
        expr: |
          sum by (service) (
            rate(
              checkout_http_server_requests_total{
                outcome="error"
              }[5m]
            )
          )
          /
          sum by (service) (
            rate(checkout_http_server_requests_total[5m])
          )
```

Recording rule không sửa được raw semantics sai. Nếu counter double count hoặc
route label dùng raw path, precompute chỉ làm lỗi nhanh hơn.

Dashboard nên đi theo drill-down:

```text
Level 1 – User journey / Golden Signals
  → traffic, success, latency, saturation

Level 2 – Service / RED
  → route, dependency, version, region

Level 3 – Resource / USE
  → pools, CPU, memory, disk, network

Level 4 – Logs/traces
  → high-cardinality event detail
```

---

## 35. Thay đổi và deprecation

Không xóa/đổi metric trực tiếp:

```text
v1 metric
  → thêm v2 metric
  → dual emit
  → migrate dashboard/rule/SLO
  → observation window
  → xóa consumer v1
  → ngừng emit v1
  → chờ retention
```

Các thay đổi breaking:

- rename metric;
- đổi type;
- đổi unit;
- thêm/xóa/rename label;
- đổi label meaning;
- đổi count point;
- đổi error mapping;
- đổi classic bucket layout;
- đổi source từ server-observed sang client-observed.

Giữ changelog cho metric contract quan trọng.

---

## 36. Anti-patterns

### Metrics thay logs

`error_message` hoặc stack trace thành label gây cardinality và lộ dữ liệu.

### Raw URL làm route

`/users/123` tạo series theo mỗi user. Dùng `/users/{id}`.

### Một metric cho nhiều quantity

`system_stats{type="latency|bytes|count"}` trộn unit/type, aggregation mất nghĩa.

### Ratio Gauge không có raw parts

Không đổi window/aggregate/debug low traffic được.

### Average của percentiles

Không tạo global p95 bằng average p95 của instances.

### Counter cho queue depth

Queue có thể giảm, nên là Gauge.

### Gauge cho request total

Mất counter reset semantics và `rate()` không đáng tin.

### Status label chứa exception message

Vocabulary không bounded. Dùng `error_type` hữu hạn và đưa detail sang trace/log.

### Histogram dùng buckets mặc định không review

SLO 300 ms nhưng không có bucket 300 ms thì latency SLI phải nội suy.

### Mọi infrastructure threshold đều page

USE signals thường giúp tìm cause/capacity; page nên ưu tiên user impact và SLO.

### Push mọi application metric vào Pushgateway

Mất pull health semantics và tạo stale series.

### Hash user ID rồi dùng làm label

Cardinality vẫn cao và privacy vẫn phải review.

---

## 37. Bài lab

### Phần A – Metric contract

Chọn một checkout API và viết contract cho:

- request counter;
- duration histogram;
- in-flight gauge;
- dependency client counter;
- business order counter.

Ghi rõ count point, unit, labels, bounds và owner.

### Phần B – Cardinality

1. Liệt kê cardinality từng label.
2. Tính upper bound cho counter.
3. Tính lại cho classic histogram 12 buckets.
4. Thêm giả định 20 replicas.
5. Xác định dimension phải bỏ hoặc pre-aggregate.

### Phần C – PromQL

Viết:

- request rate;
- error ratio;
- p95;
- latency SLI ≤ 300 ms;
- DB pool utilization;
- queue oldest age.

### Phần D – Failure cases

Tạo:

- success;
- business rejection;
- server error;
- timeout;
- retry thành công;
- unknown route;
- process restart.

Xác nhận metric semantics sau mỗi case.

### Phần E – Native histogram

1. Xác nhận client library hỗ trợ.
2. Bật `scrape_native_histograms`.
3. So sánh p95 classic/native.
4. Kiểm tra remote-write backend.
5. Đo active series, sample volume và query behavior.
6. Ghi rollback plan.

### Acceptance criteria

- không có raw path, user/order/trace ID trong labels;
- error ratio có numerator/denominator cùng semantics;
- p95 aggregate đúng qua replicas;
- bucket có threshold SLO;
- restart không phá rate;
- zero series không bị hiểu nhầm;
- cardinality nằm trong budget;
- dashboard drill-down từ symptom tới resource.

---

## 38. Checklist metric design

### Purpose

- [ ] Có câu hỏi vận hành cụ thể.
- [ ] Có owner.
- [ ] Có consumers.
- [ ] Không trùng metric chuẩn sẵn có.

### Schema

- [ ] Tên có namespace/subsystem rõ.
- [ ] Type đúng.
- [ ] Base unit đúng.
- [ ] HELP mô tả semantics.
- [ ] Count point được ghi.
- [ ] Client/server perspective được ghi.

### Labels

- [ ] Mỗi label có use case.
- [ ] Vocabulary hữu hạn.
- [ ] Route là template.
- [ ] Không PII/secret/unique ID.
- [ ] Expected và hard cardinality bound.
- [ ] Fallback value bounded.

### Histogram

- [ ] Chọn classic/native/summary có lý do.
- [ ] Classic bucket có SLO threshold.
- [ ] Bucket layout nhất quán qua replicas.
- [ ] Native histogram được test end-to-end.
- [ ] Remote write hỗ trợ.

### Behavior

- [ ] Zero-value series được cân nhắc.
- [ ] Retry/timeout/cancel semantics rõ.
- [ ] Counter reset được test.
- [ ] Gauge được giảm ở mọi exit path.
- [ ] Error taxonomy hữu hạn.

### Lifecycle

- [ ] Unit/exposition test.
- [ ] Cardinality load test.
- [ ] Dashboard/rule query test.
- [ ] Migration/deprecation plan.
- [ ] Changelog.

---

## 39. Câu hỏi tự kiểm tra

1. Vì sao metric nên được xem như public API?
2. Golden Signals trả lời những câu hỏi nào?
3. RED khác USE ở boundary nào?
4. Utilization khác saturation thế nào?
5. Vì sao CPU cao chưa chắc là saturation?
6. Khi nào dùng Counter và khi nào dùng Gauge?
7. Vì sao nên export timestamp thay vì seconds-since?
8. Classic histogram tạo những series nào?
9. Vì sao phải giữ `le` khi aggregate classic histogram?
10. Native histogram khác classic histogram thế nào?
11. Prometheus 3.13 cần cấu hình gì để scrape native histogram?
12. Vì sao Summary quantiles không aggregate được?
13. Bucket SLO threshold giúp tính gì?
14. Vì sao đổi bucket layout là schema migration?
15. Prometheus dùng base unit nào cho time và ratio?
16. Vì sao raw URL không được dùng làm label?
17. Cardinality của histogram được ước lượng thế nào?
18. Hash user ID có giải quyết cardinality không?
19. Vì sao cần initialize một số zero series?
20. Count-at-start và count-at-end khác nhau thế nào?
21. Attempts khác operations khi có retry ra sao?
22. Messaging “processed” cần định nghĩa boundary nào?
23. Metric quan trọng nhất của batch job thường là gì?
24. Pushgateway có những failure mode nào?
25. Exemplar giải quyết nhu cầu trace ID thế nào?
26. Tại sao phải kiểm tra tên OTel metric sau translation?
27. Scrape limit có thay thế cardinality review không?
28. Recording rule có sửa raw metric semantics sai không?
29. Một metric breaking change gồm những loại nào?
30. Dashboard nên drill-down theo các lớp nào?

---

## 40. Tài liệu chính thức

- [Prometheus metric and label naming](https://prometheus.io/docs/practices/naming/)
- [Prometheus instrumentation practices](https://prometheus.io/docs/practices/instrumentation/)
- [Prometheus metric types](https://prometheus.io/docs/concepts/metric_types/)
- [Prometheus histograms and summaries](https://prometheus.io/docs/practices/histograms/)
- [Prometheus native histograms specification](https://prometheus.io/docs/specs/native_histograms/)
- [When to use the Pushgateway](https://prometheus.io/docs/practices/pushing/)
- [Prometheus recording rules](https://prometheus.io/docs/practices/rules/)
- [The Zen of Prometheus](https://prometheus.io/docs/practices/the_zen/)
- [Google SRE – Monitoring Distributed Systems](https://sre.google/sre-book/monitoring-distributed-systems/)
- [Brendan Gregg – The USE Method](https://www.brendangregg.com/usemethod.html)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [OpenTelemetry HTTP metrics semantic conventions](https://opentelemetry.io/docs/specs/semconv/http/http-metrics/)

---

## Chủ đề tiếp theo

[Alerting Strategy – SLO, alert design và on-call](alerting_strategy.md)

---

*Cập nhật lần cuối: 2026-07-29*
