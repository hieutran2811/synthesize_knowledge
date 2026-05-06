# Full Observability Stack – Prometheus + Grafana + Loki + Tempo + OTel

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Full Observability Stack là gì?

**Three Pillars of Observability:**

```
Metrics  → Prometheus → "Hệ thống có đang healthy không?"
Logs     → Loki       → "Chuyện gì đã xảy ra?"
Traces   → Tempo      → "Tại sao request này chậm?"

Kết hợp qua Grafana:
  Dashboard (Metrics) → thấy spike error
  → click "View Logs" → xem logs của error đó
  → click TraceID → xem trace của request fail
  → xem span breakdown → tìm bottleneck
```

```
App/Service
    ↓ instrument với OpenTelemetry SDK
    ├── Metrics → Prometheus (scrape /metrics)
    ├── Logs    → Loki (via Promtail/Alloy)
    └── Traces  → Tempo (via OTLP)

Grafana (single pane):
  ├── Explore: Metrics + Logs + Traces
  ├── Correlations: Metric → Log → Trace
  └── Dashboards
```

---

## Components – Loki

### What – Loki là gì?

**Loki** là log aggregation system của Grafana Labs, được thiết kế như "Prometheus nhưng cho logs". Không index nội dung log (chỉ index labels) → **rẻ hơn Elasticsearch 10x**.

```
Architecture:
  App → Promtail/Alloy (log agent) → Loki → Grafana

Loki components:
  Distributor → Ingester (write path)
  Querier     → Ruler   (read path)
  Compactor   → object storage
```

### Loki Stack (Docker Compose)

```yaml
services:
  loki:
    image: grafana/loki:2.9.0
    ports:
      - "3100:3100"
    volumes:
      - loki_data:/loki
      - ./loki-config.yml:/etc/loki/local-config.yaml
    command: -config.file=/etc/loki/local-config.yaml

  promtail:
    image: grafana/promtail:2.9.0
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - ./promtail-config.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml
```

### loki-config.yml

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 1h
  max_chunk_age: 1h
  chunk_target_size: 1048576
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/boltdb-shipper-active
    cache_location: /loki/boltdb-shipper-cache
    cache_ttl: 24h
    shared_store: filesystem
  filesystem:
    directory: /loki/chunks

compactor:
  working_directory: /loki/boltdb-shipper-compactor
  shared_store: filesystem

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  max_query_length: 0h      # no limit

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 744h   # 31 days
```

### Promtail Config

```yaml
# promtail-config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml   # track file positions

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  # Docker containers logs
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: [__meta_docker_container_name]
        target_label: container
      - source_labels: [__meta_docker_container_label_com_docker_compose_service]
        target_label: service
      - source_labels: [__meta_docker_container_log_stream]
        target_label: stream

  # Kubernetes pods logs (khi dùng K8s)
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    pipeline_stages:
      # Parse JSON logs
      - json:
          expressions:
            timestamp: time
            level: level
            message: message
            traceId: traceId
            spanId: spanId
      # Extract log level
      - labels:
          level:
      # Extract traceId (cho Loki → Tempo correlation)
      - output:
          source: message
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        target_label: app
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
```

### LogQL (Loki Query Language)

```logql
# Cơ bản: filter by labels
{app="api", namespace="production"}

# Filter log content
{app="api"} |= "ERROR"          # contains
{app="api"} != "health"          # not contains
{app="api"} |~ "error|exception" # regex

# Parse JSON logs
{app="api"}
  | json
  | level="ERROR"
  | line_format "{{.message}}"

# Metrics từ logs (log rate)
rate({app="api"} |= "ERROR" [5m])

# Count errors per minute
count_over_time({app="api"} |= "ERROR" [1m])

# Quantile từ log duration field
{app="api"}
  | json
  | unwrap duration_ms
  | quantile_over_time(0.99, [5m])

# Top N patterns (log clustering)
topk(10, sum by (message) (count_over_time({app="api"} |= "ERROR" [1h])))
```

---

## Components – Tempo (Distributed Tracing)

### What – Tempo là gì?

**Tempo** là distributed tracing backend của Grafana Labs. Chỉ lưu traces (không index) → rất rẻ. Tích hợp native với Grafana.

```yaml
# tempo-config.yml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        http:
          endpoint: "0.0.0.0:4318"
        grpc:
          endpoint: "0.0.0.0:4317"
    jaeger:
      protocols:
        thrift_http:
          endpoint: "0.0.0.0:14268"
    zipkin:

ingester:
  max_block_duration: 5m

storage:
  trace:
    backend: local
    wal:
      path: /tmp/tempo/wal
    local:
      path: /tmp/tempo/blocks

compactor:
  compaction:
    compaction_window: 1h
    max_block_bytes: 100_000_000
    block_retention: 1h
    compacted_block_retention: 10m

querier:
  max_concurrent_queries: 20
  trace_by_id:
    query_timeout: 10s
  tags:
    query_timeout: 30s
