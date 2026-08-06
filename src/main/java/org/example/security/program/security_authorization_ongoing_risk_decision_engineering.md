# Security Authorization & Ongoing Risk Decision Engineering

> Mục tiêu: biến authorization thành quyết định risk có scope, authority, evidence, điều kiện và expiry rõ ràng;
> duy trì tính hợp lệ bằng continuous monitoring và significant-change review thay vì coi approval là giấy phép vĩnh viễn.

---

## 1. Security authorization là gì?

Authorization là quyết định có trách nhiệm rằng một system/service/control có thể vận hành hoặc được sử dụng trong boundary, purpose,
conditions và thời gian xác định dựa trên risk đã biết:

```text
mission / business use + authorization boundary
    → requirements + risk scenarios + controls
        → implementation + assessment + findings
            → residual risk + uncertainty + dependencies
                → authorize / condition / deny
                    → monitor / change / reassess / revoke / renew
```

Decision không khẳng định “an toàn tuyệt đối”. Nó nói ai chấp nhận residual consequences nào, vì mục tiêu gì và với guardrails nào.

## 2. Authorization không phải compliance certificate

Phân biệt:

- **Architecture/design approval:** thiết kế phù hợp direction tại một thời điểm.
- **Control assessment:** control objectives được kiểm theo scope/period.
- **Compliance/certification:** criteria bên ngoài/nội bộ được đánh giá.
- **Risk acceptance:** residual scenario được giữ trong authority/time/scope.
- **Authorization:** cho phép operation/use có điều kiện dựa trên toàn decision package.

Audit pass có thể là evidence nhưng không tự authorize business use. Ngược lại, authorization không xóa finding, legal obligation hoặc
customer commitment.

## 3. Authorization lifecycle

```text
prepare → define boundary/use → categorize/assess risk
  → select/implement controls → assess
    → assemble/challenge package → decide
      → operate/monitor → significant change
        → update/reassess/reauthorize or retire
```

Thiết kế authorization từ đầu lifecycle; nếu đợi trước go-live mới gom package, finding quan trọng không còn thời gian xử lý.
State model phải phân `draft`, `under review`, `authorized`, `authorized-with-conditions`, `denied`, `suspended`, `expired`, `retired`.

## 4. Vocabulary và decision objects

| Khái niệm | Nghĩa |
|---|---|
| Authorization boundary | Tập component, data, process, people và dependency thuộc decision |
| Authorization package | Information set dùng để ra decision |
| Authorizing role/official | Người có authority/accountability quyết định |
| Risk executive/function | Điều phối risk view xuyên organization/enterprise |
| Residual risk | Scenario còn lại sau controls/treatment thực tế |
| Condition | Ràng buộc bắt buộc để authorization có hiệu lực |
| POA&M/treatment plan | Work/milestone xử lý deficiency/risk |
| Significant change | Change có khả năng làm decision/risk basis không còn đúng |
| Ongoing authorization | Duy trì decision bằng information/evidence đủ mới và response liên tục |

Không dùng “ATO” như tên chung cho mọi security sign-off nếu authority và legal context khác.

## 5. Các tầng risk decision

Authorization có thể tồn tại ở:

- **enterprise/organization:** common policy/control/service và concentration;
- **mission/business process:** use case, critical service và impact;
- **system/product:** boundary/implementation cụ thể;
- **component/service use:** cho phép dùng shared/cloud/SaaS capability;
- **change/release:** approval trong giới hạn authorization hiện có.

Tầng dưới không được chấp nhận risk vượt appetite/authority tầng trên. Tầng trên không nên ký thay facts/operation mà system owner
phải chứng minh.

## 6. Roles và accountability

| Vai trò | Accountability chính |
|---|---|
| Authorizing authority | quyết operation/use và chịu residual risk decision |
| Business/mission owner | outcome, criticality, impact và benefit |
| System/product owner | boundary, implementation, operation và package accuracy |
| Control/common provider | control portions, evidence, changes/findings |
| Risk/security/privacy officer | analysis, challenge, recommendation |
| Assessor | independent conclusion theo plan/criteria |
| Legal/compliance/safety | non-waivable constraints và specialist impact |
| Operations/SRE/IR | run state, monitoring, response và recovery evidence |

