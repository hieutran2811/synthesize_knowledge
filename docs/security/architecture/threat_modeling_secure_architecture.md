---
title: "Threat Modeling & Secure Architecture – Mô hình hóa mối đe dọa và kiến trúc an toàn"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-02
last_verified: null
version_scope: "unspecified"
source_count: 14
---
# Threat Modeling & Secure Architecture – Mô hình hóa mối đe dọa và kiến trúc an toàn

> Thuật ngữ: [Glossary](../glossary.md).

Threat modeling không phải buổi họp để điền đủ STRIDE rồi lưu một file PDF. Đây là vòng lặp giúp
team hiểu đúng hệ thống, tìm cách hệ thống có thể bị lạm dụng, đưa ra quyết định thiết kế có thể
kiểm chứng và cập nhật các quyết định đó khi kiến trúc thay đổi.

```text
scope → model → discover threats → prioritize → respond
  ↑                                             ↓
  └──────────── verify, observe, update ────────┘
```

Tài liệu tập trung vào application, API, cloud và distributed system. IAM chi tiết nằm tại
[Identity & Access Management](../identity/iam_authentication_authorization.md), còn vòng đời key
và credential nằm tại [Secrets & Key Management](../secrets/secrets_key_management.md).

---

## 1. Threat modeling là gì?

Threat modeling là quy trình có cấu trúc, lặp lại được để:

1. mô tả target of evaluation từ góc nhìn security;
2. xác định điều gì có thể xảy ra sai và ai có thể gây ra;
3. quyết định eliminate, mitigate, transfer hay accept;
4. biến quyết định thành requirement và evidence kiểm chứng;
5. duy trì mô hình cùng hệ thống.

Nó tìm cả design flaw chưa có CVE: workflow cho phép hoàn tiền hai lần, service dùng quyền
cross-tenant, queue consumer tin message không có provenance hoặc recovery flow yếu hơn login.

## 2. Kết quả cần có và điều threat modeling không hứa

Một threat model hữu dụng tạo ra:

- scope, assumption và security objective rõ;
- diagram/model khớp hệ thống;
- threat scenario có asset, precondition, path và impact;
- owner, priority, response và due date;
- security requirement có thể test;
- residual risk và người chấp nhận;
- trigger cập nhật mô hình.

Threat modeling không chứng minh hệ thống “an toàn tuyệt đối”, không thay code review, SAST/DAST,
penetration test, incident response hay risk management cấp tổ chức. Nó kết nối các hoạt động đó.

## 3. Bốn câu hỏi cốt lõi

Theo cách tổ chức phổ biến của Threat Modeling Manifesto và OWASP:

| Câu hỏi | Artifact chính |
|---|---|
| Chúng ta đang xây gì? | Scope, asset, DFD, dependency, assumption |
| Điều gì có thể sai? | STRIDE prompt, abuse case, attack tree, threat statement |
| Sẽ làm gì với nó? | Response, control, security requirement, owner |
| Đã làm đủ tốt chưa? | Review, test, telemetry, residual-risk decision |

Bỏ câu hỏi cuối biến mitigation thành ý tưởng chưa được kiểm chứng. Bỏ câu hỏi đầu tạo danh sách
threat chung chung không gắn với kiến trúc thật.

## 4. Khi nào cần threat model hoặc review lại?

Thực hiện sớm khi còn thay đổi thiết kế rẻ, và review khi:

- sản phẩm hoặc trust boundary mới;
- thêm flow dữ liệu nhạy cảm, tenant, region hoặc integration;
- đổi authentication, authorization, recovery hay admin workflow;
- đưa service ra Internet, đổi protocol hoặc client type;
- thêm queue, cache, webhook, file upload, plugin hoặc code execution;
- chuyển cloud/provider/orchestrator hoặc shared responsibility;
- thay dependency/supply-chain path đặc quyền;
- incident, near miss, pentest finding cho thấy assumption sai;
- control, threat intelligence hoặc business impact thay đổi.

Không cần vẽ lại toàn hệ thống cho mỗi ticket. Review delta và các dependency/boundary bị ảnh hưởng.

## 5. Thành phần workshop và vai trò

Một workshop nhỏ thường cần:

- product owner: value, abuse impact và acceptable behavior;
- architect/developer: flow thực tế, state, dependency và failure mode;
- operations/SRE: deployment, identity, observability, DR và runbook;
- security/privacy: prompt, attacker path, requirement và risk consistency;
- tester: cách tạo evidence và negative test;
- data/legal/safety owner khi impact liên quan.

Facilitator giữ scope và tránh tranh luận giải pháp quá sớm. Scribe ghi threat/decision. Risk owner
không mặc định là security team; business owner chịu trách nhiệm chấp nhận impact kinh doanh.

