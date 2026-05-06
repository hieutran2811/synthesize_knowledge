# Prometheus Advanced – PromQL, Recording Rules & Alerting

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – PromQL Advanced là gì?

PromQL (Prometheus Query Language) là **functional query language** cho time-series data. Ngoài cú pháp cơ bản, advanced PromQL bao gồm: subqueries, offset, joins, recording rules để tối ưu hiệu suất, và alerting rules để tự động phát hiện vấn đề.

---

## How – PromQL Nâng Cao

### Subquery

```promql
# Subquery: tính rate của gauge trong khoảng thời gian dài
# Syntax: expr[<range>:<resolution>]

# Tính max rate(requests) trong 1h, với resolution 1m
max_over_time(rate(http_requests_total[5m])[1h:1m])

# Tính avg latency p99 trong 24h qua
avg_over_time(
  histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))[24h:5m]
)

# Cảnh báo khi cpu spike bất thường hơn 6h trước
rate(node_cpu_seconds_total{mode="user"}[5m])
  > 2 * rate(node_cpu_seconds_total{mode="user"}[5m] offset 6h)
```

### Offset Modifier

```promql
# So sánh với tuần trước (week-over-week)
rate(http_requests_total[5m])
  /
rate(http_requests_total[5m] offset 1w)

# Phát hiện anomaly: hiện tại vs 1 giờ trước
rate(errors_total[5m]) > 2 * rate(errors_total[5m] offset 1h)

# @ modifier: query tại thời điểm cụ thể (Prometheus 2.25+)
http_requests_total @ 1609459200  # Unix timestamp
```

### Vector Matching (Join)

```promql
# one-to-one matching (default)
# Cần labels giống nhau
metric_a * metric_b

# ignoring: bỏ qua label khi match
method_code:http_errors:rate5m
  / ignoring(code)
method:http_requests:rate5m

# on: chỉ match theo các labels chỉ định
sum by (instance, job) (rate(errors_total[5m]))
  / on (instance, job)
sum by (instance, job) (rate(requests_total[5m]))

# group_left / group_right: many-to-one join
# Thêm labels từ metric có ít cardinality hơn vào metric chính
rate(http_requests_total[5m])
  * on (instance) group_left (datacenter, team)
node_info  # metric chứa datacenter, team labels

# Ví dụ thực tế: join với kube_pod_info để lấy thêm labels
container_cpu_usage_seconds_total
  * on (pod, namespace) group_left (label_app, label_version)
kube_pod_labels
```

### Advanced Aggregation

```promql
# count_values: đếm số series có cùng giá trị
count_values("version", kube_pod_container_info)

# quantile: tính quantile của nhiều series
# quantile(phi, vector) - phi: 0-1
quantile(0.95, rate(http_request_duration_seconds_sum[5m]))

# stddev, stdvar: phát hiện outliers
stddev(rate(http_requests_total[5m])) by (job)

# Phát hiện instance nào có request rate cao bất thường
(
  rate(http_requests_total[5m])
  - avg without (instance) (rate(http_requests_total[5m]))
)
/ stddev without (instance) (rate(http_requests_total[5m]))
> 2  # z-score > 2 (outlier)
```

---

## How – Recording Rules

Recording rules tính toán trước và lưu kết quả như metric mới, giúp **tăng tốc dashboard query** và **giảm tải query engine**.

