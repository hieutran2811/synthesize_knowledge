# Metrics Design – RED, USE & 4 Golden Signals

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Metrics Design là gì?

**Metrics Design** là nghệ thuật chọn **đúng metrics** để monitor hệ thống. Không phải cứ collect nhiều metrics là tốt. Các methodology giúp tập trung vào những gì quan trọng nhất cho reliability và user experience.

```
Anti-patterns:
- Monitor quá nhiều, không biết metric nào quan trọng
- Alert trên infrastructure metrics, miss user-facing impact
- High cardinality labels → OOM Prometheus
- Counter vs Gauge nhầm lẫn
- Không có naming convention → dashboard chaos
```

---

## How – 4 Golden Signals (Google SRE)

Theo Google SRE Book: **4 signals đủ để biết hệ thống có vấn đề không**.

```
1. LATENCY    – Thời gian xử lý request (distinguish success vs error latency)
2. TRAFFIC    – Lưu lượng (req/s, messages/s, transactions/s)
3. ERRORS     – Tỷ lệ lỗi (explicit 5xx, implicit timeout, wrong response)
4. SATURATION – Mức độ "đầy" của hệ thống (CPU%, memory%, queue depth)
```

### PromQL cho 4 Golden Signals

```promql
# 1. LATENCY – p50, p95, p99
histogram_quantile(0.50, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.95, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m])))
histogram_quantile(0.99, sum by (job, le) (rate(http_request_duration_seconds_bucket[5m])))

# QUAN TRỌNG: track error latency separately
histogram_quantile(0.99,
  sum by (le) (rate(http_request_duration_seconds_bucket{status=~"5.."}[5m]))
)

# 2. TRAFFIC – req/s
sum(rate(http_requests_total[5m])) by (job)

# 3. ERRORS – error ratio
sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
/
sum(rate(http_requests_total[5m])) by (job)

# Absolute error count
sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)

# 4. SATURATION
# CPU
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)

# Memory
1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Disk I/O utilization
rate(node_disk_io_time_seconds_total[5m])

# Network saturation (approaching bandwidth)
rate(node_network_transmit_bytes_total[5m]) / node_network_speed_bytes
```

---

## How – RED Method (Tom Wilkie, Weave Works)

RED tập trung vào **service-level** (không phải infrastructure):

```
R – Rate:    số requests/second đang được xử lý
E – Errors:  số requests/second đang bị fail
D – Duration: lượng thời gian mỗi request mất
```

```promql
# Dùng cho: microservices, HTTP APIs, gRPC services, Kafka consumers

# Rate
sum(rate(http_requests_total[5m])) by (service, method)

# Errors (rate)
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)

# Duration (p99)
histogram_quantile(0.99,
  sum by (service, le) (rate(http_request_duration_seconds_bucket[5m]))
)
```

---

## How – USE Method (Brendan Gregg)

USE tập trung vào **resource-level** (hardware/OS):

```
U – Utilization: % thời gian resource đang bận
S – Saturation:  lượng work đang queue (bị trì hoãn)
E – Errors:      error events của resource
```

```promql
# CPU
U: avg(rate(node_cpu_seconds_total{mode!="idle"}[5m])) by (instance)
S: node_load1 / count without (cpu,mode)(node_cpu_seconds_total{mode="idle"})  # normalized load
E: rate(node_cpu_seconds_total{mode="steal"}[5m])  # CPU steal (VM)

# Memory
U: 1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes
S: node_vmstat_pgscan_kswapd  # kswapd activity = memory pressure
E: node_vmstat_oom_kill

# Disk
U: rate(node_disk_io_time_seconds_total[5m])             # % time busy
S: rate(node_disk_io_time_weighted_seconds_total[5m])    # avg queue length
E: rate(node_disk_read_errors_total[5m]) + rate(node_disk_write_errors_total[5m])

# Network
U: rate(node_network_transmit_bytes_total[5m]) / node_network_speed_bytes
S: node_sockstat_TCP_tw  # TIME_WAIT sockets = saturation
E: rate(node_network_transmit_errs_total[5m])
```

---

## How – Instrumentation Best Practices

### Naming Convention

```
<namespace>_<subsystem>_<name>_<unit>_<suffix>

namespace:  tên app/team (orders, payments, auth)
subsystem:  component con (db, cache, http, grpc)
name:       mô tả hành động (requests, errors, duration)
unit:       đơn vị SI (seconds, bytes, total)
suffix:     _total (counter), _bucket/_count/_sum (histogram)

Ví dụ:
  orders_http_requests_total                  ✅
  orders_db_query_duration_seconds_bucket     ✅
  payments_kafka_consumer_lag_messages        ✅
  auth_cache_hit_ratio                        ✅

  request_count                               ❌ (thiếu namespace)
  http_req_dur                                ❌ (viết tắt, thiếu unit)
  total_errors                                ❌ (thiếu context)
```

### Label Design

```python
# Labels tốt: low cardinality, high selectivity
http_requests_total{
    method="GET",         # ~5 values: GET/POST/PUT/DELETE/PATCH
    status="200",         # ~10 values: 200/201/400/401/403/404/500/503...
    service="api",        # ~20 services
    endpoint="/users"     # ~50-100 endpoints (cẩn thận!)
}

# Labels nguy hiểm: HIGH CARDINALITY → OOM
http_requests_total{
    user_id="12345",      # ❌ millions of unique values
    request_id="abc-123", # ❌ unique per request
    ip="1.2.3.4",         # ❌ millions of IPs
    trace_id="xxx"        # ❌ unique per trace
}

# Rule: tổng số time-series = product của cardinality các labels
# 5 methods × 10 statuses × 20 services × 100 endpoints = 100,000 series → OK
# 5 × 10 × 20 × 1,000,000 (user_ids) = 1 tỷ series → CRASH
```

