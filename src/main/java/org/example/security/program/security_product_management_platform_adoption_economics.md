# Security Product Management & Platform Adoption Economics

> Mục tiêu: quản lý security controls và platform capabilities như sản phẩm có người dùng, vấn đề,
> giá trị, chiến lược, vòng đời và economics rõ ràng; biến “đã triển khai” thành “được dùng đúng,
> được duy trì và tạo security outcome với chi phí bền vững”.

---

## 1. Security product management giải quyết điều gì?

Security product management nối ba câu hỏi thường bị tách rời:

1. Người dùng đang cố hoàn thành công việc nào và gặp trở ngại gì?
2. Hành vi hoặc trạng thái bảo mật nào cần thay đổi?
3. Cách giải quyết nào tạo đủ giá trị để được dùng đúng và duy trì lâu dài?

Ví dụ, “mua secrets manager” là một output. Product outcome là các workload đủ điều kiện chuyển sang
credential ngắn hạn, deploy được nhanh hơn, không phải giữ secret tĩnh và vẫn khôi phục được khi dependency lỗi.

## 2. Product khác project, service, platform và control

| Khái niệm | Đơn vị tối ưu | Khi nào hoàn thành? |
|---|---|---|
| Project | Scope, thời gian, ngân sách | Deliverables được bàn giao |
| Service | End-to-end request/outcome vận hành | Khi service được retire an toàn |
| Platform | Capabilities dùng lại và control plane | Khi ecosystem không còn cần nó |
| Control | Risk treatment và evidence | Khi risk/control objective không còn |
| Product | Vấn đề, người dùng, giá trị và outcome | Khi problem không còn đáng giải hoặc product bị thay thế |

Một security product có thể chạy trên platform, được cung cấp qua service và chứa nhiều controls. Không nên dùng
project deadline làm bằng chứng product đã thành công.

## 3. Product lifecycle không kết thúc ở go-live

```text
discover problem
  → test problem/value assumptions
    → test solution and delivery assumptions
      → beta with bounded cohorts
        → general availability
          → improve / reposition / scale
            → deprecate / migrate / retire
```

Mỗi phase cần exit criteria riêng. Feature complete không đồng nghĩa product fit; production deployment cũng
không đồng nghĩa adoption.

## 4. Trách nhiệm của security product manager

Product manager chịu trách nhiệm về **choice quality**, không phải tự làm mọi việc:

- giữ problem, segment, outcome và product thesis rõ;
- nối user value với control/risk outcome;
- quyết định không làm gì và thứ tự học;
- quản roadmap theo outcome, dependency và uncertainty;
- thiết kế measurement, review evidence và điều chỉnh;
- làm rõ lifecycle, funding, ownership và retirement.

Risk acceptance vẫn thuộc đúng risk owner; product manager không thay thế control owner, architect hay service owner.

## 5. Product team đa chức năng

Một nhóm tối thiểu thường cần:

- product: problem, strategy, prioritization, economics;
- design/research: journey, accessibility, qualitative evidence;
- engineering/platform: feasibility, reliability, delivery;
- security/control: threats, control objective, assurance;
- data/measurement: definitions, instrumentation, evaluation;
- operations/support: production behavior và failure demand.

Mô hình “business viết requirements rồi ném sang engineering” làm mất learning loop. Cả team cùng sở hữu outcome.

## 6. Bắt đầu bằng problem framing

Problem statement hữu ích có dạng:

```text
[segment] khi [context/job] đang gặp [observable problem],
dẫn tới [user/business/security consequence].
Evidence hiện có là [signals], còn chưa biết [uncertainties].
```

“Chúng ta cần dashboard/tool mới” là solution statement. “Các deployment team mất hai ngày để xin, copy và
xoay secret nên tái sử dụng credential dài hạn” mới mô tả problem có thể kiểm chứng.

## 7. Segment theo hành vi và constraints

Không dùng “toàn công ty” như một segment. Có thể tách theo:

- risk/materiality của workload;
- architecture và delivery model;
- maturity, skills và support need;
- regulated/non-regulated environment;
- greenfield/brownfield/third-party;
- frequency và criticality của job.

Hai team có cùng job title nhưng technology constraints khác nhau có thể cần proposition và migration path khác nhau.

