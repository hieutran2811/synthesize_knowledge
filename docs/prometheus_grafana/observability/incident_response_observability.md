---
title: "Incident Response with Observability – Từ Detection đến Continuous Learning"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 19
---
# Incident Response with Observability – Từ Detection đến Continuous Learning

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là xây một quy trình incident response có cấu trúc, trong đó
> metrics, logs, traces, profiles, topology và change events được dùng như bằng chứng
> để đánh giá impact, giảm tác động, kiểm tra giả thuyết và xác nhận phục hồi.
>
> Baseline tham chiếu của dự án: **Prometheus 3.13.x**, **Grafana 13.1.x**,
> **Mimir 3.1.x**, **Loki 3.7.x**, **Tempo 3.0.x**, **Pyroscope 2.2.x**,
> **OpenTelemetry Java 1.64.x / Collector 0.157.x** và **Grafana Alloy 1.18.x**.
>
> Nên đọc trước:
> [Alerting Strategy & SLO](alerting_strategy.md),
> [Full Observability Stack](stack_integration.md),
> [Continuous Profiling](continuous_profiling.md),
> [Chaos Engineering for Observability](chaos_engineering_observability.md) và
> [Observability Platform Engineering](observability_platform_engineering.md).

---

## 1. Incident response tối ưu điều gì?

Trong sự cố, mục tiêu đầu tiên không phải tìm “root cause” đẹp nhất.

Thứ tự ưu tiên:

```text
protect people and data
  → stop impact from growing
  → restore acceptable service
  → verify recovery
  → understand contributing causes
  → prevent recurrence or reduce impact
```

Ba năng lực phải chạy song song:

- **control**: một đường chỉ huy và quyết định rõ;
- **coordinate**: đúng người làm đúng việc, không trùng lặp;
- **communicate**: responders và stakeholders cùng hiểu trạng thái.

Observability hỗ trợ quyết định. Nó không thay incident command, kiến thức hệ thống hoặc judgment.

---

## 2. Alert, event, problem và incident

| Khái niệm | Ý nghĩa |
|---|---|
| Event | một thay đổi/trạng thái đã xảy ra |
| Alert | điều kiện cần sự chú ý hoặc hành động |
| Problem report | người/máy báo expected khác actual |
| Incident | gián đoạn hoặc rủi ro cần response có điều phối |
| Root/contributing problem | cơ chế tạo hoặc khuếch đại sự cố |

Không phải mọi alert là incident:

```text
alert fired
  → validate
  → assess impact/urgency
  → handle locally hoặc declare incident
```

Và không phải mọi incident bắt đầu bằng alert. Nó có thể được phát hiện bởi:

- customer support;
- security;
- business KPI;
- synthetic probe;
- dependency/vendor;
- engineer quan sát bất thường.

---

## 3. Incident lifecycle

```text
detect
  → acknowledge
  → triage
  → declare/classify
  → mobilize
  → mitigate
  → recover
  → validate
  → close response
  → review
  → complete actions
```

Các mốc phải có timestamp:

- first impact;
- first detection;
- page sent/acknowledged;
- incident declared;
- first mitigation;
- impact stopped;
- service restored;
- incident closed;
- postmortem published;
- actions completed.

Một incident chưa thực sự tạo learning nếu action items biến mất sau buổi review.

---

## 4. Readiness trước incident

Cần chuẩn bị khi hệ thống còn khỏe:

- service catalog và owners;
- on-call schedule/escalation;
- severity model;
- incident roles;
- command channel/bridge;
- live document template;
- runbooks và dashboards;
- break-glass access;
- status-page process;
- backup communication path;
- game day;
- postmortem criteria.

```text
incident response capability
  = people + process + tools + practiced muscle memory
```

Một runbook chưa từng dùng hoặc quyền khẩn cấp chưa từng test chỉ là giả định.

---

## 5. Severity model

Severity dựa trên impact và urgency, không dựa vào component “quan trọng” trong sơ đồ.

Ví dụ:

| Severity | Impact | Response |
|---|---|---|
| SEV-1 | diện rộng, data/safety/revenue nghiêm trọng | incident command đầy đủ, executive/customer comms |
| SEV-2 | nhiều users/critical function degraded | coordinated response |
| SEV-3 | phạm vi nhỏ, workaround tồn tại | team response |
| SEV-4 | no current user impact, cần follow-up | normal workflow |

Dimensions:

- số/tỷ lệ users;
- chức năng bị ảnh hưởng;
- vùng/tenant;
- data loss/corruption;
- security/privacy;
- revenue/compliance;
- duration và tốc độ lan;
- workaround.

Severity có thể nâng/hạ khi có bằng chứng mới.

---

## 6. Declare sớm

Declare incident sớm khi:

- cần nhiều hơn một team;
- impact chưa rõ nhưng có thể lớn;
- điều tra/mitigation bắt đầu phân tán;
- cần stakeholder updates;
- data integrity/security có rủi ro;
- on-call quá tải.

Chi phí declare nhầm thường nhỏ hơn chi phí điều phối muộn.

```text
"chúng ta chưa biết root cause"
  không phải lý do để trì hoãn declare
```

Declaration message tối thiểu:

```text
Incident: INC-2026-0184
Severity: SEV-2
Impact: checkout success giảm tại APAC
Started: khoảng 10:12 UTC
IC: @lan
Channel/bridge: ...
Next update: 10:35 UTC
```

---

## 7. Incident Commander

IC sở hữu response process, không nhất thiết là người debug giỏi nhất.

Trách nhiệm:

- giữ overall state;
- đặt mục tiêu hiện tại;
- phân vai;
- ưu tiên mitigation;
- quản lý scope và escalation;
- phê duyệt thay đổi rủi ro;
- đảm bảo communication cadence;
- quyết định handoff/closure.

IC không nên:

- tự chạy mọi query;
- sửa code trong khi không ai giữ command;
- tranh luận sâu mọi hypothesis;
- trở thành bottleneck cho thao tác đã ủy quyền.

Vai trò chưa giao mặc định thuộc IC; vì vậy phải delegate sớm khi incident lớn.

---

## 8. Operations Lead

Ops Lead điều phối technical response:

- chia workstreams;
- assign SMEs;
- tổng hợp hypotheses;
- kiểm soát thay đổi;
- báo kết quả cho IC;
- xác nhận mitigation/recovery.

Ví dụ workstreams:

```text
Workstream A: user impact + SLO
Workstream B: recent deployments/config
Workstream C: database/dependency
Workstream D: safe mitigation
```

Mỗi workstream có owner duy nhất và update deadline. “Mọi người cùng xem database” thường tạo
trùng lặp nhưng không ai tổng hợp.

---

## 9. Communications Lead

Comms Lead:

- viết internal/external updates;
- giữ thông điệp nhất quán;
- quản lý stakeholder questions;
- phối hợp support/legal/security;
- không suy đoán root cause;
- cập nhật theo cadence kể cả không có tiến triển.

Update tốt:

```text
What:
  Checkout completion đang giảm ở APAC.

Impact:
  Khoảng 18% attempts thất bại; EU/US bình thường.

Action:
  Đang chuyển traffic khỏi region bị ảnh hưởng.

Next update:
  10:50 UTC.
```

Không copy raw stack trace hoặc internal topology vào thông báo customer.

---

## 10. Scribe và timeline keeper

Scribe ghi:

- observations;
- alerts;
- queries/links;
- hypotheses;
- decisions;
- actions và owner;
- kết quả;
- changes;
- communication;
- handoffs.

Format:

```text
10:18 UTC | OBSERVATION | checkout 5xx 18% tại ap-southeast
10:20 UTC | HYPOTHESIS  | payment dependency timeout
10:22 UTC | TEST        | Tempo shows payment span normal
10:23 UTC | RESULT      | hypothesis weakened
10:25 UTC | DECISION    | rollback checkout v42
10:29 UTC | RESULT      | 5xx giảm còn 2%
```

Scribe không cần sửa văn đẹp trong incident. Functional, timestamped và searchable quan trọng
hơn.

---

## 11. Subject Matter Experts và responders

SME:

- điều tra phạm vi được giao;
- ghi query/evidence;
- báo confidence và uncertainty;
- không tự ý thay production ngoài control;
- trả lại kết luận cho Ops Lead.

Responder update:

```text
Finding:
  DB latency bình thường.

Evidence:
  p99 < 20ms; connection errors không tăng.

Scope:
  prod APAC 10:00–10:30 UTC.

Confidence:
  medium.

Next:
  kiểm tra pool saturation ở application.
```

“Không thấy gì” phải kèm query/time range/tenant; nếu không người khác sẽ lặp lại.

---

## 12. Command post

Mỗi incident có:

- canonical chat channel;
- voice/video bridge khi cần;
- live incident document;
- incident record/ticket;
- dashboard/query links;
- stakeholder update location.

Nguyên tắc:

```text
one command channel
one live state
one current IC
```

Side channel có thể dùng cho workstream, nhưng quyết định và finding quan trọng phải quay về
canonical record.

Command tooling cần failure domain hợp lý. Không phụ thuộc duy nhất vào hệ thống đang gặp sự cố.

---

## 13. Live incident state document

Đặt thông tin quan trọng ở đầu:

```yaml
incident: INC-2026-0184
severity: SEV-2
status: mitigating
incident_commander: lan
operations_lead: minh
communications_lead: an
impact: checkout failures in APAC
started_at: 2026-07-30T10:12:00Z
current_objective: shift traffic from affected region
next_update_at: 2026-07-30T10:50:00Z
links:
  dashboard: ...
  channel: ...
```

Sau đó:

- known/unknown;
- hypotheses;
- workstreams;
- decisions/actions;
- timeline;
- recovery criteria.

Doc sống là working memory, không phải postmortem hoàn chỉnh.

---

## 14. Handoff rõ ràng

Handoff gồm:

- current impact/severity;
- roles;
- mitigation state;
- hypotheses/evidence;
- ongoing changes;
- safety constraints;
- open actions;
- next update;
- access/tool issues.

Protocol:

```text
outgoing IC summarizes
  → incoming IC asks questions
  → incoming IC explicitly accepts
  → channel announces new IC
  → outgoing stays overlap window
```

Không handoff chỉ bằng link document.

Với incident dài, rotation bảo vệ judgment và sức khỏe responder.

---

## 15. Human factors

Incident tạo:

- tunnel vision;
- confirmation bias;
- action bias;
- sunk-cost bias;
- fatigue;
- authority gradient;
- communication overload.

Guardrails:

- IC tách khỏi deep debugging;
- hypothesis board;
- peer check cho risky change;
- timebox workstream;
- rest/rotation;
- explicit dissent;
- stop conditions;
- checklist ngắn.

Không đánh giá năng lực con người dựa trên quyết định nhìn lại với thông tin mà họ chưa có lúc
đó.

---

## 16. Detection sources

Detection defense in depth:

| Source | Điểm mạnh | Điểm mù |
|---|---|---|
| SLO/symptom alert | gắn user impact | có thể trễ/aggregate |
| Component alert | chẩn đoán nhanh | noise, không chứng minh impact |
| Synthetic probe | end-to-end | coverage hữu hạn |
| Customer report | experience thật | trễ, thiếu context |
| Business KPI | outcome | attribution khó |
| Security detection | misuse/threat | false positives |
| Dependency status | external context | không phản ánh tenant mình |

Theo dõi **detection source** trong incident data để tìm monitoring gaps.

Nếu customer luôn phát hiện trước, alerting strategy chưa đạt.

---

## 17. Actionable alert contract

Page phải trả lời:

- cái gì xấu;
- ai bị ảnh hưởng;
- mức nào;
- bắt đầu khi nào;
- owner;
- dashboard/runbook;
- action đầu tiên;
- labels để route/dedup.

Ví dụ:

```yaml
labels:
  severity: page
  service: checkout
  team: commerce
  environment: production
annotations:
  summary: Checkout availability SLO burning fast
  impact: Customers may fail to place orders
  dashboard: https://grafana/...
  runbook: https://docs/...
```

Không nhét giá trị cardinality cao vào labels của alert.

---

## 18. Grouping, deduplication, inhibition và silence

Alertmanager:

- **grouping**: gộp alerts liên quan;
- **deduplication**: tránh gửi cùng state lặp;
- **routing**: tới đúng receiver;
- **inhibition**: suppress symptom phụ khi cause-level alert phù hợp đang firing;
- **silence**: mute theo matcher trong thời gian.

Guardrails:

- silence có owner/reason/expiry;
- inhibition test tránh che user-impact alert;
- group không gom nhiều incidents khác nhau;
- route fallback tồn tại;
- heartbeat kiểm chứng delivery.

Alert flood trong sự cố là một incident response failure, không chỉ vấn đề UX.

---

## 19. Alert symptom, dashboard diagnosis

Page trên symptom:

```text
user-visible availability/latency/data correctness
```

Chẩn đoán bằng:

- dependency;
- saturation;
- queue;
- error reason;
- deployment/config;
- infrastructure.

Không page riêng từng nguyên nhân có thể xảy ra nếu không có action độc lập.

Prometheus guidance ưu tiên ít alert, gắn user pain, và link console để pinpoint cause.

Cause alert vẫn hữu ích khi:

- cần hành động trước user impact;
- capacity sắp cạn;
- redundancy đã mất;
- data corruption/security risk;
- automation cần signal.

---

## 20. SLO burn trong triage

SLO burn cho biết:

- impact có thật không;
- tốc độ tiêu thụ error budget;
- scope theo region/tenant/operation;
- mitigation có cải thiện không.

Đừng chỉ nhìn aggregate:

```promql
sum(rate(http_server_requests_seconds_count{
  service="checkout",
  outcome="SERVER_ERROR"
}[5m]))
/
sum(rate(http_server_requests_seconds_count{
  service="checkout"
}[5m]))
```

Break down bounded dimensions:

- region;
- route;
- status class;
- version;
- dependency;
- tenant tier.

Không group theo user/request ID.

---

## 21. Alert delivery là một pipeline

```text
condition
  → rule evaluation
  → pending
  → firing
  → Alertmanager/Grafana Alerting
  → route/group
  → integration
  → device/person
  → acknowledgement
```

Khi page “không tới”, kiểm tra từng hop.

Metrics:

- rule evaluation errors/duration;
- active/pending/firing state;
- notification failures/latency;
- integration response;
- escalation;
- acknowledgement.

Dead-man/heartbeat và synthetic notification giúp kiểm chứng end-to-end.

---

## 22. Năm phút đầu

Checklist:

```text
1. Acknowledge
2. Validate signal
3. Assess user/data/security impact
4. Check current/ongoing changes
5. Declare/escalate if criteria met
6. Open command channel/live doc
7. Assign roles
8. Choose safe first mitigation
```

Câu hỏi:

- service thực sự xấu hay telemetry xấu?
- global hay một cohort?
- đang tăng hay ổn định?
- data có nguy cơ mất/corrupt?
- rollback/failover/degrade có sẵn?
- cần specialist nào?

Đừng dành năm phút đầu để tối ưu một query phức tạp.

---

## 23. Impact assessment

Tách:

| Dimension | Ví dụ |
|---|---|
| Users | 18% checkout attempts |
| Geography | APAC only |
| Feature | submit order, read unaffected |
| Data | no confirmed loss; duplicate risk |
| Time | since 10:12 UTC |
| Business | payment conversion down |
| Security | none known |
| Workaround | retry may duplicate, không khuyến nghị |

Ghi:

```text
confirmed impact
suspected impact
explicitly unaffected
unknown
```

Không biến “chưa có bằng chứng data loss” thành “không có data loss”.

---

## 24. Scope và blast radius

Bắt đầu từ ngoài vào:

```text
global
  → region/cluster
  → tenant/customer cohort
  → service/version
  → route/operation
  → instance/request
```

So sánh healthy vs unhealthy cohort:

- version;
- zone/node;
- region;
- feature flag;
- request type;
- dependency shard;
- tenant tier.

Một dimension phân tách rõ thường có giá trị hơn 20 panels aggregate.

Kiểm tra telemetry coverage trước khi kết luận cohort không bị ảnh hưởng.

---

## 25. Thời gian và clock normalization

Timeline cần một chuẩn, thường UTC.

Ghi cả:

- event time;
- ingestion time;
- detection time;
- observation time;
- action time.

