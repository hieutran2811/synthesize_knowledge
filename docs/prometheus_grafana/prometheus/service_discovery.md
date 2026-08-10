---
title: "Prometheus Service Discovery và Relabeling – Từ metadata đến scrape target"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 17
---
# Prometheus Service Discovery và Relabeling – Từ metadata đến scrape target

> Thuật ngữ: [Glossary](../glossary.md).

> Phiên bản mục tiêu: **Prometheus 3.13.x**.
>
> Điều kiện đầu vào: đã đọc [Prometheus Fundamentals](prometheus_fundamentals.md) và [PromQL, Recording Rules, Alerting Rules](prometheus_advanced.md).

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- phân biệt discovery, target relabeling, scrape và metric relabeling;
- chọn đúng discovery mechanism cho static host, file, Kubernetes, Consul hoặc cloud;
- đọc được các internal label như `__address__`, `__meta_*`, `__param_*`;
- viết relabel rule có thứ tự, regex và capture group chính xác;
- dùng Kubernetes `EndpointSlice` và Prometheus Operator đúng selector chain;
- kiểm soát cardinality thay vì copy toàn bộ metadata thành metric label;
- chẩn đoán target “không xuất hiện”, “bị drop” hoặc “xuất hiện nhưng scrape fail”.

---

## 2. Service Discovery thực sự làm gì?

Service discovery trả lời:

```text
“Prometheus nên thử scrape những địa chỉ nào,
 và mỗi địa chỉ có metadata gì?”
```

Nó chưa khẳng định target sống, endpoint đúng hoặc response hợp lệ.

```text
Registry / API / file / DNS
        │
        ▼
Discovered target groups
        │ internal metadata: __meta_*
        ▼
Target relabeling
        │ keep/drop/rewrite URL + target labels
        ▼
Active scrape target
        │ HTTP GET
        ▼
Scraped samples
        │ metric relabeling
        ▼
Accepted samples
        │ sample/label limits
        ▼
TSDB
```

Ba trạng thái thường bị nhầm:

| Trạng thái | Ý nghĩa |
|---|---|
| Không được discover | SD API/file/DNS/RBAC/selector không trả target. |
| Discovered nhưng bị drop | Một target relabel rule loại target trước khi scrape. |
| Active nhưng `up == 0` | Target qua relabeling nhưng HTTP scrape thất bại. |

Service discovery đồng bộ theo watch/refresh của từng cơ chế. Không nên diễn giải là “luôn chính xác tức thời”: API outage, permission, cache, refresh interval và network partition đều có thể tạo độ trễ.

---

## 3. Hai loại label ở hai thời điểm

### Discovered labels

Đến từ discovery mechanism:

```text
__address__="10.1.2.3:8080"
__meta_kubernetes_namespace="production"
__meta_kubernetes_service_name="shop-api"
__meta_kubernetes_pod_name="shop-api-7f6d9..."
job="kubernetes-endpointslice"
```

Chúng là đầu vào của `relabel_configs`.

### Final target labels

Sau target relabeling:

```text
job="kubernetes-endpointslice"
instance="10.1.2.3:8080"
namespace="production"
service="shop-api"
pod="shop-api-7f6d9..."
```

Các label này được gắn vào sample khi scrape, trừ khi xảy ra label conflict theo `honor_labels`.

### Vòng đời internal labels

```text
__meta_*     → metadata chỉ tồn tại trong target relabeling
__address__  → địa chỉ Prometheus sẽ kết nối
__scheme__   → http hoặc https
__metrics_path__ → path, mặc định /metrics
__param_x    → query parameter x
__tmp*       → biến tạm giữa các relabel step
```

Sau target relabeling:

- label bắt đầu bằng `__` bị loại;
- `instance` mặc định lấy final `__address__` nếu chưa được đặt;
- muốn giữ metadata, phải copy rõ sang label không bắt đầu bằng `__`.

Ví dụ:

```yaml
- source_labels: [__meta_kubernetes_namespace]
  target_label: namespace
  action: replace
```

---

## 4. Pipeline đầy đủ và điểm đặt policy

```text
1. Discovery
   input: API/file/DNS
   output: target + __meta_* labels

2. relabel_configs
   input: discovered target labels
   output: active hoặc dropped target
   có thể đổi URL scrape và target labels

3. Scrape
   input: final URL + auth/TLS
   output: exposed samples hoặc scrape error

4. Label conflict handling
   target labels được gắn vào exposed samples

5. metric_relabel_configs
   input: từng scraped sample
   output: keep/drop/rewrite sample trước ingest

6. Scrape limits
   vượt giới hạn → cả scrape có thể bị xem là failed

7. TSDB
   lưu accepted samples
```

Điểm quan trọng:

- drop target ở bước 2 tiết kiệm cả network và parse cost;
- drop metric ở bước 5 vẫn phải tải và parse response;
- metric relabeling không áp dụng cho series tự sinh như `up`;
- `sample_limit` được xét sau metric relabeling;
- vượt sample/label limit không “cắt bớt”, mà có thể làm toàn scrape fail.

---

## 5. Chọn discovery mechanism

