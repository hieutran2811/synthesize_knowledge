# Full Observability Stack – metrics, logs, traces và OpenTelemetry

> Baseline tài liệu ngày 2026-07-29:
> **Prometheus 3.13.x**, **Grafana 13.1.x**, **Loki 3.7.x**,
> **Tempo 3.0.x**, **Grafana Alloy 1.18.x** và
> **OpenTelemetry Collector 0.157.x**.
>
> Promtail đã **end of life từ 2026-03-02**. Ví dụ mới dùng Grafana Alloy hoặc
> OpenTelemetry Collector; không triển khai Promtail mới.
>
> Điều kiện đầu vào: đã hiểu metric contract, dashboard, production operation
> và SLO alert. Xem [Metrics Design](metrics_design.md),
> [Alerting Strategy](alerting_strategy.md) và
> [Grafana Production](../grafana/grafana_production.md).
>
> Baseline giúp nhận diện semantics tại thời điểm viết, không phải yêu cầu ghim
> mọi hệ thống vào cùng một patch version. Production phải pin image digest và
> kiểm tra release note của phiên bản thực tế.

---

## 1. Mục tiêu của bài

Sau bài này, bạn có thể:

- giải thích vai trò khác nhau của metrics, logs và traces;
- thiết kế một resource/identity contract dùng chung cho mọi signal;
- chọn OpenTelemetry Collector, Grafana Alloy hoặc kết hợp cả hai;
- triển khai agent, gateway và hybrid topology;
- đưa application logs vào Loki bằng Alloy hoặc OTLP;
- chọn Loki label và structured metadata không gây cardinality explosion;
- hiểu kiến trúc Tempo 3.0 và lựa chọn deployment mode;
- thiết kế head/tail sampling mà không làm mất error trace ngoài ý muốn;
- liên kết metric → trace, log ↔ trace và trace → metric trong Grafana;
- bảo vệ PII, tenant identity, credentials và telemetry endpoints;
- đặt retention, capacity và reliability target cho observability stack;
- kiểm thử toàn tuyến ingest → store → query → correlate.

Một stack có đủ sản phẩm chưa chắc đã có observability. Giá trị chỉ xuất hiện
khi dữ liệu có semantics thống nhất và giúp rút ngắn một quyết định vận hành.

---

## 2. Observability không chỉ là “ba trụ cột”

Cách gọi metrics, logs và traces là “three pillars” dễ nhớ nhưng có thể tạo hiểu
lầm rằng chỉ cần cài ba backend là xong.

Nên xem chúng là các signal bổ sung nhau:

| Signal | Mạnh ở câu hỏi | Điểm yếu |
|---|---|---|
| Metrics | vấn đề xảy ra ở đâu, từ khi nào, lớn đến mức nào | ít context cho một request cụ thể |
| Logs | ứng dụng đã ghi nhận sự kiện gì | volume lớn, schema dễ trôi |
| Traces | một request đi qua đâu và mất thời gian ở đâu | sampling và instrumentation gap |
| Profiles | code path nào tiêu CPU/memory | cần correlation và kiểm soát overhead |
| Events | deploy/config/change nào vừa xảy ra | không thay thế health signal |

```text
Metrics phát hiện symptom
  └──▶ exemplar mở một trace đại diện
         └──▶ span chỉ ra dependency chậm
                └──▶ trace_id mở logs đúng request
                       └──▶ deploy event cung cấp change context
```

Không signal nào là “source of truth” cho mọi câu hỏi.

---

## 3. Trách nhiệm của từng thành phần

```text
Application / Infrastructure
        │
        ├── Prometheus exposition ──────────────▶ Prometheus
        │
        ├── structured stdout ──▶ Alloy ───────▶ Loki
        │
        └── OTLP ───────────────▶ Collector ───▶ Tempo / Loki
                                                     │
                                                     ▼
Prometheus ─ metrics ─┐
Loki ─────── logs ────┼──▶ Grafana Explore / dashboards / correlations
Tempo ────── traces ──┘
```

- **Application SDK/agent** tạo telemetry và context.
- **Alloy/Collector** nhận, enrich, filter, batch và export.
- **Prometheus** lưu time series, chạy PromQL và rules.
- **Loki** lưu/query logs theo stream label và metadata.
- **Tempo** lưu/query distributed traces.
- **Grafana** query các backend; không thay chúng lưu dữ liệu.

Không gửi cùng một signal qua hai pipeline nếu không chủ đích. Ví dụ vừa tail
stdout vừa export cùng log bằng OTLP sẽ tạo duplicate.

---

## 4. Hai kiến trúc: lab và production

### Lab

```text
App
  ├── /metrics ──▶ Prometheus
  ├── stdout ────▶ Alloy ──▶ Loki monolithic
  └── OTLP ──────▶ OTel Collector ──▶ Tempo monolithic

Grafana ──▶ Prometheus + Loki + Tempo
```

Mục tiêu:

- học data flow;
- test instrumentation và correlation;
- dùng local filesystem;
- một instance cho mỗi backend.

### Production

```text
Workload
  ├── Prometheus scrape / remote-write topology
  ├── node-local Alloy for files and infrastructure
  └── OTLP agent/gateway
           │
           ├── policy + redaction + batching
           ├── traces ──▶ Tempo distributor
           └── logs ────▶ Loki gateway

Prometheus / long-term metrics backend
Loki monolithic HA hoặc distributed + object storage
Tempo microservices + Kafka-compatible queue + object storage
Grafana HA + authenticated data-source access
```

Production cần:

- authentication/TLS;
- object storage;
- HA và failure isolation;
- limits/quotas;
- backup config và disaster recovery;
- meta-monitoring;
- upgrade/migration plan.

Không biến Docker Compose lab thành production bằng cách chỉ tăng replica.

---

## 5. Correlation bắt đầu từ identity contract

Mọi signal phải mô tả cùng một service theo cùng semantics:

| Ý nghĩa | OpenTelemetry resource | Prometheus/Loki form thường gặp |
|---|---|---|
| logical service | `service.name` | `service` hoặc `service_name` |
| nhóm service | `service.namespace` | `service_namespace` |
| version deploy | `service.version` | `version` |
| environment | `deployment.environment.name` | `environment` |
| cluster | `k8s.cluster.name` | `cluster` |
| namespace K8s | `k8s.namespace.name` | `namespace`/`k8s_namespace_name` |
| instance | `service.instance.id` | `instance`/structured metadata |

Contract:

```text
service.name
  = logical component
  = giống nhau trên mọi replica
  ≠ pod name
  ≠ image tag
  ≠ deployment environment
```

`service.instance.id` phải phân biệt các instance đang chạy đồng thời.

Do backend normalize tên khác nhau, correlation config cần mapping tường minh:

```text
trace resource: service.name
metric label:   service
Loki field:     service_name
```

Không đổi mọi hệ thống về một tên bằng relabeling tùy hứng nếu điều đó tạo hai
identity contract cạnh tranh.

---

## 6. Trace context

W3C Trace Context chuẩn hóa:

```text
traceparent: 00-<trace-id>-<parent-span-id>-<flags>
tracestate:  vendor-specific state
```

Mỗi service phải:

1. extract context từ inbound request/message;
2. tạo child span;
3. inject context vào outbound request/message.

Nếu một service không propagate:

```text
checkout trace ──X── payment trace
```

Tempo sẽ thấy hai trace rời dù cả hai đều được instrument.

Với async messaging:

- inject context vào message headers;
- consumer span liên kết đúng producer context;
- hiểu khác biệt giữa parent-child và span link;
- không tái sử dụng một context cho nhiều business operation không liên quan.

Không đưa secret hoặc PII vào baggage. Baggage có thể lan qua nhiều service và
ra ngoài trust boundary.

---

## 7. OpenTelemetry gồm những lớp nào?

```text
Instrumentation API
  └── instrumentation library / auto-instrumentation
         └── SDK
                ├── resource
                ├── sampling
                ├── processing
                └── OTLP exporter
                         └── Collector / Alloy
                                └── backend
```

| Thành phần | Trách nhiệm |
|---|---|
| API | tạo span, metric, log API không phụ thuộc vendor |
| SDK | sampling, batching, export |
| Semantic Conventions | tên/ý nghĩa attribute, metric và span |
| OTLP | protocol truyền telemetry |
| Collector | receive, process, export |
| Operator | quản lý Collector và auto-instrumentation trên Kubernetes |

OpenTelemetry là vendor-neutral ở instrumentation/protocol layer. Backend,
query language, storage schema và operations vẫn có semantics riêng.

---

## 8. Agent, gateway và hybrid

### Agent

Một Collector/Alloy gần workload:

```text
App ──▶ local agent ──▶ backend
```

Ưu điểm:

- endpoint local ổn định;
- enrich host/Kubernetes metadata;
- đọc file/node logs;
- buffer ngắn khi network chập chờn.

Nhược điểm:

- nhiều instance;
- config rollout rộng;
- tail sampling toàn trace khó nếu span đi qua nhiều agent.

### Gateway

```text
Apps/agents ──▶ load balancer ──▶ collector gateways ──▶ backends
```

Ưu điểm:

- policy và credentials tập trung;
- dễ route nhiều tenant/backend;
- scale độc lập.

Nhược điểm:

- thêm hop và failure domain;
- cần load balancing, queue và capacity.

### Hybrid

```text
App
  └──▶ node/sidecar agent
          └──▶ regional gateway
                  └──▶ backend
```

Đây thường là topology production hợp lý: agent làm enrichment/file collection,
gateway làm policy, sampling và backend credentials.

---

## 9. OpenTelemetry Collector hay Grafana Alloy?

| Tiêu chí | OTel Collector | Grafana Alloy |
|---|---|---|
| Pipeline OTLP trung lập | Rất phù hợp | Có OTel components |
| Prometheus discovery/scrape | Có receiver | Native `prometheus.*` pipeline mạnh |
| Loki file/Kubernetes logs | Qua receivers/components | Native `loki.*` components |
| Config | YAML | Alloy configuration language |
| Vendor neutrality | Cao | Grafana distribution, vẫn hỗ trợ OTLP |
| Tail sampling | Contrib processor | OTel component tương ứng |
| Fleet integration | tùy nền tảng | Grafana Fleet/Alloy ecosystem |

Không cần chọn một sản phẩm cho mọi signal:

```text
Alloy DaemonSet:
  infrastructure metrics + Kubernetes/file logs

OTel Collector gateway:
  application OTLP + tail sampling + vendor-neutral routing
```

Chọn distribution dựa trên component thật sự có trong binary:

```bash
otelcol components
```

Một component được viết trong config nhưng không có trong distribution sẽ làm
Collector không start.

---

## 10. Java auto-instrumentation trên Kubernetes

Tạo `Instrumentation` resource:

```yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: checkout
  namespace: shop
spec:
  exporter:
    endpoint: http://otel-gateway.observability:4318
  propagators:
    - tracecontext
    - baggage
  sampler:
    type: parentbased_traceidratio
    argument: "1"
```

Opt in ở Pod template:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
  namespace: shop
spec:
  template:
    metadata:
      annotations:
        instrumentation.opentelemetry.io/inject-java: "checkout"
        resource.opentelemetry.io/service.name: "checkout"
        resource.opentelemetry.io/service.version: "2026.07.29"
        resource.opentelemetry.io/deployment.environment.name: "production"
    spec:
      containers:
        - name: checkout
          image: registry.example.com/checkout@sha256:<digest>
```

Với Java Operator hiện hành, auto-instrumentation mặc định dùng
OTLP `http/protobuf`, nên endpoint là port `4318`. Luôn kiểm tra protocol của
ngôn ngữ/agent thực tế; không suy đoán `4317` luôn là đúng.

`argument: "1"` giữ toàn bộ trace ở head để lab hoặc tail-sampling gateway có
đủ dữ liệu quyết định. Production không được giữ 100% một cách vô thức.

---

## 11. Auto-instrumentation không thay thế manual instrumentation

Auto-instrumentation thường bắt được:

- inbound/outbound HTTP;
- database client;
- common messaging clients;
- runtime metrics;
- framework logs/context.

Nó không tự hiểu:

- checkout ID là business operation nào;
- inventory reservation thành công nghĩa là gì;
- retry nào thuộc cùng operation;
- queue deadline của doanh nghiệp;
- lỗi payload `200 OK`;
- domain event nào đáng ghi.

Manual span gợi ý:

```text
name: checkout.place_order
kind: INTERNAL
attributes:
  order.channel = "web"
  checkout.result = "success|rejected|error"
events:
  inventory.reserved
  payment.authorized
```

Không thêm:

- raw order ID có cardinality cao nếu không cần;
- card number, token, password;
- full SQL statement có dữ liệu người dùng;
- HTTP raw URL chứa ID/query secret.

Telemetry review phải là một phần của code review.

---

## 12. Collector gateway tối thiểu

Ví dụ baseline cho Collector `0.157.x`; xác nhận component name bằng
`otelcol components` trên distribution thực tế:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 400
    spike_limit_mib: 100

  resource/common:
    attributes:
      - key: deployment.environment.name
        value: production
        action: upsert

  filter/drop_health:
    error_mode: ignore
    traces:
      span:
        - 'attributes["http.route"] == "/health"'

  batch:
    timeout: 5s
    send_batch_size: 2048

exporters:
  otlp_grpc/tempo:
    endpoint: tempo-gateway.observability:4317
    tls:
      ca_file: /var/run/secrets/telemetry/ca.pem

  otlp_http/loki:
    endpoint: https://loki-gateway.observability/otlp
    tls:
      ca_file: /var/run/secrets/telemetry/ca.pem

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors:
        - memory_limiter
        - resource/common
        - filter/drop_health
        - batch
      exporters: [otlp_grpc/tempo]

    logs:
      receivers: [otlp]
      processors:
        - memory_limiter
        - resource/common
        - batch
      exporters: [otlp_http/loki]
```

