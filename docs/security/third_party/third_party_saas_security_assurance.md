---
title: "Third-Party & SaaS Security Assurance – Quản trị niềm tin ngoài ranh giới tổ chức"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-03
last_verified: null
version_scope: "unspecified"
source_count: 7
---
# Third-Party & SaaS Security Assurance – Quản trị niềm tin ngoài ranh giới tổ chức

> Thuật ngữ: [Glossary](../glossary.md).

Tổ chức có thể thuê dịch vụ, phần mềm và hạ tầng, nhưng không thể thuê ngoài toàn bộ accountability đối với customer, dữ liệu và
mission. Third-party assurance là vòng đời biến một quan hệ phụ thuộc bên ngoài thành quyết định risk có bằng chứng, control ownership
rõ, khả năng phản ứng và đường thoát khả thi.

```text
business need + service/data/access dependency
    → inherent risk + assurance scope
        → due diligence + architecture + contract
            → secure onboarding + continuous evidence
                → incident/change response + exit / deletion verification
```

Chương này mở rộng [Security Governance & Risk Engineering](../governance/security_governance_risk_engineering.md),
[Software Supply Chain Security](../supply_chain/software_supply_chain_security.md),
[Data Security & Privacy Engineering](../data/data_security_privacy_engineering.md) và
[Business Continuity & Cyber Resilience](../resilience/business_continuity_disaster_recovery_cyber_resilience.md).
Nội dung không thay tư vấn pháp lý, privacy hoặc yêu cầu regulator theo ngành/quốc gia.

---

## 1. Third-party security assurance là gì?

Đây là khả năng trả lời liên tục năm câu hỏi:

1. Ta phụ thuộc ai, cho business outcome nào?
2. Họ truy cập/xử lý dữ liệu, identity và hệ thống nào?
3. Control nào do supplier, customer hoặc hai bên cùng thực hiện?
4. Evidence nào chứng minh control còn hiệu lực trong đúng scope/thời gian?
5. Khi supplier đổi, bị sự cố hoặc chấm dứt, ta phát hiện và hành động thế nào?

Questionnaire chỉ là một cách thu thập thông tin. Assurance là decision system gồm inventory, assessment, contract, technical control,
monitoring, escalation và exit.

## 2. Vòng đời quan hệ bên thứ ba

```text
need / sourcing
  → triage + inherent risk
    → due diligence + design review
      → selection + contract + risk decision
        → onboarding + configuration validation
          → operation + continuous assurance
            → change / incident / renewal
              → offboarding + data/access cleanup + lessons learned
```

Security tham gia quá muộn sau khi hợp đồng đã ký sẽ chỉ ghi nhận rủi ro. Thiết kế fast path cho low-risk và early engagement cho
critical supplier để procurement không phải né quy trình.

## 3. Governance và quyền quyết định

Các vai trò cần tách:

- business relationship owner sở hữu nhu cầu và value;
- data/system owner xác định scope, classification và access;
- procurement/commercial sở hữu sourcing và điều khoản thương mại;
- legal/privacy diễn giải obligation và contractual language;
- security/risk đánh giá scenario, control và evidence;
- service owner vận hành cấu hình/integration;
- supplier manager theo dõi performance/change;
- risk owner chấp nhận residual risk;
- incident/continuity lead điều phối sự cố.

Security không nên tự “approve vendor” thay business risk owner; business cũng không được override technical gate mà không qua exception có thẩm quyền.

## 4. Taxonomy: vendor, supplier, processor và service provider

Một tổ chức bên ngoài có thể đồng thời là:

- SaaS/PaaS/IaaS provider;
- software/hardware manufacturer;
- managed service/MSP/MSSP;
- data processor/subprocessor;
- contractor/professional service;
- payment/identity/telecom provider;
- reseller/integrator;
- open-source/community dependency;
- fourth party của supplier.

Tên thương mại không quyết định risk. Hãy mô hình hóa quan hệ: họ cung cấp gì, control gì, nhận quyền/dữ liệu nào và phụ thuộc ai khác.

## 5. Inventory và system of record

Supplier inventory tối thiểu cần:

- legal entity, service/product và stable relationship ID;
- business/service owner, technical owner và contract owner;
- service/use case, environment và customer population;
- data category, purpose, location, retention;
- access/integration/identity type;
- business criticality và recovery dependency;
- subprocessors, hosting/provider concentration;
- contract/renewal/termination dates;
- assessment, evidence, finding, exception và incident history;
- authoritative discovery source và last verified time.