## 8. User, customer, sponsor và beneficiary không giống nhau

| Vai trò | Ví dụ với workload identity |
|---|---|
| User | Developer cấu hình federation |
| Customer/consumer | Application team chịu delivery outcome |
| Sponsor/buyer | Platform/security leader cấp funding |
| Beneficiary | Organization và data subjects giảm exposure |
| Risk owner | Người có authority chấp nhận residual risk |

Nếu chỉ tối ưu cho sponsor, product dễ tạo báo cáo đẹp nhưng làm user né tránh. Nếu chỉ tối ưu convenience, control
objective có thể bị loãng.

## 9. Product discovery là thu thập bằng chứng

Discovery không phải workshop tạo ý tưởng. Dùng nhiều nguồn để giảm bias:

- quan sát user hoàn thành job thật;
- phỏng vấn theo sự kiện gần nhất, không hỏi ý định chung;
- support tickets, failed changes, exception và abandonment;
- time-on-task, rework, handoff và waiting time;
- incident, exposure và control-assurance evidence;
- prototype/usability tests;
- alternative paths, scripts và shadow solutions.

Feature request là một signal về problem, không tự động là solution đúng.

## 10. Định lượng opportunity trước solution

Opportunity sizing nên nêu:

```text
eligible population × problem frequency × consequence × addressable share
```

Đừng dùng tổng headcount nếu chỉ 80 workloads đủ điều kiện. Phân biệt:

- total population;
- eligible/reachable population;
- affected population;
- realistically addressable population.

Ghi range và uncertainty thay vì một con số chính xác giả tạo.

## 11. Product thesis

Một thesis ngắn có thể là:

```text
Cho [target segment] cần [job], product sẽ [change in pathway/behavior]
để đạt [user value + security outcome], tốt hơn [current alternative]
vì [differentiator]. Ta tin điều này khi [evidence threshold].
```

Thesis là giả thuyết có thể bác bỏ. Nếu sau các cohort phù hợp vẫn không đạt evidence threshold, phải reposition,
thay solution hoặc dừng—không chỉ tăng truyền thông.

## 12. Value proposition có ba lớp

Một security product bền vững tạo giá trị đồng thời:

1. **User value:** job nhanh hơn, ít lỗi hơn, dễ khôi phục hơn.
2. **Security value:** giảm exposure, probability hoặc impact; tăng detect/recover capability.
3. **Enterprise value:** reuse, consistency, evidence, lower lifecycle cost hoặc strategic option.

Nếu user chỉ nhận thêm bước còn organization nhận toàn bộ benefit, mandate có thể cần thiết nhưng product team vẫn
phải giảm burden và cung cấp assisted path.

## 13. Product–control fit

Product–control fit tồn tại khi:

- product behavior thực sự thực hiện control objective;
- default, failure và recovery paths không phá objective;
- evidence chứng minh effective state chứ không chỉ configuration;
- exception/escape hatch được bounded;
- product changes vẫn trace được tới risk/control intent.

Một UX được yêu thích nhưng không tạo control outcome là utility, chưa phải security product thành công.

## 14. Internal product fit

Với sản phẩm nội bộ, product fit không phải chỉ “nhiều người dùng”. Cần đồng thời:

- target users hoàn thành job tốt hơn alternative;
- eligible units kích hoạt và dùng **đúng**;
- hành vi được giữ qua nhiều chu kỳ công việc;
- bypass/exception/failure demand giảm;
- reliability và support economics bền vững;
- security outcome có evidence.

Mandate có thể ép deployment và tạo adoption ảo. Voluntary pull, correct use và retention mới cho biết proposition mạnh.

## 15. Product principles và guardrails

Các nguyên tắc giúp team tự quyết nhất quán, ví dụ:

- secure outcome là mặc định, không phải add-on;
- một lần khai báo, nhiều lần tái sử dụng;
- feedback tại nơi user có thể hành động;
- bounded self-service trước manual gate;
- failure phải visible, reversible và recoverable;
- evidence sinh ra từ flow, không bắt user chụp màn hình;
- accessibility và privacy là constraints từ đầu.

Principle phải chỉ dẫn trade-off; slogan không thay thế quyết định.

## 16. Product strategy là tập hợp lựa chọn