```yaml
# rules/recording.yml
groups:
  - name: http_recording_rules
    interval: 30s    # ghi mỗi 30s (override global evaluation_interval)
    rules:
      # Tính req/s theo job (thay vì query full cardinality mỗi lần)
      - record: job:http_requests:rate5m
        expr: sum by (job) (rate(http_requests_total[5m]))

      # Error ratio theo job + handler
      - record: job_handler:http_errors:rate5m
        expr: |
          sum by (job, handler) (rate(http_requests_total{status=~"5.."}[5m]))
          /
          sum by (job, handler) (rate(http_requests_total[5m]))

      # p99 latency đã tính sẵn (Histogram)
      - record: job:http_request_duration_p99:rate5m
        expr: |
          histogram_quantile(0.99,
            sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]))
          )

      # CPU usage per instance
      - record: instance:node_cpu:rate5m
        expr: |
          100 - (avg by (instance) (
            rate(node_cpu_seconds_total{mode="idle"}[5m])
          ) * 100)

  - name: business_recording_rules
    rules:
      # Revenue per minute (business metric)
      - record: service:order_revenue:rate1m
        expr: sum(rate(order_amount_total[1m])) by (currency)

      # Active users (sliding window)
      - record: service:active_users:5m
        expr: count(increase(user_request_total[5m]) > 0)
```

**Naming convention cho recording rules:**

```
<level>:<metric>:<operations>

level:    aggregation level (job, instance, cluster, service)
metric:   base metric name
ops:      operations applied (rate5m, ratio, count, p99, etc.)

Ví dụ:
  job:http_requests:rate5m
  instance:node_cpu:avg_rate5m
  cluster:jvm_heap_used:ratio
```

---

## How – Alerting Rules

```yaml
# rules/alerts.yml
groups:
  - name: application_alerts
    rules:
      # --- HIGH AVAILABILITY ---
      - alert: InstanceDown
        expr: up == 0
        for: 5m          # phải fire liên tục 5m mới gửi alert (giảm false positive)
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "Instance {{ $labels.instance }} is down"
          description: "{{ $labels.job }} on {{ $labels.instance }} has been down for 5 minutes."
          runbook_url: "https://wiki.example.com/runbooks/instance-down"

      # --- ERROR RATE ---
      - alert: HighErrorRate
        expr: |
          (
            sum by (job) (rate(http_requests_total{status=~"5.."}[5m]))
            /
            sum by (job) (rate(http_requests_total[5m]))
          ) > 0.05   # > 5% error rate
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High error rate on {{ $labels.job }}"
          description: "Error rate is {{ $value | humanizePercentage }} (threshold: 5%)"
          dashboard: "https://grafana.example.com/d/api-overview"

      # --- LATENCY (SLO) ---
      - alert: HighLatencyP99
        expr: |
          histogram_quantile(0.99,
            sum by (job, le) (rate(http_request_duration_seconds_bucket[5m]))
          ) > 2   # p99 > 2 seconds
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "P99 latency high: {{ $labels.job }}"
          description: "P99 latency is {{ $value | humanizeDuration }} (SLO: 2s)"

      # --- SATURATION ---
      - alert: HighMemoryUsage
        expr: |
          (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes)
          / node_memory_MemTotal_bytes * 100 > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage is {{ $value | humanize }}% on {{ $labels.instance }}"

      # --- DISK SPACE ---
      - alert: DiskSpaceLow
        expr: |
          (node_filesystem_avail_bytes{fstype!="tmpfs"}
          / node_filesystem_size_bytes{fstype!="tmpfs"} * 100) < 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Disk space low: {{ $labels.instance }}:{{ $labels.mountpoint }}"
          description: "Only {{ $value | humanize }}% disk space remaining"

      # --- PREDICT (disk full) ---
      - alert: DiskWillFillIn4Hours
        expr: |
          predict_linear(node_filesystem_free_bytes{fstype!="tmpfs"}[6h], 4*3600) < 0
        for: 30m
        labels:
          severity: critical
        annotations:
          summary: "Disk will fill in 4h: {{ $labels.instance }}:{{ $labels.mountpoint }}"

      # --- JVM ---
      - alert: JvmHeapUsageHigh
        expr: |
          (jvm_memory_used_bytes{area="heap"}
          / jvm_memory_max_bytes{area="heap"} * 100) > 85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "JVM heap usage high: {{ $labels.instance }}"
          description: "Heap usage: {{ $value | humanize }}%"

      # --- DEAD LETTER QUEUE ---
      - alert: MessageQueueDead
        expr: rabbitmq_queue_messages{queue=~".*dead.*"} > 10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Dead letter queue growing: {{ $labels.queue }}"

      # --- ABSENT (metric missing) ---
      - alert: MetricMissing
        expr: absent(up{job="payment-service"})
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "payment-service metrics are missing (job gone?)"
```

