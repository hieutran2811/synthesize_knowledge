# Security Developer Relations, Champions & Community Enablement

> Mục tiêu: xây mạng lưới tin cậy hai chiều giữa security và các delivery communities để security capabilities
> được hiểu, thử, cải thiện và dùng đúng trong local context; tạo developer advocacy, champion program và
> contribution system bền vững mà không biến volunteers thành security team miễn phí hoặc risk approvers.

---

## 1. Security DevRel là gì?

Security Developer Relations (DevRel) kết nối security specialists/product/platform teams với developers, operators,
data teams và technology communities. Nó có bốn chuyển động:

- **listen:** hiểu job, constraints, language và failure của practitioners;
- **enable:** giúp họ áp dụng security capability vào work thật;
- **advocate:** đại diện nhu cầu hai chiều, không chỉ quảng bá từ trung tâm;
- **co-create:** để community đóng góp patterns, fixes, examples và product feedback.

DevRel thành công khi trust, correct adoption và local capability tăng—not khi tổ chức nhiều sự kiện.

## 2. Ranh giới với các chương trình khác

| Chương trình | Trọng tâm |
|---|---|
| Awareness/learning | Knowledge, skill, practice và behavior change |
| Knowledge management | Authoritative, findable, lifecycle-managed content/decision support |
| Product management | Problem, proposition, adoption funnel và product economics |
| Service management | Request, fulfillment, support, SLO và service outcome |
| Change management | Transition từ current sang target state theo cohorts/waves |
| DevRel/champions | Relationship network, peer influence, contribution và feedback flow |

DevRel dùng tất cả capability trên nhưng không thay chúng. Một community channel không phải support queue hoặc approval forum.

## 3. Operating loop hai chiều

```text
listen to community signals
  → synthesize jobs / friction / gaps
    → co-design message / artifact / experience
      → enable advocates and champions
        → support local application
          → observe outcome / collect feedback
            → route product / policy / service / learning changes
```

Nếu feedback không quay lại backlog/decision và có closure, chương trình chỉ là broadcast marketing.

## 4. Outcome model

Một outcome chain thực dụng:

```text
trusted relationships + access to help
  → earlier questions / higher-quality feedback
    → better local decisions and implementation
      → retained correct use / fewer repeat failures
        → security and delivery outcomes
```

Attendance, membership và messages là activity signals. Chúng chỉ có ý nghĩa khi liên kết với task, cohort và downstream outcome.

## 5. Ecosystem và audience map

Liệt kê đầy đủ:

- application developers, QA, product và delivery leads;
- platform, SRE, cloud, data/ML và operations;
- architects, security engineers, control/policy owners;
- managers và budget/capacity owners;
- contractors, suppliers và open-source maintainers;
- internal communities/guilds và regional sites;
- new joiners, experienced practitioners và informal influencers.

Không đồng nhất “developer community” với một persona. Technology, risk, geography và delivery model tạo nhu cầu khác nhau.

## 6. Jobs và moments that matter

DevRel nên xuất hiện tại các moments có decision:

- bắt đầu service/repository;
- chọn architecture, data store hoặc identity pattern;
- tích hợp security platform/control;
- review pull request/change;
- triage vulnerability;
- prepare release;
- handle incident/recovery;
- migrate hoặc deprecate technology.

Map champion/community touchpoint tới job cụ thể; đừng tạo calendar hoạt động tách khỏi delivery rhythm.

## 7. Trust và social contract

Community cần biết:

- kênh nào informal, kênh nào tạo accountable decision;
- câu hỏi/near-miss được xử lý công bằng ra sao;
- dữ liệu participation/telemetry dùng cho mục đích nào;
- response/closure expectation;
- điều gì confidential hoặc cần chuyển private channel;
- disagreement và appeal xử lý thế nào;
- central team sẽ sửa gì khi community nêu friction có evidence.

Trust đến từ hành vi nhất quán và closure, không từ khẩu hiệu “security is everyone’s responsibility”.

## 8. Program charter

Charter tối thiểu có:

- problem/outcomes và target communities;
- in-scope/out-of-scope activities;
- champion/advocate/central-team responsibilities;
- authority và prohibited decisions;
- manager time commitment;
- support/escalation model;
- contribution/review rules;
- safety, privacy và code of conduct;
- funding, measures, review và exit criteria.

Một charter chỉ nói “promote security culture” không đủ để manager cấp capacity hoặc champion biết khi nào phải dừng/escalate.

## 9. Role taxonomy

| Vai trò | Primary contribution |
|---|---|
| DevRel lead | Strategy, portfolio, network health và cross-team routing |
| Developer advocate | Listening, content/demo, community engagement và product feedback |
| DevRel engineer | Reference implementation, sample, SDK/tooling và technical enablement |
| Security champion | Local context, peer support, early signal và bounded activities |
| Ambassador/advocate | Awareness, connection và event/community reach |
| Domain SME | Deep technical judgment và escalation |
| Community facilitator | Inclusion, cadence, moderation và contributor flow |

Tên có thể khác nhưng responsibilities và authority phải rõ; đừng trao title mà không có operating contract.

## 10. Authority boundary của champion

Champion có thể:

- chỉ đường tới standard/pattern/service đúng;
- hỗ trợ peer dùng paved road;
- facilitate threat-model/checklist session nếu đã đủ năng lực;
- thu friction và recurring gaps;
- thử beta và đóng góp examples/fixes;
- escalate ambiguity sớm.

Champion không mặc nhiên được:

- chấp nhận risk hoặc approve exception;
- ký assurance cho chính team;
- xử lý incident nhạy cảm ngoài role;
- diễn giải policy mới như authority;
- thay specialist/support/control owner.

## 11. Coverage model theo risk và need

Không yêu cầu “mỗi team một champion” nếu team/technology/risk không giống nhau. Có thể dùng:

- champion theo product/domain;
- guild theo technology stack;
- regional/time-zone advocate;
- shared champion cho nhóm low-risk nhỏ;
- embedded security engineer cho high-risk area;
- specialist-only route cho rare critical decisions.

Coverage nên xét eligible teams, critical moments, support capacity và local influence—not chỉ headcount ratio.

## 12. Chọn pilot cohort

Pilot tốt có:

- một problem/adoption outcome rõ;
- 3–5 team đại diện đủ diversity nhưng scope kiểm soát được;
- manager đồng ý protected time;
- champion tự nguyện và có credibility;
- product/platform owner sẵn sàng sửa friction;
- baseline và observation window;
- specialist capacity cho escalation;
- stop/adjust/scale criteria.

Friendly teams giúp khởi động nhưng không đủ chứng minh model hoạt động với brownfield, remote hoặc high-pressure teams.

## 13. Recruitment tự nguyện và bao trùm

Recruit qua nhiều đường:

- open call mô tả rõ job/time/value;
- team nomination có consent;
- manager/community referral;
- người từng phát hiện failure hoặc cải thiện workflow;
- non-developer roles như QA, SRE, data và product;
- regional và underrepresented groups.

Không chỉ chọn người đã nổi tiếng hoặc có sẵn thời gian. Forced assignment tạo title rỗng; self-selection thuần túy có thể tạo mạng không đại diện.

## 14. Selection và fit

Đánh giá:

- credibility và empathy với local team;
- curiosity, communication và willingness to learn;
- ability to say “không biết” và escalate;
- availability được manager xác nhận;
- interest phù hợp với program outcome;
- respect for confidentiality/boundaries;
- collaboration hơn gatekeeping;
- succession potential.

Không yêu cầu champion phải là security expert ngay từ đầu. Technical depth có thể phát triển; trust và responsible judgment khó bù bằng badge.

## 15. Manager agreement và protected time

Manager–champion–program owner thống nhất:

```text
expected activities + time range + delivery trade-off
+ learning/mentoring + escalation support
+ review cadence + recognition/career evidence
```

Time phải xuất hiện trong capacity planning, không chỉ “khi rảnh”. Khi priority conflict, manager và program owner quyết định;
champion không tự gánh overtime để giữ cả hai workload.

## 16. Onboarding contract

Onboarding gồm:

- purpose, charter, authority và prohibited actions;
- top local risk scenarios/jobs;
- authoritative knowledge và service routes;
- safe communication/confidentiality;
- facilitation, listening và feedback capture;
- practice với realistic cases;
- mentor/buddy và first activity;
- manager alignment;
- check-in sau 30/60/90 ngày.

Completion deck không đủ. Quan sát champion route một case, hỗ trợ peer và escalate đúng trước khi mở rộng scope.

## 17. Capability map cho champion

Map theo task thay vì course list:

| Task | Knowledge/skill cần | Boundary |
|---|---|---|
| Hướng dẫn safe path | Product, pattern, eligibility; coaching | Không hứa support ngoài contract |
| Facilitate design discussion | Threat cues, questions, documentation | Material novelty route SME |
| Thu feedback | Interview/listening, evidence, privacy | Không ghi sensitive details vào public channel |
| Triage câu hỏi | Taxonomy, urgency, routing | Không tự xử legal/risk acceptance |
| Contribute artifact | Source/version, examples, review workflow | Peer content chưa authoritative trước approval |

NICE Task–Knowledge–Skill language có thể hỗ trợ mô tả và đánh giá capability.

## 18. Learning path và deliberate practice

Một path có thể gồm:

```text
observe → practice in safe scenario → co-facilitate
→ perform bounded task with review → independent within scope
→ mentor others / contribute patterns
```

Dùng labs, paired review, office-hour shadowing, failure cases và feedback. Không biến learning thành danh sách video bắt buộc;
đo khả năng thực hiện task và biết boundary.

## 19. Mentoring, buddy và specialist access

Mỗi champion cần:

- named central/domain contact;
- backup khi contact vắng;
- response expectation theo urgency;
- regular mentor check-in ban đầu;
- route cho sensitive/private issue;
- peer buddy hoặc small cohort;
- escalation without penalty.

Nếu hỏi expert khó hơn tự đoán, network sẽ tạo false confidence. Theo dõi unanswered/escalation latency và specialist bottleneck.

## 20. Central enablement team và capacity

Central team phải tài trợ:

- program operations/facilitation;
- technical content/pattern/demo;
- mentoring và office hours;
- product/policy/service routing;
- community safety/moderation;
- data/measurement;
- events và contribution review;
- succession và regional support.

Estimate demand theo active champions, question complexity, launches và escalation rate. Network scale làm tăng central workload trước khi self-sustaining.

## 21. Community architecture

Thiết kế các lớp:

```text
broad practitioner community
  → active champions / working groups
    → maintainers / facilitators
      → domain specialists / authorities
```

Mỗi lớp có purpose, entry/exit, privileges, expectations và handoff. Không tạo một chat channel khổng lồ chứa announcements,
support, incidents, approvals và peer conversation cùng lúc.

## 22. Channel contract

| Channel | Dùng cho | Không dùng cho |
|---|---|---|
| Announcement | Versioned release/change | Discussion dài |
| Community chat | Peer questions/discovery | Secrets, formal approval |
| Q&A/knowledge | Curated reusable answers | Novel high-risk judgment |
| Issue/backlog | Reproducible gap/contribution | Sensitive incident |
| Office hours | Exploration/coaching | Hidden approval |
| Service/incident route | Accountable outcome/urgent response | General community talk |

Pin contract, owner, expected response, retention và escalation. Chat history không tự động là knowledge base.

## 23. Synchronous và asynchronous participation

Synchronous sessions tạo rich interaction nhưng bất lợi cho time zone, accessibility và focus work. Kết hợp:

- async agenda/questions trước;
- recording/caption khi phù hợp và được consent;
- written decision/summary/action sau;
- rotating meeting times;
- asynchronous contribution/review path;
- office hours nhiều vùng;
- no-meeting way để đạt cùng outcome.

Không dùng attendance trực tiếp làm điều kiện duy nhất để có influence hoặc recognition.

## 24. Community meeting thiết kế theo outcome

Agenda có thể gồm:

1. changes/risks cần biết;
2. one practical demo/case;
3. community problem-solving;
4. product/policy feedback decisions;
5. contribution/review opportunities;
6. actions, owners và closure date.

