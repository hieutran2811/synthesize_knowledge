# Prometheus Service Discovery – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Service Discovery là gì?

**Service Discovery** trong Prometheus là cơ chế **tự động phát hiện targets** cần scrape mà không cần cấu hình thủ công từng IP/port. Trong môi trường dynamic (K8s, cloud), instances được tạo/xóa liên tục – service discovery đảm bảo Prometheus luôn có danh sách targets chính xác.

```
Không có SD:
  static_configs → list cứng IPs → phải update thủ công khi thay đổi

Có SD:
  kubernetes_sd / consul_sd / ec2_sd → tự discover → luôn up-to-date
  + Relabeling: lọc, rename, thêm labels từ metadata của targets
```

---

## How – Các SD Mechanisms

### 1. Static Config

```yaml
scrape_configs:
  - job_name: api-servers
    static_configs:
      - targets:
          - "api1.internal:8080"
          - "api2.internal:8080"
        labels:
          environment: production
          region: ap-southeast-1

      - targets:
          - "api3.internal:8080"
        labels:
          environment: staging
```

### 2. File-based SD

```yaml
# prometheus.yml
scrape_configs:
  - job_name: dynamic-targets
    file_sd_configs:
      - files:
          - "/etc/prometheus/targets/*.json"
          - "/etc/prometheus/targets/*.yml"
        refresh_interval: 30s  # reload file mỗi 30s

# /etc/prometheus/targets/api.json
[
  {
    "targets": ["api1:8080", "api2:8080"],
    "labels": {
      "job": "api",
      "env": "production",
      "version": "2.1.0"
    }
  },
  {
    "targets": ["api3:8080"],
    "labels": {
      "job": "api",
      "env": "staging",
      "version": "2.2.0-beta"
    }
  }
]
```

Dùng khi: **Consul/etcd/custom registry** – bên ngoài viết file, Prometheus đọc.

### 3. Kubernetes SD

```yaml
scrape_configs:
  # --- PODS ---
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: ["production", "staging"]   # chỉ các namespace này

    relabel_configs:
      # Chỉ scrape pods có annotation prometheus.io/scrape=true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"

      # Custom path từ annotation
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)

      # Custom port từ annotation
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: "([^:]+)(?::\\d+)?;(\\d+)"
        replacement: "$1:$2"
        target_label: __address__

      # Scheme (http/https) từ annotation
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scheme]
        action: replace
        regex: "(https?)"
        target_label: __scheme__

      # Copy all pod labels → Prometheus labels
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)

      # Thêm namespace label
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace

      # Thêm pod name
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod

      # Thêm container name
      - source_labels: [__meta_kubernetes_pod_container_name]
        target_label: container

      # Thêm node name
      - source_labels: [__meta_kubernetes_pod_node_name]
        target_label: node

  # --- SERVICES (endpoints) ---
  - job_name: kubernetes-services
    kubernetes_sd_configs:
      - role: endpoints

    relabel_configs:
      # Chỉ scrape services có annotation
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scrape]
        action: keep
        regex: "true"

      # Scheme
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_scheme]
        action: replace
        target_label: __scheme__
        regex: "(https?)"

      # Path
      - source_labels: [__meta_kubernetes_service_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)

      # Port
      - source_labels: [__address__, __meta_kubernetes_service_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: "([^:]+)(?::\\d+)?;(\\d+)"
        replacement: "$1:$2"

      # Service labels
      - action: labelmap
        regex: __meta_kubernetes_service_label_(.+)

      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace

      - source_labels: [__meta_kubernetes_service_name]
        target_label: service

  # --- NODES ---
  - job_name: kubernetes-nodes
    kubernetes_sd_configs:
      - role: node

    relabel_configs:
      # Dùng node IP thay vì hostname
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)

      # Kubelet metrics qua apiserver proxy
      - target_label: __address__
        replacement: "kubernetes.default.svc:443"

      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: "/api/v1/nodes/${1}/proxy/metrics"

    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token

  # --- CADVISOR ---
  - job_name: kubernetes-cadvisor
    kubernetes_sd_configs:
      - role: node

    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)

      - target_label: __address__
        replacement: "kubernetes.default.svc:443"

      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: "/api/v1/nodes/${1}/proxy/metrics/cadvisor"

    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
```

