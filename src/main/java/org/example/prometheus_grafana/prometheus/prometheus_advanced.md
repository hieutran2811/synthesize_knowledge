# Prometheus Advanced – PromQL, Recording Rules và Alerting Rules

> Phiên bản mục tiêu: **Prometheus 3.13.x**.
>
> Điều kiện đầu vào: đã đọc [Prometheus Fundamentals](prometheus_fundamentals.md), hiểu counter, gauge, histogram, label và time series.

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- đọc một biểu thức PromQL theo type và label set thay vì “thử đến khi có graph”;
- join hai vector mà không tạo many-to-many hoặc làm rơi series ngoài ý muốn;
- dùng subquery, `offset`, `@`, aggregation và set operator đúng ngữ nghĩa;
- thiết kế recording rule có contract rõ ràng và kiểm soát cardinality;
- hiểu vòng đời `inactive → pending → firing → resolved`;
- phân biệt alerting rule của Prometheus với routing/silence/inhibition của Alertmanager;
- kiểm tra rule bằng `promtool` trước khi deploy.

Mental model:

```text
Raw series
   │
   ├── PromQL tức thời ───────────────▶ dashboard / ad-hoc investigation
   │
   ├── Recording rule ──▶ series mới ─▶ dashboard / alerting rule
   │
   └── Alerting rule ──▶ alert instance
                              │
                              ▼
                         Alertmanager
                 group / deduplicate / route
                 silence / inhibit / notify
```

---

## 2. Đọc PromQL như một type system

PromQL có bốn value type:

| Type | Ví dụ | Ý nghĩa |
|---|---|---|
| Scalar | `0.05` | Một số đơn. |
| String | `"text"` | Có trong type system nhưng ít dùng trực tiếp. |
| Instant vector | `up{job="api"}` | Nhiều series, mỗi series có một sample tại thời điểm đánh giá. |
| Range vector | `http_requests_total[5m]` | Nhiều series, mỗi series có nhiều sample trong một cửa sổ. |

Native histogram có thể xuất hiện như sample dạng histogram bên trong instant/range vector. Không phải mọi operator/function dành cho float đều áp dụng được cho histogram sample.

### Instant query khác range query

```text
Instant query:
  đánh giá biểu thức một lần tại thời điểm T

Range query:
  đánh giá cùng một biểu thức nhiều lần:
  start, start + step, start + 2×step, ... end
```

Range query API không biến mọi selector thành range vector. Ví dụ `up` vẫn là instant-vector expression; Prometheus chỉ chạy nó lặp lại ở từng `step`.

### Câu hỏi phải trả lời ở mỗi tầng

Với biểu thức:

```promql
sum by (service) (
  rate(http_requests_total{status=~"5.."}[5m])
)
/
sum by (service) (
  rate(http_requests_total[5m])
)
```

Đọc từ trong ra ngoài:

1. `http_requests_total[5m]` là range vector của counter.
2. `rate(...)` biến mỗi range thành tốc độ/giây, kết quả là instant vector.
3. `sum by (service)` chỉ giữ label `service`.
4. Hai vế có cùng label contract nên phép chia one-to-one.
5. Kết quả là error ratio theo `service`.

Nếu không biết type hoặc label set sau mỗi tầng, việc thêm `group_left` chỉ là đoán.

---

## 3. Selector và thời gian nâng cao

### 3.1 Matcher rỗng và matcher phủ rộng

Một vector selector phải có metric name hoặc ít nhất một matcher không match chuỗi rỗng:

```promql
{job=~".+"}               # hợp lệ: cần job không rỗng
{__name__=~"http_.+"}     # hợp lệ: chọn theo metric name
```

Selector quá rộng có thể đọc hàng triệu series. Luôn bắt đầu bằng metric name và label hẹp nhất có ý nghĩa.

### 3.2 `offset`

`offset` dịch selector hoặc subquery về quá khứ so với thời điểm đánh giá:

```promql
# Traffic hiện tại
sum(rate(http_requests_total[5m]))

# Traffic tại cửa sổ tương ứng một tuần trước
sum(rate(http_requests_total[5m] offset 1w))

# Tỷ lệ week-over-week
sum(rate(http_requests_total[5m]))
/
sum(rate(http_requests_total[5m] offset 1w))
```

Modifier phải đi ngay sau selector:

```promql
# Đúng
sum(http_requests_total offset 5m)

# Sai cú pháp
sum(http_requests_total) offset 5m
```

Bẫy:

- label/instance tuần trước có thể không còn giống hiện tại;
- deploy, holiday hoặc traffic mix thay đổi làm so sánh sai ngữ cảnh;
- mẫu số bằng 0 tạo `Inf`/`NaN`;
- `offset` không phải anomaly detection model.

### 3.3 `@`

`@` cố định selector tại Unix timestamp hoặc biên của range query:

```promql
# Giá trị tại một Unix timestamp cố định
http_requests_total @ 1767225600

# Top 5 series được chọn theo giá trị tại cuối range query
topk(5, rate(http_requests_total[5m] @ end()))
```

`@ start()` và `@ end()` giúp giữ một tập series ổn định xuyên suốt range query. Nếu không, `topk(5, ...)` được tính lại tại mỗi step và toàn graph có thể chứa hơn năm series.

### 3.4 Subquery

Cú pháp:

```text
<instant-vector-expression>[<range>:<resolution>]
```