| Cơ chế | Phù hợp khi | Metadata | Đổi target |
|---|---|---|---|
| `static_configs` | Lab, appliance hoặc VM rất ổn định | Khai báo tay | Sửa/reload config |
| `file_sd_configs` | Custom registry hoặc automation sinh file | Tùy file | File watch + refresh fallback |
| `http_sd_configs` | Registry cung cấp HTTP endpoint theo schema Prometheus | Tùy response | Poll HTTP |
| `dns_sd_configs` | DNS A/AAAA/SRV là source of truth | Ít | Theo DNS refresh |
| `kubernetes_sd_configs` | Kubernetes | Rất nhiều | LIST/WATCH API |
| `consul_sd_configs` | Consul catalog/health | Service/node metadata | Consul API |
| Cloud SD | VM/service cloud | Tags, zone, instance metadata | Cloud API refresh |

Nguyên tắc chọn:

1. dùng source of truth đang quản lý lifecycle target;
2. filter sớm tại API nếu giảm tải đáng kể;
3. relabel tiếp để tạo contract label ổn định;
4. không biến toàn bộ metadata của registry thành metric labels.

---

## 6. Static configuration

```yaml
scrape_configs:
  - job_name: node
    scrape_interval: 30s
    static_configs:
      - targets:
          - "node-1.internal:9100"
          - "node-2.internal:9100"
        labels:
          environment: production
          region: ap-southeast-1
```

Ưu điểm:

- dễ hiểu, dễ review;
- không cần quyền tới registry;
- tốt cho lab và target ổn định.

Nhược điểm:

- target lifecycle và config dễ lệch nhau;
- scale/replacement cần automation;
- một IP tái sử dụng có thể đổi identity nhưng vẫn giữ label cũ.

Static config không đồng nghĩa “không cần relabeling”. Có thể dùng relabel để normalize `instance` hoặc shard target giống các SD khác.

---

## 7. File-based Service Discovery

`prometheus.yml`:

```yaml
scrape_configs:
  - job_name: file-sd-api
    file_sd_configs:
      - files:
          - "/etc/prometheus/targets/api_*.yml"
        refresh_interval: 5m

    relabel_configs:
      - source_labels: [__meta_filepath]
        target_label: discovery_file
```

`/etc/prometheus/targets/api_production.yml`:

```yaml
- targets:
    - "api-1.internal:8080"
    - "api-2.internal:8080"
  labels:
    environment: production
    service: shop-api
```

Prometheus theo dõi thay đổi file và cả parent directory; `refresh_interval` là fallback re-read định kỳ, không phải cơ chế duy nhất.

### Ghi file an toàn

Không truncate rồi ghi dần file đang được đọc:

```text
Sai:
  mở api.yml → truncate → ghi từng phần

Tốt:
  ghi api.yml.tmp hoàn chỉnh
  validate
  atomic rename thành api.yml
```

Chỉ file target group hợp lệ mới được áp dụng. Dù vậy, automation nên:

- validate JSON/YAML trước rename;
- ghi file tạm cùng filesystem;
- đặt ownership/permission rõ;
- không đặt hàng nghìn file không liên quan trong cùng parent directory;
- theo dõi tuổi file và số target sinh ra.

### `__meta_filepath`

Mỗi target từ file SD có `__meta_filepath`, hữu ích để:

- gắn source/owner;
- route target theo nhóm file;
- điều tra generator nào tạo target sai.

Không nên đưa full path chứa dữ liệu nhạy cảm thành metric label nếu không cần.

---

## 8. Kubernetes SD: chọn đúng role

Prometheus hỗ trợ:

| Role | Một target đại diện cho | Use case phổ biến |
|---|---|---|
| `pod` | Pod/container port được discover | Scrape trực tiếp pod |
| `endpointslice` | Backend endpoint của Service | Scrape workload sau Service selection |
| `endpoints` | Legacy Endpoints backend | Hệ thống chưa migrate |
| `service` | Service port/DNS | Blackbox probe hoặc scrape Service VIP |
| `node` | Kubernetes Node | Kubelet/node-oriented target |
| `ingress` | Host/path của Ingress | Blackbox probe |

### `service` không phải backend pods

`role: service` tạo target cho Service port và thường trỏ tới Kubernetes DNS của Service. Nó phù hợp để probe “Service có truy cập được không?”, không cho identity riêng của từng pod backend.

Muốn scrape từng backend, dùng `endpointslice` hoặc `pod`.

### Ưu tiên EndpointSlice

EndpointSlice stable từ Kubernetes 1.21 và là API có khả năng scale tốt hơn. Legacy `v1 Endpoints` đã deprecated từ Kubernetes 1.33; learning path này ưu tiên `role: endpointslice`.

Một Service có thể có nhiều EndpointSlice và endpoint có thể tạm xuất hiện trùng trong lúc update. Dùng implementation SD của Prometheus/Operator thay vì tự viết script giả định “một Service = một EndpointSlice”.

---

## 9. Raw Kubernetes EndpointSlice configuration

Ví dụ chỉ scrape Service opt-in bằng label:

