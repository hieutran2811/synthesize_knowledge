# Kubernetes Observability Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. kube-prometheus-stack

### What – kube-prometheus-stack là gì?
kube-prometheus-stack là Helm chart bundle toàn bộ monitoring stack: Prometheus Operator, Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter, và các pre-built dashboards/alerts.

### How – Cài đặt và cấu hình

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring-values.yaml
```

```yaml
# monitoring-values.yaml
prometheus:
  prometheusSpec:
    retention: 30d
    retentionSize: 50GB
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: fast-ssd
          resources:
            requests:
              storage: 50Gi
    # Prometheus cần xem tất cả namespaces
    podMonitorNamespaceSelector: {}
    serviceMonitorNamespaceSelector: {}
    ruleNamespaceSelector: {}
    # External labels (cho multi-cluster)
    externalLabels:
      cluster: production
      region: us-east-1
    # AlertManager address
    alerting:
      alertmanagers:
      - namespace: monitoring
        name: alertmanager-kube-prometheus-stack-alertmanager
        port: web
    resources:
      requests:
        memory: 2Gi
        cpu: 500m
      limits:
        memory: 4Gi
        cpu: "2"
    # HA: 2 replicas (thematic sharding cho large clusters)
    replicas: 2

alertmanager:
  alertmanagerSpec:
    storage:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          resources:
            requests:
              storage: 10Gi
    replicas: 3    # HA AlertManager cluster

grafana:
  adminPassword: "changeme123"
  persistence:
    enabled: true
    storageClassName: fast-ssd
    size: 10Gi
  sidecar:
    dashboards:
      enabled: true    # auto-load dashboards từ ConfigMaps
      label: grafana_dashboard
  grafana.ini:
    server:
      root_url: https://grafana.mycompany.com
    auth.generic_oauth:
      enabled: true
      name: "Google"
      client_id: xxx
      client_secret: xxx
      scopes: openid email profile
      auth_url: https://accounts.google.com/o/oauth2/auth
      token_url: https://oauth2.googleapis.com/token
      api_url: https://openidconnect.googleapis.com/v1/userinfo
      allowed_domains: mycompany.com

kube-state-metrics:
  resources:
    requests:
      memory: 128Mi
      cpu: 100m
    limits:
      memory: 256Mi

nodeExporter:
  enabled: true
```

### How – ServiceMonitor và PodMonitor

```yaml
# ServiceMonitor: scrape metrics từ Service endpoint
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: myapp-monitor
  namespace: production
  labels:
    release: kube-prometheus-stack    # label phải match Prometheus selector
spec:
  selector:
    matchLabels:
      app: myapp                    # match Service labels
  namespaceSelector:
    matchNames:
    - production
  endpoints:
  - port: metrics          # port name trong Service spec
    path: /actuator/prometheus    # custom path (Spring Boot)
    interval: 30s
    scrapeTimeout: 10s
    scheme: http
    # Basic auth nếu metrics endpoint secured
    basicAuth:
      username:
        name: metrics-auth
        key: username
      password:
        name: metrics-auth
        key: password
    # TLS
    tlsConfig:
      insecureSkipVerify: false
      caFile: /etc/prometheus/configmaps/ca/ca.crt
    # Relabeling: transform labels
    relabelings:
    - sourceLabels: [__meta_kubernetes_pod_name]
      targetLabel: pod
    - sourceLabels: [__meta_kubernetes_namespace]
      targetLabel: namespace
    metricRelabelings:
    - sourceLabels: [__name__]
      regex: "jvm_.*|http_.*|process_.*"    # chỉ giữ các metrics quan trọng
      action: keep

---
# PodMonitor: scrape trực tiếp từ Pods (không cần Service)
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: myapp-pods
  namespace: production
spec:
  selector:
    matchLabels:
      app: myapp
  podMetricsEndpoints:
  - port: metrics
    interval: 15s
