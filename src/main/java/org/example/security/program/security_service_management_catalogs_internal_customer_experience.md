# Security Service Management, Catalogs & Internal Customer Experience

> Mục tiêu: vận hành security capabilities như các services có customer outcome, service contract, request flow,
> SLO, capacity, support, evidence và lifecycle; giảm queue/friction mà không làm loãng risk decision hoặc control effectiveness.

---

## 1. Security service là một outcome system

Service không phải team, tool hoặc queue. Nó kết hợp people, process, technology, information và suppliers để giúp consumer đạt outcome.

Ví dụ:

- “architecture team” là team;
- “threat modeling tool” là tool;
- “secure design decision cho material change” là service outcome;
- “đặt lịch review” chỉ là một channel.

Tối ưu end-to-end outcome, không tối ưu riêng số ticket đã đóng.

## 2. Capability, service và request khác nhau

| Artifact | Trả lời |
|---|---|
| Capability map | Tổ chức có khả năng làm gì? |
| Service portfolio | Service nào đang proposed/live/retiring? |
| Service catalog | Consumer nhận outcome nào và bằng cách nào? |
| Request catalog | Transaction chuẩn nào consumer có thể yêu cầu? |
| Knowledge base | Cách hiểu, tự xử lý và dùng service? |

Một capability có thể cung cấp nhiều services; một service có thể dùng nhiều capabilities.

## 3. Service-management lifecycle

```text
discover need
  → design service + contract
    → launch / onboard
      → request / fulfill / support
        → monitor outcome + experience
          → review / improve / version
            → deprecate / transition / retire
```

Go-live không kết thúc lifecycle. Run funding, ownership, support và retirement phải có trước khi launch.

## 4. Service portfolio trước catalog

Portfolio giữ cả services chưa hoặc không còn public:

- proposed/discovery;
- pilot/limited availability;
- live/standard;
- constrained/degraded;
- deprecated;
- retiring/retired.

Catalog chỉ hiển thị offers phù hợp từng audience. Không xóa history/service obligations khi một catalog entry biến mất.

## 5. Service taxonomy

Có thể phân loại:

- advisory/decision: architecture, risk, privacy advice;
- protective/platform: identity, secrets, signing, scanning;
- assurance: assessment, evidence, authorization;
- response: incident, forensics, crisis support;
- information: intelligence, standards, guidance;
- enablement: training, patterns, consultations;
- exception/remediation: waiver, finding support;
- recovery: backup validation, clean recovery.

Taxonomy giúp discovery/routing, không thay exact service contract.

## 6. Service owner

Service owner chịu end-to-end:

- outcome và target consumers;
- offer/eligibility/contract;
- cost/funding/capacity;
- SLO, quality và risk;
- roadmap/version/deprecation;
- support/escalation;
- dependencies/suppliers;
- data/evidence;
- customer feedback;
- continual improvement.

Owner không nhất thiết tự thực hiện mọi request nhưng không được đẩy accountability qua handoff.

## 7. Consumer và beneficiary

Consumer trực tiếp không luôn là beneficiary cuối:

| Service | Consumer | Beneficiary |
|---|---|---|
| Secure design review | product team | customer/business |
| Access review | manager/data owner | users/data subjects |
| Detection service | incident analyst | service/customer |
| Supplier assurance | procurement/owner | enterprise/customer |

Thiết kế experience cho consumer nhưng đo outcome/harm đối với beneficiary.

## 8. Personas và jobs-to-be-done

Đừng dùng persona chỉ theo chức danh. Hiểu job/context:

- developer cần release an toàn trước deadline;
- service owner cần quyết residual risk;
- responder cần containment authority lúc outage;
- auditor cần scoped, current evidence;
- employee cần recover account mà không bị impersonation;
- supplier owner cần biết minimum contract requirements.

Một người có thể là nhiều personas theo task và urgency.

## 9. Solve the whole problem

Customer không muốn “hoàn tất form security”; họ muốn ship, onboard supplier, recover service hoặc chứng minh compliance an toàn.

