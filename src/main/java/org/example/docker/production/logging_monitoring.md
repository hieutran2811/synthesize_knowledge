# Docker Logging & Monitoring – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Docker Logging Architecture

### What – Logging Drivers là gì?
**Docker logging drivers** kiểm soát cách container logs được thu thập và gửi đến destinations. Mặc định: `json-file` (lưu local). Production thường dùng log aggregation system.

### How – Logging Drivers Overview

```
Container stdout/stderr
        ↓
Docker Logging Driver
        ↓
┌─────────────────────────────────────────────────┐
│ json-file  → /var/lib/docker/containers/<id>/*  │
│ journald   → systemd journal                     │
│ syslog     → syslog daemon                       │
│ fluentd    → Fluentd aggregator                  │
│ awslogs    → AWS CloudWatch Logs                 │
│ gcplogs    → Google Cloud Logging                │
│ splunk     → Splunk HTTP Event Collector         │
│ gelf       → Graylog Extended Log Format         │
│ none       → discard all logs                    │
└─────────────────────────────────────────────────┘
```

### How – json-file Driver (Default)

```bash
# Cấu hình trong /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",            # rotate khi file > 10MB
    "max-file": "5",              # giữ 5 files (50MB tổng)
    "compress": "true",           # gzip nén rotated files
    "labels": "service,env",      # thêm container labels vào log entry
    "env": "SERVICE_NAME,APP_VERSION"
  }
}

# Per-container override
docker run \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=3 \
  myapp

# Xem log file trực tiếp
cat /var/lib/docker/containers/<id>/<id>-json.log | head -5
# {"log":"2024-01-15T10:30:00Z INFO Starting server\n",
#  "stream":"stdout",
#  "time":"2024-01-15T10:30:00.123456789Z"}

# docker logs command vẫn hoạt động với json-file
docker logs --tail 100 --since 1h myapp
docker logs -f myapp
```

### How – fluentd Driver

```bash
# Cần Fluentd/Fluent Bit chạy trước
docker run -d \
  --log-driver fluentd \
  --log-opt fluentd-address=localhost:24224 \
  --log-opt fluentd-tag=docker.{{.Name}} \
  --log-opt fluentd-async=true \           # non-blocking (khuyến nghị)
  --log-opt fluentd-buffer-limit=8m \
  myapp

# Compose
services:
  app:
    logging:
      driver: fluentd
      options:
        fluentd-address: "fluentd:24224"
        fluentd-tag: "docker.{{.Name}}"
        fluentd-async: "true"
```

### How – AWS CloudWatch Logs

```bash
docker run -d \
  --log-driver awslogs \
  --log-opt awslogs-group=/prod/myapp \
  --log-opt awslogs-region=ap-southeast-1 \
  --log-opt awslogs-stream=instance-1 \
  --log-opt awslogs-create-group=true \
  myapp

# Compose (production)
services:
  app:
    logging:
      driver: awslogs
      options:
        awslogs-group: "/prod/myapp"
        awslogs-region: "ap-southeast-1"
        awslogs-stream: "{{.Name}}"
        awslogs-create-group: "true"
```

---

## 2. EFK Stack – Elasticsearch + Fluentd + Kibana

### What – EFK Stack là gì?
**EFK** là log aggregation stack phổ biến: **Elasticsearch** (store & search), **Fluentd** (collect & transform), **Kibana** (visualize).

### How – EFK với Docker Compose

```yaml
# compose.logging.yaml
services:
  # ── Elasticsearch ─────────────────────────────────────────
  elasticsearch:
    image: elasticsearch:8.12.0
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
      - xpack.security.enabled=false    # dev only!
    volumes:
      - esdata:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -sf http://localhost:9200/_cluster/health | grep -q '\"status\":\"green\"'"]
      interval: 30s
      retries: 5
    networks:
      - logging

  # ── Kibana ────────────────────────────────────────────────
  kibana:
    image: kibana:8.12.0
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - logging

  # ── Fluentd ───────────────────────────────────────────────
  fluentd:
    build:
      context: ./fluentd
      dockerfile: Dockerfile
    ports:
      - "24224:24224"
      - "24224:24224/udp"
    volumes:
      - ./fluentd/conf:/fluentd/etc:ro
    depends_on:
      elasticsearch:
        condition: service_healthy
    networks:
      - logging

  # ── App ───────────────────────────────────────────────────
  app:
    image: myapp:latest
    logging:
      driver: fluentd
      options:
        fluentd-address: "fluentd:24224"
        fluentd-tag: "docker.app"
        fluentd-async: "true"
    networks:
      - logging
      - default

volumes:
  esdata:

networks:
  logging:
    driver: bridge
```

