# Alerting Strategy – SLO, burn rate và on-call

> Baseline mục tiêu: **Prometheus 3.13.x** và Alertmanager tương thích.
>
> Điều kiện đầu vào: đã hiểu metric type, PromQL, recording rule và metric
> contract. Xem [Metrics Design](metrics_design.md) và
> [Prometheus Advanced](../prometheus/prometheus_advanced.md).
>
> Bài này tập trung vào **chiến lược phát hiện và phản ứng**. Cách provision
> Grafana Alerting, contact point và notification policy nằm trong
> [Grafana Advanced](../grafana/grafana_advanced.md).

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- phân biệt SLI, SLO, SLA và error budget;
- chuyển một user journey thành valid/good/bad event;
- tính burn rate và hiểu đúng thời gian tiêu error budget;
- triển khai multi-window, multi-burn-rate alert;
- chọn page, ticket hoặc chỉ ghi nhận sự kiện;
- thiết kế alert label, annotation, routing và inhibition;
- xử lý low traffic, no data, batch job và capacity alert;
- viết runbook có thể hành động an toàn;
- kiểm thử rule bằng `promtool`;
- vận hành on-call và review alert bằng dữ liệu.

Mục tiêu không phải là tạo thật nhiều alert. Mục tiêu là đưa **đúng tín hiệu**
đến **đúng người**, với **đúng mức khẩn cấp** và đủ context để hành động.

---

## 2. Alerting là một control loop

```text
User journey
    │
    ▼
SLI contract ──▶ raw metrics ──▶ recording rules ──▶ alert rules
                                                        │
                                                        ▼
                                            Alertmanager / Grafana
                                                        │
                              group + deduplicate + route + inhibit
                                                        │
                                                        ▼
                                              page / ticket / event
                                                        │
                                                        ▼
                                                  human action
                                                        │
                                                        └──▶ feedback
```

Một alert chỉ hoàn thành vòng lặp nếu người nhận:

1. hiểu user impact;
2. biết cần phản ứng khi nào;
3. có quyền truy cập dashboard, log, trace và hệ thống;
4. có runbook và escalation path;
5. xác nhận được hệ thống đã phục hồi.

Nếu notification không dẫn đến hành động hoặc quyết định, nó chưa phải alert
tốt.

---

## 3. Ba loại đầu ra

Google SRE chia đầu ra monitoring thành ba nhóm hữu ích:

| Đầu ra | Kỳ vọng | Ví dụ |
|---|---|---|
| Page | con người phải phản ứng ngay | checkout đang tiêu budget rất nhanh |
| Ticket | xử lý trong vài ngày làm việc | budget đang cháy chậm nhưng bền vững |
| Event/log | lưu context, không yêu cầu phản ứng | deploy hoàn tất, config đổi |

Quy ước label gợi ý:

```yaml
labels:
  severity: critical
  notification: page
```

```yaml
labels:
  severity: warning
  notification: ticket
```

`severity` mô tả mức ảnh hưởng; `notification` mô tả workflow. Không nên dùng
`warning` vừa để Slack, email, ticket, vừa để page tùy cảm tính.

Một email không có owner và deadline thường chỉ là noise chậm.

---

## 4. Chất lượng của một alert

Đánh giá alert bằng bốn thuộc tính:

| Thuộc tính | Câu hỏi |
|---|---|
| Precision | bao nhiêu alert thực sự cần hành động? |
| Recall | bao nhiêu incident đáng phát hiện đã được alert bắt? |
| Detection time | mất bao lâu từ khi có ảnh hưởng đến lúc alert fire? |
| Reset time | sau khi phục hồi, mất bao lâu alert mới resolve? |

Tăng độ nhạy có thể cải thiện recall và detection time nhưng làm giảm precision.
Thêm cửa sổ dài có thể giảm noise nhưng phát hiện chậm hơn. Không có một
threshold tối ưu cho mọi service.

---

## 5. Alert contract

Trước khi merge một page rule, trả lời được:

| Field | Nội dung |
|---|---|
| Owner | team chịu trách nhiệm |
| Symptom | điều gì người dùng đang trải nghiệm |
| Scope | service, environment, cluster, SLO |
| Signal | metric và semantics |
| Condition | expression, window, threshold |
| Urgency | page hay ticket; vì sao |
| Action | bước đầu tiên an toàn |
| Runbook | link ổn định |
| Dashboard | link có sẵn scope |
| Escalation | primary, secondary, incident commander |
| Recovery | cách xác minh đã hết impact |
| Test | positive, negative, no-data case |

Không có owner nghĩa là không có người duy trì. Không có action nghĩa là chưa
đủ điều kiện để page.

---

## 6. Page symptom, điều tra cause

Ưu tiên page trên symptom:

```text
Nên page:
  checkout success giảm
  request hợp lệ bị lỗi
  latency vượt SLO
  job không thể hoàn thành trước deadline

Thường dùng để điều tra:
  CPU cao
  GC tăng
  queue depth tăng
  DB connection pool gần đầy
```

Cause signal vẫn hữu ích cho:

- dashboard và drill-down;
- ticket capacity trước khi xảy ra impact;
- lỗi phần cứng sắp không thể phục hồi;
- dependency contract có deadline rõ.

