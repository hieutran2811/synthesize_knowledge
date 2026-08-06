# Security Engineering Enablement & Secure Delivery Coaching

> Mục tiêu: giúp delivery teams tự thực hiện security tasks đúng trong công việc thật thông qua coaching,
> pairing, design clinics và embedded enablement có thời hạn; chuyển giao capability có thể quan sát được,
> giảm phụ thuộc chuyên gia và cải thiện đồng thời security outcome lẫn delivery flow.

---

## 1. Secure delivery coaching là gì?

Secure delivery coaching là engagement tạm thời nơi security practitioner làm **cùng** delivery team để họ:

- hiểu security objective trong local context;
- thực hành task/decision trên work thật;
- tạo artifact, test và feedback loop dùng lại;
- nhận feedback đúng lúc;
- biết boundary và khi nào cần specialist/authority;
- cuối cùng tự thực hiện an toàn mà không cần coach thường trực.

Coach thành công khi team độc lập hơn, không phải khi lịch coach kín hơn.

## 2. Coaching khác consulting, review và training

| Hình thức | Primary outcome |
|---|---|
| Training | Knowledge/skill qua nội dung và practice có thiết kế |
| Consulting | Expert đưa analysis/recommendation/output |
| Review/assurance | Đánh giá decision/control/evidence theo authority |
| Support | Khôi phục hoặc hoàn thành bounded service request |
| Coaching | Team tăng khả năng tự ra quyết định/làm task trong context thật |
| Pairing | Hai người cùng làm một task; là một coaching technique |
| Embedded engineering | Specialist tham gia team để deliver và/hoặc transfer capability |

Một engagement có thể kết hợp nhiều hình thức nhưng phải nói rõ outcome và decision rights của từng phần.

## 3. Outcome loop

```text
delivery goal + security outcome
  → observe current task / constraint / evidence
    → choose coaching mode and bounded goal
      → model / pair / practice / feedback
        → team performs with decreasing support
          → verify work product + retained capability
            → exit / reuse learning / improve system
```

Đừng bắt đầu bằng curriculum chung nếu problem là workflow, tool hoặc authority. Chẩn đoán trước intervention.

## 4. Nguyên tắc coaching

- làm trên outcome và work thật, trong safe boundary;
- hỏi để hiểu trước khi đề xuất;
- security và delivery cùng là constraints hợp lệ;
- explicit authority, confidentiality và stop condition;
- coach làm mẫu rồi giảm dần hỗ trợ;
- feedback cụ thể, gần hành động và có retry;
- biến learning lặp lại thành pattern/product/automation;
- có exit criteria từ đầu.

“Security sẽ ngồi cùng đến khi xong project” không phải capability-transfer strategy.

## 5. Engagement portfolio

| Mode | Phù hợp | Thời lượng điển hình |
|---|---|---|
| Quick consult | Bounded question, known pattern | Một phiên ngắn |
| Design clinic | Goal/constraints/options cần làm rõ | 1–3 phiên |
| Pairing | Task cụ thể cần hands-on transfer | Theo task/sprint |
| Coaching sprint | Nhiều related tasks và behavior | Vài tuần |
| Embedded coach | High-risk/novel domain, capability gap lớn | Time-boxed theo phase |
| Group coaching | Nhiều team cùng pattern/gap | Cohort cadence |
| Specialist engagement | Deep analysis hoặc accountable output | Theo service contract |

Không dùng embedded coach cho câu hỏi có sẵn standard path; không dùng quick consult cho novel critical design.

## 6. Trigger và demand signal

Engagement có thể được kích hoạt bởi:

- new/novel architecture hoặc risk-sensitive feature;
- product/platform/control rollout;
- repeated late finding hoặc exception;
- vulnerability class lặp lại;
- incident/near-miss learning;
- team chuyển technology hoặc delivery model;
- brownfield migration;
- champion/community escalation;
- assurance evidence cho thấy process không transfer;
- team chủ động muốn tăng capability.

Không tự động coi mọi finding là skill gap; có thể root cause là requirement, product, incentive hoặc capacity.

## 7. Intake và triage

Intake tối thiểu:

- delivery goal, stage và deadline;
- target system/change và risk/context;
- team roles, current capability và constraints;
- requested help và observed problem;
- existing standard/pattern/tool/evidence;
- decisions/authority cần có;
- sensitive data/access;
- expected outcome và urgency.

Triage route sang self-service, service/review, specialist, training hoặc coaching. Coaching không phải catch-all cho queue khác.

## 8. Coaching contract

Contract viết ngắn nhưng rõ:

```text
goal + scope / out-of-scope
+ target tasks / capability and work products
+ roles / authority / confidentiality
+ cadence / capacity / dependencies
+ feedback / evidence / measures
+ stop, escalation and exit criteria
```

Team owner vẫn chịu delivery; coach chịu chất lượng coaching và advice trong scope. Contract thay đổi khi context/risk materially đổi.

## 9. Roles trong engagement

| Vai trò | Trách nhiệm |
|---|---|
| Delivery owner | Outcome, priority, team capacity và acceptance |
| Practitioner/learner | Thực hiện task, phản tư và tạo work product |
| Security coach | Facilitate practice, feedback, boundary và transfer |
| Domain SME | Deep technical judgment khi vượt coach scope |
| Product/platform owner | Sửa capability/default/friction hệ thống |
| Control/risk authority | Requirement, exception hoặc risk decision |
| Manager | Protected time và reinforcement |

Một người có thể giữ nhiều vai trò nhưng conflict và authority phải visible.

## 10. Authority và accountability boundary

Coach không mặc nhiên:

- approve architecture/control;
- accept risk hoặc exception;
- certify người/team compliant;
- commit production change thay owner;
- override product/service process;
- trở thành incident commander;
- dùng coaching note làm performance appraisal.

Nếu coach đồng thời là reviewer, nói rõ khi nào chuyển “mũ”, criteria và record nào mang tính assurance.

## 11. Trust, confidentiality và psychological safety

Team cần thử, hỏi và thừa nhận uncertainty mà không sợ bị gắn nhãn yếu. Thống nhất:

- nội dung nào ở trong coaching room;
- điều gì buộc phải escalate vì incident/legal/safety;
- notes nào được giữ, ai truy cập, retention bao lâu;
- feedback cá nhân hay team/system;
- cách challenge coach và sửa advice;
- cách xử lý mistakes/near-miss công bằng.

Psychological safety không che risk; nó làm tín hiệu xuất hiện sớm hơn để xử lý đúng.

## 12. Readiness gate

Coaching khó hiệu quả nếu thiếu:

- product/delivery owner và real task;
- protected participant time;
- access/environment/data an toàn;
- stable-enough requirement và authority path;
- coach/SME capacity;
- khả năng sửa work product;
- feedback/retry window;
- baseline quan sát được.

Nếu deadline đã qua hoặc team chỉ cần sign-off, route sang remediation/review service; đừng gắn nhãn coaching để che constraint.

## 13. Goal và baseline

Goal nên là observable performance:

> Trong ba sprint, team tự threat-model material changes, chuyển threats thành testable requirements và tạo regression
> tests cho high-priority abuse cases; SME chỉ tham gia case ngoài defined boundary.

Baseline có thể gồm task success, coach prompts, rework, late findings, cycle time, exception và confidence calibrated với thực hành.
Không dùng self-rating duy nhất.

## 14. Task analysis bằng Task–Knowledge–Skill

Phân rã:

```text
delivery outcome
  → security-sensitive task / decision
    → required knowledge + observable skill
      → context / tools / authority / evidence
        → practice and feedback design
```

NICE Framework cung cấp common language Task–Knowledge–Skill; tailor theo stack và local responsibility. “Biết OWASP” không phải task.

## 15. Capability transfer ladder

```text
coach demonstrates
  → team observes and explains rationale
    → coach + team pair
      → team acts, coach prompts
        → team acts, coach observes
          → team acts independently
            → team teaches / improves system
```

Không bắt buộc mọi task đi hết ladder; risk/frequency quyết định depth. Ghi mức hỗ trợ cần thiết để thấy dependency đang giảm hay tăng.

## 16. Learning trong delivery workflow

Đưa coaching vào nơi work xảy ra:

- backlog refinement và acceptance criteria;
- architecture spike/design session;
- IDE/pull request/code review;
- pipeline/test result triage;
- release readiness;
- incident/post-incident;
- platform migration;
- retrospective và improvement backlog.