Người viết package không tự trở thành authorizer; CISO cũng không mặc nhiên sở hữu mọi business impact.

## 7. Delegated authority

Delegation record cần:

- decision types và systems/use cases được phép;
- risk/impact/financial/data/safety threshold;
- maximum duration và conditions;
- prohibited/non-delegable decisions;
- required specialist concurrence;
- escalation path;
- quorum/substitute nếu forum;
- start, review và expiry;
- reporting/oversight.

Không suy authority từ job title hoặc người “thường ký”. Khi residual risk vượt tolerance, delegation hết hiệu lực dù deadline go-live gần.

## 8. Authorization boundary

Boundary gồm nhiều hơn compute resources:

- business capability/use and users;
- applications/services/APIs;
- data stores/flows/classifications;
- identities/admin/support paths;
- network/control planes;
- build/deploy/update path;
- logging/backup/recovery;
- common controls/platforms;
- suppliers/SaaS/subprocessors;
- facilities/people/manual processes;
- environments/regions/entities.

Boundary phải cho thấy trust/dependency edges. Vẽ hộp quá hẹp đẩy risk ra ngoài package nhưng không ra khỏi business reality.

## 9. Boundary criteria và exclusions

Mỗi included/excluded item có rule/rationale. Exclusion chỉ hợp lệ khi:

- ownership và interface rõ;
- dependency được model;
- separate authorization/assurance tồn tại nếu cần;
- data/identity/control path không bị bỏ;
- failure/incident responsibility có contract;
- residual impact vẫn được xem.

“Cloud managed”, “third party” hoặc “corporate service” không phải lý do loại khỏi risk view. Có thể ngoài implementation boundary nhưng
vẫn trong dependency/authorization context.

## 10. Common controls và inherited assurance

Package ghi:

- exact common-control provider/version/portions;
- eligibility/onboarding/effective-use evidence;
- consumer complementary responsibilities;
- provider assessment scope/period/findings;
- dependencies/concentration;
- outage/change/incident notification;
- provider và consumer exceptions;
- fallback/exit.

Không copy provider kết luận thành system pass. Authorizer cần end-to-end conclusion và limitation của reliance.

## 11. System/use description

Một executive-readable description trả lời:

- mission/business objective và value;
- users/customers/affected individuals;
- core workflows/data;
- deployment/regions/entities;
- critical dependencies;
- operating states: normal, degraded, recovery, transition;
- lifecycle/roadmap và planned changes;
- why operation/use is needed now.

Inventory chi tiết có thể ở annex; main narrative phải đủ để authorizer hiểu decision consequences.

## 12. Categorization và impact

Categorize theo potential harm, không chỉ data label:

- mission/service interruption;
- confidentiality/integrity/availability;
- individual/privacy/civil-liberties harm;
- physical/safety/environment;
- legal/contract/license;
- financial/fraud;
- reputation/trust;
- supplier/ecosystem/national impact.

Ghi assumptions, ranges, critical periods và interdependency. Một low-sensitivity control plane vẫn có high integrity/availability impact.

## 13. Risk scenario set

Scenario tốt:

```text
threat / event / condition
  → exploits exposure / control failure
    → affects asset / process / people
      → business / mission consequence
```

Bao gồm malicious, error, structural failure, supplier, privacy processing, resilience và transition risks. Nêu likelihood/impact range,
confidence, evidence và time horizon.

Danh sách vulnerabilities thiếu consequence không đủ cho authorization. Ngược lại, generic “data breach risk” không chỉ ra control path.

## 14. Appetite, tolerance và threshold

Decision criteria lấy từ:

- enterprise risk appetite/direction;
- mission/business tolerance;
- legal/non-waivable constraints;
- critical-service limits;
- risk aggregation/concentration;
- customer/contract commitments;
- delegated authority.

Không biến appetite statement mơ hồ thành score cutoff máy móc. Tolerance cần observable threshold như maximum outage, exposed population,
duration, detection latency hoặc unresolved critical pathways.

## 15. Baseline selection và tailoring

Package giải thích:

- baseline/profile được chọn và why;
- additional controls vì scenario/obligation;
- parameter values;
- not-applicable controls với evidence;
- alternative/compensating controls;
- common/system/hybrid allocation;
- deviations/exceptions;
- residual gaps.