---

## How – Alertmanager Configuration

```yaml
# alertmanager.yml
global:
  resolve_timeout: 5m
  smtp_smarthost: "smtp.gmail.com:587"
  smtp_from: "alerts@example.com"
  smtp_auth_username: "alerts@example.com"
  smtp_auth_password: "xxxx"

# Templates
templates:
  - "/etc/alertmanager/templates/*.tmpl"

# Routing tree (từ trên xuống, first match wins)
route:
  receiver: default-receiver      # default
  group_by: ["alertname", "job", "severity"]
  group_wait: 30s                  # đợi nhóm thêm alerts trước khi gửi
  group_interval: 5m               # gửi update mỗi 5m nếu có thay đổi
  repeat_interval: 4h              # gửi lại mỗi 4h nếu chưa resolve

  routes:
    # Critical → PagerDuty ngay lập tức
    - matchers:
        - severity = "critical"
      receiver: pagerduty-critical
      group_wait: 10s
      repeat_interval: 1h

    # Warning → Slack
    - matchers:
        - severity = "warning"
      receiver: slack-warning
      group_wait: 1m

    # Platform team alerts
    - matchers:
        - team = "platform"
      receiver: slack-platform
      continue: true   # tiếp tục match route khác sau khi match route này

    # Database alerts → DBA team
    - matchers:
        - job =~ "postgres|mysql|redis"
      receiver: slack-dba

# Inhibition: khi critical fire, suppress warning của cùng instance
inhibit_rules:
  - source_matchers:
      - severity = "critical"
    target_matchers:
      - severity = "warning"
    equal: ["instance", "job"]  # chỉ inhibit nếu cùng instance + job

  # Khi instance down, suppress tất cả alerts khác của instance đó
  - source_matchers:
      - alertname = "InstanceDown"
    target_matchers:
      - alertname =~ ".+"
    equal: ["instance"]

receivers:
  - name: default-receiver
    slack_configs:
      - api_url: "https://hooks.slack.com/services/xxx"
        channel: "#alerts"
        title: "{{ .GroupLabels.alertname }}"
        text: "{{ range .Alerts }}{{ .Annotations.description }}\n{{ end }}"

  - name: pagerduty-critical
    pagerduty_configs:
      - routing_key: "xxx"
        description: "{{ .GroupLabels.alertname }}: {{ .Annotations.summary }}"
        severity: "critical"

  - name: slack-warning
    slack_configs:
      - api_url: "https://hooks.slack.com/services/yyy"
        channel: "#alerts-warning"
        color: '{{ if eq .Status "firing" }}warning{{ else }}good{{ end }}'
        title: "[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}"
        text: |
          *Summary:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          {{ if .Annotations.runbook_url }}*Runbook:* {{ .Annotations.runbook_url }}{{ end }}
          *Instances:* {{ range .Alerts }}{{ .Labels.instance }} {{ end }}

  - name: slack-dba
    slack_configs:
      - api_url: "https://hooks.slack.com/services/zzz"
        channel: "#dba-alerts"

  - name: slack-platform
    slack_configs:
      - api_url: "https://hooks.slack.com/services/www"
        channel: "#platform-alerts"
```

### Alertmanager Silencing (API)

```bash
# Tạo silence (maintenance window)
curl -X POST http://alertmanager:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {"name": "instance", "value": "web1", "isRegex": false},
      {"name": "severity", "value": "warning", "isRegex": false}
    ],
    "startsAt": "2026-05-06T02:00:00Z",
    "endsAt": "2026-05-06T04:00:00Z",
    "comment": "Maintenance window - web1 upgrade",
    "createdBy": "admin"
  }'

# List silences
curl http://alertmanager:9093/api/v2/silences | jq '.[] | {id, status, comment}'

# Delete silence
curl -X DELETE http://alertmanager:9093/api/v2/silence/{id}
```