Ví dụ: lấy request rate 5 phút mỗi 1 phút, rồi tìm đỉnh trong một giờ:

```promql
max_over_time(
  sum by (service) (
    rate(http_requests_total[5m])
  )[1h:1m]
)
```

Subquery biến kết quả instant expression thành range vector để function `_over_time` xử lý.

Không gọi `rate()` của gauge chỉ vì muốn dùng subquery. Với gauge:

```promql
# Gauge cao nhất trong 1 giờ
max_over_time(shop_queue_depth[1h])

# Độ dốc tuyến tính của gauge
deriv(shop_queue_depth[30m])
```

Subquery rất tiện nhưng có thể đắt:

```text
outer steps × inner steps × input series × work của inner expression
```

Nếu dashboard và alerts chạy cùng một subquery nặng liên tục, hãy cân nhắc recording rule.

---

## 4. Chọn function theo semantics

### 4.1 Counter

```promql
# Tốc độ trung bình mỗi giây; phù hợp rule và dashboard
rate(http_requests_total[5m])

# Tổng tăng ước lượng trong cửa sổ; dễ đọc cho báo cáo
increase(http_requests_total[1h])

# Dựa vào hai sample cuối; nhạy và nhiễu hơn
irate(http_requests_total[5m])

# Số lần request counter reset
resets(http_requests_total[1h])
```

Quy tắc:

- dùng `rate()` cho alert/recording rule;
- dùng `irate()` chủ yếu khi khám phá spike trên graph;
- dùng `increase()` để diễn đạt “tăng bao nhiêu trong cửa sổ”;
- luôn `rate()` trước rồi mới aggregate để nhận ra reset từng series.

```promql
# Đúng
sum by (service) (
  rate(http_requests_total[5m])
)

# Tránh: reset từng instance có thể bị aggregation che
rate(
  (sum by (service) (http_requests_total))[5m:]
)
```

### 4.2 Gauge

```promql
avg_over_time(shop_queue_depth[30m])
max_over_time(shop_queue_depth[30m])
delta(shop_queue_depth[15m])
deriv(shop_queue_depth[30m])
changes(feature_flag_enabled[1h])
```

- `delta()` là chênh lệch đầu–cuối đã extrapolate cho gauge.
- `deriv()` dùng linear regression để ước lượng độ dốc.
- `changes()` đếm số lần giá trị đổi, không nói mức thay đổi.

### 4.3 Histogram

Classic histogram:

```promql
histogram_quantile(
  0.95,
  sum by (service, le) (
    rate(http_request_duration_seconds_bucket[5m])
  )
)
```

Native histogram:

```promql
histogram_quantile(
  0.95,
  sum by (service) (
    rate(http_request_duration_seconds[5m])
  )
)
```

`quantile(0.95, vector)` không thay thế `histogram_quantile()`:

```promql
# Đây là quantile của các giá trị sample giữa nhiều series,
# không phải p95 của toàn bộ request distribution.
quantile(
  0.95,
  rate(http_request_duration_seconds_sum[5m])
)
```

Khi một range trộn float sample và native histogram sample, một số function sẽ loại series đó và trả annotation cảnh báo. Sau migration, cần xem query warnings chứ không chỉ nhìn graph “có dữ liệu”.

### 4.4 Timestamps

```promql
# Số giây từ lần process start
time() - process_start_time_seconds

# Tuổi của lần batch thành công cuối
time() - batch_last_success_timestamp_seconds
```

`time()` là thời điểm đánh giá query, không phải timestamp của từng sample. Muốn lấy timestamp của sample, dùng function `timestamp(...)`.

---

## 5. Aggregation và contract của label

### `by` và `without`

```promql
sum by (service, status) (
  rate(http_requests_total[5m])
)

sum without (instance, pod) (
  rate(http_requests_total[5m])
)
```

Khác biệt:

- `by` chỉ giữ các label được liệt kê;
- `without` bỏ các label được liệt kê và giữ phần còn lại.

`by` tạo output contract chặt, dễ dự đoán. `without` giữ label mới trong tương lai, có ích nhưng cũng có thể làm cardinality output tăng khi exporter thêm label.

### Average của ratio thường sai

Giả sử:

```text
instance A: 1 lỗi / 10 request  = 10%
instance B: 9 lỗi / 990 request = 0,91%
```

Average hai ratio là `5,45%`, nhưng ratio toàn service là:

```text
(1 + 9) / (10 + 990) = 1%
```

PromQL đúng:

```promql
sum by (service) (
  rate(http_request_errors_total[5m])
)
/
sum by (service) (
  rate(http_requests_total[5m])
)
```

Không làm:

```promql
avg by (service) (
  rate(http_request_errors_total[5m])
  /
  rate(http_requests_total[5m])
)
```

### `topk` và `bottomk`

```promql
topk(
  10,
  sum by (route) (rate(http_requests_total[5m]))
)
```

Trong range query, top 10 được chọn lại tại mỗi step; tập union nhìn trên dashboard có thể nhiều hơn 10 route. Cố định ranking bằng `@ end()` nếu mục tiêu là một danh sách nhất quán.

### `count`, `count_values`, `group`

```promql
# Số target đang up theo job
count by (job) (up == 1)

# Có ít nhất một series cho mỗi service; value kết quả luôn là 1
group by (service) (http_requests_total)

# Đếm series theo sample value; thường dùng với info/status metric hữu hạn
count_values("version_code", application_version_code)
```