### 4. Consul SD

```yaml
scrape_configs:
  - job_name: consul-services
    consul_sd_configs:
      - server: "consul.service.consul:8500"
        token: "xxx"   # ACL token nếu bật ACL
        services: []   # [] = tất cả services
        # services: ["api", "worker"]  # hoặc filter
        tags: ["metrics"]   # chỉ services có tag "metrics"

    relabel_configs:
      # Lọc services healthy
      - source_labels: [__meta_consul_health]
        regex: passing
        action: keep

      # Port từ service metadata
      - source_labels: [__meta_consul_service_metadata_metrics_port]
        regex: (.+)
        target_label: __address__
        replacement: "${__meta_consul_address}:$1"

      # Copy service tags
      - source_labels: [__meta_consul_tags]
        regex: .*,(env-[^,]+),.*
        target_label: environment
        replacement: "$1"

      - source_labels: [__meta_consul_service]
        target_label: job

      - source_labels: [__meta_consul_node]
        target_label: instance

      - source_labels: [__meta_consul_dc]
        target_label: datacenter
```

### 5. AWS EC2 SD

```yaml
scrape_configs:
  - job_name: ec2-instances
    ec2_sd_configs:
      - region: ap-southeast-1
        access_key: xxx          # hoặc dùng IAM role
        secret_key: xxx
        port: 9100               # default port
        filters:
          - name: "tag:Environment"
            values: ["production"]
          - name: "instance-state-name"
            values: ["running"]

    relabel_configs:
      # Dùng private IP
      - source_labels: [__meta_ec2_private_ip]
        target_label: __address__
        replacement: "$1:9100"

      # Tags as labels
      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

      - source_labels: [__meta_ec2_tag_Service]
        target_label: service

      - source_labels: [__meta_ec2_availability_zone]
        target_label: zone

      - source_labels: [__meta_ec2_instance_type]
        target_label: instance_type
```

---

## How – Relabeling Deep Dive

Relabeling là **pipeline xử lý labels** trước khi scrape. Mỗi bước `relabel_config` là một transformation.

```
__meta_* labels (từ SD) → relabel_configs → labels cuối cùng trên metric

__address__     : host:port để scrape
__scheme__      : http/https
__metrics_path__ : path (default: /metrics)
__scrape_interval__, __scrape_timeout__
__param_*       : query params cho scrape URL
```

### Actions

```yaml
relabel_configs:
  # KEEP: chỉ giữ targets match regex
  - source_labels: [__meta_kubernetes_pod_phase]
    regex: Running
    action: keep

  # DROP: bỏ targets match regex
  - source_labels: [__meta_kubernetes_pod_annotation_no_metrics]
    regex: "true"
    action: drop

  # REPLACE: rename/modify label (default action)
  - source_labels: [__meta_kubernetes_namespace]
    target_label: namespace
    # nếu không có regex: copy as-is

  # REPLACE với regex capture group
  - source_labels: [__meta_kubernetes_pod_name]
    regex: "(.+)-[a-z0-9]+-[a-z0-9]+"  # strip pod hash suffix
    replacement: "$1"
    target_label: app_name

  # LABELMAP: copy nhiều labels khớp pattern
  - action: labelmap
    regex: __meta_kubernetes_pod_label_(.+)  # strip prefix, copy the rest

  # LABELDROP: xóa labels khớp pattern (sau khi scrape)
  - action: labeldrop
    regex: "__meta_.*"   # xóa tất cả meta labels

  # LABELKEEP: chỉ giữ labels khớp pattern
  - action: labelkeep
    regex: "job|instance|namespace|pod|container|service"

  # HASHMOD: sharding (chia targets cho nhiều Prometheus instance)
  - source_labels: [__address__]
    target_label: __tmp_hash
    modulus: 3          # 3 shards
    action: hashmod
  - source_labels: [__tmp_hash]
    regex: "0"          # shard 0 chỉ scrape targets hash % 3 == 0
    action: keep
```

### Metric Relabeling (metric_relabel_configs)

Chạy **sau khi scrape**, trước khi lưu vào TSDB. Dùng để lọc, drop metrics không cần thiết.