Strategy trả lời:

- segment nào được phục vụ trước và segment nào chưa;
- problem/opportunity nào được ưu tiên;
- capability nào tự xây, mua, tích hợp hoặc ngừng;
- lợi thế nào cần tạo: default, distribution, evidence, reuse hay economics;
- constraints và risks nào không được vượt;
- sequence nào tạo learning và adoption nhanh nhất.

Danh sách tất cả initiatives không phải strategy vì nó không thể hiện lựa chọn.

## 17. Positioning, naming và findability

User tìm giải pháp theo job, không theo sơ đồ tổ chức. Tên và mô tả nên trả lời:

- “Tôi dùng khi nào?”
- “Nó thay thế cách nào?”
- “Tôi nhận giá trị đầu tiên ra sao?”
- “Ai đủ điều kiện và giới hạn là gì?”

Đừng đặt catalog entry chỉ bằng acronym nội bộ. Positioning phải trung thực về maturity, support và constraints.

## 18. Thiết kế whole journey

Product boundary không kết thúc ở portal hoặc API:

```text
recognize need → discover → evaluate → obtain access → configure
→ verify → operate → change → recover → migrate/exit
```

Một onboarding đẹp nhưng rotation, recovery hoặc exit khó vẫn là product tệ. Vẽ cả happy path, assisted path,
emergency path và failure path.

## 19. Friction budget

Security friction là tổng cognitive load, waiting, handoff, context switch và irreversible risk mà user chịu.

Áp dụng “friction budget”:

- mỗi bước thêm phải gắn với risk/control value cụ thể;
- đưa friction vào thời điểm có context và khả năng sửa;
- tự động hóa bước deterministic;
- tránh hỏi lại dữ liệu đã biết;
- đo time-on-task, rework và abandonment theo segment;
- bỏ bước không còn thay đổi decision hoặc evidence.

Zero friction không phải mục tiêu; **friction có chủ đích** mới là mục tiêu.

## 20. Secure-by-default là distribution strategy

Default ảnh hưởng adoption mạnh hơn tài liệu. Một default tốt:

- bảo vệ trước prevalent threats ngay khi bắt đầu;
- không tính phí hoặc yêu cầu setup bất hợp lý cho baseline security;
- khiến deviation khỏi safe state rõ ràng;
- tự sinh evidence và update an toàn;
- vẫn cho phép recovery có kiểm soát.

CISA nhấn mạnh product maker phải chịu trách nhiệm về customer security outcomes; vì vậy không đẩy toàn bộ hardening
burden cho từng consumer.

## 21. Paved road và escape hatch

Paved road là path dễ nhất để đạt cả delivery và security outcome. Nó cần:

- templates/reference implementation;
- composable API/automation;
- feedback nhanh, error có remediation;
- support và compatibility rõ;
- upgrade path;
- evidence mặc định.

Escape hatch dành cho constraints thật, có scope, approver, compensating treatment, expiry và return path. Một backdoor
vĩnh viễn không phải escape hatch.

## 22. Onboarding và time-to-first-value

Tối ưu **time-to-first-verified-value**, không chỉ time-to-account-created.

Ví dụ với workload identity:

- access granted: chưa có value;
- sample chạy: learning value;
- workload thật lấy credential ngắn hạn: activation candidate;
- credential cũ bị revoke và recovery được thử: verified value.

Đo riêng elapsed time, active effort, waiting time, attempts và assisted contacts để biết nên sửa product hay capacity.

## 23. Định nghĩa activation

Activation là khoảnh khắc sớm nhất user đã nhận giá trị thật và product đã tạo trạng thái có ý nghĩa.

Một định nghĩa tốt có:

- eligible unit rõ;
- event/state quan sát được;
- quality/security conditions;
- time window;
- exclusions và deduplication;
- owner hành động khi metric đổi.

Login, license assigned, agent installed hoặc scan started thường chỉ là setup event.

## 24. Correct use khác nominal adoption

Nominal adoption trả lời “có hiện diện không?”. Correct use trả lời “có tạo trạng thái mong muốn không?”.

Ví dụ:

| Nominal signal | Correct-use evidence |
|---|---|
| Repository bật scanner | Required scope được scan, result được xử đúng policy |
| MFA được enroll | Phishing-resistant method bảo vệ đúng privileged paths |
| Vault account tồn tại | Workload không giữ long-lived secret và rotation hoạt động |
| Policy được attach | Effective permissions đúng sau inheritance và exception |

Không báo adoption nếu chưa định nghĩa “đúng”.

## 25. Adoption funnel phải dùng eligible denominator

```text
eligible
  → aware
    → evaluated / started
      → activated
        → correct use
          → retained use
            → security outcome
```

Tại mỗi bước, đo conversion, elapsed time và reason codes. Denominator phải là population thực sự đủ điều kiện trong
period; nếu chỉ chia users cho toàn bộ organization, metric không hỗ trợ decision.

## 26. Cohort và segmentation analysis

Theo dõi cohort theo thời điểm bắt đầu, risk tier, technology, business unit hoặc migration path. Cohort giúp tách:

- product đã cải thiện hay chỉ thêm easy users;
- new onboarding tốt hơn legacy migration không;
- một segment bị aggregate che khuất;
- retention giảm sau release nào;
- assisted path có tạo dependency lâu dài không.

Luôn xem distribution và segment trước khi tin một average tổng; aggregate có thể đảo chiều kết luận.

## 27. Retention, churn và abandonment

Retention nghĩa là product tiếp tục được dùng đúng khi job lặp lại. Với internal security product, churn có thể là:

- đường cũ được bật lại;
- automation bị bypass;
- secret/policy thủ công xuất hiện lại;
- user chỉ dùng khi audit tới;
- team rời platform nhưng inventory không cập nhật.

Abandonment reason phải phân biệt no longer eligible, problem solved elsewhere, product failure, support wait và
deliberate exception.

## 28. Switching và migration costs

Đánh giá toàn bộ switching cost:

- sửa code, pipeline, policy và integrations;
- chuyển data, identity và evidence history;
- downtime/dual run/reconciliation;
- kỹ năng, operating model và support;
- contract/licensing;
- rollback và reversibility;
- opportunity cost của delivery team.

Một product miễn phí vẫn có thể rất đắt để adopt. Product roadmap phải tài trợ adapters, migration tooling và assisted
cohorts khi organization là bên nhận phần lớn benefit.

## 29. Adoption economics

Tách chi phí thành:

- fixed: core platform, discovery, baseline integrations;
- variable: transaction, storage, per-unit support;
- step: thêm region, support tier, compliance boundary;
- adoption: migration, training, dual run và lost delivery time;
- exit: export, replacement, evidence retention và decommission.

Một thước đo hữu ích:

```text
cost per effectively protected unit
= total attributable lifecycle cost / units retained in correct use
```

Không chia cho license hoặc deployment count vì chúng thổi phồng denominator.

## 30. Network effects và platform ecosystem

Product platform có positive effects khi mỗi adopter bổ sung integrations, patterns, evidence hoặc knowledge dùng lại.
Nhưng cũng có negative effects:

- concentration/blast radius lớn;
- noisy neighbor và queue contention;
- common-mode misconfiguration;
- compatibility surface tăng;
- governance chậm vì quá nhiều consumers.

Đo reuse và marginal value cùng systemic risk, recovery independence và exit feasibility.

## 31. Incentives, showback và chargeback

Incentive có thể là:

- safe path nhanh hơn và ít maintenance hơn;
- support/SLA tốt hơn cho standard path;
- reusable evidence giảm audit effort;
- funding migration cho high-value cohorts;
- showback minh bạch về cost và consumption.

Chargeback cho mandatory baseline control có thể khiến team che usage hoặc bypass. Nếu dùng, cần xem price signal có
thay đổi đúng hành vi hay chỉ chuyển chi phí và tạo shadow paths.

## 32. Roadmap theo outcome, không theo feature

Roadmap tốt thể hiện:

| Horizon | Câu hỏi | Ví dụ |
|---|---|---|
| Now | Uncertainty/outcome cấp bách nào? | Giảm activation failure ở Java workloads |
| Next | Opportunity nào mở khi evidence đủ? | Mở rộng brownfield cohort với migration adapter |
| Later | Option nào cần bảo tồn? | Federation cho external partners |

Features là bets có thể thay đổi. Outcome, segment, evidence threshold và dependency mới là cam kết cần quản.

