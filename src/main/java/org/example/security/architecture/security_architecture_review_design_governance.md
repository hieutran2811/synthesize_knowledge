# Security Architecture Review & Design Governance – Review để ra quyết định, không để tạo hàng đợi

Security Architecture Review (SAR) là cơ chế giúp team đưa ra và duy trì quyết định thiết kế đáng tin cậy. Nó không phải buổi duyệt
sơ đồ một lần trước go-live, cũng không phải nơi security architect viết thay solution. Design governance tốt tạo guardrail và feedback
theo rủi ro, đồng thời giữ traceability từ business outcome tới requirement, quyết định, implementation và evidence production.

```text
change intent + business / protection needs
    → risk triage + self-service pattern
        → focused review + threat / failure analysis
            → decision + ADR + requirements / actions
                → implementation + fitness functions + runtime evidence
                    → delta review / exception expiry / pattern improvement
```

Nên đọc cùng [Threat Modeling & Secure Architecture](threat_modeling_secure_architecture.md),
[Enterprise Security Architecture & Zero Trust](enterprise_security_architecture_zero_trust.md),
[Platform Engineering Security](../platform/platform_engineering_security.md) và
[Security Testing & Validation Engineering](../validation/security_testing_validation_engineering.md).

---

## 1. Security Architecture Review là gì?

SAR là hoạt động có cấu trúc để:

1. hiểu change/system và protection needs;
2. xác định decision/risk nào thực sự quan trọng;
3. kiểm tra design có đáp ứng principle, requirement và threat scenario;
4. so sánh option/trade-off;
5. ghi decision, owner, assumption, action và residual risk;
6. nối design intent với implementation/verification;
7. xem lại khi change hoặc evidence làm assumption không còn đúng.

Outcome không nhất thiết là “approved”. Có thể là pattern tự phục vụ, yêu cầu bổ sung, decision có điều kiện hoặc escalation.

## 2. Review không phải audit, pentest hay sign-off tuyệt đối

| Hoạt động | Câu hỏi chính |
|---|---|
| Architecture review | Design và trade-off có phù hợp protection needs không? |
| Threat modeling | Điều gì có thể xảy ra sai, theo path nào? |
| Code review/test/pentest | Implementation có flaw và control có hoạt động không? |
| Compliance/audit | Requirement/criteria có được đáp ứng với evidence không? |
| Risk acceptance | Authority nào chấp nhận residual risk trong scope/time? |

Review không chứng minh hệ thống “secure”. Nó tạo design intent có thể kiểm chứng và chỉ ra điều còn chưa biết.

## 3. Mục tiêu của design governance

Governance phải cân bằng bốn outcome:

- **quality:** decision xem đủ security/privacy/resilience;
- **speed:** low-risk/pattern-conformant change tự phục vụ;
- **consistency:** cùng scenario dùng semantics/control tương đương;
- **learning:** incident, exception và delivery feedback cải thiện pattern/platform.

Nếu review chỉ tăng lead time, team sẽ né. Nếu chỉ checklist nhanh mà không phát hiện cross-boundary risk, nó tạo cảm giác an toàn giả.

## 4. Decision rights và accountability

Tách rõ:

- product/business owner sở hữu outcome và delivery decision;
- solution architect sở hữu system design/trade-off;
- security architect challenge, tư vấn và xác nhận conformance/security decision;
- domain owner sở hữu identity/data/network/platform semantics;
- control/platform owner cam kết capability dùng chung;
- risk owner chấp nhận residual business risk;
- assurance xác minh implementation/evidence;
- architecture review board xử lý decision xuyên domain/ngoài authority.

Người review không tự nhận accountability thay owner. Người tạo exposure không tự phê duyệt exception vượt authority.

## 5. Systems security engineering thay cho “security layer”

NIST SP 800-160 Vol. 1 coi security là phần của systems engineering trong toàn lifecycle. Điều này nghĩa là review xét:

- stakeholder/mission và loss concern;
- concept of operation và environment;
- requirement, architecture, implementation và integration;
- verification, validation, transition, operation và disposal;
- safety, reliability, privacy, human và supplier interaction;
- trustworthiness dưới threat/uncertainty.

Không thể “thêm security” sau khi service boundary, data ownership và privilege model đã khóa.

## 6. Workflow review end-to-end

```text
intake → auto triage → pattern/self-review
  → focused workshop/escalation khi cần
    → decision + requirements/actions
      → delivery checkpoints + verification
        → production evidence + closure
          → change trigger / periodic health review
```

Mỗi bước có entry/exit criterion và service-level expectation. Không bắt team chờ họp board hàng tuần cho một thay đổi đã conform golden path.

## 7. Intake tối thiểu nhưng đủ định tuyến

Intake nên hỏi:

- business capability/use case và owner;
- change mới hay delta, target date;
- user/workload/tenant và exposure;
- data classification/purpose/residency;
- identity, privilege và external integration;
- technology/runtime/region;
- availability/RTO/RPO/safety impact;
- third party/AI/new capability;
- diagram/repository/ADR/threat model hiện có.

Không yêu cầu 100 câu trước khi biết risk. Dữ liệu intake có schema để tự triage, reuse và đo flow.

## 8. Risk triage bằng trigger, không bằng cảm tính

Escalation trigger ví dụ:

- public/high-volume hoặc cross-tenant interface;
- sensitive/regulated/safety data/process;
- authentication, authorization, key/trust model mới;
- privileged/control-plane capability;
- new third party/subprocessor/data transfer;
- material architecture/technology pattern mới;
- irreversible/destructive/financial action;
- low RTO/RPO hoặc novel failure mode;
- AI autonomous/tool/data access;
- prior incident/exception hoặc unresolved high risk.

Triage quyết depth và reviewer, không tự tính residual risk từ tổng số trigger.

## 9. Review tier theo risk và novelty

| Tier | Khi dùng | Cơ chế |
|---|---|---|
| 0 – pre-approved | không đổi security semantics, golden path | automated conformance + owner attestation |
| 1 – lightweight | low/moderate risk, pattern quen | async self-review + security champion |
| 2 – focused | material data/access/boundary/change | workshop với domain reviewer |
| 3 – deep | critical/novel/cross-enterprise | threat model, option analysis, board/risk escalation |

Depth theo impact, novelty, control gap và evidence—not theo seniority của team hoặc kích thước dự án.

## 10. Delta review và trigger tái đánh giá

Không review lại toàn hệ thống cho mỗi PR. Mô tả delta:

- component/flow/trust boundary nào thêm/bỏ/đổi;
- identity/data/privilege/failure semantics có đổi không;
- assumption/control/pattern nào bị ảnh hưởng;
- test/evidence nào cần cập nhật;
- residual risk/exception nào không còn đúng.

Trigger gồm incident, major dependency/version, region/tenant/model/provider, new data purpose, privilege increase, RTO/RPO và pattern deprecation.

## 11. Bộ artifact tối thiểu

Tùy tier, nhưng thường cần:

- scope/context và business/protection needs;
- context/component/data-flow diagram có version;
- trust/administrative/data boundary;
- identity, data, dependency và failure flow;
- security/privacy/resilience requirements;
- threat/abuse/failure scenarios ưu tiên;
- option/trade-off và ADR;
- control ownership/assumption;
- actions, test/evidence và residual risk;
- change/review trigger.

Artifact phải đủ để quyết định, không buộc viết document dài theo template.

## 12. System context và scope

Context diagram trả lời:

- system of interest là gì và ngoài scope là gì;
- actor/system/supplier nào tương tác;
- data/control nào đi qua boundary;
- owner/authority/trust domain nào thay đổi;
- environment và operational constraint;
- dependency dùng chung/critical;
- assumption nào chưa xác minh.

Một box “Cloud” hoặc “Backend” quá thô để review. Nhưng diagram không cần thể hiện mọi Pod/route nếu decision không phụ thuộc chi tiết đó.

## 13. Flow và trust boundary

