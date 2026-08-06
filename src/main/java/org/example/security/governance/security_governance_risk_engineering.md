# Security Governance & Risk Engineering – Biến risk thành quyết định có trách nhiệm

Security governance không phải là bộ policy dài, buổi audit hằng năm hay dashboard màu
đỏ-vàng-xanh. Nó là hệ thống giúp tổ chức trả lời nhất quán:

- mục tiêu kinh doanh/mission nào có thể bị ảnh hưởng;
- risk scenario nào đáng quan tâm và uncertainty còn ở đâu;
- control outcome nào cần đạt, ai sở hữu và ai đánh giá;
- treatment nào được chọn, chi phí/cơ hội/side effect ra sao;
- ai có thẩm quyền chấp nhận residual risk trong bao lâu;
- evidence nào chứng minh control vẫn hiệu lực khi hệ thống thay đổi;
- risk nào cần tổng hợp/escalate lên enterprise leadership.

```text
mission + obligations + risk appetite
    → risk scenario + analysis + ownership
        → control objective + treatment decision
            → implementation + evidence + assurance
                → residual risk + authorization
                    → continuous monitoring + feedback
```

Chương này nối threat modeling, security testing, vulnerability management và engineering
backlog vào enterprise risk management. Đây là hướng dẫn kỹ thuật/quản trị tổng quát, không
thay tư vấn pháp lý hoặc yêu cầu riêng của regulator/contract.

---

## 1. Governance, risk management và compliance khác nhau thế nào?

| Khái niệm | Câu hỏi chính |
|---|---|
| Governance | Ai đặt định hướng, quyền quyết định, accountability và oversight? |
| Risk management | Risk được identify, analyze, respond và monitor thế nào? |
| Control management | Outcome/control nào được thiết kế, vận hành và đánh giá? |
| Compliance | Nghĩa vụ/requirement cụ thể nào phải thỏa và chứng minh? |
| Assurance | Evidence có đủ để tin control/risk conclusion không? |

Compliance có thể là bắt buộc nhưng không đồng nghĩa an toàn. Một hệ thống có thể đạt
checklist nhưng vẫn có threat scenario chưa được framework đề cập. Ngược lại, risk thấp
không tự cho phép bỏ nghĩa vụ pháp lý.

---

## 2. Governance là hệ thống quyết định

Một governance system tốt xác định:

- decision nào cần được đưa ra;
- input/evidence tối thiểu;
- decision owner và challenger/assessor;
- authority limit và escalation threshold;
- time horizon, expiry và trigger review;
- record/provenance của quyết định;
- feedback khi outcome khác giả định.

Policy chỉ là một thành phần. Nếu mọi exception đều cần CISO ký nhưng CISO không có context,
hoặc team có context nhưng không có authority, hệ thống sẽ tạo approval hình thức.

---

## 3. Ba tầng risk: organization, mission/business và system

Risk cần liên kết giữa các tầng:

| Tầng | Ví dụ quyết định |
|---|---|
| Organization/enterprise | Appetite, capital allocation, concentration risk, strategic supplier |
| Mission/business/process | Fraud tolerance, customer journey, data/safety objective, recovery priority |
| System/service/control | Architecture, control implementation, finding, exception và backlog |

System team có thể đánh giá local vulnerability thấp nhưng enterprise thấy cùng identity
provider phụ thuộc bởi mọi sản phẩm. Ngược lại, board-level “ransomware risk high” không hành
động được nếu không phân rã thành scenario, capability, control và owner.

---

## 4. Operating model và các tuyến trách nhiệm

Một mô hình thực dụng:

- **Management/engineering:** sở hữu objective, risk và control trong hoạt động hằng ngày;
- **Security/risk/compliance functions:** đặt phương pháp, challenge, aggregate và monitor;
- **Independent assurance/audit:** đánh giá độc lập governance/control theo mandate;
- **Executive/board oversight:** đặt appetite, phê duyệt risk vượt ngưỡng và giám sát outcome.

Tên tuyến có thể khác tổ chức; điều quan trọng là không để cùng người tự thiết kế, tự vận
hành, tự chấm và tự chấp nhận control quan trọng mà không có challenge tương xứng.

---

## 5. Bắt đầu từ mission và business objective

Risk không tồn tại độc lập với objective. Với mỗi service/process, ghi:

- customer/mission outcome;
- value stream và critical transaction;
- data/asset và trust dependency;
- availability/integrity/confidentiality/privacy/safety requirements;
- RTO/RPO, fraud/loss và service-level threshold;
- regulatory/contractual duties;
- reputation/ecosystem impact;
- decision owner.

“Bảo vệ database” không đủ. “Ngăn unauthorized change tài khoản nhận tiền làm thất thoát
và bảo đảm khôi phục settlement trước cutoff” tạo context cho control/risk decision.