```text
application timestamp 10:12:03
log visible          10:12:25
alert evaluated      10:13:00
page delivered       10:13:18
```

Clock skew, batching, queue và indexing làm các signal lệch nhau.

Không sắp timeline chỉ theo thứ tự message trong chat.

---

## 26. Known, unknown và hypotheses

Board:

```text
KNOWN
  5xx tăng ở checkout v42 tại APAC

UNKNOWN
  request có tới payment không?

HYPOTHESIS
  connection pool checkout bị cạn

PREDICTION
  active connections chạm max và wait time tăng

TEST
  query pool metrics + traces

RESULT
  supported / weakened / rejected
```

Hypothesis không có prediction/test chỉ là câu chuyện.

Ghi rejected hypotheses để không lặp và để postmortem hiểu đường điều tra.

---

## 27. Mitigate trước, root-cause sau

Mitigation có thể:

- rollback;
- shift traffic;
- disable feature;
- shed load;
- scale có kiểm soát;
- isolate tenant;
- switch dependency;
- enter read-only;
- stop writes để bảo vệ integrity.

```text
service restored
  ≠ root cause known
```

Đừng trì hoãn reversible mitigation an toàn chỉ để chứng minh nguyên nhân.

Nhưng preserve evidence trước nếu mitigation phá mất state quan trọng và việc chờ ngắn không
làm impact tăng nguy hiểm.

---

## 28. Change freeze và rollback

Trong incident:

- freeze unrelated deploys/config;
- inventory changes gần mốc impact;
- xác định rollback boundary;
- một owner cho mỗi change;
- record before/after;
- canary nếu thời gian cho phép;
- không chồng nhiều thay đổi không quan sát được.

Rollback không luôn an toàn:

- schema/data migration không backward compatible;
- queued events dùng format mới;
- credential rotation;
- feature flag state;
- downstream contract.

Runbook phải ghi “roll back được tới đâu”, không chỉ một nút rollback.

---

## 29. Mitigation patterns

| Pattern | Khi dùng | Risk |
|---|---|---|
| Rollback | recent reversible change | incompatibility |
| Traffic shift | region/cluster isolated | overload healthy side |
| Load shedding | bảo vệ core path | intentional errors |
| Feature disable | optional path lỗi | business impact |
| Read-only | data integrity risk | writes unavailable |
| Scale out | capacity bottleneck thật | downstream overload |
| Rate limit tenant | noisy neighbor | fairness/customer impact |
| Cache bypass/flush | corruption/staleness | load spike |

Mỗi pattern cần:

- entry criteria;
- command/API;
- approval;
- validation;
- rollback/failback.

---

## 30. Decision log

Decision entry:

```text
10:25 UTC
Decision: rollback checkout v42 → v41
Owner: minh
Reason: impact started 3m after v42 reached APAC; v41 healthy elsewhere
Alternatives: traffic shift, feature disable
Risk: DB migration is backward compatible per release plan
Abort: data errors increase or rollback > 10m
Expected: 5xx decreases within 5m
Result: confirmed at 10:31 UTC
```

Decision log giúp:

- handoff;
- tránh tranh luận lặp;
- biết assumption lúc đó;
- đánh giá response;
- xây postmortem công bằng.

---

## 31. Evidence preservation

Preserve có chọn lọc:

- dashboard snapshots/query definitions;
- relevant logs/traces/profiles;
- deployment/config diffs;
- feature flags;
- topology/ring state;
- queue/WAL/lag;
- audit events;
- command history;
- synthetic results.

Không:

- copy toàn bộ customer data vào incident doc;
- kéo production database dump tùy tiện;
- tăng retention không approval;
- ghi secrets/tokens;
- phá chain of custody cho security incident.

Evidence có access, retention và classification policy riêng.

---

## 32. Metrics workflow

Thứ tự:

```text
SLI/impact
  → traffic/errors/latency
  → saturation
  → dependency
  → cohort
  → recent changes
```

PromQL examples:

```promql
# Error ratio theo version
sum by (service_version) (
  rate(http_server_request_duration_seconds_count{
    service_name="checkout",
    http_response_status_code=~"5.."
  }[5m])
)
/
sum by (service_version) (
  rate(http_server_request_duration_seconds_count{
    service_name="checkout"
  }[5m])
)
```

```promql
# Queue utilization
max by (cluster, exporter) (
  otelcol_exporter_queue_size
  /
  clamp_min(otelcol_exporter_queue_capacity, 1)
)
```

Ghi query, time range, step và datasource/tenant để tái lập.

---

## 33. Logs workflow

Bắt đầu bằng bounded selector:

```logql
{service_name="checkout", environment="production"}
  | json
  | level="ERROR"
```

Sau đó refine:

```logql
{service_name="checkout", environment="production"}
  | json
  | trace_id="<known-trace-id>"
```

Tìm:

- error templates/counts;
- state transitions;
- dependency codes;
- retry;
- config/version;
- leader/ring;
- data identifiers đã pseudonymize.

Không bắt đầu bằng regex toàn cluster trong 30 ngày.

Log absence có thể do pipeline lỗi, sampling, wrong tenant hoặc code path không log; không tự
chứng minh event không xảy ra.

---

## 34. Traces workflow

Chọn trace từ:

- exemplar;
- error log trace ID;
- known failed synthetic/request;
- Tempo search bounded attributes.

TraceQL example:

```traceql
{
  resource.service.name = "checkout"
  && span.status = error
  && resource.deployment.environment.name = "production"
}
```

Phân tích:

- critical path;
- span lỗi đầu tiên;
- parent/child timing;
- retries/fan-out;
- queue delay;
- dependency cohort;
- missing spans;
- version/region.

Trace là sampled request. Không suy rộng tỷ lệ population từ một trace đẹp/xấu.

---

## 35. Profiles workflow

Khi CPU/latency/allocation tăng:

- chọn đúng service/version/region/time;
- so sánh trước/sau;
- diff healthy/unhealthy cohort;
- xem CPU, wall, allocation, lock profile phù hợp;
- link trace/profile nếu có.

Câu hỏi:

```text
CPU dùng ở function nào?
wall time chờ ở đâu?
allocation tăng từ code path nào?
mutex/blocking thay đổi không?
```

Profile không cho biết user impact trực tiếp. Dùng metrics xác nhận scope, traces/logs xác nhận
request path.

---

## 36. eBPF và network evidence

Khi instrumentation thiếu:

- TCP connect/reset/retransmit;
- DNS latency/failure;
- syscall/block I/O;
- scheduler/off-CPU;
- network flow policy;
- service map.

eBPF giúp trả lời “kernel/network đang làm gì”, nhưng:

- cần privilege;
- symbol/context có thể thiếu;
- sampling/drop;
- NAT/service mesh làm attribution khó;
- payload có privacy risk;
- overhead phải bounded.

Không triển khai agent privileged lần đầu ngay trong SEV-1 nếu chưa chuẩn bị.

---

## 37. Correlation workflow

```text
SLO burn/exemplar
  → representative trace
  → failed span/dependency
  → correlated logs
  → metrics/profile của cohort
  → recent change
```

Correlation keys:

- service/resource identity;
- trace/span ID;
- deployment version;
- region/zone;
- route;
- timestamp;
- tenant.

Nếu link rỗng:

1. kiểm tra retention;
2. tenant mapping;
3. time window;
4. sampling;
5. propagation;
6. datasource UID/config.

Đừng kết luận “không có logs” từ một link cấu hình sai.

---

## 38. Compare cohorts

So sánh có control:

| Unhealthy | Control |
|---|---|
| version v42 | version v41 |
| region APAC | EU cùng traffic shape |
| feature on | feature off |
| node pool new | node pool old |
| tenant class A | same class B |

Giữ các dimensions khác càng giống càng tốt.

Queries:

```text
same time window
same traffic class
same aggregation
different suspected dimension
```

Nếu control cũng xấu, hypothesis “chỉ v42” yếu đi. Negative result là progress.

---

## 39. Recent changes

Annotate:

- application deploy;
- infrastructure change;
- config/feature flag;
- schema migration;
- certificate/secret rotation;
- autoscaling;
- traffic mix;
- dependency release;
- quota/retention policy.

“What changed?” là điểm khởi đầu tốt vì hệ thống thường giữ trạng thái cho tới khi input/change
tác động.

Nhưng:

```text
change gần thời gian
  ≠ change gây incident
```

Kiểm tra prediction và cohort; tránh rollback mọi thứ chỉ vì chúng mới.

---

## 40. Dependency và topology

Service map/catalog cho biết:

- upstream/downstream;
- sync/async;
- data store;
- external provider;
- shared infrastructure;
- owner/on-call.

Triage:

```text
is dependency failing?
or caller misusing it?
or shared cause affects both?
```

Ví dụ checkout và payment cùng latency tăng có thể do:

- payment lỗi;
- checkout retry storm;
- shared DNS/network;
- telemetry clock skew.

Correlation không chứng minh hướng nhân quả.

---

## 41. Distributed-system failure patterns

Kiểm tra:

- timeout hierarchy;
- retry amplification;
- circuit breaker;
- queue lag;
- partial failure;
- split brain/quorum;
- stale cache;
- hot shard;
- clock skew;
- backpressure;
- thundering herd;
- eventual consistency;
- duplicate/out-of-order.

Một error rate aggregate có thể che:

```text
1 hot shard = 100% failure
99 shards   = healthy
aggregate   = 1% failure
```

Break down theo bounded shard/region/partition khi architecture yêu cầu.

---

## 42. Khi observability pipeline cũng lỗi

Dấu hiệu:

- traffic business ổn nhưng metrics biến mất;
- logs/traces cùng lúc trễ;
- Collector queue/drop tăng;
- canary missing;
- datasource query error;
- timestamp kỳ lạ;
- một tenant mất dữ liệu.

Runbook:

```text
check independent blackbox/business signal
  → collector internal telemetry
  → backend write/query SLO
  → synthetic canary
  → compare alternate region/tenant
```

Gắn confidence vào kết luận khi evidence source degraded.

Không restart toàn monitoring stack rồi mất thêm evidence.

---

## 43. Active tests và hypothesis testing

Test tốt:

- có prediction;
- phân biệt được hypotheses;
- risk thấp;
- reversible;
- bounded;
- có control;
- result observable.

Ví dụ:

```text
Hypothesis:
  pool cạn do một dependency endpoint.

Test:
  route 1% canary traffic sang healthy endpoint.

Prediction:
  pool wait và latency giảm cho canary.
```

Ghi cả result không như dự đoán.

Active test có thể thay state, warm cache, tăng logs hoặc tạo load; xem nó như production
change.

---

## 44. Query reproducibility

Mỗi finding lưu:

```yaml
datasource: mimir-prod
tenant: prod-commerce
query: |
  ...
from: 2026-07-30T10:00:00Z
to: 2026-07-30T10:40:00Z
step: 30s
timezone: UTC
dashboard_version: 9f83c1
result_summary: error isolated to v42
```

