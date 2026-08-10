---
title: "Security Risk Transfer, Cyber Insurance & Contractual Allocation"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-03
last_verified: null
version_scope: "unspecified"
source_count: 7
---
# Security Risk Transfer, Cyber Insurance & Contractual Allocation

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu: thiết kế risk transfer như một phần của risk treatment—map scenario tới policy/hợp đồng,
> hiểu phần tổ chức vẫn giữ, chuẩn bị claims evidence và không nhầm chuyển giao chi phí với chuyển giao accountability.

> Đây là hướng dẫn security/risk engineering, không phải tư vấn pháp lý, bảo hiểm, thuế, kế toán hoặc sanctions.
> Policy wording, endorsements, hợp đồng, facts, capacity của counterparty và luật áp dụng mới quyết kết quả thực tế.

---

## 1. Risk transfer thực sự chuyển điều gì?

Risk transfer thường chuyển hoặc chia sẻ một phần hậu quả tài chính:

- insurer hoàn trả/chi trả loss thuộc coverage;
- supplier nhận một số liability theo hợp đồng;
- customer giữ một số responsibilities;
- captive hoặc risk pool hấp thụ volatility;
- indemnitor bảo vệ một party trước defined claims.

Nó không làm event biến mất, không khôi phục trust tự động và không xóa nghĩa vụ đối với customer, regulator, workforce hoặc society.

## 2. Accountability không thể “outsource” hoàn toàn

Tổ chức vẫn phải:

- phòng ngừa và giảm harm hợp lý;
- phát hiện, response và recover;
- thực hiện notification/disclosure bắt buộc;
- duy trì business continuity;
- đưa ra truthful representations;
- quản lý supplier/customer responsibilities;
- tài trợ phần loss không được chuyển;
- học từ incident/claim.

Insurance là financial resilience layer, không phải compensating control cho security program yếu.

## 3. Risk-treatment stack

```text
avoid / change activity
    → reduce frequency
        → reduce magnitude + improve recovery
            → transfer/share eligible financial loss
                → retain deductible, exclusions, limits and non-financial harm
                    → fund residual + monitor assumptions
```

Không mua policy trước khi biết scenario nào cần transfer. Control, contract và insurance bổ sung nhau; không phải ba bản sao của cùng một protection.

## 4. Governance và decision rights

Vai trò cần phối hợp:

- board/executive đặt risk appetite và capital tolerance;
- enterprise risk/finance sở hữu financing strategy;
- risk manager/broker điều phối market/policy program;
- legal/counsel diễn giải wording và contracts;
- security cung cấp scenarios, control facts và incident evidence;
- privacy/compliance xác định obligations;
- treasury/accounting quản cash-flow/loss records;
- procurement/business owner quản counterparty;
- insurer/underwriter/claims professionals thực hiện vai trò theo policy.

Không để một team tự trả lời application hoặc tự cam kết coverage ngoài authority.

## 5. Bắt đầu từ scenario

Mỗi scenario cần map:

```text
event/pathway
first-party loss components
third-party claims / regulatory consequences
maximum plausible and expected ranges
timing / cash-flow need
existing controls
policy / contract response hypothesis
retained gaps + non-financial harm
```

Ví dụ “ransomware” quá rộng: encryption, data theft, extortion, outage, restoration, fraud và supplier outage có thể đi qua coverage khác nhau.

## 6. Loss taxonomy

| Nhóm | Ví dụ |
|---|---|
| Response | forensics, counsel, notification, crisis support |
| Restoration | rebuild, data/software recovery, hardware nếu covered |
| Interruption | lost income, extra expense, waiting period |
| Cybercrime | social engineering, funds transfer, telecom fraud |
| Extortion | negotiator, payment, recovery-related services nếu lawful/covered |
| Liability | privacy/security claims, defense, settlement/judgment |
| Regulatory | investigation/defense và amounts insurable nếu được phép |
| Dependency | supplier/cloud/MSP interruption |
| Media/technology | content/IP hoặc service-performance claims |

Taxonomy tránh double count và giúp đọc đúng policy section.

## 7. Insurability screen