Map journey trước/sau security step:

```text
intent → discover → qualify → prepare → request
       → collaborate / decide → implement
       → verify → operate / support → change / exit
```

Đừng kết thúc service ở approval nếu customer chưa biết implement, verify hoặc handle change.

## 10. Service blueprint

Blueprint nối:

- customer actions;
- visible frontstage interactions;
- backstage work/decisions;
- supporting systems/data;
- dependencies/suppliers;
- controls/evidence;
- failure/recovery paths;
- measures.

Blueprint làm handoff và invisible waiting thấy được. Swimlane theo org chart đơn thuần không cho biết customer đang mắc ở đâu.

## 11. Service catalog entry

Entry tối thiểu:

```text
name + outcome / use cases
target consumers + eligibility
when to use / not use
inputs + preparation
outputs + decision/evidence semantics
delivery channels + lifecycle states
service owner + support / escalation
SLO + dependencies / shared responsibilities
cost/showback if relevant
version + last review / deprecation
```

Viết bằng ngôn ngữ người dùng, không chỉ acronym nội bộ.

## 12. Eligibility và service boundary

Eligibility cần machine/human-readable:

- entity/geography;
- asset/data criticality;
- lifecycle/change type;
- consumer role;
- environment;
- risk tier;
- legal/product constraints;
- service availability window.

Luôn có route cho not eligible: alternate service, self-service guidance hoặc escalation. Không để request silently rejected.

## 13. Input contract

Input contract định nghĩa:

- required/optional fields;
- data types/enums/units;
- evidence freshness;
- owner/authority;
- confidentiality/classification;
- validation rules;
- attachment/link semantics;
- incomplete/unknown handling;
- version compatibility.

Chỉ yêu cầu dữ liệu dùng cho decision. Form dài làm customer đoán và tăng rework.

## 14. Output contract

Output phải nói rõ:

- advisory, assessment, approval hay authorization;
- scope/boundary/version;
- result/rationale/unknowns;
- requirements/conditions/actions;
- owner/authority;
- evidence/reference;
- validity/expiry;
- change/review triggers;
- appeal/escalation.

“Review complete” không cho consumer biết được phép làm gì hoặc còn risk nào.

## 15. Shared-responsibility matrix

Tách provider, consumer và dependency portions:

| Activity | Provider | Consumer | Dependency |
|---|---|---|---|
| Configure | pattern/default | workload input | platform capability |
| Operate | service health | correct use | supplier uptime |
| Monitor | control signals | business anomalies | log pipeline |
| Respond | service containment | workload decision | incident command |
| Evidence | provider portion | application portion | assurance source |

Service “đã cung cấp” không chứng minh consumer portion hoàn tất.

## 16. Channels và một service identity

Service có thể qua:

- portal/form;
- API/CLI/IaC;
- chat/email;
- office hours;
- embedded specialist;
- event-triggered automation;
- emergency hotline.

Mọi channel phải tạo cùng canonical service/request identity, authority và audit trail. Không để chat approval nằm ngoài system of record.

## 17. Request catalog

Một service có nhiều request types:

- new/provision;
- change;
- review/assess;
- advice/consult;
- attest/export evidence;
- exception;
- recover/revoke;
- offboard/retire;
- emergency.

Request type có input, state, authorization, SLO và output riêng. Không ép mọi việc vào một generic ticket.

## 18. Request state machine

```text
draft → submitted → validation
      → queued / assigned
      → in progress / waiting-on-consumer / dependency
      → decision / fulfilled
      → verification → closed
      → reopened / appealed / superseded
```

Mỗi state có owner, allowed transitions, clock semantics và evidence. `Waiting` phải nêu chờ ai/cái gì; không dùng để làm đẹp SLO.

## 19. Validation và progressive disclosure

Kiểm sớm:

- eligibility;
- required data;
- owner/authority;
- duplicate/existing request;
- incompatible version;
- risk tier;
- sensitive-data leakage;
- dependency readiness.

