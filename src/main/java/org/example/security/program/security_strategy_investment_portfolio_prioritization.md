# Security Strategy, Investment & Portfolio Prioritization

> Mục tiêu: biến business objective, risk appetite và evidence thành một tập lựa chọn đầu tư có thể giải thích,
> có dependency, owner, funding, tiêu chí stop/pivot/continue và cơ chế kiểm chứng lợi ích thực tế.

---

## 1. Security strategy là một tập lựa chọn

Security strategy trả lời tổ chức sẽ:

- bảo vệ hoặc enable business outcome nào;
- tập trung vào risk scenario và capability nào;
- chọn cách tiếp cận nào và chủ động **không** làm gì;
- phân bổ tiền, người, thời gian và attention ra sao;
- thay đổi từ current state sang target state theo thứ tự nào;
- kiểm chứng value và điều chỉnh khi assumptions sai.

```text
business direction + risk reality + constraints
    → strategic choices
        → investment portfolio + dependency-aware roadmap
            → execution + benefits evidence
                → stop / pivot / continue / scale
```

Strategy không phải lời hứa “loại bỏ mọi risk”; nó định hướng trade-off để tổ chức theo đuổi mục tiêu trong risk appetite.

## 2. Strategy không phải wishlist hoặc tool roadmap

Các artifact sau chưa tự tạo thành strategy:

- danh sách project mọi stakeholder muốn;
- heatmap risk không có response decision;
- roadmap mua SIEM, IAM, CNAPP hoặc sản phẩm khác;
- danh sách framework/control cần “đạt 100%”;
- ngân sách năm trước cộng thêm một tỷ lệ;
- khẩu hiệu “zero trust”, “AI-first” hoặc “security by design”;
- slide target state không có sequence, capacity và transition cost.

Một strategy thực sự nói rõ lựa chọn và hệ quả. Nếu mọi đề xuất đều là “priority 1”, không có trade-off hoặc initiative
không thể bị dừng, tổ chức có inventory dự án chứ chưa có chiến lược.

## 3. Strategy cascade

Security không xây chiến lược độc lập với enterprise:

```text
mission / business strategy
    → objectives + critical services + stakeholder expectations
        → enterprise risk strategy + appetite / tolerance
            → security strategic themes + target outcomes
                → capability / control / service investments
                    → team objectives + delivery backlog
```

Traceability phải đi được cả hai chiều: một initiative giải thích nó hỗ trợ objective/risk response nào; một objective
cho thấy portfolio nào bảo vệ hoặc enable nó. Đọc [Security Governance & Risk Engineering](../governance/security_governance_risk_engineering.md)
để chuẩn hóa risk scenario, appetite, treatment và acceptance.

## 4. Tách strategy, plan, portfolio và roadmap

| Artifact | Câu hỏi chính | Horizon |
|---|---|---|
| Strategy | Chọn outcome, position và approach nào? | trung/dài hạn |
| Portfolio | Phân bổ nguồn lực giữa các investment nào? | liên tục/nhiều năm |
| Roadmap | Sequence transition và decision point thế nào? | nhiều horizon |
| Plan | Ai làm gì, khi nào, bằng capacity nào? | ngắn/trung hạn |
| Budget | Tiền được authorize cho scope/horizon nào? | kỳ tài chính |
| Backlog | Work item tiếp theo là gì? | vận hành ngắn hạn |

Không dùng roadmap chi tiết ba năm để giả vờ chắc chắn. Strategy ổn định hơn, còn portfolio/roadmap được cập nhật khi
evidence, threat, business priority hoặc execution confidence thay đổi.

## 5. Strategy horizon và nhịp cập nhật

Có thể dùng ba horizon:

- **Now:** giữ critical controls, xử lý exposure vượt tolerance, hoàn thành commitment gần.
- **Next:** xây foundation/capability mở khóa nhiều outcomes trong 6–18 tháng.
- **Later:** option cho biến động công nghệ, market, regulation và threat trong 18–36 tháng.

Đặt event trigger ngoài calendar: incident lớn, M&A, cloud/AI adoption, regulator change, critical vendor failure,
material risk change hoặc assumption bị bác bỏ. Annual strategy review là cadence tối thiểu, không phải thời điểm duy nhất
được điều chỉnh danh mục.

## 6. Strategic context scan

Context cần nhìn cả external và internal:

| Nhóm | Tín hiệu |
|---|---|
| Business | growth, product, geography, M&A, digital dependency |
| Stakeholder | customer promise, regulator, investor, partner, workforce |
| Threat | actor intent/capability, exploitation, systemic dependency |
| Technology | cloud, AI, identity, legacy, end-of-life, architecture shift |
| Operating | incident, audit, control debt, capacity, skill, vendor |
| Economics | revenue pressure, cost of capital, currency, contract exposure |