Tách thời gian practice an toàn khỏi production emergency. Just-in-time không có nghĩa interrupt mọi task bằng lời khuyên.

## 17. Observation và shadowing

Coach quan sát current flow trước khi sửa:

- ai ra quyết định và dùng input nào;
- handoff/wait/rework ở đâu;
- tool/default/incentive ảnh hưởng gì;
- expert cues nào team chưa thấy;
- workaround nào có lý do hợp lệ;
- evidence nào sinh ra hoặc mất;
- failure/recovery thực tế ra sao.

Xin consent và tránh ghi secret/personnel data. Observation không phải covert audit.

## 18. Pairing

Hai người cùng làm một task, luân phiên driver/navigator:

- driver thao tác và giải thích intent;
- navigator quan sát, hỏi, kiểm assumptions và gợi ý;
- đổi vai để tránh coach takeover;
- pause tại decision points để nêu cues/trade-off;
- kết thúc bằng recap, artifact và next independent task.

Pairing hiệu quả khi learner điều khiển đủ nhiều. Coach gõ toàn bộ code chỉ tạo nhanh output, không chứng minh transfer.

## 19. Ensemble/mob coaching

Phù hợp khi task liên quan nhiều roles hoặc cần shared mental model:

- một driver, nhiều navigators có role rõ;
- rotate driver thường xuyên;
- timebox và explicit goal;
- facilitator giữ inclusion/decision boundary;
- parking lot cho deep issue ngoài scope;
- capture decision/action/test;
- retrospective về process và learning.

Không kéo cả team vào mọi session. Chi phí đồng thời cao nên dùng cho decisions/reuse value đủ lớn.

## 20. Design clinic

Clinic không phải architecture approval. Flow:

1. owner trình bày outcome, context, constraints và uncertainty;
2. cùng vẽ system/data/trust boundaries vừa đủ;
3. xác định abuse/failure scenarios ưu tiên;
4. so options/patterns và known limits;
5. tạo decisions, requirements, experiments và escalations;
6. team cập nhật artifacts;
7. coach follow-up capability, authority review đi route riêng.

Team phải tham gia tạo reasoning, không chỉ nhận slide đáp án.

## 21. Threat-modeling facilitation

Coach dạy team:

- scope và assets/outcomes;
- actor, entry point và trust boundary;
- abuse case/failure scenario;
- assumption và attacker capability;
- prioritization theo consequence/exposure;
- treatment và testable requirement;
- trigger cập nhật living model.

Coach dùng câu hỏi/cues rồi giảm prompt. Novel critical threat route specialist; workshop không tự tạo assurance.

## 22. Secure-requirements coaching

Chuyển mơ hồ thành observable requirement:

```text
subject + action / prohibited state
+ scope / condition / threshold / timing
+ evidence / test + exception route
```

Pair với product owner, developer và tester để đưa vào backlog/acceptance criteria. Không copy toàn framework vào user stories;
chọn requirement theo scenario, standard và product context.

## 23. Secure coding và review coaching

Tập trung vào real change:

- data/identity flow và trust assumptions;
- safe API/library/pattern;
- authorization/business invariant;
- input/output/error handling;
- secret/dependency use;
- test và review cues;
- code ownership và maintenance.

Dùng small diff, explain reasoning và regression test. Coach không trở thành mandatory reviewer cho mọi pull request sau engagement.

## 24. Toolchain và pipeline coaching

Giúp team hiểu:

- tool trả signal gì và không chứng minh gì;
- scope/coverage/config/version;
- false positive/negative và unknown;
- triage/severity/ownership;
- suppression/exception rules;
- failure/degraded mode;
- evidence/provenance;
- feedback gần nơi sửa.

Mục tiêu không phải bật tất cả scanners; là tích hợp appropriate practices vào delivery flow với action semantics rõ.

## 25. Security testing coaching

Coach hỗ trợ tạo test từ scenario/invariant:

- unit test cho authorization/validation;
- boundary/integration test;
- abuse-case end-to-end test;
- property/fuzz test khi phù hợp;
- configuration/IaC policy test;
- negative test và unknown/failure behavior;
- remediation regression test;
- safe production validation theo authorization.