Một loss có thể không chuyển được vì:

- policy không grant coverage;
- exclusion/condition/endorsement áp dụng;
- entity/territory/period không thuộc scope;
- amount không legally insurable;
- loss khó đo hoặc không đủ evidence;
- event đã known trước inception;
- limits/sublimits đã cạn;
- counterparty không đủ khả năng chi trả;
- market không cung cấp capacity hợp lý;
- public-policy/law giới hạn transfer.

Giữ legal/insurance advice theo jurisdiction; không coi “insurable” là thuộc tính cố định của một loss label.

## 8. Coverage inventory

Lập inventory toàn program:

```text
policy / insurer / number / period
named insureds / additional insureds
territory / jurisdiction
coverage parts + triggers
limits / aggregates / sublimits
retention / waiting period / coinsurance
exclusions + endorsements
notice / consent / panel requirements
other insurance / priority
broker / claims contacts
```

Include cyber, crime, property, general liability, technology E&O, D&O, kidnap/ransom và relevant specialty policies.

## 9. First-party coverage

First-party coverage có thể phản ứng với loss của chính insured, tùy wording:

- breach/incident response;
- business interruption/extra expense;
- digital asset restoration;
- cyber extortion;
- cybercrime/funds transfer;
- reputational or dependent loss nếu expressly included;
- crisis management;
- reward hoặc hardware replacement trong một số products.

Không suy ra coverage từ tên marketing. Đọc insuring agreement, definitions, conditions, exclusions và endorsements cùng nhau.

## 10. Third-party coverage

Third-party coverage có thể liên quan:

- privacy/security liability;
- defense và settlement/judgment;
- regulatory investigation/defense;
- media liability;
- technology errors and omissions;
- payment-card assessments theo wording;
- contractual liability trong phạm vi policy chấp nhận.

Phân biệt duty to defend, defense within/outside limits và quyền chọn counsel. Nghĩa vụ tự nguyện trong contract có thể không tự được covered.

## 11. Coverage trigger

Trigger quyết policy nào phản ứng:

- occurrence trong policy period;
- claim first made và reported;
- discovery của loss;
- security/privacy event được định nghĩa;
- outage bắt đầu sau waiting period;
- wrongful act dẫn tới claim;
- dependent service-provider failure.

Claims-made policy đặc biệt nhạy với notice, retroactive date và prior/related acts. Team phải đọc exact wording, không dùng tên trigger theo trí nhớ.

## 12. Policy period, retroactive date và continuity

Kiểm:

- inception/expiration và timezone;
- retroactive/prior-acts date;
- discovery/extended reporting period;
- continuity date;
- renewal gaps;
- run-off/tail khi M&A/divestiture;
- known-circumstance notice;
- related/interrelated events qua nhiều kỳ.

Incident có dwell time dài có thể chạm nhiều mốc. Dựng timeline evidence trước khi kết luận policy year nào áp dụng.

## 13. Limits và aggregate

Limit có thể là:

- per claim/event;
- per coverage part;
- annual aggregate;
- shared aggregate giữa entities;
- aggregate của tower;
- reinstatement nếu expressly provided.

Một limit lớn trên declarations không có nghĩa toàn bộ scenario nhận số đó. Track erosion bởi defense cost, prior claims, shared coverage và sublimits.

## 14. Retention, deductible và self-insured layer

Retention là phần insured tài trợ trước hoặc cùng coverage theo wording. Thiết kế dựa trên:

- loss frequency distribution;
- cash-flow/liquidity;
- claims handling capacity;
- tax/accounting treatment theo advice;
- premium savings;
- aggregate retained loss;
- business units/entities sharing layer;
- tolerance với volatility.

Retention cao không chỉ giảm premium; nó chuyển workload, evidence và cash requirement về tổ chức.

## 15. Sublimits

Sublimit thường xuất hiện ở coverage có exposure riêng, ví dụ dependent interruption, social engineering,
cyber extortion, restoration, regulatory hoặc reputational components—nhưng không có danh sách chung cho mọi policy.

Map từng scenario component tới:

```text
gross loss → applicable sublimit → retention → coinsurance → estimated net recovery
```