```yaml
scrape_configs:
  - job_name: kubernetes-endpointslice
    scrape_interval: 30s
    scrape_timeout: 10s

    kubernetes_sd_configs:
      - role: endpointslice
        namespaces:
          names:
            - production

    relabel_configs:
      # Service phải opt-in.
      - source_labels:
          - __meta_kubernetes_service_label_observability_example_com_scrape
        regex: "true"
        action: keep

      # Chỉ port có tên metrics.
      - source_labels:
          - __meta_kubernetes_endpointslice_port_name
        regex: "metrics"
        action: keep

      # Chỉ endpoint ready theo policy của hệ thống.
      - source_labels:
          - __meta_kubernetes_endpointslice_endpoint_conditions_ready
        regex: "true"
        action: keep

      # Copy có chọn lọc metadata cần cho query/alert.
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace

      - source_labels: [__meta_kubernetes_service_name]
        target_label: service

      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod

      - source_labels: [__meta_kubernetes_pod_container_name]
        target_label: container

      - source_labels:
          - __meta_kubernetes_endpointslice_endpoint_node_name
        target_label: node

      - source_labels:
          - __meta_kubernetes_endpointslice_endpoint_zone
        target_label: zone
```

Service opt-in:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shop-api
  namespace: production
  labels:
    app.kubernetes.io/name: shop-api
    observability.example.com/scrape: "true"
spec:
  selector:
    app.kubernetes.io/name: shop-api
  ports:
    - name: metrics
      port: 8080
      targetPort: metrics
```

Container cần khai báo port name khớp:

```yaml
ports:
  - name: metrics
    containerPort: 8080
```

### Tại sao không `labelmap` toàn bộ Kubernetes labels?

Cấu hình sau rất tiện nhưng rủi ro:

```yaml
- action: labelmap
  regex: "__meta_kubernetes_pod_label_(.+)"
```

Nó có thể biến mọi label Git SHA, rollout ID, Helm revision hoặc label do team khác thêm thành metric label:

```text
metadata thay đổi
  → time series identity đổi
  → series churn/cardinality tăng
  → dashboard/rule label contract đổi
```

Hãy copy allowlist rõ:

```yaml
- source_labels:
    - __meta_kubernetes_service_label_app_kubernetes_io_name
  target_label: app

- source_labels:
    - __meta_kubernetes_service_label_app_kubernetes_io_component
  target_label: component
```

---

## 10. Pod annotation pattern: convention, không phải tính năng tự động

Các annotation như:

```text
prometheus.io/scrape
prometheus.io/path
prometheus.io/scheme
```

không có ý nghĩa đặc biệt với raw Prometheus nếu bạn chưa viết relabel rules hoặc dùng chart/operator sinh rules tương ứng.

Ví dụ:

```yaml
scrape_configs:
  - job_name: kubernetes-pods-opt-in
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names: [production]

    relabel_configs:
      - source_labels:
          - __meta_kubernetes_pod_annotation_prometheus_io_scrape
        regex: "true"
        action: keep

      - source_labels:
          - __meta_kubernetes_pod_phase
        regex: "Running"
        action: keep

      - source_labels:
          - __meta_kubernetes_pod_container_port_name
        regex: "metrics"
        action: keep

      - source_labels:
          - __meta_kubernetes_pod_annotation_prometheus_io_scheme
        regex: "(https?)"
        target_label: __scheme__
        action: replace

      - source_labels:
          - __meta_kubernetes_pod_annotation_prometheus_io_path
        regex: "(/.*)"
        target_label: __metrics_path__
        replacement: "${1}"
        action: replace

      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace

      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod

      - source_labels: [__meta_kubernetes_pod_container_name]
        target_label: container
```

Deployment:

```yaml
spec:
  template:
    metadata:
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/path: "/actuator/prometheus"
        prometheus.io/scheme: "http"
    spec:
      containers:
        - name: app
          ports:
            - name: metrics
              containerPort: 8080
```

Named port tránh regex tự ghép host/port và dễ review hơn. Nếu cần port từ annotation, phải xử lý IPv4/IPv6 và validate port chặt, không chỉ nối string tùy ý.

---

## 11. Kubernetes API selectors và relabel filters

Hai nơi có thể filter:

```text
Kubernetes selectors:
  giảm object trả từ API

Relabel keep/drop:
  API trả object trước, Prometheus lọc target sau
```

Ví dụ selector:

```yaml
kubernetes_sd_configs:
  - role: pod
    selectors:
      - role: pod
        label: "observability.example.com/scrape=true"
```

Selector hữu ích khi chỉ monitor một subset nhỏ trong cluster rất lớn. Tuy nhiên mỗi tổ hợp selector có thể tạo LIST/WATCH riêng và ngăn Prometheus tái sử dụng cùng một watch giữa scrape configs.

Chọn bằng đo lường:

- ít scrape config, subset rất nhỏ → selector có thể giảm tải;
- nhiều scrape config với selector khác nhau → API server/watch cost có thể tăng;
- relabeling tập trung dễ quản lý nhưng nhận nhiều metadata hơn.

---

## 12. RBAC tối thiểu cho EndpointSlice

Ví dụ raw Prometheus chạy trong namespace `monitoring` và discover toàn cluster:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus-discovery
rules:
  - apiGroups: [""]
    resources:
      - pods
      - services
    verbs:
      - get
      - list
      - watch
  - apiGroups: ["discovery.k8s.io"]
    resources:
      - endpointslices
    verbs:
      - get
      - list
      - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus-discovery
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus-discovery
subjects:
  - kind: ServiceAccount
    name: prometheus
    namespace: monitoring
```