Giảm status slides. Có facilitator, timebox, notes và explicit decision boundary. Một meeting “hay” nhưng không tạo learning,
artifact, relationship hoặc action là event debt.

## 25. Office hours và design clinics

Office hours phù hợp exploratory help; clinic phù hợp một bounded task/design. Cần:

- published scope và prerequisites;
- booking/drop-in model theo demand;
- facilitator và specialist roster;
- confidential route;
- outcome note và follow-up;
- recurring question capture;
- formal service/authority handoff;
- demand/capacity measurement.

Nếu cùng câu hỏi lặp nhiều, sửa product/knowledge/standard; đừng tự hào vì lịch luôn kín.

## 26. Labs, challenges và hack days

Hoạt động thực hành nên gắn job:

- threat-model một feature thật đã sanitize;
- sửa vulnerable sample và viết regression test;
- migrate sang secure API/pattern;
- rehearse secret leak/recovery;
- contribute guardrail, example hoặc documentation fix;
- test beta platform journey.

Giữ safe environment, clear objective, accessibility, feedback và retry. Competition/leaderboard không được shame novice hoặc khuyến khích unsafe testing.

## 27. Launch và adoption campaign

Khi ra standard/product/control mới, DevRel:

- discovery với representative practitioners;
- recruit design partners/champions;
- co-create examples/migration story;
- prepare manager/champion brief;
- demo value và failure/recovery path;
- operate listening/office hours;
- route gaps vào release backlog;
- publish “you said / decision / change”.

Campaign không thay reliable product, migration funding hoặc enforcement strategy. Champion không phải kênh ép rollout miễn phí.

## 28. Content và demo strategy

Mỗi artifact trả một audience/job:

- 5-minute quick start;
- end-to-end sample có tests;
- live demo có scripted recovery;
- decision guide và known limits;
- migration walkthrough;
- deep technical explanation;
- FAQ chỉ cho recurring bounded questions;
- manager/leader talking points.

Reuse canonical knowledge content; DevRel đóng gói theo context và thu feedback. Không fork requirement thành slide riêng mất version.

## 29. Contribution model

Cho phép community đóng góp:

- issue/reproduction;
- example/non-example;
- documentation/pattern fix;
- reusable module/test;
- talk/lab/case study;
- translation/accessibility improvement;
- product proposal;
- incident learning đã sanitize.

Publish `CONTRIBUTING`, scope, templates, review/authority, license/IP, security disclosure và expected response. “Mọi người đều có thể góp”
không có nghĩa contribution path dễ dùng.

## 30. Contributor ladder

Ví dụ:

```text
participant → contributor → champion → reviewer
→ maintainer / facilitator → program steward
```

Mỗi bậc nêu observable contribution, responsibility, privileges, support và cách tiến/lùi/rời vai trò. Ladder không nhất thiết
trùng job grade; phải có đường cho code và non-code contribution. Không dùng tenure hoặc visibility làm tiêu chí duy nhất.

## 31. Review và maintainer governance

Mọi contribution cần đúng authority:

- peer answer: community status;
- implementation sample: technical/code owner review;
- guidance: knowledge/SME review;
- normative change: policy/standard authority;
- product change: product owner;
- exception/risk decision: designated authority.

Maintainer roster, backup, review SLA, conflict handling và recusal rõ. Không để champion tự merge guidance ảnh hưởng chính team mà không independent review.

## 32. Code of conduct và community safety

Code of Conduct cần:

- expected/unacceptable behavior;
- inclusive communication;
- confidential reporting routes;
- response team/authority;
- anti-retaliation và due process;
- event/online scope;
- restorative/corrective/removal options;
- conflict-of-interest rules.

Enforcement phải có người, process và backup; một file không tự tạo safety. Moderator không điều tra security incident nếu không có role/authority.

## 33. Sensitive disclosure và safe handling

Community có thể nhận vulnerability, secret, incident hoặc personnel detail. Thiết kế:

- prominent private disclosure route;
- automatic warning trước public post;
- minimal data collection;
- rapid acknowledgement/triage;
- move/redact/delete theo record policy;
- need-to-know handoff;
- contributor protection và coordinated disclosure;
- sanitized learning sau xử lý.