Tailoring không được dùng để hạ risk trên giấy. Authorizer cần thấy selected outcome và actual implementation—not chỉ control count.

## 16. Implementation statements

Với material controls, statement gồm:

- responsible component/person/process;
- actual configuration/workflow/version;
- population/coverage;
- operating frequency/trigger;
- dependencies/interface;
- failure/degraded behavior;
- evidence/monitoring;
- known limitation;
- owner/support.

“Implemented via product X” không đủ. Package có thể reference canonical control library nhưng phải bind tới effective system state.

## 17. Assessment plan

Plan có:

- authorization decision/purpose;
- control objectives/criteria/version;
- boundary and assessment period;
- examine/interview/test methods;
- depth, coverage, sample;
- inherited controls/reliance;
- assessor competence/independence;
- evidence access/protection;
- limitation/change handling;
- result/findings workflow.

Assessment depth theo materiality, volatility, prior failure và concentration; không chạy cùng checklist cho mọi system.

## 18. Assessment results

Result phải phân:

- design adequacy;
- implementation correctness;
- operating effectiveness;
- objective/outcome evidence;
- pass/fail/not-tested/unknown/stale/exception;
- coverage/sample/period;
- assessor confidence/limitation;
- changed state sau test;
- findings và recommendations.

Một result aggregate xanh không được che critical objective fail. Authorizer cần trace summary về procedure/evidence.

## 19. Evidence quality và freshness

Evidence record cần provenance, scope, period, source, method/version, integrity, freshness, coverage và limitation. Decision package
không được giữ kết luận pass nếu evidence hết hạn hoặc collector lỗi.

Cadence phụ thuộc control volatility:

- policy/config mỗi deployment/change;
- identity/session gần real-time;
- access review periodic/event-driven;
- restore/incident exercise theo risk;
- supplier evidence theo period và material change.

Unknown coverage là uncertainty/exposure, không phải absence of issue.

## 20. Findings và POA&M

Mỗi material finding có:

- exact objective/criteria và affected scope;
- evidence/period/confidence;
- scenario/business impact;
- root cause/systemic instances;
- containment/compensating control;
- accountable owner/funding;
- milestones/dependencies/date;
- retest/closure criteria;
- linked exception/risk decision.

Package giữ both open and recently closed findings để thấy recurrence. Due date sau authorization expiry là red flag cần explicit decision.

## 21. Residual risk không phải phép trừ score

Residual risk được mô tả bằng scenario còn lại sau **controls thực tế**:

```text
remaining pathway + affected population
  + likelihood/impact range + time horizon
  + control strength/coverage/failure modes
  + uncertainty + concentration
  + detection/response/recovery capability
```

Không tính `inherent score - control score`. Controls tương quan, coverage không đầy đủ và failure mode có thể làm phép trừ vô nghĩa.
Nêu phần nào chưa biết và evidence nào sẽ giảm uncertainty.

## 22. Aggregate và concentration risk

System risk “acceptable” riêng lẻ có thể vượt enterprise tolerance khi nhiều systems cùng:

- dùng một identity/control plane/provider;
- giữ cùng data population;
- có exceptions giống nhau;
- phụ thuộc cùng scarce responder/recovery site;
- mở cùng attack pathway;
- go-live trong cùng transition window.

Authorization package phải query enterprise risk/common-control graph. Authorizer system không tự quyết concentration vượt authority;
escalate tới risk executive/enterprise forum.

## 23. Privacy, safety và legal constraints

Security controls có thể gây harm: over-monitoring, over-retention, discrimination, unsafe fail-closed hoặc denial of essential service.
Package cần specialist review và residual harm cả từ system lẫn control.

Binding legal/license/safety duty không thể bị authorization nội bộ xóa. Nếu operation không hợp pháp/an toàn, options là change scope,
redesign, obtain external authority hoặc deny—not “accept risk”.

Ghi conflicts, rights, affected persons và redress/appeal khi relevant.

## 24. Supplier và external-service risk

Include:

- service/data/control boundary;
- shared responsibility/complementary controls;
- due diligence/assessment period/exceptions;
- contract/SLA/security/notification/exit terms;
- subprocessor/fourth-party;
- tenant/effective configuration;
- concentration/region/sovereignty;
- outage/incident/recovery/termination plan.