Đừng dùng overall limit để model một component bị sublimit thấp hơn.

## 16. Waiting period và period of restoration

Business interruption thường phụ thuộc:

- qualifying interruption;
- waiting period/franchise;
- restoration period definition;
- measurement of net income/continuing expenses;
- extra expense;
- system/dependency scope;
- proof of causation;
- maximum indemnity period.

RTO kỹ thuật không đồng nghĩa period covered. Finance, operations và claims team phải thống nhất baseline và loss methodology.

## 17. Coinsurance và participation

Một số coverage yêu cầu insured chịu phần trăm loss hoặc có participation khác. Trong tower, nhiều insurers chia layer.

Model cash flow:

```text
gross covered amount
  - retention
  - uncovered / excluded components
  × insurer participation
  subject to sublimit / aggregate / layer attachment
  = potential recovery, before timing/dispute effects
```

Đây là estimate, không phải promise thanh toán.

## 18. Definitions là control surface

Các từ cần đọc kỹ:

- computer system/network;
- insured organization/person;
- security failure/privacy event;
- data/digital assets;
- dependent service provider;
- claim/loss/damages;
- business interruption;
- cyber terrorism/war;
- wrongful act;
- prior knowledge.

Một SaaS, OT system, personal device hoặc subsidiary có thể nằm ngoài một definition nếu wording không bao phủ.

## 19. Exclusions và endorsements

Exclusion không đọc độc lập. Kiểm:

- exclusion gốc;
- carve-back/exception;
- endorsement sửa hoặc thay wording;
- schedule chỉ định entities/vendors/technologies;
- applicable law;
- interaction với insuring agreement;
- causation/anti-concurrent language;
- other-insurance provisions.

Tạo exclusion matrix theo scenarios, nhưng counsel/broker phải xác nhận interpretation.

## 20. War, cyber operations và attribution

War/hostile-act/cyber-operation wording có thể materially ảnh hưởng catastrophic scenarios.

Review:

- event/actor definitions;
- state backing/attribution standard;
- affected-location requirement;
- infrastructure/sovereignty language;
- attribution authority/process;
- carve-backs và sublimits;
- burden/process khi dispute;
- tower consistency.

Không dùng media attribution làm coverage conclusion. Exercise một state-linked systemic scenario với counsel và broker.

## 21. Ransomware, extortion và lawful response

Policy có thể cung cấp response services hoặc coverage liên quan, nhưng mọi decision phải xét:

- legality/sanctions và law-enforcement coordination;
- insurer notice/consent;
- approved negotiator/vendor;
- safety và business continuity;
- khả năng decryptor không đáng tin;
- data theft/leak risk vẫn còn;
- evidence/chain of custody;
- ethics và executive authority;
- payment không thay recovery/remediation.

Không mô tả insurance như funding mặc định cho ransom.

## 22. Business interruption measurement

Chuẩn bị trước incident:

- critical revenue/cost drivers;
- daily/weekly baseline;
- seasonality/growth;
- system-to-business dependency;
- saved/continuing/extra expenses;
- workarounds và mitigation costs;
- start/end timestamps;
- counterfactual model;
- evidence owners.

Finance/accounting và operations cùng xây methodology; security cung cấp causation/timeline, không tự tính toàn bộ loss.

## 23. Contingent/dependent business interruption

Supplier/cloud/MSP outage cần kiểm:

- provider nào được định nghĩa hoặc scheduled;
- direct/indirect dependency;
- event type tại provider;
- waiting period;
- sublimit/aggregate;
- geographic/system scope;
- evidence và cooperation rights;
- concentration/common-cause exclusions.

Supplier không chia sẻ forensic detail có thể làm proof khó. Contract phải hỗ trợ incident/evidence cooperation, không chỉ SLA availability.

## 24. Systemic và aggregation risk

Một common event có thể ảnh hưởng nhiều entities, locations, customers và policies:

- cloud/control-plane outage;
- ubiquitous software compromise;
- shared identity/MSP failure;
- self-propagating malware;
- common certificate/DNS/provider event.