## 6. Xác định Target of Evaluation và scope

Scope tốt trả lời:

```text
IN: checkout API, payment orchestration, webhook consumer, order DB
OUT nhưng là dependency: external IdP, payment provider, managed queue
OUT hoàn toàn: provider internal network không có interface/assumption liên quan
```

Với thành phần ngoài scope nhưng hệ thống phụ thuộc, vẫn phải ghi interface, trust assumption,
failure/compromise behavior và owner. “Third party quản lý” không làm threat biến mất.

Time-box scope theo một user journey, service boundary hoặc change set nếu hệ thống lớn.

## 7. Assumption là một phần của security model

Ví dụ assumption:

- IdP xác minh MFA cho admin theo assurance đã cam kết;
- queue chỉ nhận message từ producer role xác định;
- cloud provider bảo vệ physical HSM;
- client mobile có thể bị reverse engineer và không giữ được shared secret;
- clock lệch tối đa 60 giây;
- internal network không đồng nghĩa trusted;
- support staff có thể xem metadata nhưng không plaintext payment data.

Mỗi assumption quan trọng cần owner, evidence và trigger invalidation. Assumption không được kiểm
chứng chỉ là hy vọng. Ghi rõ phần nào là fact, constraint, decision hay unknown.

## 8. Asset và security objective

Asset không chỉ là database:

| Asset | Objective ví dụ |
|---|---|
| Customer data | Confidentiality, integrity, retention/privacy |
| Order/payment state | Integrity, uniqueness, auditability |
| Authentication/session | Authenticity, replay resistance, availability |
| Signing/encryption key | Confidentiality, integrity, correct usage |
| Build artifact | Provenance, integrity, reproducibility |
| Service capacity | Availability, fair use, recovery |
| Audit evidence | Integrity, completeness, restricted access |
| Reputation/safety | Tránh fraud, physical harm, legal breach |

Viết objective cụ thể: “một payment provider event chỉ được áp dụng một lần cho đúng merchant và
order” tốt hơn “bảo đảm integrity”.

## 9. Theo dữ liệu xuyên suốt lifecycle

Data-centric view hỏi dữ liệu nhạy cảm:

```text
collect → validate → process → cache → replicate → export/share
                         ↓                    ↓
                       backup              analytics
                         ↓                    ↓
                    restore/archive → delete
```

Ở mỗi bước xác định format, classification, owner, tenant, location, encryption, access, retention,
lineage và deletion semantics. Threat thường nằm ở bản sao phụ: log, search index, dead-letter
queue, analytics export, backup hoặc developer snapshot.

## 10. Adversary và capability

Không chỉ dùng nhãn “hacker”. Mô tả capability:

- unauthenticated Internet user;
- authenticated customer kiểm soát input và resource ID của chính họ;
- malicious tenant hoặc partner có valid credential;
- compromised workload/service account;
- developer/CI runner bị chiếm;
- privileged operator/support insider;
- supply-chain maintainer hoặc dependency compromise;
- attacker có physical/device access;
- accidental actor gây misconfiguration hoặc destructive action.

Ghi rõ starting access, knowledge, resource, persistence và goal. Không giả định attacker biết ít
hơn thực tế; security không dựa vào việc giấu endpoint hay format.

## 11. Use case, state machine và business invariant

Business logic cần mô hình behavior hợp lệ trước khi tìm abuse:

```text
CREATED → AUTHORIZED → CAPTURED → REFUNDED
              │             └── refund_total <= captured_total
              └── transition chỉ bởi principal/policy hợp lệ
```

Invariant ví dụ:

- tổng refund không vượt số tiền captured;
- một idempotency key chỉ đại diện một request semantic;
- maker không tự approve giao dịch của mình;
- order chỉ thuộc một tenant xuyên suốt mọi query/event;
- privilege change phải revoke/refresh session phù hợp;
- deletion phải bao phủ replica/index theo retention policy.

Invariant là nguồn tốt để viết negative test và runtime detection.

## 12. Abuse story và misuse case

Template ngắn:

```text
Là một <actor/capability>, tôi muốn <abuse action>
để <security/business impact>, bằng cách <path/precondition>.
```

Ví dụ:

> Là customer đã đăng nhập, tôi muốn replay đồng thời hai yêu cầu refund với cùng order để vượt
> invariant tổng refund, bằng cách lợi dụng check-then-update không atomic.

Abuse story phải liên kết asset và flow thật. “Attacker hack hệ thống” không actionable. OWASP đã
đánh dấu cheat sheet abuse case cũ là historical, vì vậy dùng abuse story như kỹ thuật bổ sung,
không coi nó là methodology duy nhất.