```

### How – PrometheusRule (Alerting Rules)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: myapp-alerts
  namespace: production
  labels:
    release: kube-prometheus-stack
spec:
  groups:
  - name: myapp.rules
    interval: 30s
    rules:
    # Recording rule: pre-compute expensive queries
    - record: job:http_requests_total:rate5m
      expr: |
        sum by (job, status) (
          rate(http_requests_total[5m])
        )
    # Alert: high error rate
    - alert: HighErrorRate
      expr: |
        (
          sum(rate(http_requests_total{job="myapp",status=~"5.."}[5m]))
          /
          sum(rate(http_requests_total{job="myapp"}[5m]))
        ) > 0.05
      for: 5m          # phải true trong 5 phút
      labels:
        severity: critical
        team: backend
      annotations:
        summary: "High error rate in {{ $labels.job }}"
        description: "Error rate is {{ $value | humanizePercentage }} (>5%)"
        runbook_url: "https://wiki.company.com/runbooks/high-error-rate"
        dashboard_url: "https://grafana.company.com/d/xxx?var-job={{ $labels.job }}"

    # Alert: pod not ready
    - alert: PodNotReady
      expr: |
        sum by (namespace, pod) (
          max by (namespace, pod) (kube_pod_status_phase{phase=~"Pending|Unknown|Failed"})
          * on (namespace, pod) group_left(owner_kind)
          max by (namespace, pod, owner_kind) (kube_pod_owner{owner_kind!="Job"})
        ) > 0
      for: 15m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.namespace }}/{{ $labels.pod }} not ready"

    # Alert: deployment replicas mismatch
    - alert: DeploymentReplicasMismatch
      expr: |
        (
          kube_deployment_spec_replicas
          != kube_deployment_status_available_replicas
        ) and (
          changes(kube_deployment_status_ready_replicas[10m]) == 0
        )
      for: 10m
      labels:
        severity: critical
      annotations:
        summary: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} replicas mismatch"
        description: "Desired {{ $value }} replicas but available differ for 10+ minutes"

    # Alert: disk pressure
    - alert: NodeDiskPressure
      expr: |
        (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) < 0.10
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Low disk space on {{ $labels.instance }}"
        description: "Only {{ $value | humanizePercentage }} disk space remaining"

    # Alert: memory pressure
    - alert: ContainerOOMKilled
      expr: kube_pod_container_status_last_terminated_reason{reason="OOMKilled"} == 1
      for: 0m    # alert immediately
      labels:
        severity: warning
      annotations:
        summary: "Container OOMKilled: {{ $labels.namespace }}/{{ $labels.pod }}/{{ $labels.container }}"
```

### How – Alertmanager Configuration

```yaml
# AlertManager config (Secret trong kube-prometheus-stack)
global:
  smtp_from: alerts@mycompany.com
  smtp_smarthost: smtp.gmail.com:587
  smtp_auth_username: alerts@mycompany.com
  smtp_auth_password: "smtp-password"
  slack_api_url: https://hooks.slack.com/services/xxx/yyy/zzz
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'namespace']
  group_wait: 30s         # đợi 30s gom alerts trước khi gửi
  group_interval: 5m      # gửi updates mỗi 5 phút nếu alert còn đó
  repeat_interval: 4h     # re-notify mỗi 4 giờ nếu không resolved
  receiver: slack-default
  routes:
  - match:
      severity: critical
    receiver: pagerduty-critical
    continue: true        # tiếp tục match routes khác
  - match:
      severity: critical
    receiver: slack-critical
  - match:
      team: backend
    receiver: slack-backend-team
  - match:
      alertname: Watchdog    # heartbeat alert, không gửi notification
    receiver: "null"

receivers:
- name: "null"

- name: slack-default
  slack_configs:
  - channel: '#alerts'
    title: '[{{ .Status | toUpper }}] {{ .GroupLabels.alertname }}'
    text: |
      {{ range .Alerts }}
      *Alert:* {{ .Annotations.summary }}
      *Severity:* {{ .Labels.severity }}
      *Description:* {{ .Annotations.description }}
      {{ if .Annotations.runbook_url }}*Runbook:* {{ .Annotations.runbook_url }}{{ end }}
      {{ end }}
    send_resolved: true

- name: pagerduty-critical
  pagerduty_configs:
  - routing_key: "pagerduty-integration-key"
    description: '{{ .GroupLabels.alertname }}: {{ .Annotations.summary }}'

inhibit_rules:
- source_match:
    severity: critical
  target_match:
    severity: warning
  equal: ['alertname', 'namespace']    # inhibit warning nếu critical đã fire cho cùng alertname+namespace
```

---

## 2. OpenTelemetry (OTel)

### What – OpenTelemetry là gì?
OpenTelemetry là CNCF standard cho observability: traces, metrics, logs. Thay thế vendor-specific SDKs (Datadog/NewRelic/Jaeger riêng biệt) bằng một SDK duy nhất.

### How – OTel Collector