Chỉ hỏi chi tiết khi branch cần. Prefill từ authoritative sources nhưng cho customer thấy/correct provenance, không silently dùng stale context.

## 20. Triage và routing

Triage quyết:

- service/request type đúng;
- standard vs specialist path;
- materiality/risk/urgency;
- skill/authority cần;
- dependency/escalation;
- target SLO;
- batching hoặc synchronous handling;
- duplicate/related cases.

Triage không phải mini-review lặp lại. Standard requests nên route tự động dựa trên transparent rules.

## 21. Priority và fairness

Priority dựa trên:

- safety/legal deadline;
- incident/exposure severity;
- business/customer consequence;
- time criticality/cost of delay;
- dependency unblock;
- reversibility;
- age/starvation;
- service tier.

Không dùng “executive asked” như priority class ẩn. Có override authority, rationale, expiry và impact tới queue khác.

## 22. Queue, WIP và flow

Theo dõi distribution:

- arrival rate;
- queue age;
- touch/wait time;
- work in progress;
- blocked/dependency time;
- reopen/rework;
- abandonment;
- throughput;
- tail lead time.

Utilization 100% làm wait time và fragility tăng. Giới hạn WIP, bảo vệ surge capacity và sửa request/service design thay vì ép analyst làm nhanh vô hạn.

## 23. Demand model

Demand gồm:

- planned: roadmap/releases/renewals;
- event-driven: incident/change/regulation;
- seasonal: audit/budget/peak release;
- failure demand: hỏi lại, reopen, exception do service lỗi;
- latent: teams không dùng vì khó tìm/dùng;
- induced: control/policy mới tạo workload.

Forecast theo work class, population driver và scenario; ticket history chỉ phản ánh demand đã đi qua channel hiện có.

## 24. Capacity model

```text
available capacity
= people × skill-fit × working time
- run/on-call/admin/learning
- planned leave
- reserved surge
```

Thêm automation nhưng tính maintenance/review/failure. Capacity phải match skill/authority, không chỉ headcount. Dùng ranges cho arrival/service time và test peak/dependency outage.

## 25. SLO anatomy

SLO cần:

```text
service level indicator
population / scope
target + window
clock start / stop / pause
exclusions + error handling
data source / freshness
owner + breach action
```

Ví dụ “90% standard access revocations effective trong 15 phút từ approved event trong rolling 30 ngày”; không chỉ “nhanh”.

## 26. Latency distribution và clocks

Không chỉ báo average. Dùng median/P90/P95/P99, age buckets và cohort.

Tách:

- end-to-end elapsed time;
- provider touch time;
- consumer wait;
- dependency wait;
- decision time;
- effective-change propagation.

Pause clock chỉ khi contract cho phép và vẫn báo end-to-end customer time. Closed ticket trước propagation là metric gaming.

## 27. Quality và effectiveness objective

Tốc độ cần đi cùng:

- decision accuracy/consistency;
- control effective coverage;
- defect escape;
- reopen/rework;
- exception/override rate;
- evidence completeness;
- adverse outcome;
- consumer task completion.

Một review nhanh nhưng bỏ material pathway hoặc tạo requirements không triển khai được là service failure.

## 28. Experience-level objective

Experience có thể đo:

- findability;
- first-time-right input;
- time/steps to complete task;
- handoff/repeated-information count;
- comprehension of output;
- predictability/status transparency;
- accessibility;
- perceived fairness/trust;
- effort/satisfaction theo journey stage.

Không dùng một satisfaction average thay outcome/SLO. Kết hợp analytics, research và support feedback.

## 29. Dependency objectives

Service phụ thuộc identity, CMDB/catalog, workflow, data, platform, supplier và decision authority.

Mỗi critical dependency có:

- expected service level/data contract;
- failure/stale/partial behavior;
- owner/escalation;
- fallback/degraded mode;
- monitoring;
- consumer impact;
- recovery/test.

Không hứa end-to-end SLO nếu dependency không có contract hoặc buffer phù hợp.

## 30. Error budget và risk budget

Error budget biến reliability gap thành decision:

```text
allowed unsuccessful outcomes trong window
= total eligible events × (1 - SLO target)
```

Security service cần thêm severity: một privileged false approval không ngang một minor delay. Khi budget burn cao, có thể freeze change, giảm scope, tăng review hoặc fail safe theo pre-agreed rule.

## 31. Support model

Định nghĩa:

- hours/time zones/languages;
- L0 self-help, L1 triage, L2 specialist, L3 engineering/vendor;
- channels và identity verification;
- severity/response targets;
- escalation/on-call;
- accessibility/assisted path;
- known issues/status;
- handoff tới incident/problem/change;
- feedback capture.

Support không phải nơi hấp thụ vĩnh viễn lỗi design của service.

## 32. Request, incident, problem và change

| Record | Mục đích |
|---|---|
| Request | Consumer muốn standard outcome |
| Incident | Service/outcome bị gián đoạn hoặc degraded |
| Problem | Root/systemic cause của incidents/failure demand |
| Change | Sửa service/configuration có controlled risk |
| Decision | Authority chọn option/accept condition |

Một ticket có thể liên kết nhiều records nhưng không nên đổi type để tránh breach metric.

## 33. Incident và degraded mode

Runbook service:

- declare/severity/owner;
- consumer communication/status;
- contain/control failure;
- emergency request path;
- degraded/fail-open/fail-closed behavior;
- preserve evidence;
- dependency/vendor coordination;
- recovery/reconciliation;
- backlog impact;
- post-incident problem/change.

Degraded mode có scope, authorization và expiry; không trở thành permanent bypass.

## 34. Problem management

Tìm systemic causes từ:

- repeated incidents;
- high rework/reopen;
- recurring exception;
- long-tail queue;
- common missing input;
- dependency failure;
- customer abandonment;
- control escape.

Known error có workaround, owner và target fix. Đừng tối ưu từng ticket nếu service design tạo failure demand.

## 35. Knowledge management

Knowledge artifact có:

- audience/job/use case;
- authoritative owner;
- scope/version;
- last reviewed/expiry;
- prerequisites;
- steps + decision/failure branches;
- security classification;
- feedback/search terms;
- related request/service;
- replacement/deprecation.

Đo successful task completion và deflection chất lượng, không chỉ page views. Article lỗi tạo hidden risk.

## 36. Self-service và automation

Tự động hóa khi:

- request chuẩn, repeatable;
- eligibility/authorization rõ;
- input machine-validatable;
- outcome reversible hoặc bounded;
- evidence/audit được tạo;
- failure/rollback paths có;
- exception đi specialist path.

Không tự động hóa ambiguity hoặc risk acceptance. Self-service phải giảm customer effort mà vẫn giữ control semantics.

## 37. Human-centered và accessible service

Thiết kế cho:

- assistive technology;
- language/cognitive load;
- color-independent status;
- time-zone/shift workers;
- low-connectivity/emergency channels;
- neurodiversity;
- legitimate edge cases;
- privacy/minimization;
- appeal/contestability.

Security friction không phân phối đều. Research với affected users, không chỉ champions dễ tiếp cận.

## 38. Onboarding và adoption

Adoption funnel:

```text
eligible → aware → understands → starts
         → completes → uses correctly
         → repeats / stays → achieves outcome
```

Theo cohort và drop-off reason. Mandate có thể tăng starts nhưng không tạo correct use. Onboarding gồm migration, training, support và retirement của old path.

## 39. Service tiers và variants

Variants có thể khác:

- standard/expedited/emergency;
- low/medium/high-risk depth;
- self-service/assisted/bespoke;
- business hours/24×7;
- evidence/assurance level;
- supported technology/geography.

Tier phải có eligibility, cost/capacity và outcome khác rõ. Không bán fast lane làm low-priority work bị starvation hoặc bypass control.

## 40. Cost, showback và chargeback

Service cost model:

- fixed platform/team;
- variable transaction/usage;
- step capacity;
- supplier/license;
- failure demand/rework;
- consumer effort;
- debt/retirement.