Tách supplier master khỏi từng service relationship: một tập đoàn cung cấp nhiều dịch vụ có scope/control/risk khác nhau.

## 6. Dependency map: data, access và business outcome

Với mỗi relationship, vẽ luồng:

```text
employees → enterprise IdP → payroll SaaS → cloud host
                               ├→ support subprocessors
                               ├→ banking API
                               └→ backup / analytics region
```

Ghi inbound/outbound data, API/OAuth scope, support/admin access, control plane, batch/export, backup, logging và recovery path. Supplier
không giữ dữ liệu production vẫn có thể rất critical nếu họ điều khiển DNS, signing, identity hoặc CI/CD.

## 7. Inherent risk và tiering

Đánh giá trước compensating control theo scenario:

- business/safety impact nếu unavailable hoặc sai integrity;
- sensitivity, volume, subject population và data purpose;
- privilege/reachability tới environment;
- autonomy: supplier có thể thực hiện destructive action không;
- substitutability, lock-in và recovery time;
- subprocessor/concentration/geopolitical exposure;
- product distribution blast radius;
- regulatory/contract/customer obligation.

Tier quyết định depth, cadence, approval và contract—not tự kết luận vendor “an toàn/không an toàn”.

## 8. Criticality, sensitivity và privilege là các trục riêng

| Quan hệ | Criticality | Data sensitivity | Privilege |
|---|---|---|---|
| Public status page | thấp/trung bình | thấp | thấp |
| Payroll SaaS | cao | cao | federation + financial workflow |
| CI/CD managed runner | rất cao | có thể thấp | code/signing/cloud deployment |
| Marketing survey | thấp | trung bình/cao | OAuth/file import |

Không dùng một score che mất khác biệt. Một service không có PII vẫn có thể gây compromise toàn software fleet; một processor PII nhỏ
có confidentiality impact cao nhưng availability thấp.

## 9. Scope assessment bằng scenario

Thay câu hỏi chung “Có firewall không?” bằng scenario liên quan:

- supplier admin bị phishing thì tenant của ta bị tác động thế nào;
- malicious update/artifact được ngăn/phát hiện/thu hồi ra sao;
- customer OAuth token bị lộ thì scope và revoke latency bao nhiêu;
- subprocessor/region mất thì service và data recovery thế nào;
- insider support export dữ liệu có evidence gì;
- account/contract bị chấm dứt thì lấy dữ liệu/config trong bao lâu;
- provider thay encryption/AI/data-use policy thì trigger nào.

Scenario quyết định evidence cần xem và control cần ghi vào architecture/contract.

## 10. Intake và fast path theo risk

Form intake ngắn nên thu business purpose, owner, data/access, integration, criticality, user count và target date. Tự động route:

- low-risk catalog/pre-approved service → baseline + owner attestation;
- standard SaaS → adaptive assessment + tenant configuration review;
- privileged/critical/data-sensitive → architecture, privacy, continuity và contract deep dive;
- prohibited use → chặn với lý do và alternative;
- urgent exception → scoped/time-bound decision, không bỏ record.

Tránh bắt công cụ không login và payroll platform điền cùng 300 câu. Friction không theo risk khuyến khích shadow SaaS.

## 11. Shared responsibility phải xuống tới control

Không dừng ở sơ đồ provider/customer chung chung. Lập control matrix:

| Control outcome | Supplier | Customer | Shared evidence |
|---|---|---|---|
| Platform patch | thực hiện và báo vulnerability | theo dõi advisory/compatibility | SLA + version/status |
| User lifecycle | cung cấp SSO/SCIM/API | authoritative joiner-mover-leaver | reconciliation report |
| Tenant configuration | cung cấp setting/log | cấu hình và review | exported effective config |
| Incident response | detect/contain provider | contain integration/user/data | joint notification/playbook |
| Backup/recovery | bảo vệ service copy | export/copy khi cần | restore/RTO evidence |

Mỗi dòng có owner, input/output, failure mode, evidence, cadence và exception path.

## 12. SaaS không phải “provider lo hết”

Customer thường vẫn sở hữu:

- tenant admin, SSO/MFA và local/emergency account;
- provisioning, group/role và external sharing;
- app consent/OAuth/integration token;
- data classification, purpose, retention và deletion request;
- audit log enablement/export/retention;
- domain/DNS verification và email security settings;
- device/session/access policy;
- third-party apps marketplace;
- backup/export/continuity ngoài capability mặc định khi cần.

