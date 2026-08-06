# Security Observability & Detection Engineering – Từ Audit Event đến Incident Evidence

> Mục tiêu của bài này là thiết kế security telemetry có thể trả lời ai làm gì, trên tài
> nguyên nào, từ đâu, kết quả ra sao và chuỗi hành vi có đáng ngờ không; sau đó biến telemetry
> thành detection có kiểm thử, triage được và hỗ trợ response.
>
> Baseline tham chiếu: NIST Cybersecurity Framework 2.0, MITRE ATT&CK v18 với Detection
> Strategies/Analytics, Sigma Specification hiện hành, Open Cybersecurity Schema Framework
> (OCSF) và OpenTelemetry Semantic Conventions 1.43.
>
> Security observability không đồng nghĩa thu thập mọi thứ. Log chứa credential, session,
> PII, command, query hoặc nội dung tài liệu có thể trở thành mục tiêu giá trị cao. Phải có
> minimization, access control, integrity, retention và audit cho chính telemetry.
>
> Nên đọc trước:
> [Telemetry Governance & FinOps](telemetry_governance_finops.md),
> [Incident Response](incident_response_observability.md),
> [Kubernetes Observability](kubernetes_observability.md) và
> [eBPF Observability](ebpf_observability.md).

---

## 1. Security observability khác monitoring thông thường thế nào?

Operational monitoring hỏi hệ thống có phục vụ đúng không. Security observability còn hỏi
hành vi hợp lệ có bị lạm dụng hay không.

```text
Healthy service + valid credentials ≠ legitimate activity
```

Ví dụ:

- API trả 200 nhưng tài khoản bị chiếm quyền đang tải hàng loạt dữ liệu;
- CPU thấp nhưng audit logging đã bị tắt;
- đăng nhập MFA thành công nhưng đến từ thiết bị và vị trí bất thường;
- pod chạy đúng image name nhưng digest đã bị thay.

Security cần context, sequence và evidence, không chỉ error rate.

## 2. Bốn mục tiêu

| Mục tiêu | Câu hỏi |
|---|---|
| Visibility | Hành vi quan trọng có được ghi nhận không? |
| Detection | Có nhận ra hành vi đáng ngờ đủ sớm không? |
| Investigation | Có tái dựng timeline và blast radius không? |
| Response | Có containment an toàn, có kiểm chứng không? |

Collection không có detection/use case chỉ tạo chi phí. Detection không có evidence và runbook
chỉ tạo hàng đợi alert.

## 3. Vòng đời detection

```text
threat/risk
→ observable behavior
→ telemetry requirement
→ collect/normalize/enrich
→ analytic/rule
→ alert
→ triage
→ incident/response
→ learn/tune
```

Mỗi detection phải truy ngược được:

- threat/use case;
- data source và field bắt buộc;
- rule version;
- test evidence;
- owner;
- response;
- known limitation.

## 4. Threat model trước telemetry

Xác định:

- tài sản và business impact;
- trust boundary;
- actor và capability;
- entry point;
- privilege path;
- data/operation nhạy cảm;
- plausible abuse;
- required response time.

Không bắt đầu bằng “SIEM có connector nào”. Bắt đầu bằng hành vi cần phát hiện và bằng chứng
cần giữ.

## 5. Asset inventory và criticality

Detection thiếu asset context khó ưu tiên. Inventory nên có:

```text
asset_id
asset_type
owner
environment
business_service
criticality
data_classification
internet_exposure
expected_identity/workload
```

Inventory phải có freshness và coverage SLO. CMDB cũ có thể làm alert critical bị hạ mức hoặc
traffic test bị coi là production.

## 6. Telemetry source map

Các nhóm:

- identity/IdP;
- cloud control plane;
- application/API audit;
- endpoint/process/file;
- network/DNS/proxy/firewall;
- Kubernetes/container;
- database/data access;
- SaaS;
- CI/CD/artifact;
- email/collaboration;
- security control health.

Lập matrix use case → required source → required fields → owner → retention.

## 7. Event, finding, alert và incident

| Khái niệm | Ý nghĩa |
|---|---|
| Event | Quan sát nguyên tử |
| Finding | Kết quả một control/scanner/analytic |
| Alert | Finding cần con người hoặc automation đánh giá |
| Incident | Tập evidence xác nhận/có khả năng gây impact |

Không dùng bốn từ thay nhau. Một incident có thể gồm nhiều alert; một alert có thể là false
positive nhưng event gốc vẫn đúng.