Certificate/report của vendor là input. Authorizer quyết actual use/integration and residual dependency risk.

## 25. Authorization package tối thiểu

```text
executive decision memo
system/use + boundary + categorization
requirements/control baseline/tailoring
risk assessment/scenario register
implementation and inherited-control statements
assessment plan/results/evidence references
findings + POA&M + exceptions
privacy/legal/safety/supplier analyses
continuous monitoring strategy
residual/aggregate risk + options/recommendation
proposed conditions, expiry and significant-change triggers
```

Package là linked/versioned information set; không bắt buộc một PDF khổng lồ.

## 26. Executive decision memo

Memo ngắn phải cho biết:

- exact decision requested và deadline;
- business value/cost of delay;
- boundary/use/population;
- top residual scenarios và confidence;
- material findings/exceptions/dependencies;
- legal/safety/non-waivable constraints;
- options/trade-offs;
- recommendation và dissent;
- conditions/monitoring/expiry;
- actions authorizer cần thực hiện.

Không giấu detail quan trọng trong appendix hoặc dùng màu xanh thay narrative.

## 27. Options và recommendation

Tối thiểu xem:

- authorize as proposed;
- authorize narrowed scope/cohort/use;
- authorize with conditions/timebox;
- delay để xử lý critical prerequisite;
- alternate architecture/provider/process;
- operate in pilot/read-only/degraded mode;
- deny/avoid/retire.

So sánh mission benefit, risk/harm, uncertainty, reversibility, time/cost và opportunity. “Approve or block” nhị phân thường bỏ mất
option giảm scope hoặc học thêm có kiểm soát.

## 28. Conditions of authorization

Condition phải kiểm chứng được:

```text
condition ID + exact requirement/action
owner + funded milestone + due date
interim control + health evidence
scope/use limitation
monitoring threshold
escalation/consequence if breached
verification/closure authority
```

Không dùng “team sẽ cải thiện logging” hoặc “continue monitoring”. Conditions quá nhiều/không funded biến authorization thành fiction.

## 29. Decision types

| Decision | Nghĩa |
|---|---|
| Authorize | residual risk trong authority; conditions chuẩn vẫn áp dụng |
| Authorize with conditions | operation/use được phép khi named conditions giữ đúng |
| Limited/pilot authorization | scope/time/population/function bị giới hạn |
| Deny | không được operation/use trong proposed form |
| Suspend | tạm dừng authority do breach/change/incident |
| Revoke | rút decision trước expiry |
| Expire | hết hiệu lực nếu không renew/reauthorize |

Tránh `provisional` mơ hồ: ghi exact condition/scope/time và hệ quả khi vi phạm.

## 30. Decision record

```yaml
decision_id: AUTH-PAY-2026-014
boundary_version: payments-v4.2
decision: authorize_with_conditions
authorizer: VP-Payments
decided_at: 2026-08-03T10:00:00+07:00
effective_at: 2026-08-10
expires_at: 2027-02-10
accepted_scenarios: [RSK-184, RSK-207]
conditions: [COND-31, COND-32]
monitoring_profile: tier-0
significant_change_profile: AUTH-SC-01
```

Lưu package versions, rationale, alternative rejected, dissent, concurrence và signature/authority provenance.

## 31. Challenge, concurrence và dissent

Reviewer không phải chỉ “approve/comment”. Ghi:

- security/privacy/legal/safety/compliance concurrence;
- assessor conclusion;
- material disagreement và basis;
- missing evidence/uncertainty;
- response của system owner;
- authorizer resolution;
- minority/dissent retained.

Consensus không bắt buộc nếu authority rõ, nhưng dissent material không được xóa khỏi package. Escalate khi conflict vượt domain authority.

## 32. Time-bound authorization và expiry

Duration dựa trên:

- risk/criticality;
- evidence confidence/freshness;
- open conditions/findings;
- technology/threat/change velocity;
- supplier/report period;
- transition/legacy state;
- legal/contract date.

Expiry phải enforce: trước hạn reassess/renew, hết hạn chuyển status và trigger action. Auto-renew vì calendar không phải ongoing authorization.
Short validity nhưng renewal rubber-stamp cũng không tạo assurance.

