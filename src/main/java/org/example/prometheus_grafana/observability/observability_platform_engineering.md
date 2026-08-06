# Observability Platform Engineering – Self-Service, Golden Paths và Platform SLOs

> Mục tiêu của bài này là biến Prometheus, Grafana, Mimir, Loki, Tempo, Pyroscope,
> OpenTelemetry và Alloy từ một tập hợp công cụ thành **sản phẩm nền tảng nội bộ**:
> developer có thể tự onboarding, policy được thực thi tự động, tenant được cô lập,
> thay đổi có lifecycle và chất lượng platform được đo bằng SLO.
>
> Baseline tham chiếu của dự án: **Prometheus 3.13.x**, **Grafana 13.1.x**,
> **Mimir 3.1.x**, **Loki 3.7.x**, **Tempo 3.0.x**, **Pyroscope 2.2.x**,
> **OpenTelemetry Java 1.64.x / Collector 0.157.x** và **Grafana Alloy 1.18.x**.
>
> Nên đọc trước:
> [Full Observability Stack](stack_integration.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [Grafana Mimir](grafana_mimir.md),
> [Telemetry Governance & FinOps](telemetry_governance_finops.md) và
> [Chaos Engineering for Observability](chaos_engineering_observability.md).

---

## 1. Từ monitoring stack đến platform product

Một monitoring stack trả lời:

```text
components nào đang chạy?
config đặt ở đâu?
dashboard mở thế nào?
```

Một observability platform còn phải trả lời:

```text
developer đăng ký service thế nào?
owner và tenant được xác định ra sao?
telemetry contract nào được chấp nhận?
quota, retention, access và cost do ai quyết định?
thay đổi được rollout/rollback thế nào?
platform có SLO và support model gì?
```

Nếu mỗi team phải mở ticket để:

- tạo datasource;
- thêm scrape target;
- xin tenant;
- copy dashboard;
- cấu hình alert route;
- hỏi label chuẩn;
- tìm endpoint OTLP;

thì tổ chức có một nhóm vận hành công cụ, chưa có self-service platform.

---

## 2. Platform là sản phẩm nội bộ

Platform có:

| Thuộc tính | Ví dụ |
|---|---|
| Users | developer, SRE, security, data/platform teams |
| Jobs to be done | instrument, detect, investigate, report |
| Interface | portal, API, CLI, Git/CRD, documentation |
| Contract | availability, latency, retention, limits |
| Roadmap | capabilities và deprecation |
| Feedback | support tickets, usage, surveys, SLO |
| Owner | platform product + engineering |

Tư duy sản phẩm thay đổi câu hỏi:

```text
"Chúng ta cài được Loki chưa?"
  ↓
"Service owner có thể tìm log đúng tenant trong 10 phút onboarding không?"
```

Tool adoption không phải outcome. Outcome là người dùng hoàn thành công việc với ít cognitive
load, trong ranh giới an toàn và chi phí hợp lý.

---

## 3. User personas và jobs to be done

Không có một “developer” đồng nhất.

| Persona | Nhu cầu |
|---|---|
| Service developer | instrumentation, local debug, dashboard mặc định |
| Service owner | SLO, alert, retention, cost |
| On-call | tín hiệu đáng tin, correlation, runbook |
| Platform operator | capacity, upgrades, tenancy, incident |
| Security/privacy | classification, access, audit, deletion |
| FinOps | allocation, budget, forecast |
| Executive/product | service health, SLO report |

Một portal đẹp cho developer không giải quyết được workflow của on-call nếu:

- dashboard không có owner;
- alert không link runbook;
- trace không nối logs;
- query bị chặn mà không giải thích quota;
- service catalog không phản ánh deployment thực.

Thiết kế nên bắt đầu từ user journey, không bắt đầu từ danh sách plugin.

---

## 4. Phạm vi và ranh giới trách nhiệm

Platform cung cấp:

- collection endpoints/agents;
- backend storage/query;
- identity và tenant routing;
- golden-path libraries/templates;
- default dashboards/rules;
- access, limits, retention classes;
- platform SLO và support;
- upgrade/deprecation path.

Service team chịu trách nhiệm:

- business instrumentation;
- semantic correctness;
- owner/runbook;
- SLO nghiệp vụ;
- bounded attributes;
- data classification;
- budget và exception hợp lệ.

```text
Platform owns the road.
Service team owns how its service drives on that road.
```

Platform không thể tự đoán business event. Service team không nên tự dựng backend telemetry
riêng chỉ để tránh guardrail.

---

## 5. Nguyên tắc thiết kế

Một platform tốt thường:

1. **Self-service** cho thao tác thường gặp.
2. **Declarative** để có review, diff và history.
3. **Secure by default**.
4. **Observable by default** nhưng không thu dữ liệu vô hạn.
5. **Opinionated defaults, escape hatch có kiểm soát**.
6. **API-first**, portal chỉ là một client.
7. **Idempotent và reconcilable**.
8. **Multi-tenant từ identity đến storage/query**.
9. **Product SLO và support model rõ**.
10. **Lifecycle-aware** cho version, migration và deletion.

Tự động hóa một quy trình mơ hồ chỉ làm lỗi xảy ra nhanh hơn. Contract và decision rights
phải rõ trước khi xây portal.

---

## 6. Ba plane của observability platform

```text
Experience plane:
  portal, CLI, docs, catalog, scorecard

Control plane:
  APIs, desired state, policy, reconciliation, tenancy, rollout

Data plane:
  SDK/agent → Collector → backend → query/rules
```

| Plane | Failure example |
|---|---|
| Experience | portal down nhưng Git/API vẫn dùng được |
| Control | config reconcile sai tenant |
| Data | backend ingest/query unavailable |

Không để portal trở thành single point of failure. Người dùng phải có đường declarative/API
được document.

Control-plane availability và data-plane availability cần SLO riêng; một portal xanh không
chứng minh telemetry đang chảy.

---

## 7. Reference architecture

```text
Developer
  ├─ portal/CLI
  └─ Git pull request
         │
         ▼
Service Catalog ── ownership/dependencies/classification
         │
         ▼
Platform API / CRD
  ├─ schema + admission policy
  ├─ reconciliation controller
  ├─ tenant/access/quota
  └─ status + audit
         │
         ├─ Prometheus Operator resources
         ├─ OTel Collector/Alloy config
         ├─ Grafana datasource/dashboard/rules
         └─ Mimir/Loki/Tempo/Pyroscope overrides
                         │
                         ▼
                   Data plane SLOs
```

Git, catalog và runtime không nên là ba nguồn sự thật cạnh tranh. Chỉ định rõ:

- desired state ở đâu;
- runtime status ở đâu;
- ownership metadata ở đâu;
- controller nào đồng bộ giữa chúng.

---

## 8. Operating model và team topology

Vai trò gợi ý:

| Vai trò | Trách nhiệm |
|---|---|
| Platform product owner | user outcome, roadmap, adoption |
| Platform engineers | control/data plane |
| Reliability owner | SLO, capacity, incidents, DR |
| Developer enablement | templates, docs, training |
| Security/privacy | policies và exception |
| FinOps | unit economics/showback |
| Domain champions | feedback, local patterns |

Tránh hai cực:

```text
central team làm mọi dashboard
  → bottleneck

mỗi team tự dựng mọi thứ
  → phân mảnh, rủi ro, chi phí
```

Mô hình hợp lý là nền tảng trung tâm cung cấp paved road; domain team sở hữu semantics và
extension trong contract.

---

## 9. RACI và decision rights

Ví dụ:

| Quyết định | Platform | Service | Security | FinOps |
|---|---|---|---|---|
| Endpoint/protocol | A/R | I | C | I |
| Semantic business fields | C | A/R | C | I |
| Default retention | R | C | A/C | C |
| Tenant quota | A/R | C | I | C |
| SLO service | C | A/R | I | I |
| Platform SLO | A/R | C | C | I |
| PII policy | R | R | A | I |
| Exception | R | R | A nếu sensitive | C |
| Backend upgrade | A/R | I | C | I |

Decision log nên ghi:

- ai accountable;
- input nào cần;
- SLA ra quyết định;
- escalation path;
- expiry/review.

“Shared responsibility” không có decision rights cụ thể thường biến thành không ai chịu
trách nhiệm.

---

## 10. Software catalog là nền identity

Catalog tối thiểu cần:

```yaml
service_id: shop.checkout
owner: team-checkout
system: commerce
tier: critical
repository: shop/checkout
environments: [staging, production]
dependencies: [payment, inventory]
data_classification: internal
cost_center: commerce
on_call: checkout-primary
```

Catalog giúp:

- gắn `service.name` với owner;
- route alerts;
- cấp tenant/access;
- tạo dashboard links;
- showback;
- deprecate orphan telemetry;
- xây scorecard.

Catalog không phải CMDB thủ công. Metadata nên ở gần code, được validate và đồng bộ từ nguồn
có thẩm quyền.

---

## 11. Service identity là primary key

Một logical service ID phải ổn định:

```text
shop.checkout
  ≠ repository URL
  ≠ Deployment name
  ≠ Pod name
  ≠ tenant ID
  ≠ service version
```

Mapping:

| Context | Field |
|---|---|
| Catalog | `service_id` |
| OpenTelemetry | `service.namespace` + `service.name` |
| Prometheus | normalized `service`/`namespace` labels |
| Loki/Tempo/Pyroscope | resource identity |
| Grafana | variables/links |
| Alert | owner/service labels |
| Cost | allocation key |

Identity mutation phải là migration có compatibility window, không phải đổi string tùy ý.

---

## 12. Tenant model

Tenant không nhất thiết bằng team hoặc service.

Các lựa chọn:

| Model | Ưu điểm | Nhược điểm |
|---|---|---|
| Mỗi environment | đơn giản | isolation/chargeback thô |
| Mỗi team | owner/access rõ | service lớn có thể noisy |
| Mỗi service | quota/cost chi tiết | số tenant lớn |
| Business domain | scale vừa | cần governance nội bộ |
| Hybrid | linh hoạt | mapping phức tạp |

Contract tenant:

```yaml
tenant_id: prod-commerce
owners: [team-commerce-platform]
environments: [production]
signals: [metrics, logs, traces, profiles]
identity_provider_group: commerce-observers
retention_class: operational-standard
budget_class: critical
```

Không dùng email, tên hiển thị hoặc giá trị có thể đổi làm tenant ID.

---

## 13. Multi-tenancy không chỉ là header

Cô lập theo nhiều lớp:

```text
authentication
  → authorization
  → tenant routing
  → ingest limits
  → query fairness
  → storage namespace
  → encryption/access
  → cost allocation
  → audit
```

`X-Scope-OrgID` là tenant context mà Mimir/Loki/Tempo hiểu; nó không tự xác thực caller.

Gateway tin cậy phải:

- authenticate identity;
- map identity → allowed tenant;
- strip header do client tự gửi;
- inject header đã xác minh;
- audit;
- áp rate/size limits.

Nếu client được tự chọn header, isolation chỉ là quy ước.

---

## 14. Onboarding contract

Input tối thiểu:

```yaml
apiVersion: observability.example.org/v1alpha1
kind: ObservabilityBinding
metadata:
  name: checkout-production
spec:
  serviceRef: shop.checkout
  environment: production
  criticality: tier-1
  signals:
    metrics: { enabled: true }
    logs: { enabled: true, class: operational }
    traces: { enabled: true, samplingClass: standard }
    profiles: { enabled: false }
  sloProfile: customer-facing
  retentionClass: operational-standard
  alertRoute: checkout-primary
```

Platform resolve:

- tenant;
- credentials/workload identity;
- collector endpoint;
- default limits;
- dashboards;
- rule templates;
- access group;
- cost allocation.

Không yêu cầu user nhập giá trị platform có thể suy ra từ catalog.

---

## 15. Golden path

Golden path là luồng đã được tối ưu:

```text
register service
  → validate owner/classification
  → provision tenant/access
  → add instrumentation defaults
  → create scrape/export config
  → provision dashboards/rules
  → run synthetic validation
  → publish status/links
```

Đặc điểm:

- nhanh cho use case phổ biến;
- secure/cost-aware by default;
- có local/staging experience;
- có rollback;
- có documentation;
- có support;
- đo được completion time và failure.

Golden path không chỉ là repository template. Nó là một workflow end-to-end còn được duy trì
sau ngày tạo service.

---

## 16. Paved road không phải “golden cage”

Ba mức:

| Mức | Hành vi |
|---|---|
| Default | tự động áp cho đa số |
| Configurable | chọn trong bounded options |
| Exception | yêu cầu lý do, owner, expiry |

Ví dụ sampling:

```text
default:
  standard tail-sampling profile

configurable:
  low / standard / high within budget

exception:
  100% traces trong 24 giờ cho incident
```

Nếu mọi khác biệt đều cần fork template, platform tạo fragmentation. Nếu không có escape
hatch, team sẽ bypass platform.

---

## 17. Greenfield service template

Template nên tạo:

- OTel SDK/BOM và resource configuration;
- metrics endpoint hoặc OTLP exporter;
- structured logging;
- health/readiness;
- `catalog-info.yaml`;
- `ObservabilityBinding`;
- SLO skeleton;
- runbook skeleton;
- dashboard/rule tests;
- CI validation;
- local observability profile.

Không hard-code:

- production secrets;
- tenant header tùy chọn;
- datasource UID environment-specific;
- team name không qua catalog;
- version `latest`.

Template output phải có upgrade mechanism. Copy một lần rồi bỏ mặc sẽ tạo hàng trăm phiên bản
không thể vá.

---

## 18. Brownfield onboarding

Service cũ cần discovery:

```text
inventory
  → current metrics/logs/traces
  → owner
  → identity mapping
  → sensitive fields
  → cardinality/volume
  → consumers
  → migration plan
```

Không bật mọi signal cùng lúc.

Một migration slice:

1. chuẩn hóa identity;
2. đưa critical metrics/SLO vào;
3. cấu trúc logs và redact;
4. thêm trace propagation;
5. correlation;
6. cost/quality review;
7. tắt đường cũ sau compatibility window.

Brownfield cần adapter tạm thời, nhưng adapter phải có expiry.

---

## 19. API-first, portal-second

Một capability tốt có:

- schema machine-readable;
- API/CRD;
- CLI;
- GitOps workflow;
- portal form;
- status/events;
- audit.

```text
Portal
  └─ gọi cùng platform API

CLI/Git
  └─ gọi/reconcile cùng platform API
```

Không để logic policy chỉ tồn tại trong JavaScript của portal. Nếu portal down hoặc automation
cần chạy hàng loạt, API vẫn phải dùng được.

Portal giúp discoverability và guided workflow; nó không nên là nguồn sự thật.

---

## 20. Declarative desired state

Imperative:

```text
"hãy tạo datasource, rồi tạo folder, rồi thêm rule"
```

Declarative:

```text
"service checkout cần profile observability tier-1"
```

Controller tính resource cần thiết.

Lợi ích:

- idempotency;
- drift reconciliation;
- diff/review;
- retry;
- status;
- rollback bằng version;
- bulk policy migration.

Desired state không chứa runtime facts như “queue hiện 73%”. Runtime status được controller
ghi riêng.

---

## 21. CRD hay external API?

CRD phù hợp khi:

- users và resources ở Kubernetes;
- GitOps đã chuẩn;
- cần owner references/reconciliation;
- Kubernetes RBAC/admission đủ phù hợp.

External API phù hợp khi:

- multi-cloud/non-Kubernetes;
- workflow kéo dài qua nhiều systems;
- cần tenancy/auth model khác;
- cần stable product API độc lập cluster.

Hybrid:

```text
external platform API
  → internal resources/controllers
  → per-cluster CRDs
```

Không dùng CRD như database vô hạn cho query analytics hoặc secrets plaintext.

---

## 22. Reconciliation và idempotency

Controller loop:

```text
read desired
  → read actual
  → calculate diff
  → apply safe changes
  → verify
  → write status
  → repeat
```

Yêu cầu:

- tạo lại không duplicate;
- partial failure có thể retry;
- external IDs được lưu;
- deletion có finalizer/cleanup policy;
- backoff;
- rate limiting;
- leader election;
- audit correlation ID.

Không đánh dấu Ready ngay khi API trả `201`. Chỉ Ready sau khi synthetic validation hoặc
health criteria tương ứng đạt.

---

## 23. Status và conditions

Ví dụ:

```yaml
status:
  observedGeneration: 7
  tenantId: prod-commerce
  endpoints:
    otlp: https://otlp.example.org
    grafana: https://grafana.example.org/d/checkout
  conditions:
    - type: Ready
      status: "False"
      reason: TraceValidationFailed
      message: Synthetic trace not queryable within 60s
    - type: AccessProvisioned
      status: "True"
    - type: TelemetryHealthy
      status: "False"
```

Conditions phải:

- hữu hạn và có semantics ổn định;
- có `observedGeneration`;
- phân biệt provisioning với runtime health;
- message actionable;
- không chứa secret.

Một field `status: failed` không đủ cho self-service.

---

## 24. Schema validation và admission policy

Validation:

- service tồn tại trong catalog;
- owner hợp lệ;
- environment/criticality enum;
- retention/sampling class cho phép;
- alert route thuộc team;
- không có forbidden attributes;
- budget hợp lệ;
- tenant ID không do user tùy chọn;
- production exception có expiry.

Mutating/defaulting chỉ nên thêm default dự đoán được. Không silently đổi yêu cầu quan trọng.

```text
invalid request
  → reject sớm
  → chỉ rõ field, policy, cách sửa
```

Admission webhook là control quan trọng nên cần HA, timeout và failure policy được cân nhắc.

---

## 25. GitOps lifecycle

Workflow:

```text
pull request
  → schema/policy tests
  → render/diff
  → cost/cardinality estimation
  → approval theo risk
  → merge
  → reconcile
  → synthetic verify
  → status/comment
```

Git cung cấp history, không tự cung cấp:

- runtime correctness;
- secret rotation;
- conflict resolution;
- orphan cleanup;
- API availability;
- drift handling.

Controller phải phát hiện drift. Policy cần quyết định:

- tự sửa;
- chỉ alert;
- block thay đổi;
- chấp nhận emergency override có expiry.

---

## 26. Configuration hierarchy

Một hierarchy rõ:

```text
platform hard guardrails
  → organization defaults
  → environment profile
  → tenant overrides
  → service bounded overrides
  → temporary exception
```

Ghi merge semantics:

- replace hay merge;
- list append hay override;
- zero có nghĩa disable hay unset;
- priority;
- validation sau merge;
- rendered config xem ở đâu.

Tempo runtime overrides có trường hợp giá trị không khai báo trở thành zero thay vì kế thừa
default; vì vậy platform phải render/test kết quả thực, không giả định merge behavior giống
mọi sản phẩm.

---

## 27. Environment và region overlays

Khác biệt hợp lệ:

| Dimension | Ví dụ |
|---|---|
| Environment | retention/sampling thấp hơn ở dev |
| Region | endpoint, residency, object store |
| Criticality | SLO, capacity reserve |
| Signal | logs/traces/profiles khác quota |

Giữ service contract ổn định:

```text
service declares intent
platform resolves environment-specific implementation
```

Không để application code chứa URL backend production theo region.

Overlay phải được test như final rendered config; test riêng base và patch không phát hiện mọi
conflict.

---

## 28. Secrets và workload identity

Ưu tiên:

```text
workload identity / short-lived credential
  > dynamically rotated secret
  > long-lived static token
```

Control:

- secret manager, không Git;
- scoped writer/query/admin identities;
- tenant mapping phía gateway;
- automatic rotation;
- expiry alert;
- audit;
- no secret in status/log/template output;
- revocation workflow.

Datasource provisioning có thể cần secret; đảm bảo source, rendered file, API response và
backup không vô tình lộ.

Không dùng chung admin credential cho mọi service exporter.

---

## 29. OpenTelemetry distribution contract

Platform phải công bố distribution:

```yaml
distribution: org-otelcol
version: 0.157.0-org.3
components:
  receivers: [otlp, prometheus, filelog]
  processors: [memory_limiter, batch, transform, tail_sampling]
  exporters: [otlphttp, prometheusremotewrite]
security_profile: hardened-v2
```

Vì Collector core/contrib/vendor/custom không chứa cùng components.

Quản lý:

- image digest/SBOM;
- component allowlist;
- config schema;
- CVE patch SLA;
- compatibility;
- rollout ring;
- deprecation.

User không nên phải đoán exporter nào có trong binary.

---

## 30. Agent, gateway và ownership boundary

```text
Workload
  → node/sidecar agent
  → regional gateway
  → backend
```

| Layer | Platform concern |
|---|---|
| SDK | version, propagation, resource identity |
| Agent | local collection, file positions, host context |
| Gateway | auth, transform, sampling, routing, buffering |
| Backend | tenancy, storage, query, rules |

Tách pipeline theo signal/risk khi cần:

- logs có file state;
- tail sampling có state;
- Prometheus scraping cần target ownership;
- OTLP receivers thường dễ scale stateless;
- critical audit stream cần durability khác.

Một Collector khổng lồ cho mọi use case làm blast radius và rollout risk tăng.

---

## 31. OpenTelemetry Operator và fleet management

OpenTelemetry Operator có thể quản lý Collector resources và injection trong Kubernetes.

Platform vẫn cần quyết định:

- mode `daemonset`, `deployment`, `statefulset`, `sidecar`;
- distribution image;
- allowed annotations;
- resource limits;
- config ownership;
- upgrade channel;
- Target Allocator;
- status/validation.

OpAMP mô tả giao thức quản lý agent/fleet như remote config, reporting và package/status;
việc dùng OpAMP hay sản phẩm fleet manager cụ thể phải dựa vào support/maturity thực tế.

Không xây remote arbitrary-code execution dưới tên “fleet management”.

---

## 32. Prometheus Operator làm platform API

Prometheus Operator cung cấp CRDs như:

- `Prometheus`;
- `PrometheusAgent`;
- `Alertmanager`;
- `ServiceMonitor`;
- `PodMonitor`;
- `Probe`;
- `PrometheusRule`;
- `AlertmanagerConfig`;
- `ScrapeConfig`.

Platform có thể cho service team dùng subset:

```text
ServiceMonitor + PrometheusRule
```

và giữ platform-only:

```text
Prometheus/Alertmanager instances, remote write, storage, global security
```

RBAC/admission phải ngăn một namespace scrape endpoint nhạy cảm hoặc tạo rule query phá SLO
toàn cluster.

---

## 33. ServiceMonitor contract

Ví dụ bounded:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: checkout
  labels:
    platform.example.org/profile: application
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: checkout
  endpoints:
    - port: metrics
      interval: 30s
      path: /actuator/prometheus
```

Policy:

- allowed intervals/timeouts;
- namespace selector;
- TLS/auth profile;
- sample/label limits;
- honor labels/timestamps;
- metric relabel allowlist;
- target count.

Self-service scrape không có limits có thể biến thành SSRF, secret exposure hoặc cardinality
incident.

---

## 34. Rules và alert routes as code

Rule contract:

- owner;
- service;
- severity;
- SLO/runbook;
- bounded query;
- evaluation interval;
- `for` semantics;
- test fixtures;
- destination policy.

Pipeline:

```text
promtool/unit tests
  → policy lint
  → staging evaluation
  → canary notification
  → production
```

Alert route không nên copy vào từng service. Resolve từ catalog/on-call metadata hoặc chọn một
route ID hợp lệ.

Platform-provided alerts:

- telemetry missing;
- SLO burn templates;
- SDK/collector drops;
- resource saturation.

Service team thêm business conditions.

---

## 35. Dashboard as code

Dashboard contract:

- stable UID;
- folder/team ownership;
- datasource UID variables;
- bounded time ranges;
- query lint;
- documentation links;
- version;
- no secrets;
- deletion/deprecation lifecycle.

Golden dashboards:

```text
service overview
  → traffic/errors/latency/saturation
  → deployments
  → logs/traces/profiles correlations
  → SLO
  → runbook
```

Không tạo một dashboard JSON copy cho mỗi service nếu có thể dùng library panels/template
generation. Tuy nhiên generator output cần review và khả năng override hữu hạn.

---

## 36. Datasource provisioning

Platform sở hữu:

- URL/query gateway;
- auth;
- tenant header injection;
- TLS;
- UID;
- access mode;
- derived-field/correlation config;
- timeout;
- default query settings.

User nên tham chiếu logical datasource:

```text
metrics
logs
traces
profiles
```

thay vì hard-code URL.

Datasource UID phải ổn định qua environments nếu dashboard portability yêu cầu. Nếu tenant
access khác nhau, tạo mapping/proxy đúng authorization; đừng dùng một admin datasource cho mọi
folder.

---

## 37. Grafana Alerting provisioning

Resources có thể gồm:

- alert rules;
- contact points;
- notification policies;
- mute timings;
- templates.

Tách ownership:

| Resource | Owner |
|---|---|
| Global notification tree | platform |
| Team route reference | service/team |
| Contact secret | platform/secret manager |
| Service rule | service team |
| Platform meta-alert | platform |

Provisioning method cần một source of truth. Trộn UI edits, files, Terraform và API cho cùng
resource tạo drift/conflict.

Emergency UI change phải được export/backport vào desired state hoặc tự hết hạn.

---

## 38. SLO as a service

Service khai báo:

```yaml
service: shop.checkout
objective: 99.9
window: 30d
indicator:
  type: http-availability
  success: status!~"5.."
  total: all
alertProfile: standard-multiwindow-burn
```

Platform tạo:

- recording rules;
- burn-rate alerts;
- dashboard;
- report;
- owner/runbook links;
- validation.

Platform không tự quyết định:

- request nào “good” về business;
- maintenance/exclusion hợp lệ;
- target phù hợp user expectation;
- ai chấp nhận error budget.

SLO template giảm lỗi PromQL, không thay product decision.

---

## 39. Metrics onboarding

Exit criteria:

- logical service identity;
- metric names/types/units;
- bounded labels;
- RED/USE coverage;
- scrape/export success;
- no duplicate path;
- cardinality estimate;
- recording rules;
- dashboards;
- critical alerts;
- retention/remote-write class.

Platform tự động kiểm tra:

```text
target discovered?
samples accepted?
series growth within budget?
required metrics exist?
query returns tenant-correct data?
```

Không đánh dấu complete chỉ vì `/metrics` trả text.

---

## 40. Logs onboarding

Contract:

- structured event schema;
- severity vocabulary;
- timestamp;
- resource identity;
- PII/secret rules;
- label allowlist;
- structured metadata;
- multiline policy;
- retention class;
- sampling/rate limits.

Golden path:

```text
stdout/OTLP
  → Alloy/Collector
  → redact/normalize
  → tenant route
  → Loki
  → query/correlation test
```

Phát hiện duplicate nếu service vừa gửi OTLP logs vừa bị tail stdout.

Loki stream labels không chứa trace ID, request ID hoặc user ID.

---

## 41. Traces onboarding

Exit criteria:

- W3C context propagation qua HTTP/messaging;
- server/client/internal span semantics;
- resource identity;
- error/status mapping;
- attribute limits/redaction;
- head/tail sampling contract;
- Collector route;
- trace completeness canary;
- trace-to-logs/metrics;
- cost estimate.

Platform cung cấp SDK starter và auto-instrumentation profile, nhưng service bổ sung business
spans có giá trị.

Không hứa “giữ mọi error trace” nếu head sampling đã drop trước gateway.

---

## 42. Profiles và eBPF onboarding

Profiles:

- supported runtimes;
- agent version;
- sample frequency;
- labels;
- symbols/source metadata;
- overhead budget;
- retention;
- access.

eBPF:

- kernel compatibility;
- privilege/capabilities;
- BTF/CO-RE;
- namespace isolation;
- sensitive payload policy;
- fallback.

Platform không tự động inject privileged agent vào mọi cluster.

Tier:

```text
default:
  language profiling opt-in

advanced:
  eBPF network/application observability
  qua security review và bounded rollout
```

---

## 43. Correlation contract

Platform chuẩn hóa mapping:

```text
service identity
deployment/environment
trace/span ID
timestamp
route
datasource UID
tenant
```

Validation:

- metric exemplar → trace;
- log → trace;
- trace → logs;
- trace → metrics;
- trace/profile link;
- service map edge → sample trace.

Correlation status phải là output onboarding:

```yaml
conditions:
  - type: MetricToTrace
    status: "True"
  - type: TraceToLogs
    status: "False"
    reason: TenantMappingMismatch
```

“Có đủ bốn backend” không đồng nghĩa correlation hoạt động.

---

## 44. Tenant routing

Routing pipeline:

```text
workload identity
  → catalog lookup/policy
  → verified tenant
  → gateway injects backend context
  → backend enforces tenant
```

Không map tenant từ attribute do application tùy ý gửi.

Đối với nhiều signals:

| Signal | Tenant context |
|---|---|
| Mimir remote write/query | trusted gateway/header |
| Loki push/query | `X-Scope-OrgID` qua gateway |
| Tempo OTLP/query | tenant header qua Collector/gateway |
| Grafana datasource | query identity/tenant mapping |

Cross-tenant query là capability riêng, chỉ cấp cho aggregate/platform roles và audit.

---

## 45. Authentication và authorization

Tách:

```text
who are you?       → authentication
what can you do?   → authorization
which data scope?  → tenant
what was done?     → audit
```

Permissions:

- write signal;
- query signal;
- manage dashboard;
- manage rule;
- view sensitive fields;
- federated query;
- change quota/retention;
- administer platform.

Grafana folder permission không thay backend authorization.

Service accounts phải có lifecycle, rotation và owner; không gắn token vĩnh viễn vào dashboard
JSON.

---

## 46. Quotas và limits as a product

Quota không chỉ là bảo vệ backend; nó là contract user-visible.

Theo signal:

| Signal | Limits |
|---|---|
| Metrics | active series, samples/s, labels, query |
| Logs | bytes/s, streams, line size, query |
| Traces | bytes/s, trace size, spans, search |
| Profiles | bytes/s, series/labels, query |

Platform cần:

- default theo class;
- current usage;
- utilization forecast;
- clear rejection reason;
- request/exception workflow;
- temporary burst;
- alert trước hard limit;
- fair allocation.

Không trả generic `429` mà không chỉ tenant, limit và cách xử lý.

---

## 47. Fairness và noisy-neighbor isolation

Techniques:

- per-tenant rate/concurrency limits;
- query scheduler;
- shuffle sharding;
- request prioritization;
- cache isolation;
- separate critical tiers;
- object-store/IAM boundaries;
- workload pools.

Mục tiêu:

```text
tenant A query storm
  ≠ tenant B alert evaluation failure
```

Measure:

- SLO theo tenant/tier;
- throttling/rejections;
- queue time;
- resource share;
- blast radius.

Fairness không có nghĩa mọi tenant có quota bằng nhau; criticality và paid budget có thể khác,
nhưng policy phải minh bạch.

---

## 48. Retention và data classes

Service chọn class, không chọn tùy ý số ngày:

| Class | Use case |
|---|---|
| Ephemeral debug | thời gian ngắn, non-critical |
| Operational standard | incident phổ biến |
| SLO/reporting | metrics theo reporting window |
| Security/audit | policy riêng |
| Extended exception | owner, reason, expiry |

Platform resolve:

- backend retention;
- bucket/prefix;
- access;
- backup/restore;
- cost;
- deletion.

Class giúp migrate implementation mà giữ product contract.

Retention giữa signals cần xét correlation: exemplar còn nhưng trace hết hạn là behavior phải
được document.

---

## 49. Cost allocation và showback

Catalog/tenant map sang:

```text
owner
cost center
environment
service/domain
criticality
```

Showback:

- ingest bytes/s;
- active series/streams;
- storage;
- query CPU/bytes;
- retention;
- platform shared cost;
- unit cost per request/service/customer khi phù hợp.

Platform UI nên đặt:

```text
cost + quality + value
```

cạnh nhau. Giảm 40% trace cost nhưng làm điều tra error không còn trace không phải optimization
thành công.

---

## 50. Capacity model

Forecast theo từng path:

```text
producer volume
  → network
  → collector CPU/memory/queue
  → backend ingest
  → storage/index
  → query/rules/cache
```

Inputs:

- onboarding forecast;
- organic growth;
- retention;
- incident amplification;
- retry/backlog drain;
- replication;
- region/zone failure;
- release campaigns.

Reserve capacity cho:

- mất một zone;
- backend maintenance;
- telemetry spike trong incident;
- backlog replay.

Autoscaling không thay capacity planning cho stateful/storage dependencies.

---

## 51. Scaling Collector theo workload

OpenTelemetry phân biệt:

| Loại | Scaling concern |
|---|---|
| Stateless receiver/processor | scale ngang + load balance |
| Scraper | shard targets, tránh duplicate scrape |
| Stateful processor | route affinity, state migration |

Ví dụ:

- OTLP stateless gateway có thể tăng replicas;
- Prometheus receiver cần Target Allocator/sharding;
- tail sampling cần các spans cùng trace tới cùng decision point;
- span-to-metrics cần aggregation identity đúng.

Queue tăng vì backend chậm không nên được “sửa” chỉ bằng thêm Collectors; điều đó có thể tăng
áp lực downstream.

Autoscaler signal cần kết hợp queue, refused items, CPU/memory và backend health.

---

## 52. Platform SLO hierarchy

```text
Experience SLO:
  onboarding và portal/API

Control-plane SLO:
  reconcile, config propagation, status

Data-plane SLO:
  write, freshness, query, correctness

Support SLO:
  response/restore/communication
```

Ví dụ:

| Capability | SLO |
|---|---|
| Standard onboarding | 99% hoàn tất trong 15 phút |
| Config propagation | 99.9% trong 10 phút |
| Critical metric freshness | 99.99% trong 60 giây |
| Incident query availability | 99.9% |
| Alert delivery | 99.9% trong 2 phút |

Target phải dựa trên user need và architecture, không copy bảng này mù quáng.

---

## 53. Onboarding SLI

Đo funnel:

```text
request started
  → schema valid
  → resources provisioned
  → telemetry observed
  → dashboard/rules ready
  → user success
```

Metrics:

- completion rate;
- time to first telemetry;
- time to first useful dashboard;
- failure theo reason;
- manual touch rate;
- rollback rate;
- support contact rate;
- brownfield vs greenfield.

Không tối ưu thời gian form submit nếu user vẫn mất hai ngày sửa instrumentation.

Success event nên là synthetic signal query được và owner xác nhận, không chỉ controller
`Ready`.

---

## 54. Control-plane SLI

SLIs:

- API availability/latency;
- reconciliation success;
- desired-to-applied latency;
- desired-to-verified latency;
- stale generation count;
- drift count/age;
- failed deletion/finalizer;
- policy evaluation errors;
- rollout/rollback success.

Phân biệt:

```text
Applied:
  resource được tạo

Verified:
  end-to-end behavior đạt
```

Meta-monitoring control plane nên độc lập đủ để phát hiện khi controller hoặc GitOps engine
hỏng.

---

## 55. Data-plane và correctness SLI

Theo tenant/tier:

- write success;
- freshness;
- query success/latency;
- completeness;
- duplicate;
- correlation;
- rule evaluation;
- notification;
- retention correctness.

Dùng:

- Mimir synthetic writer/reader;
- Loki Canary;
- Tempo Vulture;
- profile synthetic workload;
- external blackbox probes.

Aggregate SLO có thể che tenant nhỏ bị lỗi. Theo dõi both:

```text
global weighted SLO
  + worst tenant/tier
  + number of tenants outside SLO
```

---

## 56. Error budget và release policy

Error budget platform điều khiển:

- feature rollout;
- backend upgrade;
- config migration;
- chaos experiment;
- capacity work;
- reliability investment.

Ví dụ:

```text
budget healthy
  → normal rollout

budget burn high
  → freeze risky features
  → reliability/capacity changes only

budget exhausted
  → incident review + recovery plan
```

Không dùng error budget để từ chối mọi thay đổi; một số fix reliability cần rollout dù budget
đã hết.

Tách budget theo capability để portal incident không đóng băng một bản vá data-plane khẩn cấp.

---

## 57. Developer portal và Backstage

Portal có thể hiển thị theo service:

- owner/on-call;
- instrumentation status;
- SLO/error budget;
- dashboards;
- logs/traces/profiles links;
- quota/cost;
- alerts/runbook;
- dependencies;
- platform status;
- request upgrade/exception.

Backstage Software Catalog lưu ownership/metadata và Software Templates tạo components/workflows
là một lựa chọn phổ biến.

Không bắt buộc Backstage. Có thể dùng portal khác nếu giữ:

- catalog/API contract;
- declarative source;
- authorization;
- audit;
- lifecycle.

Portal không nên scrape ngầm mọi backend với admin credential.

---

## 58. Scorecards và conformance

Scorecard ví dụ:

| Check | Type |
|---|---|
| Owner/on-call exists | required |
| Resource identity valid | required |
| Critical SLO defined | tier-dependent |
| Logs redaction test | required |
| Correlation works | recommended/required by tier |
| SDK within supported window | required |
| Cost within budget | warning/required |
| Runbook fresh | required |

Nguyên tắc:

- checks machine-verifiable;
- evidence và timestamp;
- explain remediation;
- tier-aware;
- no vanity score;
- exceptions visible;
- không dùng để shame teams.

Điểm 95/100 không có ý nghĩa nếu missing check là secret trong logs.

---

## 59. Documentation và support model

Documentation theo task:

```text
send first telemetry
debug missing telemetry
request quota
create SLO
rotate credential
migrate SDK
respond to platform incident
offboard service
```

Support tiers:

| Tier | Kênh |
|---|---|
| Self-service | docs, examples, status |
| Community | office hours/chat |
| Assisted | ticket với response target |
| Incident | on-call/escalation |

Mỗi error message nên link đúng troubleshooting section.

Docs-as-code có owner, version, feedback và test snippets. Screenshot portal cũ nhanh lỗi thời;
ưu tiên contract và workflow.

---

## 60. Versioning, upgrade và deprecation

Version các interface:

- platform API/CRD;
- templates;
- SDK/BOM;
- Collector distribution;
- semantic conventions;
- dashboards/rules;
- tenant/retention profiles.

Lifecycle:

```text
experimental
  → preview
  → supported
  → deprecated
  → end of support
  → removed
```

Migration cần:

- inventory affected services;
- compatibility matrix;
- codemod/automation;
- canary cohort;
- telemetry comparison;
- deadline;
- exception path;
- rollback boundary.

Không ép mọi team nâng version cùng ngày nếu platform chưa có visibility adoption.

---

## 61. Exception và customization model

Exception schema:

```yaml
policy: trace-sampling-max
requestedValue: 1.0
scope: shop.checkout/production
reason: incident-2026-184
owner: team-checkout
approvedBy: observability-platform
expiresAt: 2026-08-01T12:00:00Z
rollback: automatic
```

Theo dõi:

- active exceptions;
- expired nhưng chưa revert;
- cost/risk impact;
- repeat requests;
- policy tạo nhiều exception.

Nhiều exception giống nhau là tín hiệu golden path thiếu use case, không chỉ là user “không
tuân thủ”.

Customization bền vững cần extension point có contract, không fork toàn platform.

---

## 62. Security và supply chain

Control:

- signed images/artifacts;
- SBOM;
- dependency/CVE scan;
- pinned digest;
- plugin/action allowlist;
- template provenance;
- least-privilege controller;
- namespace/network policies;
- secrets manager;
- audit;
- backup/restore.

Portal scaffolder có thể tạo repository/infrastructure nên action tùy chỉnh cần review như
code có quyền cao.

Collector processors có thể đọc/biến đổi sensitive telemetry; config change cần security
boundary phù hợp.

Không cho service team tải arbitrary Collector component/plugin vào shared gateway.

---

## 63. Reliability, chaos và multi-region

Platform phải có:

- HA theo zone;
- independent meta-monitoring;
- queue/durability contract;
- backup/restore;
- region failover/failback;
- degraded modes;
- game days;
- RTO/RPO;
- status communication.

Multi-region questions:

```text
data residency?
write local hay cross-region?
query federation?
tenant global hay regional?
configuration source?
failover credential/DNS?
duplicate handling?
cost?
```

Chaos experiments từ bài trước trở thành regression suite cho platform SLO, không phải hoạt
động biểu diễn một lần.

---

## 64. Product metrics, maturity, workshop và checklist

### Product metrics

Đo outcome:

- services onboarded/eligible;
- time to first useful telemetry;
- golden-path adoption;
- manual tickets per service;
- supported SDK coverage;
- platform SLO;
- incident detection/investigation time;
- cost per service/request;
- conformance;
- user satisfaction;
- offboarding/orphan rate.

Không tối ưu:

- số dashboards;
- số metrics;
- số plugins;
- tổng ingest;

nếu không gắn với user value.

### Maturity model

| Level | Đặc điểm |
|---|---|
| 0 – Tools | cài thủ công, owner mơ hồ |
| 1 – Standardized | naming/default/docs |
| 2 – Self-service | templates/API/GitOps |
| 3 – Governed | policy, tenancy, cost, lifecycle |
| 4 – Product | SLO, feedback, adoption, support |
| 5 – Adaptive | automated optimization và resilience validation |

Không cần đạt level 5 cho mọi capability. Ưu tiên pain và risk thực.

### Workshop: onboarding `shop.checkout`

```text
1. Register catalog identity/owner
2. Submit ObservabilityBinding
3. Resolve tenant/access/retention
4. Provision ServiceMonitor/Collector route
5. Provision datasource/dashboard/rules
6. Emit synthetic metrics/log/trace
7. Validate correlation and notification
8. Publish links/status
9. Review cost/cardinality
10. Mark Ready
```

Failure exercise:

- catalog owner thiếu → reject actionable;
- Tempo tenant mapping sai → status `TraceValidationFailed`;
- quota gần đầy → warning và forecast;
- portal down → Git/API workflow vẫn chạy;
- rollback binding → cleanup theo retention/deletion policy.

### Production checklist

- [ ] Platform có product owner và user personas.
- [ ] Experience/control/data planes tách rõ.
- [ ] Catalog identity có owner/on-call/cost center.
- [ ] Tenant mapping dựa trên trusted identity.
- [ ] Golden path có end-to-end verification.
- [ ] API/schema là nguồn logic, portal chỉ là client.
- [ ] Desired state và runtime status tách.
- [ ] Reconciliation idempotent, có conditions.
- [ ] Admission policy trả lỗi actionable.
- [ ] Config hierarchy/merge semantics được document.
- [ ] Secrets không nằm trong Git/status/template output.
- [ ] Collector distribution/component list được version.
- [ ] ServiceMonitor/rules/dashboards có guardrails.
- [ ] SLO template không thay business ownership.
- [ ] Metrics/logs/traces/profiles có exit criteria.
- [ ] Correlation được test tự động.
- [ ] Quota/retention/cost là product contract.
- [ ] Scaling phân biệt stateless/scraper/stateful.
- [ ] Platform SLO bao phủ onboarding/control/data/support.
- [ ] Portal không là single point of failure.
- [ ] Scorecard có evidence/remediation.
- [ ] Upgrade/deprecation có adoption inventory.
- [ ] Exception có owner/expiry/auto rollback.
- [ ] Chaos/DR kiểm chứng RTO/RPO.
- [ ] Product metrics đo outcome, không đếm công cụ.

### Câu hỏi tự kiểm tra

1. Tool stack khác platform product ở đâu?
2. Vì sao portal không nên là source of truth?
3. Experience, control và data plane khác nhau thế nào?
4. Service identity khác tenant ID ra sao?
5. `X-Scope-OrgID` có phải authentication không?
6. Golden path khác repository template thế nào?
7. Escape hatch cần control gì?
8. Brownfield onboarding nên bắt đầu từ đâu?
9. Desired state khác runtime status ra sao?
10. Vì sao controller phải idempotent?
11. `observedGeneration` giải quyết vấn đề gì?
12. Admission nên reject lỗi semantic nào?
13. Config merge semantics vì sao phải explicit?
14. Workload identity tốt hơn static token ở đâu?
15. Tại sao cần công bố Collector distribution?
16. Prometheus Operator CRD nào nên mở cho service team?
17. ServiceMonitor có rủi ro security/cost gì?
18. SLO as a service không thể tự quyết định điều gì?
19. Correlation condition nên kiểm tra gì?
20. Quota là contract user-visible thế nào?
21. Vì sao thêm Collector có thể làm backend tệ hơn?
22. Onboarding SLI nên kết thúc ở mốc nào?
23. Applied khác Verified ra sao?
24. Scorecard tốt khác vanity score thế nào?
25. Khi nhiều team xin cùng exception, platform nên học gì?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Platform API và developer experience

- [Backstage Software Catalog](https://backstage.io/docs/features/software-catalog/)
- [Backstage Software Templates](https://backstage.io/docs/features/software-templates/)
- [Kubernetes Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
- [Kubernetes Dynamic Admission Control](https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/)

### Prometheus và OpenTelemetry control plane

- [Prometheus Operator introduction](https://prometheus-operator.dev/docs/getting-started/introduction/)
- [Prometheus Operator API reference](https://prometheus-operator.dev/docs/api-reference/api/)
- [OpenTelemetry Operator](https://opentelemetry.io/docs/platforms/kubernetes/operator/)
- [Scaling the OpenTelemetry Collector](https://opentelemetry.io/docs/collector/scaling/)
- [Open Agent Management Protocol](https://opentelemetry.io/docs/specs/opamp/)

### Grafana provisioning

- [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
- [Provision Grafana Alerting resources](https://grafana.com/docs/grafana/latest/alerting/set-up/provision-alerting-resources/)
- [Grafana Terraform Provider](https://grafana.com/docs/grafana-cloud/as-code/infrastructure-as-code/terraform/)

### Multi-tenancy và runtime configuration

- [Mimir authentication and authorization](https://grafana.com/docs/mimir/latest/manage/secure/authentication-and-authorization/)
- [Mimir runtime configuration](https://grafana.com/docs/mimir/latest/configure/about-runtime-configuration/)
- [Loki tenant isolation](https://grafana.com/docs/loki/latest/operations/multi-tenancy/)
- [Tempo multi-tenancy](https://grafana.com/docs/tempo/latest/operations/manage-advanced-systems/multitenancy/)

### Chủ đề tiếp theo

Sau Observability Platform Engineering, chủ đề mở rộng tiếp theo là:

> **Incident Response with Observability – detection, triage, incident command,
> evidence timelines, debugging workflows, postmortems và continuous learning.**
>
> Đọc tiếp:
> [Incident Response with Observability](incident_response_observability.md).

---

*Cập nhật lần cuối: 2026-07-30*