## 33. Opportunity tree và hypotheses

Có thể nối decision như sau:

```text
desired outcome
  ├─ opportunity/problem A
  │    ├─ solution option A1 → assumptions → experiment
  │    └─ solution option A2 → assumptions → experiment
  └─ opportunity/problem B
       └─ solution option B1 → assumptions → experiment
```

Tách bốn loại assumption: value, usability, feasibility và viability/control. Test assumption có rủi ro cao trước
khi xây toàn bộ solution.

## 34. Prioritization dưới capacity constraint

Score chỉ hỗ trợ đối thoại, không tự quyết. Xem ít nhất:

- expected outcome/risk reduction;
- user value và eligible reach;
- strategic fit/reuse;
- urgency và cost of delay;
- confidence/evidence quality;
- effort, dependency và operational load;
- reversibility và option value;
- distributional impact.

Giữ capacity cho discovery, reliability, security debt, adoption enablement và retirement; không dùng 100% cho features.

## 35. Experiment là công cụ học

Mỗi experiment cần:

- hypothesis và decision nó sẽ thay đổi;
- target cohort và assignment logic;
- baseline/counterfactual phù hợp;
- primary metric và guardrails;
- sample/window đủ quan sát;
- stop/rollback rule;
- data-quality checks;
- pre-agreed interpretation.

Prototype, concierge flow, fake door có disclosure, usability test và limited beta đều có thể rẻ hơn production build.

## 36. Guardrails cho security experiments

Không được cố ý bỏ mandatory protection cho high-risk population chỉ để tạo control group. Thay vào đó:

- test UX, sequence hoặc enablement quanh baseline protection;
- dùng phased rollout khi timing hợp lệ;
- so với eligible non-adopters do constraints tự nhiên, kiểm soát confounding;
- dùng synthetic/sandbox cho destructive failure modes;
- giới hạn data, access và exposure;
- có kill switch, rollback và incident path.

Ethics, privacy, accessibility và risk appetite là constraints, không phải metrics để trade tùy ý.

## 37. Feature flags, canary và rings

Tách release khỏi exposure bằng flags/rings:

```text
team sandbox → internal dogfood → low-risk design partners
→ representative cohort → broader eligible population
```

Mỗi ring có entry/exit criteria, observation window và rollback. Flags phải có owner/expiry; stale flags tạo nhiều
effective configurations khó assurance. Không để cohort dễ nhất là bằng chứng duy nhất cho general availability.

## 38. Causal evaluation và counterfactual

Nếu outcome cải thiện sau launch, chưa chắc product là nguyên nhân. Có thể do threat volume, enforcement, seasonal work
hoặc population mix đổi.

Ưu tiên theo feasibility:

- randomized comparison khi an toàn/hợp lệ;
- staggered rollout;
- matched cohorts;
- interrupted time series;
- pre/post có adjustment;
- contribution analysis với nhiều evidence sources.

Document assumptions, confounders và uncertainty. Correlation vẫn hữu ích nếu không bị trình bày thành causality.

## 39. North Star cho security product

North Star nên nối user value với security outcome và eligible population. Ví dụ:

> Tỷ lệ eligible critical workloads dùng workload identity đúng, không còn credential dài hạn và đã kiểm thử
> recovery trong 90 ngày gần nhất.

Metric này tốt hơn “số integrations” vì chứa eligibility, correct use, retention window và resilience. Một North Star
không thay thế toàn bộ measurement system.

## 40. Counter-metrics và Goodhart’s law

Khi một metric thành target, người và hệ thống có thể tối ưu số thay vì outcome. Ghép primary metric với:

- bypass/exception và old-path reactivation;
- false block/false confidence;
- time-on-task và abandonment;
- support contacts/failure demand;
- reliability/recovery failure;
- privacy/accessibility harm;
- incident/exposure severity;
- cost per effectively protected unit.

Định kỳ xem raw cases và đổi metric khi behavior không còn phản ánh intent.

## 41. Product analytics và data contracts

Mỗi event/metric cần data contract:

- business meaning và unit of analysis;
- producer/source và schema/version;
- timestamp/event-time semantics;
- eligibility và identity rules;
- quality/freshness/completeness thresholds;
- retention, access, privacy purpose;
- owner và action khi invalid.

