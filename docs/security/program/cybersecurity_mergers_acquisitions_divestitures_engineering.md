---
title: "Cybersecurity Mergers, Acquisitions & Divestitures Engineering"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-03
last_verified: null
version_scope: "unspecified"
source_count: 6
---
# Cybersecurity Mergers, Acquisitions & Divestitures Engineering

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu: đưa security vào hệ thống ra quyết định của transaction từ thesis, diligence và signing tới Day 1,
> integration hoặc separation/TSA; làm rõ inherited exposure, unknowns, control boundaries và điều kiện để deal vận hành an toàn.

> Nội dung này là hướng dẫn engineering/governance, không thay thế tư vấn pháp lý, kế toán, thuế, cạnh tranh,
> privacy, lao động, chứng khoán hoặc nghĩa vụ regulator tại jurisdiction cụ thể.

---

## 1. M&A là một security transformation

Transaction không chỉ đổi ownership. Nó làm thay đổi cùng lúc:

- trust boundaries và control ownership;
- identity, privileged access và workforce incentives;
- data controller/processor roles và permitted uses;
- product, supplier và technology dependencies;
- reporting, contractual và regulatory obligations;
- recovery capability và incident coordination;
- risk concentration và enterprise blast radius.

Security phải bảo vệ deal value và continuity—not chỉ hoàn thành questionnaire trước ký.

## 2. Các transaction pattern

| Pattern | Security question chính |
|---|---|
| Full acquisition | exposure nào được kế thừa và khi nào integrate? |
| Merger of equals | control/architecture nào trở thành target state? |
| Asset purchase | data, IP, systems, people và liabilities nào thực sự chuyển? |
| Minority investment/JV | quyền truy cập, influence và shared operations tới đâu? |
| Divestiture/carve-out | tách dependency nào mà business vẫn chạy? |
| Spin-off | control/service nào phải xây mới trước independence? |
| Distressed acquisition | diligence bị giới hạn và Day-1 risk cao thế nào? |

Không dùng một checklist giống nhau cho mọi structure.

## 3. Deal security lifecycle

```text
strategy / target screen
    → confidentiality + initial risk hypothesis
        → diligence + red flags + valuation inputs
            → sign / conditions / covenants
                → pre-close planning + threat monitoring
                    → Day 1 minimum controls
                        → integrate / hold separate / carve out
                            → verify outcomes + close TSA / residual risk
```

Mỗi phase có information rights và legal boundaries khác nhau. Không giả định ký hợp đồng đồng nghĩa được toàn quyền truy cập target.

## 4. Security objectives theo deal thesis

Deal thesis quyết định điều gì cần bảo vệ:

- mua customer base: privacy, consent, customer trust và data portability;
- mua technology/IP: repository, build, provenance, secrets và inventorship;
- mua regulated license: control effectiveness và compliance continuity;
- mua talent: identity, insider risk, retention và knowledge transfer;
- mua operating scale: shared platforms, resilience và concentration;
- carve-out để bán: separability, TSA cost và clean ownership.

Nếu security scope không liên kết thesis, team dễ kiểm tra nhiều nhưng bỏ đúng value driver.

## 5. Governance và decision rights

Vai trò tối thiểu:

- deal sponsor sở hữu thesis/value/timeline;
- corporate development điều phối transaction;
- legal/privacy xác định information boundary và obligations;
- security lead sở hữu cyber workstream và risk scenarios;
- IT/product/data owners xác nhận feasibility/dependencies;
- integration/separation lead sở hữu target operating model;
- executive/board authority quyết material risk;
- target representatives cung cấp evidence có thẩm quyền.

Security phải có escalation path tới người có thể đổi price, term, scope, timeline hoặc quyết định không tiếp tục.

## 6. Stage gates và outputs

| Gate | Output security tối thiểu |
|---|---|
| Target screen | initial risk hypothesis + fatal-risk questions |
| Pre-LOI | information plan + clean-team constraints |
| Diligence | evidence-backed findings + unknowns + scenarios |
| Investment decision | options, valuation/term/timeline impacts |
| Signing | covenants, conditions, schedules, remediation ownership |
| Pre-close | Day-1 plan + incident/change protocol |
| Close/Day 1 | minimum controls + exceptions + command structure |
| Integration/separation | milestones, evidence, residual risks |
| Exit/stabilization | acceptance, TSA exit, access/data reconciliation |