Không dùng `count_values` với sample value liên tục như latency hoặc memory bytes: gần như mỗi value sẽ thành một label value mới.

---

## 6. Binary operator và vector matching

Đây là phần gây nhiều lỗi PromQL nhất.

### Mental model “khóa join”

```text
LHS series ──khóa label── RHS series
```

Prometheus cần tìm một cặp duy nhất cho phép toán số học/comparison. Series không tìm thấy đối tác sẽ biến mất khỏi kết quả.

### 6.1 Mặc định one-to-one

```promql
metric_a / metric_b
```

Hai series match khi label set tương ứng giống nhau. Metric name không phải khóa join thông thường.

Ví dụ:

```text
errors{service="checkout", method="GET"}  2
total{service="checkout", method="GET"} 100
```

Hai series match và kết quả là `0.02`.

### 6.2 `on` và `ignoring`

```promql
# Chỉ dùng service làm khóa
errors
/
on (service)
total

# Dùng mọi label chung trừ status
errors
/
ignoring (status)
total
```

`on(...)` thường dễ review hơn vì khóa join được khai báo rõ. Nhưng nếu mỗi bên có nhiều series cùng `service`, Prometheus sẽ báo many-to-many thay vì tự chọn.

### 6.3 Many-to-one bằng `group_left`

Giả sử:

```text
request rate: nhiều series cho mỗi instance vì có route
target_info:  một series cho mỗi instance, chứa team/region
```

Thêm metadata:

```promql
rate(http_requests_total[5m])
* on (job, instance)
  group_left (team, region)
target_info
```

Ý nghĩa:

- bên trái là “many”;
- bên phải phải duy nhất theo `(job, instance)`;
- `team`, `region` được copy từ phía “one” sang output.

`group_right` dùng khi bên phải là “many”.

### 6.4 Chẩn đoán many-to-many

Trước khi join, kiểm tra uniqueness:

```promql
count by (job, instance) (target_info) > 1
```

Nếu có kết quả, phía được kỳ vọng là “one” đang có duplicate. Không sửa mù bằng cách thêm label vào `on(...)`; hãy xác định identity thực sự hoặc aggregate/deduplicate có chủ đích.

Ví dụ metadata đổi:

```text
target_info{instance="api-1", team="old"} 1
target_info{instance="api-1", team="new"} 1
```

Trong lookback window, cả hai có thể cùng tồn tại và join thất bại. Function `info()` cố đơn giản hóa use case này nhưng hiện vẫn là experimental và có giới hạn identity mặc định; không nên đưa vào production rule nếu chưa bật/đánh giá feature rõ ràng.

### 6.5 Comparison là filter

```promql
shop_queue_depth > 100
```

Mặc định chỉ giữ series có điều kiện đúng và giữ sample value gốc.

```promql
shop_queue_depth > bool 100
```

Với `bool`, series đã match nhận `1` hoặc `0`. Series không có đối tác trong vector-to-vector operation vẫn **không xuất hiện**, chứ không tự thành `0`.

### 6.6 Set operators

```promql
# Intersection: giữ LHS có label match ở RHS
vector_a and on (service) vector_b

# Union: ưu tiên LHS, thêm RHS chưa có match
vector_a or on (service) vector_b

# Complement: giữ LHS không có match ở RHS
vector_a unless on (service) vector_b
```

`and`, `or`, `unless` làm việc theo label set, không tính toán sample value giữa hai bên và không dùng `group_left/group_right`.

---

## 7. Missing, zero, `NaN` và `Inf`

### Missing không tự thành zero

```promql
sum(rate(http_request_errors_total[5m]))
```

Nếu không có error series, kết quả có thể rỗng thay vì `0`.

Cách đơn giản:

```promql
sum(rate(http_request_errors_total[5m]))
or vector(0)
```

Nhưng `vector(0)` không mang label. Với nhiều service, có thể tạo zero dựa trên inventory:

```promql
sum by (service) (
  rate(http_request_errors_total[5m])
)
or on (service)
0 * group by (service) (
  up{job=~".+-api"}
)
```

Chỉ làm vậy khi “target tồn tại nhưng chưa có lỗi” thật sự có nghĩa là zero.

### Chia cho zero

```text
số dương / 0 → +Inf
0 / 0        → NaN
```

Alert error ratio nên có traffic floor:

```promql
(
  service:http_request_errors_per_requests:ratio_rate5m > 0.05
)
and on (service)
(
  service:http_requests:rate5m > 1
)
```

Điều này tránh page vì một lỗi trên traffic gần bằng zero.

### `NaN` không phải missing

`NaN` là sample tồn tại nhưng không có giá trị số hữu ích; missing là không có vector element. `or` không thay `NaN` bằng RHS vì LHS vẫn tồn tại.

---

## 8. Debug PromQL theo pipeline

Với query dài, chạy từng tầng:

```promql
# 1. Raw series có tồn tại?
http_requests_total

# 2. Selector đúng?
http_requests_total{service="checkout"}

# 3. Range có đủ sample?
http_requests_total{service="checkout"}[5m]

# 4. Function đúng type?
rate(http_requests_total{service="checkout"}[5m])

# 5. Aggregation output còn label nào?
sum by (service) (
  rate(http_requests_total[5m])
)

# 6. Mỗi phía join có unique theo key?
count by (service) (service_info)
```

