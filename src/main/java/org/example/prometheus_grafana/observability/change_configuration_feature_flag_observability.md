# Change, Configuration & Feature Flag Observability – Từ Desired State đến User Exposure

> Mục tiêu của bài này là nhìn thấy mọi thay đổi code, hạ tầng, cấu hình và feature flag;
> biết desired state, observed state và effective state có khớp nhau không; đồng thời liên
> kết thay đổi với phiên bản, nhóm người dùng, SLO và business outcome.
>
> Baseline tham chiếu: OpenFeature Specification, OpenTelemetry Feature Flag Semantic
> Conventions, OpenGitOps Principles và tài liệu Kubernetes hiện hành. OpenTelemetry feature
> flag conventions đang ở trạng thái Development nên phải pin schema và có migration plan.
>
> Evaluation context có thể chứa user/tenant/device identity; configuration và Secret có thể
> chứa credential. Không ghi raw value nhạy cảm vào log, trace hay metric. Áp dụng allowlist,
> pseudonymization, encryption, access audit và retention theo mục đích.
>
> Nên đọc trước:
> [CI/CD & Software Delivery Observability](cicd_software_delivery_observability.md),
> [Kubernetes Observability](kubernetes_observability.md),
> [Telemetry Governance & FinOps](telemetry_governance_finops.md) và
> [feature flag trong system design](../../system_design/saas/feature_flags.md).

---

## 1. Thay đổi là một dependency ẩn

Hệ thống có thể suy giảm mà không deploy binary mới:

- flag được bật;
- timeout hoặc limit bị sửa;
- route/service discovery đổi;
- certificate/secret rotate;
- policy hoặc experiment đổi;
- controller reconcile desired state mới;
- thao tác tay tạo drift.

Vì vậy dashboard chỉ đánh dấu code deployment sẽ bỏ sót nhiều nguyên nhân.

## 2. Lập inventory nguồn thay đổi

Tạo taxonomy chung:

| Loại | Ví dụ |
|---|---|
| Code/artifact | image, package, function version |
| App config | timeout, pool, retry, threshold |
| Infrastructure | compute, network, database |
| Routing/policy | traffic weight, authz, rate limit |
| Feature flag | enablement, variant, targeting |
| Secret/certificate | credential, key, trust bundle |
| Data/model | schema, rules, ML model |

Mỗi loại có owner, source of truth, approval và rollback khác nhau.

## 3. Desired, observed và effective state

- **Desired state:** điều control plane muốn.
- **Observed state:** agent/controller báo đang thấy.
- **Effective state:** application thực sự đang dùng.

```text
Git says v8 → controller observed v8 → process still serves v7
```

Reconcile thành công chưa đủ nếu process không reload hoặc request vẫn đi tới instance cũ.

## 4. Identity và version

Mọi cấu hình nên có:

- stable config/flag key;
- namespace/project;
- immutable version hoặc content digest;
- scope/environment;
- owner;
- schema version;
- source revision;
- effective timestamp.

Không dùng raw JSON làm identity. Hash chỉ hữu ích khi serialization được canonicalize.

## 5. Change event contract

Event tối thiểu:

```json
{
  "event.name": "configuration.changed",
  "event.id": "immutable-id",
  "change.id": "chg-...",
  "config.key": "checkout.timeout",
  "config.version": "v42",
  "scope": "production",
  "actor.type": "automation",
  "outcome": "success",
  "reason.code": "approved_rollout"
}
```

Lưu old/new digest hoặc variant; không lưu secret/raw customer targeting rule.

## 6. Timeline thay đổi

Phân biệt:

```text
proposed → approved → published → distributed → loaded → effective → verified
```

Một timestamp `updated_at` không đủ tìm propagation delay. Event phải idempotent, có sequence
hoặc version để xử lý duplicate và out-of-order.

## 7. SLO cho change/config platform

Ví dụ:

- 99.9% read/evaluation thành công;
- 99% thay đổi hợp lệ effective trong 60 giây;
- 99.9% instance hội tụ về desired version trong 5 phút;
- 100% production change có actor, source và audit evidence;
- kill switch đạt 99% target trong 30 giây.

Đo riêng correctness, availability, freshness và convergence.

## 8. Taxonomy cấu hình

Phân loại theo rủi ro:

- bootstrap vs runtime;
- global vs tenant/user;
- functional vs operational;
- public vs confidential/secret;
- local vs remote;
- restart-required vs hot-reload;
- reversible vs irreversible;
- safety-critical vs convenience.

Policy, telemetry detail và approval nên tăng theo blast radius.

## 9. Static và dynamic configuration

Static config chỉ đổi khi build/restart, dễ tái hiện nhưng phản hồi chậm. Dynamic config đổi
runtime, giảm lead time nhưng tăng distributed state, cache, staleness và race condition.

Mỗi key cần công bố reload semantics; đừng để operator tin nó dynamic trong khi application
chỉ đọc lúc startup.

## 10. Precedence

Một giá trị có thể đến từ default, file, environment, remote provider, tenant override và
request context. Ghi precedence contract:

```text
request override > tenant override > remote config
                 > environment > file > code default
```

Telemetry nên nêu **nguồn thắng** và version, không chỉ giá trị cuối.

## 11. Load và reload

Theo dõi load/reload attempt, duration, outcome, source version, last-success time và số
instance theo effective version. Reload nên atomic:

1. fetch;
2. parse;
3. validate;
4. dựng snapshot mới;
5. swap;
6. phát health/effective event.

Không cập nhật từng field làm request thấy cấu hình nửa cũ nửa mới.

## 12. Validation trước khi publish

Validation nhiều lớp:

- cú pháp/schema;
- kiểu và range;
- tham chiếu tồn tại;
- constraint chéo field;
- policy/security;
- compatibility;
- dry-run/simulation;
- canary.

Ghi validator version và reason code. Error message tự do chỉ dùng để drill-down, không làm
metric label.

## 13. Schema và compatibility

Version hóa schema; công bố field required/optional, default và deprecation. Consumer cũ phải
xử lý field mới, còn producer mới không được xóa field khi consumer cũ vẫn chạy.

```text
schema version + config version + consumer version
```

Ba version này giúp giải thích lỗi mixed-version trong rolling deployment.

## 14. Configuration drift

Drift là chênh lệch giữa source of truth và state thực tế. Theo dõi:

- resource/instance bị drift;
- age của drift;
- diff category;
- last reconciliation;
- owner và exemption expiry.

Không đưa toàn bộ diff vào metric. Cảnh báo drift theo risk/blast radius, không chỉ số lượng.

## 15. OpenGitOps

Các nguyên tắc OpenGitOps:

1. declarative;
2. versioned và immutable;
3. pulled automatically;
4. continuously reconciled.

Telemetry cần chứng minh từng liên kết: source revision, reconcile attempt, observed revision,
health và drift. Git merge thành công không có nghĩa desired state đã effective.

## 16. Reconciliation health

Controller metrics/event:

- reconcile rate/duration;
- success/error;
- retry/backoff;
- queue depth/oldest age;
- desired vs observed revision;
- suspended/degraded;
- last successful convergence.

Reconcile loop chạy liên tục nhưng luôn thất bại không phải healthy; process uptime là tín
hiệu cần nhưng không đủ.

## 17. Infrastructure as Code

Quan sát plan/apply/destroy/import:

- change set digest;
- resource add/change/remove count;
- policy result;
- approval;
- apply duration/outcome;
- provider/API error;
- state-lock wait;
- drift after apply.

Plan có thể chứa secret; lưu reference và summary đã redact thay vì raw output.

## 18. Thay đổi thủ công và out-of-band

Manual change không phải lúc nào cũng cấm, nhất là incident, nhưng phải:

- có identity và reason;
- time-bound;
- audit actor;
- tạo reconciliation plan;
- đánh dấu dashboard;
- review sau sự cố.

Phát hiện mutation không có source revision và cảnh báo khi exception hết hạn.

## 19. Kubernetes ConfigMap

ConfigMap lưu dữ liệu cấu hình không bí mật. Theo dõi resource UID, generation,
resourceVersion, update event, mount/env delivery và application effective version.

Pod dùng ConfigMap qua environment variable thường cần restart để nhận giá trị mới; volume
projection có thể cập nhật sau nhưng ứng dụng vẫn phải reload. `immutable: true` giảm mutation
ngoài ý muốn nhưng cần resource mới cho lần đổi.

## 20. Kubernetes Secret

Không coi Kubernetes Secret tự động là vault an toàn. Tài liệu Kubernetes cảnh báo Secret
được lưu không mã hóa trong etcd theo mặc định nếu chưa bật encryption at rest; quyền tạo Pod
cũng có thể dẫn tới đọc Secret trong namespace.

Telemetry chỉ lưu secret reference/version, rotation/expiry và access result; không lưu value.
Áp dụng RBAC tối thiểu, encryption at rest và external secret manager khi phù hợp.

## 21. Environment variable

Environment variable đơn giản nhưng thường:

- chỉ đọc lúc process start;
- xuất hiện trong diagnostic dump;
- thiếu schema;
- khó biết nguồn và version;
- dễ khác nhau giữa instance.

Ghi digest allowlisted của effective non-secret config và startup timestamp; không export toàn
bộ environment.

## 22. Remote configuration

Quan sát client/provider:

- connect/auth;
- fetch/stream latency;
- update count;
- last received/applied version;
- cache age;
- parse/validation error;
- reconnect/backoff;
- stale mode.

Phân biệt control-plane unavailable với data-plane evaluation: client có cache hợp lệ vẫn có
thể phục vụ khi provider tạm mất.

## 23. Service discovery và routing policy

Endpoint, weight, retry, timeout, circuit breaker và authorization đều là config ảnh hưởng
request path. Ghi version của route/policy trên trace hoặc event khi khả thi.

Một service binary không đổi nhưng mesh policy mới có thể làm latency/error tăng; đặt marker
policy change cạnh deployment marker.

## 24. Threshold và rule

Threshold trong alert, fraud, pricing, recommendation hoặc autoscaling là logic runtime.
Telemetry cần rule set version, evaluation outcome/reason và distribution đầu ra.

Không ghi rule input nhạy cảm. Kiểm thử shadow/dry-run trước khi active và theo dõi tỷ lệ
quyết định thay đổi giữa version cũ/mới.

## 25. Feature flag dùng để làm gì?

Flag hỗ trợ:

- release tách khỏi deployment;
- progressive rollout;
- experiment;
- permission/entitlement;
- operational kill switch;
- migration;
- test production có kiểm soát.

Flag không thay thế authorization. Nếu capability nhạy cảm, server vẫn phải enforce quyền.

## 26. Các loại flag

| Loại | Ví dụ | Lifetime |
|---|---|---|
| Release | rollout feature mới | ngắn |
| Experiment | A/B variant | ngắn, có hypothesis |
| Operational | kill switch, degraded mode | dài hơn |
| Permission | plan/entitlement | dài, governance cao |
| Migration | old/new backend | đến khi chuyển xong |

Loại flag quyết định owner, SLO, cleanup và audit.

## 27. Vòng đời flag

State machine gợi ý:

```text
proposed → created → tested → ramping → fully_released
         → cleanup_due → archived
```

Rollback đưa về safe state nhưng không xóa lịch sử. Mỗi flag cần expected expiry; flag tồn
tại vĩnh viễn làm tăng số tổ hợp cần kiểm thử.

## 28. Ownership và metadata

Metadata tối thiểu:

- key ổn định;
- mô tả và type;
- owner/team;
- created/updated time;
- safe default;
- environments;
- targeting scope;
- expiry/cleanup ticket;
- dependency;
- compliance classification.