Assurance phải kiểm **effective tenant state**, không chỉ provider certification.

## 13. Enterprise security khác product security

CISA Secure by Demand lưu ý procurement thường hỏi enterprise security của manufacturer nhưng ít hỏi cách họ xây product an toàn. Cần cả hai:

- enterprise security bảo vệ workforce, build, support và corporate infrastructure;
- product security gồm secure defaults, architecture, SDLC, vulnerability response, update integrity, logging và customer control;
- service operations gồm isolation, availability, data lifecycle và incident handling;
- customer implementation quyết tenant config, identity, integration và data use.

SOC 2 của corporate process không tự chứng minh một tính năng API mới không có cross-tenant authorization flaw.

## 14. Evidence hierarchy và freshness

Evidence mạnh dần theo mục tiêu:

1. marketing/policy statement;
2. self-attestation/questionnaire có owner/date/scope;
3. certification/independent report;
4. architecture/config/process artifact;
5. test sample và exception/finding history;
6. customer-observable effective configuration/log;
7. operational metric, incident/recovery exercise và direct validation.

Không có loại nào luôn tốt nhất. Kiểm scope, period, auditor criteria, carve-out, subservice organization, management response, sampling và bridge letter.
Evidence hết thời gian hoặc khác product/region không được reuse âm thầm.

## 15. Questionnaire thích ứng và có thể tái sử dụng

Questionnaire tốt:

- chỉ hỏi control liên quan scenario/scope;
- dùng câu hỏi outcome + evidence, không chỉ yes/no;
- tái sử dụng canonical answer/evidence nhưng giữ freshness;
- phân nhánh theo SaaS, product, privileged service, data processor;
- cho supplier giải thích partial/not-applicable;
- tách gap khỏi compensating control/risk decision;
- map về internal control catalog/framework;
- tạo action, owner và due date.

Một câu trả lời “Yes, policy exists” không chứng minh policy được thực thi. Đừng tính phần trăm Yes thành risk score.

## 16. Certification và assurance report: dùng đúng giới hạn

ISO 27001, SOC reports, PCI assessment, FedRAMP hoặc chứng nhận ngành có thể giảm duplication nhưng cần hỏi:

- legal entity/service/location nào trong scope;
- control period và report type;
- customer complementary controls (CUEC) nào bắt buộc;
- subservice carve-in/carve-out;
- exception/qualified opinion;
- control hoạt động liên tục hay sample;
- data/product feature mới có nằm trong scope;
- report access/confidentiality và validation source.

Certification là input assurance, không phải transfer accountability hay bảo đảm không có incident.

## 17. Architecture và product evaluation

Với service critical, review:

- tenant/isolation/trust boundary;
- identity, authorization và privileged support;
- data flow, storage, backup, key và deletion;
- control/data/management plane;
- API/webhook/integration security;
- update/build/dependency provenance;
- availability, dependency, recovery và degraded mode;
- telemetry, incident evidence và customer containment;
- portability/exit.

Yêu cầu diagram/data-flow/version và test một vài negative/failure path. Demo happy path không chứng minh isolation hoặc recovery.

## 18. Data, privacy và purpose boundary

Trước onboarding, ghi:

- data category/field, subject và volume;
- approved purpose, legal/contract basis theo tư vấn phù hợp;
- controller/processor/independent role;
- region, transfer, subprocessor và remote support location;
- minimization, masking/tokenization;
- retention, legal hold, deletion và backup expiry;
- training/analytics/advertising/model use;
- data subject/customer request workflow;
- breach cooperation/evidence.

Không gửi “toàn bộ dataset để tiện”. Dùng tenant/test data synthetic hoặc minimized khi evaluation.

## 19. Federation, provisioning và account lifecycle

Ưu tiên enterprise SSO với issuer/audience/claim mapping rõ, phishing-resistant admin auth và SCIM/API provisioning khi phù hợp. Kiểm:

- local account có tồn tại/bypass SSO không;
- domain takeover/verification;
- group-to-role mapping và default role;
- guest/external account expiry;
- joiner/mover/leaver + reconciliation;
- session/token revoke;
- break-glass owner/use alert;
- support impersonation evidence;
- tenant transfer/account recovery.

SSO chỉ xác thực; không tự offboard local API key, OAuth grant hoặc downstream workspace.

## 20. Privileged support và remote access

Supplier support access cần:

- named identity, JIT/JEA và approval theo ticket/purpose;
- customer-visible start/end và actor thật;
- hardened device/session control;
- no standing shared credential;
- command/data access logging;
- export/download restriction;
- emergency path có retrospective review;
- subprocessor/location visibility;
- revoke/contain capability phía customer;
- retention phù hợp cho investigation.

“Support may access data as necessary” quá rộng. Contract và product control phải ràng scope, purpose, notice và evidence.

## 21. API key, OAuth app và integration boundary

Integration thường tạo rủi ro lớn hơn UI:

- dùng workload identity/token ngắn hạn thay static secret khi hỗ trợ;
- scope theo action/resource/tenant, không `admin` mặc định;
- redirect URI, audience, issuer và webhook signature chặt;
- consent do đúng authority phê duyệt;
- secret/certificate rotation và revoke test;
- rate/quota/idempotency/replay defense;
- egress allow-list/private path khi hợp lý;
- inventory owner, last use và expiry;
- log correlation hai phía.

Marketplace app được user consent vẫn là third-party relationship và có thể đọc dữ liệu enterprise rộng.

## 22. Tenant configuration baseline

Tạo baseline versioned cho identity, sharing, external collaboration, audit, retention, application consent, admin, email/domain và security feature.
CISA SCuBA là ví dụ về baseline cấu hình cloud business application; tổ chức phải tailor theo risk và dịch vụ thực tế.

Lifecycle:

```text
baseline-as-code → test sandbox → approved exception
  → deploy/canary → export effective state → drift detection → remediation/retest
```

Không coi vendor default là secure default. Sau feature/license/migration thay đổi, kiểm setting mới, default mới và setting bị reset.

## 23. Logging, telemetry và customer visibility

Xác định event nào supplier tạo và customer lấy được:

- authn/session/admin/role/config changes;
- user/support/data access và export;
- API/OAuth/token activity;
- sharing/deletion/retention changes;
- malware/DLP/security alert;
- availability/backup/recovery event;
- tenant/global incident signal.

Ghi API format, latency, completeness, retention, clock, pagination, rate limit và license tier. Test export/correlation trước incident; log chỉ xem được trong portal
đang outage không phải recovery evidence đáng tin.

## 24. Encryption, key và tenant boundary

Hỏi encryption in transit/at rest nhưng đi sâu:

- key ownership/hierarchy, tenant separation và rotation;
- provider-managed, customer-managed hay customer-held key semantics;
- backup/log/search/cache có cùng coverage;
- support/decrypt path và privileged access;
- key revoke có thật sự crypto-shred và ảnh hưởng availability/backup;
- region/HSM/failure boundary;
- export/import khi đổi key hoặc rời dịch vụ.

Customer-managed key tăng control nhưng cũng tăng outage/recovery responsibility. “AES-256” không nói ai có thể giải mã hoặc key nằm ở đâu.

## 25. Vulnerability, patch và disclosure

Yêu cầu outcome đo được:

- intake/reporting channel và safe-harbor policy;
- severity/triage/remediation target theo product context;
- emergency patch/mitigation và customer action;
- supported version/EOL notice;
- coordinated disclosure/advisory/CVE khi phù hợp;
- affected-version/deployment identification;
- exploit/incident notification boundary;
- patch authenticity, rollback và compatibility;
- penetration/security test scope và finding governance.

Không yêu cầu “không có vulnerability”; yêu cầu khả năng tìm, xử lý, thông báo và chứng minh fix.

## 26. Secure development và software supply chain

Với software/service, đánh giá:

- secure development framework, threat model và security requirement;
- source/build/release access separation;
- dependency inventory, SBOM và vulnerability response;
- isolated/reproducible build khi phù hợp;
- artifact signing/provenance và update verification;
- secret trong code/build/log;
- branch/review/test/protected release;
- rollback/revoke compromised release;
- open-source maintenance và unsupported component.

Chi tiết kỹ thuật nằm ở [Software Supply Chain Security](../supply_chain/software_supply_chain_security.md). SBOM là inventory input,
không tự chứng minh source/build sạch hoặc component exploitable.

## 27. Availability, reliability và continuity

Đánh giá theo business service, không chỉ SLA phần trăm:

- architecture/failure domain và historical incident;
- dependency/subprocessor/control-plane concentration;
- RTO/RPO, backup/restore và data integrity;
- capacity/peak/quota/rate limit;
- status/notification/escalation channel;
- degraded mode và customer workaround;
- DR exercise scope/result;
- support staffing và regional disaster;
- termination/insolvency continuity.