Tester/developer phải hiểu oracle và limitation; copied test pass không tự chứng minh control effective.

## 26. Vulnerability-remediation coaching

Không chỉ sửa instance. Cùng team:

1. reproduce và xác định impact/scope;
2. hiểu root cause và variant;
3. chọn fix có defense depth;
4. viết regression/variant tests;
5. tìm similar exposure có bounded query;
6. deploy/verify/rollback an toàn;
7. cập nhật pattern/tool/standard khi systemic;
8. xác nhận team tự xử class tương tự.

Sensitive vulnerability đi đúng disclosure/incident route; coaching room không thay response process.

## 27. Incident và recovery coaching

Sau khi incident command kiểm soát tình huống, coaching có thể:

- replay decision points và cues;
- practice evidence preservation/handoff;
- sửa runbook bằng paired execution;
- rehearse containment/recovery trên safe environment;
- tạo detection/recovery verification;
- phân biệt skill gap với system/incentive gap;
- transfer ownership cho operator.

Trong live crisis, ưu tiên response authority; không thử pedagogical experiment gây delay.

## 28. Platform và control migration coaching

Với migration, coach giúp team:

- inventory dependency/current behavior;
- hiểu target contract và shared responsibility;
- dùng adapter/template/tooling;
- dual-run/reconcile khi cần;
- test failure/recovery/rollback;
- remove/revoke old path;
- tạo local pattern/evidence;
- tự migrate unit tiếp theo.

Recurring manual coaching là product signal. Route common friction tới platform/product backlog và tạo paved-road improvement.

## 29. AI-assisted secure delivery coaching

AI có thể gợi ý câu hỏi, explain code, tạo test draft hoặc summarize session. Guardrails:

- không gửi source/secret/data vượt approved boundary;
- kiểm source/version/applicability;
- coach/team review output và test behavior;
- không dùng AI làm final risk/authority decision;
- chống fabricated API/control/citation;
- ghi khi AI materially ảnh hưởng work product;
- đánh giá bias và over-reliance;
- giữ learner reasoning, không outsource toàn task.

AI trả đáp án nhanh có thể giảm learning nếu team không giải thích và verify.

## 30. Chuẩn bị session

Trước phiên:

- xác nhận goal, stage và attendee cần thiết;
- thu minimal artifacts, không yêu cầu deck nặng;
- chọn safe environment/data;
- kiểm applicable standard/pattern/source version;
- nêu decisions nào in/out of room;
- chuẩn bị scenario/questions, không pre-solve hết;
- define work product và next practice;
- accessibility/time-zone needs.

Cancel/rescope nếu không có owner hoặc real task. Meeting không phải proof of enablement.

## 31. Coaching questions

Câu hỏi tốt làm lộ reasoning:

- Outcome nào phải được bảo vệ và ai chịu consequence?
- Trust thay đổi ở boundary nào?
- Assumption nào nếu sai sẽ đổi design?
- Failure/abuse path nào khó recover nhất?
- Evidence nào cho biết control hoạt động thật?
- Safe default/path hiện tại là gì?
- Khi tool trả unknown thì chuyện gì xảy ra?
- Team sẽ tự xử case tương tự lần sau thế nào?

Không dùng câu hỏi Socratic để giấu đáp án safety-critical; nói rõ khi cần.

## 32. Feedback có thể hành động

Feedback nên:

- gần task và dựa observable behavior;
- nêu impact/rationale, không phán xét con người;
- phân biệt requirement, recommendation và option;
- đủ cụ thể để retry;
- ưu tiên ít điểm quan trọng;
- mời learner self-assess;
- kiểm comprehension bằng teach-back/work sample;
- ghi system/product gap riêng.

“Không secure” hoặc sửa hết thay learner đều không phát triển capability.

## 33. Inclusion và accessibility

Coach tạo nhiều cách tham gia:

- think/write trước khi nói;
- diagram, text, code và demo có alternative;
- keyboard/screen-reader/caption phù hợp;
- giải acronym và không shame novice;
- chia lượt nói, tránh senior domination;
- timebox/break cho cognitive load;
- async follow-up;
- local language/time-zone context.