Lưu ý:

- component được khai báo nhưng không nằm trong `service.pipelines` chưa được
  enable;
- thứ tự processor là thứ tự xử lý;
- `memory_limiter` đặt sớm;
- `batch` đặt sau các processor sửa/drop dữ liệu;
- endpoint `0.0.0.0` phải được bảo vệ bằng NetworkPolicy/auth/TLS;
- `insecure: true` chỉ phù hợp lab network được cô lập.

Một số tài liệu/phiên bản cũ dùng tên `otlp` và `otlphttp`. Không trộn tên giữa
hai schema Collector; kiểm tra binary đang chạy.

---

## 13. Batch, queue, retry và backpressure

```text
receiver
  → memory limiter
  → processors
  → batch
  → exporter sending queue
  → retry
  → backend
```

Nếu backend chậm:

1. exporter queue tăng;
2. retry giữ request lâu hơn;
3. memory tăng;
4. memory limiter bắt đầu từ chối dữ liệu;
5. SDK/agent có thể drop khi queue local đầy.

Theo dõi:

```promql
otelcol_exporter_queue_size
/
otelcol_exporter_queue_capacity
```

```promql
rate(otelcol_exporter_send_failed_spans_total[5m])
```

```promql
rate(otelcol_receiver_refused_spans_total[5m])
```

Tên suffix có thể khác theo cách Collector internal metrics được export. Xác
nhận bằng `/metrics`, không copy query mù quáng.

Queue không phải durable storage mặc định. Nếu downstream outage dài hơn khả
năng buffer, data loss là có thể xảy ra.

---

## 14. Head sampling và tail sampling

### Head sampling

Quyết định lúc trace bắt đầu:

```text
parentbased_traceidratio = 0.1
```

Ưu điểm:

- rẻ;
- nhất quán qua trace nếu propagation đúng;
- ít memory ở gateway.

Nhược điểm:

- chưa biết trace sẽ error hay chậm;
- có thể bỏ đúng trace cần điều tra.

### Tail sampling

Chờ nhiều/all spans rồi quyết định:

```yaml
processors:
  tail_sampling:
    decision_wait: 30s
    num_traces: 100000
    policies:
      - name: keep-errors
        type: status_code
        status_code:
          status_codes: [ERROR]

      - name: keep-slow
        type: latency
        latency:
          threshold_ms: 2000

      - name: baseline
        type: probabilistic
        probabilistic:
          sampling_percentage: 5
```

Ưu điểm:

- giữ error/slow trace;
- sampling theo attribute/business rule.

Nhược điểm:

- cần memory trong `decision_wait`;
- thêm latency;
- late span làm quyết định khó;
- scale phức tạp.

---

## 15. Điều kiện bắt buộc khi scale tail sampling

Mọi span của cùng một trace phải đến **cùng Collector instance**:

```text
Tier 1 gateway
  └── load-balancing exporter, routing_key=traceID
        ├──▶ tail sampler A: trace IDs shard A
        ├──▶ tail sampler B: trace IDs shard B
        └──▶ tail sampler C: trace IDs shard C
```

Round-robin thông thường:

```text
span 1 → A
span 2 → B
span 3 → C
```

Mỗi sampler thấy trace thiếu và có thể quyết định khác nhau.

Nếu muốn tail sampling giữ mọi error:

- SDK upstream phải giữ đủ span để gateway thấy error;
- head sampling `10%` trước tail sampling đã loại 90% trace, không thể phục hồi;
- size `num_traces`, decision cache và late-span behavior;
- monitor traces dropped-too-early;
- test khi rolling restart và scale.

Không dùng sampled trace metrics làm SLO source nếu sampling làm lệch population.

---

## 16. Loki lưu logs như thế nào?

Loki tổ chức log thành stream:

```text
tenant ID + label set
  └── stream
        └── compressed chunks
```

Index ánh xạ label set đến chunk. Nội dung log không được full-text index theo
cách của một search engine truyền thống.

```logql
{environment="production", service_name="checkout"}
  |= "payment timeout"
```

Query hiệu quả:

1. chọn stream bằng label hữu hạn;
2. thu hẹp time range;
3. dùng line filter trước parser;
4. parse JSON/structured metadata;
5. filter field.

Không tuyên bố Loki luôn “rẻ hơn X lần”. Chi phí phụ thuộc volume, retention,
query, label cardinality, replication, object storage và đội vận hành.

---

## 17. Loki label và structured metadata

### Indexed stream labels

Phù hợp:

```text
environment
cluster
namespace
service_name
service_namespace
```

Yêu cầu:

- cardinality thấp;
- ổn định;
- thường dùng để bắt đầu query;
- không thay đổi trên mỗi request.

### Structured metadata

Phù hợp:

```text
k8s_pod_name
service_instance_id
trace_id
span_id
process_id
```

Có thể filter nhưng không tạo stream mới cho mỗi giá trị.

### Log body

Phù hợp:

```text
message
error.type
stacktrace
domain context đã redacted
```

Không dùng `trace_id`, `user_id`, raw URL, IP hoặc request ID làm indexed label.
Một unique value tạo một stream mới và phá hiệu năng ingest/query.

---

## 18. Log contract

Structured JSON example:

```json
{
  "timestamp": "2026-07-29T14:25:03.123456Z",
  "severity": "ERROR",
  "message": "payment authorization failed",
  "service_name": "checkout",
  "service_version": "2026.07.29",
  "deployment_environment_name": "production",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "00f067aa0ba902b7",
  "error_type": "PaymentTimeout"
}
```

Contract:

- timestamp UTC và parse được;
- severity vocabulary hữu hạn;
- message đọc được nhưng không dùng làm group identity;
- stacktrace giữ multiline đúng;
- trace/span IDs dùng lowercase hex nhất quán;
- resource fields thống nhất với traces;
- không log secret/PII;
- có schema evolution plan.

Log level:

```text
ERROR  operation thất bại hoặc invariant bị phá
WARN   bất thường có fallback/recovery
INFO   lifecycle/business milestone hữu hạn
DEBUG  chẩn đoán có thời hạn, thường tắt ở production
```

Không log cùng exception ở mọi layer; một failure có thể thành hàng chục dòng
duplicate.

---

## 19. Collect Kubernetes logs bằng Alloy

Ví dụ tối giản:

```alloy
discovery.kubernetes "pods" {
  role = "pod"
}

loki.source.kubernetes "pods" {
  targets    = discovery.kubernetes.pods.targets
  forward_to = [loki.process.pods.receiver]
}

loki.process "pods" {
  stage.static_labels {
    values = {
      environment = "production",
      cluster     = "prod-ap-southeast",
    }
  }

  stage.cri {}

  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url       = "https://loki-gateway.example.com/loki/api/v1/push"
    tenant_id = "shop"
  }
}
```

Production phải bổ sung:

- discovery relabeling có chọn lọc;
- namespace/service labels;
- TLS/auth secret;
- backoff/queue theo component;
- resource limits;
- RBAC tối thiểu;
- node filtering nếu dùng DaemonSet/file path;
- clustering nếu dùng API tailer nhiều replica.