Review theo flow thực: browser/API/webhook/queue/batch/admin/support/backup/DR. Với mỗi crossing hỏi:

- principal/resource/action là gì;
- identity/assertion từ ai, freshness/confidence;
- validation/authorization/encryption;
- replay/idempotency/ordering;
- error/timeout/retry/fallback;
- log/evidence và privacy;
- bypass/alternate path;
- owner khi dependency fail.

Chi tiết phương pháp nằm ở chương threat modeling; SAR dùng kết quả để chọn/ghi design decision.

## 14. Từ business objective tới security requirement

Traceability:

```text
business objective / unacceptable loss
  → protection need
    → threat / failure scenario
      → security requirement
        → design control + owner
          → verification + runtime evidence
```

Ví dụ “chỉ merchant sở hữu đơn hàng được refund” tốt hơn “dùng OAuth”. OAuth là mechanism; resource-level authorization và ownership invariant mới là requirement.

## 15. Kết hợp threat model mà không lặp workshop

Review không nhất thiết tạo threat model mới. Nó có thể:

- reuse enterprise/domain threat library;
- apply pattern threat model và ghi delta;
- chạy focused abuse/failure session cho decision mới;
- yêu cầu deep model khi crossing novel/critical;
- cập nhật living threat model sau decision;
- sinh negative/failure tests từ scenario.

Không coi “đã threat model” là checkbox nếu diagram/scope/assumption không còn đúng.

## 16. Chuỗi principle → pattern → solution

- **Principle** định hướng: không tin cậy ngầm theo network location.
- **Standard/requirement** ràng outcome: workload phải có identity riêng, credential ngắn hạn.
- **Reference pattern** đưa cấu trúc tái sử dụng: workload-to-service qua identity-aware PEP.
- **Solution** chọn component/config cho context cụ thể.
- **Evidence** chứng minh effective path không bypass.

Review nên hỏi solution conform outcome/semantics, không ép tên vendor khi nhiều implementation hợp lệ.

## 17. Reference architecture có known limits

Một reference architecture hữu ích gồm:

- context/use cases và ngoài scope;
- logical components/responsibility;
- identity/data/control/failure flows;
- trust/administrative boundary;
- required capabilities/standards;
- deployment variants/trade-offs;
- security assumptions và known limits;
- conformance/verification points;
- owner/version/deprecation path.

Không copy diagram reference vào solution rồi tuyên bố conform; phải map component và chứng minh assumption.

## 18. Pattern và anti-pattern

Pattern ghi context, problem, forces, solution, consequences, controls, evidence và known limits. Ví dụ: BFF session, workload identity,
outbox/event, data export approval, privileged administration, legacy proxy.

Anti-pattern không chỉ “cấm”: giải thích failure như shared service account, direct-origin bypass, synchronous authorization không degraded mode,
admin API dùng cùng public token. Từ recurring review finding, ưu tiên tạo pattern/platform capability thay vì nhắc từng team.

## 19. Golden path và paved road

Golden path đóng gói pattern thành template/service/SDK/policy/test/documentation. SAR kiểm:

- secure defaults và unsafe option có bị khóa;
- version/upgrade/deprecation;
- capability owner/SLO/runbook;
- telemetry/evidence mặc định;
- extension/escape hatch;
- exception lifecycle;
- conformance trên effective state;
- developer experience và adoption.

Self-service chỉ an toàn khi platform boundary chống confused deputy và tenant không tự cấp exception.

## 20. Architecture Decision Record (ADR)

ADR tối thiểu:

```text
title / status / date / owners
context + decision drivers + assumptions
options considered + security/privacy/resilience trade-offs
decision + consequences
requirements / actions / evidence
residual risks + exceptions
review triggers + supersedes / related ADRs
```

ADR ghi **vì sao**, không thay detailed design. Không sửa lịch sử quyết định âm thầm; supersede bằng ADR mới để giữ provenance.

## 21. Phân tích option và trade-off

So sánh theo outcome:

- risk reduction/attack surface/blast radius;
- availability/latency/consistency;
- data/privacy/residency;
- operational complexity/skill;
- dependency/concentration/lock-in;
- migration/recovery/exit;
- cost/time-to-value;
- evidence/assurance;
- uncertainty/reversibility.

Ghi assumption và sensitivity: nếu revoke latency hoặc traffic tăng, option còn phù hợp không? Không chấm điểm ordinal rồi cộng thành “winner” giả khách quan.

## 22. Control ownership và inheritance

Mỗi control decision ghi provider, consumer và shared duty:

- objective và scope;
- implementation/capability;
- consumer configuration/precondition;
- interface/SLO/failure behavior;
- evidence và freshness;
- change/incident notification;
- fallback/exception;
- recovery/deprecation.

“Platform xử lý security” không đủ. Product có thể vẫn phải chọn classification, role mapping, retention và application invariant đúng.

## 23. Design intent, implementation và evidence

Tách ba trạng thái:

| Lớp | Ví dụ |
|---|---|
| Design intent | mọi admin action đi qua JIT approval gateway |
| Implementation | gateway/policy/route/config đã deploy |
| Effective evidence | direct path bị chặn; expired grant bị deny; log có actor/action |

Review design chỉ đóng lớp đầu. Closure cần owner và checkpoint cho implementation/verification; tránh “approved architecture” tồn tại khi runtime drift.

## 24. Requirement phải kiểm chứng được

Requirement tốt chứa actor/resource/action/condition/outcome và verification:

> Mọi export dữ liệu Restricted trên 1.000 record phải yêu cầu hai approver độc lập, grant hết hạn sau 30 phút,
> không có direct storage path và tạo audit event liên kết request–decision–export digest.

“Dùng encryption”, “theo best practice”, “log đầy đủ” không đủ. Version standard/reference như ASVS; tránh identifier trôi khi standard cập nhật.

## 25. Identity và authorization review

Hỏi theo lifecycle/flow:

- human/workload/device identity bootstrap và revoke;
- issuer/audience/claim/trust contract;
- authentication assurance/recovery/session;
- resource/action/tenant-level authorization;
- effective permission/delegation/confused deputy;
- privileged/JIT/break-glass/support path;
- service account/static secret;
- direct/batch/admin/async bypass;
- decision/enforcement evidence;
- IdP/PDP/PIP outage behavior.

MFA/SSO/mTLS không thay business authorization.

## 26. Data và privacy review

Review data lifecycle:

- inventory/classification/owner/purpose;
- collection/minimization/default;
- tenant/subject/region boundary;
- read/write/share/export/admin access;
- encryption/key/tokenization/masking;
- lineage/derived data/model use;
- log/cache/temp/backup/analytics copy;
- retention/legal hold/deletion verification;
- third party/subprocessor;
- breach/data-right/recovery workflow.

Privacy review không chỉ hỏi “có PII không”; purpose, linkability, observability và autonomy có thể tạo harm dù dữ liệu không mang nhãn PII.

## 27. API, integration và async review

Kiểm:

- API resource model/version/compatibility;
- authn/authz/rate/quota;
- input/output/schema/size validation;
- webhook source/replay/idempotency;
- queue producer/consumer identity, topic/record policy;
- retry/backoff/dead-letter/poison message;
- ordering/duplicate/ambiguous transaction;
- egress/destination/data minimization;
- dependency timeout/circuit breaker;
- correlation/evidence và kill switch.

Async path và batch/admin endpoint thường bị bỏ khỏi diagram nhưng có quyền tương đương hoặc lớn hơn public API.

## 28. Cloud, platform và control-plane review

Xem organization/account/project/subscription hierarchy, landing zone, identity federation, network/data/key boundary, region, quota và shared service.
Đặc biệt hỏi:

- control/management plane được ai quản trị;
- policy/IaC/admission có đường bypass;
- platform controller credential blast radius;
- tenant/workload isolation;
- backup/DR có cùng admin boundary;
- logs có nằm ngoài compromise path;
- provider/customer shared responsibility;
- bootstrap/recovery khi control plane hỏng.