Không thu telemetry “phòng khi cần”. Data minimization và access boundaries cũng là product requirements.

## 42. Qualitative feedback và product research

Số liệu cho biết **điều gì** đang xảy ra; research giúp hiểu **vì sao**. Duy trì:

- continuous discovery với recent users/non-users;
- usability test theo realistic task;
- diary/contextual study cho job dài;
- exit/abandonment interviews;
- support shadowing;
- accessibility research;
- synthesis repository có evidence strength và recency.

Không dùng survey satisfaction làm đại diện duy nhất cho security effectiveness.

## 43. Feedback synthesis không phải feature voting

Khi nhận “hãy thêm nút X”, ghi lại:

1. Context/job nào tạo yêu cầu?
2. Người dùng đang cố đạt outcome gì?
3. Workaround hiện tại và consequence là gì?
4. Bao nhiêu eligible users gặp và mức độ ra sao?
5. Đây là pattern hay anecdote?
6. Solution options nào khác giải problem tốt hơn?

Giữ trace từ evidence → opportunity → decision. Người nói to nhất không tự động đại diện segment quan trọng nhất.

## 44. Beta, GA và maturity

| Phase | Bằng chứng tối thiểu |
|---|---|
| Discovery | Problem/segment có evidence và đáng giải |
| Alpha | Value/usability/feasibility assumptions được test |
| Private beta | Cohort giới hạn đạt activation và safe operations |
| Public beta | Representative cohorts, support và economics được hiểu |
| GA | Reliability, security, support, migration, evidence và ownership production-ready |

GA không chỉ là feature complete. Gắn maturity label với constraints, support, change policy và consumer obligation.

## 45. Version, deprecation và retirement

Product lifecycle cần:

- compatibility và semantic change policy;
- inventory consumers/dependencies;
- deprecation notice theo impact;
- migration tooling, dual-run/reconciliation khi cần;
- exception có owner/expiry;
- evidence preservation;
- revoke access, data disposition và negative proof;
- post-retirement cost/risk verification.

Sunset metric không phải email đã gửi mà là consumers đã chuyển, old path không còn usable và outcome không suy giảm.

## 46. Product operations và governance

Product Ops giảm coordination cost bằng các cơ chế nhẹ:

- quarterly product/portfolio review theo decisions;
- product brief, metric dictionary và roadmap template;
- research repository và participant governance;
- experiment registry;
- dependency/risk/decision log;
- launch/deprecation checklists;
- shared cohort và eligibility definitions;
- product council có decision rights rõ.

Governance nên tăng chất lượng và tốc độ quyết định, không biến discovery thành approval queue.

## 47. Product portfolio và platform interfaces

Portfolio review tìm overlap, gap và dependency giữa products:

- product nào cùng giải một job?
- product nào chỉ là component và không nên có UX riêng?
- identity, policy, evidence và support contracts có thống nhất không?
- adoption của product A tạo tải/risk gì cho product B?
- capability nào nên thành shared platform primitive?
- product nào không còn đủ outcome/economics để tiếp tục?

Tối ưu toàn hành trình và ecosystem, không tối ưu local adoption của từng tool.

## 48. Ví dụ: workload identity product

**Problem:** deployment teams dùng static cloud credentials vì federation setup khó, feedback chậm và recovery path
không rõ.

**Target segment đầu:** critical workloads trên managed build platform, có owner và deploy ít nhất hàng tuần.

**Thesis:** template federation + automatic trust policy + preflight validation giúp team deploy nhanh hơn alternative,
xóa long-lived credential và vẫn recover có kiểm soát.

**Measurement:**

- eligible: workloads đúng scope, không phải toàn bộ repositories;
- activation: production workload lấy credential ngắn hạn và access đúng boundary;
- correct use: không còn static credential, trust conditions không broad;
- retention: các deployment tiếp theo tiếp tục federation trong 90 ngày;
- outcome: exposure window và credential-related findings giảm;
- counter-metrics: failed deploy, emergency fallback, support effort, excessive privilege, recovery failure.

Nếu adoption thấp, xem segment/cohort và switching cost trước khi kết luận “cần training”.

## 49. Kế hoạch triển khai 90 ngày