## 13. Năm phần tử của Data Flow Diagram

DFD threat modeling thường dùng:

| Phần tử | Ý nghĩa | Câu hỏi security |
|---|---|---|
| External entity | Actor/system ngoài control trực tiếp | Identity nào? input có đáng tin? |
| Process | Thành phần xử lý/chuyển đổi | Chạy với quyền gì? validate/authorize ở đâu? |
| Data store | Dữ liệu lưu trữ | Ai đọc/ghi? tenant/retention/backup? |
| Data flow | Dữ liệu/chỉ thị di chuyển | Protocol, auth, integrity, replay, schema? |
| Trust boundary | Nơi trust/privilege/owner thay đổi | Control nào bắt buộc khi đi qua? |

DFD không phải deployment diagram đẹp. Nó phải làm lộ data flow và thay đổi trust.

## 14. Trust boundary không chỉ là firewall

Boundary xuất hiện khi thay đổi:

- identity hoặc authentication authority;
- privilege/service account;
- tenant/customer ownership;
- network/exposure zone;
- process/container/host/cluster/account;
- control plane và data plane;
- human/admin automation;
- organization/provider/shared responsibility;
- data classification, region hoặc legal jurisdiction;
- build time và runtime.

Mỗi crossing cần biết ai xác minh identity, authorize action, validate data, bảo vệ transport,
chống replay và ghi audit. “Internal API” không phải security property.

## 15. Chọn độ sâu DFD

```text
Level 0: user journey + hệ thống/third party chính
Level 1: service, store, queue, identity và boundary
Level 2: endpoint/worker/subprocess của flow rủi ro cao
```

Bắt đầu coarse để tránh sa vào chi tiết. Drill-down khi một box che giấu boundary, privilege hoặc
state transition quan trọng. Một microservice không mặc định là một process duy nhất nếu sidecar,
plugin, admin port hoặc background worker có trust khác nhau.

## 16. Ví dụ DFD: đặt hàng và thanh toán

```text
[Browser]
    │ HTTPS + session, order command
    ▼                 Internet boundary
(API Gateway) ── verified identity/context ──> (Order Service)
                                                    │
                        service boundary             ├──> ||Order DB||
                                                    │
                                                    └──> [Payment Provider]
                                                           │ signed webhook
                                                           ▼
                                                    (Webhook Consumer)
                                                           │
                                                           └──> ||Event/InBox||
```

Diagram cần bổ sung tenant ID được lấy từ đâu, token audience, webhook verification, event ID,
retry semantics, encryption/key owner, admin path, logs và failure path. Mũi tên thiếu protocol/
identity/data thường che giấu assumption.

## 17. Annotation làm diagram có giá trị

Mỗi flow quan trọng nên ghi:

- data/schema/classification và kích thước giới hạn;
- source/destination identity, credential type, audience;
- authentication, authorization và tenant derivation;
- protocol, transport integrity/confidentiality;
- sync/async, ordering, retry, timeout, idempotency;
- encryption/signature/key owner;
- validation và canonicalization;
- log/trace/redaction;
- failure, fallback và dead-letter behavior.

Không cần nhét mọi thứ lên hình; dùng stable flow ID liên kết sang bảng metadata.

## 18. Attack surface inventory

Từ DFD liệt kê entry/exit point:

- public/internal/admin API, webhooks và callbacks;
- file import/upload/export;
- queue/topic/event schema;
- database, cache, object store, backup;
- DNS, service discovery, metadata endpoint;
- management/debug/metrics/health interface;
- CI/CD, artifact registry, IaC và deployment API;
- browser/mobile/desktop extension/plugin;
- support tool và manual operation;
- third-party SDK/API.

Với mỗi surface: exposure, owner, auth, rate/size limit, parser, privilege, data và monitoring.

## 19. STRIDE là bộ câu hỏi, không phải risk score

| Nhóm | Vi phạm thuộc tính | Prompt |
|---|---|---|
| Spoofing | Authentication/authenticity | Có thể giả identity/source nào? |
| Tampering | Integrity | Có thể sửa data, code, state hay policy? |
| Repudiation | Accountability | Có thể phủ nhận hoặc phá evidence? |
| Information Disclosure | Confidentiality/privacy | Có thể đọc/suy ra dữ liệu nào? |
| Denial of Service | Availability | Có thể làm cạn tài nguyên/khóa user/dependency? |
| Elevation of Privilege | Authorization | Có thể vượt role, tenant hoặc boundary nào? |