## 33. Significant change là gì?

Change significant khi có khả năng làm risk/authorization basis không còn đúng, ví dụ:

- mission/use/customer/population thay đổi;
- boundary/data flow/classification/region/entity;
- major architecture/trust/control plane;
- identity/cryptography/admin model;
- common control/provider/supplier;
- control removal/degraded mode/exception;
- serious incident/threat/exploit;
- legal/contract/license requirement;
- ownership/operating/support model;
- recovery/availability target;
- evidence/monitoring blind spot.

Significance dựa trên effect, không chỉ change size hoặc ticket label.

## 34. Trigger taxonomy

| Trigger | Ví dụ |
|---|---|
| Planned technical | migration, new API, region, identity model |
| Business | acquisition, new market/customer/use |
| Control | provider change, control retirement, parameter drift |
| Risk/threat | exploited vulnerability, threat campaign |
| Incident | compromise, material outage, privacy event |
| External | law, contract, regulator, supplier change |
| Assurance | critical finding, stale/unknown coverage |
| Organizational | owner/operator/funding change |

Trigger sources phải feed một triage path với owner/SLA; không chờ authorizer tự đọc mọi alert.

## 35. Significant-change triage

Triage record:

- change facts/source/time;
- affected boundary/use/control/dependency;
- scenario/impact delta;
- current authorization/conditions;
- urgency/reversibility;
- evidence needed;
- interim containment;
- decision: within authorization, targeted reassessment, full reauthorization, suspend/revoke;
- authority/rationale.

False negative nguy hiểm, nhưng gọi mọi release là significant làm process tắc. Dùng pre-defined examples/thresholds và expert escalation.

## 36. Reassessment theo tầng

Không phải change nào cũng full assessment:

- **Level 0:** automated validation, no material delta;
- **Level 1:** targeted control/interface tests;
- **Level 2:** focused risk/privacy/supplier assessment;
- **Level 3:** full boundary/control reassessment và reauthorization;
- **Emergency:** immediate containment/temporary decision rồi retrospective review.

Depth/coverage theo affected pathways, uncertainty và concentration. Ghi why unaffected controls/evidence vẫn được rely.

## 37. Continuous monitoring strategy

Strategy nêu:

- authorization assumptions/conditions cần theo dõi;
- controls/risks/assets/providers;
- evidence source/quality/freshness;
- periodic, event-driven và continuous cadence;
- thresholds/result states;
- owner/action/escalation;
- significant-change correlation;
- reporting tới authorizer/risk executive;
- strategy review triggers.

Telemetry không có consumer/action không duy trì decision. Monitoring phải bao gồm control effectiveness và context change, không chỉ vulnerabilities.

## 38. Decision thresholds và breach response

Ví dụ:

- critical control coverage < 98%;
- evidence stale > 24 giờ;
- unmitigated exposed pathway xuất hiện;
- condition milestone trễ 14 ngày;
- provider outage vượt tolerance;
- high-impact data population tăng > threshold;
- material incident/unauthorized use;
- aggregate exceptions vượt enterprise limit.

Mỗi threshold có data source, quality, owner và action: investigate, contain, narrow scope, escalate, suspend hoặc reauthorize. Không tự
revoke từ noisy metric nếu harm của false action cao; thêm validation gate phù hợp.

## 39. Ongoing authorization operating model

Ongoing authorization cần:

- continuously updated system/risk/control information;
- strong configuration/change management;
- assessment/evidence automation nơi phù hợp;
- stable ownership/authority;
- active findings/POA&M governance;
- significant-change detection;
- authorizer-ready reporting;
- tested suspend/revoke/recovery paths.

Nó không phải bỏ authorizer khỏi vòng lặp. Authorizer nhận exception/breach/change theo threshold và periodic confirmation theo risk.

## 40. Authorization health view

Health view không chỉ màu:

```text
decision / boundary / version / expiry
conditions and milestone health
top residual scenarios + trend/confidence
critical control coverage/evidence freshness
open findings/exceptions
common/supplier dependency health
significant changes pending
aggregate/concentration signals
required decisions/actions
```

Giữ drill-down và denominator. `Unknown/stale/error` không gộp pass; active exception không biến fail thành compliant.

## 41. Common-control change propagation