Flag không owner hoặc quá expiry cần xuất hiện trong debt dashboard.

## 29. OpenFeature

OpenFeature cung cấp vendor-neutral API cho flag evaluation, provider, hook, evaluation
context và event. Application phụ thuộc API chung thay vì SDK vendor trực tiếp, giúp thay
provider và chuẩn hóa instrumentation.

Nó không tự quyết định governance, targeting algorithm hoặc storage; platform vẫn phải thiết
kế các phần đó.

## 30. Evaluation context

Context có thể gồm application, environment, tenant, user, device và request attributes.
OpenFeature định nghĩa cách hợp nhất context ở nhiều scope với precedence.

Chỉ đưa field cần cho evaluation. Context có PII phải được phân loại, pseudonymize hoặc loại
bỏ trước telemetry; không ghi toàn bộ context để “debug cho tiện”.

## 31. Targeting và privacy

Targeting rule thường dùng region, plan, cohort hoặc hashed identity. Rủi ro:

- re-identification;
- phân biệt đối xử ngoài ý muốn;
- policy khó audit;
- context bị spoof;
- dữ liệu vượt region.

Log rule/segment version và reason code, không log raw segment membership hay thuộc tính nhạy
cảm không cần thiết.

## 32. Rollout xác định

Percentage rollout phải deterministic: cùng key/context cho cùng bucket khi cấu hình không
đổi. Ghi algorithm/version và salt scope vì đổi chúng có thể reshuffle cohort.

```text
bucket = stable_hash(flag_key, targeting_key, salt) mod 10000
```

Không dùng random mới ở mỗi request; người dùng sẽ nhảy variant và dữ liệu outcome sai.

## 33. Variant

Variant là tên ổn định như `control`, `candidate`, `large_timeout`; value là dữ liệu thực tế.
Telemetry nên ưu tiên variant vì value có thể lớn, nhạy cảm hoặc cardinality cao.

Không dùng variant chứa user ID hoặc giá trị sinh động. Mapping variant → value phải được
version hóa ở provider.

## 34. Provider lifecycle và event

OpenFeature mô tả các event như provider ready, error, configuration changed và stale; một số
context còn có reconciling/context changed.

Subscriber phải xử lý duplicate, out-of-order và startup race. Dashboard tách:

- provider không ready;
- provider error;
- configuration stale;
- evaluation lỗi dù provider ready.

## 35. Default và fallback

Mỗi evaluation cần safe default theo risk. Fallback có thể:

- fail closed cho permission/security;
- giữ cached last-known-good;
- dùng code default;
- chuyển degraded mode.

Telemetry ghi nguồn kết quả và reason: provider, cache, default, error. Không để fallback âm
thầm tạo kết quả “success”.

## 36. Cache và staleness

Đo cache hit/miss, entry age, refresh/reconnect, last-known-good version và stale-serving
duration. TTL quá ngắn làm phụ thuộc control plane; TTL quá dài làm kill switch chậm.

SLO freshness phải gắn với use case: marketing flag và safety kill switch không thể dùng cùng
một giới hạn.

## 37. Evaluation latency

Đo histogram latency theo provider, evaluation type và outcome; không label theo flag key nếu
số key lớn/churn cao. Tách local cached evaluation khỏi network fetch.

Flag evaluation nằm trên hot path cần budget rất nhỏ. Hook/instrumentation cũng phải đo
overhead để không biến quan sát thành nguyên nhân latency.

## 38. Error và evaluation reason

Phân loại:

- flag not found;
- type mismatch;
- invalid context;
- parse/config error;
- provider unavailable;
- stale/no safe value;
- forbidden;
- internal error.

Reason chuẩn hóa giúp aggregate; raw exception ở log/trace đã redact. Theo dõi cả default
rate vì hệ thống có thể trả response thành công trong khi flag platform lỗi.

## 39. OpenTelemetry feature flag conventions