Checklist khi kết quả rỗng:

1. metric name có đúng registry/exposition thực tế không?
2. time range có data không?
3. matcher có loại hết series không?
4. `rate` window có đủ sample không?
5. binary operation có label match không?
6. một phía có duplicate theo join key không?
7. float/native histogram mix có tạo warning không?

### Query cost

Cost thường tăng theo:

```text
số series được chọn
× số sample mỗi series
× số step của range query
× độ phức tạp aggregation/join/subquery
```

Tối ưu theo thứ tự:

1. thu hẹp selector/cardinality;
2. giảm range hoặc tăng step;
3. bỏ label không cần trước join;
4. tránh subquery lồng sâu;
5. recording rule cho query lặp lại;
6. sửa instrumentation nếu raw cardinality sai.

Recording rule không cứu được ingest cardinality đã bùng nổ; nó chỉ tạo thêm series precomputed.

---

## 9. Recording Rules

Recording rule chạy PromQL định kỳ và lưu kết quả thành time series mới:

```text
Query đắt lặp lại 100 lần
  → evaluate một lần mỗi interval
  → lưu output metric
  → dashboard/alert đọc metric nhỏ hơn
```

### Khi nên dùng

- cùng query xuất hiện trong nhiều dashboard/alert;
- query phải scan nhiều raw series;
- cần một metric contract dùng chung giữa các team;
- cần aggregate trước khi giữ dữ liệu dài hạn/remote write.

### Khi chưa nên dùng

- query ad-hoc hiếm chạy;
- expression còn thay đổi liên tục;
- chỉ muốn “che” instrumentation/cardinality sai;
- output vẫn có cardinality gần bằng raw input;
- chưa có owner, test và migration plan.

### Rule group

```yaml
groups:
  - name: api-recording
    interval: 30s
    limit: 5000
    query_offset: 15s
    rules:
      - record: service:http_requests:rate5m
        expr: |
          sum by (service) (
            rate(http_requests_total[5m])
          )
```

Ý nghĩa:

- `interval`: chu kỳ riêng của group, nếu bỏ dùng global `evaluation_interval`;
- `limit`: giới hạn output series/alerts **mỗi rule**, `0` là không giới hạn;
- `query_offset`: đánh giá dữ liệu lùi về quá khứ để chờ ingestion trễ;
- rules trong cùng group chạy tuần tự với cùng evaluation timestamp.

`limit` không cắt lấy “5.000 series đầu”. Khi vượt giới hạn, toàn bộ output của rule bị discard và evaluation báo lỗi. Với alerting rule, các alert của rule đó còn có thể bị clear. Vì vậy limit là guardrail cuối, không thay cardinality design.

Nếu group chưa chạy xong khi tới lượt kế tiếp, iteration mới bị skip. Theo dõi:

```promql
increase(rule_group_iterations_missed_total[15m]) > 0
```

### Dependency

Rule sau trong cùng group có thể đọc output của rule trước vì group chạy tuần tự:

```yaml
rules:
  - record: service:http_requests:rate5m
    expr: sum by (service) (rate(http_requests_total[5m]))

  - record: fleet:http_requests:sum_rate5m
    expr: sum(service:http_requests:rate5m)
```

Không giả định thứ tự giữa hai group khác nhau. Tránh chuỗi dependency dài vì tăng latency, khó test và làm một lỗi đầu chuỗi lan rộng.

---

## 10. Naming và contract của recording rule

Quy ước chính thức:

```text
<level>:<metric>:<operations>
```

Ví dụ:

```text
service:http_requests:rate5m
service:http_request_errors:rate5m
service:http_request_errors_per_requests:ratio_rate5m
service_le:http_request_duration_seconds_bucket:rate5m
```

- `level`: các label aggregate còn lại;
- `metric`: giữ gần tên gốc, bỏ `_total` sau `rate/irate`;
- `operations`: operation mới nhất đứng trước trong chuỗi tên.

Một recording rule là API nội bộ. Contract gồm:

- metric name;
- output labels;
- unit và semantics;
- evaluation interval;
- source metrics;
- owner;
- retention/deprecation policy.

Đổi label output là breaking change với dashboard, alert và downstream remote consumer.

### Record distribution, không record một quantile duy nhất

Thay vì chỉ record p95:

```yaml
- record: service_le:http_request_duration_seconds_bucket:rate5m
  expr: |
    sum by (service, le) (
      rate(http_request_duration_seconds_bucket[5m])
    )
```

Dashboard có thể tính p50/p95/p99 từ cùng distribution:

```promql
histogram_quantile(
  0.95,
  service_le:http_request_duration_seconds_bucket:rate5m
)
```

Điều này giữ khả năng chọn quantile và threshold sau này.

---

## 11. Bộ recording rules thực hành

`rules/api-recording.yml`:

```yaml
groups:
  - name: api-recording
    interval: 30s
    limit: 5000
    rules:
      - record: service:http_requests:rate5m
        expr: |
          sum by (service) (
            rate(http_requests_total[5m])
          )

      - record: service:http_request_errors:rate5m
        expr: |
          sum by (service) (
            rate(http_requests_total{status=~"5.."}[5m])
          )

      - record: service:http_request_errors_per_requests:ratio_rate5m
        expr: |
          service:http_request_errors:rate5m
          /
          service:http_requests:rate5m

      - record: service_le:http_request_duration_seconds_bucket:rate5m
        expr: |
          sum by (service, le) (
            rate(http_request_duration_seconds_bucket[5m])
          )

      - record: instance:node_cpu_utilization:ratio_rate5m
        expr: |
          1 -
          avg by (instance) (
            rate(node_cpu_seconds_total{mode="idle"}[5m])
          )

      - record: instance_mountpoint:node_filesystem_avail:ratio
        expr: |
          node_filesystem_avail_bytes{
            fstype!~"tmpfs|overlay",
            mountpoint!=""
          }
          /
          node_filesystem_size_bytes{
            fstype!~"tmpfs|overlay",
            mountpoint!=""
          }
```

Kiểm tra output:

```promql
count by (__name__) (
  {__name__=~"service:.*|instance:.*|instance_mountpoint:.*"}
)
```

Không dùng selector này trong dashboard production nếu regex metric name quá rộng; nó chỉ phục vụ kiểm kê trong lab.

---

## 12. Alerting Rules và vòng đời alert

Một alerting rule không trả boolean đơn. Nó trả một instant vector:

```promql
service:http_request_errors_per_requests:ratio_rate5m > 0.05
```

Mỗi output series trở thành một **alert instance** độc lập.

```text
Không có trong output
  → inactive

Có trong output, chưa đủ `for`
  → pending

Liên tục có cùng label identity đủ `for`
  → firing

Condition mất
  → resolved
  hoặc tiếp tục firing trong `keep_firing_for`
```

### `for`

```yaml
for: 10m
```

Alert chỉ firing nếu cùng alert instance liên tục thỏa điều kiện trong 10 phút. Nếu expression rỗng một evaluation, pending timer reset.

`for` không phải lúc nào cũng cần:

- page theo burn rate có thể cần multi-window thay vì `for` dài;
- data pipeline chỉ chạy mỗi ngày cần logic freshness phù hợp;
- target down quan trọng có thể dùng `for` ngắn.

### `keep_firing_for`

```yaml
keep_firing_for: 5m
```

Giữ alert ở trạng thái firing thêm một khoảng sau khi condition mất, giúp giảm flapping hoặc data gap ngắn. Nó trì hoãn resolve; không thay thế `for`.

### Identity nằm trong labels

Alert identity gồm `alertname` và label set cuối cùng. Vì vậy:

```yaml
labels:
  severity: page
  team: checkout

annotations:
  current_value: "{{ $value }}"
```

Không đặt `$value` vào label:

```yaml
labels:
  # Sai: value thay đổi mỗi lần evaluation, identity cũng thay đổi.
  current_value: "{{ $value }}"
```

Thông tin dùng để route/group/deduplicate nằm trong labels. Nội dung thay đổi để con người đọc nằm trong annotations.

---

## 13. Bộ alerting rules thực hành

`rules/api-alerts.yml`:

```yaml
groups:
  - name: api-alerts
    interval: 30s
    limit: 1000
    rules:
      - alert: ApiHighErrorRatio
        expr: |
          (
            service:http_request_errors_per_requests:ratio_rate5m > 0.05
          )
          and on (service)
          (
            service:http_requests:rate5m > 1
          )
        for: 10m
        keep_firing_for: 5m
        labels:
          severity: page
          team: application
        annotations:
          summary: "Tỷ lệ lỗi cao trên {{ $labels.service }}"
          description: >-
            Error ratio hiện tại là {{ $value | humanizePercentage }},
            vượt ngưỡng 5% với traffic lớn hơn 1 req/s.
          runbook_url: "https://runbooks.example.com/api-high-error-ratio"
          dashboard_url: "https://grafana.example.com/d/api-overview"

      - alert: ApiHighP95Latency
        expr: |
          (
            histogram_quantile(
              0.95,
              service_le:http_request_duration_seconds_bucket:rate5m
            ) > 0.75
          )
          and on (service)
          (
            service:http_requests:rate5m > 1
          )
        for: 10m
        labels:
          severity: ticket
          team: application
        annotations:
          summary: "P95 latency cao trên {{ $labels.service }}"
          description: >-
            P95 latency là {{ $value | humanizeDuration }},
            vượt ngưỡng 750ms.
          runbook_url: "https://runbooks.example.com/api-high-latency"

      - alert: InstanceDown
        expr: up{job=~"shop-api|payment-api"} == 0
        for: 3m
        labels:
          severity: page
          team: platform
        annotations:
          summary: "Không scrape được {{ $labels.instance }}"
          description: >-
            Prometheus không scrape thành công job {{ $labels.job }}
            tại {{ $labels.instance }} trong ít nhất 3 phút.
          runbook_url: "https://runbooks.example.com/instance-down"

      - alert: PaymentTargetsMissing
        expr: absent(up{job="payment-api"})
        for: 5m
        labels:
          severity: page
          team: platform
          service: payment
        annotations:
          summary: "Không còn target payment-api"
          description: >-
            Prometheus không có bất kỳ series up nào cho job payment-api.
            Kiểm tra service discovery, relabeling và deployment.
          runbook_url: "https://runbooks.example.com/targets-missing"

      - alert: FilesystemWillFillSoon
        expr: |
          predict_linear(
            node_filesystem_avail_bytes{
              fstype!~"tmpfs|overlay",
              mountpoint!=""
            }[6h],
            4 * 60 * 60
          ) < 0
          and
          deriv(
            node_filesystem_avail_bytes{
              fstype!~"tmpfs|overlay",
              mountpoint!=""
            }[6h]
          ) < 0
        for: 30m
        labels:
          severity: ticket
          team: platform
        annotations:
          summary: "Filesystem có thể đầy trong 4 giờ"
          description: >-
            {{ $labels.instance }} mount {{ $labels.mountpoint }}
            đang giảm dung lượng theo xu hướng tuyến tính 6 giờ.
          runbook_url: "https://runbooks.example.com/filesystem-fill"
```