```dockerfile
# fluentd/Dockerfile
FROM fluent/fluentd:v1.16-debian-1
USER root
RUN gem install fluent-plugin-elasticsearch --no-document
USER fluent
```

```xml
<!-- fluentd/conf/fluent.conf -->
<source>
  @type forward
  port 24224
  bind 0.0.0.0
</source>

<filter docker.**>
  @type parser
  key_name log
  reserve_data true
  <parse>
    @type json
    time_key timestamp
    time_format %Y-%m-%dT%H:%M:%S.%NZ
  </parse>
</filter>

<match docker.**>
  @type elasticsearch
  host elasticsearch
  port 9200
  logstash_format true
  logstash_prefix docker-logs
  include_tag_key true
  tag_key @log_name
  flush_interval 5s
</match>
```

---

## 3. Loki + Promtail (Lightweight Alternative)

### What – Loki là gì?
**Grafana Loki** là log aggregation system được thiết kế như Prometheus nhưng cho logs. **Không index nội dung log** – chỉ index labels → storage rẻ hơn Elasticsearch 10x.

### How – Loki Stack với Compose

```yaml
services:
  # ── Loki ──────────────────────────────────────────────────
  loki:
    image: grafana/loki:2.9.4
    ports:
      - "3100:3100"
    command: -config.file=/etc/loki/local-config.yaml
    volumes:
      - ./loki/config.yaml:/etc/loki/local-config.yaml:ro
      - loki-data:/loki

  # ── Promtail (log collector) ───────────────────────────────
  promtail:
    image: grafana/promtail:2.9.4
    volumes:
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./promtail/config.yaml:/etc/promtail/config.yaml:ro
    command: -config.file=/etc/promtail/config.yaml
    depends_on: [loki]

  # ── Grafana ────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:10.3.1
    ports:
      - "3000:3000"
    environment:
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/datasources:/etc/grafana/provisioning/datasources:ro
    depends_on: [loki]

volumes:
  loki-data:
  grafana-data:
```

```yaml
# promtail/config.yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: docker
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      - source_labels: ['__meta_docker_container_name']
        regex: '/(.*)'
        target_label: 'container'
      - source_labels: ['__meta_docker_container_label_com_docker_compose_service']
        target_label: 'service'
      - source_labels: ['__meta_docker_container_label_com_docker_compose_project']
        target_label: 'project'
    pipeline_stages:
      - json:
          expressions:
            level: level
            msg: message
      - labels:
          level:
```

---

## 4. Metrics – Prometheus + cAdvisor + Grafana

### What – Container Metrics là gì?
Container metrics bao gồm: **CPU**, **memory**, **network I/O**, **disk I/O**, **container lifecycle**. Prometheus scrape metrics từ exporters, Grafana visualize.

### How – Full Monitoring Stack

```yaml
services:
  # ── Prometheus ────────────────────────────────────────────
  prometheus:
    image: prom/prometheus:v2.50.0
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=15d'
      - '--web.enable-lifecycle'     # hot reload: curl -X POST /-/reload

  # ── cAdvisor (Container metrics) ──────────────────────────
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.49.1
    privileged: true
    devices:
      - /dev/kmsg
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
      - /dev/disk/:/dev/disk:ro
    ports:
      - "8080:8080"

  # ── Node Exporter (Host metrics) ──────────────────────────
  node-exporter:
    image: prom/node-exporter:v1.7.0
    pid: "host"
    network_mode: "host"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

  # ── Grafana ────────────────────────────────────────────────
  grafana:
    image: grafana/grafana:10.3.1
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro

  # ── Alertmanager ──────────────────────────────────────────
  alertmanager:
    image: prom/alertmanager:v0.27.0
    ports:
      - "9093:9093"
    volumes:
      - ./alertmanager/config.yml:/etc/alertmanager/config.yml:ro

volumes:
  prometheus-data:
  grafana-data:
```

```yaml
# prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - /etc/prometheus/rules/*.yml

scrape_configs:
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
    metric_relabel_configs:
      - source_labels: [container_label_com_docker_compose_service]
        target_label: service

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'app'
    static_configs:
      - targets: ['app:8080']    # app phải expose /metrics (Prometheus format)
    metrics_path: /metrics
```

### How – cAdvisor Metrics Quan Trọng

