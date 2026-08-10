---
title: "Security Program Operating Model & Capability Management"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-03
last_verified: null
version_scope: "unspecified"
source_count: 8
---
# Security Program Operating Model & Capability Management

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu: thiết kế cách chương trình bảo mật tạo ra kết quả có thể lặp lại, có owner,
> đủ năng lực và bền vững — thay vì chỉ vẽ sơ đồ tổ chức, mua công cụ hoặc đếm headcount.

---

## 1. Operating model trả lời câu hỏi nào?

**Security operating model** mô tả cách chiến lược và risk appetite được biến thành công việc hằng ngày:

```text
business objectives + risk reality
    → capabilities cần có
        → services / controls / decision rights
            → people + process + technology + data + partners
                → outcomes + evidence + learning
```

Nó trả lời sáu câu hỏi thực dụng:

1. Kết quả bảo mật nào cần tạo ra và cho ai?
2. Ai chịu trách nhiệm về outcome, control, service và business risk?
3. Quyết định nào được đưa ra ở đâu, dựa trên evidence nào?
4. Nhu cầu đi vào hệ thống bằng cách nào và được ưu tiên ra sao?
5. Năng lực, ngân sách và đối tác nào cung cấp dịch vụ?
6. Làm sao biết mô hình còn hiệu quả và khi nào cần thay đổi?

Operating model tốt làm giảm sự phụ thuộc vào “người biết đường”, giảm hàng đợi mơ hồ và giúp security trở thành
một hệ thống tạo giá trị có thể dự đoán.

## 2. Operating model không phải là gì?

Không nên đồng nhất operating model với:

- **sơ đồ tổ chức**: cho biết reporting line nhưng không cho biết service, flow và decision rights;
- **danh sách headcount**: có người không đồng nghĩa có capability hoạt động ổn định;
- **danh sách công cụ**: license không chứng minh adoption, coverage hoặc control effectiveness;
- **một framework**: framework cung cấp ngôn ngữ tham chiếu, không tự thiết kế cách doanh nghiệp vận hành;
- **RACI khổng lồ**: bảng vai trò không thay thế quy trình ra quyết định và cơ chế escalation;
- **danh sách project**: project có ngày kết thúc, capability cần được vận hành và cải tiến liên tục.

Một câu kiểm tra đơn giản: nếu thay tên phòng ban và vendor mà mô tả không còn dùng được, tài liệu có thể đang mô tả
organization chart chứ chưa mô tả operating model.

## 3. Bắt đầu từ mission, strategy và risk

Capability chỉ có ý nghĩa khi nối với business outcome hoặc risk response cụ thể. Không bắt đầu bằng câu hỏi
“security team nên có những team nào?”, mà bắt đầu bằng:

| Đầu vào | Câu hỏi |
|---|---|
| Business objective | Điều gì phải thành công, ở đâu và trong horizon nào? |
| Critical service | Sự gián đoạn/mất tin cậy nào gây thiệt hại lớn? |
| Risk scenario | Threat event, vulnerability, impact và uncertainty là gì? |
| Risk response | Avoid, mitigate, transfer hay accept? |
| Obligation | Luật, hợp đồng, policy và customer promise yêu cầu gì? |
| Change portfolio | Cloud, AI, M&A hoặc product expansion làm nhu cầu đổi thế nào? |

Đọc cùng [Security Governance & Risk Engineering](../governance/security_governance_risk_engineering.md)
để tránh biến operating model thành một bài tối ưu nội bộ tách rời enterprise risk.

## 4. Bảy chiều thiết kế operating model

Một mô hình hoàn chỉnh thường phải thiết kế đồng thời:

1. **Capabilities** — tổ chức phải có khả năng tạo outcome nào.
2. **Structure** — năng lực được đặt ở central, platform, domain hay partner nào.
3. **Governance** — decision rights, accountability, risk escalation và assurance.
4. **Service delivery** — catalog, intake, flow, SLO, support và lifecycle.
5. **People** — work, skills, capacity, career, succession và sustainability.
6. **Technology/data** — platform, automation, evidence, system of record và integration.
7. **Economics/sourcing** — funding, cost model, portfolio và build/buy/partner.

Thay đổi một chiều thường kéo theo chiều khác. Ví dụ đưa scanning về self-service nhưng không đổi ownership,
support và evidence flow sẽ chỉ chuyển thao tác sang product team chứ chưa cải thiện outcome.

## 5. Capability khác function, team, process và tool

**Capability** là khả năng đạt một outcome nhất quán trong các điều kiện xác định.

Ví dụ “quản lý danh tính máy” là capability. Nó có thể được hiện thực bằng:

- một platform team vận hành workload identity;
- policy và standard về credential;
- issuance/rotation/revocation process;
- KMS, CA, identity provider và inventory;
- product teams tích hợp golden path;
- assurance kiểm tra effective state.