---

## 6. Inventory nghĩa vụ và nguồn requirement

Requirement có thể đến từ:

- luật/regulation/jurisdiction;
- license, contract, customer commitment;
- industry/payment/insurance requirement;
- internal policy và risk appetite;
- architecture/security baseline;
- threat model/incident/loss;
- supplier/shared-responsibility agreement;
- privacy, safety và resilience objective.

Mỗi obligation record cần source/version/effective date, scope, interpretation owner,
control mapping và evidence expectation. Không copy nguyên văn requirement vào hàng trăm
system; tạo canonical interpretation và track nơi tailoring cần thiết.

---

## 7. Risk appetite, tolerance và capacity

- **Risk capacity:** mức loss/disruption tối đa tổ chức có thể hấp thụ.
- **Risk appetite:** loại/mức risk tổ chức sẵn sàng theo đuổi hoặc giữ để đạt objective.
- **Risk tolerance:** ngưỡng variation cụ thể quanh objective.
- **Risk limit/threshold:** trigger đo được để escalate/action.

Ví dụ “appetite thấp với data breach” quá mơ hồ. Tolerance hành động được hơn:

- không permanent privileged access vào production;
- mọi externally exposed KEV phải mitigated trong X giờ;
- recovery test phải đạt RTO/RPO cho tier-0;
- không supplier đơn lẻ kiểm soát cả identity và recovery path.

Threshold cần owner, measurement method và hành vi khi breach.

---

## 8. Risk taxonomy và tiêu chí nhất quán

Taxonomy giúp tổng hợp nhưng không nên ép mọi scenario thành nhãn chung chung. Có thể phân
loại theo:

- threat source/event;
- business capability/asset;
- impact type: financial, operational, legal, privacy, safety, reputation;
- security property/control domain;
- internal/third-party/systemic/concentration;
- time horizon và velocity;
- treatment/status/authority tier.

Định nghĩa scale likelihood/impact rõ bằng anchor/example. “High” của fraud không tự tương
đương “High” của availability nếu tiêu chí khác.

---

## 9. Viết risk scenario có thể phân tích

Mẫu:

```text
Because of <condition / vulnerability / control gap>,
<threat source> may perform <threat event through path>,
affecting <asset / objective>, resulting in <business impact>.
```

Ví dụ: “Do CI signer dùng credential dài hạn trên shared runner, attacker chiếm repository
workflow có thể ký artifact giả và phát hành tới fleet, gây compromise nhiều tenant và buộc
thu hồi/rebuild toàn bộ.”

Tránh record “Ransomware – High” hoặc “CVE-xxxx – Critical”: chúng thiếu path, asset, impact
và không cho biết control/treatment nào thay đổi risk.

---

## 10. Asset, capability và dependency graph

Risk register cần nối business capability với:

- system/service/data;
- identity/control plane;
- people/process/knowledge;
- supplier/SaaS/cloud/telecom;
- cryptographic/root-of-trust dependency;
- region/facility/network;
- recovery/backup/communication path;
- upstream/downstream customer/partner.

Inventory dạng danh sách bỏ lỡ transitive dependency. Graph cho thấy một DNS/IdP/KMS/CI
provider có thể là concentration risk dù từng service riêng lẻ có risk “medium”.

---

## 11. Threat, vulnerability, control và impact

Phân biệt input:

- **threat source:** actor/event có khả năng gây harm;
- **threat event:** hành động/sự kiện cụ thể;
- **vulnerability/predisposing condition:** điều kiện làm event thành công;
- **control:** thay đổi likelihood/impact/detection/recovery;
- **impact:** harm đến objective/stakeholder;
- **risk:** uncertainty về likelihood và consequence của scenario.

Không nhân công thức `Threat × Vulnerability × Asset` khi các scale ordinal không hỗ trợ
toán học đó. Công thức có thể là mnemonic, không phải model định lượng hợp lệ.

---

## 12. Inherent, current, residual và target risk

| Loại | Ý nghĩa |
|---|---|
| Inherent | Risk giả định chưa xét control trong scope/model đã định |
| Current | Risk với control đang thực sự hoạt động hiện nay |
| Residual | Risk còn lại sau treatment/control cụ thể |
| Target | Mức risk mong muốn sau kế hoạch trong thời hạn |

“Residual = inherent – control score” thường sai vì control tương tác, fail mode và uncertainty.
Mỗi assessment phải ghi control nào được credit và evidence nào chứng minh effectiveness.

Target risk khác acceptance: target là đích; acceptance là quyết định giữ current/residual
risk trong phạm vi/thời hạn cụ thể.

---

## 13. Ước lượng likelihood

Likelihood nên phân rã:

- threat event frequency/capability/intent;
- exposure và opportunity;
- precondition/attacker access;
- exploitability/automation;
- preventive/detective control strength;
- time horizon;
- historical internal/external event;
- uncertainty/data quality.

Không biến “chưa từng xảy ra” thành likelihood thấp nếu telemetry/retention yếu. Với rare
high-impact event, dùng scenario/stress test thay vì chỉ extrapolate lịch sử ngắn.

---

## 14. Ước lượng impact

Impact cần nhìn primary và secondary loss:

- response/forensics/rebuild;
- downtime và lost transaction;
- fraud/data loss/customer harm;
- legal/regulatory/contractual cost;
- notification/support/churn;
- safety/physical/environmental harm;
- supplier/ecosystem contagion;
- strategic/reputation/opportunity cost;
- recovery debt kéo dài.

Tránh double-count cùng loss trong nhiều category. Ghi time horizon, affected population,
currency/range và assumption khi định lượng.

---

## 15. Uncertainty, confidence và data quality

Mỗi estimate cần:

- nguồn và observation date;
- sample/coverage/freshness;
- known blind spot;
- assumption;
- confidence hoặc range;
- sensitivity: input nào làm decision đổi;
- plan thu thêm evidence có đáng chi phí không.

Unknown không bằng zero. Khi uncertainty cao trên crown jewel, có thể chọn precautionary
treatment hoặc time-boxed investigation. Precision giả như `risk = 73.4/100` không tốt hơn
range trung thực nếu input chỉ là phỏng đoán.

---

## 16. Qualitative, semi-quantitative và quantitative

| Phương pháp | Khi phù hợp | Pitfall |
|---|---|---|
| Qualitative | Triage/workshop nhanh | High/Medium không nhất quán |
| Semi-quantitative | Portfolio có scale/weight rõ | Thực hiện phép toán không hợp lệ trên ordinal score |
| Quantitative | Quyết định đầu tư/insurance/loss lớn | Dữ liệu/assumption kém nhưng tạo precision giả |

Chọn phương pháp theo decision, không theo tool. Có thể qualitative cho backlog, quantitative
cho ba treatment option tốn kém và scenario analysis cho tail risk.

---

## 17. Quantitative risk và Open FAIR

Open FAIR cung cấp taxonomy và process để ước lượng frequency/magnitude bằng distribution,
thường biểu đạt thành loss exposure tài chính. Quy trình tốt:

1. xác định scenario/scope/decision;
2. phân rã factors theo taxonomy;
3. dùng internal data, external reference và expert calibration;
4. ghi range/distribution thay single guess;
5. chạy simulation/sensitivity;
6. so treatment cost với risk reduction;
7. review assumption cùng business owner.

Định lượng không làm quyết định tự khách quan. Safety, privacy và legal constraints có thể
không nên quy hết thành tiền; sử dụng multi-criteria decision khi cần.

---

## 18. Aggregation, concentration và systemic risk

Không cộng mọi `High` để ra enterprise risk. Cần nhận diện:

- cùng root cause/control failure;
- shared IdP/cloud/region/DNS/CI/KMS/provider;
- correlated attack/campaign;
- simultaneous recovery resource demand;
- common software/component;
- same key/admin/managed-service plane;
- contractual/ecosystem cascading loss;
- diversification chỉ tồn tại trên giấy.

Một supplier outage ảnh hưởng 30 services không phải 30 independent events. Model correlation
và common-mode failure để tránh đánh giá thấp tail risk.

---

## 19. Emerging risk, horizon scanning và scenario analysis

Risk register không chỉ chứa finding hiện tại. Horizon scanning theo dõi:

- technology/architecture adoption;
- threat actor/campaign/exploit trend;
- regulation/contract/geopolitics;
- supplier/product EOL/acquisition;
- cryptographic transition;
- business expansion/data use;
- workforce/skills dependency;
- climate/physical/infrastructure disruption.

Emerging risk cần hypothesis, indicator, owner và trigger chuyển thành active assessment.
Không biến mọi tin tức thành `High risk`; dùng scenario workshop/tabletop/stress test để xem
objective và control nào bị ảnh hưởng.

---

## 20. Canonical risk register schema

Một risk record hành động được:

```yaml
id: RISK-SC-042
scenario: attacker compromises shared CI signer and distributes malicious artifacts
objectives: [customer-trust, production-integrity]
owner: vp-engineering
scope: production-software-fleet
inherent_assessment: {likelihood: high, impact: severe, confidence: medium}
controls: [short-lived-signing, provenance-verification, admission, revoke-runbook]
current_assessment: {likelihood: medium, impact: severe, confidence: medium}
treatment: isolate-runners-and-enforce-admission
target_date: 2026-10-31
acceptance_authority: risk-committee-tier-1
review_triggers: [signer-change, CI-incident, new-distribution-channel]
evidence_refs: [CTRL-SC-12, TEST-SC-09]
```