STRIDE giúp coverage nhưng không cho biết priority. Một threat có thể thuộc nhiều nhóm; đừng tạo
sáu ticket trùng nhau chỉ để đủ acronym.

## 20. Áp STRIDE lên từng phần tử và flow

Checklist thực dụng:

- external entity: spoofing, repudiation, input abuse;
- process: cả sáu nhóm, đặc biệt code/identity/privilege;
- data flow: tampering, disclosure, replay và DoS;
- data store: tampering, disclosure, availability, audit/repudiation;
- boundary crossing: spoofed context, missing authorization, trust confusion;
- control plane: privilege escalation, policy tampering, audit disablement;
- dependency/failure path: timeout amplification, fail-open, stale authorization.

Đây là prompt, không phải luật cứng. Threat business logic và privacy có thể không nổi bật nếu chỉ
áp bảng máy móc.

## 21. Viết threat statement có cấu trúc

Template:

```text
T-017: <actor> có thể <action/path> trên <component/flow>
khi <preconditions>, dẫn đến <impact trên asset/objective>.
Evidence/assumption: ...
```

Ví dụ:

```text
T-017: Merchant A có thể gửi orderId của Merchant B vào refund API
khi service authorize role nhưng không bind resource với tenant,
dẫn đến refund cross-tenant và sai lệch sổ cái.
```

Tránh nhét mitigation vào tên threat. Tách threat, response, control và verification để giữ
traceability khi giải pháp thay đổi.

## 22. Attack tree cho goal phức tạp

Attack tree bắt đầu bằng attacker goal, phân rã AND/OR:

```text
Goal: tạo refund trái phép
├── OR: chiếm session của operator
│   ├── phishing
│   └── steal session from support browser
├── OR: bypass object authorization
│   ├── đoán order ID
│   └── confuse tenant context
└── OR: giả payment webhook
    ├── lấy signing secret
    └── replay event hợp lệ AND thiếu idempotency
```

Tree hữu ích để thấy nhiều path cùng đạt một impact và nơi một control chặn nhiều nhánh. Ghi
precondition; không biến cây thành danh sách exploit vô hạn.

## 23. STRIDE, ATT&CK, CAPEC và CWE phục vụ việc khác nhau

| Nguồn | Dùng cho |
|---|---|
| STRIDE | Prompt security property có thể bị vi phạm |
| MITRE ATT&CK | Kỹ thuật adversary quan sát trong thực tế, detection/coverage |
| CAPEC | Pattern tấn công trừu tượng |
| CWE | Loại weakness trong thiết kế/implementation |
| CVE | Instance vulnerability cụ thể trong product/version |

Có thể nối threat → ATT&CK/CAPEC → CWE → control/test, nhưng không ép mapping nếu không giúp quyết
định. ATT&CK không thay application-specific business abuse; CWE không mô tả đầy đủ attacker path.

## 24. Chọn methodology theo mục tiêu

| Phương pháp | Điểm mạnh | Hợp khi |
|---|---|---|
| STRIDE + DFD | Dễ học, engineering-focused | Application/service design |
| Attack tree | Goal/path và control choke point | Fraud, safety, high-value scenario |
| PASTA | Risk/adversary/business driven, nhiều phase | Assessment sâu có thời gian |
| OCTAVE | Organizational asset/risk focus | Enterprise risk workshop |
| VAST | Scale vào Agile/enterprise process | Nhiều team cần chuẩn hóa |
| LINDDUN | Privacy threat prompts | Personal data/privacy engineering |

Không có một phương pháp đúng cho mọi hệ thống. Team mới nên bắt đầu nhỏ với DFD + STRIDE + abuse
story, đo chất lượng outcome rồi mở rộng.

## 25. Privacy threat modeling với LINDDUN

CIA/STRIDE không bao phủ hết privacy. LINDDUN gợi ý các nhóm:

- Linkability;
- Identifiability;
- Non-repudiation;
- Detectability;
- Disclosure of information;
- Unawareness;
- Non-compliance.

Ví dụ hệ thống mã hóa tốt nhưng dùng identifier ổn định xuyên nhiều context vẫn cho phép link
behavior. Privacy objective cần data minimization, purpose limitation, transparency, consent,
retention và data-subject rights, không chỉ access control.

## 26. Threat model software supply chain

Mở rộng DFD về phía build:

```text
developer → source repo → CI runner → dependency registry
          → build/sign → artifact registry → deploy controller → runtime
```

Threat cần xét:

- compromised account/token/runner/action;
- dependency confusion, malicious update hoặc maintainer compromise;
- build script có thể đọc secret;
- artifact/tag bị thay thế;
- provenance/signature không được verify ở deploy;
- branch protection/bypass và untrusted pull request;
- IaC/module/image base drift;
- rollback về artifact vulnerable.