Screenshot hữu ích cho communication nhưng không đủ tái lập.

Query result có thể thay do:

- late data;
- retention;
- recording-rule recomputation;
- backend fix;
- dashboard variable;
- schema.

Lưu query definition và critical evidence theo policy.

---

## 45. Debugging safety

Trước thao tác:

- blast radius;
- quyền;
- data integrity;
- customer impact;
- rollback;
- observability;
- timeout;
- owner/approval.

Rủi ro phổ biến:

- `kubectl delete` nhầm scope;
- query scan làm backend quá tải;
- bật DEBUG toàn fleet;
- heap dump chứa secrets;
- restart xóa state;
- cache flush tạo load;
- retry manual tạo duplicate transaction;
- copy customer data ra ngoài boundary.

Trong incident, urgency không xóa security/safety; nó làm guardrail càng quan trọng.

---

## 46. Internal communication cadence

Update theo cadence, ví dụ 15–30 phút tùy severity.

Template:

```text
Status:
  Mitigating

Impact:
  18% APAC checkout attempts fail; no confirmed data loss

Since last update:
  Rolled back v42; errors declining

Current actions:
  Validate queue drain and duplicate orders

Risks/unknowns:
  Duplicate payment risk under investigation

Next update:
  11:05 UTC
```

“Không có thay đổi đáng kể” vẫn là update hợp lệ.

---

## 47. Responder communication

Trong command channel:

- prefix loại message: `OBS`, `HYP`, `ACTION`, `RESULT`, `DECISION`;
- một owner cho action;
- dùng UTC;
- link evidence;
- thread/workstream khi cần;
- không paste noise lớn;
- gọi tên recipient cho request.

Ví dụ:

```text
ACTION @minh: rollback checkout APAC v42→v41
Expected completion 10:30 UTC
Abort if migration errors appear
```

Communication protocol giảm cognitive load và giúp timeline extraction.

---

## 48. External communication

Customer update tập trung:

- observed impact;
- affected functionality/region;
- start time nếu biết;
- action đang làm;
- workaround an toàn;
- next update.

Tránh:

- root cause chưa xác nhận;
- blame vendor/team;
- internal hostnames;
- exploit/security detail;
- promise deadline không có cơ sở;
- nói “fully resolved” trước validation.

Status page là một product surface có owner, approval và availability riêng.

---

## 49. Security, privacy và regulated incidents

Nếu nghi security/data exposure:

- kích hoạt security incident process;
- preserve evidence/chain of custody;
- giới hạn channel/access;
- phối hợp privacy/legal/compliance;
- không tự ý xóa/rotate làm mất evidence;
- vẫn giảm active harm theo chỉ huy phù hợp.

Telemetry có thể chứa:

- user identity;
- tokens/headers;
- SQL/payload;
- IP/location;
- topology;
- source symbols.

Incident doc không phải nơi miễn trừ data policy.

---

## 50. Incident kéo dài

Chuẩn bị:

- shift schedule;
- overlap handoff;
- food/rest;
- decision authority;
- timezone;
- outstanding risks;
- workstream state;
- communication cadence;
- executive/support rotation.

Technical:

- dashboard absolute time;
- state snapshot;
- config version;
- queue/backlog trend;
- mitigation expiry;
- temporary access/feature flags.

Không để temporary mitigation trở thành permanent unknown state vì ca sau không biết.

---

## 51. Recovery criteria

Define trước khi close:

- user-facing SLI trở lại target;
- error rate/latency ổn định đủ window;
- critical transactions thành công;
- queue/backlog drain;
- data integrity reconciliation;
- no duplicate/loss ngoài known scope;
- dependent services healthy;
- alerts resolve đúng;
- telemetry pipeline healthy;
- mitigation không sắp hết hạn bất ngờ.

```text
one successful request
  ≠ recovery
```

Cần stability window phù hợp chu kỳ tải/cache/queue.

---

## 52. Validate mitigation

So sánh:

```text
before
  → during action
  → after
  → control cohort
```

Kiểm tra both:

- expected improvement;
- unintended side effects.

Ví dụ rollback giảm 5xx nhưng:

- latency tăng;
- queue tiếp tục tích;
- old version duplicate payment;
- CPU healthy region bão hòa;
- data schema incompatible.

Mitigation result phải gắn với prediction; temporal correlation đơn thuần chưa đủ.

---

## 53. Close response

IC chỉ close khi:

- recovery criteria đạt;
- monitoring ổn định;
- remaining risk explicit;
- temporary changes có owner/expiry;
- customer/internal final update;
- follow-up owner;
- postmortem trigger quyết định;
- evidence/timeline lưu.

Có thể chuyển:

```text
active incident
  → monitoring
  → resolved
```

Trong monitoring phase vẫn có owner và reopen criteria.

Đừng giữ bridge mở vô hạn chỉ vì root cause chưa biết; điều tra dài hạn chuyển sang problem
management với ownership rõ.

---

## 54. Postmortem triggers

Định nghĩa trước:

- user-visible impact trên threshold;
- data loss/corruption;
- security/privacy;
- manual emergency intervention;
- resolution time dài;
- monitoring failed/customer detected;
- repeated near miss;
- surprising failure mode;
- stakeholder request.

Near miss đáng review khi:

- chỉ may mắn không có impact;
- một guardrail cuối cùng cứu hệ thống;
- blast radius có thể rất lớn;
- response bộc lộ process gap.

Không dùng severity thấp làm lý do bỏ qua learning có giá trị.

---

## 55. Blameless không nghĩa accountability bằng không

Blameless hỏi:

```text
Tại sao quyết định đó hợp lý với thông tin và incentives lúc đó?
Hệ thống/guardrail/process nào cho phép failure lan?
Làm sao giúp người tiếp theo thành công?
```

Vẫn cần:

- facts;
- owners;
- deadlines;
- review;
- policy enforcement;
- hành vi cố ý/malicious xử lý bằng process phù hợp.

Tránh:

- “human error” là root cause cuối;
- dùng passive voice để che decision;
- ca ngợi heroics thay sửa system;
- action “cẩn thận hơn”.

---

## 56. Postmortem structure

```yaml
incident: INC-2026-0184
status: final
authors: [...]
reviewers: [...]
severity: SEV-2
services: [shop.checkout]
summary: ...
impact: ...
detection: ...
timeline: ...
root_and_contributing_factors: ...
trigger: ...
resolution: ...
what_went_well: ...
what_went_poorly: ...
where_we_got_lucky: ...
action_items: ...
```

Tách:

- **trigger**: event kích hoạt;
- **contributing factors**: điều kiện làm xảy ra/lan;
- **impact multipliers**;
- **detection/response gaps**.

Một “root cause” duy nhất thường quá đơn giản cho distributed system.

---

## 57. Timeline reconstruction

Nguồn:

- live doc/chat;
- alert history;
- deploy/audit;
- metrics/logs/traces;
- ticket/status page;
- on-call events;
- feature flags;
- cloud/provider events.

Normalize UTC và đánh dấu:

| Type | Ví dụ |
|---|---|
| System | error rate started |
| Detection | alert fired |
| Human | incident declared |
| Action | rollback started |
| Communication | customer update |
| Recovery | SLI stable |

Phân biệt fact với recollection. Nếu timestamp ước lượng, ghi rõ.

---

## 58. Causal analysis

Kỹ thuật:

- five whys có kiểm soát;
- causal graph;
- fault tree;
- change analysis;
- barrier analysis;
- timeline comparison.

Ví dụ:

```text
trigger: v42 changed pool key
  → too many pools
  → connection exhaustion
  → retries amplified load
  → checkout failures

barriers missing:
  pool cardinality test
  connection limit alert
  safe canary
  retry budget
```

Không dừng ở “developer cấu hình sai”. Hỏi vì sao review, tests, defaults và rollout không
ngăn/giới hạn lỗi.

---

## 59. Action items hiệu quả

Action tốt:

```yaml
action: Add pool-key cardinality integration test
owner: team-checkout
due: 2026-08-14
priority: P1
verification: test fails with v42 fixture and passes after fix
incident: INC-2026-0184
```

Ưu tiên:

1. loại bỏ hazard;
2. tự động ngăn;
3. giảm blast radius;
4. phát hiện sớm;
5. cải thiện runbook/training.

“Document thêm” thường yếu hơn guardrail tự động, nhưng vẫn hữu ích khi knowledge gap là thật.

---

## 60. Action lifecycle và recurrence

States:

```text
proposed
  → accepted
  → in progress
  → implemented
  → verified
  → closed
```

Không close khi PR merge nếu outcome chưa verify.

Theo dõi:

- overdue;
- repeated incident trước action;
- action type;
- owner/team load;
- risk reduction;
- regression test;
- exception.

Recurring incident cần liên kết previous postmortems; tránh viết lại cùng bài học mà không xử
lý systemic constraint.

---

## 61. Incident metrics

Metrics hữu ích:

| Metric | Ý nghĩa |
|---|---|
| Time to detect | monitoring capability |
| Time to acknowledge | on-call delivery |
| Time to declare | escalation/process |
| Time to mitigate | response effectiveness |
| Time to recover | technical + operational |
| Detection source | monitoring gaps |
| Customer-impact minutes | severity thực |
| Repeat rate | learning effectiveness |
| Action completion/verification | follow-through |

Tránh dùng MTTR đơn lẻ để xếp hạng cá nhân/team.

Mix severity, complexity và detection khác nhau làm so sánh thô gây incentive xấu.

---

## 62. Automation và AI-assisted investigation

Automation có thể:

- tạo channel/doc;
- assign roles/on-call;
- chụp dashboards/config;
- annotate deploy;
- chạy safe queries;
- cập nhật timeline;
- đề xuất runbook;
- draft summary.

AI có thể:

- tóm tắt;
- gom duplicate symptoms;
- đề xuất hypotheses;
- tìm incident tương tự;
- sinh query draft.

Guardrails:

- luôn link source/evidence;
- phân biệt fact/inference;
- không tự chạy destructive action;
- tenant/access boundary;
- redact sensitive data;
- human approval;
- audit.

Fluent summary không đồng nghĩa causal analysis đúng.

---

## 63. Training, drills và continuous improvement

Practice:

- tabletop;
- game day;
- Wheel of Misfortune/replay incident cũ;
- alert delivery drill;
- IC/comms training;
- handoff exercise;
- backup tool exercise;
- chaos experiment;
- postmortem review club.

Đo:

- declare/role assignment time;
- communication clarity;
- runbook usability;
- access failures;
- telemetry gaps;
- recovery verification;
- follow-up completion.

Mỗi drill tạo findings và regression exercise. Training không chỉ là slide hàng năm.

---

## 64. Workshop, checklist và câu hỏi tự kiểm tra

### Workshop: checkout SEV-2

Scenario:

```text
10:12 UTC
  checkout availability giảm ở APAC

10:13
  multi-window burn alert page

10:16
  incident declared, roles assigned

10:20
  scope isolated to version v42

10:25
  rollback approved

10:31
  5xx giảm

10:42
  queue drained, synthetic order successful

10:55
  monitoring phase

11:15
  resolved, postmortem assigned
```