`predict_linear` chỉ là linear regression. Backup, cleanup theo lịch, workload theo chu kỳ hoặc filesystem gần đầy nhưng ổn định có thể làm dự báo kém. Luôn kết hợp trend direction, `for`, dashboard và runbook.

---

## 14. Alert tốt cần contract gì?

| Thành phần | Mục đích |
|---|---|
| `alert` | Tên ổn định, thường CamelCase. |
| `expr` | Symptom có liên hệ với user/system impact. |
| `for` | Lọc blip theo tolerance đã định. |
| `keep_firing_for` | Giảm resolve/re-fire do gap hoặc flapping. |
| `team`/`owner` label | Chỉ rõ người chịu trách nhiệm. |
| `severity` label | Điều khiển route và response expectation. |
| `service`/`cluster` label | Scope điều tra và grouping. |
| `summary` annotation | Một câu mô tả sự cố. |
| `description` annotation | Giá trị, threshold, duration và impact. |
| `runbook_url` | Các bước xác minh và hành động an toàn. |
| `dashboard_url` | Context để điều tra. |

Alert page phải actionable. Nếu người trực chỉ có thể “nhìn rồi chờ”, đó có thể là dashboard/ticket signal chứ chưa phải page.

### Alert trên symptom trước cause

```text
Symptom:
  error ratio cao, latency vượt SLO, không xử lý được request

Cause:
  CPU cao, GC nhiều, connection pool gần đầy
```

Page bằng symptom; dùng cause metrics để điều tra hoặc tạo ticket có owner. Page mọi cause tạo alert storm khi một outage sinh nhiều hậu quả.

---

## 15. Burn rate: hiểu đúng con số

Với SLO 99,9%:

```text
error budget ratio = 1 - 0,999 = 0,001
burn rate = observed error ratio / 0,001
```

Nếu error ratio là 1,44%:

```text
burn rate = 0,0144 / 0,001 = 14,4x
```

`14,4x` không có nghĩa “toàn bộ budget hết trong một giờ”. Trong pattern multi-window phổ biến cho cửa sổ SLO 30 ngày, threshold 14,4x trên cửa sổ dài 1 giờ biểu diễn khoảng **2% budget bị tiêu trong một giờ**:

```text
14,4 × 1h / 720h = 2%
```

Hai cửa sổ thường được ghép bằng `and`:

```promql
(
  service:slo_errors_per_requests:ratio_rate5m > 14.4 * 0.001
)
and on (service)
(
  service:slo_errors_per_requests:ratio_rate1h > 14.4 * 0.001
)
```

- short window xác nhận sự cố vẫn đang diễn ra;
- long window xác nhận tác động đủ lớn;
- threshold phụ thuộc SLO window và phần budget muốn tiêu;
- chi tiết strategy thuộc bài [Alerting Strategy & SLO](../observability/alerting_strategy.md).

---

## 16. Prometheus và Alertmanager chia việc thế nào?

```text
Prometheus:
  condition + for + keep_firing_for
  labels + annotations
  gửi lại firing alerts định kỳ

Alertmanager:
  grouping + deduplication + routing
  silence + inhibition
  notification timing + receiver
```

Không đưa routing theo team vào PromQL nếu có thể biểu diễn bằng label. Không dùng silence để sửa một rule sai; sửa rule và test lại.

### Cấu hình Prometheus gửi alert

```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - "alertmanager-1:9093"
            - "alertmanager-2:9093"

rule_files:
  - "rules/*.yml"
```

Trong Alertmanager HA, Prometheus nên gửi tới danh sách tất cả Alertmanager instance, không đặt một load balancer để chọn một instance duy nhất.

---

## 17. Routing tree tối thiểu

`alertmanager.yml`:

```yaml
route:
  receiver: default
  group_by: ["cluster", "alertname", "service"]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h

  routes:
    - receiver: application-page
      matchers:
        - 'team="application"'
        - 'severity="page"'

    - receiver: platform-page
      matchers:
        - 'team="platform"'
        - 'severity="page"'

    - receiver: ticket
      matchers:
        - 'severity="ticket"'

inhibit_rules:
  - source_matchers:
      - 'alertname="InstanceDown"'
    target_matchers:
      - 'alertname="FilesystemWillFillSoon"'
    equal: ["job", "instance"]

receivers:
  - name: default
    webhook_configs:
      - url: "http://notification-gateway:8080/default"
        send_resolved: true

  - name: application-page
    webhook_configs:
      - url: "http://notification-gateway:8080/application-page"
        send_resolved: true

  - name: platform-page
    webhook_configs:
      - url: "http://notification-gateway:8080/platform-page"
        send_resolved: true

  - name: ticket
    webhook_configs:
      - url: "http://notification-gateway:8080/ticket"
        send_resolved: true
```