```yaml
# OpenTelemetry Collector: thu thập, process, và export telemetry
apiVersion: v1
kind: ConfigMap
metadata:
  name: otel-collector-config
  namespace: monitoring
data:
  config.yaml: |
    receivers:
      otlp:                        # nhận từ app SDKs (gRPC/HTTP)
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
      prometheus:                  # scrape Prometheus metrics
        config:
          scrape_configs:
          - job_name: myapp
            kubernetes_sd_configs:
            - role: pod
      k8s_cluster:                 # K8s cluster metrics
        auth_type: serviceAccount
      kubeletstats:                # node + pod stats
        auth_type: serviceAccount
        endpoint: "https://${env:K8S_NODE_NAME}:10250"
        insecure_skip_verify: true

    processors:
      batch:                       # batch before export (performance)
        timeout: 5s
        send_batch_size: 1000
      memory_limiter:             # tránh OOM
        check_interval: 1s
        limit_mib: 400
        spike_limit_mib: 100
      k8sattributes:              # enrich với K8s metadata
        auth_type: serviceAccount
        passthrough: false
        extract:
          metadata:
          - k8s.pod.name
          - k8s.namespace.name
          - k8s.deployment.name
          - k8s.node.name
        pod_association:
        - sources:
          - from: resource_attribute
            name: k8s.pod.ip
      resource:
        attributes:
        - key: cluster
          value: production
          action: insert

    exporters:
      otlp/jaeger:                # export traces đến Jaeger
        endpoint: jaeger-collector.monitoring.svc.cluster.local:4317
        tls:
          insecure: true
      prometheusremotewrite:      # export metrics đến Prometheus
        endpoint: http://prometheus.monitoring.svc.cluster.local:9090/api/v1/write
      loki:                       # export logs đến Loki
        endpoint: http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push
        labels:
          resource:
            k8s.namespace.name: "namespace"
            k8s.pod.name: "pod"

    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, batch]
          exporters: [otlp/jaeger]
        metrics:
          receivers: [otlp, prometheus, k8s_cluster, kubeletstats]
          processors: [memory_limiter, k8sattributes, resource, batch]
          exporters: [prometheusremotewrite]
        logs:
          receivers: [otlp]
          processors: [memory_limiter, k8sattributes, batch]
          exporters: [loki]
```

### How – Auto-instrumentation (Java/Node.js)

```yaml
# OTel Operator: auto-inject agents
# kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

# Instrumentation CR: define how to instrument
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: myapp-instrumentation
  namespace: production
spec:
  exporter:
    endpoint: http://otel-collector.monitoring.svc.cluster.local:4317
  propagators:
  - tracecontext
  - baggage
  - b3
  sampler:
    type: parentbased_traceidratio
    argument: "0.1"    # sample 10% of traces
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest
    env:
    - name: OTEL_SERVICE_NAME
      valueFrom:
        fieldRef:
          fieldPath: metadata.labels['app']
    - name: OTEL_RESOURCE_ATTRIBUTES
      value: "cluster=production,namespace=$(OTEL_K8S_NAMESPACE)"
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:latest
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:latest
---
# Pod annotation để auto-instrument
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-java: "true"
        # hoặc:
        instrumentation.opentelemetry.io/inject-nodejs: "true"
        instrumentation.opentelemetry.io/inject-python: "true"
```

### How – Distributed Tracing với Tempo

```yaml
# Grafana Tempo: distributed tracing storage
helm install tempo grafana/tempo-distributed \
  --namespace monitoring \
  --set storage.trace.backend=s3 \
  --set storage.trace.s3.bucket=my-traces-bucket \
  --set storage.trace.s3.region=us-east-1

# Tempo DataSource trong Grafana
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  labels:
    grafana_datasource: "1"
data:
  tempo.yaml: |
    apiVersion: 1
    datasources:
    - name: Tempo
      type: tempo
      url: http://tempo.monitoring.svc.cluster.local:3100
      jsonData:
        tracesToLogsV2:
          datasourceUid: loki        # link từ trace → log
          filterByTraceID: true
          filterBySpanID: false
          customQuery: false
        serviceMap:
          datasourceUid: prometheus  # service map từ metrics
        nodeGraph:
          enabled: true
        search:
          hide: false
        lokiSearch:
          datasourceUid: loki
```

---

## 3. Grafana Dashboards

### How – Custom Dashboard as ConfigMap