Không paste exploit/customer data vào chat để “hỏi cộng đồng”. Champion phải biết dừng và chuyển kênh.

## 34. Feedback intake

Feedback record gồm:

- source/cohort/context/job;
- observed problem và evidence;
- consequence/frequency;
- workaround/alternative;
- requested solution (tách khỏi problem);
- sensitivity;
- target owner/system;
- acknowledgement và status;
- decision/closure.

Giữ anonymity khi phù hợp và consent cho quote/case. Không biến chat message thành employee performance record ngoài declared purpose.

## 35. Feedback taxonomy và routing

| Signal | Route chính |
|---|---|
| Product UX/reliability/gap | Product/platform backlog |
| Requirement mơ hồ/xung đột | Policy/standard owner |
| Hướng dẫn khó tìm/sai | Knowledge owner |
| Skill/practice gap | Learning/coaching program |
| Request/support failure | Service owner/problem management |
| Exception pattern | Control/product/risk portfolio |
| Incident/vulnerability | Private response process |
| Capacity/incentive conflict | Manager/operating model |

DevRel owns the loop, không nhất thiết owns the fix.

## 36. Close-the-loop discipline

Mỗi material signal cần:

```text
acknowledge → classify → assign → decide
→ communicate rationale → implement / decline
→ verify outcome → close / revisit
```

Publish aggregate “you said / we learned / we changed / not now and why”. Không hứa mọi request được làm; hứa evidence được
xem xét và decision minh bạch. Track aged/unowned feedback như trust debt.

## 37. Influence without authority

Influence bền vững dựa vào:

- hiểu local goals/constraints;
- credible technical evidence;
- demonstrated user và security value;
- relationships trước crisis;
- options thay vì chỉ prohibition;
- reciprocity: security cũng sửa friction của mình;
- transparent limits và uncertainty;
- follow-through.

Không thao túng bằng fear hoặc mượn executive name cho mọi đề xuất. Khi requirement bắt buộc, nói rõ authority thay vì giả vờ voluntary.

## 38. Recognition, incentives và career value

Recognition có thể gồm:

- manager-visible impact record;
- contribution badge gắn criteria thật;
- presentation/mentoring opportunity;
- learning/conference budget;
- career framework evidence;
- rotation/secondment pathway;
- public thanks nếu contributor đồng ý;
- reward cho team outcome, không chỉ hero.

Tránh gamification theo message count, findings hoặc attendance; nó tạo noise, gatekeeping và inequity. Compensation/time phải phù hợp local employment rules.

## 39. Workload, burnout và emotional labor

Champion thường nhận hidden work: câu hỏi ngắt quãng, persuasion, sensitive disclosure và conflict. Quản bằng:

- explicit time/WIP limit;
- shared roster và backup;
- office-hour boundaries;
- route support thay vì tự xử mọi thứ;
- pause/leave role không stigma;
- workload pulse và manager review;
- psychological support sau difficult case;
- central team absorption khi launch/incident tăng demand.

Network không bền nếu success dựa vào unpaid overtime.

## 40. Inclusion, accessibility và global community

Thiết kế cho:

- time zones, shifts và low-bandwidth channels;
- language/local regulatory context;
- screen reader, keyboard, caption và cognitive load;
- introverts/newcomers và nhiều contribution styles;
- contractors/partners với access khác;
- cultural power distance;
- safe challenge và anonymous feedback;
- avoid jargon, stereotypes và alcohol-centric events.

Đo representation cùng ability to influence; chỉ có tên trong roster không chứng minh inclusion.

## 41. Succession, rotation và offboarding

Mỗi role có:

- term/review cadence;
- deputy/buddy;
- artifact/relationship handover;
- access revocation;
- open actions/escalations transfer;
- recognition và alumni path;
- replacement recruitment;
- exit interview về friction/value.

Không giữ stale champion directory sau role/team change. Rotation giảm dependency nhưng không được xóa continuity cho high-context domain.

## 42. Network health

Xem mạng như graph có nodes/edges:

- coverage của eligible teams/domains;
- centrality/concentration vào vài người;
- cross-team connections;
- isolated segments;
- time-to-reach correct expert;
- bidirectional interaction;
- active/healthy vs dormant roles;
- resilience khi key person vắng.