OpenTelemetry feature flag conventions hiện ở trạng thái Development và mô hình hóa
evaluation dưới dạng log/event. Thuộc tính gồm key, provider, reason, variant, value, version
và context ID tùy trường hợp.

Trước khi dùng production:

- pin schema;
- allowlist attribute;
- ưu tiên variant;
- không phát raw value/context nhạy cảm;
- có cardinality và migration test.

## 40. Correlation với trace

Không tạo span riêng cho mọi local evaluation cực nhanh nếu overhead cao. Có thể thêm event
vào request span hoặc link evaluation record bằng trace ID.

Chỉ đính kèm các flag có ảnh hưởng request; hàng trăm flag không liên quan sẽ làm trace lớn.
Ghi variant/version và reason đủ để so path control/candidate.

## 41. Metric design

Metric hữu ích:

- evaluation count theo provider/outcome/reason class;
- latency histogram;
- default/fallback rate;
- provider ready/stale state;
- config propagation/convergence;
- instance count theo coarse version state;
- flag change và rollback count.

Flag key, user, tenant và context ID thường không phù hợp làm label không giới hạn.

## 42. Log và event design

Tách:

- **change event:** ai đổi rule/variant/rollout;
- **provider event:** config received/stale/error;
- **evaluation event:** request nhận variant nào;
- **exposure event:** người dùng thực sự thấy treatment;
- **outcome event:** hành vi sau exposure.

Mỗi event có ID, timestamp, schema version và privacy classification.

## 43. Experiment khác rollout

Rollout hỏi “phát hành an toàn không”; experiment hỏi “variant có gây khác biệt mong muốn
không”. Experiment cần hypothesis, randomization unit, exposure, sample size, guardrail và
analysis plan.

Không suy diễn causal effect từ dashboard trước/sau đơn giản. Canary reliability và A/B
product experiment có thể dùng cùng flag nhưng mục tiêu thống kê khác nhau.

## 44. Exposure event

Assignment không luôn bằng exposure: user có thể được gán variant nhưng chưa mở màn hình hoặc
chưa chạy code path. Phát exposure tại thời điểm treatment thực sự ảnh hưởng trải nghiệm.

Event nên có experiment/flag version, variant, pseudonymous subject, timestamp và dedup key.
Không phát lặp ở mỗi render nếu analysis cần one exposure per unit.

## 45. Outcome và giới hạn suy luận

Kết nối exposure với conversion, latency, error, support ticket và guardrail theo window đã
định nghĩa. Kiểm tra sample-ratio mismatch, novelty, seasonality và cross-device identity.

Observability cung cấp evidence; kết luận nhân quả cần thiết kế experiment và phương pháp
thống kê phù hợp.

## 46. Kill switch

Kill switch phải có:

- safe default;
- owner/on-call;
- propagation SLO;
- authentication/approval;
- dry-run hoặc exercise;
- dashboard theo effective state;
- fallback khi provider mất;
- audit và post-use review.

Nút “off” trên control plane không đủ; cần chứng minh target instance đã effective.

## 47. Dependency giữa các flag

Flag A có thể chỉ hợp lệ khi B bật hoặc schema/backend mới tồn tại. Dependency graph giúp phát
hiện cycle và thứ tự rollout.

Không encode chuỗi `if flagA && flagB && !flagC` rải rác không owner. Ghi prerequisite result
và reason, nhưng giới hạn telemetry để tránh nổ tổ hợp.

## 48. Blast radius

Ước lượng theo:

- environment/region;
- service/instance;
- tenant/user cohort;
- traffic percentage;
- data/resource scope;
- privilege;
- reversibility;
- dependency fan-out.

Approval và rollout step nên tỷ lệ với blast radius. “Chỉ đổi config” không đồng nghĩa rủi ro
thấp.

## 49. Canary configuration

Áp dụng config/flag mới cho một cohort instance hoặc traffic, so với baseline trên:

- error/latency;
- saturation;
- business guardrail;
- provider/evaluation health;
- dependency impact.

Lưu cohort membership/version ổn định. Nếu instance tự đổi cohort giữa analysis, so sánh sẽ
nhiễu.

## 50. Mixed-version compatibility

Rolling update tạo tổ hợp:

```text
old code + old config
old code + new config
new code + old config
new code + new config
```

Kiểm thử các tổ hợp có thể xảy ra. Telemetry phải cho biết code/config/flag version hiệu lực
trên từng request hoặc instance để phát hiện tổ hợp lỗi.

## 51. Rollback configuration

Rollback cần immutable snapshot/reference, compatibility check và verification. Cấu hình cũ
có thể không hợp lệ sau schema/data migration.

Ghi rollback trigger, target version, propagation, instance convergence và SLO restoration.
Giữ last-known-good nhưng không giữ secret cũ quá rotation policy.

## 52. Change freeze và emergency change

Freeze giảm rủi ro trong thời điểm nhạy cảm nhưng phải có scope và expiry. Emergency change
cần fast path có:

- actor/approver;
- reason/incident;
- giới hạn blast radius;
- audit;
- automatic expiry/reconciliation;
- review sau sự cố.

Không dùng freeze để che delivery process thiếu tin cậy.

## 53. Audit và security

Audit các hành động create/update/delete, targeting, permission, provider config, export và
emergency override. Bảo vệ integrity và đồng bộ thời gian.

Phát hiện:

- actor lạ hoặc ngoài giờ;
- privilege escalation;
- rollout tăng đột ngột;
- audit bị tắt;
- thay đổi không ticket/source;
- export hàng loạt;
- repeated denied action.

## 54. Secret observability

Quan sát metadata, không quan sát value:

- secret reference/version;
- created/rotated/expiry;
- last successful fetch;
- access denied/error;
- workload sử dụng;
- certificate days-to-expiry;
- rotation propagation.

Không dùng hash của secret như một cách “an toàn” để export: hash vẫn có thể hỗ trợ đoán với
không gian giá trị nhỏ.

## 55. Cardinality

Nguồn cardinality:

- flag/config key không giới hạn;
- user/tenant/context ID;
- raw value;
- rule ID động;
- version/digest;
- error message;
- segment/cohort tùy ý.

Dùng dimension allowlist/coarse class trong metric; giữ chi tiết ở sampled event/log/trace có
retention và quyền truy cập chặt hơn.

## 56. Chi phí và sampling

Evaluation có thể xảy ra hàng triệu lần mỗi giây; log mỗi lần là không thực tế. Chiến lược:

- metric aggregate toàn bộ;
- sample success event;
- giữ toàn bộ error/default hiếm;
- exposure deduplicate;
- tăng sample trong rollout/incident;
- giới hạn payload và retention.

Sampling decision phải được ghi để analyst không coi mẫu là tổng số tuyệt đối.

## 57. Dashboard

Các view:

1. change timeline cạnh SLO;
2. desired/observed/effective convergence;
3. provider availability/staleness;
4. evaluation latency/error/default;
5. rollout/variant exposure và guardrails;
6. drift, expired flag và owner;
7. audit/security anomaly.

Cho phép drill-down theo `change.id`, không biến ID thành metric label.

## 58. Alerting

Alert khi:

- kill switch không hội tụ trong SLO;
- stale/default rate tăng;
- provider unavailable vượt cache tolerance;
- config validation/reconcile lỗi kéo dài;
- nhiều instance ở version cũ;
- change không audit/source;
- drift risk cao;
- flag quá expiry vẫn nhận traffic;
- telemetry gap làm mất effective-state evidence.

Route theo owner và kèm safe action/runbook.

## 59. Incident workflow

Khi nghi config/flag:

1. xác định change gần nhất và blast radius;
2. so desired/observed/effective;
3. kiểm tra version/cohort trên request lỗi;
4. dừng ramp hoặc bật safe state;
5. rollback có kiểm tra compatibility;
6. theo dõi SLO và convergence;
7. lưu timeline/evidence;
8. reconcile emergency change về source of truth.