```

---

## Components – OpenTelemetry (OTel)

### What – OpenTelemetry là gì?

**OpenTelemetry** là CNCF project cung cấp **vendor-neutral instrumentation** cho metrics, logs, traces. Một SDK, nhiều backends.

```
OTel Components:
  API     → interface cho instrumentation (stable)
  SDK     → implementation (batching, sampling, export)
  Collector → standalone agent/gateway (nhận, process, export)

Benefits:
  - Viết instrumentation 1 lần, export đến Prometheus/Datadog/Jaeger/Tempo
  - Auto-instrumentation cho Java, Node, Python (zero code change)
  - W3C TraceContext standard → cross-language, cross-service
```

### Spring Boot + OTel Auto-instrumentation

```yaml
# K8s: inject OTel Java agent via init container
spec:
  initContainers:
    - name: otel-agent
      image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:1.32.0
      command: ["cp", "/javaagent.jar", "/otel/javaagent.jar"]
      volumeMounts:
        - name: otel-agent
          mountPath: /otel

  containers:
    - name: api
      image: myapi:latest
      env:
        - name: JAVA_TOOL_OPTIONS
          value: "-javaagent:/otel/javaagent.jar"
        - name: OTEL_SERVICE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.labels['app']
        - name: OTEL_EXPORTER_OTLP_ENDPOINT
          value: "http://otel-collector:4317"
        - name: OTEL_EXPORTER_OTLP_PROTOCOL
          value: "grpc"
        # Metrics vẫn qua Prometheus
        - name: OTEL_METRICS_EXPORTER
          value: "prometheus"
        # Logs via OTLP
        - name: OTEL_LOGS_EXPORTER
          value: "otlp"
        # Traces via OTLP
        - name: OTEL_TRACES_EXPORTER
          value: "otlp"
        # Sampling (head-based, 10% trong production)
        - name: OTEL_TRACES_SAMPLER
          value: "parentbased_traceidratio"
        - name: OTEL_TRACES_SAMPLER_ARG
          value: "0.1"

  volumes:
    - name: otel-agent
      emptyDir: {}
```

### OTel Collector (Gateway)

```yaml
# otel-collector-config.yml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"
      http:
        endpoint: "0.0.0.0:4318"
  prometheus:
    config:
      scrape_configs:
        - job_name: "otel-collector"
          static_configs:
            - targets: ["localhost:8888"]

processors:
  batch:
    timeout: 5s
    send_batch_size: 1024
  memory_limiter:
    limit_mib: 512
  resource:
    attributes:
      - key: environment
        value: production
        action: upsert
  # Sampling: chỉ giữ traces với error hoặc slow
  probabilistic_sampler:
    sampling_percentage: 10
  filter/drop_health:
    spans:
      exclude:
        match_type: strict
        attributes:
          - key: http.target
            value: "/health"

exporters:
  # Traces → Tempo
  otlp/tempo:
    endpoint: "tempo:4317"
    tls:
      insecure: true
  # Metrics → Prometheus
  prometheus:
    endpoint: "0.0.0.0:8889"
  # Logs → Loki
  loki:
    endpoint: "http://loki:3100/loki/api/v1/push"
    labels:
      resource:
        service.name: "service_name"
        k8s.namespace.name: "namespace"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, filter/drop_health, probabilistic_sampler]
      exporters: [otlp/tempo]
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, batch]
      exporters: [prometheus]
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch, resource]
      exporters: [loki]
```

---

## How – Correlation (Metrics → Logs → Traces)

### Exemplars (Metric → Trace)

```java
// Prometheus histogram với exemplar (Java Micrometer)
// Exemplar: sample data point kèm theo TraceID

// Spring Boot + OTel tự động add exemplars
// Prometheus config: --enable-feature=exemplar-storage

// PromQL: query with exemplars
// Grafana: Time series panel → "Include exemplars"
// Click data point → "View Trace" → mở Tempo
```

### Loki → Tempo (Log → Trace)

```yaml
# Grafana data source: Loki config
# Derived fields: extract traceId từ log line → link to Tempo
jsonData:
  derivedFields:
    - name: TraceID
      matcherRegex: '"traceId":"(\w+)"'
      url: "$${__value.raw}"
      datasourceUid: Tempo
      urlDisplayLabel: "View Trace"
```

### Grafana Correlations (Grafana 9.4+)

```
Settings → Correlations → Create correlation

From: Prometheus
To:   Loki
Label: "View Logs"
Config:
  Query: {app="${labels.job}", namespace="${labels.namespace}"}
  Type: query