Không công bố individual influence score để xếp hạng. Dùng aggregate network insight cho capacity, succession và inclusion.

## 43. Measurement hierarchy

```text
inputs / capacity
  → participation / contribution
    → relationship / network health
      → capability / feedback quality
        → local task / adoption outcome
          → security + delivery outcome
```

Ví dụ:

- input: protected time, mentor capacity;
- participation: active cohort và contribution diversity;
- relationship: trust pulse, expert reach time;
- capability: observed bounded task/escalation;
- adoption: retained correct use by covered cohorts;
- outcome: rework, late finding, exception/failure demand giảm.

## 44. Đánh giá champion impact

Không so đơn giản team có champion với team không có vì selection bias: team trưởng thành dễ tự nguyện hơn. Có thể dùng:

- staggered rollout;
- matched cohorts theo maturity/risk/stack;
- within-team baseline/trend;
- contribution analysis từ qualitative + quantitative evidence;
- specific intervention experiment;
- case tracing từ signal → change → outcome.

Ghi confounders như product release, enforcement và staffing. Báo uncertainty thay vì nhận toàn bộ improvement là công champion.

## 45. Counter-metrics và unintended effects

Ghép outcome với:

- champion overtime/burnout/attrition;
- specialist escalation load;
- shadow approvals và authority breaches;
- advice conflict/staleness;
- false confidence hoặc missed high-risk case;
- community safety reports;
- representation gaps;
- support work bị che khỏi service metrics;
- product defects bị chữa mãi bằng coaching;
- team delivery impact.

Một network “bận rộn” nhưng làm central team kiệt sức hoặc tạo shadow governance là thất bại.

## 46. Maturity model

| Mức | Đặc trưng |
|---|---|
| 0 — Ad hoc | Hero cá nhân, không charter/time/support |
| 1 — Pilot | Bounded cohort, role và mentor rõ |
| 2 — Repeatable | Onboarding, channels, feedback routing và basic metrics |
| 3 — Federated | Domain/community leads, contributor model, regional coverage |
| 4 — Outcome-driven | Network/correct-adoption evidence và portfolio learning |
| 5 — Adaptive | Community co-creates; product/policy/service thay đổi từ feedback; succession bền vững |

Không scale roster trước support, governance và feedback capacity. Maturity không bắt buộc tuyến tính cho mọi domain.

## 47. Federated scaling

Khi mở rộng:

- common charter, principles và authority boundaries;
- domain-specific task/capability overlays;
- regional facilitators và local adaptation;
- shared knowledge/product/service interfaces;
- contributor/maintainer ladder;
- central program operations và measurement definitions;
- cross-community council cho dependency, không approval mọi hoạt động;
- minimum safety/privacy/accessibility requirements.

Centralize semantics và support infrastructure; federate relationships, context và local experimentation.

## 48. Ví dụ: rollout workload identity qua champion network

**Problem:** static credentials tồn tại vì migration path khó và team không tin recovery.

**Pilot:** champions từ Java, data pipeline, serverless và brownfield teams; mỗi người có manager-funded time và named identity SME.

**Activities:**

- co-design migration quick start và non-examples;
- lab lấy short-lived credential, revoke static key và rehearse recovery;
- office hours route novel trust-boundary cases;
- champions hỗ trợ bounded peer migration, không approve exception;
- feedback taxonomy route SDK/product, standard, docs và support gaps;
- weekly closure note về changes.

**Measures:** eligible cohort activation, correct use/retention, migration effort, expert reach, support load, champion time,
reactivated static keys và recovery success. Scale chỉ khi representative teams đạt outcome với economics/safety bền vững.

## 49. Kế hoạch triển khai 90 ngày

### Ngày 1–30: charter và network baseline

- chọn one problem/community và define outcome;
- map ecosystem, informal influencers, channels và authority routes;
- baseline eligible coverage, trust/friction và task/adoption outcome;
- viết charter, roles, manager agreement và safety/privacy rules;
- recruit voluntary representative pilot cohort;
- reserve central specialist/facilitator capacity.