Nếu bật `attach_metadata.node: true`, Prometheus còn cần list/watch Nodes. Nếu chỉ discover một vài namespace, cân nhắc Role/RoleBinding theo namespace thay vì ClusterRole.

Không copy một manifest RBAC “đọc mọi resource” cho tiện. Permission phải khớp role SD và metadata thực sự dùng.

Kiểm tra:

```bash
kubectl auth can-i \
  --as=system:serviceaccount:monitoring:prometheus \
  list endpointslices.discovery.k8s.io \
  --all-namespaces

kubectl auth can-i \
  --as=system:serviceaccount:monitoring:prometheus \
  watch pods \
  --all-namespaces
```

---

## 13. Prometheus Operator: selector chain

Mental model:

```text
Prometheus CR
  │ serviceMonitorSelector + namespace selector
  ▼
ServiceMonitor
  │ selector + namespaceSelector
  ▼
Service
  │ spec.selector
  ▼
EndpointSlice
  │ endpoints + named port
  ▼
Pods
```

Một selector sai ở bất kỳ tầng nào đều tạo “không có target”.

### Service + ServiceMonitor

Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: shop-api
  namespace: production
  labels:
    app.kubernetes.io/name: shop-api
spec:
  selector:
    app.kubernetes.io/name: shop-api
  ports:
    - name: metrics
      port: 8080
      targetPort: metrics
```

ServiceMonitor:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: shop-api
  namespace: monitoring
  labels:
    monitoring.example.com/owner: platform
spec:
  serviceDiscoveryRole: EndpointSlice
  namespaceSelector:
    matchNames:
      - production
  selector:
    matchLabels:
      app.kubernetes.io/name: shop-api
  targetLabels:
    - app.kubernetes.io/name
  sampleLimit: 20000
  endpoints:
    - port: metrics
      path: /actuator/prometheus
      scheme: http
      interval: 30s
      scrapeTimeout: 10s
      relabelings:
        - sourceLabels: [__meta_kubernetes_pod_name]
          targetLabel: pod
      metricRelabelings:
        - sourceLabels: [__name__]
          regex: "application_debug_.*"
          action: drop
```

Điểm cần nhớ:

- `ServiceMonitor.spec.selector` chọn **Service**, không chọn Deployment/Pod;
- `endpoints[].port` là **tên port trên Service**, không phải số port;
- Service tiếp tục chọn Pods bằng `Service.spec.selector`;
- `targetLabels` chỉ copy label được allowlist từ Service;
- `relabelings` là target relabeling;
- `metricRelabelings` là sample relabeling.

### Prometheus CR chọn ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: platform
  namespace: monitoring
spec:
  serviceDiscoveryRole: EndpointSlice
  serviceMonitorSelector:
    matchLabels:
      monitoring.example.com/owner: platform
  serviceMonitorNamespaceSelector:
    matchLabels:
      observability.example.com/enabled: "true"
```

ServiceMonitor ở namespace không được Prometheus CR chọn sẽ không vào generated configuration, dù ServiceMonitor YAML hoàn toàn hợp lệ.
Với ví dụ trên, namespace `monitoring` cũng phải có label `observability.example.com/enabled="true"`.

### Khi dùng PodMonitor?

```text
ServiceMonitor:
  muốn scrape backend qua Service/EndpointSlice
  contract port nằm ở Service

PodMonitor:
  muốn chọn Pod trực tiếp
  không cần Service
  contract port nằm ở container
```

Probe dùng cho blackbox target; `ScrapeConfig` CRD dùng khi cần biểu diễn scrape config ngoài abstractions ServiceMonitor/PodMonitor.

---

## 14. Consul SD

```yaml
scrape_configs:
  - job_name: consul-services
    consul_sd_configs:
      - server: "consul.service.consul:8501"
        scheme: https
        services:
          - shop-api
          - payment-api
        tls_config:
          ca_file: /etc/prometheus/tls/consul-ca.crt

    relabel_configs:
      - source_labels: [__meta_consul_health]
        regex: "passing"
        action: keep

      - source_labels: [__meta_consul_service]
        target_label: service

      - source_labels: [__meta_consul_node]
        target_label: consul_node

      - source_labels: [__meta_consul_dc]
        target_label: datacenter

      - source_labels:
          - __meta_consul_address
          - __meta_consul_service_metadata_metrics_port
        separator: ";"
        regex: "(.+);([0-9]+)"
        replacement: "${1}:${2}"
        target_label: __address__