Team, process và tool là **cách triển khai** capability, không phải capability. Tách hai khái niệm giúp doanh nghiệp
thay vendor hoặc cấu trúc tổ chức mà vẫn giữ được outcome và accountability.

## 6. Xây capability map

Capability map là bản đồ ổn định, technology-neutral, dùng để nhìn toàn chương trình. Có thể phân ba cấp:

```text
L1: Protect digital business
└── L2: Identity security
    ├── L3: Workforce identity lifecycle
    ├── L3: Privileged access
    ├── L3: Workload identity
    └── L3: Authorization governance
```

Mỗi capability nên có:

- outcome và customer/beneficiary;
- phạm vi, boundary và dependencies;
- capability owner;
- current/target profile;
- services và controls hiện thực nó;
- measures, evidence và known gaps;
- people/technology/partner dependencies.

Không phân rã đến mức capability map trở thành danh mục task hoặc catalog sản phẩm.

## 7. Capability owner chịu trách nhiệm điều gì?

Capability owner chịu trách nhiệm về sức khỏe **end-to-end**, kể cả khi delivery phân tán. Owner cần:

- duy trì outcome, scope và target state;
- hiểu demand, coverage, dependencies và failure modes;
- phối hợp service/control owners;
- ưu tiên roadmap, debt và investment;
- theo dõi effectiveness, resilience, cost và adoption;
- xử lý gap xuyên team và escalation;
- báo rõ uncertainty và residual risk.

Capability owner không nhất thiết là line manager hoặc người vận hành mọi control. Một người chỉ “own” trên slide
nhưng không có decision rights, budget influence và access tới evidence thì chưa thật sự accountable.

## 8. Current Profile và Target Profile