`loki.source.kubernetes` dùng Kubernetes API, không đọc node system logs và có
network/CPU trade-off với kubelet. Dùng `loki.source.file` khi cần node files và
đã chấp nhận volume mount/permission.

---

## 20. Application logs qua OTLP vào Loki

Loki 3.7 hỗ trợ native OTLP/HTTP ingest. Collector export đến:

```yaml
exporters:
  otlp_http/loki:
    endpoint: https://loki-gateway.example.com/otlp
```

Điều kiện Loki:

```yaml
limits_config:
  allow_structured_metadata: true

  # Greenfield: chọn tường minh các resource attributes cardinality thấp
  # làm index labels; các resource attributes còn lại trở thành
  # structured metadata.
  otlp_config:
    resource_attributes:
      ignore_defaults: true
      attributes_config:
        - action: index_label
          attributes:
            - service.name
            - service.namespace
            - deployment.environment.name
            - k8s.cluster.name
            - k8s.namespace.name
```

Structured metadata cần:

- TSDB index;
- schema `v13`;
- chunk format tương ứng.

Mapping cần nhớ:

```text
OTel service.name
  → Loki service_name

OTel k8s.namespace.name
  → Loki k8s_namespace_name
```

Dấu chấm được normalize thành dấu gạch dưới trong Loki field name.

Default OTLP mapping của Loki vẫn có thể đưa `k8s.pod.name` và
`service.instance.id` vào index labels để giữ backward compatibility. Với
greenfield, nên review/override mapping như ví dụ trên để hai field này nằm ở
structured metadata.

Không dùng Loki exporter cũ nếu native OTLP endpoint đáp ứng use case. Kiểm tra
component và mapping của phiên bản Collector/Loki thực tế.

---

## 21. Loki storage schema hiện hành

Cấu hình khái niệm cho object storage:

```yaml
schema_config:
  configs:
    - from: "2026-01-01"
      store: tsdb
      object_store: s3
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  tsdb_shipper:
    active_index_directory: /var/loki/index
    cache_location: /var/loki/index-cache
  aws:
    s3: s3://<region>/<bucket>
```

`from` là migration boundary. Không copy ngày ví dụ vào một cluster đang có dữ
liệu; schema change phải thêm entry mới với ngày tương lai hợp lý và theo
upgrade guide.

Không dùng cho triển khai mới:

- legacy BoltDB schema;
- `boltdb-shipper` khi TSDB là lựa chọn hiện hành;
- `table_manager` cho retention;
- `shared_store` config đã bị loại khỏi Loki 3.

Filesystem phù hợp lab. Production thường dùng S3/GCS/Azure-compatible object
storage đã được tài liệu hỗ trợ.

---

## 22. Loki retention

Retention được Compactor áp dụng:

```yaml
compactor:
  working_directory: /var/loki/compactor
  compaction_interval: 10m
  retention_enabled: true
  retention_delete_delay: 2h
  delete_request_store: s3

limits_config:
  retention_period: 720h
```

Điều kiện:

- index period `24h`;
- Compactor thực sự chạy;
- persistent disk cho marker/working directory;
- quyền xóa object;
- lifecycle policy của object store không xóa rộng hơn/nhanh hơn Loki.

`retention_period` một mình không làm dữ liệu biến mất nếu Compactor retention
chưa enable.

Object-store lifecycle rule target toàn bucket có thể xóa cluster state/index
cần thiết. Scope prefix và test restore trước production.

---

## 23. Loki deployment mode

Loki hiện hướng đến:

| Mode | Khi dùng | Đặc điểm |
|---|---|---|
| Monolithic | lab, nhỏ, ưu tiên đơn giản | một binary; có thể HA theo hướng dẫn |
| Distributed/microservices | scale lớn, HA, failure isolation | scale read/write/component độc lập |

Simple Scalable Deployment đang bị deprecate và dự kiến loại ở Loki 4.0. Không
chọn SSD cho greenfield chỉ vì tutorial cũ dùng nó.

Production checklist:

- object storage;
- replication/zone awareness;
- gateway;
- query frontend/scheduler;
- per-tenant ingest/query limits;
- compactor singleton theo mode được hỗ trợ;
- caches được đo hit ratio;
- Loki Canary;
- backup config/runtime overrides.

Deployment mode là quyết định vận hành, không phải flag hiệu năng đơn lẻ.

---

## 24. LogQL thực dụng

Chọn stream:

```logql
{environment="production", service_name="checkout"}
```

Filter text trước khi parse:

```logql
{environment="production", service_name="checkout"}
  |= "authorization failed"
```

Parse JSON và filter:

```logql
{environment="production", service_name="checkout"}
  | json
  | severity="ERROR"
  | error_type="PaymentTimeout"
```

Tìm log của một trace bằng structured metadata:

```logql
{environment="production", service_name="checkout"}
  | trace_id="4bf92f3577b34da6a3ce929d0e0e4736"
```

Metric query từ logs:

```logql
sum by (service_name) (
  rate(
    {environment="production"}
      | json
      | severity="ERROR"
    [5m]
  )
)
```

Log-derived metric hữu ích khi instrumentation chưa có, nhưng không nên thay
Counter/SLI metric có contract rõ:

- log có thể bị sample/drop;
- message/schema đổi;
- một error có thể log nhiều lần;
- query logs thường đắt hơn query metric đã precompute.

---

## 25. Tempo lưu trace như thế nào?

```text
Trace
  ├── root span
  ├── server spans
  ├── client spans
  ├── messaging spans
  └── database/internal spans
```

Một span gồm:

- trace ID;
- span ID và parent span ID;
- start/end/duration;
- name và kind;
- status;
- resource attributes;
- span attributes;
- events và links.

Tempo lưu trace data thành block trong object storage và query bằng trace ID
hoặc TraceQL/search metadata. Không diễn giải “Tempo không index gì” theo nghĩa
không có cấu trúc tìm kiếm; implementation hiện dùng Parquet, block metadata,
Bloom filters/index để hỗ trợ query.

---

## 26. Kiến trúc Tempo 3.0

### Monolithic

```text
OTLP
  → distributor
  → in-process live-store
  → object storage

query frontend/querier/backend worker cùng process
```

- `target: all`;
- không cần Kafka;
- phù hợp lab và volume nhỏ/vừa;
- không scale ngang nhiều `target=all` instance;
- các component tranh cùng CPU/memory.

### Microservices

```text
OTLP
  → distributors
  → Kafka-compatible durable queue
       ├──▶ live-stores ── recent queries
       ├──▶ block-builders ── object storage
       └──▶ metrics-generators ── Prometheus-compatible backend

query frontend
  → queriers/live-stores/backend workers
```

Tempo 3.0 microservices mode cần Kafka-compatible system. Ingester và compactor
targets của kiến trúc 2.x đã được thay thế; scalable-single-binary mode đã bị
loại.

Không nâng từ Tempo 2.x bằng cách chỉ đổi image tag. Migration 3.0, rollback
boundary và config targets phải theo guide chính thức.