99,9% theo tháng vẫn cho phép outage liên tục đáng kể và có thể loại trừ maintenance/dependency. Service credit không phục hồi mission impact.

## 28. Backup, restore và customer data recovery

Làm rõ:

- provider backup nhằm platform DR hay cho phép tenant restore;
- restore granularity, point-in-time window và actual RTO;
- corruption/deletion/ransomware scenario;
- immutable/isolated copy và key dependency;
- customer export/copy format, frequency và completeness;
- restored identity/permission/config state;
- backup retention sau deletion/termination;
- restore test evidence và customer participation.

“Backed up daily” không cho biết restore từng tenant, consistency giữa module hay customer có tự yêu cầu phục hồi được không.

## 29. Incident notification và phối hợp

Contract/playbook cần định nghĩa event taxonomy và clock bắt đầu:

- suspected, confirmed, material hoặc customer-impacting event;
- notification deadline tính từ awareness nào;
- channel/contact 24x7 và fallback;
- initial facts tối thiểu: scope, time, data/service, containment;
- update cadence và preservation;
- customer action: revoke token, block integration, notify subject;
- regulator/law-enforcement/public coordination;
- root-cause/corrective-action report;
- post-incident evidence và assurance refresh.

Không chờ supplier xác định đầy đủ root cause mới báo nếu customer cần containment ngay.

## 30. Forensics, evidence và customer containment

Trước sự cố cần biết supplier có thể cung cấp:

- tenant-specific log và global-event correlation;
- actor/source/session/config/data access timeline;
- image/artifact/hash hoặc preservation statement;
- chain of custody và time synchronization;
- scope methodology, limitation và confidence;
- impacted subprocessor/region/version;
- IOC/TTP và mitigation;
- independent investigator/report access.

Customer cần kill switch: disable federation/app/token, network egress, connector hoặc data flow mà không phụ thuộc hoàn toàn vào supplier support đang quá tải.

## 31. Subprocessor và fourth-party risk

Inventory không cần mọi supplier của supplier; cần dependency có thể thay đổi risk đáng kể:

- hosting/cloud/CDN/identity/support/analytics;
- nơi họ xử lý/lưu dữ liệu và loại access;
- control được inherit và evidence;
- incident/availability/concentration effect;
- notification trước/sau thay đổi;
- quyền objection/termination theo obligation;
- flow-down requirement và deletion;
- replacement/exit dependency.

Contract “supplier chịu trách nhiệm cho subprocessor” quan trọng nhưng không thay visibility và contingency khi một fourth party chung bị sự cố.

## 32. Data location, residency và remote access

Data location gồm primary, replica, backup, log, support workstation, content delivery, telemetry và subprocessor—not chỉ region được chọn trên UI.
Xác định:

- data at rest, processing và remote administrative access;
- cross-border transfer mechanism/constraint theo tư vấn phù hợp;
- region failover và DR copy;
- metadata/diagnostic/pseudonymized data;
- law-enforcement/government request process;
- location evidence và change notice;
- deletion/return tại mọi location.

Residency không đồng nghĩa sovereignty tuyệt đối hoặc cấm mọi remote support.

## 33. Concentration và systemic risk

Từng supplier có thể đạt assessment nhưng portfolio vẫn phụ thuộc một cloud, IdP, DNS, payment rail, MSP, library hoặc geographic region. Aggregate theo:

- số/criticality business services bị ảnh hưởng;
- shared control plane/admin/key/identity;
- correlated outage/compromise/geopolitical event;
- substitutability và simultaneous migration capacity;
- fourth-party common dependency;
- financial/contract renewal cliff;
- recovery resource contention.

Không cộng supplier risk score như các event độc lập. Stress-test scenario “provider X mất 7 ngày” và ghi enterprise risk owner.

## 34. Financial, ownership và geopolitical change

Security posture có thể đổi khi supplier:

- bị mua bán/sáp nhập;
- khó khăn tài chính, sa thải security/support;
- đổi jurisdiction/ownership/control;
- ngừng product hoặc ép migration;
- chuyển data/subprocessor/location;
- thay license làm mất security feature/log;
- bị sanction/trade restriction;
- phụ thuộc sole-source component.

Theo dõi tín hiệu phù hợp với tier, nhưng không biến rumor thành fact. Trigger reassessment/continuity/exit decision với owner và evidence.

## 35. Contract biến expectation thành obligation

Các nhóm điều khoản cần tailor:

- scope, data purpose, confidentiality và ownership;
- security control/shared responsibility;
- tenant configuration/customer duties;
- subprocessor, location và change notice;
- vulnerability/patch/EOL;
- incident notice, cooperation, evidence và cost;
- availability, RTO/RPO, backup/recovery;
- audit/assurance/report access;
- data return/deletion và transition assistance;
- liability/insurance/indemnity theo legal advice;
- termination/survival/precedence.

Contract không tự enforce control. Map mỗi obligation tới operational owner, evidence, trigger và remedy.

## 36. SLA, SLO và metric semantics

Đừng chỉ đọc con số. Xác định:

- service boundary/endpoint nào được đo;
- denominator, timezone và measurement source;
- scheduled/excluded event;
- partial degradation/latency/data correctness;
- per-tenant hay global availability;
- notification/response/resolution clock;
- RTO/RPO objective hay tested capability;
- service credit, escalation và termination threshold.

Customer nên đo outcome độc lập khi có thể. Provider uptime không chứng minh user có thể authenticate, query đúng data hoặc complete transaction.

## 37. Right to audit và evidence access

Quyền audit phải khả thi và theo risk:

- independent report/certification mặc định cho control chuẩn;
- targeted evidence cho material gap/change/incident;
- customer/regulator audit với notice, confidentiality và safety;
- pooled audit để giảm tải supplier;
- penetration test coordination không gây service risk;
- remediation status và follow-up evidence;
- access sau termination/incident;
- subprocessor evidence flow-down.

Quyền audit không dùng được vì phí, notice 12 tháng hoặc cấm xem mọi finding chỉ là điều khoản trang trí.

## 38. Finding, remediation và risk acceptance

Mỗi gap cần:

- requirement/control objective và evidence quan sát;
- affected relationship/service/data;
- threat scenario/business impact;
- supplier/customer action owner;
- compensating control và coverage;
- milestone/due date;
- residual risk, decision authority và expiry;
- verification/retest method;
- escalation/termination trigger.

Không ép mọi gap thành “Critical” để đàm phán. Nếu supplier không sửa, customer có thể giảm scope/data/privilege, thêm gateway/control, chọn alternative hoặc accept đúng thẩm quyền.

## 39. Secure onboarding và go-live gate

Trước production:

1. contract/DPA/shared responsibility hoàn tất;
2. owner, tier, dependency và approved use case được ghi;
3. tenant baseline deploy và effective config export;
4. SSO/SCIM/admin/break-glass lifecycle test;
5. OAuth/API secret/scope/webhook/rate limit test;
6. logging export/correlation/retention hoạt động;
7. data minimization/region/retention/deletion setting đúng;
8. backup/export/continuity/incident contact test;
9. findings/exception có decision;
10. offboarding/kill-switch owner được xác định.

Go-live evidence phải gắn đúng tenant/environment, không dùng ảnh demo của vendor.

## 40. Continuous assurance dựa trên tín hiệu

Kết hợp cadence và event-driven signal:

- certification/report/attestation expiry;
- tenant config drift và admin/role/app consent change;
- security advisory/CVE/incident;
- availability/latency/support performance;
- subprocessor/location/terms/privacy policy change;
- financial/ownership/EOL/license change;
- data volume/purpose/integration scope growth;
- finding/SLA/exception overdue;
- threat intelligence có relevance;
- customer control/evidence failure.

External rating có thể là triage signal, không phải fact về product/tenant. Xác minh attribution, freshness và actionability trước escalation.

## 41. Reassessment trigger và delta review

Không chạy lại toàn bộ questionnaire mỗi lần. Delta review hỏi thay đổi nào ảnh hưởng scenario/control:

- new feature/AI capability hoặc admin API;
- new data field/purpose/population;
- privilege/integration/network path tăng;
- new region/subprocessor/control plane;
- merger, platform migration hoặc product rewrite;
- serious incident/vulnerability;
- BIA/tier/obligation thay đổi;
- renewal hoặc contract amendment.

Giữ baseline decision và chỉ reopen phần liên quan, nhưng material change có thể buộc review architecture/contract/continuity toàn diện.

## 42. Offboarding bắt đầu từ lúc onboarding

Exit plan ghi:

- trigger: termination, incident, EOL, performance hoặc strategic move;
- notice/transition period và owner;
- data/config/log/export format và throughput;
- target/alternative/manual continuity;
- identity/token/API/DNS/integration revoke order;
- legal hold/retention/deletion;
- supplier/subprocessor/backup cleanup;
- license/escrow/artifact/documentation;
- validation, reconciliation và customer communication;
- residual dependency sau termination.

