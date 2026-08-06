# Insider Risk Program & Trusted Workforce Operations

> Mục tiêu: giảm khả năng và tác động của harm liên quan người có/đã có trusted access bằng controls phòng ngừa,
> hỗ trợ, phát hiện và ứng phó tương xứng — đồng thời bảo vệ privacy, civil liberties, fairness và trust của workforce.

---

## 1. Insider risk là gì?

NIST mô tả insider threat là khả năng insider dùng authorized access, cố ý hoặc vô ý, gây hại cho operations, assets,
individuals hoặc tổ chức. **Insider risk** đặt threat đó trong likelihood, impact, exposure và uncertainty cụ thể.

```text
trusted / former access + opportunity + event / behavior
    → threat scenario
        → affected people / asset / mission
            → prevention + support + detection + response
                → residual risk + learning
```

“Insider” có thể là employee, contractor, partner, supplier admin, volunteer, intern hoặc former member còn access/knowledge.
Quản risk theo scenario và access path, không gắn nhãn một loại người là nguy hiểm.

## 2. Chương trình không phải hệ thống giám sát nhân viên

Program không nên được định nghĩa bằng:

- thu thập mọi activity “phòng khi cần”;
- một hidden human-risk score;
- đọc nội dung cá nhân không purpose/authority;
- xem anomaly là proof of intent;
- tự động discipline từ tool alert;
- theo dõi productivity trá hình;
- public watchlist hoặc manager rumor;
- chỉ mua user-behavior analytics product.

Surveillance quá mức làm tăng privacy risk, bias, false positive và mất speak-up. Program hiệu quả bắt đầu từ crown jewels,
risk scenarios, least privilege, supportive culture và multidisciplinary due process; monitoring chỉ là một control có giới hạn.

## 3. Phạm vi trusted workforce

Inventory relationship và access:

| Nhóm | Access/risk cần xem |
|---|---|
| Employee | system, data, facility, process, peer trust |
| Contractor/consultant | sponsor, time-bound scope, external device/employer |
| Supplier/MSP | privileged support, remote tooling, subprocessor |
| Partner/customer admin | federation, delegated administration, data exchange |
| Intern/volunteer/temp | short lifecycle, shared environment, supervision |
| Former insider | retained credential, device/data, relationship knowledge |
| Compromised insider | legitimate account/session bị attacker điều khiển |

Scope theo asset/process/privilege và lifecycle; không mặc định mọi người cần cùng monitoring depth.

## 4. Threat và harm taxonomy

Phân theo intent/state và consequence:

- unintentional error hoặc unsafe workaround;
- negligence/reckless policy violation;
- compromised identity/device;
- manipulation/coercion;
- unauthorized disclosure hoặc data theft;
- fraud/conflict of interest;
- sabotage/service degradation;
- intellectual property theft;
- physical safety/workplace violence concern;
- espionage hoặc external collusion;
- misuse sau departure.

Cùng một event như large download có thể là backup hợp lệ, compromised token hoặc malicious collection. Không suy intent từ
event taxonomy; cần context, corroboration và authorized inquiry.

## 5. Program outcomes

Một chương trình cân bằng tạo ra:

- critical assets/processes có owner và protection rõ;
- access/privilege phù hợp need và lifecycle;
- safe work path giảm error/shortcut;
- workforce báo concern/near miss sớm;
- supportive intervention trước khi risk leo thang khi phù hợp;
- signal được triage theo context, quality và threshold;
- case được xử lý nhất quán, lawful và timely;
- harm được contain/recover với minimum collateral impact;
- privacy/fairness/oversight có evidence;
- lessons cải thiện system và culture.

Không tối ưu “số case mở”; mục tiêu là giảm risk và bảo vệ cả organization lẫn people.

## 6. Core principles

- risk-based và asset/mission-centered;
- prevent/support trước, detect/respond khi cần;
- least privilege nhưng đủ để làm việc;
- purpose limitation và data minimization;
- multi-source corroboration, không single-signal guilt;
- human review và proportionate response;
- need-to-know/confidentiality;
- due process, consistency và documentation;
- separation giữa analytics, investigation và employment decision;
- independent oversight “watch the watchers”;
- positive culture/speak-up;
- learn từ incident và near miss.