Khi provider common control thay đổi/fail:

```text
provider event/finding
  → active inheritance edges
    → affected authorization boundaries
      → impact/significance triage
        → consumer condition/assurance update
          → central + local remediation/retest
```

Một root provider issue có thể tạo enterprise escalation. Provider closure không tự đóng consumer impact nếu integration/backlog chưa
reconcile. Authorization package reference provider package thay vì copy stale evidence.

## 42. Incident và emergency decision

Incident có thể làm assumptions sai ngay lập tức. Emergency authority xác định:

- ai có thể isolate, disable, fail over, narrow use;
- evidence minimum và decision log;
- safety/business collateral review;
- temporary authorization/degraded operation duration;
- notification tới authorizer/legal/privacy;
- forensic/containment constraints;
- retrospective review và reconciliation;
- criteria restore normal authority.

Incident containment không mặc nhiên là revocation, nhưng material compromise không được tiếp tục dưới old authorization không review.

## 43. Exception, waiver và authorization

Exception là permission bounded đối với requirement; authorization là decision operation/use tổng thể. Package phải aggregate:

- exact exceptions/versions/scopes;
- compensating controls và health;
- risk owners/authority;
- expiry/remediation;
- interaction/concentration;
- legal non-waivable limits.

Authorizer có thể condition/deny dựa trên exception portfolio. Authorization không tự renew exception hoặc biến nó thành standard state.

## 44. Suspend và revoke

Predefine grounds:

- condition/threshold breach;
- material incident/compromise;
- scope/use outside boundary;
- critical control/provider failure;
- false/incomplete package information;
- legal/license/contract prohibition;
- owner/operations/support collapse;
- expired decision.

Action plan nêu safe shutdown/narrowing, customer/mission impact, data preservation, communication, recovery và reauthorization criteria.
Quyền revoke không có rehearsed operating path dễ trở thành lời đe dọa không dùng được.

## 45. Reauthorization và retirement

Reauthorization không phải đổi ngày. Nó cần:

- validate boundary/use/owner;
- diff requirements/control/system/provider;
- update scenarios/impact/aggregate risk;
- evaluate conditions/findings/exceptions;
- refresh targeted/full assessment evidence;
- confirm operations/recovery and monitoring;
- new decision/rationale/expiry.

Khi retire, revoke identities/access, dispose/retain data đúng duty, close supplier/common dependencies, archive package và confirm no
residual consumer. Retired status không xóa record/history.

## 46. Metrics cho authorization system

| Câu hỏi | Measure gợi ý |
|---|---|
| Decision timely và đủ evidence? | request→decision lead time, package rework, unknown/stale rate |
| Conditions có thật? | overdue/breached conditions, funded milestone, closure retest |
| Change được thấy? | change→triage latency, significant-change false miss/rework |
| Ongoing basis còn đúng? | boundary/config drift, evidence freshness, provider health |
| Risk được xử lý? | residual scenario trajectory, concentration, repeated finding |
| Lifecycle sạch? | expired-but-running, suspended-use violations, retirement backlog |

Không tối ưu số authorization issued hoặc approval speed một mình. Đo decision quality, timely adaptation và outcome.

## 47. Automation, machine-readable package và AI

Automation hỗ trợ:

- boundary/inventory/config graph;
- control/evidence references;
- schema/version validation;
- findings/POA&M status;
- change/threshold triggers;
- package diff và authorizer view;
- OSCAL-based assessment/results/POA&M exchange.

AI có thể summarize/candidate impact nhưng không sở hữu risk, determine legal authority hoặc ký decision. Giữ citations/provenance,
confidence, human review và access controls; không gửi privileged/sensitive package vào unapproved service.

## 48. Ví dụ: authorization payment service

Payment service mới dùng common identity/logging nhưng legacy reconciliation còn batch:

```text
boundary: payment API + data + CI/CD + identity/logging providers + reconciliation
top residual: duplicated transaction after partial regional failover
evidence: failover test found 2/500 duplicate records; detection in 7 minutes
decision: limited authorization for 10% transaction volume, 60 days
conditions: idempotency fix by day 30; daily reconciliation; no high-value cohort
threshold: duplicate > 0.2% or detection > 10m → pause
trigger: region expansion/provider change → focused reauthorization
```