Nếu chưa thử export/import, “data portable” chỉ là claim.

## 43. Data return và deletion verification

Xác định data nào trả về, ở format/schema/version nào, kèm metadata/audit/attachment/permission ra sao. Sau migration:

- checksum/count/business invariant;
- completeness theo tenant/time/object;
- access permission và ownership;
- source freeze/delta reconciliation;
- deletion request/attestation;
- backup/log expiry timeline;
- subprocessor flow-down;
- legal hold/exceptions;
- account/domain/connector cleanup.

Deletion certificate là evidence từ supplier, không phải bằng chứng tuyệt đối; kết hợp contract, architecture, retention semantics và assurance history.

## 44. Portability, escrow và substitutability

Portability cần nhiều hơn CSV export:

- documented schema/API, stable identifiers và rate limits;
- configuration/policy/workflow/permission export;
- key/certificate/domain transfer;
- integration mapping và event history;
- compatible target/import tooling;
- skill/capacity/transition support;
- software/source escrow cho trường hợp phù hợp;
- license/IP right để vận hành transition;
- rehearsal và measured exit time.

Dual-provider có chi phí và semantic drift; chỉ coi là resilience nếu routing/data consistency/operation đã test.

## 45. Shadow SaaS và unsanctioned integration

Nguồn phát hiện:

- SSO/IdP và expense/procurement record;
- OAuth consent/app marketplace;
- DNS/proxy/browser/endpoint signal theo privacy policy;
- email forwarding, API token và code secret scan;
- data discovery/DLP;
- employee survey và support request.

Phản ứng theo risk: educate, onboard/contain, giảm scope, migrate hoặc block. Tạo approved catalog và fast path. Chỉ chặn domain có thể đẩy user sang tài khoản cá nhân khó thấy hơn.

## 46. MSP/MSSP và nhà cung cấp quyền đặc quyền

MSP có thể quản trị nhiều customer nên là concentration target. Yêu cầu:

- tenant-separated named identity, không shared global admin;
- JIT/JEA, privileged workstation và phishing-resistant auth;
- customer approval/visibility và session evidence;
- tool/RMM inventory, update integrity và allow-list;
- credential vault/rotation/revoke;
- subcontractor/background check theo obligation;
- cross-customer isolation;
- customer kill switch và alternate operation;
- joint incident/recovery drill.

SLA phản hồi ticket không thay control ngăn MSP account bị dùng để deploy ransomware toàn fleet.

## 47. AI SaaS và dữ liệu đưa vào model

AI feature tạo thêm câu hỏi assurance:

- prompt/input/output/file/embedding nào được lưu và ở đâu;
- có dùng customer data để train/improve model không, opt-out semantics;
- model/provider/subprocessor và version change;
- tenant isolation, connector/retrieval scope;
- retention/deletion và derived data;
- human review/support access;
- output provenance, accuracy/safety và business validation;
- prompt injection/data exfiltration control;
- logging/admin/usage policy;
- IP/privacy/regulated decision theo chuyên gia phù hợp.

Không bật AI assistant toàn tenant chỉ vì nó là feature trong SaaS đã được approve trước đây; đây là material change cần delta review.

## 48. Operating metrics và maturity

Metric hữu ích:

- % critical relationships có owner/data/access/dependency đầy đủ;
- inherent-risk triage lead time và deep-review coverage;
- evidence current/in-scope rate;
- critical tenant config conformance/drift age;
- stale account/token/app consent;
- overdue high-risk finding/exception;
- incident notification/containment latency;
- supplier/subprocessor/concentration coverage;
- exit/export/delete/recovery test pass;
- shadow SaaS discovery-to-decision time.

Không dùng số questionnaire gửi, số certification thu hoặc average vendor score làm security outcome.

## 49. Ví dụ end-to-end: onboarding payroll SaaS

**Context:** SaaS xử lý identity, salary, bank details và chuyển file/API tới ngân hàng; payroll có cut-off cố định.

