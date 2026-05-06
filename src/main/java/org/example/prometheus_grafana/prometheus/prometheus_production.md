# Prometheus Production – HA, Thanos & Long-term Storage

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Vấn Đề của Prometheus Standalone

Prometheus đơn có các giới hạn trong production:

```
Vấn đề:
1. Single point of failure: 1 instance Prometheus = 1 SPOF
2. Retention ngắn: default 15d, max practical ~3 months trên 1 node
3. Không horizontal scale: 1 TSDB local, không share
4. Multi-cluster: khó query metrics từ nhiều cluster cùng lúc
5. Disk chứa data: node breakdown = mất data
```

---

## How – Prometheus HA (Basic)

```
Giải pháp đơn giản: chạy 2 Prometheus instance giống hệt nhau

Prometheus-1 ─┐                    ┌─ Prometheus-1
              ├─ scrape same targets─┤
Prometheus-2 ─┘                    └─ Prometheus-2

Grafana → query cả 2 → Dedup kết quả (nếu dùng Thanos Query)

Ưu điểm: nếu 1 instance chết, instance kia vẫn có data
Nhược điểm:
  - Không chia sẻ storage (2x disk usage)
  - Data có thể lệch nhau vài giây (scrape timing)
  - Không giải quyết long-term storage
```

### Prometheus + Thanos (Giải pháp production chuẩn)

```
Kiến trúc Thanos:

App/Node → Prometheus → Thanos Sidecar → Object Storage (S3/GCS/Azure)
                          ↑
                     Upload blocks mỗi 2h

Thanos Query ← Thanos Store Gateway (đọc từ object storage)
             ← Thanos Sidecar (query realtime từ Prometheus)
             ↑
           Grafana (dùng Thanos Querier như data source)

Thanos Ruler: đánh giá alert rules trên dữ liệu long-term
Thanos Compactor: compaction + downsampling (giảm resolution data cũ)
```

---

## Components – Thanos

### Thanos Sidecar

```yaml
# Chạy cùng pod với Prometheus
containers:
  - name: prometheus
    image: prom/prometheus:v2.48.0
    args:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.min-block-duration=2h  # Thanos yêu cầu 2h blocks
      - --storage.tsdb.max-block-duration=2h  # không để Prometheus tự compact
      - --web.enable-lifecycle

  - name: thanos-sidecar
    image: quay.io/thanos/thanos:v0.32.0
    args:
      - sidecar
      - --tsdb.path=/prometheus
      - --prometheus.url=http://localhost:9090
      - --objstore.config-file=/etc/thanos/s3-config.yml
      - --grpc-address=0.0.0.0:10901
      - --http-address=0.0.0.0:10902
    volumeMounts:
      - name: prometheus-data
        mountPath: /prometheus
      - name: thanos-config
        mountPath: /etc/thanos

# s3-config.yml
type: S3
config:
  bucket: my-prometheus-thanos
  endpoint: s3.ap-southeast-1.amazonaws.com
  region: ap-southeast-1
  # Dùng IAM role (không cần access_key nếu IRSA)
  access_key: ""
  secret_key: ""
  sse_config:
    type: SSE-S3
```

### Thanos Query (Querier)

```yaml
# Thanos Query: unified query endpoint
# Fan out queries đến nhiều Prometheus + Store Gateway
apiVersion: apps/v1
kind: Deployment
metadata:
  name: thanos-query
spec:
  replicas: 2   # HA: stateless, horizontal scalable
  template:
    spec:
      containers:
        - name: thanos-query
          image: quay.io/thanos/thanos:v0.32.0
          args:
            - query
            - --http-address=0.0.0.0:9090
            - --grpc-address=0.0.0.0:10901
            # Sidecar endpoints (realtime data)
            - --endpoint=prometheus-0.prometheus:10901
            - --endpoint=prometheus-1.prometheus:10901
            # Store Gateway endpoint (long-term data)
            - --endpoint=thanos-store-gateway:10901
            # Ruler endpoint
            - --endpoint=thanos-ruler:10901
            # Deduplication (remove duplicate series từ HA Prometheus)
            - --query.replica-label=prometheus_replica
            # Enable instant query timeout
            - --query.timeout=5m
            - --query.max-concurrent=20
          ports:
            - name: http
              containerPort: 9090
            - name: grpc
              containerPort: 10901
```