SBOM là inventory, không tự chứng minh artifact an toàn hay đúng provenance.

## 27. Cloud và shared responsibility

Managed service chuyển một số control cho provider nhưng customer vẫn chịu trách nhiệm về:

- identity, policy, resource configuration và tenant isolation;
- data classification, key choice, retention và region;
- network/public exposure và private endpoint;
- application validation/authorization;
- logging, detection, backup và recovery;
- service limit/quota/region failure;
- provider admin/support assumption và contract.

Diagram cả control plane: IAM, KMS, orchestrator, deployment và organization policy. Compromise
control plane thường vượt qua nhiều data-plane boundary.

## 28. Microservice và event-driven system

Threat đặc thù:

- confused deputy: frontend service dùng quyền mạnh thay caller;
- token audience/context bị truyền sai downstream;
- retry tạo duplicate side effect;
- message không provenance, schema hoặc tenant binding;
- poison message làm consumer loop/DoS;
- dead-letter queue lưu PII/secret và quyền quá rộng;
- eventual consistency làm authorization/state stale;
- saga compensation bị gọi trái thứ tự;
- service discovery/sidecar/control-plane compromise;
- tracing header trở thành injection hoặc data leak path.

Mô hình message lifecycle, không chỉ HTTP request path.

## 29. Multi-tenant architecture

Threat model phải theo tenant từ ingress đến storage:

```text
authenticated subject
  → derive trusted tenant context
  → authorize action + resource + tenant
  → tenant-aware query/cache/event/object path
  → tenant-aware audit and export
```

Kiểm tra cross-tenant IDOR, cache key thiếu tenant, shared queue topic, analytics/export, admin
impersonation, noisy-neighbor DoS, key/backup isolation và deletion. Không tin `tenantId` trong
request body nếu server có thể derive từ verified identity/resource relationship.

## 30. Identity plane và authorization model

Vẽ riêng:

- IdP, authenticator, recovery và federation;
- token issuance, exchange, refresh, introspection/revoke;
- policy decision/enforcement point;
- provisioning/offboarding;
- admin/JIT/break-glass;
- workload identity và trust domain.

Threat identity plane có blast radius lớn: token signing key, IdP admin, broad group sync hoặc policy
service compromise. Token hợp lệ không chứng minh quyền trên object; enforcement phải complete và
gắn subject–action–resource–context.

## 31. Admin, support và maintenance path

“Back office” thường ít được model nhưng quyền cao:

- impersonate customer;
- reset MFA/email hoặc unlock account;
- query/export/decrypt dữ liệu;
- sửa feature flag/policy/config;
- replay job/event;
- truy cập debug console/database;
- disable detection hoặc xóa evidence.

Yêu cầu JIT/JEA, maker-checker cho action nguy hiểm, reason/ticket, customer-visible notification
khi phù hợp, immutable audit, session recording có bảo vệ và break-glass review.

## 32. Availability và cyber resilience

Không dừng ở “có rate limiting”. Model:

- resource exhaustion theo CPU, memory, thread, connection, queue, storage, quota, cost;
- amplification qua fan-out/retry/cache miss;
- dependency timeout/circuit breaker/bulkhead;
- lockout/password reset/email/SMS abuse;
- hot tenant/key/partition;
- regional/control-plane outage;
- backup corruption và destructive admin;
- degraded mode làm mất security invariant.

Giả định compromise và thiết kế detect, contain, recover, adapt. Failover chỉ an toàn khi policy,
key, data consistency và authorization vẫn đúng.

## 33. Fraud, safety và privacy impact

CIA chưa đủ cho mọi sản phẩm. Thêm objective:

- tài chính: fraud, chargeback, double spend, ledger mismatch;
- safety: injury, physical process hoặc medical decision;
- privacy: re-identification, surveillance, unlawful processing;
- legal/compliance: reporting, residency, retention;
- abuse: harassment, account farming, market manipulation;
- downstream/ecosystem: partner/customer bị ảnh hưởng.

Một vulnerability kỹ thuật “medium” có thể tạo business impact critical trong flow cụ thể.

## 34. Prioritization không phải phép nhân giả chính xác

Ma trận likelihood × impact hữu ích để thảo luận nhưng ordinal label không phải số đo chính xác.
Lưu riêng các yếu tố:

```text
likelihood: reachability, precondition, attacker capability, exposure, control strength
impact: data, money, safety, availability, legal, tenant count, recovery
confidence: known / assumed / unknown
```