Decision giảm scope và tạo learning; không gọi test fail là pass hoặc cho full rollout rồi hứa sửa sau.

## 49. Lộ trình triển khai 90 ngày

**Ngày 1–30 — Authority và pilot boundary**

- inventory authorization types/owners/expired decisions;
- định nghĩa delegation, states và decision schema;
- chọn một critical service pilot;
- map boundary/use/dependencies/common controls;
- baseline package/evidence/change gaps.

**Ngày 31–60 — Package và decision**

- dựng scenarios, categorization, baseline/tailoring;
- hoàn thành assessment/results/findings;
- mô tả residual/aggregate risk và options;
- phê duyệt conditions/thresholds/expiry;
- lưu decision record và authority provenance.

**Ngày 61–90 — Ongoing loop**

- nối continuous/event/periodic monitoring;
- tích hợp change/incident/provider triggers;
- diễn tập condition breach, suspend/revoke và emergency decision;
- reperform package/health view;
- review metrics/lessons và scale service tiếp theo.

## 50. Checklist, anti-pattern và tài liệu tham khảo

### Checklist production

- [ ] Decision có exact boundary/use/version, authorizer/authority và expiry.
- [ ] Package nối mission, scenarios, controls, evidence, findings và residual risk.
- [ ] Exclusions/dependencies/common controls vẫn hiện trong risk context.
- [ ] Assessment nói rõ design/implementation/operating effectiveness/limitations.
- [ ] Residual risk là scenario có coverage/uncertainty, không phải score subtraction.
- [ ] Aggregate/concentration và privacy/legal/safety constraints được challenge.
- [ ] Conditions có owner, funding, threshold, due date và consequence.
- [ ] Significant-change taxonomy/triage/reassessment levels được vận hành.
- [ ] Ongoing authorization có evidence freshness và suspend/revoke path.
- [ ] Reauthorization/retirement diff và reconcile toàn bộ dependency/history.

### Anti-pattern cần tránh

- Gọi security review, audit pass hoặc certificate là authorization.
- Boundary hẹp loại cloud/SaaS/common controls khỏi risk view.
- Package là PDF snapshot không version/linked evidence.
- Tính residual risk bằng inherent score trừ control score.
- Authorizer chỉ thấy composite màu xanh, không scenario/unknown/dissent.
- Conditions không funded hoặc due sau expiry.
- Authorization tự renew theo calendar.
- Mọi release đều “significant” hoặc không change nào trigger review.
- Provider finding không propagate tới consumer authorizations.
- Có quyền revoke nhưng không có safe operating procedure.

### Nguồn chính thức

- [NIST SP 800-37 Rev.2](https://csrc.nist.gov/pubs/sp/800/37/r2/final) — RMF lifecycle, system/common-control authorization, authorizing roles và ongoing authorization.
- [NIST SP 800-39](https://csrc.nist.gov/pubs/sp/800/39/final) — organization, mission/business và information-system risk views.
- [NIST SP 800-53 Rev.5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) — integrated security/privacy controls và assurance.
- [NIST SP 800-53A Rev.5](https://csrc.nist.gov/pubs/sp/800/53/a/r5/final) — assessment procedures/plans/results aligned với risk tolerance.
- [NIST SP 800-137](https://csrc.nist.gov/pubs/sp/800/137/final) — continuous monitoring strategy và control-effectiveness visibility.
- [NIST IR 8286 Rev.1](https://csrc.nist.gov/pubs/ir/8286/r1/final) — kết nối system/organization cybersecurity risk với ERM và enterprise objectives.
- [NIST OSCAL](https://csrc.nist.gov/projects/open-security-controls-assessment-language) — machine-readable SSP, assessment plan/results và POA&M artifacts.

### Học tiếp

1. [Security Governance Forums, Committees & Decision Records](security_governance_forums_committees_decision_records.md) — forum design,
   delegated authority, agenda, escalation, dissent, action và decision traceability.
2. [Security Risk Quantification, Scenario Analysis & Decision Uncertainty](security_risk_quantification_scenario_analysis_decision_uncertainty.md) — scenario frequency/impact,
   ranges, calibration, sensitivity, value of information và decision thresholds.

---

*Cập nhật lần cuối: 2026-08-03.*
