# Prometheus Fundamentals – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Prometheus là gì?

**Prometheus** là open-source **monitoring system + time-series database (TSDB)** được viết bằng Go, ra đời tại SoundCloud (2012), hiện là CNCF graduated project. Prometheus **pull metrics** từ các targets theo định kỳ (scrape), lưu trữ dưới dạng time-series, và cung cấp ngôn ngữ query PromQL.

```
Nguyên tắc cốt lõi:
- Pull-based: Prometheus chủ động kéo metrics (không phải target push)
- Local TSDB: lưu trữ on-disk, hiệu quả cao
- Dimensional data model: metrics + labels (key-value pairs)
- No external dependency: standalone binary, tự đủ
```

---

## How – Data Model

### Time-Series

```
Metric name + Labels → unique time-series

ví dụ:
  http_requests_total{method="GET", status="200", job="api"}   1234  @timestamp
  http_requests_total{method="POST", status="500", job="api"}  56    @timestamp
  node_cpu_seconds_total{cpu="0", mode="idle", instance="web1"} 9999 @timestamp

Format: <metric_name>{<label_name>=<label_value>, ...} <value> [<timestamp>]
```

### Naming Convention

```
# Pattern: <namespace>_<subsystem>_<name>_<unit>
http_requests_total              # counter: total requests
http_request_duration_seconds    # histogram: request duration
node_memory_bytes_total          # gauge: memory total
process_cpu_seconds_total        # counter: CPU time

# Units: seconds, bytes, percent (0-1), total (suffix)
# Suffix theo type:
#   Counter   → _total
#   Gauge     → không suffix
#   Histogram → _bucket, _count, _sum
#   Summary   → _count, _sum, quantile label
```

### 4 Metric Types

```go
// 1. COUNTER – chỉ tăng (hoặc reset về 0 khi restart)
// Dùng cho: requests, errors, bytes sent
var requestsTotal = prometheus.NewCounterVec(
    prometheus.CounterOpts{
        Name: "http_requests_total",
        Help: "Total HTTP requests",
    },
    []string{"method", "status"},
)

// 2. GAUGE – có thể tăng hoặc giảm
// Dùng cho: current connections, memory usage, queue size
var queueSize = prometheus.NewGaugeVec(
    prometheus.GaugeOpts{
        Name: "queue_size",
        Help: "Current queue size",
    },
    []string{"queue_name"},
)

// 3. HISTOGRAM – phân phối giá trị vào các buckets
// Dùng cho: request duration, response size
// Tự động tạo: _bucket, _count, _sum
var requestDuration = prometheus.NewHistogramVec(
    prometheus.HistogramOpts{
        Name:    "http_request_duration_seconds",
        Help:    "HTTP request duration",
        Buckets: []float64{0.001, 0.01, 0.05, 0.1, 0.5, 1, 5},
    },
    []string{"method", "handler"},
)

// 4. SUMMARY – tính quantiles phía client (không aggregate được)
// Chỉ dùng khi cần accurate quantiles trên 1 instance
var requestSummary = prometheus.NewSummaryVec(
    prometheus.SummaryOpts{
        Name: "rpc_duration_seconds",
        Objectives: map[float64]float64{
            0.5: 0.05, 0.9: 0.01, 0.99: 0.001,
        },
    },
    []string{"service"},
)
```

---

## How – Kiến Trúc & Scraping

### Prometheus Server

```
prometheus.yml (config)
    ↓
Scrape Manager
    ├── HTTP GET /metrics → Target 1 (app:8080/metrics)
    ├── HTTP GET /metrics → Target 2 (node-exporter:9100/metrics)
    └── HTTP GET /metrics → Target 3 (cadvisor:8080/metrics)
    ↓
TSDB (local disk: /prometheus/data/)
    ├── WAL (Write-Ahead Log): buffer 2h in memory
    ├── Chunks: 2h blocks
    └── Compaction: merge old blocks
    ↓
Query Engine (PromQL)
    ↓
HTTP API (:9090/api/v1/query)
    ↓
Alertmanager (push alerts when rule fires)
```

### prometheus.yml

```yaml
global:
  scrape_interval: 15s          # default scrape mỗi 15s
  evaluation_interval: 15s      # evaluate rules mỗi 15s
  scrape_timeout: 10s
  external_labels:               # gắn vào tất cả metrics (cho federation)
    cluster: production
    region: ap-southeast-1

# Alertmanager config
alerting:
  alertmanagers:
    - static_configs:
        - targets: ["alertmanager:9093"]
      timeout: 10s

# Rule files
rule_files:
  - "rules/*.yml"

# Scrape configs
scrape_configs:
  # Scrape chính Prometheus
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  # Scrape Node Exporter
  - job_name: node
    static_configs:
      - targets:
          - "node1:9100"
          - "node2:9100"
    relabel_configs:
      - source_labels: [__address__]
        target_label: instance
        regex: "(.+):.*"
        replacement: "$1"

  # Scrape Kubernetes pods (via kubernetes_sd)
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      # Chỉ scrape pods có annotation prometheus.io/scrape=true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"
      # Dùng port từ annotation prometheus.io/port
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: "([^:]+)(?::\\d+)?;(\\d+)"
        replacement: "$1:$2"
        target_label: __address__
      # Copy pod labels
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
```