Một deck “cyber risk: medium” không phải decision output.

## 7. Confidentiality, privilege và clean team

Deal data cực nhạy cảm: target identity, architecture, incidents, customers, weaknesses và strategy.

Thiết kế:

- need-to-know groups và named access;
- clean team nếu competitively sensitive;
- legal privilege/work-product handling khi phù hợp;
- approved collaboration/data-room channels;
- watermark, download/export restrictions;
- retention, legal hold và defensible deletion;
- conflict/insider-trading controls theo applicable law;
- access review khi role hoặc deal state đổi.

Không gửi vulnerability details qua email distribution rộng hoặc copy tùy ý khỏi data room.

## 8. Deal-threat model

Giai đoạn transaction làm threat tăng vì:

- announcement tạo phishing và impersonation themes;
- workforce bất ổn tăng insider/credential risk;
- nhiều advisor có temporary access;
- team bị áp lực timeline nên bypass change/control;
- attacker có thể đã ở trong target và chờ interconnection;
- divestiture tạo tranh chấp ownership/data;
- integration credentials/scripts có quyền rất lớn.

Threat model cả transaction process, không chỉ target environment.

## 9. Risk-tiered diligence

Depth nên dựa trên:

- criticality với deal thesis;
- data classification/population;
- privileged connectivity dự kiến;
- product/system exposure;
- regulatory/geographic footprint;
- incident/adversary history;
- dependency/concentration;
- reversibility và timeline;
- quality của evidence.

Low-risk asset purchase khác global platform acquisition. Triage quyết định specialists, tests, sampling và escalation cần thiết.

## 10. Diligence scope và information request

Request list nên map tới scenarios và decisions:

```text
business / legal entities / geographies
technology + product + data landscape
identity / privileged access / connectivity
security program + controls + assurance
incidents / investigations / notifications
third parties / licenses / insurance
resilience / recovery / operational capacity
known gaps / exceptions / remediation commitments
```

Không biến VDR thành nơi đổ hàng nghìn files. Mỗi request cần purpose, owner, priority và acceptable evidence.

## 11. Evidence hierarchy và freshness

Evidence có strength khác nhau:

| Evidence | Ví dụ |
|---|---|
| Direct/reproducible | configuration export, inventory, test result |
| Independent | audit/assessment trong đúng scope và period |
| Operational | incident ticket, restore test, access review |
| Management representation | interview, questionnaire, attestation |
| Design/intention | policy, roadmap, unimplemented plan |

Kiểm scope, sample, period, exceptions và target population. Policy tốt không chứng minh operating effectiveness.

## 12. Unknowns là deal information

Limited diligence là bình thường; silent assumption thì không.

Mỗi unknown cần:

```text
question + why material
attempted evidence + access limitation
plausible range / downside scenario
pre-close or post-close resolution owner
decision/term/containment effect
deadline + consequence if unresolved
```

Unknown có thể dẫn tới hold-separate, price adjustment, escrow/indemnity proposal, condition, insurance hoặc no-go—do authority phù hợp quyết.

## 13. Business và technology profile

Hiểu target trước khi chấm controls:

- products/services và revenue-critical flows;
- customers, contracts và service commitments;
- legal entities/geographies;
- technology operating model và outsourced operations;
- key people và single-person dependencies;
- planned transformations/debt;
- seasonal/transaction peaks;
- upcoming renewals/EOL;
- systems thuộc seller nhưng target đang dùng.

Một control gap material hay không phụ thuộc business consequence và transaction structure.

## 14. Asset và crown-jewel discovery

Đối chiếu nhiều nguồn vì CMDB thường không đầy đủ:

- cloud/tenant/accounts/subscriptions;
- domains, certificates và external services;
- endpoints, servers, networks và OT/IoT nếu có;
- applications, repositories, pipelines và artifact registries;
- data stores, backups và archives;
- SaaS, suppliers và shadow IT;
- keys, secrets và signing assets.

Gắn owner, entity, purpose, environment, exposure, lifecycle và deal disposition: transfer, retain, replicate, migrate hay retire.

## 15. Identity và privileged access diligence

Kiểm tra:

- authoritative identity sources và joiner/mover/leaver;
- federation, domains và tenant boundaries;
- MFA coverage/phishing resistance;
- privileged/admin/service accounts;
- shared/dormant/orphan identities;
- break-glass và recovery paths;
- contractor/advisor access;
- secrets/keys/certificates ownership;
- access reviews và unresolved exceptions.

Mục tiêu không phải đếm accounts; mục tiêu là biết ai có thể vượt boundary hoặc giữ quyền sau transaction.

## 16. Network và trust relationships

Inventory:

- internet exposure và remote access;
- site-to-site VPN/peering/private links;
- partner/customer/supplier connections;
- DNS, PKI, email và management planes;
- segmentation/enforcement points;
- legacy protocols và implicit trust;
- monitoring/response visibility;
- dependency vào seller/shared corporate network.

Không mở flat connectivity vào acquirer ở Day 1. Kết nối mới phải có use case, narrow route, identity, logging, expiry và rollback.

## 17. Cloud, SaaS và control-plane ownership

Các câu hỏi quyết định:

- tenant/account thuộc legal entity nào;
- root/billing/support/admin authority ở đâu;
- federation và emergency access phụ thuộc ai;
- keys/logs/backups nằm ở region nào;
- marketplace/reseller contracts có transfer được không;
- policies/guardrails nào là inherited từ seller;
- quota/licensing/support plan có đổi khi close;
- resources nào dùng chung với retained business.

“Chuyển subscription” không tự chuyển data rights, keys, support authority hay forensic history.

## 18. Data và privacy diligence

Map:

```text
data category / subject / sensitivity
purpose + legal/contractual basis
source → processing → sharing → storage
controller/processor/owner roles
retention/deletion/rights workflow
cross-border/localization constraints
transaction disposition
```

Kiểm whether deal làm đổi purpose, recipient, controller hoặc notice/consent requirement. Không nhập toàn bộ data vào buyer lake chỉ vì ownership đổi.

## 19. Product security và customer promises

Đánh giá:

- product architecture, tenancy và support privilege;
- secure development/release process;
- dependency/SBOM/provenance/signing;
- vulnerability intake/remediation/disclosure;
- secrets và production deployment authority;
- security features đã bán/contracted;
- customer-specific controls/attestations;
- end-of-life products và unsupported versions.

Integration không được làm mất security property mà customer contract hoặc product design đang dựa vào.

## 20. Vulnerability và exposure review

Đừng chỉ lấy tổng số CVE. Cần:

- external exposure và attack path;
- actively exploited/known-exploited issues;
- identity/control-plane weaknesses;
- reachability và business criticality;
- remediation velocity/backlog age;
- unsupported systems;
- exceptions/risk acceptances;
- evidence fixes đã verify;
- vulnerabilities target không được quyền sửa vì shared service.

Một penetration test snapshot không thay coverage và lifecycle evidence.

## 21. Incident history và active compromise

Review:

- incident taxonomy và materiality thresholds;
- investigations/forensics scope;
- root cause, persistence và remediation evidence;
- notifications/claims/litigation/regulator interactions;
- repeated patterns và unresolved findings;
- detection blind spots và retention;
- current suspicious activity;
- customer/supplier commitments;
- lessons thực sự được đưa vào controls hay chưa.

Absence of reported incidents không chứng minh absence of compromise.

## 22. Security operating model và control effectiveness

Xem organization như một system:

- governance, authority và risk acceptance;
- policy/control library và exceptions;
- architecture/engineering engagement;
- security operations/incident response;
- identity, vulnerability, data và supplier capabilities;
- assurance/audit/finding closure;
- workforce, skills, outsourcing và budget;
- metrics/decision records;
- transformation backlog.

Phân biệt capability tồn tại, coverage, reliability và outcome—not chỉ tool licenses hoặc headcount.

## 23. Resilience và recovery

Due diligence cần kiểm:

- business impact analysis và critical processes;
- RTO/RPO/MBCO assumptions;
- dependency graph;
- backup protection/immutability;
- restore và end-to-end recovery tests;
- crisis authority/communications;
- supplier/site/workforce concentration;
- seller-provided recovery services;
- ability recovery trong integration outage hoặc cyber incident.

Day-1 interconnection có thể tăng blast radius trước khi recovery capability kịp hợp nhất.

## 24. Third-party và supply-chain inheritance

Target mang theo:

- critical suppliers/subprocessors;
- software dependencies và build services;
- reseller/managed-service relationships;
- audit/data-return/incident rights;
- non-transferable contracts;
- fourth-party concentration;
- foreign ownership/control/influence considerations khi applicable;
- outstanding findings và termination dependencies.

Due diligence target không thay supplier diligence. Xác định contract nào novate, consent, renegotiate, replace hoặc đi vào TSA.

## 25. Workforce, insider và culture risk

Transaction tạo uncertainty và asymmetric information. Controls cần human-centered:

- named access dựa trên job need;
- monitoring hợp pháp/tỷ lệ và có governance;
- retention/key-person plan;
- role/authority changes đồng bộ identity;
- advisor/temporary-worker offboarding;
- protected reporting và investigation routes;
- targeted training cho Day 1;
- support cho người bị thay đổi vai trò;
- separation-of-duties trong migration.

Không gắn nhãn toàn bộ target workforce là threat; tập trung opportunity, pressure và control gaps.

## 26. Regulatory, contractual và disclosure inventory

Lập inventory theo entity, jurisdiction, product, data và event:

- licenses/sector requirements;
- privacy/data-transfer obligations;
- customer security clauses;
- incident notification/reporting clocks;
- public-company disclosure nếu applicable;
- government contract/clearance requirements;
- records/legal hold;
- outstanding commitments, audits và remediation orders.

M&A phải trigger applicability review. Không copy posture/attestation của buyer sang target mà không kiểm scope và effective date.

## 27. Insurance, claims và loss history

Xác minh:

- policyholder/entities và change-of-control terms;
- retroactive dates/prior acts;
- limits, retention, sublimits và exclusions;
- known-circumstance representations;
- open claims/notices;
- insurer consent/panel requirements;
- tail/run-off coverage cho divestiture;
- overlap/gaps giữa buyer, seller và target policies.

Insurance không sửa control gap và không chuyển accountability. Legal/broker/insurance specialists phải xác nhận wording thực tế.

## 28. Quantify deal cyber exposure

Chuyển findings thành scenarios có range:

```text
event/pathway
frequency or probability during horizon
operational / financial / customer / legal magnitude
deal-value mechanism affected
confidence + unknowns
option/control effect
```

Bao gồm one-time transition risk và steady-state risk. Tránh cộng ordinal scores; xem tail, common-cause, integration cost và delay-to-synergy.

## 29. Red flags và fatal-risk questions

Ví dụ cần escalation ngay:

- dấu hiệu active compromise nhưng không đủ quyền điều tra;
- unknown privileged/control-plane ownership;
- material incident/notification chưa được xử lý;
- crown-jewel IP provenance/ownership không chứng minh được;
- data use/transfer có constraint đe dọa thesis;
- critical service không thể tách khỏi seller;
- unsupported platform không thể vá/contain;
- representations mâu thuẫn với evidence;
- recovery chưa từng test cho critical operations.

Red flag không tự động là no-go; nó phải có decision owner, downside và response options.

## 30. Diligence finding record

Canonical record:

```text
finding / scenario / affected thesis
evidence + source + date + scope
facts / assumptions / unknowns
severity range + confidence
pre-close containment
Day-1 requirement
long-term remediation + cost/time
deal-term implications
owner / authority / status
```

Giữ traceability từ question tới evidence, scenario, term, integration backlog và closure proof.

## 31. Deal decision options

Security recommendation không chỉ “accept/remediate”:

- proceed như kế hoạch;
- đổi price/valuation assumptions;
- change transaction perimeter;
- require pre-close remediation/condition;
- hold separate và staged connect;
- tăng escrow/indemnity/insurance proposal;
- đổi signing/close/integration timeline;
- retain TSA lâu hơn hoặc build replacement;
- abandon/no-go.

Commercial/legal authority quyết terms; security cung cấp evidence, scenarios và feasibility.

## 32. Purchase-agreement security inputs

Security phối hợp legal để làm rõ, khi phù hợp:

- representations/warranties và disclosure schedules;
- known incidents/investigations/findings;
- security/privacy program statements;
- pre-close operating/change covenants;
- access to evidence và cooperation;
- incident notification giữa sign và close;
- remediation/condition obligations;
- indemnity/escrow/survival mechanics;
- records/data return/destruction;
- TSA security responsibilities.