Ghi source, freshness, confidence và implication. Trend report dài nhưng không thay đổi một choice, assumption hoặc
option nào thì chưa tạo strategic insight.

## 7. Stakeholder expectations và fiduciary context

Map stakeholder theo expectation và decision rights:

- board/executive: mission, risk appetite, fiduciary oversight và investment trade-off;
- business/product: enablement, customer trust, speed và residual risk;
- engineering/operations: usable guardrails, reliability, debt và capacity;
- legal/privacy/compliance: obligations, evidence và notification;
- customer/partner: commitments, interoperability và incident coordination;
- workforce: safe behavior, workload và speak-up channel.

Không biến mọi mong muốn thành requirement. Phân biệt legal obligation, contractual commitment, enterprise policy,
risk preference và convenience; conflict phải được đưa tới đúng decision owner.

## 8. Mission, critical service và business impact

[NIST IR 8286D](https://csrc.nist.gov/pubs/ir/8286/d/upd1/final) mở rộng BIA từ availability sang các loại loss
có thể ảnh hưởng mission. Với mỗi objective, xác định:

- mission-essential function hoặc critical service;
- customer/business process được hỗ trợ;
- asset, data, identity, supplier và people dependencies;
- impact type: financial, operational, legal, safety, trust, strategic;
- impact theo thời gian và maximum tolerable disruption/loss;
- minimum viable operation và recovery dependency.

Ưu tiên asset vì “critical” chung chung dễ dẫn tới bảo vệ mọi thứ như nhau. Nối asset tới mission consequence mới tạo
cơ sở đầu tư và sequence có thể giải thích.

## 9. Risk appetite, tolerance và capacity

- **Appetite** định hướng loại/mức risk tổ chức sẵn sàng theo đuổi hoặc giữ để đạt objective.
- **Tolerance** tạo boundary/variation cụ thể quanh objective.
- **Risk capacity** là mức loss tối đa doanh nghiệp có thể chịu trước khi viability bị đe dọa.

Strategy dịch các khái niệm này thành guardrail và trigger, ví dụ:

- critical payment không được phụ thuộc một recovery credential duy nhất;
- privileged access tồn tại quá X giờ cần delegated exception;
- outage vượt Y phút phải kích hoạt crisis authority;
- legacy unsupported exposure có deadline và migration fund.

Không dùng màu heatmap thay appetite statement; boundary phải giúp đưa ra quyết định thực tế.

## 10. Assumption, uncertainty và strategic risk

Mỗi strategy có assumptions: growth, adoption, threat likelihood, vendor readiness, hiring, budget hoặc regulation.
Tạo assumption register:

| Trường | Nội dung |
|---|---|
| Assumption | Điều đang được coi là đúng |
| Evidence/confidence | Nguồn và mức chắc chắn |
| Sensitivity | Nếu sai thì choice/business case đổi bao nhiêu? |
| Indicator | Tín hiệu xác nhận hoặc bác bỏ |
| Owner | Người theo dõi |
| Revisit trigger | Khi nào review/pivot |

Unknown không phải lý do trì hoãn mọi quyết định. Chọn option reversible, pilot hoặc mua thêm information khi uncertainty
có thể làm thay đổi lựa chọn.

## 11. Current Profile bằng evidence

Current state cần mô tả outcome thực, không chỉ policy/tool deployment:

- eligible population, coverage và unknown;
- control effectiveness và failure history;
- capability/service health;
- dependency/concentration;
- exception, debt và end-of-life;
- workforce/partner sustainability;
- cost/run capacity;
- customer friction và bypass.

[NIST SP 1301](https://csrc.nist.gov/pubs/sp/1301/final) dùng Organizational Profile để mô tả current/target CSF outcomes.
Có thể dùng profile đó làm ngôn ngữ chung, nhưng giữ drill-down tới evidence và business context của doanh nghiệp.

## 12. Target Profile là trạng thái đủ, không phải tối đa

Target state mô tả outcome cần đạt trong horizon:

```text
critical service + risk scenario
    → target outcome / tolerance
        → capability / control characteristics
            → coverage + effectiveness + resilience evidence
```

Target phải risk-based: production payment, internal wiki và disposable test environment không cần cùng depth. Ghi rõ
population, deadline, minimum characteristics, allowed tail và evidence. “Implement zero trust” hoặc “maturity 5” quá mơ hồ
để làm target đầu tư.

## 13. Gap analysis có consequence và root cause

Một gap record tốt gồm:

- current evidence và target outcome;
- affected objective/critical service;
- risk consequence nếu không xử lý;
- population/coverage và uncertainty;
- root cause: capability, architecture, process, skill, incentive, data hay funding;
- dependencies và constraints;
- existing response/compensating control;
- option candidates.

Không tự động biến mỗi gap thành project. Nhiều gap có chung root cause; một shared identity foundation có thể giải quyết
nhiều symptom tốt hơn hàng chục remediation riêng lẻ.

## 14. Strategic themes

Theme gom investment quanh một outcome bền vững, ví dụ:

- **Identity-first access:** bỏ standing/static privilege trên critical paths.
- **Recoverable digital business:** verified recovery cho critical services/dependencies.
- **Secure product delivery:** reusable guardrails và evidence trong delivery flow.
- **Trusted data/AI:** lineage, purpose, access và model lifecycle.
- **Adaptive assurance:** evidence gần effective state và risk-triggered validation.

Mỗi theme cần narrative: problem, affected objectives, choice, target outcome, principles, measures, major dependencies và
những gì nằm ngoài scope. Giới hạn số theme để leadership thật sự phân bổ attention.

## 15. Strategic outcome và guardrail

Outcome nói điều gì thay đổi; guardrail nói boundary không được phá trong quá trình đạt outcome.

Ví dụ:

| Outcome | Guardrail |
|---|---|
| Product team phát hành nhanh bằng paved road | Không bypass signing/provenance trên production artifact |
| Giảm static secrets | Migration không làm mất recovery hoặc gây mass outage |
| Tăng self-service access | Privilege vẫn time-bound, scoped và auditable |
| Consolidate vendors | Không tạo single dependency vượt tolerance |

Outcome không nên là activity “đào tạo 1.000 người” hoặc “mua tool”; cần diễn tả thay đổi ở risk, control, behavior,
resilience hoặc business enablement.

## 16. Tạo nhiều strategic options

Không đi thẳng từ problem tới vendor/solution yêu thích. Tạo option khác biệt:

1. giữ hiện trạng + monitoring;
2. giảm scope/exposure;
3. cải tiến process/control hiện tại;
4. build shared platform;
5. buy managed/product capability;
6. partner/co-source;
7. transfer/share một phần risk;
8. tránh activity gây risk;
9. staged hybrid transition.

So sánh option theo outcome, time-to-value, uncertainty, reversibility, dependency, lifecycle cost, capacity, residual risk
và exit. Option analysis làm rõ trade-off; không phải nghi thức hợp thức hóa quyết định đã có.

## 17. Nối risk response với investment

Risk response thường gồm avoid, mitigate, transfer/share và accept. Một scenario có thể dùng tổ hợp:

```text
ransomware on critical operations
    → reduce exposed attack paths
    + segment privilege/blast radius
    + improve detection/containment
    + build clean recovery
    + insure selected financial tail
    + explicitly accept remaining residual risk
```

Investment proposal phải nêu phần response nào nó đóng góp, phần nào phụ thuộc initiative khác và residual risk còn lại.
Không tuyên bố một control “solves ransomware” khi nó chỉ tác động một pathway.

## 18. Baseline “do nothing” không có nghĩa chi phí bằng zero

Mọi business case cần comparator. “Do nothing” có thể bao gồm:

- run cost hiện tại và license renewal;
- manual labor/rework và queue delay;
- expected incident/loss exposure;
- end-of-life escalation và technical debt;
- lost business/customer assurance;
- regulatory/contract consequence;
- opportunity cost vì platform chặn growth;
- future migration cost tăng.

So sánh option với baseline có cùng horizon. Nếu baseline bị mô tả tệ bất thường hoặc option không tính operating cost,
business case bị thiên lệch từ đầu.

## 19. Anatomy của business case

Một business case decision-ready gồm:

1. decision/ask và deadline;
2. business context/objective;
3. risk scenario/current evidence;
4. target outcome và success measures;
5. options, gồm baseline;
6. benefits, disbenefits và residual risk;
7. cost/capacity/cash-flow theo horizon;
8. dependencies, assumptions và uncertainty;
9. delivery/transition-to-run plan;
10. owner, governance và stop/pivot/continue gates;
11. recommendation cùng rationale.

Độ dài tùy mức investment; cấu trúc quyết định không nên mất dù proposal chỉ một trang.

## 20. Total lifecycle cost

Không dùng license/purchase price làm tổng chi phí. Tính:

- discovery, design, procurement và legal;
- integration, data migration và customization;
- platform/infrastructure;
- internal delivery capacity và opportunity cost;
- training, change/adoption và support;
- operation, assurance, evidence và incident response;
- vendor price growth, volume và currency;
- parallel run/transition;
- technical/control debt;
- deprecation, exit, data export/deletion và replacement.

Dùng range và assumptions thay false precision. CapEx/OpEx/accounting treatment có thể quan trọng nhưng không được làm
mất total economic cost và capacity constraint.

## 21. Benefits taxonomy

Lợi ích security không chỉ là “tránh breach”:

| Nhóm | Ví dụ |
|---|---|
| Risk reduction | giảm likelihood, impact, duration hoặc uncertainty |
| Resilience | phục hồi nhanh, giảm tail loss và dependency fragility |
| Enablement | vào market, ký customer, dùng cloud/AI an toàn hơn |
| Productivity | giảm wait/rework/manual evidence/support |
| Trust/assurance | chứng minh commitment với customer/regulator |
| Optionality | dễ đổi vendor, integrate acquisition, thích ứng threat |
| Cost avoidance | retire duplicate tools/process/debt |

Ghi beneficiary, mechanism, baseline, timing, measure và attribution. Tránh cộng trùng cùng một benefit dưới nhiều nhãn.

## 22. Ước lượng risk reduction

Mô tả mechanism trước con số:

```text
investment
    → control/capability change
        → exposure / likelihood / impact / duration change
            → business outcome distribution changes
```

Dùng scenario, range và confidence. Nếu định lượng expected loss, ghi frequency/impact assumptions, correlation và tail;
không dùng một điểm “$3.2M” như sự thật chắc chắn. So sánh residual risk trước/sau và những pathway không bị tác động.

[NIST IR 8286B](https://csrc.nist.gov/pubs/ir/8286/b/upd1/final) nhấn mạnh ưu tiên risk theo ảnh hưởng tới enterprise
objectives và bổ sung projected response cost vào risk register để hỗ trợ enterprise view.

## 23. ROI, ROSI, NPV và payback: dùng có điều kiện

- **ROI** so net benefit với cost, nhưng dễ phóng đại avoided loss.
- **ROSI** tập trung security investment, vẫn phụ thuộc risk reduction estimate.
- **NPV** đưa cash flow khác thời điểm về hiện tại, phù hợp option nhiều năm.
- **Payback** cho biết thời gian hoàn vốn nhưng bỏ qua value sau cutoff/tail risk.

Không xếp hạng mọi security control chỉ bằng ROI. Mandatory obligation, catastrophic tail, safety hoặc foundational
capability có thể cần decision logic khác. Công khai model, range, discount/horizon và sensitivity; dùng số để hỗ trợ
judgment, không thay judgment.

## 24. Value of Information và option value

Khi uncertainty có thể đảo quyết định, cân nhắc đầu tư nhỏ để học:

- pilot/prototype;
- asset/control coverage discovery;
- recovery exercise;
- vendor proof-of-capability;
- threat/risk analysis;
- customer research;
- architecture spike.

**Value of Information** cao khi information thay đổi choice lớn và chi phí học thấp. **Option value** cao khi một bước
reversible giữ nhiều lựa chọn tương lai. Không kéo dài pilot vô hạn: định nghĩa hypothesis, evidence, deadline và quyết định
sẽ được đưa ra sau pilot.

## 25. Định tính, bán định lượng và định lượng

| Cách | Dùng tốt khi | Cảnh báo |
|---|---|---|
| Qualitative narrative | data yếu, decision sớm, tail/obligation | label phải có định nghĩa |
| Semi-quantitative | so sánh theo rubric nhất quán | ordinal score không hỗ trợ phép toán tùy ý |
| Quantitative range | option/cost/loss có data và model | sensitivity/correlation/tail phải rõ |

Không giả chính xác bằng cách gán trọng số 17% cho opinion. Chọn resolution phù hợp decision. Có thể dùng narrative cho
systemic risk và cash-flow model cho cost trong cùng business case.

## 26. Initiative charter

Khi được chọn vào portfolio, initiative cần charter:

- sponsor và accountable outcome owner;
- strategic theme/objective/risk scenario;
- in-scope/out-of-scope;
- target outcome, baseline và measures;
- option/approach được chọn;
- funding/capacity và work class;
- dependencies/assumptions;
- milestones theo capability/adoption;
- transition-to-run owner;
- risk/issue/escalation;
- decision gates và stop/pivot/continue criteria.

Charter không đóng băng solution; thay đổi material assumption, scope, benefit hoặc cost phải quay lại governance.

## 27. Portfolio taxonomy

Phân loại giúp tránh mọi thứ cạnh tranh trong một hàng:

- **Run/protect:** vận hành critical controls và commitments.
- **Remediate/debt:** legacy, end-of-life, exception tail, brittle process.
- **Grow/enable:** hỗ trợ product, geography, M&A, cloud/AI.
- **Transform:** target architecture/capability nhiều năm.
- **Resilience:** redundancy, recovery, exercise, surge.
- **Mandatory:** legal/contract/safety với interpretation rõ.
- **Explore:** experiment/option/learning.

Một initiative có thể có nhiều benefit nhưng nên có primary class để quản funding expectation và evaluation cadence.

## 28. Portfolio balance

Portfolio khỏe không tối đa một metric; nó cân bằng:

- ngắn hạn với dài hạn;
- prevention với detection/response/recovery;
- shared foundation với domain remediation;
- run health với transformation;
- mandatory với discretionary enablement;
- predictable work với reserve cho uncertainty;
- concentrated bet với diversified options;
- people/process với technology.

Hiển thị allocation theo money **và scarce capacity**. Một portfolio có đủ budget nhưng vượt khả năng của ba specialist
vẫn không khả thi.

## 29. Dependency graph

Roadmap tuyến tính thường che dependency. Lập graph:

```text
asset / owner inventory
    ├── workload identity migration
    ├── evidence coverage
    └── incident blast-radius analysis

identity foundation
    ├── privileged JIT
    └── zero-standing-access target
```

Phân biệt prerequisite cứng, enablement mềm, shared resource và policy/business dependency. Ghi owner, readiness và
failure consequence. Khi foundation trễ, replan downstream thay vì giữ mọi milestone “xanh” độc lập.

## 30. Sequence theo value, risk và learning

Sequence tốt cân nhắc:

- urgent exposure/tolerance breach;
- dependency unlock;
- earliest usable outcome/time-to-value;
- migration/adoption waves;
- scarce skill/vendor window;
- reversibility và learning;
- change saturation của consumer;
- parallel-run và retirement timing;
- concentration/blast radius khi cutover.

Không nhất thiết xây foundation hoàn hảo trước khi có value. Dùng thin slice end-to-end để kiểm assumptions, sau đó
scale; nhưng không bypass prerequisite an toàn chỉ để đạt milestone.

## 31. Capacity-constrained portfolio

Investment approval không tạo delivery capacity. Với mỗi initiative, map:

| Capacity | Cần xem |
|---|---|
| Delivery | engineering, product, architecture, migration |
| Consumer | domain onboarding, testing, change management |
| Specialist | cryptography, identity, forensics, legal |
| Run | support, on-call, evidence, lifecycle |
| Governance | procurement, risk decision, assurance |

Tính cả BAU, incident reserve và context switching. Nếu demand vượt capacity, giảm WIP, đổi sequence/scope, partner hoặc
explicitly defer; không giả rằng mọi initiative chạy song song sẽ nhanh hơn.

## 32. Prioritization criteria

Một rubric decision-oriented có thể gồm:

- contribution tới business objective;
- risk/tolerance/critical-service effect;
- obligation/deadline;
- dependency unlocked;
- time-to-value/cost of delay;
- benefit confidence;
- delivery readiness/feasibility;
- lifecycle cost và capacity;
- reversibility/option value;
- concentration/systemic impact;
- customer/adoption burden.

Định nghĩa scale và evidence required trước khi chấm. Rubric tạo cuộc đối thoại nhất quán; leadership vẫn phải đưa ra
trade-off khi criteria xung đột.

## 33. Scoring model và bẫy precision

Composite score có thể hỗ trợ triage nhưng dễ che judgment:

- cộng ordinal labels như số đo khoảng;
- double count severity/impact/criticality;
- weight được chọn để hợp thức hóa kết quả;
- score cao nhưng dependency chưa sẵn sàng;
- cost/capacity đứng ngoài công thức;
- proposal owner game input;
- tail/systemic risk bị average mất.

Giữ component, evidence và narrative; chạy sensitivity khi weight thay đổi. Nếu xếp hạng đảo mạnh chỉ vì weight nhỏ,
decision không robust và cần thảo luận, không thêm decimal.

## 34. Aggregate risk mà không cộng mù

[NIST IR 8286C Rev. 1](https://csrc.nist.gov/pubs/ir/8286/c/r1/final) mô tả tích hợp cybersecurity risk register
vào enterprise risk portfolio. Khi tạo portfolio view, xử lý:

- shared IdP/cloud/DNS/vendor dependency;
- correlated threat events;
- cùng loss được đếm ở nhiều risk register;
- risk cascade giữa system, organization và enterprise;
- concentration theo region/technology/provider;
- diversification thật và giả;
- risk opportunity/enablement bên cạnh loss.

Ba mươi service phụ thuộc một IdP không phải ba mươi independent risks. Aggregate theo scenario/objective/dependency,
giữ provenance và drill-down.

## 35. Scenario-based portfolio optimization

Stress-test portfolio dưới các scenario:

- ransomware + identity compromise;
- critical cloud region/provider failure;
- rapid acquisition/onboarding;
- regulation/customer requirement mới;
- budget giảm 15%;
- specialist/vendor mất khả dụng;
- AI adoption tăng nhanh;
- major control platform outage.

Hỏi investment nào vẫn tạo value, dependency nào thành bottleneck, reserve nào thiếu và initiative nào có thể defer.
Tối ưu không chỉ cho expected case; resilience strategy phải nhìn tail và khả năng thích nghi.

## 36. Funding architecture

Funding phải phản ánh beneficiary và accountability:

- enterprise fund cho shared foundation/minimum control;
- domain fund cho migration/remediation/context;
- co-fund cho enablement có lợi ích chung;
- transformation fund cho transition tạm thời;
- reserve cho emerging risk/incident;
- vendor/insurance transfer cho phần phù hợp.

Ring-fence run/debt/resilience tối thiểu để project mới không ăn mòn capability hiện tại. Showback có thể làm rõ consumption;
chargeback cần tránh khiến domain bypass minimum control. Chi tiết delivery model xem
[Security Program Operating Model](security_program_operating_model_capability_management.md).

## 37. Annual budget và continuous planning

Annual budget tạo boundary, nhưng risk và business change liên tục. Thiết kế:

- annual strategic allocation theo theme/capability;
- quarterly rolling forecast và reallocation;
- delegated threshold cho small decisions;
- contingency reserve với trigger/authority;
- material-change gate cho cost/benefit/scope;
- transparent unfunded/deferred risk;
- multi-year commitment visibility.

Không dùng “budget đã phê duyệt” làm lý do tiếp tục initiative mất value. Đồng thời tránh thay priority hàng tuần khiến
delivery không hoàn thành; thay đổi phải dựa trên material evidence và decision cadence.

## 38. Stage gates theo bằng chứng

Gate nên giảm uncertainty từng bước:

| Gate | Decision | Evidence tối thiểu |
|---|---|---|
| Explore | Có đáng nghiên cứu? | problem, objective, rough exposure |
| Shape | Option nào khả thi? | options, architecture, cost range, dependencies |
| Commit | Có fund/delivery? | business case, owner, capacity, target measures |
| Pilot | Có scale? | hypothesis, adoption, effectiveness, failure, revised economics |
| Scale | Mở rộng wave nào? | readiness, support/run, migration evidence |
| Realize | Benefit có xảy ra? | outcome/coverage/cost/residual risk |
| Retire | Đóng initiative/legacy? | handoff, decommission, revoke/delete, lessons |

Gate là decision point, không phải document ceremony hoặc approval đã định sẵn.

## 39. Dependency-aware roadmap

Roadmap nên trình bày transition state và decision, không chỉ delivery date:

```text
Now        : baseline + ownership + urgent containment
0–6 months : thin-slice platform + pilot + evidence
6–12 months: adoption waves + new-use default + run model
12–24 months: legacy tail + enforcement + retirement
Decision   : scale/pivot at coverage, reliability and unit-cost thresholds
```

Mỗi item ghi outcome, dependency, owner, confidence và revisit trigger. Dùng range/horizon cho work xa; chi tiết tăng khi
đến gần và uncertainty giảm.

## 40. OKR và strategy deployment

Objective mô tả thay đổi có ý nghĩa; key result đo evidence của thay đổi đó:

**Objective:** Critical services phục hồi được sau identity-destructive incident.

**Key results minh họa:**

- 100% Tier-0 recovery identities tách khỏi primary trust plane;
- 90% critical services pass clean-recovery exercise trong RTO, unknown = 0;
- critical recovery dependencies có owner, alternative và verified runbook;
- severe exercise findings đóng/accepted trước expiry.

Không dùng “hoàn thành 20 tabletop” làm KR duy nhất. Activity có thể là initiative; KR cần gần outcome/evidence hơn.

## 41. Leading, lagging và decision measures

Mỗi investment cần measurement chain:

- **input:** money, people, vendor/capacity;
- **activity/output:** platform, migrations, training, tests;
- **leading:** adoption, coverage, control conformance, exception tail;
- **effectiveness:** control hoạt động dưới failure/adversary;
- **lagging/outcome:** incident impact/duration, customer/business effect;
- **economics:** unit cost, avoided rework, run cost;
- **risk:** residual exposure và uncertainty.

Đọc [Security Metrics, Measurement & Executive Reporting](../metrics/security_metrics_measurement_executive_reporting.md)
để định nghĩa denominator, data quality, confidence và reporting semantics.

## 42. Baseline, counterfactual và attribution

Không thể tuyên bố benefit nếu không biết “so với gì”. Trước investment:

- chốt baseline population/time window;
- ghi trend/seasonality và concurrent changes;
- định nghĩa comparator/counterfactual hợp lý;
- xác định benefit mechanism;
- ghi data quality và uncertainty.

Incident count giảm có thể do attack volume giảm, detection kém hoặc scope đổi. Dùng cohort, phased rollout, matched
comparison hoặc evidence triangulation khi phù hợp; không khẳng định causation chỉ từ correlation.

## 43. Benefits realization owner

Project manager thường chịu delivery; **benefit owner** chịu outcome sau go-live. Owner cần:

- xác nhận baseline/target;
- đảm bảo adoption/migration;
- phối hợp process/incentive/policy change;
- theo dõi disbenefit và residual risk;
- duy trì run capacity;
- báo benefit theo schedule;
- đề xuất scale/pivot/retire.

Benefit có thể xuất hiện sau khi project team giải tán, nên handoff, data source, review date và accountability phải được
thiết kế trước funding approval.

## 44. Stop, pivot, continue và scale

Đặt criteria trước khi sunk cost xuất hiện:

| Decision | Trigger minh họa |
|---|---|
| Continue | assumptions giữ, milestone tạo evidence, benefit/cost trong range |
| Scale | pilot đạt effectiveness, reliability, adoption và unit economics |
| Pivot | outcome còn đúng nhưng solution/sequence/segment sai |
| Pause | dependency/capacity chưa sẵn sàng, chờ evidence có deadline |
| Stop | objective mất, benefit không khả thi, cost/risk vượt boundary |
| Retire | target đạt, legacy decommission và run owner tiếp nhận |

Dừng đúng lúc giải phóng capacity là một kết quả quản trị tốt, không mặc định là thất bại.

## 45. Sunk cost, escalation of commitment và gaming

Các bias phổ biến:

- tiếp tục vì “đã đầu tư quá nhiều”;
- chỉ báo output thuận lợi, che adoption/effectiveness;
- đổi baseline hoặc denominator;
- chia nhỏ overrun để dưới approval threshold;
- gọi mandatory để tránh prioritization;
- optimistic benefit, bỏ transition/run cost;
- sponsor prestige khiến challenge bị im lặng.

Giảm bias bằng independent challenge, pre-mortem, reference class, evidence gate, transparent assumptions và decision log.
Reward việc surfacing bad news sớm; nếu người báo vấn đề bị phạt, portfolio luôn xanh cho tới lúc thất bại.

## 46. Portfolio governance và decision rights

Một portfolio forum tốt có:

- mandate fund/sequence/pause/stop/reallocate;
- đại diện business, finance, technology, risk/security và delivery;
- pre-read theo cùng business-case schema;
- view money, capacity, dependency, risk và benefit;
- conflict-of-interest disclosure;
- decision log với rationale/conditions;
- escalation theo appetite/delegation;
- cadence và event trigger.

Security leadership đề xuất/challenge, nhưng business risk owner và enterprise authority quyết định residual risk/investment
theo delegation. Forum không nên chỉ “xem status”.

## 47. Executive và board communication

Báo cáo theo decision, không dump technical dashboard:

```text
objective / strategic theme
    → material scenarios + current / target exposure
        → portfolio choices + progress / confidence
            → concentration / assumptions / residual risk
                → decision or ask
```

Nêu rõ: điều gì thay đổi, benefit nào đã/ chưa chứng minh, investment nào lệch, option/trade-off, consequence nếu defer
và management recommendation. Giữ technical drill-down sẵn nhưng không che uncertainty bằng một màu hoặc composite score.

## 48. Ví dụ: đầu tư cyber recovery

**Objective:** duy trì settlement service sau identity-destructive ransomware.

| Thành phần | Nội dung minh họa |
|---|---|
| Current evidence | backup có nhưng recovery identity phụ thuộc primary domain; exercise chưa test clean room |
| Target outcome | khôi phục minimum settlement trong RTO với trust plane độc lập và verified data integrity |
| Options | cải tiến hiện trạng; isolated recovery platform; managed recovery; staged hybrid |
| Dependencies | BIA, service map, Tier-0 identity, immutable backup, crisis authority, vendor access |
| Benefits | giảm outage/tail loss, tăng customer/regulator assurance, learning qua exercise |
| Costs | build/integration, parallel run, exercise, on-call, vendor và decommission legacy |
| Gates | architecture proof → service pilot → destructive exercise → migration waves |
| Measures | critical coverage/unknown, exercise pass/RTO/RPO, severe findings, recovery dependency tail |

Stop/pivot nếu identity independence không đạt hoặc operating cost vượt range; scale chỉ sau evidence recovery end-to-end.

## 49. Lộ trình triển khai trong 90 ngày

**Ngày 1–30 — Align và baseline**

- chọn 3–5 business objectives/critical services;
- thống nhất appetite/tolerance và top scenarios;
- inventory portfolio hiện tại, funding, capacity và commitments;
- xác định duplicate, orphan initiative và missing baseline.

**Ngày 31–60 — Shape choices**

- tạo strategic themes/current-target profiles;
- chuẩn business-case/rubric/dependency schema;
- review options, cost range, benefits và assumptions;
- draft balanced portfolio và defer list.

**Ngày 61–90 — Decide và instrument**

- quyết fund/sequence/stop/pivot;
- assign sponsor/benefit owner/run owner;
- đặt gates, measures và review cadence;
- công bố narrative, decision log và first rolling review.

## 50. Checklist, anti-pattern và tài liệu tham khảo

### Checklist decision-ready

- [ ] Strategy nối mission, objective, critical service và risk appetite.
- [ ] Current/target profile có scope, evidence, coverage và uncertainty.
- [ ] Strategic theme thể hiện choice và điều chủ động không làm.
- [ ] Business case có baseline, options, lifecycle cost, benefit mechanism và residual risk.
- [ ] Portfolio cân bằng run/debt/resilience/enablement/transformation/explore.
- [ ] Dependency graph và scarce capacity được dùng khi sequence.
- [ ] Prioritization giữ component evidence, không che judgment trong score.
- [ ] Initiative có sponsor, benefit owner, run owner và decision gates.
- [ ] Baseline/counterfactual/data quality đủ để kiểm benefits.
- [ ] Stop/pivot/continue/scale criteria được đặt trước review.

### Anti-pattern cần tránh

- Strategy là danh sách tool/project không có choice.
- Mọi item “priority 1”; không có deferred/unfunded view.
- Business case chỉ tính purchase price và avoided-breach số đơn.
- Cộng ordinal risk/maturity score rồi xếp hạng với decimal.
- Approve tiền nhưng bỏ qua consumer/specialist/run capacity.
- Roadmap không có dependency, uncertainty hoặc transition state.
- Go-live được báo là benefit realization.
- Initiative không bao giờ bị dừng vì sunk cost hoặc sponsor prestige.

### Nguồn chính thức

- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework) — GOVERN, risk strategy và outcome-based prioritization.
- [NIST IR 8286 Rev. 1](https://csrc.nist.gov/pubs/ir/8286/r1/final) — tích hợp cybersecurity risk với enterprise objectives và ERM.
- [NIST IR 8286B](https://csrc.nist.gov/pubs/ir/8286/b/upd1/final) — ưu tiên risk và lựa chọn response theo enterprise objectives/cost.
- [NIST IR 8286C Rev. 1](https://csrc.nist.gov/pubs/ir/8286/c/r1/final) — staging/aggregation vào enterprise risk portfolio.
- [NIST IR 8286D](https://csrc.nist.gov/pubs/ir/8286/d/upd1/final) — dùng business impact để ưu tiên và response.
- [NIST SP 800-221](https://csrc.nist.gov/pubs/sp/800/221/final) — quản trị ICT risk trong enterprise risk portfolio.
- [NIST SP 800-221A](https://csrc.nist.gov/pubs/sp/800/221/a/final) — ICT Risk Outcomes Framework.
- [NIST SP 1301](https://csrc.nist.gov/pubs/sp/1301/final) — CSF 2.0 Organizational Profiles.

### Học tiếp

1. [Security Culture, Human Risk & Behavior Engineering](security_culture_human_risk_behavior_engineering.md) — behavior, incentive, friction,
   secure norms, intervention design và outcome measurement.
2. [Security Transformation & Change Management](security_transformation_change_management.md) — adoption waves, stakeholder change,
   transition risk, communication và institutionalization.

---

*Cập nhật lần cuối: 2026-08-03.*