Capability không chỉ thuộc người nói nhanh nhất trong workshop. Quan sát ai thực sự được thực hành và quyết định.

## 34. Work products và evidence

Engagement nên để lại artifacts sống:

- updated threat model/ADR;
- testable requirements;
- code/config/tests;
- reference pattern/example;
- pipeline rule và triage semantics;
- runbook/recovery test;
- decision/escalation record;
- team-owned checklist/job aid;
- systemic product/policy backlog.

Artifact có owner/version/repository. Coaching notes không thay production evidence hoặc formal approval.

## 35. Action và improvement backlog

Phân loại actions:

- team delivery work;
- practice/capability follow-up;
- product/platform friction;
- standard/knowledge ambiguity;
- service/support gap;
- specialist/authority decision;
- systemic investment/debt.

Mỗi item có owner, outcome, priority/dependency và closure evidence. Không đẩy mọi action sang delivery team nếu central system tạo problem.

## 36. Cadence và fading support

Ví dụ:

```text
week 1: observe + demonstrate
week 2: pair on two real tasks
week 3: team leads, coach prompts
week 4: team leads, coach observes
week 6: independent sample + outcome review
week 10: retention / regression check
```

Cadence theo task frequency/risk. Fading là có chủ đích; giảm support quá sớm tạo failure, giữ quá lâu tạo dependency.

## 37. Exit criteria và time-to-independence

Exit khi:

- target tasks được team thực hiện đúng trên representative cases;
- team giải thích reasoning/limits và route unknown;
- work products được owner duy trì;
- result qua appropriate verification/review;
- support/escalation path rõ;
- capability giữ qua một chu kỳ sau;
- systemic gaps có owner;
- no hidden coach dependency.

`Time-to-independent-safe-performance` đo từ engagement start tới evidence này, không tới ngày cuối lịch.

## 38. Dependency và “learned helplessness”

Signals:

- mọi decision chờ coach;
- team hỏi lại cùng câu không thử source/tool;
- coach giữ repo/meeting/context riêng;
- work chỉ tiến khi coach tham dự;
- manager không cấp internal owner;
- coach sửa output trước khi learner thử;
- engagement auto-renew không có new goal.

Response: chuyển driver, require teach-back, giảm prompts, tạo bounded decision rights, sửa product/knowledge và chốt exit/recontract.

## 39. Capacity, queue và allocation

Coach capacity là constraint hiếm. Quản:

- demand theo mode/risk/stage;
- WIP limit và reserved urgent capacity;
- match domain/technology/coaching skill;
- preparation/follow-up/review time, không chỉ session hours;
- group vs individual leverage;
- travel/time-zone/context switch;
- utilization không tới 100%;
- failure demand từ broken products/processes.

Triage minh bạch; không để executive visibility quyết mọi ưu tiên. Long queue có thể cần product fix, patterns hoặc more specialists.

## 40. Coach capability và supervision

Coach cần:

- secure engineering depth đủ scope;
- facilitation, listening và feedback skill;
- systems thinking/root-cause diagnosis;
- learning/task design;
- delivery/product context;
- authority/confidentiality judgment;
- inclusion/accessibility;
- biết giới hạn và route SME.

Dùng observation, peer supervision, case review và continuous practice. Senior technical expert không tự động là effective coach.

## 41. Quality assurance và conflict of interest

Chất lượng coaching được bảo vệ bằng:

- approved sources/patterns nhưng cho phép contextual judgment;
- peer observation/sample review;
- learner feedback và outcome evidence;
- advice correction/recall path;
- disclosure of uncertainty/conflict;
- separation khi coach review work mình đã quyết định;
- escalation cho unsafe advice;
- minimal records và privacy controls.

Không standardize đến mức coach chỉ đọc script; standardize safety, semantics và quality loop.

## 42. Contractor và supplier knowledge transfer

Hợp đồng/engagement nên yêu cầu:

- team pairing/shadowing, không black-box delivery;
- local owner và shared repository;
- rationale/assumption/runbook/test handover;
- teach-back và independent operation rehearsal;
- access/data/IP boundaries;
- no irreplaceable proprietary workflow;
- exit criteria và transition time;
- post-exit support contract rõ.

Document handover ở ngày cuối không chứng minh capability transfer. Kiểm bằng team tự thay đổi, vận hành và recover.