CPU 90% có thể là sử dụng tài nguyên hiệu quả. Checkout thất bại mới là user
impact.

---

## 7. SLI, SLO và SLA

### SLI

**Service Level Indicator** là phép đo định lượng về hành vi service.

Ví dụ:

```text
availability SLI =
  số request hợp lệ có kết quả tốt
  /
  tổng số request hợp lệ
```

### SLO

**Service Level Objective** là mục tiêu cho SLI trong một cửa sổ.

```text
99.9% request hợp lệ phải thành công trong rolling 30 ngày
```

### SLA

**Service Level Agreement** là cam kết với bên khác, thường có hậu quả kinh
doanh hoặc pháp lý khi vi phạm.

```text
SLI = đo cái gì
SLO = mục tiêu nội bộ
SLA = thỏa thuận và hậu quả
```

Không nên dùng ba từ này thay thế lẫn nhau.

---

## 8. Bắt đầu từ user journey

Ví dụ user journey “đặt hàng”:

```text
Client
  └──▶ POST /orders
         ├── validate
         ├── reserve inventory
         ├── authorize payment
         └── create order
```

Contract cần định nghĩa:

| Khái niệm | Ví dụ |
|---|---|
| Valid event | request đã qua gateway và hợp lệ về protocol |
| Good event | order được tạo trong ≤ 300 ms |
| Bad event | timeout, 5xx, hoặc response thành công nhưng > 300 ms |
| Excluded | health check, request bị client hủy trước khi server xử lý |
| Count point | khi server hoàn tất response |
| Owner | Checkout team |

Không mặc định mọi `4xx` là lỗi service. Ví dụ `429` có thể là service từ chối
user hợp lệ vì hết capacity, trong khi một số `400` là input sai của client.
Phân loại phải phản ánh user journey và product contract.

---

## 9. Error budget

Với SLO `99.9%`:

```text
error_budget_ratio = 1 - 0.999 = 0.001 = 0.1%
```

Nếu mọi phút có trọng số bằng nhau:

```text
30 ngày × 24 giờ × 60 phút × 0.001 = 43.2 phút
```

Với request-based SLI, budget chính xác là số **bad events** được phép, không
nhất thiết là 43.2 phút downtime. Downtime lúc traffic cao tiêu nhiều event
budget hơn downtime lúc traffic thấp.

Không đặt SLO 100%:

- không còn error budget;
- mọi lỗi nhỏ trở thành vi phạm;
- cản trở thay đổi mà không phản ánh đúng nhu cầu người dùng.

---

## 10. Burn rate

Burn rate là tốc độ tiêu error budget so với tốc độ cho phép:

```text
burn_rate =
  observed_bad_event_ratio
  /
  error_budget_ratio
```

Với SLO `99.9%`:

| Bad-event ratio | Burn rate | Nếu giữ nguyên, budget 30 ngày hết sau |
|---:|---:|---:|
| 0.1% | 1x | 30 ngày |
| 0.6% | 6x | 5 ngày |
| 1.44% | 14.4x | 50 giờ |
| 100% | 1000x | 43.2 phút |

Công thức tổng quát:

```text
time_to_exhaust = SLO_window / burn_rate

budget_fraction_consumed =
  burn_rate × alert_window / SLO_window
```

Điểm dễ nhầm:

```text
14.4x trong 1 giờ
  ≠ budget hết sau 1 giờ
  = tiêu 14.4 × 1h / 720h = 2% budget 30 ngày
```

Burn rate phải được đọc cùng SLO window và alert window.

---

## 11. Vì sao cần nhiều cửa sổ?

Một cửa sổ ngắn:

- phát hiện nhanh;
- dễ fire vì spike ngắn;
- dễ flap.

Một cửa sổ dài:

- ổn định;
- phản ánh budget tốt;
- reset và phát hiện chậm.

Multi-window yêu cầu cả hai:

```text
long window vượt threshold
AND
short window vẫn vượt threshold
```

Long window xác nhận vấn đề đủ lớn. Short window xác nhận vấn đề vẫn đang diễn
ra. Một guideline phổ biến là short window bằng khoảng `1/12` long window.

---

## 12. Bộ cửa sổ chuẩn cho SLO 30 ngày

Google SRE Workbook đưa ra cấu hình khởi đầu:

| Hành động | Long window | Short window | Burn rate | Budget tiêu trong long window |
|---|---:|---:|---:|---:|
| Page nhanh | 1h | 5m | 14.4x | 2% |
| Page chậm | 6h | 30m | 6x | 5% |
| Ticket | 3d | 6h | 1x | 10% |

Đây là baseline, không phải định luật. Team có thể điều chỉnh theo:

- SLO window;
- traffic;
- thời gian phản ứng;
- chi phí false positive;
- khả năng tự phục hồi;
- blast radius.

Mọi thay đổi phải được mô tả bằng phần budget tiêu thụ và detection time, không
chỉ bằng cảm giác “nhạy hơn”.

---

## 13. Metric contract dùng trong ví dụ

Bài dùng:

```text
checkout_http_server_requests_total{
  service="checkout",
  outcome="success|error",
  ...
}
```

Giả định:

- counter tăng khi response hoàn tất;
- `outcome="error"` đúng với bad event của availability SLI;
- zero-valued outcome series được initialize khi có thể;
- `service` là target label ổn định;
- health check không nằm trong user journey.

Nếu metric thực tế dùng `job`, đổi query theo contract. Không tự thêm label
không tồn tại.

---

## 14. Recording rules đủ năm cửa sổ

```yaml
groups:
  - name: checkout-slo-availability-recording
    interval: 30s
    rules:
      - record: service:slo_errors_per_request:ratio_rate5m
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

      - record: service:slo_errors_per_request:ratio_rate30m
        expr: |
          sum by (service) (
            rate(
              checkout_http_server_requests_total{
                outcome="error"
              }[30m]
            )
          )
          /
          sum by (service) (
            rate(checkout_http_server_requests_total[30m])
          )

      - record: service:slo_errors_per_request:ratio_rate1h
        expr: |
          sum by (service) (
            rate(
              checkout_http_server_requests_total{
                outcome="error"
              }[1h]
            )
          )
          /
          sum by (service) (
            rate(checkout_http_server_requests_total[1h])
          )

      - record: service:slo_errors_per_request:ratio_rate6h
        expr: |
          sum by (service) (
            rate(
              checkout_http_server_requests_total{
                outcome="error"
              }[6h]
            )
          )
          /
          sum by (service) (
            rate(checkout_http_server_requests_total[6h])
          )

  - name: checkout-slo-availability-recording-slow
    interval: 5m
    rules:
      - record: service:slo_errors_per_request:ratio_rate3d
        expr: |
          sum by (service) (
            rate(
              checkout_http_server_requests_total{
                outcome="error"
              }[3d]
            )
          )
          /
          sum by (service) (
            rate(checkout_http_server_requests_total[3d])
          )
```

Không dùng:

```promql
denominator = clamp_min(total_rate, 1)
```

Nếu traffic là `0.1 request/s`, ép denominator thành `1` làm tỷ lệ nhỏ đi 10
lần. No traffic phải được xử lý như một signal riêng, không được âm thầm sửa
mẫu số.

Khi denominator bằng zero, phép chia không tạo ra một tỷ lệ hữu ích. Điều này
không chứng minh service tốt hay xấu.

Ví dụ tách cửa sổ `3d` sang group evaluate mỗi `5m` vì ticket không cần độ phân
giải `30s`. Range query dài trên nhiều raw series có thể tốn CPU; production nên
benchmark rule duration, pre-aggregate đúng semantics khi cần và không tăng
interval của page rule chỉ để che vấn đề capacity.

---

## 15. Page rule

```yaml
groups:
  - name: checkout-slo-availability-alerts
    rules:
      - alert: CheckoutAvailabilitySLOBurnRatePage
        expr: |
          (
            service:slo_errors_per_request:ratio_rate1h{
              service="checkout"
            } > 14.4 * 0.001
            and
            service:slo_errors_per_request:ratio_rate5m{
              service="checkout"
            } > 14.4 * 0.001
          )
          or
          (
            service:slo_errors_per_request:ratio_rate6h{
              service="checkout"
            } > 6 * 0.001
            and
            service:slo_errors_per_request:ratio_rate30m{
              service="checkout"
            } > 6 * 0.001
          )
        labels:
          severity: critical
          notification: page
          team: checkout
          slo: checkout-availability
        annotations:
          summary: "Checkout availability is consuming error budget quickly"
          description: >-
            The availability SLO is above a fast-burn threshold.
            Confirm user impact and stop further budget loss.
          dashboard_url: "https://grafana.example.com/d/checkout-slo"
          runbook_url: "https://runbooks.example.com/checkout/slo-burn"
```

Rule không có `for` mặc định vì các range vector đã là cửa sổ xác nhận. Thêm
`for: 2m` không sai, nhưng sẽ tăng detection time và làm thay đổi error budget
tiêu trước khi page. Hãy đo trade-off đó.

Không ghi “budget sẽ hết sau một giờ” trong annotation. Cả hai nhánh có ý nghĩa
khác nhau, và `$value` của biểu thức logic không đại diện đơn giản cho một burn
rate duy nhất.

---

## 16. Ticket rule

```yaml
groups:
  - name: checkout-slo-availability-ticket
    rules:
      - alert: CheckoutAvailabilitySLOBurnRateTicket
        expr: |
          service:slo_errors_per_request:ratio_rate3d{
            service="checkout"
          } > 1 * 0.001
          and
          service:slo_errors_per_request:ratio_rate6h{
            service="checkout"
          } > 1 * 0.001
        labels:
          severity: warning
          notification: ticket
          team: checkout
          slo: checkout-availability
        annotations:
          summary: "Checkout availability is steadily consuming error budget"
          description: >-
            The 3-day and 6-hour windows are both above the 1x burn-rate
            threshold. Create an owned reliability task.
          dashboard_url: "https://grafana.example.com/d/checkout-slo"
          runbook_url: "https://runbooks.example.com/checkout/slo-burn"
```

Ticket phải đi vào hệ thống có owner, priority và deadline. Không discard
warning ngoài giờ làm việc rồi hy vọng nó xuất hiện lại.

---

## 17. Availability và latency SLI khác nhau

Availability numerator:

```promql
sum(rate(checkout_http_server_requests_total{outcome="error"}[5m]))
/
sum(rate(checkout_http_server_requests_total[5m]))
```

Latency bad-event ratio với classic histogram và mục tiêu `≤ 300 ms`:

```promql
1 -
(
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
)
```

Trong ví dụ này:

- success nhanh là good;
- success chậm là bad;
- error cũng là bad vì nằm trong denominator nhưng không nằm trong numerator.

Đừng alert p99 rồi gọi đó là SLO burn rate nếu SLO thực tế được định nghĩa bằng
tỷ lệ event dưới threshold.

---

## 18. Low traffic

Service ít traffic tạo ra hai vấn đề:

1. một lỗi có thể làm tỷ lệ tăng rất mạnh;
2. không có request thì không có đủ bằng chứng để tính request-based SLI.

Không thêm volume gate một cách máy móc:

```promql
error_ratio > threshold
and request_rate > 1
```

Gate có thể giấu outage toàn phần của service vốn chỉ có vài request quan trọng.
Các lựa chọn:

- dùng cửa sổ dài hơn;
- aggregate theo user journey hoặc cohort hợp lý;
- thêm synthetic probe cho critical path;
- kết hợp tỷ lệ với số lỗi tuyệt đối;
- theo dõi deadline thay vì request ratio cho batch;
- định nghĩa no-traffic là bình thường hay bất thường;
- dùng event-based error-budget accounting ngoài PromQL nếu mẫu quá thưa.

Low traffic là bài toán semantics, không phải lỗi toán học cần `clamp_min`.

---

## 19. No data không có nghĩa là healthy

Phân biệt:

```text
Service healthy
  metric tồn tại và SLI tốt

Scrape failure
  up == 0

Target biến mất khỏi discovery
  series up không tồn tại

Service không có traffic
  target vẫn up nhưng request denominator bằng zero
```

Ví dụ scrape failure:

```promql
up{job="checkout"} == 0
```

Ví dụ target dự kiến nhưng hoàn toàn biến mất:

```promql
absent(up{job="checkout"})
```

`up` chỉ cho biết Prometheus scrape được target, không cho biết checkout đang
phục vụ người dùng thành công. SLI alert và telemetry alert phải tách nhau.

Với dynamic infrastructure, `absent()` cần một nguồn inventory/desired-state
đáng tin cậy; nếu không, Prometheus không thể biết một target chưa từng tồn tại.

---

## 20. Vòng đời alert: inactive, pending, firing

```yaml
- alert: CheckoutScrapeFailed
  expr: up{job="checkout"} == 0
  for: 5m
  keep_firing_for: 10m
```

- `for: 5m`: expression phải đúng liên tục 5 phút trước khi firing.
- `keep_firing_for: 10m`: sau khi expression hết đúng, giữ firing thêm tối đa
  10 phút để tránh resolve quá sớm.

```text
false ──▶ true ── for ──▶ firing ── false ── keep_firing_for ──▶ resolved
          pending
```

`for` lọc spike nhưng trì hoãn detection. `keep_firing_for` giảm flap nhưng kéo
dài trạng thái và notification. Không copy cùng một giá trị cho mọi alert.

Nếu rule evaluation bị gián đoạn, cần hiểu Prometheus state và restart behavior;
đừng coi `for` là một scheduler bền vững cho batch workflow.

---

## 21. Label là identity, annotation là context

Alertmanager deduplicate alert instance theo label set.

Label ổn định:

```yaml
labels:
  alertname: CheckoutAvailabilitySLOBurnRatePage
  service: checkout
  cluster: prod-ap-southeast
  environment: production
  severity: critical
  notification: page
  team: checkout
  slo: checkout-availability
```

Context động:

```yaml
annotations:
  summary: "Checkout availability is consuming error budget quickly"
  dashboard_url: "..."
  runbook_url: "..."
```

Không đưa các giá trị sau vào label:

- timestamp hiện tại;
- request ID hoặc trace ID;
- error message tự do;
- current metric value;
- raw URL;
- pod UID nếu page được group ở service level.

Label động tạo alert identity mới mỗi lần evaluate, phá deduplication và làm
tăng cardinality.

---

## 22. Online service, offline job và batch job

### Online request/response

Page trên latency, error hoặc availability tác động người dùng.

### Offline pipeline

Signal hữu ích:

```text
oldest_unprocessed_event_age_seconds
```

Age gắn trực tiếp với deadline hơn queue length. Queue 1000 item có thể bình
thường ở 10k events/s nhưng nghiêm trọng ở 1 event/s.

### Periodic batch

Giả sử job chạy mỗi 4 giờ, thường mất 1 giờ, và phải có kết quả trước hai chu kỳ:

```promql
time() - checkout_reconciliation_last_success_timestamp_seconds
  > 10 * 60 * 60
```

Threshold cần đủ chỗ cho ít nhất hai lần chạy đầy đủ nếu một lần thất bại vẫn
chịu được:

```text
4h chờ lần kế tiếp + 1h chạy
+ 4h chờ retry kế tiếp + 1h chạy
= 10h
```

Nếu không chịu được một lần thất bại, giải pháp thường là chạy thường xuyên hơn,
không phải page ngay ở mọi lần fail.

---