Kiểm event aggregation language, related claims và shared limits. Insurance program không nên dựa trên giả định losses độc lập nếu architecture tập trung.

## 25. Social engineering và funds transfer

Phân biệt:

- attacker tự truy cập system và chuyển tiền;
- employee được lừa để authorize;
- vendor/customer invoice bị thay;
- credential/account takeover;
- telecom/call-center fraud.

Cyber, crime và social-engineering endorsements có thể trigger/exclude khác nhau. Kiểm verification-control conditions và overlaps trước khi model recovery.

## 26. Data và digital asset restoration

Các câu hỏi:

- dữ liệu/software nào thuộc definition;
- cost recreate/recollect có covered không;
- betterment/upgrade bị xử lý thế nào;
- hardware/OT có nằm trong scope;
- restore từ backup hay rebuild clean;
- loss-of-use/value có recognized không;
- internal labor được tính ra sao;
- evidence integrity/causation.

Restore decision ưu tiên an toàn và integrity; không chọn phương án chỉ vì có vẻ dễ claim hơn.

## 27. Privacy, regulatory và payment-card exposure

Map separately:

- breach counsel/forensics;
- notification/call center/monitoring;
- regulatory response/defense;
- fines/penalties where law permits and policy covers;
- civil claims/class actions;
- contractual/payment-card assessments;
- data-subject remediation;
- cross-border costs.

“Regulatory coverage” không bảo đảm mọi fine/penalty được insurable. Applicable law và wording quyết định.

## 28. Technology E&O và media overlap

Cyber event có thể gây:

- product/service failure claim;
- breach of professional duty;
- failure to deliver contracted security;
- content/IP/defamation claim;
- customer economic loss.

Review cyber, tech E&O, media và general liability together. Xác định priority, exclusions, allocation và defense handling khi một claim có nhiều allegations.

## 29. Silent/non-affirmative cyber

Silent cyber là cyber exposure trong policy không expressly grant hoặc exclude cyber loss.

Đối với policyholder:

- inventory non-cyber policies có thể chạm scenario;
- không giả định silence là coverage;
- xem cyber exclusions/endorsements mới;
- kiểm other-insurance/priority;
- reconcile broker coverage map;
- tránh double counting potential recovery.

Mục tiêu là affirmative clarity: biết policy nào dự kiến phản ứng và policy nào không.

## 30. Named insureds, territory và corporate change

Kiểm mọi entity/subsidiary/JV:

- named insured/automatic acquisition thresholds;
- newly acquired/created entity provisions;
- divested entity/run-off;
- change of control;
- employee/contractor/board capacity;
- worldwide territory và claim venue;
- sanctions/restricted territory handling;
- shared limits/allocation.

Organization chart thay đổi phải trigger policy review; brand name trong certificate không chứng minh entity được covered.

## 31. Application representations

Underwriting application có thể hỏi về controls như MFA, backups, patching, EDR, email security, encryption,
incident history hoặc supplier practices. Quy trình trả lời:

1. Định nghĩa population/scope/time.
2. Lấy evidence từ authoritative sources.
3. Ghi exceptions/unknowns.
4. Có control/data owner xác nhận.
5. Legal/risk/broker review wording.
6. Authority phù hợp sign.
7. Lưu application/version/evidence.

Không biến “planned” thành “implemented” hoặc sample thành enterprise-wide assertion.

## 32. Control attestation và evidence register

Mỗi representation material nên có:

```text
question / policy year / exact answer
defined scope + exclusions
evidence source + timestamp
control owner
known gaps / remediation
change trigger
review / signatory
```

Evidence register phục vụ renewal, claim và internal control improvement. Nó không nên trở thành lý do giữ sensitive telemetry vô hạn.

## 33. Change-in-circumstance workflow

Các event có thể cần review/notice theo policy/advice:

- acquisition/divestiture/change of control;
- material control degradation;
- major architecture/cloud/MSP change;
- known incident/circumstance;
- new geography/product/data class;
- significant revenue/dependency change;
- control representation không còn đúng;
- policy endorsement/insurer change.

Workflow phải route tới risk manager, broker và counsel; không tự suy đoán notification duty.

