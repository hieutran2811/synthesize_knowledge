# Security Transformation & Change Management

> Mục tiêu: chuyển security target state thành cách làm được chấp nhận, vận hành và kiểm chứng trong thực tế — với
> transition state an toàn, migration theo wave, feedback, rollback, legacy retirement và ownership bền vững.

---

## 1. Transformation là thay đổi một hệ thống

Security transformation thay đổi đồng thời:

- risk decision và accountability;
- capability/service/control;
- architecture, data và technology;
- workflow, role và skill;
- incentive, culture và behavior;
- funding, sourcing và operating model;
- evidence, metrics và governance.

```text
business / risk reason
    → target outcome + transition principles
        → stakeholder / process / technology changes
            → pilots + migration waves + safe cutover
                → adoption + effectiveness + institutionalization
```

Thành công không phải “go-live”, mà là target behavior/control hoạt động ổn định và legacy/risk cũ được loại bỏ.

## 2. Transformation không phải tool rollout

Những việc sau chưa đủ gọi là transformation:

- mua license hoặc deploy platform;
- publish policy mới;
- gửi email thông báo;
- hoàn thành training;
- di chuyển một pilot nhưng không có adoption waves;
- đạt milestone project nhưng chưa có run owner;
- đổi sơ đồ tổ chức mà interface/quyết định vẫn cũ;
- giữ legacy vô hạn “để dự phòng”.

Tool có thể là một enabler. Nếu workflow, ownership, incentive, integration, support, evidence và retirement không đổi,
doanh nghiệp thường chỉ thêm một lớp công nghệ và chi phí.

## 3. Chuỗi từ strategy tới adoption

```text
strategic choice / risk response
    → capability + target profile
        → transformation portfolio / roadmap
            → service / platform / process change
                → consumer adoption + migration
                    → effective-state evidence + benefits
```

Mọi change work phải trace lên target outcome; mọi target outcome phải có initiative/adoption path. Đọc
[Security Strategy, Investment & Portfolio Prioritization](security_strategy_investment_portfolio_prioritization.md)
để xác định business case, dependency, funding và stop/pivot/continue trước khi scale.

## 4. Phân biệt transformation, change, release và project

| Khái niệm | Phạm vi |
|---|---|
| Transformation | thay đổi target operating state và capability nhiều chiều |
| Organizational change | giúp stakeholder hiểu, chấp nhận và thực hiện cách làm mới |
| Technical change | sửa configuration/code/infrastructure có control |
| Release | đưa một version/capability vào môi trường |
| Migration | chuyển consumer/data/workload từ trạng thái A sang B |
| Project | cấu trúc tạm thời để tạo deliverable/outcome |
| Product/service lifecycle | vận hành, cải tiến và retire capability lâu dài |

Transformation chứa nhiều project/release/change nhưng không kết thúc chỉ vì chúng đóng. Adoption, effective state và
legacy retirement mới hoàn tất chuyển đổi.

## 5. Outcome, scope và horizon

Charter cần xác định:

- business objective/risk scenario;
- current và target outcome;
- population, geography, product, partner trong scope;
- explicit out-of-scope;
- horizon Now/Next/Later;
- minimum viable transition;
- non-negotiable guardrails;
- benefits, disbenefits và residual risk;
- sponsor, outcome owner và run owner;
- review/stop triggers.

Tránh scope “toàn enterprise” không phân wave. Scope phải đủ rõ để inventory denominator, dependency và owner.

## 6. Current, Target và Transition Profiles