Priority còn phụ thuộc deadline, dependency, control reuse, fix cost và irreversible harm. Không hạ
threat chỉ vì chưa có exploit công khai nếu architecture path rõ và impact lớn.

## 35. Đánh giá likelihood có evidence

Câu hỏi:

- surface có Internet-reachable hay cần internal/admin foothold?
- attacker cần valid account, victim action, race hay physical access?
- precondition hiếm hay do default configuration?
- attack có scale/automation được không?
- control hiện tại được verify hay chỉ dự kiến?
- detection làm giảm dwell time không?
- technique đã quan sát trong threat intelligence/incident tương tự?
- uncertainty lớn đến mức nào?

Không dùng “internal nên low”. Compromised workload hoặc insider có thể đã ở trong boundary.

## 36. Đánh giá impact theo blast radius

Tách:

- một object, một user, một tenant hay toàn hệ thống;
- confidentiality, integrity, availability và accountability;
- immediate và delayed/cascading impact;
- reversible hay irreversible;
- online data, backup, signing trust và downstream consumer;
- detection/recovery time;
- safety, financial, contractual và legal effect.

Key/control-plane compromise thường có concentrated value. Một action nhỏ nhưng không rate limit có
thể thành systemic impact khi tự động hóa.

## 37. Inherent risk, control effectiveness và residual risk

```text
inherent scenario
  → preventive controls
  → detective/corrective/recovery controls
  → verified effectiveness + assumptions
  → residual risk
```

Không đánh dấu “mitigated” chỉ vì ticket tạo xong. Control status nên là proposed, implemented,
verified, monitored hoặc ineffective. Residual risk phải mô tả scenario còn lại, không chỉ đổi màu
từ đỏ sang xanh.

## 38. Bốn cách response

| Response | Ví dụ |
|---|---|
| Eliminate | Bỏ upload executable hoặc bỏ shared admin credential |
| Mitigate | Object authorization, idempotency, signature/replay protection |
| Transfer/share | Provider/insurance/contract, nhưng accountability có thể vẫn còn |
| Accept | Business owner chấp nhận residual risk có thời hạn |

Acceptance cần scope, rationale, owner có thẩm quyền, expiry/review date, compensating detection và
trigger reopen. “Backlog” không đồng nghĩa accepted risk.

## 39. Biến threat thành security requirement

Requirement tốt có subject, behavior, condition và cách verify:

```text
SR-017: Refund API phải derive tenant từ authenticated subject/resource relationship,
authorize `refund` trên order trước mọi state transition, và trả cùng một generic
not-found response cho order ngoài tenant. Negative integration test phải chứng minh
Merchant A không đọc hoặc refund order của Merchant B.
```

“Dùng encryption”, “validate input” hay “theo best practice” quá mơ hồ. Ghi algorithm/protocol,
key owner, scope, failure behavior, telemetry và version chuẩn khi chúng ảnh hưởng verification.

## 40. Dùng control catalog mà không checklist-driven

OWASP ASVS 5.0.0 cung cấp requirement ID versioned cho web application; NIST, CIS hoặc provider
framework có thể bổ sung environment control. Quy trình:

1. bắt đầu từ threat scenario/context;
2. chọn requirement/control phù hợp;
3. tailor cho kiến trúc và assurance cần thiết;
4. thêm application-specific invariant;
5. định nghĩa test/evidence và owner;
6. ghi control nào xử lý threat nào.

Checklist giúp coverage nhưng không phát hiện đầy đủ business logic, unusual trust boundary hoặc
failure mode riêng.

## 41. Traceability từ threat đến evidence

```text
Asset A-03 / Flow F-12
  → Threat T-017
      → Requirement SR-017
          → Design decision ADR-042
              → Code/Policy change PR-812
                  → Test SEC-IT-94
                      → Runtime signal DET-21
                          → Residual risk RR-017
```

Stable ID cho phép kiểm tra threat “mồ côi”, requirement chưa test và control không còn consumer.
Không nhét mọi artifact vào một spreadsheet khổng lồ; dùng liên kết giữa source-of-truth phù hợp.

## 42. Nguyên tắc secure architecture

- least privilege và least functionality;
- fail-safe default/deny by default;
- complete mediation ở mọi access path;
- separation of privilege/duties;
- minimize attack surface và shared mechanism;
- defense in depth với failure độc lập hợp lý;
- secure by default, hard to misuse;
- explicit trust và strong identity;
- data minimization và purpose limitation;
- assume breach, compartmentalize và recover;
- crypto agility, dependency/provenance visibility;
- observability không làm lộ dữ liệu.

Nguyên tắc là lens thiết kế, không phải bằng chứng control đã hoạt động.

## 43. Đặt control ở đúng boundary