```

Nếu Consul cần token, quản lý secret bằng cơ chế deployment/secret store phù hợp và giới hạn read permission; không commit token thật vào repository.

### Capture group, không phải biến label

Sai:

```yaml
replacement: "${__meta_consul_address}:$1"
```

`replacement` chỉ hiểu regex capture group như `${1}`, `${2}`; nó không nội suy label bằng tên. Muốn dùng nhiều label, đặt chúng trong `source_labels`, chọn `separator` và capture từng phần.

---

## 15. AWS EC2 SD

```yaml
scrape_configs:
  - job_name: ec2-node
    ec2_sd_configs:
      - region: ap-southeast-1
        port: 9100
        refresh_interval: 60s
        filters:
          - name: instance-state-name
            values: [running]
          - name: "tag:Monitoring"
            values: [enabled]
          - name: "tag:Environment"
            values: [production]

    relabel_configs:
      - source_labels: [__meta_ec2_private_ip]
        regex: "(.+)"
        replacement: "${1}:9100"
        target_label: __address__

      - source_labels: [__meta_ec2_instance_id]
        target_label: ec2_instance_id

      - source_labels: [__meta_ec2_tag_Name]
        target_label: instance_name

      - source_labels: [__meta_ec2_tag_Service]
        target_label: service

      - source_labels: [__meta_ec2_availability_zone]
        target_label: zone
```

Ưu tiên IAM role/workload identity/default credential chain. Không đặt `access_key` và `secret_key` trực tiếp trong config hoặc tài liệu copy-paste production.

Cloud tags cũng là input không hoàn toàn tin cậy:

- tag key được sanitize thành meta label name;
- tag value có thể đổi và tạo series churn;
- tag có thể chứa dữ liệu không nên lộ trong UI/API;
- chỉ copy allowlist tags có owner và cardinality bounded.

---

## 16. Relabel rule được thực thi thế nào?

Một rule:

```yaml
- source_labels: [label_a, label_b]
  separator: ";"
  regex: "(.+);(.+)"
  replacement: "${1}-${2}"
  target_label: combined
  action: replace
```

Các bước:

```text
1. Lấy value label_a và label_b
2. Label thiếu → chuỗi rỗng
3. Nối bằng separator, mặc định ";"
4. Match regex RE2, mặc định "(.*)"
5. Thực hiện action
6. Output trở thành input cho rule kế tiếp
```

Regex được anchor toàn bộ:

```text
regex: "api"
  match đúng "api", không match "shop-api-v2"

regex: ".*api.*"
  match chuỗi có chứa "api"
```

RE2 không hỗ trợ lookaround và backreference trong pattern như một số PCRE engine.

### Thứ tự là logic chương trình

```yaml
# 1. Tạo label tạm
- source_labels: [__meta_kubernetes_namespace]
  target_label: __tmp_namespace

# 2. Dùng label tạm
- source_labels: [__tmp_namespace, __meta_kubernetes_service_name]
  separator: "/"
  target_label: workload

# 3. __tmp* tự bị loại sau target relabeling
```

Đảo rule 1 và 2 sẽ tạo output khác.

---

## 17. Các relabel actions

| Action | Làm gì |
|---|---|
| `replace` | Ghi `replacement` vào `target_label` nếu regex match. |
| `keep` | Drop target/sample khi regex **không** match. |
| `drop` | Drop target/sample khi regex match. |
| `keepequal` | Giữ khi source value bằng value hiện tại của `target_label`. |
| `dropequal` | Drop khi source value bằng value hiện tại của `target_label`. |
| `lowercase` | Chuyển concatenated source value thành chữ thường. |
| `uppercase` | Chuyển thành chữ hoa. |
| `hashmod` | Hash source rồi lấy modulo. |
| `labelmap` | Match trên **label names**, copy sang tên mới. |
| `labeldrop` | Xóa label có tên match regex. |
| `labelkeep` | Chỉ giữ label có tên match regex. |

### `replace`

```yaml
- source_labels: [__meta_kubernetes_namespace]
  regex: "(.+)"
  replacement: "${1}"
  target_label: namespace
  action: replace
```

Với default `regex: (.*)`, `replacement: $1`, có thể viết gọn:

```yaml
- source_labels: [__meta_kubernetes_namespace]
  target_label: namespace
```

### `keep` và `drop`

```yaml
- source_labels: [environment]
  regex: "production|staging"
  action: keep

- source_labels: [__meta_kubernetes_pod_phase]
  regex: "Succeeded|Failed"
  action: drop
```

Đặt filter rẻ và loại nhiều target lên sớm để các rule sau xử lý ít target hơn.

### `lowercase`

```yaml
- source_labels: [__meta_ec2_tag_Environment]
  target_label: environment
  action: lowercase
```

Normalization có thể làm hai giá trị trước đây khác nhau trở thành cùng label set. Phải kiểm tra uniqueness trước khi deploy.

### `labelmap`

```yaml
- action: labelmap
  regex: "__meta_kubernetes_service_label_observability_example_com_(.+)"
  replacement: "${1}"
```

Pattern hẹp này chỉ copy namespace label do platform sở hữu, an toàn hơn copy toàn bộ Service/Pod labels.

### `labeldrop` và `labelkeep`

```yaml
- action: labeldrop
  regex: "build_sha|deployment_uid"