```yaml
# Auto-load dashboard từ ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: myapp-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "1"    # label này để Grafana sidecar auto-load
data:
  myapp-dashboard.json: |
    {
      "title": "MyApp Overview",
      "uid": "myapp-overview",
      "panels": [
        {
          "title": "Request Rate",
          "type": "timeseries",
          "targets": [
            {
              "expr": "sum(rate(http_requests_total{job=\"myapp\"}[5m])) by (status)",
              "legendFormat": "{{status}}"
            }
          ]
        },
        {
          "title": "P99 Latency",
          "type": "timeseries",
          "targets": [
            {
              "expr": "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{job=\"myapp\"}[5m])) by (le))",
              "legendFormat": "p99"
            }
          ]
        },
        {
          "title": "Error Rate",
          "type": "stat",
          "targets": [
            {
              "expr": "sum(rate(http_requests_total{job=\"myapp\",status=~\"5..\"}[5m])) / sum(rate(http_requests_total{job=\"myapp\"}[5m]))",
              "legendFormat": "Error Rate"
            }
          ],
          "fieldConfig": {
            "defaults": {
              "unit": "percentunit",
              "thresholds": {
                "steps": [
                  {"color": "green", "value": null},
                  {"color": "yellow", "value": 0.01},
                  {"color": "red", "value": 0.05}
                ]
              }
            }
          }
        }
      ],
      "templating": {
        "list": [
          {
            "name": "namespace",
            "type": "query",
            "query": "label_values(kube_pod_info, namespace)"
          },
          {
            "name": "pod",
            "type": "query",
            "query": "label_values(kube_pod_info{namespace=\"$namespace\"}, pod)"
          }
        ]
      }
    }
```

### How – Useful PromQL Queries

```promql
# === Pod & Container ===
# CPU usage (millicores)
sum(rate(container_cpu_usage_seconds_total{namespace="production", container!=""}[5m])) by (pod, container) * 1000

# Memory usage
sum(container_memory_working_set_bytes{namespace="production", container!=""}) by (pod, container)

# Memory limit utilization
(
  sum(container_memory_working_set_bytes{namespace="production"}) by (pod)
  /
  sum(kube_pod_container_resource_limits{namespace="production", resource="memory"}) by (pod)
)

# Container restarts in last hour
increase(kube_pod_container_status_restarts_total{namespace="production"}[1h]) > 0

# === Node ===
# Node CPU usage
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)) * 100

# Node memory available
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Node disk I/O
rate(node_disk_io_time_seconds_total{device!~"loop.*"}[5m])

# === Application ===
# HTTP error rate
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# Apdex score (satisfaction/toleration/frustration)
(
  sum(rate(http_request_duration_seconds_bucket{le="0.3"}[5m]))
  +
  sum(rate(http_request_duration_seconds_bucket{le="1.2"}[5m])) / 2
) / sum(rate(http_request_duration_seconds_count[5m]))

# Request rate by status code
sum by (status) (rate(http_requests_total[5m]))

# P50/P95/P99 latency
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

---

### Compare – Observability Tools

| | Prometheus + Grafana | Datadog | New Relic | Victoria Metrics |
|--|---------------------|---------|-----------|-----------------|
| **Cost** | Free (infra cost) | Expensive | Expensive | Free (open-source) |
| **Retention** | Limited by storage | Long-term | Long-term | High cardinality |
| **Setup** | Complex | Easy | Easy | Medium |
| **Customization** | Full control | Limited | Limited | Full control |
| **Cardinality** | Limited | High | High | Very High |
| **Tracing** | Tempo/Jaeger | Built-in | Built-in | External |
| **Best for** | Cost-sensitive, custom | Enterprise, easy setup | APM focus | High-scale |

### Trade-offs
- Prometheus federation: giải quyết multi-cluster nhưng thêm complexity; Thanos/Cortex cho global view
- High cardinality metrics: Prometheus có thể OOM với quá nhiều label values; cẩn thận với dynamic labels
- OTel sampling: quá cao (100%) tốn storage; quá thấp (0.1%) bỏ sót bugs; head vs tail sampling
- Alert fatigue: quá nhiều alerts → ignored; luôn cần actionable alerts với runbook

### Real-world Usage
```bash
# Kiểm tra Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# → http://localhost:9090/targets: xem tất cả scrape targets và status

# Xem alert rules
# → http://localhost:9090/alerts: xem active alerts và pending

# Grafana: port forward
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# → http://localhost:3000 (admin/changeme123)

# Debug scraping issues
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
  promtool check config /etc/prometheus/config_out/prometheus.env.yaml

# Kiểm tra recording/alerting rules
kubectl exec -n monitoring prometheus-kube-prometheus-stack-prometheus-0 -- \
  promtool check rules /etc/prometheus/rules/*

# Alert volume analysis
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# → http://localhost:9093: xem alerts đang active, silences
```

### Ghi chú – Chủ đề tiếp theo
> Helm Deep – Chart authoring best practices, Helm hooks, library charts, OCI registry, helmfile

---

*Cập nhật lần cuối: 2026-05-06*