Showback làm consumption/cost thấy được. Nếu chargeback, bảo vệ minimum mandatory controls, minh bạch allocation và theo dõi avoidance/gaming.

## 41. Service data model và system of record

Canonical entities:

```text
service / version / owner
consumer / beneficiary / asset
request / state / timestamps
decision / authority / rationale
control / evidence / condition
incident / problem / change
dependency / supplier
measure / SLO / breach
```

Link records thay vì copy inconsistent fields. Access/retention theo sensitivity; không đưa secrets/personal data vào labels/report tùy tiện.

## 42. Measurement và observability của service

Theo bốn layers:

- **health:** channel/workflow/dependency hoạt động?;
- **flow:** demand, wait, WIP, throughput?;
- **quality:** correct/rework/escape/evidence?;
- **outcome/experience:** control effective, customer đạt job, harm giảm?;

Mỗi measure có definition, source, population, latency, quality và action. Dashboard không thay service review.

## 43. Customer research và feedback

Kết hợp:

- interviews/contextual inquiry;
- journey/task observation;
- usability tests;
- search/support/request data;
- abandonment/reopen analysis;
- surveys theo touchpoint;
- complaint/appeal;
- research với non-users.

Feedback không đồng nghĩa feature request. Tìm underlying job, constraint và risk; phản hồi lại customer điều gì đã/không đổi.

## 44. Service review

Cadence review hỏi:

1. Outcome/risk có trong tolerance?
2. Ai chưa được covered hoặc bỏ service?
3. Demand/flow/capacity thay đổi gì?
4. SLO/quality/experience breach vì sao?
5. Incidents/problems/dependencies nào tái diễn?
6. Cost/unit economics và benefit ra sao?
7. Roadmap/change/deprecation decisions nào cần?

Record action/decision/owner/evidence; không biến review thành đọc dashboard.

## 45. Supplier-backed service

Khi provider ngoài thực hiện một phần:

- internal service owner vẫn accountable;
- map supplier SLA tới end-to-end SLO;
- giữ data/evidence/incident rights;
- kiểm subprocessor/concentration;
- quản entitlement/licensing;
- có escalation/continuity/exit;
- đo customer outcome, không chỉ vendor availability;
- test transition khi supplier change/fail.

Vendor portal không phải service-management strategy.

## 46. Control inheritance và assurance

Service cung cấp common control cần publish:

- exact provider portion;
- consumer complementary controls;
- supported scope/versions;
- evidence/freshness;
- known gaps/exceptions;
- SLO/control health;
- change/incident notification;
- fallback;
- consumer-specific validation.

Green service health không tự chứng minh mọi consumer implementation effective.

## 47. Versioning, change và compatibility

Version khi thay:

- input/output schema;
- eligibility/scope;
- decision/control semantics;
- SLO/support;
- dependencies;
- price/allocation;
- security/privacy behavior.

Có release notes, migration path, compatibility window, consumer inventory và rollback. Không silently đổi approval semantics sau portal update.

## 48. Deprecation và retirement

Retirement checklist:

- reason/decision/owner;
- affected consumers/dependencies;
- replacement/equivalence/gaps;
- notice/migration/support timeline;
- data/evidence/records disposition;
- identities/secrets/access revoke;
- contracts/licenses;
- old channel/API shutdown;
- negative tests;
- residual risk/exception handling.

Đóng catalog entry trước khi consumers migrate tạo shadow service và control gap.

## 49. Ví dụ: secure design review service

```text
Outcome: material design có decision-ready threats/requirements
Eligibility: new trust boundary, sensitive data, critical dependency
Requests: consult / standard review / high-risk authority / change review
Inputs: DFD, owner, data, deployment, change, deadline
States: validate → tier → collaborate → decide → verify
Outputs: scoped decision, requirements, evidence, triggers, expiry
SLO: time-to-triage + decision latency + quality/rework
Experience: findability, repeated fields, comprehension, effort
Outcome: requirements implemented/verified; escaped material design issues
```