## 43. Measurement hierarchy

```text
capacity / engagement
  → practice participation and work products
    → task capability / decreasing prompts
      → independent retained performance
        → delivery flow + security outcome
```

Metrics:

- time-to-first-practice và active practice share;
- task success, prompt level, teach-back;
- time-to-independent-safe-performance;
- rework/late findings/escaped defects;
- coach/escalation hours per retained capable team;
- correct adoption/recovery evidence;
- systemic fixes created from coaching signals.

## 44. Evaluation và counterfactual

Team tự chọn coaching thường có motivation cao. Để đánh giá:

- baseline trước engagement;
- representative task samples;
- staggered cohorts;
- matched teams theo maturity/stack/risk;
- interrupted trend;
- qualitative case trace;
- retention check sau coach exit.

Ghi product releases, staffing, enforcement và complexity change. Không nhận toàn bộ outcome improvement là do coaching.

## 45. Counter-metrics

Theo dõi:

- delivery delay/context switching;
- coach/learner overload;
- dependency và repeat questions;
- unreviewed advice/authority drift;
- team chỉ làm tốt khi observed;
- suppressed disagreement/psychological harm;
- inequality về access tới coaching;
- specialist queue tăng;
- product defect bị che bằng human workaround;
- assurance conflict và escaped risk.

Giảm vulnerability nhưng tăng cycle time vô hạn hoặc phụ thuộc coach vĩnh viễn không phải outcome bền vững.

## 46. Scaling patterns

Scale bằng:

- group coaching cho common task;
- coach-the-coach với supervised practice;
- champion + specialist escalation;
- reusable clinic kit/case library;
- office hours cho follow-up bounded questions;
- product/platform paved-road improvement;
- reference implementation/test templates;
- federated coaches với common quality contract.

Không scale bằng cách ghi hình một workshop rồi gọi đó là coaching. High-context feedback cần interaction và observation.

## 47. Maturity model

| Mức | Đặc trưng |
|---|---|
| 0 — Heroics | Specialist sửa hộ, không goal/exit/transfer |
| 1 — Defined pilot | Contract, bounded task, pairing và basic evidence |
| 2 — Repeatable | Triage, modes, task model, fading/exit và quality review |
| 3 — Portfolio | Capacity/WIP, cohort programs, systemic feedback routing |
| 4 — Outcome-driven | Independent retained performance và causal caution |
| 5 — Adaptive | Coaching demand giảm nhờ product/default; federated coaches và continuous learning |

Maturity cao không có nghĩa nhiều coaching hơn; có thể nghĩa ít manual help hơn vì hệ thống đã tốt lên.

## 48. Ví dụ: coaching team xây webhook thanh toán

**Context:** team thêm endpoint nhận payment-status webhook; chưa từng thiết kế replay/idempotency và signature verification.

**Goal:** team tự thiết kế, implement và test webhook có source authentication, replay protection, idempotency, safe error/logging
và recovery trong hai sprint; novel provider limitation route payment-security SME.

**Engagement:**

- observe current integration/design;
- clinic vẽ trust/data flow và abuse/failure cases;
- pair viết requirements và verification adapter;
- team driver implement signature/timestamp/idempotency;
- ensemble tạo negative/replay/concurrency tests;
- coach observe second endpoint với prompt tối thiểu;
- formal review theo route riêng;
- extract reusable library/pattern và provider gap.

**Evidence:** representative tests pass, logs không lộ payload, recovery rehearsed, team explain limits/unknown, second endpoint độc lập,
không còn coach-owned code. Counter-metrics gồm cycle time, false rejection, coach hours và operational support load.

## 49. Kế hoạch triển khai 90 ngày

### Ngày 1–30: define service và pilot

- chọn một repeat/high-consequence secure task;
- inventory current consult/review/training demand và root causes;
- define coaching modes, intake, triage, contract và authority boundary;
- map Task–Knowledge–Skill và representative work samples;
- baseline task success, rework, dependency và delivery flow;
- recruit 2–4 pilot teams, reserve coach/SME capacity.

### Ngày 31–60: coach trên work thật