## 8. Identity telemetry

Identity cần:

- human/workload identity;
- issuer/tenant;
- authentication method;
- session/token identifier đã bảo vệ;
- device/workload context;
- source;
- role/claims;
- impersonation/delegation chain;
- result và reason.

Đừng chỉ ghi username. Cloud role assumption, service account và workload federation cần
principal gốc lẫn effective principal.

## 9. Authentication

Theo dõi:

- success/failure;
- MFA challenge/result;
- password/token/certificate/passkey method;
- impossible/unusual travel chỉ như một tín hiệu;
- new device/session;
- password reset/recovery;
- token issue/refresh/revoke;
- repeated failures và distributed spray.

Không alert mọi failure. Correlate theo identity, source, target, time và success sau failures.

## 10. Authorization và privilege

Quan sát:

- role/group/policy change;
- permission grant/revoke;
- privileged elevation;
- break-glass;
- denied action;
- resource-policy change;
- delegation/impersonation;
- unused/new privilege.

`403` tăng có thể là bug hoặc reconnaissance. Context deployment và identity giúp phân biệt.

## 11. Cloud control-plane audit

Event nên giữ:

```text
provider/account/project/subscription
region
principal + session
operation
resource
request source
result/error
request parameters đã redaction
response metadata
event and ingest time
```

Đặc biệt theo dõi disable logging, policy change, key creation, snapshot/export, public access
và cross-account trust.

## 12. Application audit

Application hiểu semantic tốt nhất:

- login/session;
- sensitive view/export;
- admin action;
- permission/config;
- payment/refund;
- secret/key lifecycle;
- bulk operation;
- destructive action;
- consent/privacy action.

Audit event phải do server ghi sau authorization; client event không đủ tin cậy.

## 13. Endpoint và process

Quan sát:

- process creation/tree;
- executable hash/signature;
- command/script;
- module/driver;
- user/session;
- network/file child activity;
- privilege;
- sensor health.

Command line có thể chứa secret. Redaction và restricted raw tier cần được thiết kế trước khi
thu thập đại trà.

## 14. File, registry và configuration

Use case:

- sensitive file create/modify/delete;
- startup/persistence location;
- security config change;
- registry/service/scheduled task;
- permission/owner change;
- binary replacement;
- integrity baseline mismatch.

Không theo dõi mọi file với cùng severity. Scope theo critical path, signer, process context
và change window.

## 15. Kubernetes và container

Nguồn:

- Kubernetes audit;
- admission decision;
- image digest/signature;
- RBAC change;
- exec/attach/port-forward;
- secret access;
- privileged workload;
- runtime process/syscall;
- network policy flow;
- control-plane health.

Pod name là ephemeral. Enrich bằng workload, namespace, service account, node, image digest và
cluster identity.

## 16. Network security telemetry

Flow/network event trả lời:

- source/destination identity;
- address/port/protocol;
- direction;
- bytes/packets/duration;
- allow/drop;
- DNS/TLS/HTTP metadata khi hợp pháp;
- sensor/vantage point.

Network không thấy đầy đủ intent, nhất là qua NAT, proxy và encryption. Correlate identity,
endpoint và application audit.

## 17. DNS, proxy và email

DNS:

- query/type/result/latency;
- rare/new domain;
- NXDOMAIN;
- resolver/client identity.

Proxy/email:

- URL/domain/category;
- upload/download;
- sender/recipient;
- attachment/link verdict;
- auth/session.

Không lưu query/path/body nhạy cảm mặc định. Domain reputation là context, không phải verdict
tuyệt đối.

## 18. SaaS và collaboration

Theo dõi:

- login/session;
- app consent/OAuth grant;
- sharing/public link;
- mass download;
- mailbox forwarding/delegation;
- admin/config;
- retention/audit change;
- external guest;
- API token.

Schema và retention của provider thay đổi; có monitor cho connector lag và permission.

## 19. Database và data access

Quan sát:

- principal/role;
- database/object;
- operation class;
- rows/bytes hoặc export size;
- result;
- client/application;
- privileged/break-glass;
- schema/permission change.

Không ghi raw SQL có literal nhạy cảm mặc định. Dùng normalized fingerprint và audit tier
riêng cho truy vấn điều tra.

## 20. CI/CD và supply chain

Event:

- source commit/review;
- workflow change;
- runner identity;
- secret access;
- dependency resolution;
- artifact build/sign/attest;
- registry push/pull;
- deployment approval;
- environment mutation.

Correlate source commit → build run → artifact digest → deployment. Tag/image name không đủ
chứng minh provenance.

## 21. Security event contract

Tối thiểu:

```json
{
  "event_name": "privileged_role_granted",
  "event_time": "2026-07-30T12:00:00Z",
  "observed_time": "2026-07-30T12:00:03Z",
  "actor": {"type": "workload", "id": "release-bot"},
  "action": "role.grant",
  "resource": {"type": "project", "id": "payments-prod"},
  "outcome": "success",
  "source": {"service": "cloud-audit", "region": "ap-southeast-1"}
}
```

Contract cần version, required field, enum, privacy classification và compatibility.

## 22. OCSF

OCSF cung cấp schema vendor-neutral gồm:

- categories;
- event classes;
- reusable objects;
- common attributes;
- profiles/extensions.

Normalization giúp analytic portable hơn nhưng không tự tạo semantic hoàn hảo. Giữ raw event
reference, parser version và mapping confidence để điều tra lỗi mapping.

## 23. Time semantics

Phân biệt:

- event time;
- device time;
- observed/ingest time;
- normalized time;
- processing/detection time.

Theo dõi clock skew và pipeline delay:

```text
ingest_lag = observed_time - event_time
detection_latency = alert_time - event_time
```

Không reorder timeline chỉ dựa trên ingest time khi connector bị backlog.

## 24. Integrity và provenance

Controls:

- authenticated transport;
- append/immutable storage phù hợp;
- hash/signature hoặc chain-of-custody;
- source identity;
- parser/version;
- write-once retention khi yêu cầu;
- access audit;
- time synchronization.

Hash không giúp nếu attacker kiểm soát sensor trước khi event được tạo. Ghi health và
independent control-plane evidence.

## 25. Security telemetry pipeline

```text
source
→ agent/connector
→ buffer
→ parse/normalize
→ enrich
→ route/index/archive
→ detect
→ case/response
```

Mỗi stage cần metrics về rate, lag, drop, parse error, retry, queue, storage và detection
execution. Security pipeline là production system có SLO.

## 26. Collection gap

Phát hiện:

- heartbeat mất;
- expected source im lặng;
- event rate lệch baseline;
- sequence/checkpoint gap;
- permission/token expired;
- parser rejection;
- region/account mới chưa onboard;
- log setting bị tắt.

“Không có alert” có thể vì không có tấn công hoặc vì sensor mù. Coverage health phải hiển thị
ngay trên SOC dashboard.

## 27. Normalization

Normalization gồm:

- type conversion;
- field mapping;
- enum/outcome;
- identity/resource canonicalization;
- timestamp;
- IP/domain normalization;
- schema version.

Không overwrite raw field khi mapping không chắc. Lưu `raw_ref`, parser version và lỗi;
quarantine thay vì drop âm thầm.

## 28. Enrichment

Context:

- asset criticality/owner;
- identity role/risk;
- geo/ASN;
- threat intelligence;
- vulnerability/exposure;
- change/deployment;
- business calendar;
- allowlist.

Mọi enrichment có timestamp/version. Reputation hiện tại không được gắn ngược vào event cũ
như thể nó đã biết tại thời điểm xảy ra.

## 29. Correlation identity và resource

Canonical keys:

```text
principal_id
session_id
device/workload_id
cloud_resource_id
artifact_digest
source/destination identity
trace/request ID
```

Không join chỉ bằng display name hoặc IP. IP thay đổi, NAT dùng chung và account rename làm
correlation sai.

## 30. Detection taxonomy

Các loại:

- atomic/signature;
- threshold;
- sequence/correlation;
- behavioral baseline;
- anomaly;
- state/config drift;
- threat-intel match;
- policy violation;
- cross-domain analytic.

Mỗi loại có false-positive, explainability và data dependency khác nhau.

## 31. Atomic detection

Atomic rule tốt cho hành vi hiếm và rõ:

- audit logging bị tắt;
- root key mới;
- public access critical bucket;
- unsigned artifact deploy;
- break-glass ngoài quy trình.

Rule đơn giản dễ test, nhưng attacker có thể dùng hành vi hợp lệ theo chuỗi. Kết hợp atomic
signal thành correlation khi cần.

## 32. Sigma

Sigma mô tả detection portable bằng YAML với:

- metadata/title/id/status;
- log source;
- detection selections;
- condition;
- false positives;
- level;
- tags.

Backend converter phải map đúng field/schema và semantics query. “Compile thành công” không
chứng minh rule chạy đúng trên SIEM đích.

## 33. Correlation và sequence

Ví dụ:

```text
many auth failures
→ one success
→ privilege discovery
→ sensitive export
```

Thiết kế:

- grouping key;
- order;
- time window;
- missing/optional event;
- late arrival;
- dedup;
- state retention.

Time window quá ngắn bỏ sót slow attack; quá dài tăng noise và state.

## 34. Behavioral và anomaly detection

Baseline có thể theo:

- identity;
- peer group;
- resource;
- time;
- volume;
- sequence.

Anomaly không đồng nghĩa malicious. Hiển thị reason, baseline, effect size và context. Không
tự động block hoạt động quan trọng chỉ vì điểm anomaly chưa được kiểm chứng.

## 35. MITRE ATT&CK Detection Strategies

ATT&CK v18 đưa Detection Strategies và platform-specific Analytics thành cấu trúc mới để mô tả
cách phát hiện technique. Danh sách Data Sources cũ đã deprecated từ tháng 10-2025 và chỉ còn
để tham khảo.

Dùng:

```text
Technique
→ Detection Strategy
→ Analytic
→ Log Source / mutable elements
→ local implementation + test
```

Không đo coverage bằng số technique có tag ATT&CK.

## 36. Detection coverage

Coverage có nhiều lớp:

1. threat/use case được ưu tiên;
2. telemetry source tồn tại;
3. required fields đủ và đúng;
4. analytic triển khai;
5. rule chạy khỏe;
6. alert đến đúng queue;
7. analyst xử lý được;
8. response đã diễn tập.

Heatmap chỉ layer 4 sẽ thổi phồng maturity.

## 37. Rule lifecycle

```text
idea → design → implement → review → test
→ shadow → enable → tune → measure → retire
```

Metadata:

- stable ID/version;
- owner;
- severity;
- data dependency;
- expected volume;
- runbook;
- ATT&CK mapping;
- exceptions;
- last test/review.

## 38. Detection-as-code

Repository nên có:

- rule source;
- schema;
- test fixtures;
- lint;
- backend compilation;
- query plan/cost check;
- reviewer/approval;
- release notes;
- rollback;
- deployment status.

Không đưa raw production event chứa PII vào Git làm fixture. Dùng synthetic/redacted data.

## 39. Testing detection

Các mức:

- unit: event match/non-match;
- schema compatibility;
- conversion;
- integration với SIEM;
- replay historical/synthetic;
- adversary emulation được phê duyệt;
- end-to-end alert/case/notification;
- negative/performance test.

Test cả expected no-alert. Một rule bắt mọi thứ có recall cao nhưng vô dụng.

## 40. Tuning

Tuning dựa trên:

- false-positive reason;
- entity/context;
- threshold/window;
- duplicate source;
- planned change;
- data-quality issue;
- benign tool.

Đừng thêm allowlist rộng để dập alert. Exception cần scope nhỏ, owner, reason, expiry và audit.

## 41. Suppression và allowlist

Safe suppression:

```text
identity + operation + resource + environment + time window
```

Không chỉ allowlist IP hoặc admin role. Credential admin vẫn bị chiếm quyền; NAT/proxy làm IP
không đại diện một actor.

Đo số event/alert bị suppress và kiểm tra sample định kỳ.

## 42. Risk score và severity

Severity nên kết hợp:

- behavior confidence;
- asset criticality;
- identity privilege;
- exposure;
- data sensitivity;
- technique stage;
- blast radius;
- control/fallback.

Tách **analytic confidence** khỏi **business impact**. Một detection chắc chắn trên lab asset
không nhất thiết P1; anomaly yếu trên crown-jewel có thể cần review nhanh.

## 43. Dedup và grouping

Group alert theo incident hypothesis:

- same actor/session;
- same target;
- same campaign/indicator;
- same behavior chain;
- bounded time.

Giữ count, first/last seen và sample evidence. Dedup không được xóa escalation khi severity
hoặc scope tăng.

## 44. SIEM storage architecture

Tách tier:

- hot: detection/triage;
- warm: hunting/investigation;
- archive: compliance/forensic;
- restricted: raw sensitive evidence.

Định tuyến theo use case và risk. Không index mọi field. Retention dài không bù cho source bị
drop hoặc schema sai.