### Ngày 31–60: onboard và co-create

- task-based onboarding, practice và boundary check;
- establish mentor, office hours và channel contracts;
- co-create one demo/lab/decision aid/migration artifact;
- launch feedback record, taxonomy, owners và closure cadence;
- enable contribution/review workflow;
- observe local application, không chỉ collect attendance.

### Ngày 61–90: prove outcome và sustainability

- measure correct task/adoption outcomes theo cohort;
- inspect burnout, escalation, representation và shadow authority;
- close material feedback và publish rationale;
- establish contributor ladder, succession và maintainer backup;
- compare pilot evidence với baseline/counterfactual phù hợp;
- decide scale, redesign, pause hoặc embed into BAU.

## 50. Checklist, anti-pattern, nguồn và học tiếp

### Checklist production

- [ ] Program có problem/outcome, target communities và two-way operating loop.
- [ ] Roles, authority boundary và prohibited actions rõ.
- [ ] Champion tự nguyện, đại diện đủ và có manager-funded protected time.
- [ ] Onboarding đánh giá task/escalation, không chỉ completion.
- [ ] Central specialists, facilitator, moderation và backup có capacity.
- [ ] Channels tách peer talk, support, approval, incident và knowledge.
- [ ] Feedback có evidence, owner, decision, closure và privacy rules.
- [ ] Contribution có ladder, review authority, CoC và safe disclosure.
- [ ] Metrics nối network/capability với correct adoption/outcome và counter-metrics.
- [ ] Succession/offboarding xử lý access, actions và relationships.

### Anti-pattern cần tránh

- Gán mỗi team một champion rồi coi như đã scale security.
- Champion làm unpaid overtime hoặc bị manager ưu tiên delivery 100%.
- Dùng champion làm risk approver, free reviewer hoặc incident responder.
- Community channel trộn chat, secret disclosure, formal approval và support.
- DevRel chỉ broadcast launch; feedback không đổi backlog.
- Badge theo attendance/message count tạo gaming.
- Friendly pilot được dùng để khẳng định toàn organization sẵn sàng.
- Community answer được coi là authoritative standard.
- Event nhiều nhưng product friction, repeated questions không giảm.
- Không có succession nên network chết khi hero chuyển team.

### Nguồn chính thức

- [NIST Human-Centered Cybersecurity: Adoption, Awareness & Training](https://csrc.nist.gov/projects/human-centered-cybersecurity/research-areas/cybersecurity-adoption) —
  adoption factors, cybersecurity advocates và việc trao quyền để con người là informed security partners.
- [NIST SP 800-50 Rev.1](https://csrc.nist.gov/pubs/sp/800/50/r1/final) — lifecycle learning program,
  diverse audiences, behavior/culture outcomes và continual evaluation.
- [NIST NICE Framework](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center/getting-started) —
  common Task–Knowledge–Skill language để mô tả champion work và capability.
- [OWASP Security Champions Guide](https://owasp.org/www-project-security-champions-guidebook/) — vendor-neutral,
  adaptable program guidance và reusable charters, metrics, learning artifacts, case studies.
- [OWASP Security Champions Playbook](https://devguide.owasp.org/en/08-culture-process/02-security-champions/03-security-champions-playbook/) —
  identify teams, define role, nominate champions, channels, knowledge và sustained engagement.
- [OpenSSF Developer Relations Community](https://openssf.org/devrel/) — example mission/governance,
  open participation, community meetings, office hours và contribution channels.
- [CNCF Contributor Strategy templates](https://contribute.cncf.io/projects/best-practices/templates/) —
  contributor ladder, governance, maintainer, review, Code of Conduct và security templates.

### Học tiếp

1. [Security Engineering Enablement & Secure Delivery Coaching](security_engineering_enablement_secure_delivery_coaching.md) — embedded coaching, pairing,
   design clinics, capability transfer và measurable delivery outcomes.
2. [Security Research, Innovation & Emerging Technology Governance](security_research_innovation_emerging_technology_governance.md) — horizon discovery,
   safe experimentation, evidence gates, transition-to-production và responsible retirement.

---

*Cập nhật lần cuối: 2026-08-03.*