Risk register là decision system, không phải archive. Record không owner, treatment hoặc
review trigger là note chứ chưa phải managed risk.

---

## 21. Risk owner, control owner và action owner

- **Risk owner:** chịu accountability với business objective và quyết định treatment/acceptance.
- **Control owner:** bảo đảm control design, vận hành, evidence và improvement.
- **Action/remediation owner:** giao deliverable cụ thể đúng hạn.
- **Assessor/challenger:** đánh giá evidence/conclusion với independence phù hợp.
- **Requirement owner:** giải thích nghĩa vụ/policy intent.

CISO không thể là risk owner cho mọi product risk nếu không sở hữu objective/budget. Security
có thể tư vấn/challenge/escalate; business/system owner phải sở hữu residual impact trong authority.

---

## 22. Control objective, control, implementation và evidence

| Lớp | Ví dụ |
|---|---|
| Objective/outcome | Chỉ artifact từ build path tin cậy được chạy production |
| Control | Admission xác minh provenance/signature theo policy |
| Implementation | Policy engine, signer allowlist, deployment integration |
| Procedure | Rollout/revoke/exception/runbook |
| Evidence | Deny test, deployed coverage, policy revision, alert và revoke drill |

Framework control text không tự là implementation. Một tool cũng không tự là control nếu
không có objective, owner, scope, operating condition và expected outcome.

---

## 23. Control catalog và framework mapping

Tạo canonical internal control catalog rồi map NIST/ISO/contract/customer requirements:

- stable control ID và objective;
- risk/threat addressed;
- scope/applicability/tiering;
- owner/provider/consumer;
- implementation pattern;
- evidence/assessment method;
- frequency/trigger;
- dependencies/failure mode;
- exception protocol;
- mappings có source/version/rationale.

Nhiều-to-nhiều mapping giảm duplicate implementation/evidence. Mapping không chứng minh
requirement đã thỏa; assessor vẫn cần xem semantics, scope và effectiveness.

---

## 24. Baseline và tailoring theo risk

Baseline tạo default theo system/data/trust tier. Tailoring có thể:

- thêm control do threat/obligation;
- tăng assurance/frequency;
- chọn implementation alternative đạt cùng objective;
- đánh dấu not applicable có rationale;
- thay common control bằng system-specific control;
- yêu cầu compensating control;
- điều chỉnh parameter như retention/session/backup interval.

Tailoring không phải xóa control để đạt compliance score. Mọi deviation cần risk rationale,
owner, scope và evidence outcome tương đương hoặc residual-risk decision.

---

## 25. Common, system-specific, hybrid và inherited control

- **Common control:** central provider vận hành cho nhiều systems;
- **System-specific:** chỉ áp cho một system;
- **Hybrid:** phần central, phần consumer;
- **Inherited control:** system dựa vào common control do provider cung cấp.

Inheritance contract phải ghi:

- control portion/provider/consumer responsibility;
- scope/tenant/region được bao phủ;
- evidence và assurance level;
- dependency/SLO/outage mode;
- change/incident notification;
- exception và fallback;
- consumer configuration bắt buộc.

“Cloud/platform đã lo” không đủ. Consumer có thể cấu hình sai hoặc dùng ngoài scope inherited.

---

## 26. Control lifecycle

```text
risk / requirement
    → control objective and design
        → implement + assign owner
            → operate + collect evidence
                → assess design/implementation/effectiveness
                    → remediate / accept / improve
                        → retire / replace with dependency cleanup
```

Control catalog cần version và lifecycle state. Khi retire tool/control, kiểm tra mọi risk,
requirement, system và evidence mapping phụ thuộc. “Mua tool mới” không tự chuyển coverage,
rule, history hay operating knowledge từ control cũ.

---

## 27. Design adequacy, implementation và operating effectiveness

Ba câu hỏi khác nhau:

| Khía cạnh | Câu hỏi |
|---|---|
| Design adequacy | Nếu vận hành như thiết kế, control có giảm scenario/risk đủ không? |
| Implementation correctness | Control có được triển khai đúng scope/config/version không? |
| Operating effectiveness | Trong khoảng thời gian quan tâm, control có chạy và đạt outcome ổn định không? |

Một WAF rule có thể implemented đúng nhưng design không bao phủ origin/private path. Một
backup policy design tốt nhưng job thất bại ba tháng là operating failure.

Assessment conclusion phải nói rõ lớp nào được kiểm chứng, period và limitation.

---

## 28. Evidence có provenance và freshness

Evidence record nên chứa:

- control/objective/assessment ID;
- artifact/config/policy/test version;
- scope/environment/resource identity;
- collection source/method/identity;
- observed/event/ingest time;
- raw evidence hoặc immutable reference;
- expected và observed outcome;
- coverage/limitation/confidence;
- retention/access/integrity;
- reviewer và decision sử dụng evidence.

Screenshot/signed PDF tự nó không chứng minh state hiện tại. Evidence cần bind với effective
system state và freshness phù hợp control volatility.

---

## 29. Assurance plan và independence theo risk

Assurance có nhiều lớp:

- owner self-check/continuous test;
- peer/second-line review;
- independent internal assessment;
- external audit/certification/customer assessment;
- adversary emulation/recovery exercise;
- production telemetry/canary.

Independence và depth theo impact, change, control concentration và prior failure. Không
cần external audit cho mọi unit test; Tier-0 shared identity/backup/control plane cần challenge
mạnh hơn self-attestation.

Assurance plan ghi objective, method `examine/interview/test`, sample, period, assessor,
evidence, frequency và trigger.

---

## 30. Continuous monitoring và ongoing authorization

Continuous không nghĩa scan mọi control mỗi giây. Chọn cadence theo:

- control/state volatility;
- threat velocity;
- impact và concentration;
- evidence collection cost;
- detection/response latency cần thiết;
- change/incident/supplier trigger;
- last assessment confidence.

Ví dụ policy drift kiểm tra mỗi deploy/giờ; access review theo tháng/quý; restore drill theo
risk; architecture review khi significant change.

Authorization/risk decision được duy trì khi evidence còn đủ mới và threshold không breach.
Significant change phải trigger reassessment, không chờ annual cycle.

---

## 31. Findings, deficiency và Plan of Action & Milestones

Finding là observation; deficiency là control/objective chưa đạt; POA&M/treatment plan là
cam kết sửa có quản trị. Record cần:

- source finding/evidence và affected scope;
- control/risk/requirement mapping;
- root cause và systemic instances;
- interim control;
- action owner, deliverables, milestones, dependencies;
- due date/risk lane;
- resources/funding;
- verification/closure criteria;
- residual risk/acceptance link;
- escalation khi trễ.

Không tạo một POA&M khổng lồ “improve security program” hoặc hàng trăm item trùng root cause.
Giữ traceability từ deficiency tới từng instance và outcome.

---

## 32. Risk response: avoid, mitigate, transfer/share và accept

| Response | Ví dụ | Điều không nên nhầm |
|---|---|---|
| Avoid | Dừng feature/market/data use tạo risk | Không phải trì hoãn vô hạn |
| Mitigate | Giảm likelihood/impact bằng control | Không tự xóa residual risk |
| Transfer/share | Contract/insurance/outsourcing | Accountability/reputation thường vẫn còn |
| Accept | Giữ risk trong authority/time/scope | Không phải bỏ qua hoặc suppression |
| Pursue/increase | Chấp nhận thêm risk để đạt opportunity | Vẫn cần appetite/limit/monitor |

Treatment có thể kết hợp nhiều response. Ghi objective, expected risk change, cost, side
effect và uncertainty của từng option.

---

## 33. Treatment plan nối risk với engineering

Một treatment phải chuyển thành capability/deliverable:

```text
risk scenario
    → target risk / control outcome
        → architecture and operating changes
            → program / epic / backlog items
                → milestones + owner + funding
                    → verification + residual reassessment
```

Không dùng ticket “implement zero trust”. Phân rã thành workload identity, policy enforcement,
inventory, migration wave, revoke test và adoption metric cụ thể.

Theo dõi dependency và leading indicator; deadline cuối xanh trong khi milestone đầu đã trễ
là reporting sai.

---

## 34. Exception, waiver, deviation và risk acceptance

Tổ chức nên định nghĩa từ ngữ:

- **exception/deviation:** permission tạm không tuân baseline/policy;
- **waiver:** miễn một requirement theo authority/quy tắc cụ thể;
- **risk acceptance:** quyết định giữ residual risk;
- **false positive/not applicable:** kết luận requirement/finding không áp dụng, có evidence;
- **compensating control:** control khác nhằm đạt objective hoặc giảm risk.

Một exception thường tạo risk acceptance nhưng không phải cùng artifact. Scanner suppression
chỉ thay display/workflow, không có authority để miễn policy hay chấp nhận business loss.

---

## 35. Decision authority và escalation tier

Authority matrix dựa trên:

- residual impact/likelihood và uncertainty;
- business unit/system scope;
- duration;
- legal/regulatory/contractual constraint;
- safety/privacy/customer harm;
- concentration/systemic effect;
- appetite/tolerance breach;
- prior incidents/expired exceptions.