Không dùng boilerplate thay facts. Legal counsel sở hữu drafting và enforceability.

## 33. Signing-to-close controls

Khoảng sign-to-close là một risk window. Cần:

- change/incident notification protocol;
- material security action approval boundary;
- monitoring threat/brand/domain abuse;
- protect deal identities/data rooms;
- revalidate high-risk findings;
- restrict new privileged interconnection;
- refresh asset/incident/customer facts;
- prepare Day-1 access without activating sớm;
- closing risk certification với known exceptions.

Nếu closing conditions hoặc law yêu cầu entities độc lập, không điều hành target trước quyền kiểm soát hợp pháp.

## 34. Day-1 minimum viable security

Day 1 không cần hoàn tất integration nhưng phải có safe operating envelope:

- named incident command và contact paths;
- protected executive/admin accounts;
- emergency access và recovery contacts;
- known critical services/data/dependencies;
- high-risk external exposure contained;
- log/evidence preservation;
- legal/privacy/reporting escalation;
- workforce communication/phishing defense;
- no-unreviewed-connectivity rule;
- explicit exceptions, owner và expiry.

Day-1 controls ưu tiên catastrophic/tail scenarios, không ưu tiên cosmetic policy alignment.

## 35. Hold-separate và trust-before-connect

Giữ target như trust domain riêng cho tới khi đạt connection criteria:

```text
inventory known
identity/admin authority controlled
active-compromise checks complete enough
critical vulnerabilities contained
required visibility and response paths ready
data flows approved
rollback tested
```

Dùng narrow proxies, brokered access, file scanning và allowlisted flows. Không coi corporate LAN/VPN là dấu hiệu đã integrate.

## 36. Identity integration sequencing

Một trình tự an toàn:

1. Thiết lập clean administrative authority.
2. Bảo vệ break-glass/root/domain/tenant accounts.
3. Reconcile people, roles, contractors và service identities.
4. Loại shared/dormant/orphan access.
5. Chọn federation tạm thời hoặc migration target.
6. Migrate theo cohorts với entitlement diff.
7. Rotate secrets/keys/tokens.
8. Revoke legacy trust và verify negative access.

Đừng federate hai directories khi chưa hiểu privilege paths và account recovery.

## 37. Data migration và disposition

Mỗi dataset cần disposition decision:

| Action | Điều kiện chính |
|---|---|
| Retain in place | owner/control/TSA rõ |
| Copy/migrate | purpose, transfer right, integrity, reconciliation |
| Split | record-level ownership và leakage controls |
| Archive | access, retention, legal hold, readability |
| Delete | authority, scope, replicas/backups, evidence |

Migration có reconciliation count/hash, exception queue, rollback và access tests. “Copy thành công” chưa chứng minh source/replicas đã xử lý đúng.

## 38. Control inheritance và target state

Mỗi control cần xác định:

- current provider/consumer;
- legal/technical boundary;
- inherited/shared/complementary portions;
- evidence và effective period;
- target-state provider;
- transition gap;
- migration acceptance criteria;
- fallback nếu provider/service không sẵn sàng.

Không tuyên bố target “được bao phủ” bởi buyer control chỉ vì policy áp dụng trên giấy.

## 39. Security operations và evidence continuity

Integration phải giữ continuity của:

- incident intake/escalation;
- time synchronization và identifiers;
- audit/security logs;
- case history và evidence custody;
- detection ownership/coverage;
- threat intelligence/context;
- notification decision records;
- forensic access và retention;
- response authority across entities.

Khi đổi platform, chạy song song hoặc reconciliation đủ lâu; tránh blind window đúng lúc attacker quan sát transition.

## 40. Product, customer và external communication

Trước thay đổi product/control:

- inventory contractual/security commitments;
- xác định customer consent/notice nếu cần;
- giữ support/incident contacts;
- validate branding/domain/email changes;
- cập nhật subprocessors/data locations có governance;
- bảo vệ vulnerability-reporting channel;
- phối hợp truthful, non-speculative communication;
- không tiết lộ chi tiết giúp attacker.

M&A announcement và security disclosure là hai decision streams có dependencies nhưng authority khác nhau.

## 41. Incident trong transaction

Runbook phải trả lời:

```text
ai phát hiện / ai điều tra / ai giữ privilege
seller, target, buyer authority theo deal phase
evidence sharing và clean-team limits
containment có ảnh hưởng closing/business không
materiality + notification/disclosure owner
insurer/regulator/customer coordination
deal representation/covenant update
go / pause / reprice / hold-separate decision
```

Không để deal confidentiality chặn incident response; cũng không chia sẻ vượt quyền trước close.

## 42. Integration roadmap theo risk

Sequence theo dependencies và risk reduction:

- stabilize catastrophic pathways;
- thiết lập identity/admin/evidence foundations;
- đóng critical exposure;
- bảo đảm resilience và response;
- migrate shared platforms/data;
- harmonize policy/control/assurance;
- retire duplicated/legacy services;
- verify residual risk và benefits.

Không đặt “mọi thứ theo buyer standard trong 90 ngày” nếu capacity, architecture hoặc business commitments không cho phép.

## 43. Integration backlog và exception governance

Mỗi item có:

- linked diligence finding/scenario;
- current/target/transition state;
- owner/funding/dependencies;
- milestone và acceptance evidence;
- risk during transition;
- temporary control;
- expiry/escalation;
- closure verifier.

Giữ diligence findings trong cùng traceability chain; không đóng chúng chỉ vì đã tạo integration ticket.

## 44. Divestiture và carve-out discovery

Carve-out bắt đầu bằng dependency mapping:

- people/roles và shared teams;
- applications/infrastructure/cloud tenants;
- identities/domains/PKI/secrets;
- data, records, archives và backups;
- networks/facilities/endpoints;
- suppliers/licenses/contracts;
- security operations/recovery;
- IP/repositories/build pipelines;
- policies/evidence/assurance artifacts.

Seller, buyer và carved entity thường có ba target states khác nhau; ghi disposition cho từng asset/dependency.

## 45. TSA security design

Mỗi Transition Service Agreement service cần:

```text
service + provider + consumer
scope / users / data / systems
security responsibilities + minimum controls
identity / privileged access model
logging / incident / evidence sharing
availability / recovery expectations
change / vulnerability management
subprocessors / locations
exit criteria + date + extension consequence
```

TSA là temporary dependency có risk, không phải lý do trì hoãn target architecture vô thời hạn.

## 46. Separation execution

Separation plan nên có waves và negative tests:

1. Tạo clean destination authority.
2. Copy/split data có reconciliation.
3. Chuyển service, keys, domains và contracts.
4. Rebind monitoring, backup và recovery.
5. Revoke cross-entity identities/trust/connectivity.
6. Xóa/retain source copies theo authority.
7. Test business operation độc lập.
8. Verify seller không còn access và buyer không phụ thuộc ẩn.

Thành công không chỉ là target đăng nhập được; còn phải chứng minh bên không có quyền đã mất quyền.

## 47. Stranded assets, access và obligations

Sau separation thường còn:

- orphan accounts/service principals;
- shared certificates/keys;
- DNS/email forwarding;
- backup/archive chứa mixed data;
- source-code forks và signing authority;
- vendor accounts/billing;
- log/case/legal-hold records;
- customer notices/contract commitments;
- devices/media chưa thu hồi.

Dùng reconciliation ledger với owner, disposition, evidence và expiry; không dựa vào lời xác nhận “đã tách xong”.

## 48. Assurance, metrics và closure

Đo outcome thay vì volume:

- material unknowns aging/resolved;
- red flags có decision/term linkage;
- Day-1 control coverage và expired exceptions;
- privileged/orphan access removed;
- critical connectivity/data migrations verified;
- diligence findings remediated đúng acceptance criteria;
- incident/detection blind-window duration;
- restore/recovery success;
- TSA services exited đúng hạn;
- repeated findings/post-close surprises;
- realized integration risk/cost so với estimate.

Closure cần evidence và independent challenge theo materiality, không chỉ owner self-attestation.

## 49. Ví dụ: mua một SaaS B2B

Deal thesis: mua product và customer base; target chạy tenant riêng, dùng seller identity/help desk và một shared build service.

```text
Material scenarios:
1. compromised target admin → customer-data exposure
2. seller identity remains trusted after close
3. shared build compromise → poisoned release
4. customer data transferred beyond contractual purpose
5. seller dependency fails before replacement/TSA exit
```

Decision response:

- sign với disclosure/remediation/TSA inputs được legal xử lý;
- giữ network/tenant riêng ở Day 1;
- tạo clean root/admin authority và rotate credentials;
- broker support access, preserve logs và run active-compromise checks;
- migrate build trước broad federation;
- map customer/data obligations trước copy;
- TSA có service/control/incident/exit criteria;
- verify revoked seller access bằng negative tests.

## 50. Playbook 100 ngày, checklist và nguồn

### Pre-sign / diligence

- [ ] Deal thesis, structure, scope, jurisdictions và timeline đã rõ.
- [ ] Clean-team/data-room access có owner, retention và monitoring phù hợp.
- [ ] Risk-tiered request list map tới scenarios/decisions.
- [ ] Identity, data, product, cloud, supplier, incident và resilience evidence được review.
- [ ] Unknowns có downside, resolution path và deal consequence.
- [ ] Findings map tới price/term/scope/timeline/containment options.

### Signing-to-close / Day 1

- [ ] Change/incident protocol và closing certification được thống nhất.
- [ ] Day-1 command, contacts, admin authority và reporting paths sẵn sàng.
- [ ] Active-compromise/critical exposure checks đủ cho connection decision.
- [ ] Không có broad trust/connectivity chưa review.
- [ ] Minimum controls, exceptions, funding, expiry và rollback rõ.
- [ ] Applicable disclosure/notification decisions có đúng authority.

### Integration / separation

- [ ] Current-target-transition architecture và control ownership đã map.
- [ ] Identity/data/connectivity migrations có cohorts, reconciliation và negative tests.
- [ ] Logs, cases, evidence và recovery continuity được giữ.
- [ ] Diligence findings tồn tại tới acceptance evidence.
- [ ] TSA có security schedule và exit criteria kiểm chứng được.
- [ ] Stranded assets/access/data/obligations được reconcile.

### Anti-pattern cần tránh

- Security chỉ tham gia sau signing.
- Chấm target bằng questionnaire/certificate duy nhất.
- Không phân biệt fact, representation và unknown.
- Giảm mọi finding thành một màu hoặc điểm trung bình.
- Kết nối network/federate identity ngay Day 1 để “tạo synergy”.
- Copy data trước purpose/ownership/contract review.
- Áp buyer policy trên giấy rồi tuyên bố control đã inherited.
- Đóng finding khi tạo ticket, không khi đạt outcome.
- TSA không có security responsibilities hoặc exit criteria.
- Divestiture chỉ test positive access, không test quyền đã bị revoke.

### Nguồn chính thức

- [NIST SP 1326](https://doi.org/10.6028/NIST.SP.1326) — due-diligence assessment cho ICT suppliers,
  gồm ownership/control/influence, provenance, resilience, foundational cyber practices và supply-chain tiers.
- [NIST SP 800-161 Rev.1](https://csrc.nist.gov/pubs/sp/800/161/r1/final) — cybersecurity supply-chain risk management
  xuyên lifecycle acquisition, supplier và system.
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework) — governance, supply-chain risk,
  asset/risk identification, protection, detection, response và recovery outcomes.
- [NIST IR 8286 Rev.1](https://csrc.nist.gov/pubs/ir/8286/r1/final) — liên kết cybersecurity risk với enterprise objectives và risk registers.
- [DOJ Evaluation of Corporate Compliance Programs, September 2024](https://www.justice.gov/criminal-fraud/page/file/937501/download) —
  due diligence, M&A integration, tracking remediation và post-transaction compliance/audit considerations; áp dụng theo context pháp lý liên quan.
- [SEC Cybersecurity Risk Management, Strategy, Governance, and Incident Disclosure Final Rule](https://www.sec.gov/files/rules/final/2023/33-11216.pdf) —
  material incident và risk-management/governance disclosure requirements cho registrants thuộc phạm vi áp dụng.

### Học tiếp

1. [Security Risk Transfer, Cyber Insurance & Contractual Allocation](security_risk_transfer_cyber_insurance_contractual_allocation.md) — insurability, retention,
   exclusions, limits, claims evidence, indemnity và residual accountability.
2. [Cybersecurity Economics, Business Cases & Control Value Realization](cybersecurity_economics_business_cases_control_value_realization.md) — cost of delay,
   economic trade-offs, benefits tracking, option value và investment learning.

---

*Cập nhật lần cuối: 2026-08-03.*