```

---

## How – Full Stack Docker Compose

```yaml
version: '3.8'
services:
  # Prometheus
  prometheus:
    image: prom/prometheus:v2.48.0
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.retention.time=15d
      - --enable-feature=exemplar-storage   # exemplars
    ports: ["9090:9090"]

  # Loki
  loki:
    image: grafana/loki:2.9.0
    ports: ["3100:3100"]
    volumes:
      - loki_data:/loki

  # Promtail
  promtail:
    image: grafana/promtail:2.9.0
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro

  # Tempo
  tempo:
    image: grafana/tempo:2.3.0
    ports:
      - "3200:3200"   # Tempo HTTP
      - "4317:4317"   # OTLP gRPC
      - "4318:4318"   # OTLP HTTP
    volumes:
      - tempo_data:/tmp/tempo

  # OTel Collector
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.89.0
    volumes:
      - ./otel-collector-config.yml:/etc/otel-collector-config.yml
    command: ["--config=/etc/otel-collector-config.yml"]
    ports:
      - "4317:4317"  # OTLP gRPC
      - "4318:4318"  # OTLP HTTP

  # Grafana
  grafana:
    image: grafana/grafana:10.2.0
    ports: ["3000:3000"]
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning
      - grafana_data:/var/lib/grafana

  # Node Exporter
  node-exporter:
    image: prom/node-exporter:v1.7.0
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
    network_mode: host

  # Alertmanager
  alertmanager:
    image: prom/alertmanager:v0.26.0
    ports: ["9093:9093"]
    volumes:
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml

volumes:
  prometheus_data:
  loki_data:
  tempo_data:
  grafana_data:
```

---

## Compare – Observability Stacks

| | PLG (Prometheus+Loki+Grafana) | ELK/EFK | Datadog | Grafana Cloud |
|--|-------------------------------|---------|---------|---------------|
| Cost | Free | Free/Enterprise | $$$$ | Free tier + $$ |
| Metrics | Prometheus | Beats/Metricbeat | Agent | Mimir (Prometheus) |
| Logs | Loki (cheap) | Elasticsearch (expensive) | Agent | Loki |
| Traces | Tempo | APM | Yes | Tempo |
| Unified UI | Grafana | Kibana | Datadog | Grafana |
| Setup effort | Medium | Hard | Easy | Very Easy |
| Ops overhead | Medium | High | None | None |
| K8s native | Excellent | Good | Good | Excellent |
| Log indexing | Labels only (fast/cheap) | Full text (slow/expensive) | Full | Labels |
| Scale | Thanos/Mimir for HA | Enterprise cluster | Auto | Auto |

---

## Trade-offs

```
PLG Stack (self-hosted):
✅ Full control, data on-premises
✅ Very cost effective (Loki 10x cheaper than ELK)
✅ Vendor-neutral (OTel)
✅ Native Grafana integration
❌ Phải manage infrastructure
❌ HA phức tạp (Thanos, Loki distributed mode)
❌ Learning curve cho mỗi component

Datadog/New Relic:
✅ Zero ops, full managed
✅ Auto-instrumentation
✅ Advanced ML anomaly detection
❌ Very expensive (can be $50k+/month for large scale)
❌ Vendor lock-in
❌ Data out of your control

ELK:
✅ Powerful full-text search
✅ Machine learning (X-Pack)
❌ High resource usage (Elasticsearch hungry)
❌ Complex to scale
❌ Expensive license cho enterprise features
```

---

## Real-world – K8s Observability Stack

```
Recommended stack cho K8s production:

Metrics:   kube-prometheus-stack (Prometheus Operator + Grafana + Alertmanager)
           + Thanos (long-term) hoặc Grafana Mimir

Logs:      Grafana Loki + Promtail DaemonSet
           (thay thế: FluentBit → Loki)

Traces:    Grafana Tempo
           + OTel Operator (auto-instrumentation)

Install via Helm:
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
  helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace \
    -f values-kube-prometheus.yaml

  helm repo add grafana https://grafana.github.io/helm-charts
  helm install loki grafana/loki-stack -n monitoring \
    --set grafana.enabled=false \
    --set prometheus.enabled=false

  helm install tempo grafana/tempo -n monitoring

Mục tiêu MTTD (Mean Time To Detect):
  - Metric-based alerts: < 5 phút
  - Log-based errors: real-time
  - Trace-based: per-request, on-demand

Dashboard structure:
  1. Cluster Overview (infra)
  2. Namespace Overview (per team)
  3. Service Overview (per service)
  4. Debugging (logs + traces)
```

---

## Ghi chú – Tổng Kết

Đã hoàn thành toàn bộ 10 sub-topics về Prometheus & Grafana:

```
Prometheus:  prometheus_fundamentals → prometheus_advanced
             → service_discovery → prometheus_production (Thanos)

Grafana:     grafana_fundamentals → grafana_advanced
             → grafana_production

Observability: metrics_design → alerting_strategy → stack_integration

Chủ đề tiếp theo (nếu muốn mở rộng):
  - Grafana Mimir (Prometheus-as-a-Service)
  - OpenTelemetry deep dive
  - eBPF-based monitoring (Cilium, Tetragon, Pyroscope)
  - Continuous Profiling (Pyroscope/Parca)
  - Chaos Engineering + SLO verification
```

---

*Cập nhật lần cuối: 2026-05-06*