Ví dụ product owner chấp nhận low residual risk trong 30 ngày; VP/risk committee quyết định
high cross-product risk; board giám sát risk vượt appetite hoặc strategic concentration.

Không cho người tạo exposure tự phê duyệt exception vượt authority. Security challenge có
thể bắt buộc nhưng business authority phải rõ.

---

## 36. Acceptance record có lifecycle

Record tối thiểu:

- risk/scenario/control/requirement ID;
- current/residual assessment và confidence;
- scope/asset/tenant/environment/version;
- rationale và alternatives đã xét;
- compensating control/evidence;
- accountable risk owner/approver;
- start/expiry và maximum renewal;
- monitoring/KRI;
- treatment/migration dependency;
- trigger review/escalation;
- stakeholder notification khi cần.

Hết hạn mặc định phải re-evaluate/escalate, không auto-renew. Renewal lặp lại là signal
structural debt/funding/architecture issue cần xử lý ở cấp cao hơn.

---

## 37. Change-driven risk assessment

Trigger review khi:

- business objective/data use/market/jurisdiction đổi;
- architecture/trust boundary/identity/control plane đổi;
- new supplier/SaaS/cloud/AI capability;
- merger/acquisition/divestiture;
- vulnerability/threat/exploit campaign;
- control failure/incident/near miss;
- major version/migration/EOL;
- risk appetite/tolerance/obligation đổi;
- evidence health/coverage suy giảm;
- recovery assumption không còn đúng.

Dùng delta assessment: điều gì mới, path/impact/control nào đổi, risk record/test nào bị ảnh
hưởng. Không làm lại full questionnaire cho mọi commit.

---

## 38. Third-party và supply-chain risk governance

Supplier risk không chỉ questionnaire lúc mua. Lifecycle:

```text
criticality / dependency / data / access assessment
    → due diligence + contract/control requirements
        → onboarding + technical integration validation
            → continuous signal + performance/evidence review
                → incident/change/concentration management
                    → exit / transition / data-access cleanup
```

Ghi shared responsibility, subprocessor/fourth-party, geographic/control-plane dependency,
notification SLA, RTO/RPO, vulnerability/SBOM/VEX, audit right, data return/delete và exit plan.

Chứng nhận nhà cung cấp là evidence có scope/time, không bảo đảm tenant config hoặc current
service behavior.

---

## 39. Compliance là constraint và evidence source

Quản trị compliance tốt:

- inventory obligation/source/version/scope;
- canonical interpretation;
- map tới internal control objective;
- reuse implementation/evidence;
- track gap/exception theo authority;
- monitor change;
- đánh giá effectiveness ngoài “document exists”.

Không được dùng risk acceptance nội bộ để bỏ legal requirement nếu luật không cho phép.
Ngược lại, đạt minimum compliance không có nghĩa risk trong appetite; threat model và
business objective có thể cần control mạnh hơn.

---

## 40. Audit và assurance không nên là sân khấu theo mùa

Audit hiệu quả khi:

- scope/criteria/period/sample rõ;
- auditor có access evidence cần thiết nhưng independence được bảo vệ;
- control owner không tạo artifact giả riêng cho tuần audit;
- evidence đến từ operating workflow;
- finding phân biệt design/implementation/operation;
- management response có root cause/milestone;
- closure được retest;
- systemic theme được aggregate;
- không trả lời mâu thuẫn cho nhiều customer/regulator.

“Audit pass” chỉ hỗ trợ một conclusion trong scope/time cụ thể. Nó không phải bảo hành security
cho toàn enterprise.

---

## 41. Policy, standard, procedure và guideline

| Artifact | Vai trò |
|---|---|
| Policy | Intent, principle, mandate và authority |
| Standard/baseline | Requirement đo được và bắt buộc |
| Procedure/runbook | Cách thực hiện/ứng phó từng bước |
| Guideline/pattern | Cách khuyến nghị, có thể có alternatives |
| Control catalog | Outcome/control/evidence/ownership chuẩn hóa |

Policy nên ngắn, stable và trỏ xuống standard versioned. Procedure gần implementation và
được owner kỹ thuật cập nhật. Mỗi artifact cần owner, approver, scope, effective/review date,
exception path và change communication.

---

## 42. Risk committee và decision cadence

Committee không nên đọc từng ticket. Agenda tập trung:

- appetite/tolerance breach;
- top/new/changing/accepted risks;
- treatment milestone/funding blocker;
- systemic/concentration/shared-control issue;
- expired/repeated exceptions;
- incidents/control failure/assurance signal;
- supplier/obligation change;
- quyết định/owner/deadline cần xác nhận.

Pre-read dùng consistent scenario/evidence/options. Minutes ghi decision, dissent/assumption,
authority, action và review trigger—not chỉ “discussed”.

---