---

## 27. Tempo deployment và storage

| Nhu cầu | Lựa chọn |
|---|---|
| local learning | monolithic + local filesystem |
| small controlled production | cân nhắc monolithic + object storage, hiểu giới hạn HA |
| high volume/HA | microservices + Kafka-compatible queue + object storage |

Object storage production:

- S3;
- GCS;
- Azure Blob Storage.

Retention là policy theo tenant/storage configuration. Trước khi chọn:

- trace volume bytes/s;
- sampling rate;
- search time range;
- object-store request cost;
- query concurrency;
- compliance/delete requirement.

Không expose OTLP receiver hoặc Tempo query endpoint trực tiếp ra Internet.

---

## 28. TraceQL cơ bản

Error trace của checkout:

```traceql
{
  resource.service.name = "checkout"
  && status = error
}
```

Trace có span chậm:

```traceql
{
  resource.service.name = "checkout"
  && duration > 2s
}
```

Theo route template:

```traceql
{
  resource.service.name = "checkout"
  && span.http.route = "/orders"
}
```

TraceQL cho phép tìm theo cấu trúc trace/span; không dùng nó như full-text log
search. Attribute contract và dedicated columns/index tuning quyết định hiệu
quả query.

Nếu không tìm thấy trace:

1. trace có được sample không;
2. propagation có đứt không;
3. Collector có drop không;
4. tenant header có đúng không;
5. time range/clock có đúng không;
6. Tempo recent/long-term path có healthy không.

---

## 29. Metrics từ traces

Tempo metrics-generator hoặc Alloy có thể tạo:

- span RED metrics;
- service-graph metrics;
- exemplars.

```text
traces
  └── metrics-generator
         ├── span calls/errors/duration
         └── client ↔ server service graph
                    │
                    ▼ remote write
          Prometheus-compatible backend
```

Service Graph trong Grafana không tự sinh từ việc chỉ cài Tempo. Cần:

1. enable span/service-graph generation;
2. remote-write metrics đến backend;
3. cấu hình Tempo datasource link đến Prometheus datasource;
4. semantics `service.name`, span kind và propagation đúng.

Cardinality có thể bùng nổ nếu đưa arbitrary span attributes vào metric
dimensions. Estimate active series trước khi enable.

Metrics từ sampled traces mô tả sampled population. Không tự động dùng chúng làm
request SLO chính xác.

---

## 30. Prometheus vẫn là metrics path chính

Nếu ứng dụng đã expose Prometheus metrics tốt:

```text
Application /metrics
  ← Prometheus scrape
```

Không cần ép mọi metric qua OTLP chỉ để “một pipeline”.

Ưu điểm giữ pull path:

- target health rõ;
- service discovery/relabeling đã có;
- counter reset/staleness semantics quen thuộc;
- tránh Collector single-writer/out-of-order problem;
- giảm stateful metric translation.

Dùng OTel metrics khi:

- instrumentation ecosystem phù hợp;
- backend nhận OTLP;
- collector translation được test;
- temporality/resource mapping rõ.

Review metric sau translation như một public API:

- name/unit/type;
- resource-to-label mapping;
- histogram/native histogram;
- start timestamp/reset;
- cardinality;
- duplicate writer.

---

## 31. Exemplars: metric → trace

Exemplar gắn một trace ID đại diện vào histogram/counter observation:

```text
latency bucket sample
  + trace_id=4bf92f...
```

Luồng:

```text
instrumented histogram
  → Prometheus scrape exemplar
  → exemplar storage
  → Grafana time-series marker
  → click
  → Tempo trace by ID
```

Prometheus cần:

```text
--enable-feature=exemplar-storage
```

Grafana Prometheus datasource cần map exemplar field đến Tempo datasource.

Giới hạn:

- chỉ observation có sampled trace context mới có trace ID;
- exemplar là mẫu, không phải mọi request;
- retention/quantity khác metric samples;
- trace phải còn tồn tại trong Tempo lúc người dùng click.

---

## 32. Logs ↔ traces

### Log → trace

Log chứa hoặc có structured metadata:

```text
trace_id=4bf92f3577b34da6a3ce929d0e0e4736
```

Loki datasource `derivedFields` trích field rồi internal-link sang Tempo.
Nếu trace ID chỉ nằm trong structured metadata, chọn derived-field type
**Label** và match key `trace[_]?id`; regex trên log body sẽ không thấy field
này.

### Trace → logs

Tempo datasource `tracesToLogsV2` map:

```text
service.name              → service_name
k8s.namespace.name       → k8s_namespace_name
deployment.environment.name → deployment_environment_name
```

Nó mở Loki ở time range quanh span và có thể filter trace/span ID.

Hai chiều phải được cấu hình. Chỉ cấu hình Tempo → Loki không tự tạo link
Loki → Tempo.

Correlation thất bại phổ biến vì:

- log dùng `traceId`, datasource tìm `trace_id`;
- Loki OTLP đã normalize dấu chấm;
- service name khác nhau;
- app log trước khi context được attach;
- trace bị sample-out;
- time zone/clock sai.

---

## 33. Trace → metrics và Service Graph

Trace → metrics có thể link một span đến query metrics đã tồn tại:

```promql
sum by (service) (
  rate(checkout_http_server_requests_total{
    service="checkout"
  }[5m])
)
```

Map:

```text
span resource service.name → metric label service
```

Trace-to-metrics không bắt buộc metrics-generator. Nó chỉ xây link/query từ
span attributes sang metrics backend.

Service Graph thì cần metrics-generator hoặc Alloy tạo service-graph/span
metrics rồi ghi vào Prometheus-compatible backend.

Hai feature giải quyết hai nhu cầu khác nhau.

---

## 34. Grafana datasource provisioning

Skeleton; option name phải được kiểm tra với Grafana 13.1.x đang chạy:

```yaml
apiVersion: 1

datasources:
  - name: Prometheus
    uid: prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    jsonData:
      exemplarTraceIdDestinations:
        - name: trace_id
          datasourceUid: tempo

  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki-gateway
    jsonData:
      derivedFields:
        - name: TraceID
          matcherRegex: 'trace[_]?id[=": ]+([0-9a-fA-F]{32})'
          datasourceUid: tempo
          url: '$${__value.raw}'

  - name: Tempo
    uid: tempo
    type: tempo
    access: proxy
    url: http://tempo-query-frontend:3200
    jsonData:
      tracesToLogsV2:
        datasourceUid: loki
        spanStartTimeShift: "-2m"
        spanEndTimeShift: "2m"
        filterByTraceID: true
        filterBySpanID: false
        tags:
          - key: service.name
            value: service_name
          - key: k8s.namespace.name
            value: k8s_namespace_name
      tracesToMetrics:
        datasourceUid: prometheus
        spanStartTimeShift: "-2m"
        spanEndTimeShift: "2m"
        tags:
          - key: service.name
            value: service
      serviceMap:
        datasourceUid: prometheus
      nodeGraph:
        enabled: true
```