Ví dụ request đi qua gateway rồi service:

- gateway có thể verify token format, issuer, audience, rate/size limit;
- service sở hữu resource phải enforce object/action/tenant authorization;
- database có thể bổ sung row/role isolation nhưng không hiểu toàn business invariant;
- queue producer/consumer cùng kiểm tra provenance/schema/idempotency theo vai trò;
- egress proxy giới hạn destination nhưng app vẫn phải chống SSRF redirect/DNS behavior.

Không dồn mọi security vào edge. Internal/cached/async/admin path có thể bỏ qua gateway.

## 44. Secure default và usable security

Control dễ bị bypass nếu đường an toàn quá khó:

- MFA/phishing-resistant option mặc định cho admin;
- private resource và least privilege template mặc định;
- SDK chuẩn hóa auth, logging/redaction, retry và tenant context;
- safe parser/config thay vì mỗi team tự chọn;
- error message hữu ích cho operator nhưng không leak cho attacker;
- recovery/break-glass có thể dùng khi outage và vẫn audit;
- migration/rotation có zero-downtime pattern.

Secure by design đặt trách nhiệm giảm rủi ro lên product/platform, không đẩy cấu hình nguy hiểm
sang customer rồi gọi đó là lựa chọn.

## 45. Verification và validation khác nhau

- Verification: hệ thống/control được xây đúng theo requirement chưa?
- Validation: requirement và hệ thống có giải đúng protection need trong môi trường thật không?

Ví dụ unit test chứng minh signature verifier reject tag sai là verification. End-to-end review cho
thấy webhook có đường debug bỏ qua verifier là validation failure. Cần architecture review, code/
config review, negative test, pentest, chaos/failover drill và production telemetry.

## 46. Sinh test trực tiếp từ threat model

Với mỗi threat critical/high, tạo:

- positive test cho flow hợp lệ;
- negative authorization/tenant/state-transition test;
- parser/schema/fuzz/property-based test;
- concurrency/replay/idempotency test;
- failure-mode test: timeout, stale cache, dependency down;
- policy/IaC test;
- detection test dùng canary action;
- recovery/rollback/failover drill.

Test phải chạy qua đúng path production. Mock authorization/KMS/queue quá sâu có thể bỏ sót boundary
thật.

## 47. Tích hợp vào Agile và DevOps

Pattern nhẹ:

```text
Epic/design: model level 0/1 + top threats
Story: abuse story + security acceptance criteria
PR: cập nhật flow/assumption/requirement liên quan
CI: policy, negative test, diagram/schema validation
Release: unresolved risk + evidence gate
Operate: signal/incident cập nhật model
```

Dùng security champion và office hour cho team; central security review sâu với change rủi ro cao.
Threat model là living artifact, nhưng không bắt mọi PR mở workshop.

## 48. Threat modeling as code và metric

Lưu model có version gần kiến trúc/code nếu không chứa thông tin quá nhạy cảm. Có thể dùng text/
diagram-as-code và structured YAML/JSON cho threat register. Pipeline kiểm tra:

- stable ID/owner/status bắt buộc;
- broken link tới component/requirement/test;
- accepted risk đã quá hạn;
- high threat thiếu verification;
- diagram/component drift qua service catalog/IaC;
- review required khi file/path/tag nhạy cảm đổi.

Metric tốt: time từ design đến response, high threat chưa owner, requirement chưa test, expired
acceptance, model age và incident liên quan assumption sai. Số threat càng nhiều không đồng nghĩa
chất lượng càng cao.

## 49. Ví dụ end-to-end: payment webhook replay

### Model và threat

```text
Flow F-07: Payment Provider → public Webhook Consumer → InBox → Order Worker
Asset A-02: payment/order ledger integrity

T-021: attacker có thể replay một event hợp lệ nhiều lần khi consumer chỉ kiểm tra
signature mà không enforce freshness và event uniqueness, dẫn đến capture/refund lặp.
```

### Response và requirement

```text
Response: mitigate

SR-021a: verify signature trên exact raw body bằng active provider key.
SR-021b: reject timestamp ngoài bounded window theo protocol/provider contract.
SR-021c: atomically insert provider + eventId vào inbox có unique constraint trước side effect.
SR-021d: state transition phải kiểm tra business invariant và idempotency.
SR-021e: duplicate/rejected event tạo metric/audit không chứa payload nhạy cảm.
```

### Verification và residual risk