1. Intake xác định high confidentiality/integrity/availability, business owner và MBCO/RTO/RPO.
2. Data-flow map gồm IdP, SaaS, cloud host, support subprocessor, banking API, backup/analytics region.
3. Due diligence xem tenant isolation, product SDLC, support privilege, recovery, log và incident evidence—not chỉ SOC report.
4. Contract giới hạn purpose/training, region/subprocessor, incident notice, RTO/RPO, return/delete và transition assistance.
5. SSO/SCIM cấu hình role tối thiểu; payroll admin riêng, phishing-resistant auth, break-glass alert.
6. Banking integration dùng scoped workload credential, dual approval, amount/file integrity và reconciliation.
7. Baseline khóa external sharing/app consent; audit export sang customer-controlled store.
8. Test leaver, support access, token revoke, sample data export, restore scenario và manual payroll workaround.
9. Continuous assurance theo config drift, admin/OAuth change, evidence expiry, incident, subprocessor và cut-off performance.
10. Exit drill đo export/import employee/history/permission, delta freeze, bank reconciliation và deletion timeline.

Quyết định go-live dựa trên residual scenarios và owner, không dựa trên việc vendor “đạt 92% questionnaire”.

## 50. Checklist, anti-pattern và tài liệu chính thức

### Checklist production

- [ ] Mỗi supplier-service relationship có business, technical, data và contract owner.
- [ ] Inventory ghi use case, data, access, criticality, integration, subprocessor và renewal/exit.
- [ ] Tiering tách business criticality, data sensitivity, privilege và substitutability.
- [ ] Assessment dựa trên scenario, scope và adaptive evidence—not questionnaire giống nhau.
- [ ] Shared responsibility map tới từng control, owner, failure mode và evidence.
- [ ] Enterprise/product/service/customer security được đánh giá riêng nhưng nối với nhau.
- [ ] Certification/report được kiểm scope, period, carve-out, CUEC và exception.
- [ ] Effective tenant config, SSO/SCIM/admin/OAuth/log/data lifecycle được kiểm trước go-live.
- [ ] Contract obligation có operational owner, evidence, trigger, remedy và exit clause.
- [ ] Incident playbook có taxonomy, clock, contact 24x7, evidence và customer kill switch.
- [ ] Subprocessor/location/concentration được model ở portfolio level.
- [ ] Continuous assurance dùng config/evidence/change/incident signal có xác minh.
- [ ] Finding/exception có owner, milestone, residual risk, expiry và retest.
- [ ] Offboarding revoke mọi access/integration và kiểm return/delete/reconciliation.
- [ ] Portability/recovery/exit được test; SLA và certification không thay capability.

### Anti-pattern thường gặp

- “Vendor có SOC 2/ISO 27001 nên không cần xem use case.”
- “SaaS provider chịu toàn bộ security.”
- “Questionnaire càng dài thì assurance càng mạnh.”
- “Tỷ lệ câu trả lời Yes là vendor risk score.”
- “SSO tự động xử lý mọi offboarding.”
- “Provider backup nghĩa là customer restore được từng tenant.”
- “SLA 99,9% đáp ứng mọi RTO.”
- “Contract đã ký thì control đã được enforce.”
- “Supplier chịu trách nhiệm subprocessor nên không cần biết dependency.”
- “External rating là bằng chứng product/tenant bị compromise.”
- “CSV export đồng nghĩa có exit plan.”
- “AI feature nằm trong SaaS đã duyệt nên không cần đánh giá lại.”

### Tài liệu chính thức

- [NIST SP 800-161 Rev. 1 Update 1 – Cybersecurity Supply Chain Risk Management](https://csrc.nist.gov/pubs/sp/800/161/r1/upd1/final)
- [NIST SP 1305 – CSF 2.0 Quick-Start Guide for C-SCRM](https://csrc.nist.gov/pubs/sp/1305/final)
- [NIST IR 8276 – Key Practices in Cyber Supply Chain Risk Management](https://csrc.nist.gov/pubs/ir/8276/final)
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)
- [CISA Secure by Demand Guide](https://www.cisa.gov/sites/default/files/2024-08/SecureByDemandGuide_080624_508c.pdf)
- [CISA Vendor Supply Chain Risk Management Template](https://www.cisa.gov/sites/default/files/2025-06/Vendor-Supply-Chain-Risk-Management-Template_Final_508.pdf)
- [CISA Secure Cloud Business Applications (SCuBA) Project](https://www.cisa.gov/resources-tools/services/secure-cloud-business-applications-scuba-project)

### Học tiếp

1. [Security Architecture Review & Design Governance](../architecture/security_architecture_review_design_governance.md) – intake, review gates, ADR, pattern conformance,
   exception và architecture fitness functions.
2. [Security Metrics, Measurement & Executive Reporting](../metrics/security_metrics_measurement_executive_reporting.md) – metric design, uncertainty, leading/lagging indicators,
   aggregation và decision-oriented communication.

---

*Cập nhật lần cuối: 2026-08-03.*