[NIST CSF 2.0 Organizational Profiles](https://csrc.nist.gov/pubs/sp/1301/final) mô tả current/target posture
theo các outcome của CSF. Tư duy này hữu ích để quản lý capability:

1. ghi trạng thái hiện tại bằng evidence và coverage thực;
2. xác định target dựa trên mission, stakeholder, threat và obligation;
3. mô tả gap, dependency và risk consequence;
4. chọn sequence chuyển đổi khả thi;
5. định kỳ cập nhật khi business/risk thay đổi.

Target không nên là “mọi capability đạt mức tối đa”. Khả năng recovery của dịch vụ thanh toán có thể cần target cao
hơn một môi trường thử nghiệm có thể tái tạo; ưu tiên phải phản ánh protection need và risk appetite.

## 9. Dùng maturity model đúng cách

Maturity giúp mô tả đặc tính phát triển, ví dụ:

| Mức | Mô tả minh họa |
|---|---|
| 1 — Ad hoc | Outcome phụ thuộc cá nhân, scope/evidence chưa rõ |
| 2 — Repeatable | Có cách làm lặp lại trong một phần scope |
| 3 — Defined | Service, owner, standard và evidence được định nghĩa |
| 4 — Managed | Coverage, flow, effectiveness và capacity được quản lý |
| 5 — Adaptive | Feedback thay đổi control/service trước biến động risk |

Đây là **ordinal scale**: mức 4 không “gấp đôi” mức 2, không nên cộng hoặc average tùy ý. Maturity cao cũng không
tự đồng nghĩa risk thấp; một capability rất trưởng thành nhưng sai scope vẫn có thể bỏ trống critical asset.

## 10. Operating principles

Trước khi chọn cấu trúc, thống nhất các nguyên tắc thiết kế:

- outcome và risk trước activity;
- enterprise consistency ở nơi cần control chung, domain context ở nơi cần quyết định gần sản phẩm;
- paved road là lựa chọn dễ nhất, exception là explicit;
- một decision có một accountable owner;
- self-service đi kèm guardrail, support và evidence;
- standardize interfaces trước khi centralize mọi người;
- bảo vệ surge capacity cho incident và change;
- build capability có lifecycle, không chỉ giao project;
- evidence được tạo trong flow, không gom thủ công cuối kỳ;
- feedback từ incident, customer và metrics phải thay đổi backlog.

Principle chỉ có giá trị khi được dùng để giải quyết trade-off cụ thể.

## 11. Mô hình centralized

Trong mô hình centralized, phần lớn chuyên môn và delivery nằm trong một security organization.

**Phù hợp khi:** quy mô nhỏ, kỹ năng hiếm, yêu cầu consistency cao hoặc capability mới cần tập trung học nhanh.

**Ưu điểm:**

- chuyên môn và tooling dễ gom;
- policy, evidence và practice nhất quán;
- dễ nhìn tổng thể risk và concentration.

**Rủi ro:**

- queue dài, xa context sản phẩm;
- security trở thành gate và single point of failure;
- product teams coi security là việc “đã outsource”.

Centralize capability không bắt buộc centralize mọi thao tác; platform tự phục vụ vẫn có thể do central team cung cấp.

## 12. Mô hình decentralized

Trong mô hình decentralized, domain hoặc business unit có security resources, budget và delivery riêng.

**Phù hợp khi:** domain khác biệt mạnh, tốc độ/context địa phương quan trọng, business unit đủ quy mô để tự duy trì.

**Ưu điểm:** quyết định gần customer và engineering, phản hồi nhanh, accountability gắn với business.

**Rủi ro:**

- trùng công cụ và chi phí;
- control/evidence không nhất quán;
- khó điều chuyển specialist và ứng phó sự kiện xuyên domain;
- local optimization che enterprise concentration risk.

Decentralized không có nghĩa mỗi team tự đặt policy. Enterprise outcome, minimum control, interfaces và escalation
vẫn cần thống nhất.

## 13. Mô hình federated / hub-and-spoke

Federated model kết hợp một **hub** giữ enterprise capabilities với **spokes** gần domain:

| Hub thường giữ | Spoke thường giữ |
|---|---|
| Strategy, policy, risk aggregation | Product/domain context |
| Shared platform và specialist | Local adoption và prioritization |
| Enterprise incident coordination | First response và remediation |
| Common evidence/assurance | Ownership effective state |
| Standards, patterns, workforce practice | Feedback và domain exceptions |

Mô hình này chỉ hoạt động khi interface rõ: hub cung cấp service gì, spoke phải làm gì, ai quyết định conflict,
funding đi theo đâu và khi nào escalation. “Federated” không nên là cách nói lịch sự cho accountability mơ hồ.

## 14. Product, platform và domain model

Security capability có thể được delivery qua ba lớp:

- **security product**: service có customer, roadmap, adoption, support và lifecycle;
- **security platform**: reusable control primitives/golden paths phục vụ nhiều team;
- **domain security**: tích hợp capability vào context, workflow và risk của domain.

Ví dụ workload identity platform cấp identity ngắn hạn; security product quản lý onboarding, policy, support và
evidence; domain team thay static secret trong workload của mình. Không lớp nào một mình tạo đủ outcome.

Đọc thêm [Platform Engineering Security](../platform/platform_engineering_security.md) để thiết kế paved road,
self-service và fleet governance.

## 15. Lines model và accountability

Một cách phân vai thường gặp:

- **business/product/technology owners** quản lý risk và vận hành controls trong phạm vi của họ;
- **risk/security oversight** đặt framework, challenge, aggregate và theo dõi;
- **independent assurance/audit** đánh giá độc lập thiết kế và hoạt động.

Tên “line” có thể khác theo tổ chức. Điều cốt lõi là tránh hai lỗi:

1. security bị gán “own mọi security risk”, làm business owner mất accountability;
2. cùng một người vừa thiết kế/vận hành control vừa tự cấp assurance độc lập cho chính mình.

Control owner, service owner, risk owner và assurance provider là các vai trò khác nhau dù đôi lúc một người kiêm nhiệm.

## 16. Decision rights: vượt qua RACI

RACI hữu ích để hình dung tham gia, nhưng thường không nói rõ **ai quyết định**. Với mỗi decision class, ghi:

| Decision | Người quyết định | Input bắt buộc | Guardrail | Escalation |
|---|---|---|---|---|
| Chọn enterprise identity standard | Capability owner | Risk, architecture, domain impact | Policy/target state | Security steering |
| Chấp nhận residual risk | Business risk owner | Scenario, options, evidence | Appetite/delegation | Executive risk forum |
| Ưu tiên onboarding | Service/product owner | Criticality, readiness, capacity | Portfolio policy | Capability owner |
| Dùng exception tạm thời | Delegated approver | Compensating control, expiry | Exception standard | Risk owner |

Decision log cần lưu context, options, owner, ngày, expiry/revisit trigger và evidence — không chỉ trạng thái approved.

## 17. Security service catalog

Capability map nói **tổ chức có thể làm gì**; service catalog nói **người dùng nhận được gì và bằng cách nào**.

Một catalog entry tối thiểu gồm:

- service name, purpose và outcome;
- customer/eligibility và use cases;
- request channel, prerequisites, inputs và outputs;
- service owner, support và escalation;
- service tier, SLO và availability window;
- customer responsibilities;
- control/evidence được tạo;
- dependencies, limits và known failure modes;
- cost/funding, version, roadmap và retirement path.

Catalog không phải menu marketing. Nó là hợp đồng vận hành giúp hai phía dự đoán flow và trách nhiệm.

## 18. Service contract và shared responsibility

Mỗi service cần làm rõ “provider làm gì” và “consumer vẫn phải làm gì”. Ví dụ secret rotation service:

```text
Provider: issue + store + rotate + revoke + audit trail
Consumer: classify use case + integrate supported client + handle reload/failure
Platform: reliable API + policy enforcement + telemetry
Risk owner: approve unsupported legacy exception + fund migration
```

Nếu chỉ ghi “security owns secrets”, scope sẽ rơi vào khoảng trống: application có reload được không, local copy có
bị tạo không, failure có làm outage không? Shared responsibility phải gắn từng failure mode với owner và evidence.

## 19. Service tier và delivery mode

Không phải mọi customer cần cùng depth. Có thể thiết kế:

- **self-service**: pattern chuẩn, automated guardrail, documentation và support;
- **assisted**: consultation ngắn cho biến thể có giới hạn;
- **managed**: provider vận hành phần lớn lifecycle;
- **expert review**: high-risk/novel case cần specialist;
- **emergency**: incident hoặc critical deadline với cơ chế override có kiểm soát.

Tier phải dựa trên risk, complexity, criticality và consumer readiness. “VIP fast lane” không có policy sẽ phá fairness,
che capacity problem và khiến demand bình thường luôn bị gián đoạn.

## 20. Demand intake và triage

Một front door tốt thu đủ thông tin để route mà không biến thành questionnaire dài:

1. customer, desired outcome và deadline driver;
2. asset/service criticality và data sensitivity;
3. change type, novelty và blast radius;
4. pattern/service đã thử;
5. dependency, blocker và evidence sẵn có;
6. incident/regulatory/customer commitment nếu có.

Triage cần trả về một state rõ: self-service, accepted, need-info, rerouted, scheduled, expedited hoặc declined cùng lý do.
Theo dõi request bị loop/reroute vì đó là dấu hiệu catalog hoặc ownership kém.

## 21. Forecast demand thay vì chỉ đếm ticket

Demand có nhiều nguồn:

- roadmap sản phẩm, cloud migration, M&A và market expansion;
- obligation mới và audit cycle;
- threat/risk landscape thay đổi;
- control debt và end-of-life;
- incident, exception và remediation;
- adoption tăng do paved road thành công.

Kết hợp historical arrival rate với leading signals từ portfolio. Đếm ticket không đủ vì một review pattern-conformant
và một legacy migration có effort khác nhau. Dùng work type, size band, urgency, skill class và expected arrival window.

## 22. Capacity model

Capacity khả dụng không bằng headcount × giờ làm việc. Một mô hình thực dụng:

```text
effective capacity
= available time
- leave / learning / coordination / operational overhead
- planned resilience reserve
- known support and maintenance load
```

Phân capacity theo work class: run/operate, support, planned change, control debt, improvement và unplanned response.
Đồng thời map skill constraints: năm generalist không thay thế được một specialist PKI trong một quyết định chuyên sâu.

Giữ assumptions và confidence range; capacity forecast là công cụ ra quyết định, không phải lời hứa chính xác tuyệt đối.

## 23. Queue, WIP và utilization

Khi utilization tiến gần 100%, biến động demand và service time làm wait time tăng mạnh. Security cần **surge capacity**
cho incident, zero-day, regulator request và business change.

Theo dõi ít nhất:

- arrival rate và completion rate theo work class;
- work in progress (WIP);
- queue age và percentile lead time;
- blocked/rework/reroute rate;
- expedite share và lý do;
- skill bottleneck;
- planned/unplanned mix.

Giới hạn WIP, hoàn thành work đang mở và làm rõ expedite policy thường hiệu quả hơn khởi động thêm nhiều initiative.

## 24. SLO cho security service

SLO mô tả mức dịch vụ mà consumer có thể dựa vào, ví dụ:

- 90% standard architecture intake được triage trong hai ngày làm việc;
- high-severity identity revocation hoàn tất trong 15 phút khi prerequisite hợp lệ;
- signing service đáp ứng availability target trong supported region;
- exception decision có response time theo risk tier.

SLO cần có population, clock start/stop, exclusions, dependency và error handling. Không chỉ đo response nhanh; quyết định
nhanh nhưng sai hoặc request bị đóng rồi mở lại không phải service tốt. Khi SLO liên tục không đạt, phải đổi demand,
capacity, scope hoặc service design — không ép team làm overtime vô hạn.

## 25. Product management cho security service

Quản lý service như product yêu cầu:

- customer/problem discovery;
- product vision và measurable outcomes;
- roadmap gồm adoption, reliability, usability, debt và retirement;
- backlog dựa trên risk/value/evidence;
- release/change communication;
- feedback loop và support model;
- lifecycle từ pilot → general availability → deprecation → retirement.

Product manager không thay capability owner: product tối ưu một service; capability owner nhìn toàn outcome và những
service/control khác. Có thể một người giữ cả hai vai trong tổ chức nhỏ, nhưng decision scope vẫn cần tách rõ.

## 26. Customer discovery và developer experience

Control không được dùng đúng thì design tốt vẫn không tạo outcome. Nghiên cứu:

- user đang cố hoàn thành job nào;
- step nào gây cognitive load hoặc chờ đợi;
- prerequisite/documentation có tìm thấy không;
- lỗi có actionable và safe-by-default không;
- migration cost và local incentive là gì;
- unsupported use case nào lặp lại.

Đo time-to-first-success, drop-off, support burden, adoption theo eligible population và override. Không tối ưu “developer
happiness” bằng cách bỏ control; mục tiêu là làm cách an toàn trở thành cách nhanh, rõ và đáng tin cậy nhất.

## 27. Golden path, guardrail và exception

Golden path đóng gói standard, pattern, automation và evidence cho use case phổ biến. Nó cần:

- supported assumptions và known limits;
- version, owner và upgrade path;
- default an toàn nhưng cấu hình được trong boundary;
- conformance check và feedback rõ;
- break-glass/exception có expiry;
- support và deprecation policy.

Guardrail giữ outcome tối thiểu; exception xử lý trường hợp không thể theo path trong thời gian xác định. Nếu exception
lặp lại cùng lý do, product backlog phải xem đó là tín hiệu thiếu capability chứ không coi là lỗi riêng của consumer.

## 28. Embedded security và champion network

Embedded practitioner/champion mang context và tăng adoption, nhưng không nên trở thành “đội security miễn phí”.
Chương trình champion cần:

- charter và scope công việc rõ;
- manager đồng ý cấp thời gian;
- training, office hours và escalation path;
- reusable playbook/tooling;
- quyền hạn phù hợp, không ép nhận risk ngoài delegation;
- recognition và career value;
- succession khi người tham gia chuyển vai trò;
- measures về outcome/adoption, không chỉ attendance.

Champion kết nối domain với central capability; họ không thay specialist, control owner hoặc accountable risk owner.

## 29. Community of Practice

Community of Practice (CoP) giúp người làm cùng một loại công việc chia sẻ pattern và học tập xuyên reporting line.
Một CoP hiệu quả tạo artifact:

- reference patterns và decision records;
- incident lessons và failure catalog;
- skill sessions/labs;
- common terminology;
- proposals cải thiện platform/policy;
- peer review cho case mới.

CoP không nên chỉ là cuộc họp cập nhật. Có facilitator, backlog, artifact owner và cadence; decision chính thức vẫn đi
qua authority đã định, tránh biến consensus không rõ thành policy.

## 30. Workforce planning theo work, knowledge và skills

[NICE Framework](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center) cung cấp ngôn ngữ
chung để mô tả cybersecurity work cùng knowledge và skills cần thiết. Áp dụng theo chuỗi:

```text
capability outcome
    → work / task cần thực hiện
        → knowledge + skills + responsibility level
            → roles / teams / partners / learning plan
```

Không lập workforce plan chỉ từ job title vì cùng “security engineer” có thể làm work rất khác. Cũng không copy mọi
work role vào org chart; tailor theo scope, technology, risk và delivery model của tổ chức.

## 31. Headcount và workforce demand

Headcount plan phải bắt đầu từ work volume, service level, skill mix và coverage window:

| Driver | Ảnh hưởng |
|---|---|
| Demand volume/variability | baseline và reserve capacity |
| Automation/self-service | giảm thao tác, tăng platform engineering/support |
| Geographic/24×7 coverage | shift, handoff và on-call |
| Critical dependency | redundancy/succession |
| Specialist depth | hire, develop hay partner |
| Growth/change portfolio | temporary vs enduring capacity |

Tránh benchmark “security staff bằng X% IT” như quy tắc cứng. Hai doanh nghiệp cùng quy mô nhưng exposure, automation,
sourcing và obligation khác nhau sẽ cần workforce khác nhau.

## 32. Competency và career architecture

Một capability bền vững cần skill taxonomy và career path:

- proficiency observable qua loại decision/work, không chỉ số năm kinh nghiệm;
- dual track cho individual contributor và manager;
- learning plan nối target capability gaps;
- labs, shadowing, rotation và supervised practice;
- assessment bằng work sample/evidence;
- mentorship và community;
- promotion criteria tránh thưởng heroics/overtime;
- skill adjacencies để reskill nội bộ.

Certification là một signal, không chứng minh người đó thực hiện được task trong context sản xuất. Kết hợp kiến thức,
thực hành, judgment, communication và mức trách nhiệm.

## 33. On-call, fatigue và key-person risk

Capability có thể “xanh” trên dashboard nhưng mong manh nếu chỉ một người biết vận hành. Kiểm tra:

- bus factor và named backup;
- on-call load, page quality và recovery time;
- overtime, interrupted leave và burnout signal;
- runbook freshness và rehearsal;
- privileged access/break-glass;
- cross-training và succession;
- handoff giữa timezone/provider;
- dependency vào contractor sắp hết hợp đồng.

Reliability của con người là phần của capability health. Không dùng tinh thần trách nhiệm cá nhân để bù vô thời hạn cho
service design, staffing hoặc automation yếu.

## 34. Build, buy hay partner

Đánh giá sourcing theo outcome và lifecycle:

| Tiêu chí | Câu hỏi |
|---|---|
| Strategic differentiation | Capability này có tạo lợi thế hoặc cần context riêng không? |
| Control/accountability | Quyết định và risk nào không thể giao ngoài? |
| Skill/scarcity | Nội bộ có thể thu hút và giữ năng lực không? |
| Time-to-value | Mua/partner nhanh hơn bao nhiêu sau integration? |
| Total cost | License, integration, operations, assurance và exit? |
| Resilience | Concentration, lock-in và failure dependency? |
| Evidence | Có quan sát effective state và kiểm chứng service không? |

“Buy” vẫn cần product owner, integration, configuration, assurance, support và exit capability nội bộ.

## 35. Managed service không chuyển giao accountability

Khi dùng MSSP hoặc managed security service, hợp đồng cần nối với operating model:

- shared responsibility theo từng workflow/failure mode;
- authority cho containment/change;
- data ownership, access, retention và portability;
- severity, notification, escalation và crisis coordination;
- quality/effectiveness measure, không chỉ ticket volume;
- evidence/audit right;
- subcontractor và concentration risk;
- transition assistance, revoke access và verified deletion;
- tabletop/exercise với cả hai bên.

Vendor thực hiện task; enterprise vẫn chịu trách nhiệm với customer, regulator và business risk.

## 36. Funding model

Các lựa chọn thường gặp:

- **central funding** cho shared capability và enterprise minimum;
- **embedded funding** ở domain cho adoption/context/remediation;
- **co-funding** cho transformation có lợi ích chung;
- **showback** để minh bạch consumption/cost mà chưa thu phí;
- **chargeback** phân bổ chi phí theo usage.

Chargeback có thể làm domain tránh dùng shared security service hoặc tạo hành vi tối ưu số lượng request. Nếu dùng,
thiết kế unit economics và guardrail cẩn thận; không thu phí cho minimum control theo cách khuyến khích bypass.

Funding phải đi cùng accountability: ai trả không tự động là người có quyền accept enterprise risk.

## 37. Run, change và control debt

Budget/portfolio nên nhìn đủ bốn loại:

1. **run** — vận hành, support, license và assurance;
2. **change/grow** — capability mới, adoption và business enablement;
3. **debt/renewal** — end-of-life, brittle integration, manual evidence, skill debt;
4. **resilience** — exercises, redundancy, surge và recovery readiness.

Nếu chỉ tài trợ project mới, capability cũ âm thầm suy giảm. Mọi business case cần tính total lifecycle cost, transition,
operating capacity và eventual retirement; project “go-live” chưa phải benefits realization.

## 38. Security portfolio management

Portfolio là tập các investment/change được quản lý cùng nhau để tối ưu enterprise outcomes trong giới hạn nguồn lực.
Mỗi initiative nên có:

- strategic theme/business objective;
- risk scenario/outcome và baseline;
- accountable sponsor/capability owner;
- option considered và cost range;
- dependency/prerequisite;
- capacity/skill demand;
- milestone tạo capability, không chỉ deliver artifact;
- leading/lagging measure;
- stop/pivot/continue criteria;
- transition-to-run owner và cost.

Portfolio forum cân bằng BAU health, urgent response, debt và transformation thay vì xếp mọi item trong một backlog phẳng.

## 39. Prioritization theo outcome và dependency

Không ưu tiên chỉ bằng severity score. Có thể đánh giá theo:

- expected risk reduction hoặc business enablement;
- affected critical services/population;
- obligation/deadline và consequence;
- exploitability/urgency và uncertainty;
- control/capability dependency unlocked;
- time-to-value và reversibility;
- delivery confidence, readiness và scarce skills;
- cost of delay và opportunity cost;
- concentration/systemic effect.

Ghi rationale thay vì che judgment trong composite score. Dependency-aware sequencing rất quan trọng: inventory/identity
foundation có thể cần đi trước một control automation dù lợi ích trực tiếp nhìn nhỏ hơn.

## 40. Roadmap, OKR và outcome

Roadmap nên biểu diễn **transition of capability**:

```text
Now: static credential, coverage unknown
Next: inventory + issuance service + two pilot domains
Then: golden path + migration waves + enforced new workloads
Later: legacy retirement + verified exception tail
```

Objective mô tả kết quả; key result đo thay đổi có nghĩa. “Triển khai tool X” là output, còn “95% eligible production
workloads dùng short-lived identity, unknown < 2%, no critical static secret beyond expiry” gần outcome hơn.

Mỗi horizon cần assumptions, dependencies, decision points và capacity—not một Gantt chart giả vờ chắc chắn.

## 41. Control ownership và inheritance

Shared platform thường cung cấp control mà nhiều service **inherit**. Cần registry thể hiện:

- control objective và design owner;
- implementation/service owner;
- scope/eligible population;
- consumer prerequisites và responsibilities;
- evidence source/freshness;
- assurance method;
- exception và residual gap;
- downstream consumers bị ảnh hưởng khi control đổi/hỏng.

Inheritance không phải copy chữ “compliant”. Consumer chỉ được kế thừa phần control thực sự áp dụng trong effective state.
Một platform certificate hết hiệu lực hoặc scope sai có thể ảnh hưởng đồng thời hàng trăm service — cần blast-radius ownership.

## 42. Governance forum và cadence

Mỗi forum phải có decision mandate, không chỉ status:

| Forum | Quyết định chính | Cadence minh họa |
|---|---|---|
| Capability review | health, gap, roadmap, dependency | monthly/quarterly |
| Service review | demand, SLO, adoption, backlog | biweekly/monthly |
| Portfolio council | fund/sequence/stop/pivot | monthly/quarterly |
| Risk forum | accept/escalate/treat residual risk | risk-triggered/monthly |
| Workforce review | skill/capacity/succession/sourcing | quarterly |
| Executive/board | appetite, exposure, investment ask | quarterly/triggered |

Pre-read nêu decision/option/evidence; biên bản ghi owner, action, due date và revisit trigger. Hủy hoặc gộp forum không
có decision value.

## 43. Exception, risk và escalation flow

Một flow rõ tránh ticket bị chuyển vòng:

```text
standard path fails
    → classify constraint + affected outcome
        → propose alternative / compensating control
            → assess residual risk + duration
                → delegated decision or escalation
                    → register + expiry + verification + systemic feedback
```

Exception approver không luôn là risk owner. Nếu residual risk vượt delegation/appetite, escalation tới đúng business
authority. Expired exception không tự trở thành approved; phải close, renew có evidence mới hoặc escalate.

Phân tích exception lặp lại để sửa pattern, service, capacity hoặc policy.

## 44. Data và evidence backbone

Operating model cần một backbone kết nối:

- capability/service/control registry;
- asset/service/owner inventory;
- demand/work/decision records;
- risk và exception register;
- portfolio/funding/dependency;
- workforce/skill/capacity;
- control evidence và measurement definitions.

Không nhất thiết là một tool duy nhất, nhưng cần identifiers, semantics, ownership, lineage, freshness và integration.
Tự động thu evidence gần execution point, giữ provenance và phân biệt unknown với compliant.

Đọc [Security Metrics, Measurement & Executive Reporting](../metrics/security_metrics_measurement_executive_reporting.md)
để thiết kế measure contract, uncertainty và decision-oriented reporting.

## 45. Automation và AI trong operating model

Automation/AI có thể triage, enrich, recommend hoặc thực thi. Với mỗi use case, định nghĩa:

- decision/task boundary;
- authoritative inputs và data sensitivity;
- confidence/abstention rule;
- human approval theo impact/reversibility;
- least privilege và action limit;
- audit trail, provenance và version;
- test/evaluation, drift và failure handling;
- override/rollback/kill switch;
- model/vendor dependency và exit.

Tự động hóa quy trình mơ hồ chỉ làm lỗi chạy nhanh hơn. Giữ accountable owner; AI không phải risk owner, control owner
hay người chịu trách nhiệm cuối cùng.

## 46. Chuyển đổi operating model

Không “big bang” toàn bộ organization. Một lộ trình khả thi:

1. chọn 1–2 capability có pain/risk rõ;
2. baseline outcome, demand, ownership, flow và capacity;
3. thiết kế target service/interface/decision rights;
4. pilot với domain đại diện;
5. đo adoption, effectiveness, wait/rework và people load;
6. sửa product/policy/funding;
7. scale theo migration wave;
8. retire process/tool/role cũ;
9. institutionalize review và feedback.

Change plan cần communication, manager incentive, training và transition capacity. Không đòi team vừa vận hành 100%
vừa tự chuyển đổi mà không giảm scope hoặc bổ sung năng lực tạm thời.

## 47. Đo capability health

Đánh giá đa chiều, tránh một maturity score duy nhất:

| Chiều | Ví dụ câu hỏi |
|---|---|
| Outcome/risk | Exposure hoặc business consequence thay đổi không? |
| Coverage/adoption | Bao nhiêu eligible population được bảo vệ, unknown bao nhiêu? |
| Effectiveness/quality | Control có ngăn/phát hiện/phục hồi như thiết kế? |
| Flow/capacity | Demand, queue, tail, rework và surge có bền vững? |
| Reliability/resilience | Service/dependency có chịu failure và recovery được? |
| Economics | Unit cost, total cost và avoided waste có hợp lý? |
| Customer experience | Path có rõ, nhanh, usable và supportable? |
| People sustainability | Skill depth, on-call, attrition và key-person risk? |

Mỗi measure cần decision, owner, denominator, quality và action threshold.

## 48. Capability assessment và roadmap cải tiến

Assessment nên tạo quyết định, không tạo “điểm đẹp”:

1. xác định scope/outcome và target profile;
2. thu evidence từ design, operation, consumer và incident;
3. đánh giá từng chiều health/maturity;
4. mô tả gap và risk consequence;
5. tìm root cause: ownership, service, capacity, skill, data hay funding;
6. xác định options và dependencies;
7. ưu tiên roadmap, owner, measure và review date;
8. kiểm chứng sau thay đổi.

Không average ordinal maturity. Có thể một capability Defined về process nhưng Ad hoc về coverage; giữ profile nhiều chiều
để tránh mất thông tin và đầu tư sai chỗ.

## 49. Ví dụ end-to-end: workload identity

**Bối cảnh:** nhiều workload dùng static secrets, inventory thiếu và rotation gây outage.

| Thành phần operating model | Thiết kế |
|---|---|
| Outcome | Workload được xác thực bằng identity ngắn hạn, revoke/trace được |
| Capability owner | Chịu target state, coverage, dependency và roadmap |
| Service | Issuance, federation, policy, SDK, support, audit evidence |
| Platform owner | Reliability, API, key hierarchy, region và recovery |
| Domain owner | Inventory, integration, migration, runtime failure handling |
| Risk owner | Quyết định legacy tail vượt tolerance |
| Demand/capacity | Forecast theo workload waves; specialist cho legacy patterns |
| Funding | Central platform + domain migration + temporary enablement team |
| Measures | Eligible/covered/unknown, static-secret tail, auth failure, queue, exception age |

Flow chuyển đổi:

```text
inventory → pilot → golden path → new-workload default
    → migration waves → enforced policy → exception-tail retirement
```

Incident, support ticket và exception lặp lại quay về product backlog; certificate hay vendor không tự chứng minh outcome.

## 50. Checklist, anti-pattern và tài liệu tham khảo

### Checklist thiết kế

- [ ] Capability có outcome, scope, customer và owner rõ.
- [ ] Current/target profile dựa trên risk và evidence.
- [ ] Service catalog nêu eligibility, inputs/outputs, SLO, support và shared responsibility.
- [ ] Decision rights, delegation, exception và escalation nhất quán.
- [ ] Demand, WIP, capacity, skill bottleneck và surge reserve được nhìn thấy.
- [ ] Funding tính run, change, debt, resilience và lifecycle cost.
- [ ] Workforce plan dựa trên work/knowledge/skills, có succession và sustainability.
- [ ] Partner contract nối với workflow, evidence, exercise và exit.
- [ ] Portfolio có dependencies, transition-to-run và stop/pivot criteria.
- [ ] Capability health nối outcome, coverage, effectiveness, flow, economics và people.

### Anti-pattern cần tránh

- “Security owns security” nhưng business/control ownership không rõ.
- Headcount, tool count hoặc maturity average được dùng thay outcome.
- Central team nhận mọi request, không catalog/triage/WIP limit.
- Self-service không có guardrail, support, evidence và lifecycle.
- Champion nhận việc vô hạn ngoài job, không authority hoặc manager support.
- Vendor được coi là đã chuyển giao accountability.
- Project go-live nhưng không có operating capacity và retirement plan.
- Governance forum chỉ đọc status, không có decision mandate.

### Nguồn chính thức

- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework) — quản lý và truyền đạt cybersecurity risk bằng outcomes.
- [NIST SP 1301 — Organizational Profiles](https://csrc.nist.gov/pubs/sp/1301/final) — current/target profile và action-oriented gap analysis.
- [NIST SP 800-181 Rev. 1 — NICE Framework](https://csrc.nist.gov/pubs/sp/800/181/r1/final) — mô tả cybersecurity work, tasks, knowledge và skills.
- [NICE Framework Resource Center](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center) — components và hướng dẫn workforce hiện hành.
- [NIST SP 1308](https://csrc.nist.gov/pubs/sp/1308/final) — nối enterprise risk, cybersecurity risk và workforce decisions.
- [NIST IR 8286 Rev. 1](https://csrc.nist.gov/pubs/ir/8286/r1/final) — tích hợp cybersecurity risk vào enterprise risk management.

### Học tiếp

1. [Security Strategy, Investment & Portfolio Prioritization](security_strategy_investment_portfolio_prioritization.md) — strategic themes, business case,
   dependency-aware roadmap, benefits realization và stop/continue decisions.
2. [Security Culture, Human Risk & Behavior Engineering](security_culture_human_risk_behavior_engineering.md) — behavior, incentive, friction,
   secure norms, intervention design và outcome measurement.

---

*Cập nhật lần cuối: 2026-08-03.*