## 45. SOAR và automation

Automation phù hợp:

- enrich;
- collect volatile evidence;
- disable/revoke với confidence cao và blast radius thấp;
- quarantine;
- open/update case;
- notify owner;
- request approval.

Mỗi playbook cần idempotency, dry-run, approval gate, rollback, audit và rate limit. Không để
alert giả khóa hàng loạt account production.

## 46. Triage

Analyst cần:

```text
what happened
why rule fired
actor/session/device
target and criticality
before/after timeline
related alerts
recent changes
evidence links
recommended next steps
```

Alert chỉ có query result làm analyst phải tự lắp context, tăng MTTR và inconsistency.

## 47. Evidence timeline

Timeline giữ:

- event time và ingest time;
- source/provenance;
- immutable event/reference;
- timezone;
- clock skew;
- analyst/action;
- hypothesis và confidence.

Phân biệt fact với inference. “IP ở quốc gia X” là enrichment; “attacker ở X” là suy luận
không chắc chắn.

## 48. Incident response

Phases thực dụng:

```text
validate → scope → contain → eradicate
→ recover → monitor → learn
```

Observability phải hỗ trợ cả quyết định containment và xác nhận recovery. Sau revoke token,
theo dõi session/activity còn tiếp diễn; sau rebuild, kiểm tra persistence signal.

## 49. Threat hunting

Hunt bắt đầu từ hypothesis:

```text
Nếu actor lạm dụng cloud discovery,
ta sẽ thấy chuỗi list/describe bất thường
từ identity mới trên nhiều service trong một cửa sổ.
```

Ghi query, data coverage, timeframe, result và gap. Hunt không tìm thấy gì không chứng minh
không có compromise.

## 50. Threat intelligence

Intel gồm indicator, TTP, actor/campaign context và confidence.

Controls:

- source/license;
- first/last seen;
- TTL;
- confidence;
- false-positive history;
- matching normalization;
- retrospective search.

IOC match đơn lẻ dễ noisy và stale. Ưu tiên behavior + context, dùng IOC để enrich/seed hunt.

## 51. Deception và canary

Canary token/account/resource tạo tín hiệu high-confidence khi bị dùng.

Thiết kế:

- không ảnh hưởng production;
- không chứa secret thật;
- placement có chủ đích;
- alert route nhanh;
- attribution/context;
- rotate/test;
- legal/privacy review.

Không biến deception thành bẫy gây hại hoặc thu dữ liệu ngoài phạm vi được phép.

## 52. Detection quality metrics

Metric hữu ích:

- alerts theo rule/severity;
- true/false/benign-positive;
- precision trên alert đã adjudicate;
- alert-to-incident conversion;
- analyst time;
- coverage health;
- rule execution latency/failure;
- last successful test;
- stale exceptions.

Recall production thường không biết đầy đủ vì không có ground truth. Đừng báo con số giả chính xác.

## 53. MTTD, MTTR và dwell time

Phân biệt:

```text
time to ingest
time to detect
time to triage
time to contain
time to recover
```

Average che tail; xem percentile và critical tier. Timestamp “incident start” thường được cập
nhật sau điều tra, nên định nghĩa metric phải rõ.

## 54. Security telemetry SLO

Ví dụ:

- 99.9% critical audit event ingest dưới 2 phút;
- không có source critical im lặng quá 5 phút mà không alert;
- 99% detection high severity chạy đúng schedule;
- 100% production account có logging policy;
- 99% P1 alert tới case queue dưới 1 phút.

Đo cả event loss và blind spot, không chỉ SIEM uptime.

## 55. Dashboard

Các tầng:

1. active incidents và impact;
2. high-risk detections;
3. identity/asset/data context;
4. source coverage/gaps;
5. detection health/quality;
6. queue/analyst workload;
7. pipeline lag/drop;
8. cost/retention.

Không dùng ATT&CK heatmap màu xanh làm dashboard duy nhất.

## 56. Alert telemetry health

Page khi:

- audit disabled;
- critical connector silent;
- ingest lag vượt response budget;
- parser rejection tăng;
- rule engine không chạy;
- alert/case delivery fail;
- clock skew lớn;
- integrity validation fail;
- storage quota sắp chặn ingest.

Đây là “alarm của hệ thống báo động” và cần route độc lập nếu có thể.

## 57. Privacy

Security purpose không tự động cho phép thu mọi dữ liệu.