```

Nếu hai series chỉ khác nhau ở label bị xóa, chúng có thể trở thành duplicate cùng timestamp/label set và làm scrape fail hoặc dữ liệu không còn đúng identity.

---

## 18. Target relabeling và metric relabeling

### Target relabeling

```yaml
relabel_configs:
  - source_labels: [__meta_kubernetes_service_name]
    regex: "shop-api"
    action: keep
```

Chạy một lần trên mỗi discovered target trước scrape.

Phù hợp:

- chọn/bỏ target;
- đổi address, scheme, path, params;
- tạo target labels;
- phân shard target.

### Metric relabeling

```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: "application_debug_.*"
    action: drop

  - action: labeldrop
    regex: "request_id|session_id"
```

Chạy trên từng sample sau scrape, trước ingest.

Phù hợp:

- drop metric family không cần;
- bỏ/normalize sample labels;
- đổi metric name có migration plan;
- bảo vệ TSDB khỏi một subset đắt.

Không phù hợp:

- tiết kiệm network tới target;
- sửa target URL;
- drop series `up` tự sinh;
- cứu exporter trả response quá lớn trước khi parse.

### Các relabel stage khác

| Stage | Vị trí |
|---|---|
| `relabel_configs` | Trước scrape, trên target. |
| `metric_relabel_configs` | Trước local ingest, trên scraped samples. |
| `write_relabel_configs` | Trước từng remote write destination. |
| `alert_relabel_configs` | Trước gửi alert sang Alertmanager, sau external labels. |

Không copy một rule giữa các stage mà không xét available labels và mục đích.

---

## 19. Label conflict và `honor_labels`

Target có label:

```text
job="shop-api"
instance="10.1.2.3:8080"
```

Exporter lại expose:

```text
some_metric{job="internal-worker"} 1
```

Mặc định `honor_labels: false`:

```text
some_metric{
  job="shop-api",
  exported_job="internal-worker",
  instance="10.1.2.3:8080"
} 1
```

Với `honor_labels: true`, label từ scraped data được giữ khi conflict và target label tương ứng không thắng.

Thông thường:

- scrape trực tiếp application/exporter: để default false, target identity do monitoring config kiểm soát;
- federation/Pushgateway có semantics đặc biệt và có thể cần `honor_labels: true`;
- không bật chỉ để “làm mất exported_job”.

Nếu exporter vô tình tạo label `cluster`, `namespace` hoặc `service`, cần sửa contract rõ ràng thay vì phụ thuộc conflict behavior.

---

## 20. Sharding target bằng `hashmod`

Prometheus shard 0/2:

```yaml
relabel_configs:
  - source_labels: [__address__]
    modulus: 2
    target_label: __tmp_shard
    action: hashmod

  - source_labels: [__tmp_shard]
    regex: "0"
    action: keep
```

Shard 1 dùng cùng rule nhưng `regex: "1"`.

### Sharding không phải HA

```text
Sharding:
  mỗi target thường chỉ thuộc một shard
  shard chết → phần target đó không được scrape

HA replicas:
  hai replica chạy cùng shard selection
  mỗi target của shard được cả hai replica scrape
```

Thay `modulus` làm nhiều target đổi shard cùng lúc, gây series ownership movement, cache cold và query/dedup considerations. Cần rollout/migration plan.

Hash key phải ổn định. Hash `__address__` sẽ đổi khi pod IP đổi; đôi khi muốn hash trên stable workload identity, nhưng phải đảm bảo uniqueness và phân bố đều.

---

## 21. Multi-target exporter pattern

Blackbox Exporter là một scrape target nhưng probe một target khác.

Scrape config:

```yaml
scrape_configs:
  - job_name: blackbox-http
    metrics_path: /probe
    params:
      module: [http_2xx]

    static_configs:
      - targets:
          - "https://shop.example.com/health"
          - "https://payment.example.com/health"

    relabel_configs:
      # Target gốc trở thành query parameter target.
      - source_labels: [__address__]
        target_label: __param_target

      # Giữ target được probe làm identity dễ đọc.
      - source_labels: [__param_target]
        target_label: instance

      # Prometheus thực sự kết nối Blackbox Exporter.
      - target_label: __address__
        replacement: "blackbox-exporter.monitoring.svc:9115"
```

Final scrape URL:

```text
http://blackbox-exporter.monitoring.svc:9115/probe
  ?target=https://shop.example.com/health
  &module=http_2xx
```

Đừng để URL chứa token/secret trong `instance`, `__param_target` hoặc UI discovery.

---

## 22. Scrape guardrails

```yaml
scrape_configs:
  - job_name: third-party-exporter
    sample_limit: 50000
    label_limit: 40
    label_name_length_limit: 100
    label_value_length_limit: 500
    target_limit: 500
    keep_dropped_targets: 1000

    static_configs:
      - targets: ["exporter.internal:9999"]
