---
title: "Telemetry Governance & FinOps – Data Contracts, Cost và Operational Control"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 16
---
# Telemetry Governance & FinOps – Data Contracts, Cost và Operational Control

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là quản trị telemetry như một data product có owner, contract,
> quality target, privacy policy và cost budget. Bài không chỉ hỏi “lưu dữ liệu bao
> lâu”, mà còn trả lời ai tạo dữ liệu, ai dùng, giá trị vận hành là gì, chi phí phát
> sinh ở đâu và thay đổi nào cần được kiểm soát.
>
> Baseline tham chiếu của dự án: **Prometheus 3.13.x**, **Grafana 13.1.x**,
> **Mimir 3.1.x**, **Loki 3.7.x**, **Tempo 3.0.x**, **Pyroscope 2.2.x**,
> **OpenTelemetry Java 1.64.x / Collector 0.157.x** và **Grafana Alloy 1.18.x**.
>
> Đây là framework kỹ thuật và vận hành, không phải tư vấn pháp lý/kế toán. Retention,
> dữ liệu cá nhân, legal hold, transfer region và chargeback phải được xác nhận với
> security, privacy, legal và finance của tổ chức.
>
> Nên đọc trước:
> [Metrics Design](metrics_design.md),
> [Full Observability Stack](stack_integration.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [Continuous Profiling](continuous_profiling.md),
> [eBPF Observability](ebpf_observability.md) và
> [Grafana Mimir](grafana_mimir.md).

---

## 1. Vì sao telemetry cần governance?

Không có governance, observability thường tăng theo quán tính:

```text
thêm service
  → thêm metrics/logs/traces
  → thêm labels/attributes
  → retention giữ nguyên hoặc tăng
  → query và index tăng
  → chi phí tăng
  → không ai biết dữ liệu nào thật sự hữu ích
```

Vấn đề không chỉ là tiền:

- metric cùng tên nhưng khác nghĩa;
- service identity không thống nhất;
- secret/PII đi vào logs hoặc spans;
- dashboard phụ thuộc field không có owner;
- alert dùng telemetry sắp bị xóa;
- sampling làm trace correlation đứt;
- tenant lớn ảnh hưởng tenant khác;
- dữ liệu cũ không thể deprecate vì không biết consumer.

Governance biến telemetry từ “dữ liệu phát sinh” thành “dữ liệu được quản lý”.

---

## 2. Telemetry là một data product

Một telemetry product cần:

| Thuộc tính | Câu hỏi |
|---|---|
| Owner | Ai chịu trách nhiệm semantic và chi phí? |
| Producer | Service/agent nào tạo? |
| Consumers | Alert, dashboard, SLO, incident, analytics nào dùng? |
| Contract | Tên, type, attributes và units là gì? |
| Quality | Coverage, freshness, loss và accuracy target? |
| Sensitivity | Có secret, PII hoặc internal topology không? |
| Lifecycle | Introduce, change, deprecate, delete thế nào? |
| Economics | Ingest, store, query và operate tốn bao nhiêu? |

Nếu một signal không có consumer hoặc mục đích rõ, mặc định không nên thu ở quy mô
production.

---

## 3. Governance không đồng nghĩa bureaucracy

Governance tốt tạo guardrails tự động:

```text
developer khai báo contract
  → CI lint schema/cardinality/privacy
  → collector/backend enforce limits
  → catalog ghi owner/consumer
  → dashboards theo quality/cost
  → exception có expiry
```

Governance kém:

- review thủ công mọi metric;
- tài liệu spreadsheet không đồng bộ;
- một hội đồng trung tâm quyết định mọi label;
- cấm telemetry mới vì sợ chi phí;
- xử lý cost spike bằng xóa dữ liệu khẩn cấp.

Mục tiêu là **self-service trong ranh giới an toàn**, không phải central bottleneck.

---

## 4. Ba mục tiêu: value, risk và cost

Mọi quyết định telemetry phải cân bằng:

```text
Value:
  phát hiện, điều tra, SLO, capacity, security

Risk:
  privacy, secret, access, compliance, wrong decisions

Cost:
  ingest, network, storage, index, query, operations
```

Ví dụ:

| Quyết định | Value | Risk | Cost |
|---|---|---|---|
| Log full request body | debug cao trong vài case | PII/secret rất cao | volume cao |
| Metric route/status | alert/SLO cao | thấp nếu normalize | thấp |
| 100% traces | coverage cao | attributes nhạy cảm | rất cao |
| Profile 19 Hz | code hotspot tốt | function/source metadata | vừa |

Không tối ưu cost bằng cách phá value hoặc tăng risk.

---

## 5. Operating model

Vai trò gợi ý:

| Vai trò | Trách nhiệm |
|---|---|
| Platform observability | pipeline, backends, guardrails, unit cost |
| Service owner | instrumentation contract, consumer, budget |
| Security/privacy | classification, access, redaction policy |
| FinOps/finance | allocation model, showback/chargeback |
| SRE/on-call | quality/SLO/runbook và incident value |
| Data governance | naming, lifecycle, catalog integration |

Platform team không thể biết mọi business field. Service team không nên tự đặt
backend retention hoặc quyền truy cập.

Governance là shared responsibility có decision rights rõ.

---

## 6. RACI tối thiểu

Ví dụ:

| Hoạt động | Platform | Service | Security | FinOps |
|---|---|---|---|---|
| Định nghĩa metric | C | A/R | C | I |
| Pipeline/backend | A/R | I | C | C |
| PII classification | C | R | A | I |
| Cardinality budget | A | R | I | C |
| Retention | R | C | A/C | C |
| Showback | R | I | I | A |
| Exception | R | R | A nếu sensitive | C |
| Deprecation | C | A/R | I | I |

`A` – accountable, `R` – responsible, `C` – consulted, `I` – informed.

Không cần dùng đúng ma trận này; cần tránh vùng “mọi người đều tưởng người khác
chịu trách nhiệm”.

---

## 7. Telemetry catalog

Catalog không nhất thiết là sản phẩm lớn. Bản đầu có thể là YAML trong Git:

```yaml
id: checkout-http-server
owner: team-checkout
service: shop.checkout
signals:
  metrics:
    - http.server.request.duration
  traces:
    - span_kind: server
      route_source: framework
consumers:
  - checkout-slo
  - incident-dashboard
sensitivity: internal
retention_class: operational-standard
cost_center: commerce
review_after: 2026-10-01
```

Catalog cần liên kết được tới:

- source repository;
- dashboards/rules;
- collector policy;
- tenant;
- cost report;
- deprecation state.

---

## 8. Inventory trước khi tối ưu

Không thể govern thứ không đo được.

Inventory:

```text
producers
  → agents/SDK versions
  → endpoints/pipelines
  → tenants/backends
  → signal volume
  → retention
  → consumers
  → owners
```

Câu hỏi đầu tiên:

- top services theo series/log bytes/spans/profile bytes;
- top attributes/labels cardinality;
- top queries theo samples/bytes/CPU;
- dữ liệu nào không được query 30/60/90 ngày;
- dashboard/rule nào không còn owner;
- pipeline nào gửi duplicate;
- tenant nào không map được cost center.

Đừng bắt đầu bằng giảm retention đồng loạt.

---

## 9. Signal lifecycle

Một signal đi qua:

```text
proposed
  → experimental
  → stable
  → deprecated
  → disabled at source
  → retention window
  → deleted
```

Mỗi bước cần:

- semantic version;
- owner;
- adoption/consumer evidence;
- compatibility plan;
- rollback;
- deadline.

Xóa khỏi dashboard không dừng ingest. Dừng SDK không xóa history ngay. Deprecation
phải quản lý cả producer, pipeline, backend và consumer.

---

## 10. Telemetry contract

Contract nên mô tả:

```yaml
signal: metric
name: checkout.payment.attempts
type: counter
unit: "{attempt}"
description: Number of payment attempts initiated by checkout.
attributes:
  payment.provider:
    type: enum
    allowed: [bank_a, bank_b, wallet]
    max_cardinality: 10
  payment.result:
    type: enum
    allowed: [success, declined, error]
forbidden:
  - user.id
  - card.number
owner: team-checkout
stability: stable
```

Contract là interface. Dashboard, alert và billing đều là consumers của interface
đó.

---

## 11. Contract cho từng signal khác nhau

| Signal | Contract quan trọng |
|---|---|
| Metric | type, unit, monotonicity, labels, cardinality |
| Log | event name, severity, schema, fields, redaction |
| Trace | span name/kind, parent, status, attributes, sampling |
| Profile | profile type, sample rate, labels, symbol policy |
| Event | event taxonomy, timestamp, actor, target, outcome |

Không ép mọi signal vào schema giống nhau.

Điểm chung cần thống nhất:

- resource/service identity;
- environment/region;
- ownership;
- sensitivity;
- tenant/cost allocation;
- timestamp semantics;
- lifecycle.

---

## 12. Semantic conventions

Semantic conventions giảm số cách diễn đạt cùng một ý:

```text
service.name
deployment.environment.name
http.request.method
http.response.status_code
server.address
```

Nguyên tắc:

- ưu tiên convention stable hiện hành;
- ghi version convention/SDK;
- không tạo alias nội bộ nếu field chuẩn đủ dùng;
- extension phải có namespace và owner;
- migration cần dual-read hoặc transform có thời hạn;
- không dual-write vĩnh viễn.

Convention chuẩn hóa tên/ý nghĩa, không tự giới hạn cardinality hay PII.

---

## 13. Resource identity contract

Tối thiểu:

| Field | Ý nghĩa |
|---|---|
| `service.name` | logical service |
| `service.namespace` | grouping domain |
| `service.version` | deployed version |
| `service.instance.id` | running instance |
| `deployment.environment.name` | environment |
| `k8s.cluster.name` | cluster |
| `cloud.region` | region |

Contract:

```text
service.name
  ≠ pod name
  ≠ deployment version
  ≠ repository URL
```

Resource identity sai làm:

- correlation đứt;
- cost attribution sai;
- service map nhiễu;
- SLO trộn workloads;
- access policy sai boundary.

---

## 14. Naming policy

Tên tốt:

- mô tả semantic, không mô tả implementation tạm thời;
- có unit/type rõ;
- ổn định qua refactor;
- tránh duplicate namespace;
- không chứa variable value.

Ví dụ:

```text
Tốt:
  payment.attempts
  payment.duration

Không tốt:
  bank_a_payment_duration
  new_payment_v2_metric
  checkout_timer_ms
```

Provider nên là attribute bounded, version nằm trong resource/attribute, unit nằm
trong metadata chứ không tự nhét tùy tiện vào mọi tên.

---

## 15. Schema versioning

Change types:

| Change | Compatibility |
|---|---|
| Sửa description không đổi nghĩa | thường compatible |
| Thêm optional bounded attribute | cost/consumer review |
| Đổi unit | breaking |
| Counter → gauge | breaking |
| Đổi span name | breaking cho queries |
| Xóa field | breaking |
| Đổi enum meaning | breaking |

Migration:

```text
new producer
  → dual read/transform tạm thời
  → update dashboards/rules
  → measure old consumer usage
  → stop old producer
  → chờ retention
  → remove compatibility layer
```

---

## 16. Consumer registry

Signal không thể deprecate an toàn nếu không biết consumers.

Registry nên ghi:

- alert rules;
- recording rules;
- dashboards/panels;
- SLO calculations;
- notebooks/reports;
- anomaly/ML jobs;
- external API users;
- security investigations.

Tự động hóa bằng:

- parse PromQL/LogQL/TraceQL;
- datasource query logs;
- dashboard/rule repository;
- catalog annotations.

Query không xuất hiện gần đây không chứng minh không cần; có thể là disaster-only
runbook.

---

## 17. Data classification

Class gợi ý:

| Class | Ví dụ | Control |
|---|---|---|
| Public | product uptime public | bình thường |
| Internal | service topology | employee access |
| Confidential | customer/account metadata | restricted/redacted |
| Restricted | secret, credential, sensitive personal data | không thu hoặc isolation nghiêm |

Classification áp cho **field**, không chỉ signal.

Một log event có thể gồm:

```text
event name       → internal
service identity → internal
user email       → confidential/restricted
authorization    → forbidden
```

---

## 18. Secret không được xem là telemetry

Không thu:

- authorization/cookie;
- API key/token;
- password;
- private key;
- full connection string;
- payment credential;
- secret trong process args/environment.

Nếu secret đã vào pipeline:

1. dừng producer hoặc filter ngay;
2. rotate/revoke credential;
3. xác định backends/caches/queues/exports;
4. restrict access;
5. xóa theo capability/policy;
6. audit exposure;
7. thêm regression test.

Hash secret không làm nó an toàn nếu input space có thể brute-force hoặc hash dùng
để correlate identity nhạy cảm.

---

## 19. PII và quasi-identifiers

PII rõ:

- email;
- phone;
- government/customer ID;
- exact IP trong một số context;
- location;
- user-provided content.

Quasi-identifier:

- rare route;
- device + region + timestamp;
- organization + error text;
- unique session pattern.

Nhiều field không nhạy cảm riêng lẻ có thể tái nhận diện khi kết hợp.

Policy phải xét:

```text
field + precision + retention + access + joinability
```

Không chỉ grep các tên như `email`.

---

## 20. Data minimization

Thứ tự ưu tiên:

1. không tạo dữ liệu không cần;
2. drop tại SDK/agent;
3. normalize/redact trước export;
4. filter ở node/edge collector;
5. filter ở gateway;
6. backend access/retention là lớp cuối.

```text
drop tại backend
  = dữ liệu đã đi qua app, agent, network, gateway
```

Minimize tốt hơn encrypt dữ liệu không cần thiết. Encryption bảo vệ data, nhưng
không xóa chi phí và không loại bỏ misuse sau khi decrypt.

---

## 21. Redaction và pseudonymization

Kỹ thuật:

| Kỹ thuật | Dùng khi |
|---|---|
| Drop | field không cần |
| Mask | cần nhận dạng format một phần |
| Normalize | route/path/error template |
| Tokenize | cần reversible mapping có vault/control |
| Hash keyed | cần stable grouping, quản lý key |
| Bucket | latency/size/age |
| Truncate | debug prefix có giới hạn |

Ví dụ URL:

```text
/users/918273/orders/4455?token=...
  → /users/{user_id}/orders/{order_id}
```

Không dùng regex ngây thơ cho mọi payload; parser theo protocol/schema an toàn hơn.

---

## 22. Access control

Tách:

- write identity;
- query identity;
- admin/config identity;
- tenant federation;
- backend object access;
- debug endpoints.

Least privilege:

```text
service A writer
  → chỉ ghi tenant A

team A reader
  → chỉ query tenant A

platform reader
  → federated aggregate, audit

storage admin
  → không mặc định xem plaintext query data
```

Dashboard permission không thay datasource/backend authorization.

---

## 23. Retention theo use case

Không dùng một retention cho mọi data:

| Use case | Window |
|---|---|
| realtime alert | phút–giờ |
| incident phổ biến | ngày–tuần |
| trend/capacity | tháng |
| SLO reporting | theo reporting/audit period |
| forensic | policy riêng |
| debug payload | rất ngắn hoặc không lưu |

Retention decision:

```text
longest valid investigation/report window
+ ingestion/query delay
+ safety margin
```

Sau đó đối chiếu privacy, compliance và cost.

---

## 24. Hot, warm và cold data

Tách value theo tuổi:

```text
Hot:
  full resolution, query thường xuyên

Warm:
  query ít, có thể compact/downsample

Cold:
  archive/compliance, restore chậm
```

Không phải backend nào hỗ trợ tiering/downsampling giống nhau.

Nếu archive không thể query trực tiếp, phải ghi:

- restore time objective;
- format/version;
- encryption key;
- index rebuild;
- ai được restore;
- chi phí restore/egress.

Cold data không có restore test chỉ là cảm giác an toàn.

---

## 25. Retention, backup và legal hold

Ba khái niệm:

```text
Retention:
  dữ liệu được giữ bao lâu trong hệ thống

Backup:
  khôi phục sau loss/corruption

Legal hold:
  ngăn dữ liệu thuộc phạm vi bị xóa theo yêu cầu pháp lý
```

Chúng không thay nhau.

Observability backend có thể không hỗ trợ per-series delete/hold. Khi requirement
khác nhau mạnh, cần tách tenant/bucket/pipeline thay vì hy vọng filter lúc xóa.

---

## 26. Correlation contract

Metrics, logs, traces và profiles liên kết qua:

- service/resource identity;
- trace/span ID;
- exemplars;
- deployment/version;
- timestamp;
- normalized route;
- profile labels.

Retention phải giữ liên kết hữu dụng:

```text
metric exemplar còn 180 ngày
trace chỉ còn 3 ngày
  → link cũ hợp lệ về format nhưng không còn target
```

Đây không nhất thiết là lỗi, nhưng dashboard phải thể hiện expected retention thay
vì báo “trace missing” mơ hồ.

---

## 27. Metrics cardinality budget

Series count xấp xỉ:

```text
series
  ≈ product(cardinality của dimensions thực sự kết hợp)
```

Ví dụ:

```text
method 5
route 200
status 10
region 4
instance 100

worst-case = 5 × 200 × 10 × 4 × 100
           = 4,000,000 series
```

Thực tế combination có thể ít hơn, nhưng review cần worst-case và expected-case.

Budget phải tính trên **toàn metric family và replicas**, không chỉ một process.

---

## 28. Label policy

Label tốt:

- enum bounded;
- dimension cần aggregate/filter/route;
- stable;
- low churn;
- không nhạy cảm.

Label nguy hiểm:

- request/trace/session/user ID;
- raw URL;
- full exception message;
- timestamp;
- UUID;
- pod hash nếu không cần;
- client IP;
- SQL statement.

Quy tắc review:

```text
Mỗi label phải có:
  purpose
  expected cardinality
  worst-case cardinality
  source
  owner
  expiry nếu experimental
```

---

## 29. Active series và churn

Cost metrics không chỉ là active series:

- new series creation rate;
- churn;
- samples/second;
- bytes/sample;
- label length;
- histogram buckets;
- query scan.

Một workload tạo 100k series mỗi 10 phút rồi xóa có:

- active series trung bình vừa;
- churn/index/WAL/compaction rất cao;
- query cache kém;
- block index lớn.

Theo dõi both stock và flow:

```text
active series = stock
series created/removed per time = flow/churn
```

---

## 30. Native histogram governance

Native histogram giảm số series so với classic buckets trong một số trường hợp,
nhưng một sample có payload phức tạp hơn.

Contract cần:

- schema/resolution;
- bucket limits;
- reset behavior;
- classic histogram coexistence;
- query function compatibility;
- sender/backend/Grafana support;
- cost per sample.

Không bật classic + native cho toàn fleet vĩnh viễn. Giai đoạn dual-emission cần
deadline và đo accuracy/cost.

---

## 31. Logs volume model

Log cost:

```text
events/s
× average bytes/event
× compression/index factor
× retention
+ query scan/cache
```

Nguồn tăng:

- debug enabled;
- stack trace lặp lại;
- request/response body;
- multiline expansion;
- retry loop;
- duplicate tail + OTLP;
- high-cardinality stream labels;
- Kubernetes metadata quá nhiều.

Đếm event và bytes trước/after parsing, vì JSON enrich có thể làm record lớn hơn.

---

## 32. Log event contract

Ví dụ:

```json
{
  "event.name": "payment.authorization.failed",
  "severity": "ERROR",
  "service.name": "checkout",
  "payment.provider": "bank_a",
  "error.type": "timeout",
  "trace_id": "..."
}
```

Contract không cho:

- raw card/customer data;
- full request body;
- authorization header;
- unbounded error message làm indexed label;
- duplicated stack trên mọi retry.

Event name ổn định giúp sampling/dedup/query tốt hơn free-text prefix.

---

## 33. Loki label và structured metadata

Loki stream labels nên:

- bounded;
- ổn định;
- hữu ích để chọn tập log ban đầu.

Ví dụ labels:

```text
cluster, namespace, service, environment
```

Structured metadata/parsed fields:

```text
trace_id, user-safe identifier, pod, request route, error.type
```

Không index `trace_id`, raw path hoặc pod UID như label nếu không có lý do và budget.

Label explosion làm nhiều stream nhỏ, chunk kém đầy và index/query cost tăng.

---

## 34. Log levels không phải retention policy

`ERROR` không tự có giá trị cao; `INFO` không tự vô ích.

Ví dụ:

- health-check error lặp mỗi giây có value thấp;
- deploy/config event INFO có value rất cao;
- security audit event cần policy riêng;
- debug log có thể hữu ích 30 phút.

Nên dùng:

```text
event class + owner + sensitivity + use case
```

để quyết định retention/sampling, không chỉ severity.

---

## 35. Trace volume model

Trace cost:

```text
requests/s
× spans/request
× bytes/span
× sampling rate
× retention
+ trace index/search
+ query/compaction
```

Levers:

- head sampling;
- tail sampling;
- span limits;
- attribute/event limits;
- route filtering;
- remove duplicate instrumentation;
- shorter retention;
- service-specific policy.

Một request có 200 spans với 1% sampling có thể vẫn đắt hơn request 10 spans với
10% sampling.

---

## 36. Head sampling governance

Head sampling quyết định sớm:

```text
request start
  → sample hoặc drop
  → propagate decision
```

Policy:

- parent-based để giữ trace nhất quán;
- rate theo service/traffic class;
- minimum floor cho low-traffic critical service;
- không lấy một global ratio cho mọi service;
- document unsampled behavior;
- metrics/logs không phụ thuộc trace sampled nếu cần SLO.

Sampling probability không phải privacy filter. Sampled trace vẫn có thể chứa
secret/PII.

---

## 37. Tail sampling governance

Tail sampling giữ spans tạm để quyết định sau:

- error;
- latency;
- attribute;
- probabilistic baseline;
- rare route.

Cost trước sampling:

```text
all spans
  → network tới tail sampler
  → memory/buffer/processing
  → decision
  → chỉ subset vào backend
```

Tail sampling giảm storage backend nhưng không loại bỏ upstream ingest/network/
collector cost.

Scale cần trace-affinity routing, capacity cho decision window và policy conflict
resolution.

---

## 38. Span hygiene

Guardrails:

- span name là operation/route, không chứa ID;
- attribute count/length limits;
- event count limits;
- exception stack only when useful;
- avoid payload;
- set status đúng semantic;
- không duplicate client spans từ SDK + proxy + eBPF;
- database statement sanitize/normalize;
- baggage allowlist.

Span name cardinality cao phá service operation views và search index.

Ví dụ:

```text
Tốt:  GET /users/{id}
Xấu:  GET /users/918273
```

---

## 39. Profiles cost model

Profile cost:

```text
targets
× sample frequency
× stack depth
× profile types
× label combinations
× retention
+ symbol storage/query
```

Controls:

- chỉ bật profile types cần;
- sample frequency theo workload;
- target selection;
- label budget;
- symbol/debug artifact lifecycle;
- retention;
- avoid duplicate profilers;
- on-demand high-resolution window.

Profile nhỏ về event count nhưng stack/symbol processing có operational cost riêng.

---

## 40. eBPF governance

eBPF agent có hai budget:

### Telemetry budget

- event rate;
- map entries;
- ring-buffer loss;
- export bytes;
- label/attribute cardinality.

### Privilege/risk budget

- capabilities;
- host namespaces/mounts;
- process/TLS visibility;
- kernel compatibility;
- signed image/object;
- hook inventory.

Cost optimization không được khuyến khích một agent privileged không có owner chỉ
vì “không sửa application”.

---

## 41. Events và audit data

Deployment/config/security events thường rất có giá trị và volume thấp:

```text
who
did what
to which resource
when
outcome
change/version
```

Tách audit evidence khỏi debug logs khi yêu cầu:

- immutability;
- access;
- retention;
- legal hold;
- tamper evidence.

Không gửi audit event qua pipeline có aggressive sampling hoặc drop-on-overload mà
không có explicit reliability decision.

---

## 42. Observability cost anatomy

Tổng cost:

```text
Instrumentation CPU/memory
+ agent/collector compute
+ network/egress
+ ingest compute
+ Kafka/queue
+ object/block storage
+ index/cache
+ query compute
+ compaction
+ dashboards/alerts
+ engineering/on-call time
+ vendor/support/license
```

Bill backend chỉ là một phần.

Ví dụ giảm backend retention nhưng giữ collector double-export có thể không đạt
tiết kiệm dự kiến.

---

## 43. Ingest cost

Drivers:

| Signal | Driver |
|---|---|
| Metrics | samples/s, active series, label length |
| Logs | bytes/s, events/s, streams |
| Traces | spans/s, bytes/span |
| Profiles | samples/s, stacks, symbols |

Đo ở ranh giới:

```text
generated
→ accepted by agent
→ exported
→ accepted/rejected by gateway
→ ingested by backend
```

Chênh lệch cho biết sampling, filtering, retries, loss hoặc duplication.

---

## 44. Storage cost

Storage:

```text
ingested bytes/day
× compression factor
× retention days
+ index/metadata
+ replicas
+ backups/versioning
+ cache/local disks
```

Không dùng raw payload bytes làm dự báo duy nhất.

Đo:

- actual object bytes per tenant/day;
- index/chunk ratio;
- compaction effect;
- small-object count;
- replication/versioning;
- delete lag;
- restore/egress.

Retention reduction chỉ thấy full effect sau khi old data thật sự được compactor/
lifecycle xóa.

---

## 45. Query cost

Query cost phụ thuộc:

- query frequency;
- range;
- step;
- selected series/streams/spans;
- cache hit;
- parallel shards;
- scanned bytes/samples;
- result size;
- recording rules;
- dashboard refresh;
- users/automation.

Hai queries cùng latency có thể tiêu CPU rất khác.

Governance cần cả:

```text
user-visible latency
AND
resource work: scanned samples/bytes, CPU-seconds
```

Dashboard refresh 5 giây chạy 24/7 là recurring production workload.

---

## 46. Network và egress cost

Luồng:

```text
application → agent
agent → gateway
gateway → backend
backend → user/query
cross-zone replication
cross-region archive
```

Cross-zone/region có thể lớn do:

- Kafka replication;
- ingester replicas;
- remote write tập trung;
- OTLP spans trước tail sampling;
- object-store fetch;
- dashboard ở region khác.

Đặt collector gần nguồn và compress không phải lúc nào cũng thắng nếu enrich/filter
ở gateway cần raw data. Cần đo end-to-end.

---

## 47. Hidden operational cost

Chi phí con người:

- false alerts;
- dashboard khó hiểu;
- instrumentation drift;
- incident chậm vì identity sai;
- upgrade blocked bởi schema cũ;
- privacy incident;
- query abuse;
- manual tenant onboarding;
- exception không hết hạn.

Một signal rẻ về storage nhưng gây alert noise có total cost cao.

FinOps cho observability phải kết hợp dollar cost và engineering time/value.

---

## 48. Allocation dimensions

Cost allocation cần dimensions bounded và đáng tin:

| Dimension | Nguồn |
|---|---|
| Tenant | authenticated pipeline |
| Team/owner | service catalog |
| Cost center | CMDB/finance mapping |
| Environment | resource contract |
| Product | service ownership metadata |
| Region | infrastructure/resource |
| Signal | pipeline/backend |

Không dùng user-provided arbitrary label làm billing truth.

Mapping phải có:

- effective date;
- owner;
- fallback `unallocated`;
- history khi team đổi;
- reconciliation với finance.

---

## 49. Shared cost allocation

Shared platform cost:

- base cluster;
- HA headroom;
- caches;
- gateways;
- meta-monitoring;
- support;
- unused reserved capacity.

Allocation options:

```text
fixed base per tenant
+ variable usage
+ premium feature surcharge
```

Hoặc:

- proportional theo ingest;
- proportional weighted theo signal;
- theo peak/committed capacity;
- central platform subsidy.

Không có một công thức đúng cho mọi tổ chức. Công thức phải minh bạch và khuyến
khích behavior mong muốn.

---

## 50. Showback

Showback hiển thị usage/cost nhưng chưa chuyển hóa đơn nội bộ.

Report:

- total và trend;
- theo team/service/environment/signal;
- top growth;
- unit cost;
- budget variance;
- unallocated;
- optimization opportunities;
- quality/value context.

Showback là bước nên làm trước chargeback:

```text
đo → làm sạch allocation → cho team phản hồi
→ ổn định model → mới cân nhắc chargeback
```

Không showback số có độ chính xác giả.

---

## 51. Chargeback

Chargeback phân bổ chi phí thật cho đơn vị.

Prerequisites:

- allocation coverage cao;
- rate card/version rõ;
- dispute process;
- correction window;
- shared-cost policy;
- budget owner;
- exception cho regulated/critical workloads;
- data reconciliation.

Rủi ro:

- team drop telemetry quan trọng để giảm bill;
- game labels/cost center;
- né shared observability;
- incident value giảm.

Chargeback phải đi cùng minimum observability standard.

---

## 52. Budget model

Budget layers:

```text
organization
  → platform/backend
    → tenant/team
      → service
        → signal
```

Budget có thể là:

- monetary;
- active series;
- samples/s;
- GB logs/day;
- spans/s;
- profile targets;
- query CPU/concurrency;
- retention class.

Hard limit phù hợp bảo vệ hệ thống. Soft budget phù hợp planning/showback.

Không dùng hard quota bất ngờ cho critical telemetry mà chưa có degradation policy.

---

## 53. Forecast

Forecast inputs:

- service/project roadmap;
- traffic growth;
- active series/bytes/spans trend;
- new regions/clusters;
- retention changes;
- histogram migration;
- sampling policy;
- pricing/contract;
- efficiency initiatives.

Baseline:

```text
forecast next period
  = current run rate
  × traffic growth
  × telemetry-per-unit change
  × unit price change
```

Tách volume growth do business thành công khỏi inefficiency do instrumentation.

---

## 54. Unit economics

Useful units:

- cost per 1k requests;
- metrics samples per request;
- log bytes per transaction;
- spans per trace;
- cost per active service;
- cost per incident investigated;
- cost per SLO;
- profile bytes per CPU-hour.

Ví dụ:

```text
telemetry cost / orders completed
```

Nếu traffic tăng 50% và cost tăng 50%, unit cost ổn định. Nếu cost tăng 200%, cần
điều tra telemetry intensity hoặc pricing/capacity inefficiency.

---

## 55. Cost allocation formula

Ví dụ rate model:

```text
service_cost
  = metric_samples × metric_rate
  + log_GB × log_rate
  + trace_GB × trace_rate
  + profile_GB × profile_rate
  + query_CPU_hours × query_rate
  + allocated_shared_cost
```

Rate không nhất thiết là vendor bill trực tiếp; có thể là internal blended rate.

Ghi:

- currency;
- period;
- included retention;
- tier/region;
- tax/support;
- update date;
- rounding.

---

## 56. Optimization ladder

Ưu tiên:

1. xóa duplicate;
2. chặn secret/PII;
3. normalize high-cardinality fields;
4. dừng unused telemetry;
5. aggregate/recording rules;
6. sampling/filtering theo value;
7. giảm retention/tiering;
8. tune compression/cache/query;
9. resize capacity/contract.

Lý do:

```text
duplicate/unused data
  → tốn mọi lớp

retention reduction
  → chủ yếu giảm storage/history
```

Tối ưu gần source thường có compound benefit lớn hơn.

---

## 57. Metrics cost controls

- metric allow/deny policy;
- label cardinality lint;
- scrape interval theo use case;
- metric relabel drop trước ingest;
- recording rules cho query lặp;
- native histogram có kiểm soát;
- active series limit;
- per-tenant ingestion limit;
- custom active-series trackers;
- deprecate legacy metric.

Không tăng scrape interval cho availability alert mà không đánh giá detection
latency và SLO math.

---

## 58. Logs cost controls

- structured event schema;
- debug off mặc định;
- dynamic debug có TTL;
- drop health-check noise;
- deduplicate/rate limit repeated errors;
- stack trace once per incident/context;
- label allowlist;
- payload size cap;
- early filtering;
- retention theo class;
- query scan guardrails.

Sampling logs phải giữ:

- security/audit events theo policy;
- rare critical errors;
- deploy/config changes;
- counters để biết số event bị suppress.

---

## 59. Traces và profiles cost controls

### Traces

- parent-based head sampling;
- tail policy cho error/slow/rare;
- span/attribute/event limits;
- normalize names;
- remove duplicate auto-instrumentation;
- service-specific ratio;
- shorter raw-trace retention;
- aggregate service graph/span metrics.

### Profiles

- profile type allowlist;
- frequency budget;
- target/service selection;
- bounded labels;
- symbol cache/artifact policy;
- on-demand high resolution;
- avoid multiple profilers.

Luôn đo telemetry loss/coverage sau tối ưu.

---

## 60. Collector policy-as-code

Collector/Alloy là enforcement point:

```text
receivers
  → identity validation
  → resource normalization
  → sensitive field drop/redact
  → filter
  → sample
  → batch
  → tenant route
  → exporters
```

Policy rules cần:

- version control;
- unit tests với sample telemetry;
- canary;
- dry-run/count-only mode nếu có;
- drop counters theo reason;
- rollback;
- owner;
- expiry cho temporary rule.

Không dùng transform rule phức tạp không có tests trên hot gateway.

---

## 61. Backend guardrails

Backend controls:

- tenant authentication;
- ingestion rate/burst;
- active series/stream limits;
- label/attribute length;
- query range/concurrency/samples;
- retention;
- shuffle sharding;
- object-store lifecycle;
- per-tenant overrides;
- admin API isolation.

Layering:

```text
source contract
  → collector policy
  → backend hard guardrail
```

Backend limit là last defense, không phải nơi duy nhất quản trị quality.

---

## 62. Cost dashboard và governance KPIs

Dashboard nên có:

### Volume/cost

- ingest theo signal/team;
- storage/retention;
- query work;
- unit cost;
- forecast/budget variance;
- unallocated cost.

### Quality

- unknown service/owner;
- rejected/dropped telemetry;
- missing required fields;
- high-cardinality violations;
- trace completeness;
- stale contracts.

### Risk

- sensitive-field detections;
- unauthorized queries;
- exception count/age;
- data in wrong region/tenant.

Cost giảm kèm quality giảm có thể là regression.

---

## 63. Change, exception và incident process

### Change

```text
proposal
→ contract/cardinality/privacy/cost estimate
→ automated tests
→ canary
→ observe
→ approve stable
```

### Exception

Mỗi exception:

- exact field/signal;
- business reason;
- owner/approvers;
- extra cost/risk;
- compensating controls;
- expiry;
- review date;
- automatic alert trước expiry.

### Cost spike incident

1. identify signal/tenant/service;
2. check deploy/config/traffic;
3. stop duplicate/noise bằng reversible filter;
4. bảo vệ backend với limits;
5. giữ SLO/security telemetry;
6. xác minh loss;
7. root cause;
8. backfill contract/test;
9. remove temporary exception/filter.

---

## 64. Maturity model, checklist và câu hỏi tự kiểm tra

### Maturity

| Level | Đặc điểm |
|---|---|
| 0 – Unmanaged | không owner, không đo volume |
| 1 – Visible | inventory và cost tổng |
| 2 – Controlled | contracts, limits, retention, access |
| 3 – Allocated | team/service showback, budgets |
| 4 – Optimized | unit economics, automated policies |
| 5 – Adaptive | value/quality/cost feedback liên tục |

### Checklist

- [ ] Mọi service có owner và resource identity chuẩn.
- [ ] Có catalog producers, consumers, tenants và backends.
- [ ] Signal mới có contract, stability và lifecycle.
- [ ] Required/forbidden fields được lint.
- [ ] PII/secret policy áp trước export.
- [ ] Access control tồn tại ở backend, không chỉ Grafana UI.
- [ ] Retention theo use case/classification.
- [ ] Retention, backup và legal hold không bị trộn.
- [ ] Metrics có cardinality/churn budget.
- [ ] Logs có event schema và label allowlist.
- [ ] Traces có span limits và sampling contract.
- [ ] Profiles/eBPF có frequency/privilege budget.
- [ ] Có ingest/storage/query/network cost model.
- [ ] Allocation coverage và `unallocated` được theo dõi.
- [ ] Showback chạy ổn trước chargeback.
- [ ] Budget có soft/hard/degradation policy.
- [ ] Collector/backend policy được version/test/canary.
- [ ] Drop/reject có metric theo reason.
- [ ] Exception có owner và expiry.
- [ ] Cost optimization đo cả quality/value.

### Câu hỏi tự kiểm tra

1. Vì sao telemetry nên được coi là data product?
2. Governance tốt khác review thủ công ở đâu?
3. Contract cần mô tả gì cho metric?
4. Semantic convention có tự ngăn cardinality không?
5. Resource identity sai ảnh hưởng cost thế nào?
6. Làm sao biết consumer trước khi deprecate?
7. Data classification nên áp ở signal hay field?
8. Vì sao hash không luôn anonymize?
9. Data minimization nên xảy ra ở đâu sớm nhất?
10. Retention khác backup/legal hold thế nào?
11. Cardinality worst-case tính ra sao?
12. Active series khác churn ở đâu?
13. Vì sao native histogram vẫn cần cost review?
14. Loki label khác structured metadata thế nào?
15. Tail sampling giảm những lớp cost nào?
16. Profile cost phụ thuộc dimensions nào?
17. Total observability cost gồm gì ngoài backend bill?
18. Showback khác chargeback ra sao?
19. Shared platform cost có thể allocate thế nào?
20. Unit economics tốt hơn total cost ở quyết định nào?
21. Vì sao xóa duplicate đứng trước giảm retention?
22. Collector policy cần tests gì?
23. Backend limits có thay source governance không?
24. Cost dashboard phải đặt cạnh quality KPI nào?
25. Cost spike mitigation làm sao giữ critical telemetry?

---

## 65. Tài liệu tham chiếu và chủ đề tiếp theo

> Lưu ý: tại lần cập nhật này, phiên truy cập web của môi trường bị lỗi xác thực.
> Các liên kết dưới đây là nguồn chính thức dùng làm điểm vào; trước khi áp dụng
> cấu hình production, cần kiểm tra lại version và lifecycle của component thực tế.

### OpenTelemetry và semantic contracts

- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)
- [Service resource conventions](https://opentelemetry.io/docs/specs/semconv/resource/service/)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Transforming telemetry](https://opentelemetry.io/docs/collector/transforming-telemetry/)
- [Handling sensitive data](https://opentelemetry.io/docs/security/handling-sensitive-data/)
- [OpenTelemetry sampling](https://opentelemetry.io/docs/concepts/sampling/)

### Grafana stack governance

- [Mimir runtime configuration](https://grafana.com/docs/mimir/latest/configure/about-runtime-configuration/)
- [Mimir shuffle sharding](https://grafana.com/docs/mimir/latest/configure/configure-shuffle-sharding/)
- [Mimir retention](https://grafana.com/docs/mimir/latest/configure/configure-metrics-storage-retention/)
- [Loki labels và structured metadata](https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/)
- [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/)
- [Grafana Tempo operations](https://grafana.com/docs/tempo/latest/operations/)
- [Pyroscope configuration](https://grafana.com/docs/pyroscope/latest/configure-client/)

### FinOps

- [FinOps Framework](https://www.finops.org/framework/)
- [FinOps capabilities](https://www.finops.org/framework/capabilities/)
- [OpenCost documentation](https://opencost.io/docs/)

### Chủ đề tiếp theo

Sau Telemetry Governance & FinOps, chủ đề mở rộng tiếp theo là:

> **Chaos Engineering for Observability – failure injection, telemetry pipeline
> SLO, data-loss detection, degraded modes và disaster recovery exercises.**
>
> Đọc tiếp:
> [Chaos Engineering for Observability](chaos_engineering_observability.md).

---

*Cập nhật lần cuối: 2026-07-30*