- observe current workflow và confirm diagnosis;
- run clinic/pairing/practice với learner as driver;
- tạo team-owned artifacts/tests và systemic backlog;
- record prompt/support levels, not personal grading;
- fade support theo evidence;
- peer-review coaching quality và advice.

### Ngày 61–90: prove transfer và scale decision

- test independent representative task;
- follow retention sau một delivery cycle;
- verify appropriate formal review/outcome;
- inspect delay, overload, inequality và hidden dependency;
- route common gaps vào product/knowledge/policy/service;
- decide scale group coaching, train coaches, redesign hoặc stop.

## 50. Checklist, anti-pattern, nguồn và học tiếp

### Checklist production

- [ ] Engagement có observable delivery/security goal và coaching contract.
- [ ] Coaching được chọn sau diagnosis, không phải default cho mọi gap.
- [ ] Roles, authority, confidentiality, stop/escalation rõ.
- [ ] Team có protected time, real task, safe environment và ability to retry.
- [ ] Task–Knowledge–Skill, baseline và representative work sample có.
- [ ] Learner là driver; coach giảm prompt và không giữ critical ownership.
- [ ] Work products thuộc team, trace source và đi formal review đúng route.
- [ ] Exit dựa independent retained performance, không theo calendar.
- [ ] Capacity/WIP/quality supervision và specialist backup được quản.
- [ ] Metrics ghép transfer/outcome với delivery, overload, dependency và access fairness.

### Anti-pattern cần tránh

- Expert sửa hộ rồi gọi đó là coaching.
- Embedded coach ở mãi vì không có goal hoặc exit criteria.
- Coach đồng thời tự approve design mình đã quyết.
- Mọi finding bị quy thành knowledge/skill gap.
- Learner chỉ xem demo, không lái real task và retry.
- Session notes bị dùng làm employee ranking ngoài declared purpose.
- Time-to-exit nhanh hơn được tối ưu bằng cách giảm quality.
- Coach utilization 100% và queue ưu tiên theo executive visibility.
- Product/platform lỗi nhưng coaching tiếp tục dạy workaround.
- Supplier bàn giao documents nhưng local team không tự vận hành/recover.

### Nguồn chính thức

- [NIST SP 800-218 SSDF 1.1](https://csrc.nist.gov/pubs/sp/800/218/final) — outcome-based secure software
  practices/tasks cho prepare, protect, produce và respond; tailor theo risk, feasibility và context thay vì checklist máy móc.
- [NIST SSDF project](https://csrc.nist.gov/projects/ssdf) — current SSDF resources, implementation examples,
  community profiles và continual evolution của secure-development practices.
- [NIST NICE Framework](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center/getting-started) —
  Task–Knowledge–Skill language để thiết kế capability và work-sample evidence.
- [NIST SP 800-50 Rev.1](https://csrc.nist.gov/pubs/sp/800/50/r1/final) — lifecycle learning program,
  role-based needs, behavior/culture outcome và evaluation.
- [CISA Secure by Design principles](https://www.cisa.gov/sites/default/files/2023-10/SecureByDesign_508c.pdf) —
  security outcome phải được xây vào product/development lifecycle, không đẩy burden cho customer.
- [OWASP SAMM](https://owasp.org/www-project-samm/) — maturity-based governance, design,
  implementation, verification, operations, education và guidance practices.
- [GOV.UK: Agile training, learning and support](https://www.gov.uk/service-manual/the-team/agile-training-learning-and-support) —
  learning through practice, shadowing, pairing, mentoring và sharing knowledge giữa teams.
- [GOV.UK Service Standard: Multidisciplinary team](https://www.gov.uk/service-manual/service-standard/point-6-have-a-multidisciplinary-team) —
  sustainable delivery team có skills phù hợp và access tới specialist expertise trong lifecycle.

### Học tiếp

1. [Security Research, Innovation & Emerging Technology Governance](security_research_innovation_emerging_technology_governance.md) — horizon discovery,
   safe experimentation, evidence gates, transition-to-production và responsible retirement.
2. [Security Capability Academies, Mentoring & Technical Career Development](security_capability_academies_mentoring_technical_career_development.md) — capability curricula,
   apprenticeship, mentoring systems, proficiency evidence và sustainable specialist pipelines.

---

*Cập nhật lần cuối: 2026-08-03.*