---

## How – PromQL Cơ Bản

### Selector & Matcher

```promql
# Exact match
http_requests_total{job="api", status="200"}

# Regex match
http_requests_total{status=~"2.."}      # 200, 201, 204...
http_requests_total{status!~"4..|5.."}  # không phải 4xx, 5xx

# Không có label (wildcard)
http_requests_total{}                   # tất cả series

# Range vector (time window)
http_requests_total[5m]                 # 5 phút gần nhất
```

### Các Hàm Quan Trọng

```promql
# rate(): tốc độ thay đổi counter / giây (dùng với counter)
rate(http_requests_total[5m])           # avg req/s trong 5m

# irate(): tốc độ tức thời (2 data points cuối)
irate(http_requests_total[5m])          # spike detection

# increase(): tổng tăng trong khoảng thời gian
increase(http_requests_total[1h])       # tổng requests trong 1h

# sum(), avg(), max(), min(), count()
sum(rate(http_requests_total[5m])) by (job)    # tổng req/s theo job
avg(node_memory_MemAvailable_bytes) by (instance)

# topk(), bottomk()
topk(5, rate(http_requests_total[5m]))  # top 5 endpoints by req/s

# histogram_quantile(): p99 latency từ histogram
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# predict_linear(): dự báo giá trị tương lai
predict_linear(node_filesystem_free_bytes[6h], 24*3600)  # disk free sau 24h

# absent(): cảnh báo khi metric biến mất
absent(up{job="api"})  # fire khi không có instance api nào

# label_replace(): thêm/sửa label
label_replace(metric, "new_label", "$1", "existing_label", "(.+)-(.+)")
```

### Aggregation Operators

```promql
# without: aggregation bỏ các label chỉ định
sum without (instance) (http_requests_total)

# by: chỉ giữ các label chỉ định
sum by (job, status) (http_requests_total)

# Binary operations
# rate error / rate total = error ratio
rate(http_requests_total{status=~"5.."}[5m])
/
rate(http_requests_total[5m])

# Join 2 metrics khác nhau (matching labels)
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
```

---

## Components – Ecosystem

```
Prometheus Core:
├── prometheus-server          → main server, TSDB, scrape, PromQL
├── alertmanager               → nhận alerts, routing, dedup, throttle, notify
├── pushgateway                → dành cho batch jobs (push thay vì pull)
└── prometheus-operator        → CRD-based management trong K8s

Exporters (chuyển đổi metrics sang format Prometheus):
├── node-exporter              → OS/hardware metrics (CPU, RAM, disk, network)
├── cadvisor                   → container metrics (Docker/containerd)
├── blackbox-exporter          → probe HTTP/TCP/ICMP endpoints
├── mysqld-exporter            → MySQL metrics
├── postgres-exporter          → PostgreSQL metrics
├── redis-exporter             → Redis metrics
├── kafka-exporter             → Kafka consumer lag, topic metrics
├── jmx-exporter               → JVM/Java metrics via JMX
└── custom exporter            → viết bằng Go/Python/Java SDK

Client Libraries:
├── Go:     github.com/prometheus/client_golang
├── Java:   io.micrometer (Spring Boot tự tích hợp)
├── Python: prometheus-client
└── Node:   prom-client
```

---

## Why – Tại Sao Dùng Prometheus?

```
1. Pull-based model:
   - Đơn giản hóa service discovery
   - Dễ phát hiện target down (scrape fail)
   - Không cần firewall inbound rule cho target

2. Dimensional data model:
   - Filter, aggregate linh hoạt qua labels
   - 1 metrics_name + nhiều label = nhiều series

3. Local TSDB hiệu quả:
   - 1-2 bytes/sample sau compression
   - 10M+ series trên 1 server thông thường

4. Ecosystem phong phú:
   - 100+ exporters sẵn có
   - Native K8s integration (Prometheus Operator)
   - Grafana support native

5. CNCF graduated:
   - Battle-tested tại Uber, Airbnb, GitLab, SoundCloud
   - Community lớn, tài liệu đầy đủ
```

---

## When – Khi Nào Dùng?