## 34. Renewal lifecycle

```text
180–120 days: scenarios, losses, changes, strategy
120–90 days: control evidence + application draft
90–60 days: market submission + Q&A
60–30 days: quote/wording comparison + stress cases
30–0 days: bind, endorsements, contacts, playbook update
post-bind: verify documents + communicate obligations
```

Timeline thực tế tùy market/program. Renewal không chỉ tối ưu premium; phải kiểm coverage quality, limits, service panel và retained risk.

## 35. Wording comparison và coverage matrix

So sánh quotes theo scenario, không chỉ price:

| Dimension | Option A | Option B | Decision impact |
|---|---|---|---|
| Trigger/definition | | | event nào phản ứng? |
| Limit/sublimit | | | tail bao nhiêu được tài trợ? |
| Retention/waiting | | | cash-flow/frequency loss? |
| Exclusions/carve-backs | | | scenario gap? |
| Panel/consent | | | response feasibility? |
| Territory/entities | | | population covered? |
| Claims reputation/service | | | execution uncertainty? |

Giữ wording diffs và rationale của quyết định.

## 36. Tower, excess và layer consistency

Với primary/excess tower, kiểm:

- attachment points;
- follow-form extent;
- exclusions/definitions khác nhau;
- exhaustion language;
- defense cost treatment;
- drop-down/gap;
- notice từng carrier;
- claims control/settlement consent;
- currency/entity/territory;
- aggregation qua layers.

Một excess quote rẻ nhưng không follow underlying scenario quan trọng có thể tạo gap đúng ở tail.

## 37. Self-insurance, captive và alternative financing

Tổ chức có thể giữ risk bằng:

- operating cash/reserve;
- high retention;
- captive;
- risk pool;
- parametric/alternative structure nếu phù hợp;
- contract allocation.

Đánh giá capital, volatility, tax/accounting/legal, administration, claims expertise và correlation.
“Self-insured” phải có funding/governance thật, không phải euphemism cho không chuẩn bị.

## 38. Limit adequacy và scenario analysis

Không chọn limit bằng peer average đơn thuần. Dùng:

- annual loss distribution;
- tail scenarios;
- business interruption dependencies;
- privacy/customer population;
- defense/restoration inflation;
- systemic/common-cause cases;
- policy gaps/sublimits;
- liquidity and risk appetite;
- marginal premium/capacity.

Output là retained-loss distribution và probability vượt liquidity/tolerance sau insurance—not “đã insured” nhị phân.

## 39. Total cost of risk

```text
premium + broker/advisor cost
+ expected retained loss
+ uninsured/excluded loss
+ control requirements and administration
+ cost of capital / volatility
+ claim friction and delay
- response services / risk-reduction value
```

Giá rẻ không đồng nghĩa efficient nếu sublimits/gaps lớn; coverage rộng không luôn tối ưu nếu retention/capital phù hợp hơn.

## 40. Contractual allocation system

Hợp đồng nên nối risk ownership với khả năng kiểm soát:

- ai quyết architecture/configuration;
- ai vận hành/detect/respond;
- ai giữ data/evidence;
- ai thông báo ai và khi nào;
- ai chịu cost nào;
- audit/assurance/cooperation rights;
- change/subprocessor/flow-down;
- termination/exit;
- limitations, indemnities và insurance.

Không giao liability vô hạn cho party không thể kiểm soát risk hoặc không có capacity chi trả.

## 41. Security schedule và shared responsibility

Security schedule cần testable requirements:

```text
scope / systems / data / services
roles + responsibility matrix
baseline controls + configuration portions
incident definition / notice / updates
evidence / audit / remediation
resilience / recovery / exercises
subprocessors / flow-down
data return / deletion / transition
```

“Industry-standard security” một mình khó vận hành. Gắn requirements với scope, evidence, timing và consequence.

## 42. Indemnity và limitation of liability

Các dimension cần legal negotiation:

- trigger/breach/claim;
- first-party vs third-party loss;
- covered loss/damages definition;
- defense/control/settlement;
- causation/allocation/contributory fault;
- caps, baskets, exclusions và carve-outs;
- survival/time limits;
- sole/exclusive remedy;
- insurance interaction/subrogation;
- enforceability và collectability.