Principle phải thành gate, data contract và review—not chỉ policy statement.

## 7. Executive sponsor và mandate

Senior official cần authority để:

- approve charter/scope/risk appetite;
- giải quyết conflict giữa security, HR, legal, privacy và business;
- cấp resource và specialist;
- bảo vệ program independence/confidentiality;
- phê duyệt high-impact response theo delegation;
- nhận aggregate risk/oversight report;
- đảm bảo program không bị dùng sai mục đích;
- sponsor culture và reporting.

[CISA Insider Threat Mitigation Guide](https://www.cisa.gov/sites/default/files/2022-11/Insider%20Threat%20Mitigation%20Guide_Final_508.pdf)
khuyến nghị senior official cùng multidisciplinary governance. Charter phải nêu rõ authority **và giới hạn authority**.

## 8. Multidisciplinary hub

Hub/team có thể gồm:

- program lead/risk;
- HR/employee relations;
- legal/compliance;
- privacy, civil rights/civil liberties;
- cybersecurity/IT/data owners;
- physical security/safety;
- fraud/loss prevention;
- ethics/internal audit;
- employee assistance/behavioral specialist khi phù hợp;
- communications/business continuity;
- law enforcement liaison theo nhu cầu.

Không phải mọi thành viên xem mọi dữ liệu. Dùng staged access, need-to-know, quorum/recusal và documented handoff. Hub tích hợp
context và route response; nó không thay authority chuyên môn của HR, legal, safety hoặc incident response.

## 9. Legal và regulatory authority map

Yêu cầu khác theo quốc gia, ngành, union/works council, employment relationship và data type. Trước collection/use:

- xác định lawful basis/authority;
- employment/labor/collective agreement;
- privacy/data protection;
- electronic communication/monitoring law;
- background screening/anti-discrimination;
- health/disability/protected information;
- whistleblower/retaliation protection;
- evidence/investigation/due process;
- cross-border transfer/retention;
- regulator/law-enforcement notification.

Tài liệu này không thay tư vấn pháp lý. Legal/privacy owner phải phê duyệt local implementation và material use-case change.

## 10. Privacy, civil rights và civil liberties

CISA nhấn mạnh program phải quản trust mà không xâm phạm privacy, civil rights hoặc civil liberties. Thiết kế:

- purpose/necessity/proportionality assessment;
- data minimization và aggregation;
- notice/transparency phù hợp;
- access/retention/secondary-use limits;
- fairness/bias review;
- human decision và appeal/correction khi applicable;
- protected activity/characteristic exclusion;
- independent audit/oversight;
- deletion/closure evidence;
- emergency access có retrospective review.

“Security” không phải blank check. Một control giảm insider risk có thể tạo privacy/employment/trust risk mới cần xử lý.

## 11. Policy architecture và transparency

Policy cần nêu:

- purpose/outcomes/scope;
- insider/trusted access terminology;
- roles, authority và decision rights;
- acceptable use/monitoring boundaries;
- reporting/protection against retaliation;
- data sources và allowed use ở mức phù hợp;
- triage/inquiry/investigation distinction;
- confidentiality/record handling;
- response/escalation/due process;
- oversight/audit/complaint;
- exception và review cadence.

Tách public/workforce notice, internal procedure và restricted investigation playbook. Minh bạch đủ để tạo expectation hợp lý,
không công bố chi tiết làm suy yếu control.

## 12. Crown jewels và critical processes

Không thể bảo vệ mọi asset như nhau. Xác định:

- critical data/IP/model/source code;
- payment/settlement/financial process;
- privileged identity/trust plane;
- safety/OT/facility;
- customer records/service;
- signing/release/build system;
- merger/strategy/legal material;
- recovery/backup/incident capability;
- people/role then chốt.

Map owner, authorized population, business impact, access path, supplier, monitoring/evidence và recovery. “Sensitive” chung
chung không đủ để chọn controls hoặc triage priority.

## 13. Scenario-based risk assessment

Viết scenario:

```text
actor / access state
    → action / event under conditions
        → asset / process affected
            → business / people harm
                → existing controls + uncertainty
```

Ví dụ: departing engineer còn personal token và local clone, exfiltrate proprietary source before effective revoke, gây IP
loss và customer trust impact. Phân tích likelihood/impact range, opportunity, detectability, response options và residual risk.

Không dùng generic “disgruntled employee” làm risk statement; nó stereotype và không chỉ ra control path.

## 14. Threat modeling trusted access

Với từng critical process, hỏi:

- ai có direct, inherited, delegated hoặc emergency access;
- access nào persistent/anonymous/shared;
- ai có thể approve và execute cùng transaction;
- data có thể copy/export/print/chụp không;
- control plane/logging có thể sửa/xóa không;
- remote/vendor/offline path nào tồn tại;
- failure/recovery path có bypass không;
- former access/session/key còn hiệu lực bao lâu;
- collusion cần bao nhiêu người;
- compromised account giống legitimate action ra sao.

Threat model opportunity/capability, không phán đoán tính cách của người giữ access.

## 15. Positive deterrence và organizational trust

Deterrence không chỉ là punishment. Tăng legitimate commitment bằng:

- fair treatment và consistent policy;
- meaningful work/recognition;
- usable secure process;
- grievance/conflict channel;
- manager support và workload hợp lý;
- help-seeking không stigma;
- clear consequences và visible control;
- early resolution của workplace issue;
- respectful onboarding/offboarding;
- leadership accountability.

SEI đưa positive incentives vào nghiên cứu insider risk. Trust không thay access control; nó làm giảm grievance/shortcut và
tăng early reporting, bổ sung defense-in-depth.

## 16. Security culture và bystander reporting

Workforce cần biết:

- concern nào nên báo;
- báo qua channel nào;
- emergency khác non-urgent ra sao;
- không tự điều tra/đối đầu;
- giữ confidentiality thế nào;
- good-faith report được bảo vệ;
- malicious/retaliatory report có consequence;
- program phản hồi/closure ra sao.

Không dạy checklist “đặc điểm người nguy hiểm” dễ tạo bias. Tập trung observable risk-relevant activity/context và immediate
safety behavior. Đọc [Security Culture & Human Risk](security_culture_human_risk_behavior_engineering.md) cho just culture.

## 17. Supportive intervention và employee assistance

Một concern có thể được giảm bằng hỗ trợ trước investigation, tùy context/authority:

- manager/HR conversation;
- conflict/grievance resolution;
- workload/role adjustment;
- financial/wellbeing assistance hợp pháp;
- employee assistance/referral;
- temporary access adjustment;
- leave/safety plan;
- retraining/supervision;
- clear expectation/follow-up.

Không chẩn đoán sức khỏe tâm thần từ telemetry hoặc equate distress với maliciousness. Protected health information chỉ được
truy cập/chia sẻ theo authority và need-to-know; safety và dignity cùng là outcomes.

## 18. Pre-employment và onboarding

Tailor screening theo role/risk/law:

- identity/qualification/reference verification;
- conflict/eligibility disclosure;
- background checks khi lawful/proportionate;
- consent/notice và dispute process;
- vendor screening responsibility;
- role/access prerequisites;
- confidentiality/IP/acceptable-use clarity;
- reporting/support channels;
- manager sponsorship;
- baseline access không vượt need.

Screening là point-in-time signal, không bảo đảm future trustworthiness. Tránh overcollection hoặc blanket checks không liên quan
job; onboard bằng expectation rõ và secure workflow.

## 19. Joiner–Mover–Leaver operations

JML là transaction xuyên HR, identity, application, physical và supplier systems:

```text
authoritative event
    → approve role / access delta
        → provision + verify effective state
            → monitor / review
                → revoke + reconcile + close
```

Mover phải remove quyền cũ trước/đồng thời add quyền mới; temporary privilege có expiry. Leaver đo tới effective deny trên
session, local account, token, key, SaaS, VPN, facility và downstream system—not chỉ `disabled` trong HR/IdP.

## 20. High-risk transition và separation

Một số event tăng opportunity/uncertainty: resignation, termination, role removal, M&A, contract end, dispute hoặc admin transfer.
Response theo individual scenario, không blanket suspicion:

- plan HR/legal/manager/security coordination;
- inventory access, device, data, delegated ownership;
- preserve continuity/handoff;
- time-bound access adjustment;
- revoke session/token/key/physical access;
- return asset và reconcile export/share;
- respectful communication/escort khi justified;
- partner/customer contact transition;
- post-event monitoring có authority và expiry.

Timing/notification phải cân bằng safety, fairness, legal duty và business continuity.

## 21. Least privilege và just-in-time access

Giảm opportunity bằng:

- role/task-scoped entitlement;
- JIT/JEA/PIM và approval;
- short session/token/credential;
- separate admin identity/workstation;
- resource/action/context policy;
- periodic/event-driven review;
- deny/revoke latency target;
- break-glass with audit/review;
- orphan/shared/local account elimination;
- effective permission analysis.

Least privilege không nghĩa làm job bất khả thi. Friction quá mức tạo credential sharing và shadow path; cung cấp fast safe
path và support.

## 22. Segregation of duties và dual control

Áp dụng nơi single person có thể tạo material harm:

- create vendor + release payment;
- develop + approve + sign release;
- grant privilege + erase audit;
- initiate + authorize high-value transfer;
- backup + destroy recovery copies;
- investigate + decide discipline.

Kiểm collusion, emergency override, reviewer independence và rubber-stamping. Dual control chỉ hiệu quả nếu hai actor có
information, time và authority để challenge; log hai click không chứng minh independent review.

## 23. Data protection và exfiltration resistance

Defense-in-depth:

- classify/owner/need-to-know;
- row/object/action-level authorization;
- managed endpoint/browser/workspace;
- approved export/share path;
- volume/rate/context guardrail;
- watermark/tag/rights management khi phù hợp;
- removable media/print controls theo risk;
- egress/cloud app governance;
- encryption/key separation;
- data lineage/audit;
- rapid revoke/recall và legal hold.

Không block mọi copy nếu business cần. Thiết kế safe export có purpose, approval, expiry và evidence; measure bypass/unknown.

## 24. Physical security và safety interface

Insider risk có thể liên quan facility/people/equipment. Tích hợp:

- badge/access zoning và visitor escort;
- key/media/equipment inventory;
- tailgating/reporting;
- sensitive-area two-person rule;
- after-hours access context;
- workplace violence/safety response;
- emergency services/contact;
- continuity/evacuation;
- CCTV/access log governance;
- offboarding/reconciliation.

Safety concern cần route riêng với trained authority; cybersecurity analyst không tự đánh giá threat of violence. Emergency
action theo local plan và law.

## 25. Contractor, supplier và partner risk

Contract/shared responsibility cần:

- named sponsor và business owner;
- personnel screening/training requirements phù hợp;
- scoped, time-bound identity/access;
- managed support channel/tool;
- subcontractor visibility;
- logging/evidence/notification;
- incident/investigation cooperation;
- data/location/use restrictions;
- personnel change/offboarding SLA;
- return/delete/revoke/exit assistance;
- audit/remedy.

Supplier admin có thể là insider đối với service của bạn. SSO không tự xử lý vendor local/emergency account hoặc downstream copy.

## 26. Signal design bắt đầu từ scenario

Không bắt đầu bằng “tool thu được gì”. Với mỗi signal, ghi:

- scenario/control objective;
- population và scope;
- data source/fields;
- expected legitimate behavior;
- detection hypothesis;
- context/corroboration cần;
- sensitivity/false-positive trade-off;
- owner/triage action;
- retention/access/privacy;
- validation và retirement.

Signal không dẫn tới một authorized action hoặc learning decision có thể chỉ tạo surveillance cost. Unknown coverage phải được
báo, không coi không có alert là không có risk.

## 27. Technical telemetry

Nguồn có thể gồm, theo lawful scope:

- identity/authentication/session/privilege;
- data access/export/share;
- endpoint/device/removable media;
- email/collaboration/cloud app;
- code/repository/build/signing;
- network/egress;
- physical access;
- admin/config/audit changes;
- JML/access-review systems;
- DLP/CASB/UEBA alerts.

Giữ provenance, clock, identity correlation, coverage và tamper protection. Content inspection nhạy cảm hơn metadata và cần
purpose/authority cao hơn; không thu nội dung mặc định vì “có thể hữu ích”.

## 28. Contextual và organizational signals

Context có thể đến từ:

- role/privilege/asset ownership;
- approved business process/change window;
- travel/remote work;
- HR lifecycle event;
- support/grievance hoặc manager concern;
- declared conflict/secondary employment;
- training/authorization prerequisite;
- supplier assignment;
- incident/compromise intelligence.

Mỗi source có owner, reliability, sensitivity và use restriction. Protected characteristic, medical detail, union activity,
whistleblowing hoặc lawful dissent không được biến thành risk proxy. Context dùng để giảm ambiguity, không để profile con người.

## 29. Phân biệt compromised account và malicious insider

Một account dùng credential đúng nhưng hành vi lạ có thể do attacker. Triage song song:

- source/device/session/token evidence;
- phishing/malware/credential exposure;
- impossible/novel access context;
- user confirmation qua independent safe channel;
- concurrent identity alerts;
- action phù hợp task/approval không;
- session/key revoke test;
- scope downstream.

Contain identity compromise nhanh mà không cần kết luận intent. Gắn nhãn malicious insider quá sớm làm chậm incident response,
tổn hại cá nhân và bias investigation.

## 30. Analytics và risk score: giới hạn

Composite “employee risk score” có vấn đề:

- ordinal/heterogeneous signals bị cộng tùy ý;
- base-rate thấp tạo nhiều false positive;
- role/exposure khác nhau;
- missing data bị hiểu là clean;
- protected/activity proxies;
- automation bias;
- score drift và vendor opacity;
- Goodhart/gaming;
- khó appeal/correct.

Ưu tiên scenario-specific rules/models, component evidence, confidence và human review. Không dùng score đơn làm căn cứ adverse
action. Model phải có validation, bias review, version, access, retention và stop criteria.

## 31. Correlation, provenance và data quality

Trước khi correlate:

- resolve identity nhưng giữ ambiguity;
- đồng bộ time/timezone;
- biết scope/coverage/gap;
- phân biệt event time và ingest time;
- version parser/rule/model;
- deduplicate retry/mirror;
- bảo vệ source integrity;
- giữ lineage và query/audit;
- mark unknown/not applicable;
- kiểm shared device/service account.

Hai weak signals không tự thành strong evidence nếu cùng một faulty source. Correlation phải mô tả mechanism, không chỉ tăng score.

## 32. Detection triage

Triage an toàn:

1. xác minh alert/data quality/scope;
2. kiểm approved activity/change window;
3. đánh giá asset/action/impact/urgency;
4. tìm compromise/system error alternative;
5. thu context tối thiểu theo authority;
6. decide close/enrich/contain/refer;
7. document rationale/confidence;
8. protect confidentiality;
9. set review/expiry;
10. feed false positive/system gap.

Analyst không liên hệ manager/subject tùy ý nếu có thể gây retaliation, tipping-off hoặc safety issue; dùng approved playbook.

## 33. Intake và case classification

Nguồn intake: workforce report, technical alert, HR/security referral, audit, supplier/customer, incident hoặc law enforcement.
Record tối thiểu:

- allegation/observable facts, tách opinion;
- reporter/source/confidentiality;
- time/asset/person/relationship;
- immediate safety/operational concern;
- data quality/unknown;
- conflict/retaliation concern;
- authority và owner;
- initial classification/severity;
- actions/decision log;
- retention/closure.

Không mở full investigation cho mọi report. Screening/triage/inquiry/investigation là các state có threshold khác nhau.

## 34. Threshold và proportionality

Escalation phụ thuộc:

- credibility/corroboration;
- imminence/urgency;
- potential impact/crown jewel;
- access/opportunity;
- reversible containment option;
- safety/legal duty;
- privacy/collateral impact;
- prior verified pattern, không rumor;
- confidence/unknown;
- decision authority.

Định nghĩa threshold và required approver; emergency action có retrospective review. Proportionality nghĩa dùng mức intrusion/
response nhỏ nhất đủ quản risk, rồi tăng khi evidence/impact yêu cầu.

## 35. Evidence preservation và chain of custody

Khi inquiry được authorize:

- legal/privacy scope và hold;
- identify volatile/authoritative sources;
- collect forensic copy/metadata phù hợp;
- hash, time, collector, tool/version;
- preserve original, work trên copy;
- access log/need-to-know;
- secure storage/transfer;
- document gaps/limitations;
- coordinate HR/legal/law enforcement;
- retention/disposition.

Không tự ý mở thiết bị/tài khoản cá nhân hoặc vượt authority. Evidence quality và admissibility requirements tùy jurisdiction/case.

## 36. Investigation plan

Plan trước khi mở rộng collection:

- allegation/questions/hypotheses;
- applicable authority/policy;
- investigator và independence/conflict;
- scope/time/population/data sources;
- alternative explanations;
- collection/interview sequence;
- containment/safety trigger;
- communication/need-to-know;
- decision standard và approver;
- subject/reporter rights;
- timeline/review gate;
- closure/retention.

Không dùng fishing expedition. Mỗi collection step cần relevance, necessity và proportionality; scope creep phải reauthorize.

## 37. Interview và cross-functional coordination

Interview do trained/authorized personnel thực hiện. Chuẩn bị:

- objective và known facts/unknown;
- role/legal/HR representation requirements;
- order để tránh contamination/retaliation;
- neutral, non-accusatory questions;
- accurate note/recording authority;
- interpreter/accessibility;
- safety plan;
- evidence preservation;
- follow-up/corroboration;
- confidentiality expectation.

Không hứa confidentiality tuyệt đối nếu không thể. Analyst kỹ thuật cung cấp fact/context, không tự đưa employment conclusion.

## 38. Containment và business continuity

Options theo risk:

- revoke/rotate session/token/key;
- reduce/JIT privilege;
- isolate device/account;
- block export/share/destination;
- dual approval hoặc hold transaction;
- preserve data/log;
- change duty/supervision theo authority;
- protect people/facility;
- notify partner/bank/provider;
- activate continuity/recovery.

Mỗi action có owner, expected effect, collateral impact, validation, expiry và rollback. Contain không đồng nghĩa kết luận guilt;
technical precaution có thể cần khi account compromise hoặc uncertainty cao.

## 39. Safety và threat-management path

Concern về self-harm, violence hoặc immediate physical danger phải đi qua trained safety/threat-management/emergency process,
không chỉ cyber case queue. Program cần:

- emergency contact/authority rõ;
- multidisciplinary threat assessment;
- duty-to-warn/protect guidance theo law;
- facility/people continuity plan;
- minimal information sharing;
- professional support/referral;
- secure documentation;
- post-event care/review.

Không xây profile dựa trên diagnosis, personality hoặc stereotype. Observable concern cần professional contextual assessment.

## 40. External escalation

Escalate theo criteria và counsel:

- imminent safety/emergency services;
- suspected crime/law enforcement;
- regulatory/contract notification;
- data breach/privacy authority/customer;
- fraud/bank/payment rail;
- national security/counterintelligence khi applicable;
- insurer/external counsel/forensic provider;
- supplier/partner coordination.

Ghi ai có authority, preservation/privilege, timing, approved facts và communication owner. Không overstate certainty hoặc
chia sẻ personal data vượt need/purpose.

## 41. Due process và decision segregation

Tách:

- signal generation;
- triage/inquiry;
- investigation/fact finding;
- risk/safety containment;
- HR/employment decision;
- legal/criminal decision;
- appeal/review;
- program oversight.

Một team/tool không nên vừa tạo score, kết luận intent và tự quyết discipline. Decision record nêu evidence, standard,
alternative, conflicts, approver và rights. Consistency kiểm bằng case review nhưng không máy móc bỏ context.

## 42. Case data governance

Case data nhạy cảm cần:

- purpose-specific case ID;
- separate restricted system;
- role/attribute-based access;
- no broad search/export;
- encryption/key separation;
- immutable access/audit log;
- retention theo case/legal need;
- hold và defensible deletion;
- correction/annotation;
- redaction/aggregation;
- vendor/subprocessor controls;
- break-glass retrospective review.

Không đưa raw case data vào general analytics, training hoặc AI model nếu không có new purpose/authority/risk assessment.

## 43. Program metrics

Đo outcome và safeguards:

| Chiều | Ví dụ |
|---|---|
| Prevention | critical access coverage, SoD/JIT, JML revoke latency |
| Reporting | time-to-report, good-faith channel use, retaliation concern |
| Detection | scenario coverage, quality/unknown, time-to-triage |
| Response | time-to-contain, impact/recovery, overdue actions |
| Quality | false positive, reopened/reclassified, evidence gaps |
| Fairness/privacy | access violations, over-retention, cohort disparity, appeals |
| Support | early intervention/referral outcome ở aggregate phù hợp |
| Learning | recurring root cause/control improvement |

Case count tăng có thể do reporting tốt hơn; không mặc định program xấu hơn.

## 44. False positive, bias và harm review

Review:

- alert rate theo role/exposure/device/geography;
- false positive và escalation disparity;
- proxy protected characteristic;
- remote/shift/accessibility effect;
- reporter/manager bias;
- data coverage imbalance;
- analyst consistency;
- adverse action/appeal outcome;
- tool/model drift;
- chilling effect/trust signal.

Small cohorts cần privacy protection và statistical caution. Khi harm/false-positive vượt benefit, sửa/giới hạn/tắt signal;
không giữ chỉ vì vendor quảng cáo “AI risk detection”.

## 45. Exercises và readiness validation

Tabletop/scenario nên test:

- report/intake/triage;
- compromised account vs malicious ambiguity;
- HR/legal/privacy/safety decision;
- evidence hold/collection;
- rapid access containment;
- supplier/remote worker;
- business continuity;
- communication/external escalation;
- due process/confidentiality;
- recovery/lessons.

Dùng safe synthetic data và authorized participants. Đánh giá decision latency, role clarity, evidence gap và collateral impact;
không mô phỏng bằng cách bí mật nhắm cá nhân thật.

## 46. Case closure và lessons learned

Closure gồm:

- disposition và confidence;
- actions/approvals;
- affected asset/person/process;
- access/data/evidence reconciliation;
- required notification/support;
- retention/deletion date;
- reporter/subject feedback khi appropriate;
- control/root-cause actions;
- recurrence search ở mức lawful;
- metrics/model update;
- independent review cho high-impact case.

Học cả false positive và near miss. Đóng case không có nghĩa mọi allegation đúng/sai tuyệt đối; ghi unknown/limitations.

## 47. Vendor/tool governance

Trước mua UEBA/DLP/employee-monitoring/case platform, đánh giá:

- use cases và prohibited uses;
- data fields/content/access;
- model/rule explainability;
- customer-controlled threshold;
- bias/validation evidence;
- human review/workflow;
- tenant/region/subprocessor;
- retention/export/delete;
- admin/support access;
- incident/audit/contract remedy;
- integration/exit và data portability.

Không để vendor default quyết định legal/privacy boundary. Pilot bằng synthetic/limited data và đo actionable value, false
positive, analyst burden, privacy harm trước scale.

## 48. Ví dụ end-to-end: departing engineer và source code

**Scenario:** engineer sắp rời công ty, còn repo token/local clone và truy cập signing workflow.

| Lớp | Thiết kế |
|---|---|
| Prevention | least privilege, JIT signing, managed repo/device, code/IP classification |
| Lifecycle | HR event → access inventory → timed revoke → downstream reconciliation |
| Culture/support | respectful process, handoff, clear IP/export rules, speak-up |
| Signal | unusual bulk export + new destination + role/context, không single event guilt |
| Triage | verify approved migration, account compromise và data quality |
| Response | preserve evidence, limit token/export, maintain release continuity |
| Governance | HR/legal/privacy/security review, need-to-know và due process |
| Closure | reconcile clones/tokens/devices, determine facts, delete/retain case data |
| Learning | fix personal token, local clone, offboarding latency và manager handoff gaps |

Không tự động kết luận malicious từ resignation hoặc download; containment và inquiry theo threshold/proportionality.

## 49. Lộ trình triển khai 90 ngày

**Ngày 1–30 — Charter và scope**

- sponsor, multidisciplinary hub, authority/limits;
- legal/privacy/fairness principles;
- crown jewels và top scenarios;
- inventory policies, data sources, controls và reporting.

**Ngày 31–60 — Design controls và workflow**

- JML/privilege/supportive prevention gaps;
- intake/triage/case/containment/due-process states;
- signal/data contracts và restricted case store;
- metrics, oversight và exercise scenario.

**Ngày 61–90 — Pilot và validate**

- pilot 1–2 scenario với limited/synthetic data;
- tabletop cross-functional response;
- đo quality, false positive, privacy/analyst burden;
- fix controls và approve staged roadmap.

## 50. Checklist, anti-pattern và tài liệu tham khảo

### Checklist production

- [ ] Charter nêu outcome, scope, authority, limits và independent oversight.
- [ ] Multidisciplinary hub có HR/legal/privacy/security/safety/business roles.
- [ ] Crown jewels và scenarios quyết định controls/data—not tool availability.
- [ ] Prevention gồm culture/support/JML/least privilege/SoD/safe workflow.
- [ ] Signal có purpose, provenance, corroboration, retention và authorized action.
- [ ] Analytics không tự suy intent hoặc quyết adverse action.
- [ ] Intake→triage→inquiry→investigation→closure có threshold và due process.
- [ ] Case data tách biệt, need-to-know, audit và defensible deletion.
- [ ] Metrics đo privacy/fairness/false positive cùng prevention/response outcome.
- [ ] Exercise và lessons learned cải thiện system, không tạo secret surveillance.

### Anti-pattern cần tránh

- Đồng nhất insider risk program với employee monitoring/UEBA tool.
- Gắn nhãn “high-risk person” từ một anomaly, rumor hoặc lifecycle event.
- Thu mọi data trước rồi tìm purpose sau.
- Một team vừa tạo score, điều tra và quyết discipline.
- Dùng health, protected activity hoặc demographic làm risk proxy.
- Alert volume/case count được báo như program effectiveness.
- Offboarding chỉ disable IdP, bỏ session/key/local/SaaS/physical access.
- Điều tra mở rộng không scope, authority, review gate hoặc deletion.

### Nguồn chính thức và nghiên cứu thực hành

- [CISA Insider Threat Mitigation Guide](https://www.cisa.gov/sites/default/files/2022-11/Insider%20Threat%20Mitigation%20Guide_Final_508.pdf) — program governance, legal/privacy, critical assets và mitigation.
- [CISA Insider Risk Mitigation Program Evaluation](https://www.cisa.gov/insider-risk-self-assessment-tool) — self-assessment readiness/maturity.
- [CISA Insider Threat Resources](https://www.cisa.gov/topics/physical-security/insider-threat-mitigation/resources-and-tools) — onboarding, HR, reporting và training resources.
- [NITTF Mission and Resources](https://www.dni.gov/index.php/ncsc-how-we-work/ncsc-nittf) — deter, detect, mitigate và program resources.
- [NITTF Insider Threat Program Maturity Framework](https://www.dni.gov/files/NCSC/documents/features/NITTF_MaturityFramework_web.pdf) — capability/maturity attributes.
- [NIST SP 800-53 Rev.5](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final) — integrated security/privacy control catalog.
- [NIST SP 800-53A Rev.5](https://csrc.nist.gov/pubs/sp/800/53/a/r5/final) — assessment procedures cho security/privacy controls.
- [SEI Common Sense Guide, 7th Edition](https://www.sei.cmu.edu/library/common-sense-guide-to-mitigating-insider-threats-seventh-edition/) — 22 practices dựa trên hơn 3.000 cases.

### Học tiếp

1. [Security Policy, Standards & Exception Lifecycle Engineering](security_policy_standards_exception_lifecycle_engineering.md) — policy architecture,
   control objectives, enforceability, waiver, evidence và retirement.
2. [Security Compliance Engineering & Continuous Control Assurance](security_compliance_engineering_continuous_control_assurance.md) — obligation mapping,
   control testing, evidence automation, issue lifecycle và audit readiness.

---

*Cập nhật lần cuối: 2026-08-03.*