```yaml
scrape_configs:
  - job_name: expensive-exporter
    static_configs:
      - targets: ["exporter:9999"]

    metric_relabel_configs:
      # Drop metrics không cần thiết (giảm cardinality)
      - source_labels: [__name__]
        regex: "go_gc_.*|go_memstats_.*|process_.*"
        action: drop

      # Drop high-cardinality labels
      - source_labels: [uuid]
        target_label: uuid
        replacement: ""
        regex: ".*"

      # Rename metrics
      - source_labels: [__name__]
        regex: "old_metric_name_(.*)"
        replacement: "new_metric_name_$1"
        target_label: __name__

      # Thêm label từ metric value (labelmap trên metric labels)
      - action: labelmap
        regex: "exported_(.*)"
```

---

## Components – Kubernetes RBAC cho Prometheus

```yaml
# ServiceAccount + ClusterRole để Prometheus discover K8s objects
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
  - apiGroups: [""]
    resources: [nodes, nodes/proxy, nodes/metrics, services, endpoints, pods]
    verbs: [get, list, watch]
  - apiGroups: [extensions, networking.k8s.io]
    resources: [ingresses]
    verbs: [get, list, watch]
  - nonResourceURLs: [/metrics, /metrics/cadvisor]
    verbs: [get]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: monitoring
```

### ServiceMonitor (Prometheus Operator)

```yaml
# Prometheus Operator: không viết scrape_configs tay,
# dùng ServiceMonitor CRD để declare targets
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api-service-monitor
  namespace: monitoring
  labels:
    release: kube-prometheus-stack   # match với Prometheus selector
spec:
  namespaceSelector:
    matchNames: ["production"]
  selector:
    matchLabels:
      app: api                        # chọn Service có label này
  endpoints:
    - port: metrics                   # tên port trong Service spec
      path: /actuator/prometheus
      interval: 30s
      scheme: http
      tlsConfig:
        insecureSkipVerify: false
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_name]
          targetLabel: pod
      metricRelabelings:
        - sourceLabels: [__name__]
          regex: "jvm_gc_pause_.*"
          action: drop
```

---

## Compare – SD Mechanisms

| SD Type | Dùng khi | Dynamic | Metadata |
|---------|----------|---------|---------|
| static | Lab, VM cố định | Không | Label thủ công |
| file | Custom registry, hybrid | Có (file watch) | Tùy |
| kubernetes | K8s cluster | Có | Pod/service annotations & labels |
| consul | Service mesh, multi-DC | Có | Tags, metadata |
| ec2 | AWS VMs | Có | Tags, AZ, type |
| dns | Simple lookup | Có | Ít |

---

## Trade-offs

```
Kubernetes SD:
✅ Native, không cần gì thêm
✅ Rất nhiều metadata (labels, annotations, node info)
❌ Chỉ dùng trong K8s cluster
❌ RBAC phức tạp hơn

File SD:
✅ Universal, hoạt động với bất kỳ registry nào
✅ Tự viết script generate targets
❌ Cần mechanism bên ngoài update file
❌ Delay 1 refresh_interval khi có thay đổi

Consul SD:
✅ Tốt cho multi-DC, multi-cloud
✅ Health check tích hợp
❌ Cần Consul cluster
❌ Thêm dependency
```

---

## Real-world – Pod Annotation Pattern

```yaml
# Thêm annotations vào Deployment để Prometheus tự discover
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/actuator/prometheus"
        prometheus.io/scheme: "http"
      labels:
        app: api
        version: "2.1.0"
        team: backend
```

### Debug Service Discovery

```bash
# Xem tất cả targets (discovered, dropped, active)
curl localhost:9090/api/v1/targets | jq '.data'

# Xem chỉ active targets
curl localhost:9090/api/v1/targets?state=active | jq '.data.activeTargets[] | {job: .labels.job, instance: .labels.instance, health: .health}'

# Xem dropped targets (để debug relabeling)
curl localhost:9090/api/v1/targets?state=dropped | jq '.data.droppedTargets[0].discoveredLabels'

# Prometheus UI: Status → Targets, Status → Service Discovery
# http://localhost:9090/targets
# http://localhost:9090/service-discovery
```

---

## Ghi chú – Chủ đề tiếp theo
> `prometheus_production.md`: Federation, Thanos, Cortex, VictoriaMetrics – HA và long-term storage

---

*Cập nhật lần cuối: 2026-05-06*