```

Semantics:

| Guardrail | Khi vượt |
|---|---|
| `sample_limit` | Cả scrape fail nếu post-metric-relabel samples vượt giới hạn. |
| `label_limit` | Cả scrape fail nếu một sample có quá nhiều labels. |
| `label_*_length_limit` | Cả scrape fail nếu label name/value quá dài. |
| `target_limit` | Targets của scrape config bị đánh dấu failed, không scrape. |
| `keep_dropped_targets` | Giới hạn dropped targets giữ trong memory/UI. |

`target_limit` và một số body-related guardrail còn được tài liệu đánh dấu experimental; kiểm tra release notes trước khi coi behavior là API ổn định.

Theo dõi:

```promql
scrape_samples_scraped
scrape_samples_post_metric_relabeling
scrape_series_added
scrape_duration_seconds
up
```

Tỷ lệ giữ lại:

```promql
scrape_samples_post_metric_relabeling
/
scrape_samples_scraped
```

Nếu metric relabel drop 99% sample, exporter vẫn gửi và Prometheus vẫn parse chúng. Tốt hơn là tắt collector/metric tại source nếu có thể.

---

## 23. Debug Service Discovery theo tầng

### Tầng 1 – config parse được?

```bash
promtool check config prometheus.yml
```

### Tầng 2 – discovery + relabel trả gì?

```bash
promtool check service-discovery prometheus.yml kubernetes-endpointslice
```

Command cần quyền/network giống môi trường chạy và chờ discovery result trong timeout.

### Tầng 3 – Prometheus runtime thấy target nào?

```bash
curl -fsS \
  "http://localhost:9090/api/v1/targets?state=active"

curl -fsS \
  "http://localhost:9090/api/v1/targets?state=dropped"
```

Trong response:

- `discoveredLabels`: trước target relabeling;
- `labels`: sau relabeling;
- `scrapeUrl`: URL cuối;
- `health` và `lastError`: kết quả scrape;
- `scrapePool`: job/scrape pool.

### Tầng 4 – xem từng relabel step

Prometheus 3.12+ có endpoint thử nghiệm phục vụ UI:

```text
GET /api/v1/targets/relabel_steps
```

Nó cho biết label set thay đổi sau từng rule, rất hữu ích khi target bị drop. Endpoint này experimental; không xây automation phụ thuộc response schema.

### Tầng 5 – gọi final URL

Từ network context tương đương Prometheus:

```bash
curl -fsS \
  --max-time 10 \
  "http://10.1.2.3:8080/actuator/prometheus"
```

Nếu có TLS/auth, dùng cùng CA, server name và credential contract; không dùng `-k` như một “fix” production.

### Tầng 6 – sample có bị metric relabel drop?

So sánh:

```promql
scrape_samples_scraped
scrape_samples_post_metric_relabeling
```

Query metric name trực tiếp và kiểm tra final labels.

---

## 24. Debug selector chain của ServiceMonitor

### 1. Prometheus CR có chọn ServiceMonitor?

```bash
kubectl get prometheus -n monitoring platform -o yaml
kubectl get servicemonitor -n monitoring shop-api --show-labels
```

So `serviceMonitorSelector` và `serviceMonitorNamespaceSelector`.

### 2. ServiceMonitor có chọn Service?

```bash
kubectl get service \
  -n production \
  -l app.kubernetes.io/name=shop-api \
  --show-labels
```

### 3. Service có chọn Pods?

```bash
kubectl get pods \
  -n production \
  -l app.kubernetes.io/name=shop-api \
  -o wide
```

### 4. EndpointSlice có endpoint ready và đúng port?

```bash
kubectl get endpointslice \
  -n production \
  -l kubernetes.io/service-name=shop-api \
  -o wide
```

### 5. Port name có khớp?

```text
ServiceMonitor endpoints.port
  = Service spec.ports[].name

Service targetPort
  = container port name hoặc port number phù hợp
```

`port: metrics` đúng; `port: "8080"` không có nghĩa chọn Service port số 8080.

### 6. RBAC có đủ?

```bash
kubectl auth can-i \
  --as=system:serviceaccount:monitoring:prometheus \
  list services \
  -n production

kubectl auth can-i \
  --as=system:serviceaccount:monitoring:prometheus \
  list endpointslices.discovery.k8s.io \
  -n production