Security mô tả scenarios/cost pathways; counsel soạn và diễn giải legal effect.

## 43. Supplier insurance requirements

Yêu cầu certificate/limit chưa đủ. Cần risk-based:

- loại policy phù hợp service;
- named insured/additional insured khi phù hợp;
- limits/retentions và financial strength;
- relevant coverage/exclusions;
- notice of cancellation/change nếu available;
- proof/renewal cadence;
- subcontractor/flow-down;
- run-off/tail;
- không coi insurance thay security/evidence;
- response/cooperation dù claim bị denied.

Certificate thường chỉ là evidence tóm tắt, không thay full policy/endorsement review khi material.

## 44. Customer commitments và stacking liability

Một provider có thể cam kết khác nhau cho hàng trăm customers:

- notification clocks;
- uncapped/carved-out liabilities;
- credits/refunds;
- audit/forensic reports;
- insurance limits;
- data-location/deletion;
- regulator cooperation.

Aggregate commitments có thể vượt insurance limit và response capacity. Contract deviation register cần map concentration và conflicting duties.

## 45. Incident notice và insurer engagement

Runbook giữ exact policy requirements:

- what constitutes notice/circumstance/claim;
- recipient/channel/address;
- timing standard;
- required initial facts;
- continuing updates;
- notice to primary/excess/other policies;
- consent before cost/settlement;
- broker/counsel roles;
- proof và delivery receipt.

Notify sớm theo advice nhưng không suy đoán material facts. Regulatory/customer/law-enforcement notices là streams riêng cần phối hợp.

## 46. Panel vendors, consent và incident command

Policy có thể có approved providers cho counsel, forensics, negotiator, notification, PR hoặc restoration.

Trước incident:

- compare panel với existing retainers;
- kiểm conflicts, regions, capacity và rates;
- xác định pre-approval/consent process;
- exercise insurer/broker contact path;
- giữ safe emergency authority;
- biết cost nào trước consent có risk không được reimbursed;
- không để claims workflow làm chậm containment cần thiết.

Incident commander quản outcome; insurer/counsel/claims roles được tích hợp nhưng không làm command mơ hồ.

## 47. Claims evidence và loss ledger

Canonical ledger:

```text
cost / date / vendor / invoice
work performed + incident linkage
coverage hypothesis / policy section
approval / consent reference
paid / accrued / disputed
business-interruption category
mitigation / saved expense
supporting evidence + custodian
submitted / acknowledged / resolved
```

Tách fact, estimate và forecast. Giữ chain of custody, procurement exceptions, time records và decision rationale theo retention/privilege rules.

## 48. Claim lifecycle, dispute và recovery

```text
incident / circumstance
  → notice + acknowledgment
    → coverage position / reservation
      → investigation + documentation
        → interim payment / negotiation
          → settlement / denial / dispute
            → subrogation / recovery
              → reconciliation + lessons
```

Reservation of rights không tự là denial. Track deadlines, information requests, privilege, settlement consent và business impact với qualified counsel/broker.

## 49. Exercises, metrics và learning loop

Exercise scenarios:

- ransomware có panel/consent/sanctions fork;
- supplier outage chạm dependent BI;
- social-engineering overlap cyber/crime;
- incident trước/sau renewal;
- tower exhaustion/systemic event;
- claim cùng customer indemnity;
- acquisition/divestiture entity gap.

Metrics hữu ích:

- scenario-to-coverage mapping completeness;
- material gaps/unknown aging;
- application evidence freshness;
- notice/panel contact exercise success;
- claim documentation latency;
- gross/covered/paid/retained variance;
- denial/dispute/root causes;
- control changes từ claims;
- total cost of risk và tail retained.

## 50. Operating playbook, checklist và nguồn

### Trước bind/renewal