## 23. Capacity alert

Capacity alert hợp lý nếu dự báo một outage sắp xảy ra và người nhận có thể hành
động trước deadline.

Ví dụ disk dự kiến hết trong 4 giờ:

```promql
predict_linear(
  node_filesystem_avail_bytes{
    mountpoint="/data",
    fstype!~"tmpfs|overlay"
  }[6h],
  4 * 60 * 60
) < 0
and
node_filesystem_readonly{mountpoint="/data"} == 0
```

Cần thêm:

- filter filesystem ổn định;
- `for` phù hợp để loại trend tạm thời;
- dashboard cho growth rate;
- action về retention, compaction hoặc capacity;
- phân biệt page “hết trong vài giờ” và ticket “hết trong vài tuần”.

`disk > 80%` không nói được còn bao lâu và có thể noise trên volume cố định lớn.

---

## 24. Meta-monitoring

Monitoring system cũng có thể hỏng. Theo dõi:

- Prometheus target và rule evaluation;
- missed/failed rule evaluations;
- Alertmanager availability;
- notification integration failures;
- queue/backlog của remote write nếu dùng;
- Grafana datasource health;
- synthetic alert đi hết pipeline.

Một dead-man switch:

```yaml
- alert: Watchdog
  expr: vector(1)
  labels:
    severity: none
    notification: heartbeat
  annotations:
    summary: "Monitoring alert pipeline heartbeat"
```

Receiver bên ngoài phải alert khi heartbeat **không đến**. Chỉ thấy Watchdog
firing trong Prometheus UI chưa chứng minh Pager/Slack/ticket integration hoạt
động end-to-end.

---

## 25. Alertmanager grouping và routing

```yaml
route:
  receiver: default-ticket
  group_by:
    - alertname
    - service
    - cluster
    - environment
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  routes:
    - receiver: oncall-pager
      matchers:
        - notification = "page"

    - receiver: ticketing
      matchers:
        - notification = "ticket"

receivers:
  - name: default-ticket
  - name: oncall-pager
  - name: ticketing
```

Ý nghĩa:

- `group_wait`: chờ alert cùng nhóm đến trước notification đầu;
- `group_interval`: khoảng tối thiểu trước khi gửi thay đổi của nhóm;
- `repeat_interval`: khoảng lặp lại notification cho alert chưa resolve.

Root receiver là đường an toàn cho alert không match child route. Không dùng
receiver “null” làm default.

Nếu mục tiêu là một page cho mỗi service, không group theo `instance` hoặc
`pod`. Nếu một instance cần action độc lập, mới giữ label đó trong identity.

---

## 26. Inhibition

Inhibition suppress notification của alert cấp thấp khi một alert cấp cao giải
thích cùng symptom:

```yaml
inhibit_rules:
  - source_matchers:
      - alertname = "CheckoutUnavailable"
      - severity = "critical"
    target_matchers:
      - service = "checkout"
      - severity = "warning"
    equal:
      - service
      - cluster
      - environment
```

Guardrail:

- source và target không được match cùng một alert;
- mọi label trong `equal` phải có contract và hiện diện;
- test khi label thiếu;
- không suppress alert độc lập chỉ vì cùng cluster;
- inhibition chỉ chặn notification, không sửa nguyên nhân.

Trong Alertmanager, label thiếu và label rỗng có thể được xem là bằng nhau khi
so `equal`. Một rule quá rộng có thể suppress nhiều alert ngoài ý muốn.

---

## 27. Silence, mute interval, inhibition và pause

| Cơ chế | Khi dùng | Điều không làm |
|---|---|---|
| Silence | sự kiện tạm thời, có matcher và expiry | không dừng evaluation |
| Mute time interval | maintenance định kỳ | không đổi alert state |
| Inhibition | suppress alert phụ thuộc bằng alert nguồn | không sửa dependency |
| Pause/disable rule | ngừng evaluation có chủ đích | có thể làm mất coverage |

Maintenance window:

```yaml
time_intervals:
  - name: planned-maintenance
    time_intervals:
      - weekdays: [sunday]
        times:
          - start_time: "01:00"
            end_time: "03:00"
        location: "Asia/Ho_Chi_Minh"

route:
  receiver: default-ticket
  routes:
    - receiver: oncall-pager
      matchers:
        - notification = "page"
      mute_time_intervals:
        - planned-maintenance
```

Maintenance không hoàn lại error budget. Nếu người dùng vẫn bị ảnh hưởng, SLO
report phải phản ánh đúng policy đã thống nhất.

Silence phải có:

- owner;
- lý do;
- phạm vi matcher tối thiểu;
- expiry;
- link change/incident.

Không tạo silence không thời hạn.

---

## 28. Nội dung notification

Người bị đánh thức phải nhìn thấy:

```text
What:
  Checkout availability is consuming error budget quickly

Impact:
  Valid order requests may fail

Scope:
  production / prod-ap-southeast / checkout

Since:
  firing start time

Evidence:
  SLO and burn-rate dashboard

Next action:
  validate user impact, recent changes and dependency health

Links:
  dashboard / runbook / deploys / incident channel
```

Không nhồi toàn bộ query result vào page. Notification là điểm bắt đầu điều
tra, không phải dashboard thay thế.