### Thanos Store Gateway

```yaml
# Đọc historical blocks từ object storage
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: thanos-store-gateway
spec:
  replicas: 2   # Sharding: mỗi instance handle subset of blocks
  template:
    spec:
      containers:
        - name: thanos-store
          image: quay.io/thanos/thanos:v0.32.0
          args:
            - store
            - --data-dir=/data               # local cache
            - --objstore.config-file=/etc/thanos/s3-config.yml
            - --grpc-address=0.0.0.0:10901
            - --http-address=0.0.0.0:10902
            # Sharding (2 instances, này là shard 0)
            - --selector.relabel-config=|
                - source_labels: [__block_id]
                  target_label: __tmp_hash
                  modulus: 2
                  action: hashmod
                - source_labels: [__tmp_hash]
                  regex: "0"
                  action: keep
          resources:
            requests:
              memory: "2Gi"    # cần cache index
              cpu: "500m"
```

### Thanos Compactor

```yaml
# Single instance (không chạy nhiều hơn 1)
# Compact + downsampling blocks cũ
containers:
  - name: thanos-compactor
    image: quay.io/thanos/thanos:v0.32.0
    args:
      - compact
      - --data-dir=/data
      - --objstore.config-file=/etc/thanos/s3-config.yml
      - --wait                         # chạy liên tục
      - --retention.resolution-raw=30d # data gốc giữ 30d
      - --retention.resolution-5m=90d  # downsampled 5m giữ 90d
      - --retention.resolution-1h=1y   # downsampled 1h giữ 1 năm
      - --compact.concurrency=1        # QUAN TRỌNG: chỉ 1 instance
      - --delete-delay=48h             # delay trước khi xóa blocks đã compact
```

### Thanos Ruler (Alert Rules trên Long-term Data)

```yaml
containers:
  - name: thanos-ruler
    image: quay.io/thanos/thanos:v0.32.0
    args:
      - rule
      - --data-dir=/data
      - --eval-interval=1m
      - --rule-file=/etc/thanos/rules/*.yml
      - --alertmanagers.url=http://alertmanager:9093
      - --query=http://thanos-query:9090    # dùng Thanos Query
      - --objstore.config-file=/etc/thanos/s3-config.yml
      - --label=ruler_cluster="production"
```

---

## How – VictoriaMetrics (Alternative đơn giản hơn)

```yaml
# VictoriaMetrics: drop-in replacement cho Prometheus
# HA cluster built-in, long-term storage, PromQL superset

# vminsert (nhận data) + vmstorage (lưu) + vmselect (query)
# Hoặc dùng single-node cho nhỏ hơn

# vmagent (thay thế Prometheus scraping, nhẹ hơn)
containers:
  - name: vmagent
    image: victoriametrics/vmagent:v1.93.0
    args:
      - -promscrape.config=/etc/prometheus/prometheus.yml
      - -remoteWrite.url=http://vminsert:8480/insert/0/prometheus
      - -remoteWrite.label=cluster=production
      - -memory.allowedBytes=512MB

# Victoria Metrics Single (dev/small prod)
containers:
  - name: victoriametrics
    image: victoriametrics/victoria-metrics:v1.93.0
    args:
      - -storageDataPath=/data
      - -retentionPeriod=12  # 12 months
      - -httpListenAddr=:8428
```

---

## How – Remote Write (Push to Long-term Storage)

```yaml
# prometheus.yml: remote_write đến long-term storage
global:
  external_labels:
    cluster: production
    region: ap-southeast-1

remote_write:
  # Thanos Receive (alternative to sidecar)
  - url: "http://thanos-receive:19291/api/v1/receive"
    queue_config:
      capacity: 10000
      max_shards: 30
      min_shards: 1
      max_samples_per_send: 5000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 100ms
    write_relabel_configs:
      # Chỉ gửi metrics cần long-term
      - source_labels: [__name__]
        regex: "job:.*|service:.*|cluster:.*"  # chỉ recording rules
        action: keep

  # Grafana Cloud / Cortex / Mimir
  - url: "https://prometheus-prod.grafana.net/api/prom/push"
    basic_auth:
      username: "123456"
      password_file: /etc/prometheus/grafana-cloud-key

  # VictoriaMetrics
  - url: "http://victoriametrics:8428/api/v1/write"
    remote_timeout: 30s
```