[NIST SP 1301](https://csrc.nist.gov/pubs/sp/1301/final) dùng Organizational Profiles để mô tả current/target CSF outcomes.
Transformation cần thêm **transition profile**:

| Profile | Câu hỏi |
|---|---|
| Current | Outcome nào đang đạt, bằng evidence và coverage nào? |
| Target | Trạng thái đủ nào cần đạt theo objective/risk appetite? |
| Transition | Trong giai đoạn coexistence, control/owner/failure mode nào giữ an toàn? |

Transition state không chỉ là target chưa hoàn thành. Nó là architecture/operating state riêng: hai identity systems,
dual policy, data sync, parallel support hoặc temporary exception có failure modes mới.

## 7. Transformation principles

Thống nhất nguyên tắc trước design:

- outcome và risk trước output;
- consumer workflow/adoption là phần của solution;
- thin slice end-to-end trước scale;
- transition state phải secure và operable;
- no irreversible cutover nếu chưa có evidence tương xứng;
- automation có preview, limit, rollback;
- migration theo blast radius/failure domain;
- exception có owner/expiry/return path;
- legacy retirement được fund từ đầu;
- feedback thay đổi roadmap, không chỉ communication;
- protect run/incident capacity trong transformation.

Principle cần được dùng trong gate và decision log, không chỉ đặt trên slide.

## 8. Executive sponsor và guiding coalition

Sponsor phải có quyền giải quyết conflict về priority, funding, policy và cross-domain dependency. Một guiding coalition
thường gồm business, technology, security/risk, operations, finance, HR/change, legal/privacy và đại diện consumer.

Coalition cần:

- common outcome/narrative;
- explicit decision rights;
- protected capacity;
- shared view dependency/risk;
- escalation path;
- cadence theo decision;
- commitment thực hiện behavior mới.

Không chọn sponsor chỉ vì chức danh. Sponsor không sẵn sàng dừng bypass, fund migration hoặc xử lý manager conflict sẽ
không tạo được transformation.

## 9. Governance và role clarity

| Vai trò | Accountability |
|---|---|
| Executive sponsor | outcome, resources, enterprise conflict |
| Transformation lead | integrated roadmap, dependency, change health |
| Capability owner | target capability và long-term health |
| Product/service owner | value, adoption, support, lifecycle |
| Technical owner | design, release, reliability, rollback |
| Business/domain owner | local adoption, process/control operation |
| Change lead | stakeholder impact, readiness, communication |
| Risk owner | residual/transition risk decision |
| Benefits owner | baseline, realization và sustainment |

Một RACI không đủ nếu không biết ai quyết cutover, pause, accept residual risk hoặc retire legacy.

## 10. Integrated transformation roadmap

Roadmap phải nối các workstream:

- policy/standard;
- architecture/platform/integration;
- data/inventory/evidence;
- service/support/operations;
- workforce/skill/role;
- business process/adoption;
- supplier/contract;
- assurance/risk/exception;
- decommission/financial exit.

Mỗi milestone cần outcome, dependency, consumer population, confidence và decision gate. Không để technical roadmap xanh
trong khi procurement, data, support hoặc domain adoption đỏ.

## 11. Stakeholder map

Map theo ảnh hưởng và influence:

| Stakeholder | Cần hiểu |
|---|---|
| Sponsor/board | risk, outcome, investment, decision |
| Control/risk owner | residual risk, delegation, evidence |
| Product/domain team | workflow, migration effort, local benefit |
| Operators/support | runbook, on-call, failure/recovery |
| End user/customer | behavior, friction, continuity |
| HR/legal/privacy | role, data, labor/regulatory constraint |
| Supplier/partner | interface, contract, timeline, exit |
| Assurance/audit | control mapping, evidence, transition scope |

Không chỉ đánh nhãn “supportive/resistant”. Ghi interest, impact, concern, authority, trusted channel và action needed.

## 12. Change impact assessment

Với từng stakeholder/cohort, đánh giá delta:

- process/task/decision;
- role/accountability;
- skill/knowledge;
- tool/interface/access;
- data/reporting;
- policy/incentive/performance;
- workload/capacity;
- dependency/handoff;
- failure/recovery;
- emotional/trust/status impact.

Đánh mức impact theo evidence, không đoán. “Chỉ thêm MFA” có thể tác động thiết bị, recovery, frontline shift, partner,
accessibility và support capacity lớn hơn dự kiến.

## 13. Persona và journey theo work context

Journey map:

```text
discover → decide / request → onboard → first success
    → routine use → support / exception → incident / recovery → offboard
```

Quan sát từng step: trigger, goal, channel, cognitive load, wait, error, workaround, evidence và owner. Persona dựa trên
task/context như “contractor dùng mobile ở site” hữu ích hơn demographic stereotype.

Journey giúp phát hiện adoption không dừng ở provisioning: first use thành công nhưng recovery/support kém vẫn dẫn tới bypass.

## 14. Readiness assessment

Readiness không phải một survey score. Giữ profile:

- sponsor/manager commitment;
- target/design clarity;
- platform reliability/security;
- inventory/data quality;
- process/policy alignment;
- consumer capacity và skill;
- support/on-call/runbook;
- vendor/contract readiness;
- migration/recovery tooling;
- evidence/measurement;
- competing change và local constraints.

Xác định blocker, owner, due date và minimum entry criteria. Không average màu đỏ/xanh thành “78% ready”.

## 15. Change saturation và portfolio collision

Một cohort có thể đồng thời nhận ERP, cloud, reorg, MFA và policy changes. Quản:

- số/độ lớn change theo population/time;
- shared manager/SME/training/support capacity;
- peak business/blackout period;
- message/process conflicts;
- repeated migration fatigue;
- cumulative productivity/friction;
- incident/operational reserve.

Sequence hoặc bundle change khi có lợi; tách khi cognitive/technical risk cao. “Security urgent” không tạo thêm capacity.
Escalate portfolio trade-off thay vì đẩy mọi deadline xuống consumer.

## 16. Case for change

Case for change cần giải thích:

1. điều gì đang thay đổi trong business/risk;
2. current state gây pain/exposure nào;
3. vì sao bây giờ;
4. target outcome là gì;
5. stakeholder được lợi/mất gì;
6. điều gì sẽ không đổi;
7. transition/support thế nào;
8. alternative và consequence nếu không đổi;
9. decision/ask cụ thể.

Dùng evidence và story từ work context. Fear-only tạo urgency ngắn hạn nhưng có thể làm mất trust; không phóng đại threat
hoặc tuyên bố solution loại bỏ mọi risk.

## 17. Change narrative và message architecture

Giữ một narrative lõi nhưng tailor theo audience:

```text
why / why now
    → outcome and design principles
        → what changes for this audience
            → when / how / support
                → what to do now + how to give feedback
```

Lập message map cho leader, manager, technical team, end user, customer và supplier. Version thông tin, công khai known/unknown,
decision date và source of truth. Tránh mỗi workstream gửi timeline/thuật ngữ khác nhau.

## 18. Communication là hai chiều

Communication plan gồm:

- sender đáng tin cho từng audience;
- channel/cadence/timing;
- required action và deadline;
- demo/FAQ/job aid;
- feedback/listening channel;
- misinformation correction;
- accessibility/language;
- escalation và emergency update;
- measure reach/understanding/action;
- archive/version.

Không đo email sent/open như adoption. Communication chỉ thành công khi stakeholder hiểu implication, thực hiện action hoặc
nêu được blocker đủ sớm.

## 19. Resistance là dữ liệu

Resistance có thể phản ánh:

- target không giải quyết job-to-be-done;
- mất autonomy/status hoặc local control;
- migration cost không được fund;
- prior transformation thất hứa;
- secure path chậm/không reliable;
- risk/benefit không được tin;
- incentive hoặc deadline xung đột;
- legitimate safety/regulatory concern;
- change saturation;
- thiếu skill/support.

Phân biệt objection có evidence, misunderstanding, constraint và deliberate obstruction. “Quản lý resistance” không có
nghĩa ép compliance; dùng insight để sửa solution/sequence hoặc minh bạch trade-off.

## 20. Listening và feedback loop

Kết hợp:

- interview/focus group;
- usability observation;
- office hours/community;
- support ticket/search/query;
- champion/manager input;
- survey mở và pulse;
- pilot telemetry;
- incident/near miss;
- exception/workaround analysis.

Mọi feedback cần route: acknowledge, classify, owner, decision và closure. Công bố “you said / we did / we did not and why”.
Nếu feedback không bao giờ đổi backlog, channel trở thành nghi thức và trust giảm.

## 21. Manager enablement

Manager cần:

- local impact/timeline và talking points;
- decision/escalation authority;
- protected time cho migration/learning;
- readiness checklist;
- cách xử lý exception/support;
- cohort metrics không dùng để shame;
- channel giải quyết conflict;
- expectations về reinforcement sau go-live.

Manager không chỉ forward email. Họ ưu tiên work, giải thích norm và quyết định shortcut có được chấp nhận không. Đo manager
action/support, không chỉ attendance briefing.

## 22. Champions và local change agents

Champions giúp:

- dịch target vào local workflow;
- tìm early adopter/pilot;
- test documentation/pattern;
- phát hiện dependency/workaround;
- hỗ trợ peer;
- đưa feedback tới product team;
- reinforce sau rollout.

Cần charter, manager-supported time, training, artifact, escalation, recognition và succession. Không dùng champion để bù
thiếu support team hoặc ép họ accept risk ngoài authority. Đọc
[Security Culture & Human Risk](security_culture_human_risk_behavior_engineering.md) cho human-centered adoption.

## 23. Capability và learning plan

Map:

```text
future task / decision
    → knowledge + skill + authority
        → learning / practice / performance support
            → observed safe performance
```

Tách audience: operators, support, consumers, managers, assurance, incident responders. Dùng lab, shadowing, rehearsal,
scenario và just-in-time job aid; certification/completion không đủ. Training environment phải sẵn trước migration wave,
không sau cutover.

## 24. Workflow và performance support

Đưa thay đổi vào nơi work diễn ra:

- guided onboarding;
- template/golden path;
- inline validation/error có cách sửa;
- decision checklist;
- migration assistant;
- contextual documentation;
- one-click support/report;
- runbook và recovery branch;
- default/automation an toàn.

Tài liệu dài ở portal không bù workflow khó. Đo time-to-first-safe-success, rework, abandonment, support và recovery.

## 25. Align policy, incentive và performance

Nếu policy yêu cầu target mới nhưng:

- deadline vẫn thưởng bypass;
- budget chỉ cho build, không migration;
- KPI đếm output chứ không adoption;
- procurement mua solution cũ;
- exception dễ hơn secure path;
- manager không có capacity;
- audit vẫn đòi evidence format legacy;

thì transformation bị chống lại bởi system. Cập nhật policy, standard, goal, funding, role, assurance và reward cùng lúc.
Không phạt consumer vì mâu thuẫn do governance tạo ra.

## 26. Service/product adoption model

Transformation cung cấp security service như product:

- clear customer/value proposition;
- eligibility và prerequisites;
- onboarding/first success;
- reliability/SLO/support;
- integration/migration pattern;
- adoption và eligible denominator;
- roadmap/changelog/version;
- exception/deprecation;
- unit cost và consumer effort.

Adoption không chỉ là account created hoặc agent installed. Cần effective use, control coverage và legacy path không còn được
dùng. Chi tiết xem [Security Program Operating Model](security_program_operating_model_capability_management.md).

## 27. Golden path và adoption pull

Golden path tạo “pull” khi:

- giải quyết job thật nhanh hơn;
- secure-by-default;
- integration/documentation rõ;
- error actionable;
- support đáng tin;
- có extension boundary;
- evidence tự sinh;
- migration/upgrade ít đau;
- feedback được phản hồi.

Enforcement có thể vẫn cần cho minimum control, nhưng “mandate first, product later” tạo exception và shadow path. Kết hợp
enablement, default và enforcement theo readiness gate.

## 28. Pilot để học, không để biểu diễn

Pilot cần hypothesis:

```text
for cohort X, solution/change Y
will improve outcome Z within T,
given assumptions A,
without exceeding guardrails G.
```

Chọn cohort đại diện có đủ complexity, không chỉ team thân thiện/greenfield. Định nghĩa baseline, sample, support, success,
failure, stop và decision sau pilot. Pilot thành công không tự chứng minh scale; kiểm volume, diversity, dependency và operating cost.

## 29. Canary và cohort design

Canary nên đại diện failure mode cần học và giới hạn blast radius:

- business criticality;
- architecture/integration pattern;
- geography/time zone;
- identity/device/workforce type;
- data sensitivity;
- support maturity;
- reversible boundary;
- monitoring/evidence quality.

Không chọn canary chỉ vì “ít quan trọng” nếu nó không giống population còn lại. Giữ control group/comparator khi phù hợp,
và không thử variant yếu nơi có thể gây material harm.

## 30. Migration waves

Wave plan gồm:

- population/owner/volume;
- entry readiness;
- prerequisites/dependencies;
- change window/blackout;
- enablement/support capacity;
- cutover method;
- validation/soak period;
- max blast radius;
- pause/rollback trigger;
- exit evidence;
- lessons áp dụng cho wave sau.

Sequence theo risk, learning, dependency và capacity. Không dồn toàn bộ legacy khó vào “wave cuối” mà không fund specialist,
product improvement và exception retirement.

## 31. Entry và exit criteria

**Entry** minh họa:

- inventory/owner/prerequisite đủ;
- target service đạt reliability/security threshold;
- runbook/support/on-call ready;
- data backup/reconciliation/rollback tested;
- consumer informed/trained;
- exception/risk decision rõ.

**Exit** minh họa:

- effective target state verified;
- business transaction/availability normal;
- old access/session/data path revoked;
- severe finding closed/accepted;
- support handoff complete;
- legacy population/unknown reconciled.

Completion ticket không phải exit evidence.

## 32. Transition architecture

Mô hình transition state cần:

- old/new trust boundaries;
- source of truth và sync direction;
- identity/authorization mapping;
- data schema/version;
- routing/fallback;
- evidence/audit correlation;
- operational ownership;
- failure/degraded modes;
- rollback boundary;
- expiry/decommission trigger.

Coexistence thường tăng attack surface và complexity. Threat model riêng cho transition, không chỉ reuse target architecture.

## 33. Coexistence và dual-run

Dual-run có thể giảm cutover risk nhưng tạo:

- policy drift và inconsistent decision;
- duplicate identity/data;
- double operations/support cost;
- ambiguous source of truth;
- bypass qua legacy path;
- reconciliation gap;
- kéo dài tạm thời thành vĩnh viễn.

Định nghĩa authoritative system, conflict rule, monitoring, maximum duration và exit. “Fallback” tới legacy insecure path
phải có boundary, authorization và expiry chứ không mở mặc định.

## 34. Data migration và reconciliation

Data/control migration cần:

- inventory/classification/owner;
- mapping/schema/semantics/version;
- extraction/transfer integrity;
- encryption/access/temporary copy;
- deduplication và rejected records;
- count/hash/sample reconciliation;
- delta/cutover handling;
- backup/restore;
- retention/legal hold;
- source deletion và verified closure.

“Job succeeded” không chứng minh data đầy đủ hoặc quyền đúng. Reconcile business invariant và downstream consumers.

## 35. Identity và access migration

Đặc biệt kiểm:

- stable subject/resource identifiers;
- account/linking collision;
- group/role/entitlement semantics;
- effective permissions trước/sau;
- service/workload identity;
- session/token/cache lifetime;
- privileged/break-glass path;
- joiner/mover/leaver sync;
- recovery và support;
- revoke old federation/key/grant;
- orphan/unknown reconciliation.

Không bật federation mới rồi giữ local admin vô hạn. Test deny, revoke và incident response, không chỉ successful login.

## 36. Supplier và external dependency change

Transformation có thể cần:

- contract amendment/licensing;
- supplier roadmap/release window;
- API/data portability;
- subprocessor/location change;
- assurance/evidence;
- partner training/support;
- incident coordination;
- exit/transition assistance;
- fallback và concentration management.

Supplier “đã support feature” không nghĩa tenant/config/integration đã sẵn. Map shared responsibility và effective state;
không đặt critical milestone trên verbal promise không có owner/date/remedy.

## 37. Cutover plan

Runbook cutover gồm:

1. authority/go-no-go participants;
2. prerequisite/freeze/snapshot;
3. exact actions và expected outputs;
4. validation theo technical và business invariant;
5. observation/soak window;
6. communication/status channel;
7. timeout/branch/escalation;
8. rollback/forward-fix criteria;
9. evidence/decision log;
10. post-cutover reconciliation.

Rehearse trên môi trường/dataset representative. Go/no-go cần quyền dừng thực, không phải ceremony khi deadline đã cố định.

## 38. Rollback, forward-fix và kill switch

Rollback không luôn an toàn nếu schema/data/credential đã đổi. Xác định:

- reversible components và point of no return;
- immutable known-good version;
- backward/forward compatibility;
- data delta/reconciliation;
- identity/session/key state;
- security regression khi quay lại;
- max recovery time;
- authority và rehearsed steps;
- forward-fix alternative;
- kill switch scope/fail-safe behavior.

Test rollback như một product capability. `git revert` hoặc bật legacy route chưa chứng minh phục hồi end-to-end.

## 39. Exception, defer và migration tail

Với workload chưa migrate, ghi:

- owner/business reason;
- risk/affected outcome;
- blocker/root cause;
- compensating control;
- target path và prerequisite;
- expiry/review trigger;
- funding/capacity;
- evidence/monitoring;
- escalation nếu vượt tolerance.

Phân tail theo pattern để đầu tư fix chung. Không để “temporary exception” trở thành operating model; expired exception không
tự gia hạn vì migration khó.

## 40. Legacy retirement

Retirement là workstream được fund:

- stop new enrollment/write;
- migrate/reconcile remaining consumers/data;
- revoke identity/key/token/integration;
- archive/retain/delete theo obligation;
- remove route/DNS/firewall/job/agent;
- terminate license/vendor/access;
- update DR/backup/runbook/CMDB/evidence;
- validate không còn usage/unknown;
- communicate support/end-of-life;
- record residual exception.

Tắt UI không phải retire. Legacy hidden trong DR image, batch job hoặc local credential có thể quay lại sau incident.

## 41. Transition-to-run và operating model

Trước scale, xác nhận:

- service/capability owner;
- SLO/support/escalation/on-call;
- run capacity/budget/vendor contract;
- maintenance/patch/version/deprecation;
- control/evidence/assurance;
- incident/recovery;
- backlog/product roadmap;
- workforce skill/succession;
- customer responsibility;
- change governance.

Project team không “ném qua tường” sau go-live. Handoff bằng shadow/rehearsal/evidence và acceptance của run owner. Đọc
[Security Program Operating Model](security_program_operating_model_capability_management.md) để thiết kế service lifecycle.

## 42. Adoption metrics

Đo funnel với denominator:

```text
eligible → aware / contacted → ready → onboarded
    → first safe success → active effective use
        → old path removed → sustained
```

Giữ unknown, cohort, time và reason code. Các metric hữu ích:

- coverage/adoption theo eligible population;
- time-to-first-safe-success;
- migration lead time/tail age;
- drop-off/rework/support;
- legacy usage/exception;
- manager/champion readiness;
- repeated use và drift.

Agent installed hoặc account provisioned chưa chắc là effective adoption.

## 43. Outcome và benefits realization

Nối adoption với:

- control effectiveness;
- exposure/residual risk;
- incident impact/duration;
- service reliability/recovery;
- customer/business enablement;
- friction/productivity;
- total run/transition cost;
- legacy retirement/debt reduction.

Có baseline, counterfactual, benefit owner và review horizon. Nếu adoption tăng nhưng outcome không đổi, kiểm target design,
coverage quality, threat mix, lag và measurement validity—không tự tuyên bố thành công.

## 44. Change health dashboard

Không dùng một RAG tổng hợp. Giữ profile:

| Chiều | Signal |
|---|---|
| Outcome | target/risk/benefit evidence |
| Adoption | funnel, cohort, legacy tail |
| Readiness | platform, data, support, consumer |
| Delivery | milestone, dependency, capacity |
| Change | understanding, manager action, saturation, feedback |
| Technical | reliability, failure, rollback, drift |
| People | workload, skill, fatigue, trust |
| Economics | spend, forecast, run cost, unit cost |

Dashboard phải dẫn tới decision: unblock, re-sequence, improve, pause, rollback, scale hoặc stop.

## 45. Reinforcement sau go-live

Adoption có thể thoái lui nếu:

- legacy path vẫn dễ hơn;
- manager tiếp tục bypass;
- support không đáp ứng;
- documentation/tool drift;
- new joiners không được onboarding;
- KPI/reward cũ còn nguyên;
- incident làm team quay về workaround.

Reinforce bằng default/enforcement hợp lý, manager cadence, just-in-time support, community, feedback, recurring assurance và
removal of old path. Không kéo dài campaign nếu root cause là product reliability.

## 46. Institutionalization

Transformation được institutionalize khi:

- target practice vào policy/standard;
- role/decision rights vào operating model;
- service có funding/SLO/lifecycle;
- skill vào hiring/onboarding/career;
- control/evidence vào normal workflow;
- metrics vào decision cadence;
- supplier/procurement requirement được cập nhật;
- audit/assurance dùng effective state mới;
- incident lessons quay về backlog;
- legacy artifacts đã retire.

Không phụ thuộc transformation office hoặc hero cá nhân để duy trì. Institutionalization không có nghĩa đóng băng; capability
cần thích nghi theo evidence/risk.

## 47. Transformation risk register

Theo dõi risk phát sinh do chính chuyển đổi:

- split-brain/dual-control inconsistency;
- migration outage/data loss/access error;
- temporary privilege/exception kéo dài;
- change fatigue/capacity depletion;
- vendor/skill concentration;
- false sense of control từ partial rollout;
- customer/partner incompatibility;
- audit/evidence gap;
- benefit shortfall/cost overrun;
- legacy reactivation qua DR/rollback;
- incident xảy ra giữa cutover.

Mỗi risk có scenario, owner, response, indicator và trigger. Transformation không được coi mặc định là risk treatment thuần túy.

## 48. Ví dụ end-to-end: workload identity transformation

**Current:** static secrets phân tán, inventory thiếu, rotation gây outage.

| Lớp | Thiết kế chuyển đổi |
|---|---|
| Target | short-lived workload identity, trace/revoke được, static tail trong tolerance |
| Stakeholder | platform, app teams, CI/CD, DB, vendor, incident/assurance |
| Transition | dual credential có expiry; source of truth và revoke semantics rõ |
| Pilot | hai patterns representative, gồm batch/legacy dependency |
| Waves | new workloads default → cloud-native → critical → legacy tail |
| Enablement | SDK/template, migration tool, lab, office hours, support |
| Guardrail | no new static credential; exception có owner/expiry |
| Evidence | eligible/covered/unknown, auth failure, report/support, static use/revoke |
| Retirement | delete old secrets, roles, jobs, vault paths, DR copies và contract |

Scale chỉ khi reliability, recovery, consumer effort và unit cost qua threshold; không ép wave khi platform chưa sẵn.

## 49. Lộ trình triển khai 90 ngày

**Ngày 1–30 — Frame và diagnose**

- chốt outcome/current-target-transition scope;
- lập coalition, roles và decision rights;
- map stakeholders, impacts, dependencies, saturation;
- baseline adoption/legacy/risk/benefit.

**Ngày 31–60 — Design và prepare**

- thiết kế service, journey, enablement và communications;
- định nghĩa pilot/waves/entry-exit/cutover/rollback;
- chuẩn support/run/data/evidence;
- lập transformation risk register.

**Ngày 61–90 — Pilot và decide**

- chạy thin slice representative;
- đo adoption/effectiveness/friction/failure;
- sửa product/process/sequence;
- quyết scale/pivot/pause/stop và công bố wave plan.

## 50. Checklist, anti-pattern và tài liệu tham khảo

### Checklist production

- [ ] Outcome, scope, current/target/transition profile và guardrails rõ.
- [ ] Sponsor/coalition có decision rights, funding và protected capacity.
- [ ] Stakeholder impact/readiness/saturation dựa trên evidence.
- [ ] Narrative, listening và feedback có owner/closure.
- [ ] Policy, incentive, workflow, product và learning cùng hướng target.
- [ ] Pilot/cohort đại diện, có hypothesis và safe guardrail.
- [ ] Wave có entry/exit, soak, support, pause/rollback và reconciliation.
- [ ] Coexistence/dual-run/exception có owner và maximum duration.
- [ ] Legacy retirement và transition-to-run được fund từ đầu.
- [ ] Adoption nối effective outcome/benefit, không dừng ở deployment.

### Anti-pattern cần tránh

- Gọi tool deployment hoặc communication campaign là transformation.
- Chỉ vẽ target state, không threat-model transition state.
- Pilot chọn greenfield thân thiện nên không học được scale risk.
- Mọi wave chạy song song dù shared capacity/saturation vượt ngưỡng.
- Go-live không có run owner, support, funding hoặc rollback drill.
- Dual-run/exception kéo dài và legacy trở thành fallback mặc định.
- Resistance bị coi là thái độ xấu thay vì signal về solution/context.
- Báo adoption bằng license/account/agent count nhưng old path vẫn hoạt động.

### Nguồn chính thức

- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework) — risk outcomes và continuous improvement.
- [NIST SP 1301](https://csrc.nist.gov/pubs/sp/1301/final) — tạo/dùng Current và Target Organizational Profiles.
- [NIST SP 1302](https://csrc.nist.gov/pubs/sp/1302/final) — dùng CSF Tiers để hiểu và cải thiện rigor của practice.
- [NIST Human-Centered Cybersecurity](https://csrc.nist.gov/Projects/human-centered-cybersecurity/about) — adoption dựa trên people, process và technology context.
- [NIST Cybersecurity Adoption, Awareness & Training](https://csrc.nist.gov/projects/human-centered-cybersecurity/research-areas/cybersecurity-adoption) — adoption factors và security advocates.
- [NIST SP 800-50 Rev.1](https://csrc.nist.gov/pubs/sp/800/50/r1/final) — learning lifecycle và behavior change.
- [NIST SP 800-128](https://csrc.nist.gov/pubs/sp/800/128/upd1/final) — security-focused configuration/change control.
- [CISA Zero Trust Maturity Model v2](https://www.cisa.gov/topics/cybersecurity-best-practices/executive-order-improving-nations-cybersecurity) — ví dụ roadmap chuyển đổi theo pillars/cross-cutting capabilities.

### Học tiếp

1. [Insider Risk Program & Trusted Workforce Operations](insider_risk_trusted_workforce_operations.md) — prevention, detection, privacy,
   investigation, response và cross-functional governance.
2. [Security Policy, Standards & Exception Lifecycle Engineering](security_policy_standards_exception_lifecycle_engineering.md) — policy architecture,
   control objectives, enforceability, waiver, evidence và retirement.

---

*Cập nhật lần cuối: 2026-08-03.*