Áp dụng:

- purpose limitation;
- field allowlist;
- masking/tokenization;
- minimum cohort;
- role-based views;
- regional boundary;
- retention;
- subject/legal process;
- audit access.

Hunt query và case note cũng có thể chứa PII.

## 58. Secret và token

Không ghi:

- password;
- access/refresh token;
- session cookie;
- API key;
- private key;
- authorization header;
- secret value;
- recovery code.

Nếu cần correlation, lưu fingerprint/HMAC có key rotation và scope. Hash token entropy cao
vẫn tạo stable identifier nhạy cảm; bảo vệ như credential metadata.

## 59. Access control và separation of duties

Phân quyền:

- collector writer;
- parser/developer;
- detection author;
- analyst;
- responder;
- auditor;
- platform admin.

Production rule change, raw log access và destructive SOAR action nên có approval/audit.
Không cho compromised application xóa hoặc sửa telemetry của chính nó.

## 60. Retention và legal hold

Retention theo:

- detection window;
- investigation need;
- regulatory/legal;
- sensitivity;
- cost;
- source replay capability.

Legal hold phải có authorization, scope và release process. Không giữ toàn bộ raw telemetry
vô thời hạn “phòng khi cần”.

## 61. Cardinality và cost

Nguồn cost:

- event volume/size;
- indexing;
- high-cardinality fields;
- expensive correlation;
- hot retention;
- duplicate sources;
- enrichment;
- egress.

Tối ưu bằng filter/routing, columnar archive, parse once, summary metrics và use-case tiers.
Không drop critical audit chỉ vì bill tăng mà không risk review.

## 62. Resilience trước attacker

Giả định attacker sẽ:

- tắt/né sensor;
- flood log;
- tạo alert fatigue;
- sửa clock;
- xóa evidence;
- chiếm SIEM/SOAR;
- lợi dụng automation.

Controls: rate/buffer, immutable copy, independent health, least privilege, MFA, isolated
response path, capacity reserve và tested degraded mode.

## 63. Governance

Governance artifact:

- telemetry catalog;
- source/data owner;
- use case/risk;
- schema/classification;
- detection registry;
- exception register;
- retention;
- access review;
- validation evidence;
- incident learning.

NIST CSF 2.0 gồm Govern, Identify, Protect, Detect, Respond và Recover. Security observability
phải nối các function, không chỉ tập trung Detect.

## 64. Workshop, checklist và câu hỏi

Workshop:

1. chọn hành vi “privileged role grant rồi export”;
2. vẽ required events;
3. chuẩn hóa actor/resource/outcome;
4. viết correlation rule;
5. test match/non-match;
6. làm connector chậm;
7. triage, contain và xác nhận recovery.

Checklist:

- [ ] Threat/use case và owner rõ?
- [ ] Required fields và coverage SLO?
- [ ] Raw event/provenance được giữ an toàn?
- [ ] Rule có test, version, runbook?
- [ ] Exception có expiry?
- [ ] Telemetry health có alert độc lập?
- [ ] SOAR idempotent, có approval/rollback?
- [ ] Privacy, retention và access được review?

Câu hỏi:

1. Event, alert và incident khác nhau thế nào?
2. Vì sao ATT&CK tag không chứng minh coverage?
3. Detection precision đo ra sao khi adjudication thiếu?
4. Làm sao biết “không có alert” là bình thường?
5. Normalization lỗi ảnh hưởng detection thế nào?
6. Khi nào anomaly được phép tự động block?
7. Làm sao bảo vệ telemetry khỏi attacker?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Framework và detection

- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)
- [MITRE ATT&CK Detection Strategies](https://attack.mitre.org/detectionstrategies/)
- [MITRE ATT&CK Data Sources deprecation notice](https://attack.mitre.org/datasources/)
- [Sigma Specification](https://sigmahq.io/sigma-specification/)

### Schema và telemetry

- [Open Cybersecurity Schema Framework](https://github.com/ocsf/ocsf-schema)
- [OpenTelemetry event semantic conventions](https://opentelemetry.io/docs/specs/semconv/general/events/)
- [OpenTelemetry Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/)

Chủ đề tiếp theo:
[Network Observability & Traffic Analysis](network_observability_traffic_analysis.md) – DNS,
TCP, TLS, QUIC, routing, load balancing, flows, probes và packet evidence.

---

*Cập nhật lần cuối: 2026-07-30*