Provisioned datasource không được chỉnh bền vững từ UI. Thay đổi file/Git rồi
reload/deploy theo quy trình.

Datasource UID là API contract cho dashboards/correlations; giữ ổn định.

---

## 35. Incident workflow đa signal

Ví dụ checkout SLO page:

```text
1. Alert mở SLO dashboard
2. Xác nhận error budget burn + traffic + telemetry health
3. Chọn exemplar ở latency/error spike
4. Mở trace
5. Xác định payment client span chậm/error
6. Từ span mở logs đúng service/time/trace_id
7. So với deployment event và dependency metrics
8. Mitigate
9. Xác minh SLI + synthetic journey + Collector/backends
```

Signal order không cứng:

- biết trace ID từ support ticket → trace trước;
- batch job fail → logs/event trước;
- node saturation → metrics/profile trước;
- audit request → log theo identity/time trước.

Dashboard nên làm launchpad, không cố nhét toàn bộ log và trace vào một panel.

---

## 36. Multi-tenancy không phải authentication

Loki và Tempo dùng:

```text
X-Scope-OrgID: <tenant>
```

Header chọn tenant cho write/query nhưng không tự chứng minh caller có quyền với
tenant đó.

Loki và Tempo OSS không đi kèm authentication layer đầy đủ. Đặt authenticating
reverse proxy/gateway phía trước:

```text
client
  → TLS/mTLS/OIDC authentication
  → authorization
  → proxy inject tenant header đáng tin cậy
  → Loki/Tempo
```

Không tin `X-Scope-OrgID` do client Internet tự gửi.

Collector:

- receiver auth;
- exporter auth;
- TLS/mTLS;
- secrets từ secret manager/mounted files;
- NetworkPolicy;
- egress allowlist.

Không commit token/password vào Collector, Alloy hoặc Grafana provisioning.

---

## 37. Privacy và data minimization

Telemetry có thể chứa:

- account/email/IP;
- URL query;
- SQL parameters;
- HTTP headers;
- exception payload;
- message body;
- access token;
- internal topology.

Policy:

```text
collect only what answers an operational question
  → redact at source when possible
  → transform/drop before leaving trust boundary
  → encrypt in transit and at rest
  → restrict query access
  → retain only as long as needed
  → audit access/deletion
```

Hashing không luôn anonymize; một domain nhỏ có thể bị brute-force.

Không debug bằng cách tạm log toàn bộ header/body ở production nếu chưa có
approval, expiry, scope, encryption và cleanup.

Sampling không phải privacy control: một sampled trace vẫn có thể chứa secret.

---

## 38. Retention theo signal

Không dùng một retention cho mọi signal:

| Signal/data class | Câu hỏi quyết định |
|---|---|
| high-resolution metrics | cần điều tra/SLO trong bao lâu? |
| logs operational | incident thường được phát hiện trễ bao lâu? |
| audit logs | legal/compliance yêu cầu gì? |
| traces | trace có còn khi exemplar/log link được click không? |
| profiles | overhead và giá trị historical? |

Guardrail correlation:

```text
trace retention >= khoảng điều tra phổ biến của exemplar/log link
```

Nếu metrics giữ 30 ngày nhưng trace chỉ 2 giờ, exemplar cũ sẽ dẫn tới “not
found”. Điều đó có thể chấp nhận nếu được document.

Retention không thay backup. Backup không thay retention/delete compliance.

---

## 39. Capacity và cost model

### Metrics

```text
active series
× samples/second
× bytes/sample
× retention
× replication
```

### Logs

```text
ingested bytes/day
× retention days
× compression/storage overhead
× replication
+ index/cache/query cost
```

### Traces

```text
requests/second
× spans/request
× bytes/span
× sampling ratio
× retention
```

Ví dụ:

```text
2,000 requests/s
× 12 spans/request
× 800 bytes/span
= 19.2 MB/s raw trace payload

head sample 10%
≈ 1.92 MB/s trước protocol/storage overhead
```

Tail sampling cần ingest/buffer nhiều hơn lượng cuối cùng được lưu vì gateway
phải thấy trace trước khi quyết định.

Đo dữ liệu thật; không dùng tỷ lệ nén hoặc tuyên bố “rẻ hơn 10x” như hằng số.

---

## 40. Meta-monitoring

### Collector/Alloy

- accepted/refused items;
- exporter sent/failed;
- queue size/capacity;
- memory/CPU/restarts;
- config/component health;
- file tail lag/positions;
- sampling drops.

### Loki

- ingest rate/rejections;
- active streams;
- distributor/ingester errors;
- query latency/errors;
- cache hit;
- compactor/retention;
- object-store errors;
- Loki Canary.

### Tempo

- accepted/refused spans;
- Kafka lag trong microservices mode;
- live-store/block-builder health;
- object-store errors;
- query latency/errors;
- metrics-generator drops/cardinality;
- Tempo Vulture.

### Grafana

- datasource health;
- query errors/latency;
- alert evaluation/contact point;
- auth/database/session health.

Monitoring stack phải có một đường cảnh báo độc lập đủ để báo khi chính nó
hỏng.

---

## 41. End-to-end canary

Health endpoint chỉ xác nhận process trả lời.

### Logs

```text
Loki Canary
  → write known log
  → query it back
  → compare missing/out-of-order latency
```

### Traces

```text
Tempo Vulture
  → write synthetic trace
  → get by trace ID
  → search by attribute
  → validate result
```

### Metrics

```text
synthetic counter/target
  → Prometheus scrape
  → query
  → rule/notification heartbeat
```

### Correlation

Tạo synthetic request có:

- metric exemplar;
- structured log;
- trace;
- stable resource attributes.

CI/post-deploy test xác nhận cả ba link trong Grafana. Backend healthy riêng lẻ
không chứng minh correlation hoạt động.

---

## 42. Failure modes

| Failure | Biểu hiện | Kiểm tra |
|---|---|---|
| propagation đứt | trace chia thành nhiều root | outbound/inbound headers |
| sampling quá sớm | không có error trace | SDK head sampler |
| Collector quá tải | refused/dropped items | internal telemetry |
| Loki stream explosion | ingest reject/query chậm | label cardinality |
| tenant sai | data “mất” hoặc 401 | `X-Scope-OrgID` hai chiều |
| clock skew | span/log ngoài time range | NTP/time source |
| duplicate log path | cùng event xuất hiện hai lần | stdout tail + OTLP |
| metric identity lệch | trace-to-metrics rỗng | tag mapping |
| trace expired | exemplar link not found | retention alignment |
| object store lỗi | ingest/query/compaction fail | backend metrics |
| datasource UID đổi | dashboard links hỏng | provisioning diff |
| schema migration sai | Loki không start/query history lỗi | schema timeline |

Điều tra pipeline theo từng hop, không bắt đầu bằng restart mọi component.

---

## 43. Versioning và configuration lifecycle

Pin:

```text
container image digest
Helm/chart version
CRD/operator version
configuration schema
dashboard/rule version
semantic-convention version khi cần
```

Trước upgrade:

1. đọc breaking changes/deprecation;
2. render config/manifests;
3. validate binary components;
4. backup config và storage metadata cần thiết;
5. thử staging/canary tenant;
6. test ingest/query/correlation;
7. đo resource/cost;
8. ghi rollback boundary.

Tempo 3.0 không có in-place downgrade đơn giản sau khi hoàn tất migration.
Loki schema timeline cũng không được “rollback” bằng cách sửa ngược `from`.

Không dùng `latest` trong production manifest.

---

## 44. Validation commands

Collector:

```bash
otelcol components
otelcol validate --config=file:/etc/otelcol/config.yaml
```

Tên subcommand có thể khác theo distribution; kiểm tra `otelcol --help`.

Alloy:

```bash
alloy fmt /etc/alloy/config.alloy
alloy validate /etc/alloy/config.alloy
```

Prometheus:

```bash
promtool check config prometheus.yml
promtool check rules rules/*.yml
```

Tempo:

```bash
tempo --config.file=/etc/tempo/tempo.yaml --config.verify
```

Grafana:

- provision staging;
- gọi health endpoint của từng datasource;
- mở dashboard/correlation bằng synthetic data.

Static validation không chứng minh credential, tenant, network, storage và
semantic mapping đúng. Luôn có smoke test end-to-end.

---

## 45. Rollout theo vertical slice

Không triển khai toàn công ty cùng lúc:

```text
1 service
  → traces + propagation
  → structured logs
  → stable metrics
  → three correlations
  → dashboard/runbook
  → canary and cost review
  → template
  → next cohort
```

Exit criteria của một service:

- `service.name` đúng ở mọi signal;
- trace nối qua dependency chính;
- logs có trace ID và không có PII cấm;
- exemplars mở trace;
- trace mở logs và metrics;
- sampling/retention được document;
- telemetry drop rate trong target;
- owner biết query và debug;
- cost nằm trong budget.

Template chỉ được nhân rộng sau khi một vertical slice chứng minh được data
quality.

---

## 46. Anti-patterns

### Cài đủ sản phẩm nhưng không có identity contract

Grafana có ba datasource nhưng không link được dữ liệu.

### Dùng Promtail cho triển khai mới

Promtail đã EOL; dùng Alloy hoặc supported client.

### Loki label chứa trace/request/user ID

Tạo stream cardinality explosion.

### Cấu hình Loki v11/BoltDB/Table Manager từ tutorial cũ

Không phù hợp Loki 3.7 greenfield.

### Dùng Loki exporter cũ dù backend hỗ trợ native OTLP

Tăng phụ thuộc vào component đã đổi/deprecate.

### Head sample 10% rồi kỳ vọng tail sampler giữ mọi error

90% trace đã biến mất trước gateway.

### Round-robin trước tail sampling

Các span cùng trace đến nhiều sampler.

### Dùng trace-derived metrics làm SLO mà không hiểu sampling

Population bị bias.

### `service.name` là pod name

Service Graph và correlation bị phân mảnh theo replica.

### Expose `4317`, `4318`, Loki hoặc Tempo ra Internet

Tạo đường ingest/query không auth và nguy cơ DoS/data poisoning.

### Retention chỉ dựa vào dung lượng hiện tại

Không xét incident delay, compliance và correlation.

### Compose lab được gọi là HA production

Không có object storage, authentication, failure isolation hoặc restore plan.

### Sampling được coi là redaction

Secret vẫn tồn tại trong trace được giữ.

---

## 47. Workshop: checkout vertical slice

### Bước 1 – identity

```text
service.name = checkout
service.namespace = shop
service.version = 2026.07.29
deployment.environment.name = production
k8s.cluster.name = prod-ap-southeast
```

### Bước 2 – instrument

- HTTP server/client;
- payment/inventory messaging;
- database spans;
- business span `checkout.place_order`;
- RED metrics;
- JSON logs có trace ID.

### Bước 3 – collect

- Prometheus scrape metrics;
- Alloy collect container logs;
- OTel Collector receive traces;
- không duplicate application logs.

### Bước 4 – store

- Loki TSDB v13 + object storage;
- Tempo monolithic lab hoặc microservices production;
- Prometheus retention đúng SLO.

### Bước 5 – correlate

- metric exemplar → Tempo;
- Loki trace ID → Tempo;
- Tempo span → Loki;
- Tempo span → Prometheus;
- Service Graph → sampled trace.

### Bước 6 – failure injection

Tạo payment latency trong staging:

```text
expected:
  SLO/latency metric tăng
  exemplar tồn tại
  trace có payment client span chậm
  checkout log và payment log cùng trace ID
  Service Graph edge checkout → payment phản ánh latency
```

### Bước 7 – pipeline failure

Tạm làm Tempo receiver unavailable trong staging:

- exporter retry;
- queue tăng;
- meta-alert fire;
- application không bị crash vì exporter;
- data-loss boundary được đo;
- pipeline phục hồi không tạo storm.

### Bước 8 – review

- data hữu ích nào thiếu;
- field nào dư/nhạy cảm;
- cardinality;
- bytes/request;
- query latency;
- on-call có rút ngắn điều tra không.

---

## 48. Production checklist

### Semantics

- [ ] `service.name` là logical service.
- [ ] Resource mapping giữa OTel/Prometheus/Loki rõ.
- [ ] Route/span names có cardinality hữu hạn.
- [ ] Trace propagation qua HTTP và messaging được test.
- [ ] Log schema và severity vocabulary có owner.

### Collection

- [ ] Không còn Promtail cho greenfield.
- [ ] Không duplicate stdout và OTLP logs.
- [ ] Collector distribution có đủ component.
- [ ] Memory limiter/batch/queue được sizing.
- [ ] Tail sampling nhận mọi span cùng trace.
- [ ] Collector/Alloy internal telemetry được scrape.

### Storage

- [ ] Loki dùng TSDB schema v13 cho OTLP/structured metadata.
- [ ] Loki retention có Compactor và persistent marker storage.
- [ ] Tempo mode phù hợp volume/HA.
- [ ] Tempo 3 microservices có Kafka-compatible queue.
- [ ] Object-store IAM và lifecycle scope đúng.
- [ ] Retention giữa signal không phá correlation ngoài ý muốn.

### Grafana

- [ ] Datasource UID ổn định.
- [ ] Metric → trace hoạt động.
- [ ] Log → trace hoạt động.
- [ ] Trace → logs hoạt động.
- [ ] Trace → metrics hoạt động.
- [ ] Service Graph có generated metrics.

### Security

- [ ] TLS/mTLS hoặc auth phù hợp.
- [ ] Reverse proxy kiểm soát tenant header.
- [ ] OTLP/backend endpoints không public.
- [ ] Secrets không nằm trong Git.
- [ ] PII redaction được test.
- [ ] Query access/audit đúng compliance.

### Reliability

- [ ] Loki Canary chạy.
- [ ] Tempo Vulture/synthetic trace chạy.
- [ ] Collector drop/queue alerts tồn tại.
- [ ] Backend ingest/query/object-storage alerts tồn tại.
- [ ] End-to-end correlation smoke test chạy sau deploy.
- [ ] Rollback/migration boundary được ghi.