- [ ] Material scenarios và loss taxonomy đã được cập nhật.
- [ ] Coverage inventory gồm cyber và adjacent policies.
- [ ] Definitions, triggers, limits, retention, sublimits, exclusions và endorsements được review.
- [ ] Entities, territory, acquisitions/divestitures và policy periods đúng.
- [ ] Application answers có scope, owner, evidence và known exceptions.
- [ ] Wording/options được so sánh theo scenarios và retained tail.
- [ ] Contract/insurance/capital strategy không double count transfer.

### Trước incident

- [ ] Policy/contacts/notice requirements truy cập được khi hệ thống down.
- [ ] Panel/consent và existing retainers đã reconcile.
- [ ] Incident command có insurer/broker/counsel/finance roles.
- [ ] Business-interruption baseline và loss ledger template sẵn sàng.
- [ ] Supplier/customer cooperation và evidence rights được biết.
- [ ] Tabletop đã thử coverage gaps và emergency decisions.

### Khi có incident/claim

- [ ] Containment/safety/legal obligations được ưu tiên.
- [ ] Policy-prescribed notice/consent được thực hiện theo advice.
- [ ] Facts, estimates và privilege được quản riêng.
- [ ] Costs/time/causation/approvals được ghi từ đầu.
- [ ] Primary/excess/adjacent policies và contractual recovery được xem xét.
- [ ] Settlement, communications và subrogation không làm hại quyền khác.

### Anti-pattern cần tránh

- Nói “rủi ro đã chuyển” mà không nêu phần retained.
- Mua limit theo peer average, không theo scenarios/liquidity.
- Chỉ đọc declarations page, bỏ definitions/endorsements/exclusions.
- Dùng overall limit cho component có sublimit/waiting period.
- Trả lời application bằng policy intention thay actual evidence.
- Giả định silent policy chắc chắn cover.
- Cam kết indemnity không xem liability cap/collectability/insurance.
- Đợi incident mới tìm notice address hoặc panel vendor.
- Tối ưu claim recovery bằng cách làm chậm containment/notification bắt buộc.
- Claim đóng nhưng không sửa control, contract hoặc coverage gap.

### Nguồn chính thức

- [UK NCSC Cyber Insurance Guidance](https://www.ncsc.gov.uk/guidance/cyber-insurance-guidance) — câu hỏi về existing defenses,
  impacts, coverage/limits, included services, incident support và tính chính xác của security information khi mua/renew/claim.
- [NAIC Cybersecurity Insurance Topic](https://content.naic.org/insurance-topics/cybersecurity) — cyber loss categories,
  standalone/package context và lưu ý cyber policies được tùy chỉnh mạnh.
- [NYDFS Cyber Insurance Risk Framework](https://www.dfs.ny.gov/industry_guidance/circular_letters/cl2021_02) — affirmative/silent cyber,
  systemic aggregation, data-driven risk measurement và insurance không thay cybersecurity.
- [U.S. Treasury Federal Insurance Office Reports & Notices](https://home.treasury.gov/policy-issues/financial-markets-financial-institutions-and-fiscal-service/federal-insurance-office/reports-notices) —
  current official reports về insurance market, terrorism program và catastrophic cyber-risk work.
- [NIST IR 8286B](https://csrc.nist.gov/pubs/ir/8286/b/upd1/final) — risk response prioritization,
  bao gồm transfer/share trong enterprise risk context.
- [NIST SP 1305](https://csrc.nist.gov/pubs/sp/1305/final) — thiết lập supplier requirements và giao tiếp chúng qua agreements theo CSF 2.0.
- [CISA StopRansomware Guide](https://www.cisa.gov/stopransomware/ransomware-guide) — response/notification planning và phối hợp các stakeholders,
  có thể gồm cyber insurer, law enforcement và incident-response partners.

### Học tiếp

1. [Cybersecurity Economics, Business Cases & Control Value Realization](cybersecurity_economics_business_cases_control_value_realization.md) — cost of delay,
   marginal risk reduction, benefits tracking, option value và investment learning.
2. [Security Service Management, Catalogs & Internal Customer Experience](security_service_management_catalogs_internal_customer_experience.md) — service ownership,
   request/fulfillment model, SLO, capacity, chargeback/showback và service improvement.

---

*Cập nhật lần cuối: 2026-08-03.*