```
✅ Dùng Prometheus khi:
- Microservices / containers / K8s
- Cần dimensional metrics với labels
- Monitoring infrastructure + applications
- Scrape interval 15-60s là đủ
- Budget thấp (self-hosted, free)

❌ Không phù hợp khi:
- Cần sub-second precision (high-frequency trading)
- Long-term storage > 1 năm (cần Thanos/Cortex/VictoriaMetrics)
- Event logging (dùng ELK/Loki thay thế)
- Distributed tracing (dùng Jaeger/Tempo)
```

---

## Compare – Prometheus vs các giải pháp khác

| Feature | Prometheus | InfluxDB | Datadog | VictoriaMetrics |
|---------|-----------|----------|---------|-----------------|
| Model | Pull | Push/Pull | Agent | Pull |
| Storage | Local TSDB | Time-series DB | SaaS | Local/Cluster |
| Query | PromQL | Flux/InfluxQL | DQL | MetricsQL (PromQL superset) |
| HA | Federation/Thanos | Enterprise | SaaS | Native cluster |
| Cost | Free | Free/Enterprise | $$$$ | Free |
| K8s native | Yes (Operator) | No | Yes (Agent) | Yes |
| Long-term | No (need addon) | Yes | Yes | Yes |
| Cardinality | ~10M series | High | High | Very high |

---

## Trade-offs

```
Ưu điểm:
✅ Đơn giản, dễ cài, không dependency
✅ PromQL rất mạnh cho time-series analysis
✅ Pull model: dễ debug, target tự document
✅ Low overhead (Go binary ~70MB RAM)
✅ K8s native với Prometheus Operator

Nhược điểm:
❌ Pull model: không phù hợp cho short-lived jobs (dùng Pushgateway)
❌ Local TSDB: không horizontal scale natively
❌ Retention ngắn (default 15 days)
❌ No built-in HA: cần Thanos/Cortex cho HA
❌ High cardinality labels gây OOM (ví dụ: user_id, request_id làm label)
❌ Không có long-term storage native
```

---

## Real-world Usage

### Instrumentation Spring Boot

```java
// Spring Boot + Micrometer tự động expose /actuator/prometheus
// application.yml:
management:
  endpoints:
    web:
      exposure:
        include: health, info, prometheus
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${spring.profiles.active:default}

// Custom metrics trong Spring:
@Service
public class OrderService {
    private final Counter orderCounter;
    private final Timer orderTimer;
    private final Gauge pendingOrders;

    public OrderService(MeterRegistry registry) {
        this.orderCounter = Counter.builder("orders.created.total")
            .description("Total orders created")
            .tag("type", "all")
            .register(registry);

        this.orderTimer = Timer.builder("orders.processing.duration")
            .description("Order processing duration")
            .publishPercentiles(0.5, 0.95, 0.99)
            .register(registry);

        this.pendingOrders = Gauge.builder("orders.pending", this,
            OrderService::getPendingOrderCount)
            .register(registry);
    }

    public Order createOrder(OrderRequest req) {
        return orderTimer.record(() -> {
            orderCounter.increment();
            return processOrder(req);
        });
    }
}
```

### Docker Compose Setup

```yaml
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:v2.48.0
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - ./rules:/etc/prometheus/rules
      - prometheus_data:/prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=30d
      - --storage.tsdb.retention.size=50GB
      - --web.enable-lifecycle            # hot reload: curl -XPOST /-/reload
      - --web.enable-admin-api
    ports:
      - "9090:9090"
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.7.0
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - --path.procfs=/host/proc
      - --path.rootfs=/rootfs
      - --path.sysfs=/host/sys
      - --collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)
    network_mode: host

  alertmanager:
    image: prom/alertmanager:v0.26.0
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
    ports:
      - "9093:9093"

volumes:
  prometheus_data:
```

### TSDB Management

```bash
# Xem storage stats
curl localhost:9090/api/v1/status/tsdb

# Hot reload config (không cần restart)
curl -X POST localhost:9090/-/reload

# Check targets
curl localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Query qua API
curl 'localhost:9090/api/v1/query?query=up' | jq '.data.result'

# Range query
curl 'localhost:9090/api/v1/query_range?query=rate(http_requests_total[5m])&start=2026-05-06T00:00:00Z&end=2026-05-06T01:00:00Z&step=60s'

# Xóa series (admin API)
curl -X POST -g 'localhost:9090/api/v1/admin/tsdb/delete_series?match[]=old_metric{job="legacy"}'
```

---

## Ghi chú – Chủ đề tiếp theo
> `prometheus_advanced.md`: PromQL nâng cao, Recording Rules, Alerting Rules, Inhibition/Silencing trong Alertmanager

---

*Cập nhật lần cuối: 2026-05-06*