## 43. Báo cáo cho executive và board

Board/executive cần:

- cyber risk liên quan objective/strategy nào;
- trend/velocity và vì sao đổi;
- exposure/current vs target;
- loss/impact ranges và uncertainty;
- treatment options, cost, benefit và trade-off;
- appetite breach/concentration risk;
- management action/funding/accountability;
- assurance confidence và blind spot;
- decision/oversight cần thiết.

Tránh dashboard tool count, CVE count hoặc maturity score không gắn outcome. Dùng một số
scenario trọng yếu và capability/control theme để kể câu chuyện quyết định.

---

## 44. KPI, KRI và KCI

- **KPI:** process/capability performance, ví dụ time-to-verified-remediation.
- **KRI:** mức exposure/risk hoặc proximity tới tolerance, ví dụ privileged standing access.
- **KCI:** control performance/effectiveness, ví dụ % production deploy được provenance verify.

Metric cần:

- decision/use case;
- definition/formula/denominator;
- source/owner/freshness;
- target/tolerance/threshold;
- segmentation theo criticality;
- gaming/side effect;
- action khi breach.

Một metric có thể thuộc loại khác tùy decision. Không tranh nhãn bằng việc làm rõ outcome
và hành động nó hỗ trợ.

---

## 45. Risk aggregation và enterprise reporting

Để aggregate system risks:

1. dùng taxonomy/scenario/scale/time horizon nhất quán;
2. map cùng business objective/capability/dependency;
3. dedup common root cause/control;
4. model correlation/concentration;
5. phân biệt gross/current/accepted/target;
6. giữ uncertainty và source lineage;
7. stage/escalate theo authority;
8. tránh cộng ordinal scores.

Enterprise view phải drill-down được tới system/control/action evidence; system register cũng
phải biết scenario đã được aggregate ở đâu để tránh decision mâu thuẫn.

---

## 46. Incident, loss và near-miss feedback

Sau incident/near miss:

- risk scenario/likelihood/impact assumption nào sai;
- control design hay operation nào fail;
- detection/response/recovery evidence nói gì;
- common control/supplier nào ảnh hưởng systems khác;
- risk acceptance/exception nào liên quan;
- KRI/KCI nào không báo trước;
- loss data nào cập nhật quantitative model;
- treatment/catalog/baseline/test nào cần đổi.

Không chỉ thêm một risk mới; cập nhật existing scenario và parameter/provenance. Track action
tới verification, rồi kiểm tra cùng failure mode ở portfolio.

---

## 47. GRC tooling, automation và OSCAL

Tool hỗ trợ workflow nhưng data model quan trọng hơn UI. NIST OSCAL cung cấp machine-readable
formats cho catalog/profile, system implementation, assessment plan/result và POA&M.

Automation hữu ích:

- sync asset/control/owner metadata;
- evidence collection với provenance;
- mapping và reuse;
- trigger assessment/expiry;
- policy/test result ingestion;
- report/drill-down và API integration.

Không tự động hóa blind attestation hoặc AI-generate evidence không kiểm chứng. Giữ canonical
IDs, schema validation, access control, change history và human decision/approval provenance.

---

## 48. Maturity model thực dụng

| Mức | Đặc trưng | Bước tiếp theo |
|---|---|---|
| 0 – Reactive | Spreadsheet, audit-driven, risk/finding lẫn nhau | Taxonomy, owner và scenario schema |
| 1 – Repeatable | Register/control catalog/exception workflow | Trace risk–control–evidence–action |
| 2 – Risk-driven | Appetite/tiering/assurance plan | Common control và change-triggered review |
| 3 – Continuous | Automated evidence/KRI, ongoing authorization | Aggregate concentration/systemic risk |
| 4 – Adaptive | Quantified options, incident feedback, portfolio optimization | Improve decision quality và resilience |

Maturity không phải số control/tool. Dấu hiệu trưởng thành là decision nhanh hơn, evidence
tốt hơn, accountability rõ hơn và risk outcome cải thiện.

---

## 49. Ví dụ end-to-end: shared CI signer risk

**Objective:** chỉ trusted release được chạy production trên mọi tenant.

**Scenario:** attacker sửa workflow trên shared runner, lấy signing credential dài hạn và
phát hành malicious artifact tới fleet.

**Analysis:** impact severe, likelihood medium/high do untrusted PR path; concentration lớn
vì một signer phục vụ nhiều products; confidence medium vì runner inventory thiếu.

**Controls/treatment:**

1. tách untrusted/trusted job và ephemeral runner;
2. signing bằng workload identity ngắn hạn;
3. provenance bind source/workflow/builder/digest;
4. admission verify claims;
5. deployed digest inventory và revoke/rebuild drill;
6. independent test đường PR không lấy signer;
7. supplier/registry dependency và outage mode review.