### Routing không đơn giản là “mọi match đều chạy”

- mọi alert bắt đầu ở root route;
- root không được có matcher;
- child routes được xét theo thứ tự;
- mặc định dừng sau child đầu tiên match;
- `continue: true` cho phép tiếp tục xét các sibling sau;
- child kế thừa setting từ parent nếu không override.

### Ba khoảng thời gian

| Setting | Ý nghĩa |
|---|---|
| `group_wait` | Chờ trước notification đầu của group mới. |
| `group_interval` | Khoảng kiểm tra/gửi thay đổi tiếp theo của group. |
| `repeat_interval` | Gửi nhắc lại nếu group firing không đổi. |

`group_wait` quá ngắn có thể gửi trước khi alert liên quan tới để group/inhibit. Quá dài làm chậm page.

### `group_by` là quyết định UX và cardinality

```yaml
group_by: ["alertname", "cluster"]
```

Gộp nhiều instance thành một notification.

```yaml
group_by: ["alertname", "cluster", "instance"]
```

Mỗi instance có thể thành group riêng.

```yaml
group_by: ["..."]
```

Tắt aggregation, gần như mỗi label set đi riêng; hiếm khi là lựa chọn tốt.

---

## 18. Silence, inhibition và `for`

| Cơ chế | Nằm ở | Dùng khi |
|---|---|---|
| `for` | Prometheus rule | Condition phải kéo dài đủ lâu. |
| `keep_firing_for` | Prometheus rule | Trì hoãn resolve để giảm flapping/gap. |
| Silence | Alertmanager state | Maintenance hoặc mute có thời hạn theo matcher. |
| Inhibition | Alertmanager config | Alert nguyên nhân đang firing thì mute notification hậu quả. |
| Route time interval | Alertmanager config | Mute/activate route theo lịch đã định. |

Silence chỉ chặn notification; alert vẫn firing và vẫn quan sát được.

Ví dụ với `amtool`:

```bash
amtool \
  --alertmanager.url=http://localhost:9093 \
  silence add \
  alertname="InstanceDown" \
  instance="api-1:8080"

amtool \
  --alertmanager.url=http://localhost:9093 \
  silence query
```

Trong production, silence cần author, comment/ticket, thời gian kết thúc và scope hẹp. Không silence bằng matcher `severity=~".*"` nếu chưa chứng minh phạm vi.

### Bẫy inhibition

```yaml
equal: ["cluster", "service"]
```

Alertmanager coi label missing và label có giá trị rỗng là tương đương. Nếu cả source và target đều thiếu `service`, inhibition vẫn có thể áp dụng. Hãy đảm bảo các label trong `equal` thực sự tồn tại ở cả hai loại alert và source/target không vô tình match cùng một tập.

---

## 19. Validate và unit test rules

### Syntax/config validation

```bash
promtool check config prometheus.yml
promtool check rules rules/*.yml
amtool check-config alertmanager.yml

# Chuẩn bị cho matcher parser UTF-8 strict
amtool check-config alertmanager.yml \
  --enable-feature="utf8-strict-mode"
```

`check rules` chứng minh YAML/PromQL parse được, không chứng minh threshold và label contract đúng.

### Unit test alert lifecycle

`rules/instance-alerts.yml`:

```yaml
groups:
  - name: instance-alerts
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 3m
        labels:
          severity: page
          team: platform
        annotations:
          summary: "Instance {{ $labels.instance }} down"
```

`rules/instance-alerts.test.yml`:

```yaml
rule_files:
  - instance-alerts.yml

evaluation_interval: 1m

tests:
  - interval: 1m
    input_series:
      - series: 'up{job="shop-api", instance="api-1:8080"}'
        values: '1 1 0 0 0 0'

    alert_rule_test:
      # Condition mới kéo dài 2 phút: chưa firing.
      - eval_time: 4m
        alertname: InstanceDown
        exp_alerts: []

      # Condition bắt đầu ở phút 2, tới phút 5 đã đủ for: 3m.
      - eval_time: 5m
        alertname: InstanceDown
        exp_alerts:
          - exp_labels:
              instance: "api-1:8080"
              job: shop-api
              severity: page
              team: platform
            exp_annotations:
              summary: "Instance api-1:8080 down"
```

Chạy:

```bash
promtool test rules rules/instance-alerts.test.yml
```

### Test recording rule/PromQL output

```yaml
promql_expr_test:
  - expr: up == 0
    eval_time: 5m
    exp_samples:
      - labels: 'up{instance="api-1:8080",job="shop-api"}'
        value: 0
```

Test nên bao phủ:

- ngay dưới/ngay trên threshold;
- đủ và chưa đủ `for`;
- counter reset;
- missing series;
- denominator bằng zero hoặc traffic thấp;
- output labels sau aggregation/join;
- native/classic histogram migration nếu có.

---

## 20. Deploy rules an toàn

```text
1. Viết/change rule
2. Review semantics + label/cardinality contract
3. promtool check
4. promtool unit tests
5. Chạy expression trên production data ở chế độ read-only
6. Quan sát số output series/alert instances
7. Deploy canary hoặc một Prometheus replica
8. Reload
9. Kiểm tra /rules, /alerts và self-metrics
10. Roll out phần còn lại
```

Prometheus chỉ áp dụng reload nếu cấu hình/rule files hợp lệ. Dù vậy, rule hợp lệ cú pháp vẫn có thể:

- tạo hàng nghìn alert;
- page nhầm team;
- làm query engine quá tải;
- reset `for` vì alert labels thay đổi;
- tạo recording series sai unit.

### Self-metrics nên theo dõi

```promql
# Evaluation failures
increase(prometheus_rule_evaluation_failures_total[15m]) > 0

# Missed iterations
increase(rule_group_iterations_missed_total[15m]) > 0

# Thời gian evaluation so với interval
prometheus_rule_group_last_duration_seconds

# Alertmanager discovery/notification path cần theo dõi bằng
# các prometheus_notifications_* và alertmanager_* metrics phù hợp deployment.
```

Tên self-metric có thể thay đổi giữa component/version; xác nhận tại `/metrics` trước khi viết rule production.

---

## 21. Những lỗi thiết kế thường gặp

### Join rồi mất series

Nguyên nhân: RHS không có match. Binary arithmetic không giữ LHS unmatched.

### Many-to-many

Nguyên nhân: key trong `on(...)` không unique ở phía “one”. Kiểm tra bằng `count by (...) > 1`.

### Alert không bao giờ đủ `for`

Nguyên nhân: dynamic value nằm trong labels hoặc output label set chập chờn. Chuyển giá trị mô tả sang annotations.

### Average của p95 hoặc ratio

Nguyên nhân: aggregate statistic đã aggregate. Quay về numerator/denominator hoặc distribution rồi aggregate trước.

### Recording rule nhanh nhưng số liệu khác raw query

Nguyên nhân: label bị bỏ, interval/query offset khác, dependency order hoặc rule name cũ vẫn được dashboard dùng.

### Silence rồi vẫn thấy alert

Đúng behavior: silence mute notification, không xóa trạng thái firing.

### Alertmanager gửi trùng trong network partition

HA Alertmanager ưu tiên không bỏ lỡ notification; partition có thể tạo duplicate. Đây không phải exactly-once delivery.

### Burn-rate alert mô tả “hết budget trong một giờ”

Sai nếu chỉ dựa threshold 14,4x. Phải tính phần budget tiêu trong long window và SLO window như mục 15.

---

## 22. Checklist review

### PromQL

- [ ] Type của input/function đúng.
- [ ] `rate()` chạy trước aggregation.
- [ ] Label set sau mỗi aggregation được biết rõ.
- [ ] Vector matching có khóa và phía “one” unique.
- [ ] Missing/zero/NaN/Inf được xử lý theo business semantics.
- [ ] Query không average ratio, average hoặc quantile đã aggregate.
- [ ] Subquery/range/step có cost budget.

### Recording rule

- [ ] Query thật sự lặp lại hoặc đắt.
- [ ] Tên theo `level:metric:operations`.
- [ ] Unit, labels, interval và owner được ghi rõ.
- [ ] Output cardinality được đo.
- [ ] Dependency nằm cùng group hoặc không dựa order giữa group.
- [ ] Có migration/deprecation cho consumer.

### Alerting rule

- [ ] Alert dựa trên symptom/actionable impact.
- [ ] Có traffic floor hoặc missing-data semantics khi cần.
- [ ] Labels ổn định và đủ cho route/group.
- [ ] Dynamic values chỉ nằm trong annotations.
- [ ] `for`/`keep_firing_for` phản ánh tolerance thật.
- [ ] Có team, severity, runbook và dashboard.
- [ ] Có unit test threshold/lifecycle/labels.

### Alertmanager

- [ ] Root route không có matcher.
- [ ] Thứ tự child route và `continue` được test.
- [ ] `group_by` không tạo notification storm.
- [ ] Inhibition `equal` labels tồn tại ở source/target.
- [ ] Silence có owner, comment, expiry và scope hẹp.
- [ ] Matcher tương thích UTF-8 strict mode.

---

## 23. Câu hỏi tự kiểm tra

1. Range query khác range vector thế nào?
2. Vì sao unmatched vector element biến mất khi chia hai vector?
3. Khi nào cần `group_left`, và phía nào phải unique?
4. `> 0` khác `> bool 0` thế nào?
5. Vì sao `avg(p95)` không phải p95 toàn service?
6. Khi nào subquery nên được thay bằng recording rule?
7. Rules trong hai group có được giả định thứ tự không?
8. Vì sao không đưa `$value` vào alert labels?
9. `for`, `keep_firing_for`, silence và inhibition khác nhau thế nào?
10. Burn rate 14,4x trên long window 1 giờ tiêu bao nhiêu phần trăm budget 30 ngày?

---

## 24. Tài liệu chính thức

- [Querying basics](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [PromQL operators và vector matching](https://prometheus.io/docs/prometheus/latest/querying/operators/)
- [PromQL functions](https://prometheus.io/docs/prometheus/latest/querying/functions/)
- [Defining recording và alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)
- [Recording rule naming practices](https://prometheus.io/docs/practices/rules/)
- [Alerting practices](https://prometheus.io/docs/practices/alerting/)
- [Unit testing rules](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/)
- [Alertmanager concepts](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Alertmanager configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [Alertmanager high availability](https://prometheus.io/docs/alerting/latest/high_availability/)

---

## Chủ đề tiếp theo

[Service Discovery và Relabeling](service_discovery.md)

---

*Cập nhật lần cuối: 2026-07-29*