```

### 7. Generated config có ServiceMonitor?

Prometheus Operator tạo config từ CRDs. Cách inspect Secret phụ thuộc deployment/version/chart; ưu tiên trang Status/Configuration của Prometheus và hướng dẫn troubleshooting chính thức của Operator, tránh sửa trực tiếp generated Secret.

---

## 25. Failure modes thường gặp

### Target không có trong Service Discovery

Nguyên nhân:

- Prometheus/ServiceMonitor selector không match;
- namespace selector sai;
- RBAC không list/watch được resource;
- file glob không match;
- cloud/Consul API credential hoặc filter sai.

### Target có trong dropped list

Nguyên nhân:

- `keep` regex không match;
- source label thiếu nên thành chuỗi rỗng;
- rule order dùng label trước khi tạo;
- port/annotation convention không đúng.

### Target active nhưng `up == 0`

Nguyên nhân:

- `__address__`, path hoặc scheme sai;
- DNS/network policy/firewall;
- TLS CA/server name/auth;
- scrape timeout;
- response parse lỗi;
- sample/label/body limit.

### `up == 1` nhưng metric không có

Nguyên nhân:

- metric không được exporter expose;
- metric relabel drop;
- metric name bị đổi;
- collector disabled;
- query dùng target label không tồn tại.

### Cardinality tăng sau deploy

Nguyên nhân:

- `labelmap` copy toàn bộ metadata;
- thêm version, pod UID hoặc build SHA vào labels;
- normalize/labeldrop làm identity collision;
- một ServiceMonitor/PodMonitor mới discover trùng target cũ.

### Cùng target bị scrape hai lần

Nguyên nhân:

- vừa raw scrape config vừa ServiceMonitor;
- ServiceMonitor selectors overlap;
- pod role và EndpointSlice role cùng chọn workload;
- EndpointSlice migration chạy cả Endpoints và EndpointSlice mà chưa deduplicate design.

Hai scrape có `job` khác nhau vẫn tạo hai bộ series và tăng ingest; cùng label set có thể tạo duplicate/out-of-order behavior tùy pipeline.

---

## 26. Quy trình thay đổi relabeling an toàn

```text
1. Chụp discoveredLabels và final labels hiện tại
2. Xác định desired target/label contract
3. promtool check config
4. promtool check service-discovery
5. So active/dropped target count trước–sau
6. Kiểm tra output cardinality và duplicate target
7. Canary trên một Prometheus replica/shard
8. Reload
9. Theo dõi up, scrape samples, series added, SD errors
10. Roll out và giữ rollback config
```

Relabeling là code:

- review theo thứ tự;
- có input/output examples;
- test empty/missing labels;
- kiểm tra regex anchored;
- có owner và rollback;
- tránh rollout đồng thời với instrumentation label change.

---

## 27. Checklist production

### Discovery

- [ ] Source of truth phù hợp target lifecycle.
- [ ] API/file/DNS refresh và failure mode được hiểu.
- [ ] Credentials dùng least privilege và không commit trong config.
- [ ] Kubernetes ưu tiên EndpointSlice.
- [ ] Selector/API watch cost được đo.
- [ ] Có alert khi discovery trả bất thường ít/nhiều target.

### Target relabeling

- [ ] Filter opt-in/port/ready rõ ràng.
- [ ] Rule order có input/output contract.
- [ ] Chỉ copy metadata allowlist.
- [ ] `instance`, `job`, `service`, `namespace` ổn định.
- [ ] Regex RE2 và anchored semantics được kiểm.
- [ ] Không nội suy label name trong `replacement`.
- [ ] Hashmod key và HA/sharding design rõ.

### Metric relabeling

- [ ] Drop list có owner và usage audit.
- [ ] Không xóa label tạo duplicate identity.
- [ ] Không kỳ vọng metric relabeling giảm network.
- [ ] Tỷ lệ pre/post relabel được theo dõi.
- [ ] Ưu tiên tắt collector tại source khi drop phần lớn response.

### Kubernetes Operator

- [ ] Prometheus CR chọn đúng monitor objects/namespaces.
- [ ] ServiceMonitor chọn Service, không nhầm Pod.
- [ ] Service selector chọn Pods.
- [ ] Named Service port khớp `endpoints.port`.
- [ ] EndpointSlice và RBAC đã migrate.
- [ ] ServiceMonitor/PodMonitor không overlap ngoài chủ đích.

---

## 28. Câu hỏi tự kiểm tra

1. Discovered target khác active target thế nào?
2. `__meta_*` biến mất ở thời điểm nào?
3. Vì sao `instance` thường bằng `__address__`?
4. Target relabel và metric relabel tiết kiệm chi phí khác nhau thế nào?
5. Vì sao annotation `prometheus.io/scrape` không tự hoạt động?
6. `role: service` khác `role: endpointslice` ở đâu?
7. Tại sao không nên `labelmap` toàn bộ pod labels?
8. `replacement` có đọc `${__meta_label}` theo tên được không?
9. Vượt `sample_limit` có ingest phần đầu response không?
10. ServiceMonitor selector chain gồm những tầng nào?
11. Sharding bằng `hashmod` có cung cấp HA không?
12. Khi target bị drop, API/UI field nào cần so sánh?

---

## 29. Tài liệu chính thức

- [Prometheus configuration và service discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Relabel configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#relabel_config)
- [File-based service discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#file_sd_config)
- [Kubernetes service discovery](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config)
- [Prometheus HTTP targets API](https://prometheus.io/docs/prometheus/latest/querying/api/#targets)
- [Promtool service discovery check](https://prometheus.io/docs/prometheus/latest/command-line/promtool/)
- [Kubernetes EndpointSlices](https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/)
- [Prometheus Operator design](https://prometheus-operator.dev/docs/getting-started/design/)
- [Prometheus Operator API reference](https://prometheus-operator.dev/docs/api-reference/api/)
- [Prometheus Operator troubleshooting](https://prometheus-operator.dev/docs/platform/troubleshooting/)

---

## Chủ đề tiếp theo

[Prometheus Production – HA, capacity và long-term storage](prometheus_production.md)

---

*Cập nhật lần cuối: 2026-07-29*