Nếu queue tăng, kiểm missing-input failure demand, tier rules, reusable patterns và embedded consultation—not chỉ thêm reviewers.

## 50. Lộ trình 90 ngày, checklist và nguồn

### Ngày 1–30: discover và define

- chọn 3–5 high-demand/material services;
- xác định customer job/beneficiary và whole journey;
- map blueprint, failure demand và dependencies;
- tạo catalog/output/shared-responsibility contracts;
- baseline flow, quality, outcome và experience.

### Ngày 31–60: instrument và pilot

- chuẩn hóa request types/state/timestamps;
- đặt SLO/quality/XLO có breach action;
- validation/routing/progressive disclosure;
- support/incident/problem/knowledge paths;
- pilot với cohorts và research non-users.

### Ngày 61–90: operate và improve

- service review bằng decisions/actions;
- demand/capacity/WIP và error-budget rules;
- showback và failure-demand reduction;
- version/deprecation governance;
- mở rộng chỉ khi effective outcome và experience cùng tốt hơn.

### Checklist production

- [ ] Service khác capability/team/tool và có end-to-end owner.
- [ ] Catalog nêu outcome, eligibility, contract, SLO, support và lifecycle.
- [ ] Request types có state machine, authority, clock và output riêng.
- [ ] Shared responsibilities/dependencies/failure modes rõ.
- [ ] SLO đo latency distribution cùng quality/effectiveness.
- [ ] Customer journey gồm assisted/emergency/change/exit paths.
- [ ] Demand, capacity, WIP, surge và failure demand được quản.
- [ ] Incident/problem/knowledge/change records liên kết đúng.
- [ ] Measurement có population, source, quality và action.
- [ ] Version/deprecation/retirement có migration và negative proof.

### Anti-pattern cần tránh

- Đổi tên team thành service.
- Catalog là danh sách tools hoặc org acronyms.
- Một generic request cho mọi work/risk tier.
- Pause clock để mọi ticket đạt SLO.
- Đóng request trước effective propagation/verification.
- Chỉ đo average latency và satisfaction.
- Utilization 100%, không surge capacity.
- Self-service tự approve ambiguity/risk acceptance.
- Support hấp thụ failure demand nhưng không tạo problem record.
- Xóa catalog entry mà chưa migrate/revoke dependencies.

### Nguồn chính thức

- [NIST SP 800-55 Vol.1](https://csrc.nist.gov/pubs/sp/800/55/v1/final) — chọn, document, test,
  validate và evaluate information-security measures với data quality/uncertainty.
- [NIST SP 800-55 Vol.2](https://csrc.nist.gov/pubs/sp/800/55/v2/final) — scope, roles, workflow,
  communication và data concerns của information-security measurement program.
- [NIST SP 800-137](https://csrc.nist.gov/pubs/sp/800/137/final) — continuous-monitoring strategy,
  visibility vào assets/threats/control effectiveness và timely risk response.
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework) — outcome-oriented governance,
  protection, detection, response, recovery và continual improvement context.
- [GOV.UK Service Standard: Solve a whole problem](https://www.gov.uk/service-manual/service-standard/point-2-solve-a-whole-problem) —
  end-to-end user journey xuyên boundaries, incremental improvement và outcome orientation.
- [GOV.UK Service Manual: Measuring service success](https://www.gov.uk/service-manual/measuring-success/measuring-the-success-of-your-service) —
  kết hợp performance data, user research và end-to-end task measurement; dùng như service-design reference, không phải nghĩa vụ chung.

### Học tiếp

1. [Security Product Management & Platform Adoption Economics](security_product_management_platform_adoption_economics.md) — product discovery,
   internal journeys, adoption funnels, roadmap experiments và product-market fit cho controls.
2. [Security Knowledge Management, Standards Enablement & Decision Support](security_knowledge_management_standards_enablement_decision_support.md) — authoritative content,
   findability, lifecycle, reuse, expert routing và knowledge quality.

---

*Cập nhật lần cuối: 2026-08-03.*