---

## 29. Runbook an toàn

Template:

```markdown
# CheckoutAvailabilitySLOBurnRatePage

## Ownership
- Team:
- Primary service:
- Escalation:

## User impact
- User journey:
- SLO:
- Expected symptom:

## Validate
1. Mở SLO dashboard đúng environment/cluster.
2. Xác nhận traffic và telemetry còn đầy đủ.
3. Kiểm tra synthetic probe hoặc user-facing signal độc lập.

## Diagnose
1. Kiểm tra thay đổi gần nhất.
2. Drill down theo route/outcome hợp lệ.
3. Kiểm tra dependency, saturation, log và trace.

## Mitigate
- Chọn thay đổi nhỏ nhất, có thể đảo ngược.
- Ghi điều kiện áp dụng, quyền phê duyệt và blast radius.
- Ghi rollback trigger trước khi thực hiện.

## Verify recovery
- Short và long SLI window trở lại bình thường.
- Synthetic journey thành công.
- Không còn backlog hoặc lỗi tiềm ẩn.

## Escalate and communicate
- Khi nào gọi secondary?
- Khi nào declare incident?
- Ai cập nhật stakeholder?

## Aftercare
- Link incident timeline.
- Tạo follow-up có owner/deadline.
```

Không đặt lệnh rollback hoặc scale mù quáng ngay đầu runbook. Một lệnh đúng ở
cluster này có thể sai ở cluster khác. Runbook phải có guardrail và bước xác
minh context.

---

## 30. On-call vận hành được

On-call cần:

- primary và secondary rõ ràng;
- handoff cho incident đang mở, silence và change rủi ro;
- access được kiểm tra trước ca;
- dashboard/runbook mở được từ thiết bị trực;
- escalation path không phụ thuộc trí nhớ;
- training và game day;
- quyền ưu tiên mitigation trước root-cause analysis;
- thời gian nghỉ sau ca bị gián đoạn nghiêm trọng.

Không để một kỹ sư trực 24/7 vô thời hạn. Đó là single point of failure về con
người.

Trong incident:

```text
1. Xác nhận impact và scope
2. Chặn budget loss bằng mitigation an toàn
3. Escalate sớm khi vượt năng lực hoặc thời gian
4. Ghi timeline và quyết định
5. Xác minh phục hồi bằng signal độc lập
6. Sau đó mới đào root cause đầy đủ
```

---

## 31. Error-budget policy

Error budget chỉ hữu ích khi gắn với quyết định.

Ví dụ policy:

```text
Budget còn tốt:
  release bình thường, tiếp tục reliability work đã cam kết

Budget tiêu nhanh:
  tăng review, giảm rollout risk, ưu tiên nguyên nhân lớn nhất

Budget đã vượt:
  tạm dừng thay đổi tăng rủi ro, trừ security/emergency
  tập trung phục hồi reliability

Ngoại lệ:
  được product + engineering owner ghi nhận, có expiry và mitigation
```

Policy phải được thống nhất trước incident. Không dùng error budget như công cụ
đổ lỗi cho một team.

---

## 32. Alert review bằng dữ liệu

Theo dõi:

- số page theo alert/service/ca trực;
- tỷ lệ page có hành động;
- page tự resolve trước khi người nhận phản ứng;
- acknowledgement time distribution;
- số notification lặp;
- alert firing quá lâu;
- incident đáng page nhưng không có alert;
- manual step lặp lại có thể tự động hóa;
- budget tiêu theo nguyên nhân;
- page ngoài giờ làm việc.

Không áp một mục tiêu phổ quát như “dưới 5 page/tuần” cho mọi team. Pager load
phù hợp phụ thuộc độ dài ca, mức phức tạp, thời gian xử lý và support model.

MTTA/MTTR trung bình có thể che tail xấu. Xem distribution và incident context,
không dùng một con số để xếp hạng cá nhân.

---

## 33. Alert lifecycle

```text
Draft
  └──▶ query review
         └──▶ shadow/dashboard
                └──▶ ticket route
                       └──▶ page route
                              └──▶ periodic review
                                     └──▶ tune/deprecate
```

Mỗi giai đoạn cần exit criteria:

### Draft

- SLI contract rõ;
- owner và runbook tồn tại;
- positive/negative cases được mô tả.

### Shadow

- rule evaluate nhưng không page;
- đo precision và reset time;
- so với incident/deploy thật.

### Promote

- routing, grouping, inhibition đã test;
- on-call biết alert mới;
- dashboard và access đã kiểm tra.

### Deprecate

- xác nhận không còn consumer;
- xóa route/runbook/dashboard phụ thuộc;
- ghi lý do và replacement.

Không tự động xóa alert chỉ vì ba tháng chưa fire. Một alert disaster hiếm vẫn
có giá trị; phải review risk và coverage.

---

## 34. Kiểm tra cú pháp rule

```bash
promtool check rules rules/slo-recording.yml
promtool check rules rules/slo-alerts.yml
```

Kiểm tra toàn bộ Prometheus config:

```bash
promtool check config prometheus.yml
```

`promtool check` chỉ chứng minh cú pháp và một số lỗi tĩnh. Nó không chứng minh:

- SLI semantics đúng;
- label tồn tại;
- traffic đủ;
- notification route đúng;
- runbook có thể dùng.

---

## 35. Unit test rule

Prometheus hỗ trợ:

```bash
promtool test rules tests/slo-alerts.test.yml
```

Test matrix tối thiểu:

| Case | 1h | 5m | 6h | 30m | 3d | Kỳ vọng |
|---|---:|---:|---:|---:|---:|---|
| Healthy | thấp | thấp | thấp | thấp | thấp | không alert |
| Fast burn | cao | cao | bất kỳ | bất kỳ | bất kỳ | page |
| Spike đã hết | cao | thấp | thấp | thấp | thấp | không page |
| Slow page | thấp | thấp | cao | cao | bất kỳ | page |
| Slow ticket | thấp | thấp | cao hơn 1x | thấp hơn 6x | cao hơn 1x | ticket |
| No data | absent | absent | absent | absent | absent | telemetry policy |
| Low volume | một vài event | một vài event | — | — | — | theo policy riêng |

Skeleton test:

```yaml
rule_files:
  - ../rules/slo-alerts.yml

evaluation_interval: 1m

tests:
  - name: fast burn requires both 1h and 5m windows
    interval: 1m
    input_series:
      - series: >-
          service:slo_errors_per_request:ratio_rate1h{service="checkout"}
        values: "0.02x10"
      - series: >-
          service:slo_errors_per_request:ratio_rate5m{service="checkout"}
        values: "0.02x10"
      - series: >-
          service:slo_errors_per_request:ratio_rate6h{service="checkout"}
        values: "0x10"
      - series: >-
          service:slo_errors_per_request:ratio_rate30m{service="checkout"}
        values: "0x10"
    alert_rule_test:
      - eval_time: 5m
        alertname: CheckoutAvailabilitySLOBurnRatePage
        exp_alerts:
          - exp_labels:
              service: checkout
              severity: critical
              notification: page
              team: checkout
              slo: checkout-availability
            exp_annotations:
              summary: >-
                Checkout availability is consuming error budget quickly
              description: >-
                The availability SLO is above a fast-burn threshold.
                Confirm user impact and stop further budget loss.
              dashboard_url: "https://grafana.example.com/d/checkout-slo"
              runbook_url: "https://runbooks.example.com/checkout/slo-burn"
```

Nếu recording và alert rules ở hai file, test cả:

1. raw counter → recording series;
2. recording series → alert state.

Đừng chỉ feed sẵn kết quả recording rule rồi bỏ qua lỗi aggregation.

---

## 36. Integration test notification

Trước production:

```text
Rule
  └──▶ Prometheus firing
         └──▶ Alertmanager receives
                └──▶ correct route
                       └──▶ correct grouping
                              └──▶ contact point
                                     └──▶ acknowledge
```

Test:

- alert có đúng labels/annotations;
- duplicate từ Prometheus HA không page hai lần;
- critical vào pager;
- warning tạo ticket;
- inhibition chỉ suppress mục tiêu dự kiến;
- silence hết hạn đúng lúc;
- resolved notification đúng policy;
- broken contact point tạo meta-alert;
- links mở đúng environment.

Không thử bằng cách gây outage production nếu có thể dùng synthetic test alert
và staging receiver.

---

## 37. Rule deployment

Quy trình gợi ý:

```text
edit
  → format/lint
  → promtool check
  → promtool unit tests
  → code review
  → staging/shadow
  → reload
  → verify rule evaluation
  → end-to-end notification test
```

Nếu đặt recording và alert rule cùng group, Prometheus evaluate tuần tự và dùng
cùng evaluation timestamp. Nếu tách group, alert có thể thấy recording result
từ lần evaluate trước.

Với window `3d`, cần retention và dữ liệu lịch sử đủ dài. Sau deploy metric/rule
mới, ticket rule chưa có ba ngày quan sát đầy đủ.

---

## 38. Anti-patterns

### Page mọi threshold hạ tầng

```text
CPU > 80%
memory > 75%
disk > 70%
```

Không có user impact, deadline hoặc action.

### Mọi thứ là critical

Pager trở thành notification feed; urgency mất ý nghĩa.

### Thiếu short window

Long window vẫn cao sau khi incident đã hết, làm page reset chậm.

### Thiếu recording rule được tham chiếu

Rule dùng `rate5m` hoặc `rate30m` nhưng không khai báo chúng.

### Hiểu sai burn rate

`14.4x` không có nghĩa budget hết sau một giờ.

### Ép mẫu số lên 1

Làm sai ratio ở service dưới 1 request/s.

### Page trên no data mà không hiểu nguyên nhân

Target scale-to-zero hợp lệ có thể bị coi là outage.

### Dynamic value trong label

Phá deduplication, tạo alert mới ở mỗi evaluation.

### Silence không expiry

Coverage biến mất vĩnh viễn.

### Runbook chỉ có lệnh nguy hiểm

Không xác nhận context, blast radius, approval hoặc rollback trigger.

### Warning gửi vào kênh không có owner

Notification tồn tại nhưng công việc không được hoàn thành.

---

## 39. Workshop: thiết kế alert cho checkout

### Bước 1 – viết SLO bằng câu

```text
99.9% valid checkout requests thành công trong rolling 30 ngày.
```