```promql
# CPU usage per container (%)
rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100

# Memory usage
container_memory_usage_bytes{name!=""}

# Memory limit
container_spec_memory_limit_bytes{name!=""}

# Memory usage % của limit
container_memory_usage_bytes{name!=""} /
  container_spec_memory_limit_bytes{name!=""} * 100

# Network I/O
rate(container_network_receive_bytes_total[5m])
rate(container_network_transmit_bytes_total[5m])

# Container restart count
increase(container_start_time_seconds{name!=""}[1h])

# Disk I/O
rate(container_fs_reads_bytes_total[5m])
rate(container_fs_writes_bytes_total[5m])
```

### How – Alerting Rules

```yaml
# prometheus/rules/docker.yml
groups:
  - name: docker
    interval: 30s
    rules:
      - alert: ContainerHighCPU
        expr: rate(container_cpu_usage_seconds_total{name!=""}[5m]) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Container {{ $labels.name }} high CPU"
          description: "CPU usage {{ $value | humanize }}% for 5 minutes"

      - alert: ContainerMemoryNearLimit
        expr: |
          container_memory_usage_bytes{name!=""} /
          container_spec_memory_limit_bytes{name!=""} * 100 > 85
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Container {{ $labels.name }} memory near limit"

      - alert: ContainerOOMKilled
        expr: increase(container_oom_events_total[5m]) > 0
        labels:
          severity: critical
        annotations:
          summary: "Container {{ $labels.name }} OOM killed"

      - alert: ContainerNotRunning
        expr: |
          absent(container_last_seen{name=~"myapp.*"})
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Container {{ $labels.name }} is not running"
```

---

## 5. Application-level Metrics

### How – Expose Prometheus Metrics từ App

```javascript
// Node.js: prom-client
const prometheus = require('prom-client');
const collectDefaultMetrics = prometheus.collectDefaultMetrics;
collectDefaultMetrics({ timeout: 5000 });

const httpRequestDurationMs = new prometheus.Histogram({
  name: 'http_request_duration_ms',
  help: 'HTTP request duration in milliseconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [1, 5, 10, 50, 100, 200, 500, 1000, 2000, 5000]
});

app.use((req, res, next) => {
  const end = httpRequestDurationMs.startTimer();
  res.on('finish', () => {
    end({ method: req.method, route: req.route?.path, status: res.statusCode });
  });
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', prometheus.register.contentType);
  res.end(await prometheus.register.metrics());
});
```

```java
// Spring Boot: Micrometer + Prometheus
// pom.xml: micrometer-registry-prometheus + spring-boot-actuator

// application.yml:
// management:
//   endpoints:
//     web:
//       exposure:
//         include: health,info,prometheus,metrics
//   endpoint:
//     prometheus:
//       enabled: true
//   metrics:
//     tags:
//       application: myapp
//       env: production

// → /actuator/prometheus expose metrics tự động
```

### Compare – Logging Backends

| | Elasticsearch | Loki | Splunk | CloudWatch |
|--|-------------|------|--------|-----------|
| Index full text | ✅ | ❌ (labels only) | ✅ | ✅ |
| Query language | KQL | LogQL | SPL | Insights QL |
| Storage cost | Cao | Thấp (10x) | Cao | Trung bình |
| Complexity | Cao | Thấp | Cao | Thấp |
| Hosted option | Elastic Cloud | Grafana Cloud | Splunk Cloud | AWS managed |
| License | Elastic | AGPLv3 | Commercial | AWS service |

### Trade-offs
- json-file: đơn giản nhưng không aggregate, tốn disk nếu không configure rotation
- fluentd vs fluent-bit: Fluentd (Ruby, nhiều plugins) vs Fluent Bit (C, nhẹ hơn, tốt cho edge)
- Elasticsearch: full-text search tốt nhưng resource hungry (RAM++)
- Loki: rẻ hơn nhưng chỉ search theo labels, không search nội dung nhanh

### Real-world Usage
```bash
# Xem logs với jq (json-file format)
docker logs myapp 2>&1 | jq -r '. | "\(.time) [\(.level // "INFO")] \(.message)"'

# Follow logs từ nhiều containers với timestamps
docker compose logs -f --timestamps app worker

# Aggregate logs from nhiều containers sang file
docker compose logs --no-color > all-logs-$(date +%Y%m%d).txt

# Grafana dashboard provisioning (auto-load dashboards)
# /etc/grafana/provisioning/dashboards/docker.json (from grafana.com/dashboards/893)
# Dashboard ID 893: Docker & System Monitoring
```

### Ghi chú – Chủ đề tiếp theo
> CI/CD Integration – GitHub Actions full pipeline, GitLab CI, Jenkins với Docker agent

---

*Cập nhật lần cuối: 2026-05-06*