“Managed service” giảm một phần operation, không xóa customer architecture duty.

## 29. Failure mode và resilience review

Với mỗi dependency/control, thử unavailable, stale, slow, partial, compromised và inconsistent—not chỉ down. Ghi:

- fail open/closed/degraded theo action tier;
- timeout/retry/load amplification;
- cache TTL/freshness/revoke;
- redundancy thật và concentration;
- data consistency/reconciliation;
- backup/clean recovery;
- RTO/RPO/MBCO;
- operator/communication dependency;
- test/drill và recovery evidence.

Availability và security cùng là design trade-off; “fail closed mọi thứ” có thể gây safety/mission loss không chấp nhận được.

## 30. Third-party và SaaS review

Review relationship chứ không chỉ vendor certificate:

- data/access/business dependency và tier;
- shared responsibility và tenant config;
- federation/OAuth/support privilege;
- evidence scope/freshness;
- subprocessor/location/concentration;
- incident/customer containment;
- availability/backup/recovery;
- contract obligation/operational owner;
- portability/deletion/exit.

Chi tiết nằm ở [Third-Party & SaaS Security Assurance](../third_party/third_party_saas_security_assurance.md).

## 31. AI và emerging capability review

Novelty là escalation trigger vì assumption/control/evidence chưa chín. Với AI-enabled system, hỏi:

- model/tool autonomy và action boundary;
- training/RAG/prompt/output data lifecycle;
- identity/authorization cho connector/tool;
- prompt injection/data exfiltration;
- provenance/version/evaluation và model/provider change;
- human oversight/appeal/fallback;
- abuse/safety/privacy/bias theo use case;
- output validation trước business action;
- logging/incident/kill switch;
- dependency/exit và residual uncertainty.

Không dùng “AI policy approved” thay review data/action flow cụ thể.

## 32. Cơ chế một buổi review hiệu quả

Trước buổi họp, reviewer đọc artifact và gửi câu hỏi/decision cần xử lý. Trong buổi:

1. owner nêu outcome, scope, delta và constraints;
2. walkthrough flow/boundary, không đọc slide;
3. tập trung top decision/threat/failure;
4. so sánh option và assumption;
5. ghi decision/action ngay tại nguồn;
6. xác nhận owner, due date, evidence và escalation;
7. parking-lot vấn đề ngoài scope.

Kết thúc với shared understanding, không để “security sẽ gửi note sau” làm mơ hồ trạng thái.

## 33. Reviewer đúng domain và collaboration

Tùy scope mời product/solution architect, AppSec, cloud/platform, IAM, data/privacy, reliability, safety, fraud, legal/compliance,
incident/operations và supplier expert. Không cần tất cả mọi buổi; triage chọn domain.

Security architect đóng vai trò integrator/challenger, không giả vờ biết sâu mọi chuyên môn. Ghi disagreement và decision authority; tránh “design by committee” nơi không ai sở hữu consequence.

## 34. Challenge có bằng chứng, không dựa quyền lực

Câu hỏi tốt:

- outcome/threat/failure nào quyết định requirement này;
- assertion/attribute đến từ đâu và có thể stale/giả thế nào;
- path nào bypass control;
- dependency mất/compromise thì sao;
- blast radius và recovery boundary;
- evidence nào làm ta đổi quyết định;
- option ít phức tạp hơn có đạt outcome không;
- residual unknown do thiếu dữ liệu gì.

Không nói “security best practice yêu cầu” nếu không giải thích context và consequence.

## 35. Trạng thái quyết định rõ nghĩa

Ví dụ state machine:

```text
intake → triaged → reviewing
  → conformant / conditionally conformant / redesign required / escalated
    → implementation verified → closed
```

- conformant: đáp ứng requirement/pattern trong scope;
- conditional: decision hợp lệ khi actions/preconditions hoàn tất;
- redesign required: invariant/requirement chưa đạt, không phải risk acceptance;
- escalated: trade-off vượt authority;
- closed: evidence implementation đã kiểm.