### Bước 2 – định nghĩa event

```text
valid = request vào đúng public route và đủ điều kiện xử lý
good  = order được tạo
bad   = valid - good
```

### Bước 3 – kiểm tra instrumentation

- numerator và denominator là Counter;
- count cùng boundary;
- outcome có vocabulary hữu hạn;
- retry semantics rõ;
- zero series được cân nhắc.

### Bước 4 – tạo SLI dashboard

- current compliance;
- remaining budget;
- burn rate theo 5m/30m/1h/6h/3d;
- valid-event volume;
- deploy annotation;
- breakdown theo dimension hữu hạn.

### Bước 5 – tạo page và ticket

- page `14.4x 1h/5m OR 6x 6h/30m`;
- ticket `1x 3d/6h`;
- telemetry alert riêng.

### Bước 6 – test edge cases

- một spike 4 phút;
- lỗi kéo dài 40 phút;
- lỗi đã hết nhưng long window còn cao;
- traffic bằng zero;
- target biến mất;
- một instance lỗi nhưng service aggregate còn tốt;
- deploy thay đổi label;
- Alertmanager receiver lỗi.

### Bước 7 – diễn tập

- on-call nhận page;
- mở được runbook;
- xác nhận impact;
- escalate;
- thực hiện mitigation giả lập;
- xác minh resolved;
- ghi feedback để tune.

---

## 40. Checklist production

### SLO

- [ ] User journey và owner rõ.
- [ ] Valid/good/bad/excluded event rõ.
- [ ] Objective và rolling/calendar window rõ.
- [ ] SLO khác SLA được phân biệt.
- [ ] Error-budget policy được thống nhất.

### Query

- [ ] Numerator và denominator cùng boundary.
- [ ] Error taxonomy đúng semantics.
- [ ] Không ép denominator làm sai low traffic.
- [ ] Đủ `5m`, `30m`, `1h`, `6h`, `3d`.
- [ ] Label aggregation giữ đúng scope.
- [ ] Retention đủ cho cửa sổ dài.

### Alert

- [ ] Page trên symptom/user impact.
- [ ] Page và ticket tách workflow.
- [ ] `for`/`keep_firing_for` có lý do.
- [ ] Label ổn định; context động ở annotation.
- [ ] Runbook và dashboard mở được.
- [ ] No-data/low-traffic policy rõ.

### Delivery

- [ ] Root receiver an toàn.
- [ ] Grouping không tạo page storm.
- [ ] Inhibition được test với label thiếu.
- [ ] Silence có owner và expiry.
- [ ] HA deduplication được test.
- [ ] Heartbeat kiểm tra end-to-end.

### Human process

- [ ] Primary/secondary và escalation rõ.
- [ ] Access được kiểm tra.
- [ ] Alert mới được thông báo cho on-call.
- [ ] Review page load bằng distribution.
- [ ] Incident feedback quay lại rule/runbook.

---

## 41. Câu hỏi tự kiểm tra

1. Page, ticket và event khác nhau ở kỳ vọng hành động nào?
2. Precision và recall trade-off ra sao?
3. SLI, SLO và SLA khác nhau thế nào?
4. Vì sao request-based budget không luôn bằng số phút downtime?
5. Burn rate `14.4x` của SLO 30 ngày có ý nghĩa gì?
6. Vì sao cần cả long và short window?
7. Cặp window chuẩn cho page nhanh là gì?
8. Vì sao `clamp_min(total_rate, 1)` làm sai low-traffic ratio?
9. No traffic khác scrape failure thế nào?
10. Khi nào `absent()` không đủ để phát hiện target biến mất?
11. Vì sao SLO rule thường không cần `for` dài?
12. `keep_firing_for` giải quyết failure mode nào?
13. Vì sao current value không được đặt vào alert label?
14. Batch job nên alert trên failure count hay last success?
15. Khi nào capacity alert đáng page?
16. Inhibition khác silence thế nào?
17. Label thiếu trong `equal` có rủi ro gì?
18. Vì sao warning nên tạo ticket thay vì bị discard ngoài giờ?
19. Watchdog end-to-end hoạt động thế nào?
20. `promtool check` và `promtool test rules` chứng minh những gì?
21. Vì sao một alert ba tháng không fire chưa chắc nên bị xóa?
22. Error-budget policy ảnh hưởng release decision thế nào?

---

## 42. Tài liệu chính thức

- [Google SRE – Service Level Objectives](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook – Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)
- [Google SRE Workbook – Example Error Budget Policy](https://sre.google/workbook/error-budget-policy/)
- [Google SRE Workbook – On-Call](https://sre.google/workbook/on-call/)
- [Prometheus alerting practices](https://prometheus.io/docs/practices/alerting/)
- [The Zen of Prometheus](https://prometheus.io/docs/practices/the_zen/)
- [Prometheus alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Prometheus recording rules](https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/)
- [Prometheus unit testing rules](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/)
- [Alertmanager configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [Alertmanager alerts API](https://prometheus.io/docs/alerting/latest/alerts_api/)

---

## Chủ đề tiếp theo

[Full Observability Stack – metrics, logs, traces và OpenTelemetry](stack_integration.md)

---

*Cập nhật lần cuối: 2026-07-29*