---

## Compare – Thanos vs Cortex vs VictoriaMetrics vs Grafana Mimir

| | Thanos | Cortex | VictoriaMetrics | Grafana Mimir |
|--|--------|--------|----------------|---------------|
| Kiến trúc | Sidecar/Receive + Object Storage | Microservices | Monolithic/Cluster | Microservices |
| Complexity | Trung bình | Cao | Thấp | Cao |
| Object Storage | S3/GCS/Azure | S3/GCS/Azure | S3/GCS/Azure | S3/GCS/Azure |
| PromQL compat | 100% | 99% | 99%+ superset | 100% |
| Long-term | Yes | Yes | Yes | Yes |
| Multi-tenant | Hạn chế | Yes | Yes | Yes |
| K8s native | Yes (Operator) | Yes | Yes | Yes |
| Downsampling | Yes | No | No | No |
| Setup effort | Medium | Hard | Easy | Hard |
| Best for | Self-hosted HA | Large multi-tenant | Simple, high perf | Grafana Cloud |

---

## Trade-offs

```
Thanos:
✅ Mature, battle-tested (Shopify, GitLab...)
✅ Downsampling (tiết kiệm storage query data cũ)
✅ Không thay đổi Prometheus
❌ Nhiều components (sidecar, query, store, compactor)
❌ Compactor SPOF nếu không cẩn thận
❌ High memory footprint cho Store Gateway

VictoriaMetrics:
✅ Đơn giản nhất, 1 binary
✅ 5-10x ít RAM hơn Prometheus cho cùng workload
✅ Ingest nhanh, cardinality cao hơn
❌ Không downsampling native
❌ Ít community hơn Thanos
❌ Trả phí cho enterprise features

Cortex/Mimir:
✅ True horizontal scale
✅ Multi-tenancy
❌ Phức tạp nhất
❌ Cần nhiều infrastructure (Kafka, Cassandra hoặc nhiều S3 paths)
```

---

## Real-world – Production Setup Checklist

```
Storage:
□ Retention policy: raw/5m/1h (dùng Thanos Compactor)
□ Object storage lifecycle: Glacier/IA sau 90d
□ Disk: SSD cho Prometheus data dir (/prometheus)
□ IOPS: ~100 IOPS/node scraping 1000 series@15s

HA:
□ 2+ Prometheus instances với replica label
□ Thanos Query với --query.replica-label
□ Alertmanager HA cluster (3 nodes)

Networking:
□ Thanos gRPC: mTLS giữa các components
□ Objstore: VPC endpoint (không qua internet)
□ Scrape: NetworkPolicy cho phép Prometheus → target:port

Resource sizing (rule of thumb):
  Prometheus: 3GB RAM per 1M active series
  Thanos Store: 2GB RAM + SSD cache
  Thanos Compactor: 1-4GB RAM (spike khi compact)
  VictoriaMetrics: 1GB RAM per 1M active series

Performance:
□ Set --storage.tsdb.wal-compression
□ Recording rules cho expensive queries
□ Limit scrape concurrency: --scrape.concurrent-scrapes
□ metric_relabel_configs để drop unused metrics
□ High cardinality alert: check series count thường xuyên
```

### Monitoring Prometheus Itself

```promql
# Số active series
prometheus_tsdb_head_series

# Ingestion rate (samples/sec)
rate(prometheus_tsdb_head_samples_appended_total[5m])

# Storage size
prometheus_tsdb_storage_blocks_bytes

# WAL size
prometheus_tsdb_wal_storage_size_bytes

# Scrape duration (phát hiện target chậm)
scrape_duration_seconds > 10

# Failed scrapes
rate(scrape_samples_post_metric_relabeling[5m]) == 0
  and up == 1  # up but 0 samples = misconfigured exporter

# Query latency
histogram_quantile(0.99, rate(prometheus_engine_query_duration_seconds_bucket[5m]))

# Rule evaluation lag
prometheus_rule_group_last_duration_seconds > prometheus_rule_group_interval_seconds
```

---

## Ghi chú – Chủ đề tiếp theo
> `grafana_fundamentals.md`: Grafana data sources, Dashboards, Panel types, Variables, Explore

---

*Cập nhật lần cuối: 2026-05-06*