### Histogram Buckets

```go
// Buckets phải bao phủ range expected values
// Mặc định của Prometheus quá coarse-grained

// Web API (ms range)
prometheus.DefBuckets  // [.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10] (seconds)

// Database queries (fast)
Buckets: []float64{0.001, 0.002, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1}

// Background jobs (slow)
Buckets: []float64{0.1, 0.5, 1, 2, 5, 10, 30, 60, 120}

// File sizes
Buckets: prometheus.ExponentialBuckets(1024, 2, 12)  // 1KB, 2KB, 4KB, ... 2MB

// Rule: target p99 nằm trong 1 bucket, có 4-8 buckets nhỏ hơn target
// Nếu SLO = 200ms, cần buckets: ..., 0.1, 0.2, 0.5, ...
```

---

## How – Business Metrics vs Technical Metrics

```
Technical metrics (thấp, dễ collect):
  - CPU%, memory%, latency, error rate
  - Cần thiết nhưng không đủ

Business metrics (cao, khó collect nhưng quan trọng):
  - Orders per minute
  - Revenue per minute
  - Successful payment rate
  - User registration rate
  - Search result click-through rate
  - Cart abandonment rate

Kết hợp:
  Business metric drop → trace qua technical metrics tìm root cause
  Technical alert → estimate business impact

Ví dụ correlation:
  payment_success_rate thấp
    → payment_api_error_rate cao
    → payment_db_query_duration_p99 cao
    → node_disk_io_time > 95%
    → ROOT CAUSE: disk I/O saturation
```

---

## How – SLI/SLO/SLA Metrics

```
SLI (Service Level Indicator): metric đo lường reliability
SLO (Service Level Objective): target của SLI
SLA (Service Level Agreement): contract với user (penalties)

Ví dụ:
  SLI: tỷ lệ requests thành công trong 5 phút
  SLO: SLI > 99.9% trong rolling 30d
  SLA: refund 10% nếu SLO không đạt
```

```promql
# SLI: availability (request success ratio)
# Tốt hơn: đặt ngưỡng (request < 2s = "good", còn lại = "bad")
sum(rate(http_requests_total{status!~"5.."}[5m]))
/
sum(rate(http_requests_total[5m]))

# SLI: latency (tỷ lệ requests dưới SLO threshold)
sum(rate(http_request_duration_seconds_bucket{le="0.2"}[5m]))
/
sum(rate(http_request_duration_seconds_count[5m]))

# Error budget remaining (%)
# SLO = 99.9%, window = 30d
# Error budget = 100% - 99.9% = 0.1% = 43.2 phút/tháng
(
  1 - (
    sum(increase(http_requests_total{status=~"5.."}[30d]))
    /
    sum(increase(http_requests_total[30d]))
  )
) / (1 - 0.999)  # 1 = 100% budget, < 0 = exceeded

# Burn rate (xem prometheus_advanced.md cho chi tiết)
```

---

## Compare – RED vs USE vs 4 Golden Signals

| | 4 Golden Signals | RED | USE |
|--|-----------------|-----|-----|
| Tập trung | Service + Infra | Service | Resource |
| Audience | SRE/Ops | Dev/SRE | Ops/SysAdmin |
| Dùng cho | Tổng quan hệ thống | Microservices | Infrastructure |
| Latency tracking | Yes | Yes (Duration) | No |
| User impact | Direct | Direct | Indirect |
| Resource tracking | Saturation | No | Full |

**Khuyến nghị:** Dùng tất cả 3:
- 4 Golden Signals: dashboard overview toàn hệ thống
- RED: per-service dashboards
- USE: infrastructure dashboards

---

## Trade-offs

```
Instrumentation nhiều:
✅ Debug nhanh hơn khi có incident
✅ Capacity planning chính xác
❌ Storage cost tăng
❌ Developer overhead (viết code instrumentation)
❌ High cardinality risk

Instrumentation ít:
✅ Simple, ít cost
✅ Không risk OOM
❌ Blind spots khi incident xảy ra
❌ MTTR (Mean Time to Recover) cao hơn
```

---

## Real-world – Dashboard Design Template

```
Mỗi service nên có 3 dashboard levels:

1. Overview Dashboard (cho mọi người):
   - 4 panels: Traffic, Errors, Latency p99, Saturation
   - Time range: last 1h với 30s refresh
   - Annotations: deployments

2. Service Detail Dashboard (cho engineers):
   - RED per endpoint
   - JVM metrics (heap, GC, threads)
   - DB connection pool
   - External dependencies latency
   - Business metrics

3. Debugging Dashboard (cho on-call):
   - Logs (Loki)
   - Traces (Tempo)
   - Raw metrics với high resolution
   - Comparison: current vs 1 week ago
```

---

## Ghi chú – Chủ đề tiếp theo
> `alerting_strategy.md`: Alert design principles, noise reduction, SLO-based alerting, on-call practices

---

*Cập nhật lần cuối: 2026-05-06*