### Ngày 1–30: problem và baseline

- chọn một product/job/segment cụ thể;
- lập user/customer/sponsor/risk-owner map;
- quan sát recent journeys và alternatives;
- định nghĩa eligible population, baseline funnel và data quality;
- viết product thesis, control objective và top assumptions;
- chọn North Star, counter-metrics và decision cadence.

### Ngày 31–60: test proposition

- prototype paved road và failure/recovery paths;
- test value, usability, feasibility, viability/control assumptions;
- ước tính switching cost và cost per effectively protected unit;
- chạy bounded design-partner cohort;
- phân tích activation/correct-use friction;
- cập nhật thesis/roadmap theo evidence.

### Ngày 61–90: prove retention và operating model

- mở representative cohort theo rings;
- kiểm tra retained correct use và outcome signal;
- thiết lập support, reliability, analytics/data contracts;
- chốt GA/maturity criteria và migration offer;
- quyết định scale, reposition, pause hoặc retire;
- đưa learning vào product/portfolio review.

## 50. Checklist, anti-pattern, nguồn và học tiếp

### Checklist production

- [ ] Product có target segment, problem evidence và product thesis kiểm chứng được.
- [ ] User value, security outcome và enterprise value đều rõ.
- [ ] Eligible population và unit of analysis được định nghĩa.
- [ ] Activation là first verified value, không phải setup event.
- [ ] Correct use, retention, outcome và counter-metrics được đo theo cohort.
- [ ] Paved road/default giảm burden; escape hatch bounded, audited và expiring.
- [ ] Roadmap theo outcome/opportunity; experiments gắn với decisions.
- [ ] Switching cost và cost per effectively protected unit được tính.
- [ ] GA có reliability, support, migration, evidence và owner.
- [ ] Version/deprecation/retirement có inventory, transition và negative proof.

### Anti-pattern cần tránh

- Gọi một tool hoặc project là product nhưng không có problem/segment owner.
- Dùng mandate, license assigned hoặc agent installed làm adoption.
- Đếm users nhưng không biết eligible denominator.
- Tối ưu activation rồi bỏ qua correct use và retention.
- Roadmap là danh sách feature request của stakeholder mạnh nhất.
- A/B test bằng cách bỏ bảo vệ bắt buộc khỏi population rủi ro cao.
- Tăng training để chữa UX, reliability hoặc switching-cost problem.
- Chargeback baseline control làm team tạo shadow path.
- Scale từ friendly cohort mà chưa thử representative users.
- Không có exit path vì product được gọi là “strategic”.

### Nguồn chính thức

- [CISA: Shifting the Balance of Cybersecurity Risk](https://www.cisa.gov/sites/default/files/2023-10/SecureByDesign_508c.pdf) —
  take ownership of customer security outcomes, secure-by-default, transparency và product leadership.
- [NIST SP 800-55 Vol.1](https://csrc.nist.gov/pubs/sp/800/55/v1/final) — phát triển, ưu tiên và đánh giá
  information-security measures thay vì chỉ đếm outputs.
- [NIST SP 800-55 Vol.2](https://csrc.nist.gov/pubs/sp/800/55/v2/final) — tổ chức measurement program có scope,
  roles, workflow và data governance.
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework) — dùng outcome language để nối product
  decisions với cybersecurity risk management và continual improvement.
- [GOV.UK: Measuring the success of your service](https://www.gov.uk/service-manual/measuring-success/measuring-the-success-of-your-service) —
  kết hợp performance metrics, user research, task completion và end-to-end journey.
- [GOV.UK: Iterate and improve frequently](https://www.gov.uk/service-manual/service-standard/point-8-iterate-and-improve-frequently) —
  học với real users và cải tiến xuyên suốt lifecycle.

### Học tiếp

1. [Security Knowledge Management, Standards Enablement & Decision Support](security_knowledge_management_standards_enablement_decision_support.md) — authoritative knowledge,
   findability, content lifecycle, decision aids, expert routing và reuse.
2. [Security Developer Relations, Champions & Community Enablement](security_developer_relations_champions_community_enablement.md) — community adoption, advocates,
   feedback networks, enablement programs và influence without authority.

---

*Cập nhật lần cuối: 2026-08-03.*