---

## 49. Câu hỏi tự kiểm tra

1. Vì sao có đủ metrics, logs và traces chưa chắc đã có observability?
2. `service.name` khác `service.instance.id` thế nào?
3. Vì sao identity mapping phải được khai báo ở Grafana correlation?
4. `traceparent` giải quyết vấn đề gì?
5. Agent và gateway trade-off ra sao?
6. Khi nào dùng Alloy và khi nào dùng OTel Collector?
7. Vì sao phải chạy `otelcol components`?
8. Auto-instrumentation không hiểu những business semantics nào?
9. Tại sao `memory_limiter` nên đứng sớm và `batch` đứng muộn?
10. Queue có bảo đảm không mất telemetry vô hạn không?
11. Head sampling khác tail sampling thế nào?
12. Vì sao head sampling có thể phá mục tiêu “giữ mọi error”?
13. Tail sampling scale ngang cần routing gì?
14. Loki stream được định danh bởi gì?
15. Trường nào nên là Loki label và trường nào là structured metadata?
16. Vì sao trace ID không được dùng làm indexed label?
17. Loki native OTLP endpoint là đường nào?
18. Vì sao OTLP logs cần TSDB schema v13?
19. Retention Loki do component nào áp dụng?
20. Vì sao Simple Scalable mode không nên chọn cho Loki greenfield?
21. Tempo 3 monolithic và microservices khác nhau thế nào?
22. Component nào thay ingester path trong Tempo 3 microservices?
23. Metrics-generator khác trace-to-metrics link thế nào?
24. Exemplar có chứa mọi request không?
25. Vì sao phải cấu hình cả hai chiều logs ↔ traces?
26. `X-Scope-OrgID` có phải authentication không?
27. Sampling có phải privacy control không?
28. Retention metrics dài hơn traces ảnh hưởng exemplar ra sao?
29. Vì sao tail sampling cost không tỷ lệ đơn giản với stored sample rate?
30. Canary end-to-end chứng minh điều gì mà `/ready` không chứng minh?

---

## 50. Tài liệu chính thức

### OpenTelemetry

- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Collector configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Collector deployment patterns](https://opentelemetry.io/docs/collector/deploy/)
- [Gateway deployment pattern](https://opentelemetry.io/docs/collector/deploy/gateway/)
- [Collector internal telemetry](https://opentelemetry.io/docs/collector/internal-telemetry/)
- [Collector security](https://opentelemetry.io/docs/security/)
- [OpenTelemetry sampling](https://opentelemetry.io/docs/concepts/sampling/)
- [Kubernetes auto-instrumentation](https://opentelemetry.io/docs/platforms/kubernetes/operator/automatic/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [Service resource conventions](https://opentelemetry.io/docs/specs/semconv/resource/service/)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)

### Loki và Alloy

- [Grafana Loki](https://grafana.com/docs/loki/latest/)
- [Promtail EOL notice](https://grafana.com/docs/loki/latest/send-data/promtail/)
- [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
- [Send OTel logs to Loki](https://grafana.com/docs/loki/latest/send-data/otel/)
- [Loki labels and structured metadata](https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/)
- [Loki storage](https://grafana.com/docs/loki/latest/operations/storage/)
- [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/)
- [Loki deployment modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/)
- [Loki authentication](https://grafana.com/docs/loki/latest/operations/authentication/)
- [Loki Canary](https://grafana.com/docs/loki/latest/operations/loki-canary/)

### Tempo và Grafana

- [Grafana Tempo](https://grafana.com/docs/tempo/latest/)
- [Tempo 3 deployment modes](https://grafana.com/docs/tempo/latest/set-up-for-tracing/setup-tempo/plan/deployment-modes/)
- [Tempo architecture](https://grafana.com/docs/tempo/latest/introduction/architecture/)
- [Migrate Tempo 2.x to 3.0](https://grafana.com/docs/tempo/latest/set-up-for-tracing/setup-tempo/migrate-to-3/)
- [Tempo authentication](https://grafana.com/docs/tempo/latest/operations/authentication/)
- [Tempo Vulture](https://grafana.com/docs/tempo/latest/operations/tempo-vulture/)
- [Tempo service graphs](https://grafana.com/docs/tempo/latest/metrics-from-traces/service_graphs/)
- [Configure Tempo datasource](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/)
- [Trace-to-logs correlation](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/configure-trace-to-logs/)
- [Trace-to-metrics correlation](https://grafana.com/docs/grafana/latest/datasources/tempo/configure-tempo-data-source/configure-trace-to-metrics/)
- [Prometheus exemplar storage](https://prometheus.io/docs/prometheus/latest/feature_flags/)

---

## Hoàn thành lộ trình

```text
Prometheus:
  fundamentals → PromQL/rules → discovery → production

Grafana:
  fundamentals → dashboards/alerting-as-code → production

Observability:
  metric contract → SLO alerting → full-stack correlation
```

Hướng mở rộng:

- [OpenTelemetry deep dive](opentelemetry_deep_dive.md);
- [continuous profiling với Pyroscope/Parca](continuous_profiling.md);
- [eBPF observability](ebpf_observability.md);
- [Grafana Mimir](grafana_mimir.md);
- [telemetry governance và FinOps](telemetry_governance_finops.md);
- [chaos engineering cho observability pipeline](chaos_engineering_observability.md);
- [observability platform engineering](observability_platform_engineering.md);
- [incident response với observability](incident_response_observability.md);
- [database observability và performance engineering](database_observability_performance.md);
- [Redis và cache observability](redis_cache_observability.md);
- [Kubernetes observability deep dive](kubernetes_observability.md);
- [messaging và Kafka observability](messaging_kafka_observability.md);
- [API và HTTP observability](api_http_observability.md);
- [frontend và Real User Monitoring](frontend_rum_observability.md);
- [mobile app observability](mobile_app_observability.md);
- [serverless và functions observability](serverless_functions_observability.md);
- [LLM và Generative AI observability](llm_generative_ai_observability.md);
- [data pipeline và ETL observability](data_pipeline_etl_observability.md);
- [machine learning model observability](machine_learning_model_observability.md);
- [security observability và detection engineering](security_observability_detection_engineering.md);
- [network observability và traffic analysis](network_observability_traffic_analysis.md);
- [CI/CD và software delivery observability](cicd_software_delivery_observability.md);
- [change, configuration và feature flag observability](change_configuration_feature_flag_observability.md);
- [business và product observability](business_product_observability.md);
- [multi-tenant và SaaS observability](multi_tenant_saas_observability.md);
- [cloud cost và sustainability observability](cloud_cost_sustainability_observability.md);
- [capacity planning và performance efficiency](capacity_planning_performance_efficiency.md);
- [storage và object storage observability](storage_object_storage_observability.md);
- [search và indexing observability](search_indexing_observability.md).

---

*Cập nhật lần cuối: 2026-07-30*