Tránh nhãn “security approved” tuyệt đối và vĩnh viễn.

## 36. Action, finding và design debt

Record cần requirement/scenario, observation, consequence, owner, due date, milestone, verification và dependency. Phân biệt:

- question/unknown cần evidence;
- design action trước implementation;
- implementation defect;
- improvement/debt;
- exception/risk decision;
- out-of-scope issue chuyển owner khác.

Không để mọi note thành blocker hoặc mọi blocker thành backlog vô thời hạn. Closure phải dựa evidence, không chỉ owner comment “done”.

## 37. Exception, waiver, deviation và pattern gap

Exception tốt ghi:

- standard/requirement bị lệch và lý do;
- exact scope/environment/path;
- threat/business consequence;
- compensating control + coverage/health;
- residual risk/authority;
- owner, milestone và expiry;
- monitoring/review trigger;
- rollback/return-to-standard và verification.

Nhiều exception cùng lý do cho thấy pattern/platform gap; aggregate và tài trợ fix dùng chung thay vì gia hạn từng ticket.

## 38. Risk acceptance và escalation

Reviewer cung cấp scenario, option, control gap, uncertainty và recommendation. Risk owner quyết khi residual risk nằm trong authority; higher impact/concentration/
appetite breach lên cấp phù hợp. Decision log ghi:

- business objective và deadline;
- options/cost/risk;
- affected stakeholder;
- residual risk và confidence;
- conditions/expiry/triggers;
- accountable authority.

Delivery pressure không phải bằng chứng likelihood thấp. Security cũng không được dùng escalation để tránh đưa option khả thi.

## 39. Architecture Review Board dùng cho việc gì?

Board nên xử lý:

- decision xuyên domain/team có consequence enterprise;
- pattern/standard mới hoặc thay đổi lớn;
- strategic concentration/shared control;
- unresolved conflict giữa objectives;
- exception vượt authority;
- investment/deprecation/transition architecture;
- recurring systemic findings.

Không duyệt từng application design hoặc đọc status. Publish decision/precedent và delegate decision lặp lại xuống domain/golden path.

## 40. Federated governance và security champion

Scale bằng mô hình federated:

- central architecture sở hữu principle, taxonomy, enterprise pattern;
- domain architect sở hữu semantics/reference design;
- platform team encode guardrail/golden path;
- security champion hỗ trợ self-review/delta;
- specialist review high-risk/novel;
- board xử lý systemic/escalated;
- assurance kiểm effective outcome.

Delegation cần training, authority boundary, calibration và sampled review. Champion không phải security person “kiêm nhiệm trách nhiệm vô hạn”.

## 41. Policy/architecture as code

Artifact có schema giúp automation:

- intake/triage rule;
- ADR/requirement/control linkage;
- pattern version/conformance metadata;
- policy/guardrail/test;
- exception scope/expiry;
- dependency/owner freshness;
- evidence query và dashboard.

Automation kiểm rule rõ ràng, không tự giải trade-off mơ hồ. Version rule và lưu input/decision/provenance để giải thích false positive/negative.

## 42. Architecture fitness function

Fitness function là phép kiểm lặp lại cho đặc tính kiến trúc quan trọng, ví dụ:

- không public storage chứa data Restricted;
- mọi workload production có identity riêng;
- không route nào tới origin bỏ qua gateway;
- service dependency có timeout/circuit breaker;
- admin role chỉ được cấp qua JIT;
- backup copy nằm ngoài production delete authority;
- event schema giữ tenant/provenance field.

Có thể là static check, policy, integration/negative test hoặc runtime query. Không phải mọi principle đều tự động hóa được; ghi coverage/limit.

## 43. Conformance và architecture drift

Conformance kiểm outcome/semantics, không chỉ presence của component:

```text
declared pattern + mapped components + required config
  + negative/failure tests + effective runtime state
```

Drift đến từ manual config, new path, platform version, feature flag, emergency change, shadow dependency hoặc expired exception. Dùng continuous signal và
periodic sampling; unknown/missing evidence không được tự chuyển thành compliant.