Không thay nhiều flag cùng lúc nếu chưa biết tác động.

## 60. Flag debt và cleanup

Debt metrics:

- flag quá expiry;
- flag 100% một variant lâu ngày;
- flag không evaluation;
- không owner;
- dependency chain dài;
- code branch còn tồn tại;
- stale SDK/provider.

Cleanup gồm xóa nhánh code cũ, rule, dashboard, alert, test và metadata; archive audit trước
khi delete theo retention policy.

## 61. Kiểm thử

Kiểm thử:

- unit cho default/type;
- contract giữa app và provider;
- property test cho deterministic bucketing;
- compatibility old/new code-config;
- provider outage/stale cache;
- duplicate/out-of-order event;
- percentage boundary;
- targeting privacy;
- kill-switch propagation;
- telemetry redaction/cardinality.

Production exercise có scope nhỏ và rollback rõ.

## 62. Resilience và disaster recovery

Xác định backup/restore cho flag/config definition, history, audit và provider metadata.
Client cần startup strategy khi control plane unavailable: last-known-good, signed snapshot
hoặc safe default tùy risk.

Diễn tập region/provider failover và kiểm tra không split-brain rollout. RPO của audit history
có thể nghiêm ngặt hơn cache.

## 63. Governance

Policy gợi ý:

- naming/type/owner bắt buộc;
- schema và validation;
- PII/secret prohibition;
- approval theo blast radius;
- rollout limit;
- expiry/cleanup;
- audit retention;
- emergency exception;
- SDK/schema version support.

Golden path và template giúp tuân thủ dễ hơn; policy deny phải có reason và remediation link.

## 64. Workshop, checklist và câu hỏi tự kiểm tra

Workshop: chọn một flag production, đổi rollout 0% → 5% → 25%, quan sát propagation,
evaluation, exposure, guardrail rồi rollback và cleanup.

- [ ] Phân biệt desired/observed/effective?
- [ ] Có config/flag immutable version?
- [ ] Context/value nhạy cảm đã loại khỏi telemetry?
- [ ] Provider stale/default được nhìn thấy?
- [ ] Percentage rollout deterministic?
- [ ] Exposure khác assignment?
- [ ] Kill switch có propagation SLO?
- [ ] Metric label có cardinality budget?
- [ ] Owner, expiry và cleanup ticket tồn tại?

Câu hỏi:

1. Vì sao Git merge chưa chứng minh config effective?
2. Code version và config version cần correlate thế nào?
3. Khi nào fallback nên fail closed?
4. Variant tốt hơn raw value trong telemetry ở điểm nào?
5. Assignment khác exposure thế nào?
6. Một flag 100% lâu ngày gây chi phí gì?
7. Làm sao biết kill switch thực sự hoạt động?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Feature flag và telemetry

- [OpenFeature specification](https://openfeature.dev/specification/)
- [OpenFeature evaluation context](https://openfeature.dev/specification/sections/evaluation-context/)
- [OpenFeature hooks](https://openfeature.dev/specification/sections/hooks/)
- [OpenFeature events](https://openfeature.dev/specification/sections/events/)
- [OpenTelemetry feature flag semantic conventions](https://opentelemetry.io/docs/specs/semconv/feature-flags/)
- [OpenTelemetry feature flag attributes](https://opentelemetry.io/docs/specs/semconv/registry/attributes/feature-flag/)

### Configuration và reconciliation

- [OpenGitOps Principles](https://opengitops.dev/)
- [Kubernetes ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes Secret](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Kubernetes Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

Chủ đề tiếp theo:
[Business & Product Observability](business_product_observability.md) – user journey, funnel,
conversion, revenue, business SLO, guardrail và correlation giữa technical health với
customer outcome.

---

*Cập nhật lần cuối: 2026-07-30*