Evidence path:

1. SLO confirms impact.
2. version cohort separates v42/v41.
3. traces show wait before database client call.
4. pool metrics show connection exhaustion.
5. logs show pool keys exploding by dynamic region value.
6. rollback reduces error.
7. data reconciliation finds no loss, two duplicates corrected.

### Active incident checklist

- [ ] Alert/problem report được acknowledge.
- [ ] Impact và data/security risk được đánh giá.
- [ ] Incident được declare theo criteria.
- [ ] Severity và IC rõ.
- [ ] Ops/Comms/Scribe được giao khi cần.
- [ ] Canonical channel/live doc tồn tại.
- [ ] Next communication time được đặt.
- [ ] Known/unknown/hypotheses tách.
- [ ] Workstreams có owner/deadline.
- [ ] First mitigation ưu tiên giảm impact.
- [ ] Changes được freeze/ghi log.
- [ ] Risky actions có approval/abort.
- [ ] Queries ghi tenant/time range.
- [ ] Evidence nhạy cảm được bảo vệ.
- [ ] Handoff explicit.
- [ ] Recovery criteria được kiểm tra.
- [ ] Queue/data integrity/telemetry cũng phục hồi.
- [ ] Temporary changes có owner/expiry.
- [ ] Final communication đã gửi.
- [ ] Postmortem/actions được assign.

### Postmortem checklist

- [ ] Summary và impact định lượng.
- [ ] Detection source/gap rõ.
- [ ] Timeline dùng UTC và facts.
- [ ] Trigger/contributing factors/barriers tách.
- [ ] Response effectiveness được review.
- [ ] What went well/poorly/lucky.
- [ ] Không blame cá nhân.
- [ ] Actions có owner/due/verification.
- [ ] Reviewers phê duyệt.
- [ ] Postmortem được chia sẻ đúng access.
- [ ] Actions được theo dõi tới Verified.

### Câu hỏi tự kiểm tra

1. Vì sao incident response không bắt đầu bằng root cause?
2. Alert khác incident thế nào?
3. Severity nên dựa trên component hay impact?
4. Khi nào nên declare sớm?
5. IC khác technical lead ở đâu?
6. Ops Lead và Comms Lead chịu trách nhiệm gì?
7. Live state doc khác postmortem thế nào?
8. Vì sao handoff cần explicit acceptance?
9. Symptom alert tốt hơn cause alert trong trường hợp nào?
10. Grouping/inhibition sai có thể che impact ra sao?
11. Năm phút đầu cần trả lời gì?
12. Confirmed, suspected và unknown impact khác nhau thế nào?
13. Hypothesis tốt cần prediction/test gì?
14. Vì sao negative result có giá trị?
15. Khi nào preserve evidence trước mitigation?
16. Rollback có thể nguy hiểm trong tình huống nào?
17. Metrics/logs/traces/profiles trả lời câu hỏi khác nhau ra sao?
18. Log absence có chứng minh event không xảy ra không?
19. Trace sampled có đại diện toàn population không?
20. Recent change có chứng minh causation không?
21. Recovery criteria cần gì ngoài error rate giảm?
22. Blameless khác no-accountability thế nào?
23. Trigger khác contributing factor ra sao?
24. Action item tốt cần verification gì?
25. AI summary cần guardrail nào?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Incident response và troubleshooting

- [Google SRE Workbook – Incident Response](https://sre.google/workbook/incident-response/)
- [Google SRE – Managing Incidents](https://sre.google/sre-book/managing-incidents/)
- [Google SRE – Effective Troubleshooting](https://sre.google/sre-book/effective-troubleshooting/)
- [Google SRE – Emergency Response](https://sre.google/sre-book/emergency-response/)

### Postmortem và learning

- [Google SRE – Postmortem Culture](https://sre.google/sre-book/postmortem-culture/)
- [Google SRE Workbook – Postmortem Culture](https://sre.google/workbook/postmortem-culture/)
- [Google SRE – Example Postmortem](https://sre.google/sre-book/example-postmortem/)
- [Google SRE Incident Management Guide](https://sre.google/resources/practices-and-processes/incident-management-guide/)

### Alerting và incident tooling

- [Prometheus alerting practices](https://prometheus.io/docs/practices/alerting/)
- [Prometheus alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Alertmanager configuration](https://prometheus.io/docs/alerting/latest/configuration/)
- [Grafana incident response and learning](https://grafana.com/docs/learning-hub/is-grafana-cloud-right-for-me/06-test-and-respond-with-turnkey-solutions/01-incident-response/)
- [Grafana IRM configuration](https://grafana.com/docs/learning-paths/grafana-irm-configuration/)

### Telemetry correlation

- [OpenTelemetry Context](https://opentelemetry.io/docs/specs/otel/context/)
- [OpenTelemetry Propagators API](https://opentelemetry.io/docs/specs/otel/context/api-propagators/)
- [OpenTelemetry Baggage security considerations](https://opentelemetry.io/docs/concepts/signals/baggage/)

### Chủ đề tiếp theo

Sau Incident Response with Observability, chủ đề mở rộng tiếp theo là:

> **Database Observability & Performance Engineering – workload metrics, query
> tracing, connection pools, transactions, locks, execution plans và capacity.**
>
> Đọc tiếp:
> [Database Observability & Performance Engineering](database_observability_performance.md).

---

*Cập nhật lần cuối: 2026-07-30*