## 44. Review trong Agile và continuous delivery

Review sớm ở discovery/design, nhưng bám delivery bằng:

- security requirements/acceptance criteria trong backlog;
- threat/ADR delta khi story thay boundary;
- champion/async office hour;
- golden path và automated guardrail;
- focused checkpoint trước irreversible/high-risk step;
- release evidence thay manual sign-off cho routine change;
- post-deploy verification.

“Shift left” không có nghĩa dồn mọi security task vào developer; platform, operations và production feedback vẫn thiết yếu.

## 45. Handoff từ design sang implementation

Mỗi decision phải đi vào artifact team dùng:

- backlog requirement/action có owner;
- API/schema/IaC/policy/config contract;
- reference implementation/template/SDK;
- test case và evidence location;
- operational SLO/alert/runbook;
- rollout/rollback/migration;
- exception condition;
- review/closure trigger.

Một PDF review không liên kết repo/backlog/test sẽ drift. Trace link nên hai chiều và stable qua đổi ticket/tool.

## 46. Verification và production feedback

Trước closure, xác minh:

- implementation map design decision;
- required positive/negative/failure test pass;
- direct/bypass/admin/async path được kiểm;
- effective config/permission/data flow đúng;
- telemetry/evidence hoạt động;
- rollback/revoke/recovery được test theo risk;
- residual action/exception còn hợp lệ;
- synthetic/business invariant sau deploy.

Incident, vulnerability, drift và operating metric có thể invalidate ADR/assumption và trigger delta review.

## 47. Metric cho flow và outcome

Đo hai nhóm:

| Flow | Outcome/quality |
|---|---|
| intake-to-triage/review/decision lead time | critical changes reviewed đúng tier |
| wait time vs active review time | recurring risk được productize thành pattern |
| self-service/pattern reuse rate | conformance/effective evidence coverage |
| action closure/retest age | escaped design issue/incident feedback |
| review rework/late-engagement rate | expired/repeated exception và drift |

Không tối ưu số review hoặc approval rate. Lead time thấp do bỏ qua critical flow không phải thành công.

## 48. Maturity và transformation roadmap

```text
Stage 0: ad-hoc expert gate, artifact rời rạc
Stage 1: intake/tiering/template/decision log
Stage 2: patterns, champions, domain review, traceable requirements
Stage 3: golden paths, fitness functions, effective-state evidence
Stage 4: continuous conformance, production feedback, systemic learning
```

Bắt đầu bằng top recurring decisions và critical changes; đừng xây portal lớn trước khi semantics/workflow rõ. Mỗi wave có adoption, quality và risk-reduction outcome.

## 49. Ví dụ end-to-end: thêm tính năng bulk data export

**Change:** product B2B cho tenant admin export tối đa hàng triệu customer records sang object storage do khách hàng chọn.

1. Intake trigger Tier 3 vì Restricted data, cross-tenant, external destination và high-volume irreversible action.
2. Context/DFD làm rõ UI, export API, job queue, worker, data store, customer bucket, key/log/support path.
3. Threat/failure focus: broken tenant authz, confused deputy, SSRF/destination takeover, duplicate job, partial export, log/temporary copy, exfiltration.
4. Options: direct presigned upload, customer pull, managed transfer gateway; so sánh identity, egress, audit, reliability và cost.
5. ADR chọn managed transfer: destination ownership challenge, allow-listed scheme, tenant-bound job identity, dual approval và short-lived grant.
6. Requirement thêm field minimization, per-tenant quota, encrypted temp with expiry, digest/manifest, cancel/revoke và immutable decision log.
7. Failure design dùng idempotency, checkpoint, no cross-tenant retry, customer-visible status và cleanup/reconcile.
8. Fitness functions kiểm worker identity, public bucket deny, origin bypass, temp retention và event tenant/provenance.
9. Negative tests thử tenant khác, stale grant, DNS/rebinding-like destination change, approval self-service và queue replay theo môi trường an toàn.
10. Canary tenant, synthetic export digest và egress monitoring xác minh effective state.
11. Một legacy region thiếu destination control nhận exception 45 ngày, giảm record limit, owner/expiry/retest rõ.
12. Production signal về failure/exception/adoption cập nhật reference export pattern cho team khác.