---

## How – SLO-Based Alerting (Multi-Burn-Rate)

```yaml
# SLO: 99.9% availability (error budget = 0.1% = 43.2 min/month)
# Multi-burn-rate: phát hiện nhanh burn rate cao bất thường

groups:
  - name: slo_alerts
    rules:
      # Tính error ratio (recording rule để reuse)
      - record: job:slo_error_ratio:rate5m
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
          / sum(rate(http_requests_total[5m])) by (job)

      - record: job:slo_error_ratio:rate1h
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[1h])) by (job)
          / sum(rate(http_requests_total[1h])) by (job)

      - record: job:slo_error_ratio:rate6h
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[6h])) by (job)
          / sum(rate(http_requests_total[6h])) by (job)

      # Page immediately: burn rate > 14.4x → tiêu hết budget trong 1h
      - alert: SLOBurnRateFast
        expr: |
          job:slo_error_ratio:rate5m > (14.4 * 0.001)
          and job:slo_error_ratio:rate1h > (14.4 * 0.001)
        for: 2m
        labels:
          severity: critical
          slo: "availability_99.9"
        annotations:
          summary: "Fast SLO burn: {{ $labels.job }}"
          description: "Burning error budget at 14.4x rate. Budget exhausted in ~1h."

      # Page: burn rate > 6x → tiêu hết budget trong 6h
      - alert: SLOBurnRateMedium
        expr: |
          job:slo_error_ratio:rate5m > (6 * 0.001)
          and job:slo_error_ratio:rate6h > (6 * 0.001)
        for: 15m
        labels:
          severity: warning
          slo: "availability_99.9"
        annotations:
          summary: "Medium SLO burn: {{ $labels.job }}"
          description: "Burning error budget at 6x rate. Budget exhausted in ~6h."
```

---

## Trade-offs – Recording Rules

```
Ưu điểm:
✅ Dashboard load cực nhanh (query precomputed metric)
✅ Giảm CPU/Memory cho query engine
✅ Cho phép viết PromQL phức tạp mà không ảnh hưởng UX

Nhược điểm:
❌ Mất granularity (chỉ query ở resolution của recording rule)
❌ Thêm storage cho metrics mới
❌ Phải maintain thêm rule files
❌ Delay: recording rule có evaluation_interval delay
```

---

## Real-world

### Checklist Alert Quality

```
Mỗi alert cần:
□ Actionable: có người biết cần làm gì khi nhận
□ for: clause: tránh false positive do spike tạm thời
□ runbook_url: link tới hướng dẫn xử lý
□ severity label: routing đúng team/channel
□ Inhibition rules: tránh alert storm khi instance down
□ Test: amtool check-config alertmanager.yml
       promtool check rules rules/*.yml
```

### Validate Rules

```bash
# Check syntax
promtool check rules /etc/prometheus/rules/*.yml

# Test rules với unit tests
# rules/test_alerts.yml
rule_files:
  - alerts.yml

tests:
  - interval: 1m
    input_series:
      - series: 'http_requests_total{job="api", status="500"}'
        values: '0 0 0 0 0 10 20 30 40 50'  # sau 5m bắt đầu tăng
      - series: 'http_requests_total{job="api", status="200"}'
        values: '0 100 200 300 400 500 600 700 800 900'

    alert_rule_test:
      - eval_time: 10m
        alertname: HighErrorRate
        exp_alerts:
          - exp_labels:
              job: api
              severity: warning

promtool test rules rules/test_alerts.yml
```

---

## Ghi chú – Chủ đề tiếp theo
> `service_discovery.md`: Service Discovery (static, file, kubernetes, consul, ec2), Relabeling sâu, scrape config patterns

---

*Cập nhật lần cuối: 2026-05-06*