**Governance:** VP Engineering là risk owner; platform sở hữu controls; security assess;
milestones được tài trợ; temporary exception scope hai legacy products, hết hạn 60 ngày.
Closure cần evidence fleet coverage, negative tests và revoke drill; residual concentration
risk tiếp tục được board risk committee giám sát.

---

## 50. Checklist, anti-pattern và tài liệu chính thức

### Checklist production

- [ ] Governance xác định decision, input/evidence, authority, escalation và review trigger.
- [ ] Mission/business objectives, obligations, appetite/tolerance và critical dependencies rõ.
- [ ] Risk record viết theo threat event–path–asset/objective–business impact, không chỉ nhãn.
- [ ] Inherent/current/residual/target risk có scope, control credit, confidence và thời gian.
- [ ] Risk owner, control owner, action owner, assessor và requirement owner được tách rõ.
- [ ] Internal control catalog map nhiều framework nhưng giữ objective/semantics/evidence.
- [ ] Common/inherited/hybrid control có provider–consumer contract và outage/exception path.
- [ ] Assurance đánh giá design, implementation và operating effectiveness với depth phù hợp.
- [ ] Findings/POA&M nối root cause, milestone, funding, verification và residual risk.
- [ ] Treatment option nêu expected risk reduction, cost, side effect và uncertainty.
- [ ] Exception/suppression/acceptance/not-applicable là các artifact riêng có authority.
- [ ] Acceptance có scope, owner, expiry, monitoring và trigger; không auto-renew.
- [ ] Change/incident/supplier/obligation signal trigger delta risk assessment.
- [ ] KRI/KPI/KCI có denominator, source, threshold và action; enterprise aggregation xử lý correlation.
- [ ] Tool/OSCAL automation giữ provenance và không thay human accountability.

### Anti-pattern thường gặp

- “Compliance pass nghĩa là risk đã thấp.”
- “CISO sở hữu mọi cyber risk.”
- “Risk = Threat × Vulnerability × Asset” với các thang ordinal tùy ý.
- “Residual risk bằng inherent score trừ control score.”
- “Risk register chỉ cần Risk/Impact/Status màu.”
- “Framework control text là implementation.”
- “Cloud/platform control được inherit nên consumer không cần cấu hình hay test.”
- “Audit evidence là screenshot mới tạo trước audit.”
- “Suppression/waiver/exception/risk acceptance là cùng một thứ.”
- “Insurance hoặc outsourcing đã chuyển toàn bộ accountability.”
- “Cộng mọi system risk score ra enterprise risk.”
- “Continuous monitoring nghĩa là chạy mọi check liên tục.”

### Tài liệu chính thức

- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)
- [NIST CSF 2.0 Core](https://nvlpubs.nist.gov/nistpubs/CSWP/NIST.CSWP.29.pdf)
- [NIST SP 800-37 Rev. 2 – Risk Management Framework](https://csrc.nist.gov/pubs/sp/800/37/r2/final)
- [NIST SP 800-30 Rev. 1 – Guide for Conducting Risk Assessments](https://csrc.nist.gov/pubs/sp/800/30/r1/final)
- [NIST SP 800-53 Rev. 5 – Security and Privacy Controls](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)
- [NIST SP 800-53A Rev. 5 – Assessing Controls](https://csrc.nist.gov/pubs/sp/800/53/a/r5/final)
- [NIST IR 8286 Series – Cybersecurity and Enterprise Risk Management](https://www.nist.gov/news-events/news/2025/02/integrating-cybersecurity-and-enterprise-risk-management-nist-ir-8286)
- [NIST IR 8286B – Prioritizing Cybersecurity Risk for ERM](https://csrc.nist.gov/pubs/ir/8286/b/upd1/final)
- [NIST IR 8286D – Business Impact Analysis for Risk Prioritization](https://csrc.nist.gov/pubs/ir/8286/d/upd1/final)
- [NIST OSCAL – Open Security Controls Assessment Language](https://pages.nist.gov/OSCAL/)
- [ISO 31000:2018 – Risk Management Guidelines](https://www.iso.org/standard/65694.html)
- [The Open Group – Open FAIR Body of Knowledge](https://www.opengroup.org/open-fair)

### Học tiếp

1. [Enterprise Security Architecture & Zero Trust](../architecture/enterprise_security_architecture_zero_trust.md) – capability map, trust zones, policy
   decision/enforcement và transformation roadmap.
2. [Business Continuity, Disaster Recovery & Cyber Resilience](../resilience/business_continuity_disaster_recovery_cyber_resilience.md) – BIA, dependency, recovery
   strategy, crisis coordination và resilience validation.

---

*Cập nhật lần cuối: 2026-08-03.*