Review thành công vì quyết định được encode và kiểm tiếp, không vì meeting kết thúc với dấu “Approved”.

## 50. Checklist, anti-pattern và tài liệu chính thức

### Checklist production

- [ ] Workflow có intake, risk triage, tier, service expectation và authority rõ.
- [ ] Low-risk/pattern-conformant change có self-service; high-risk/novel change được review sâu.
- [ ] Scope, context, flows, trust boundaries, assumptions và protection needs đủ để quyết định.
- [ ] Requirement trace từ business loss/threat tới control, test và runtime evidence.
- [ ] Principle, standard, pattern, solution và implementation không bị trộn lẫn.
- [ ] Reference pattern có known limits, conformance point, owner/version/deprecation.
- [ ] ADR ghi options/trade-off/assumption/consequence/trigger, không sửa lịch sử âm thầm.
- [ ] Identity, data, API/async, control plane, third party và failure mode được review theo scope.
- [ ] Shared/inherited control có provider-consumer contract và evidence.
- [ ] Decision status/action/finding/exception/risk acceptance là artifact riêng có semantics.
- [ ] Board chỉ xử lý systemic/escalated decision; domain/champion/platform được delegation rõ.
- [ ] Fitness function/guardrail encode invariant quan trọng và ghi giới hạn coverage.
- [ ] Handoff nối ADR/requirement với repo/backlog/test/runbook/evidence.
- [ ] Closure cần implementation/effective-state verification, không chỉ design sign-off.
- [ ] Metric đo flow + escaped risk/conformance/learning, không đếm approval.

### Anti-pattern thường gặp

- “Security review là buổi ký duyệt sơ đồ trước release.”
- “Mọi change phải chờ Architecture Review Board.”
- “Checklist pass nghĩa design không còn risk.”
- “Threat model đã làm một lần nên không cần delta review.”
- “Dùng đúng vendor/tool chuẩn nghĩa conform pattern.”
- “ADR là risk acceptance.”
- “Platform lo security nên product không còn responsibility.”
- “Approved architecture chứng minh runtime secure.”
- “Shift left nghĩa giao toàn bộ security cho developer.”
- “Fitness function tự động hóa được mọi architecture principle.”
- “Nhiều exception là lỗi riêng của từng team.”
- “Review nhiều và nhanh nghĩa governance trưởng thành.”

### Tài liệu chính thức

- [NIST SP 800-160 Vol. 1 Rev. 1 – Engineering Trustworthy Secure Systems](https://csrc.nist.gov/pubs/sp/800/160/v1/r1/final)
- [NIST SP 800-218 – Secure Software Development Framework](https://csrc.nist.gov/pubs/sp/800/218/final)
- [NIST SP 800-53 Rev. 5 – Security and Privacy Controls](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)
- [NIST SP 800-53A Rev. 5 – Assessing Security and Privacy Controls](https://csrc.nist.gov/pubs/sp/800/53/a/r5/final)
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)
- [CISA Secure by Design](https://www.cisa.gov/securebydesign)
- [OWASP Application Security Verification Standard](https://owasp.org/www-project-application-security-verification-standard/)
- [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [OWASP Software Assurance Maturity Model](https://owaspsamm.org/)

### Học tiếp

1. [Security Metrics, Measurement & Executive Reporting](../metrics/security_metrics_measurement_executive_reporting.md) – metric semantics, uncertainty,
   leading/lagging indicators, aggregation và decision-oriented communication.
2. [Security Program Operating Model & Capability Management](../program/security_program_operating_model_capability_management.md) – service catalog, ownership,
   funding, capacity, portfolio prioritization và capability maturity.

---

*Cập nhật lần cuối: 2026-08-03.*