- replay cùng event tuần tự và đồng thời chỉ tạo một side effect;
- event ID trùng khác merchant/provider không bị namespace confusion;
- crash giữa inbox insert và worker execution phục hồi đúng;
- key rotation N/N+1 vẫn verify đúng, unknown key bị từ chối có rate limit;
- clock/provider outage có behavior đã định nghĩa;
- residual risk: compromised provider signing authority vẫn có thể tạo event mới hợp lệ, nên cần
  amount/order invariant, reconciliation và anomaly detection.

Ví dụ cho thấy “verify HMAC” chỉ xử lý một nhánh, không xử lý replay, state và issuer compromise.

## 50. Checklist, anti-pattern và nguồn chính thức

### Checklist workshop/review

- [ ] Scope/TOE, out-of-scope dependency và assumption có owner.
- [ ] Asset có security/business/privacy/safety objective cụ thể.
- [ ] Actor được mô tả theo capability, không chỉ tên chung.
- [ ] DFD có external entity, process, store, flow và trust boundary đúng độ sâu.
- [ ] Flow quan trọng có identity, protocol, data, tenant, retry và failure annotation.
- [ ] Business state/invariant, admin/control plane và supply-chain path được model.
- [ ] STRIDE/abuse story/attack tree được dùng như prompt phù hợp.
- [ ] Threat statement có actor, action/path, precondition, asset và impact.
- [ ] Priority ghi likelihood, impact, confidence và blast radius; không chỉ màu/điểm.
- [ ] Mỗi threat có response, owner, deadline và residual risk.
- [ ] Mitigation trở thành requirement cụ thể, versioned control reference và test.
- [ ] Traceability nối threat → decision → implementation → evidence → detection.
- [ ] Accepted risk có approver, expiry, rationale và trigger review.
- [ ] Change/incident/dependency trigger cập nhật living threat model.

### Anti-pattern

| Anti-pattern | Hậu quả | Cách sửa |
|---|---|---|
| Vẽ diagram deployment nhưng thiếu data flow | Không thấy boundary/data abuse | DFD có flow ID và annotation |
| Điền đủ STRIDE rồi kết thúc | Threat không thành control | Response → requirement → evidence |
| Chỉ model Internet attacker | Bỏ insider, tenant, CI và workload compromise | Actor theo capability |
| “Internal = trusted” | Lateral movement/confused deputy | Identity, authorize từng boundary |
| Risk = likelihood × impact như số chính xác | Che uncertainty và business context | Lưu factor/evidence/confidence riêng |
| CVSS = business risk | CVSS chỉ severity của vulnerability | Thêm environment, threat và impact context |
| Mitigated vì ticket đã đóng | Không biết control có hiệu lực | Verified + monitored status |
| Threat model một lần trước release | Model drift | Delta review + trigger + version control |
| Security team tự model | Thiếu business/ops reality | Cross-functional ownership |
| Cố liệt kê mọi threat | Workshop kiệt sức, không ra quyết định | Scope, top paths và iterative depth |

### Nguồn chính thức

- [OWASP Threat Modeling Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Threat_Modeling_Cheat_Sheet.html)
- [Microsoft Threat Modeling Fundamentals](https://learn.microsoft.com/en-us/training/paths/tm-threat-modeling-fundamentals/)
- [Threat Modeling Manifesto](https://www.threatmodelingmanifesto.org/)
- [NIST SP 800-160 Vol. 1 Rev. 1 – Engineering Trustworthy Secure Systems](https://csrc.nist.gov/pubs/sp/800/160/v1/r1/final)
- [NIST SP 800-160 Vol. 2 Rev. 1 – Developing Cyber-Resilient Systems](https://csrc.nist.gov/pubs/sp/800/160/v2/r1/final)
- [NIST SP 800-218 – Secure Software Development Framework](https://csrc.nist.gov/pubs/sp/800/218/final)
- [OWASP ASVS 5.0.0](https://owasp.org/www-project-application-security-verification-standard/)
- [OWASP SAMM – Threat Modeling](https://owaspsamm.org/model/design/threat-assessment/stream-b/)
- [MITRE ATT&CK](https://attack.mitre.org/)
- [MITRE CWE](https://cwe.mitre.org/) và [CAPEC](https://capec.mitre.org/)
- [LINDDUN Privacy Threat Modeling](https://linddun.org/)
- [FIRST CVSS v4.0 Specification](https://www.first.org/cvss/v4.0/specification-document)
- [CISA Secure by Design](https://www.cisa.gov/securebydesign)

### Học tiếp

1. [Data Security & Privacy Engineering](../data/data_security_privacy_engineering.md) – classification, retention, tokenization, masking và lineage.
2. [Software Supply Chain Security](../supply_chain/software_supply_chain_security.md) – provenance, signing, SBOM, build isolation và dependency policy.

---

*Cập nhật lần cuối: 2026-08-02.*
