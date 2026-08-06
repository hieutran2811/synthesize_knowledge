# Enterprise Security Architecture & Zero Trust – Từ năng lực đến thực thi chính sách

Enterprise Security Architecture (ESA) không phải bộ sơ đồ đẹp để trình bày, và Zero Trust không phải sản phẩm
"không tin ai". ESA nối mục tiêu kinh doanh với capability, nguyên tắc, pattern, tiêu chuẩn và lộ trình triển khai;
Zero Trust loại bỏ **tin cậy ngầm**, thay bằng quyết định truy cập tường minh, có ngữ cảnh, giới hạn và kiểm chứng được.

```text
business outcome + risk appetite
    → security capabilities + architecture principles
        → reference patterns + policy model
            → PDP / PIP / PEP + platform guardrails
                → evidence + feedback + transformation roadmap
```

Chương này bổ sung góc nhìn enterprise cho [Threat Modeling & Secure Architecture](threat_modeling_secure_architecture.md),
[IAM](../identity/iam_authentication_authorization.md), [Network Defense](../network/network_defense.md) và
[Platform Engineering Security](../platform/platform_engineering_security.md).

---

## 1. Enterprise Security Architecture là gì?

ESA là tập hợp quyết định và artifact giúp nhiều team xây hệ thống theo cùng security outcomes:

- nguyên tắc định hướng khi chưa có thiết kế chi tiết;
- capability map cho biết tổ chức cần làm được gì;
- current-state và target-state architecture;
- reference architecture, pattern và standard tái sử dụng;
- exception, transition architecture và roadmap;
- evidence để biết kiến trúc đã được triển khai và còn hiệu lực.

ESA không thay solution architect. Enterprise architect tạo ngôn ngữ và ràng buộc chung; solution architect áp dụng
chúng vào một hệ thống cụ thể và ghi lại khác biệt.

## 2. Kiến trúc phải tạo outcome, không chỉ tạo diagram

Một kiến trúc có giá trị khi giúp trả lời quyết định thật:

| Câu hỏi | Outcome cần thấy |
|---|---|
| Ai được truy cập dữ liệu nào? | Chính sách và enforcement point cụ thể |
| Một identity bị chiếm thì blast radius bao nhiêu? | Boundary, least privilege và đường lan truyền bị giới hạn |
| IdP/PDP mất thì dịch vụ hoạt động ra sao? | Degraded mode đã thiết kế và kiểm thử |
| Mua hay xây capability? | Tiêu chí, dependency, exit plan và total cost |
| Target state đạt đến đâu? | Coverage và hiệu lực, không phải số sản phẩm đã mua |

Diagram không có owner, assumption, phiên bản và quyết định sử dụng sẽ nhanh chóng thành tài liệu lịch sử.

## 3. Các tầng artifact kiến trúc

Từ ổn định đến thay đổi nhanh:

1. **Principle:** ví dụ mọi access đều được quyết định theo subject, resource, action và context.
2. **Capability:** tổ chức cần identity proofing, device posture, policy decision, key management...
3. **Reference architecture:** các building block và quan hệ chuẩn, không khóa vào vendor.
4. **Pattern:** cách giải quyết lặp lại như workforce-to-SaaS hay service-to-service.
5. **Standard/guardrail:** yêu cầu bắt buộc, phiên bản và conformance test.
6. **Solution design:** triển khai cụ thể cho một product/environment.

Không nhảy thẳng từ principle sang tên công cụ; khoảng giữa chính là nơi semantics và integration dễ bị bỏ sót.

## 4. Operating model và quyền quyết định

ESA cần ranh giới trách nhiệm rõ:

- business/risk owner xác định outcome và residual risk chấp nhận được;
- security architecture sở hữu principle, capability model và reference pattern;
- domain architect sở hữu identity, data, cloud, network hoặc application semantics;
- platform team cung cấp paved road và enforcement dùng chung;
- product team sở hữu cách dùng đúng trong workload;
- assurance xác minh design, implementation và operation;
- architecture review board giải quyết quyết định xuyên domain, không duyệt từng thay đổi nhỏ.

RACI chỉ hữu ích khi đi cùng decision right: ai được chuẩn hóa, ai được cấp exception và ai có quyền dừng rollout.

## 5. Bắt đầu từ mission và business capability

Không bắt đầu chương trình bằng câu "triển khai Zero Trust". Hãy bắt đầu bằng luồng giá trị:

```text
customer onboarding → identity verification → account activation → transaction → settlement
```

Với mỗi bước, xác định critical outcome, data, actor, dependency, tolerance với gián đoạn và fraud. Security capability
sau đó bảo vệ outcome: strong customer authentication, transaction authorization, immutable evidence, recovery...

Hai hệ thống cùng dùng Kubernetes không nhất thiết có cùng target architecture nếu mission impact và threat khác nhau.

## 6. Scope, context, current state và target state

Mỗi engagement cần ghi:

- enterprise/domain/system trong scope và phần ngoài scope;
- stakeholder, regulatory constraint và risk assumption;
- current state dựa trên inventory/evidence, gồm cả shadow path;
- target state theo horizon thời gian;
- transition state có thể vận hành an toàn;
- dependency, blocker, cost và quyết định không thực hiện.

Target state không phải "mọi thứ optimal". Nó là trạng thái đủ để đạt outcome trong risk appetite đã thống nhất.

## 7. Architecture principles hữu dụng

Principle tốt phải định hướng trade-off và có hệ quả:

- bảo vệ resource thay vì tin network zone;
- identity cho human, device và workload đều có lifecycle;
- deny by default, grant tối thiểu, có thời hạn khi phù hợp;
- policy tách khỏi application khi cần nhất quán nhưng enforcement ở gần resource;
- mọi đường truy cập quản trị đều là production path;
- control plane được cô lập, phục hồi và audit mạnh hơn data plane;
- evidence được thiết kế cùng control;
- failure mode là một phần kiến trúc, không để runtime tự quyết.

Nếu principle không thay đổi quyết định nào, nó chỉ là khẩu hiệu.

## 8. Security capability map

Capability mô tả **khả năng**, không mô tả sản phẩm hay sơ đồ tổ chức:

| Nhóm | Capability ví dụ |
|---|---|
| Govern | risk decision, policy lifecycle, exception, assurance |
| Identify | inventory, identity lifecycle, classification, dependency mapping |
| Protect | access decision, isolation, encryption, secret/key lifecycle |
| Detect | telemetry, correlation, behavioral detection, control-health signal |
| Respond | contain identity/workload/data path, evidence preservation |
| Recover | trusted rebuild, credential recovery, policy/config restore |

Đánh giá từng capability theo people, process, data, technology và integration. "Có tool" không đồng nghĩa capability hoạt động.

## 9. Control plane, data plane và management plane

- **Data plane** xử lý request/data nghiệp vụ.
- **Control plane** phân phối policy, identity, route, key hoặc desired state.
- **Management plane** cho operator quản trị hệ thống và control plane.

Compromise control plane thường tạo blast radius lớn hơn một workload. Vì vậy cần identity riêng, privileged workflow,
segmentation, signed change, independent evidence, backup và recovery drill. Không để management endpoint dùng chung
public ingress hoặc phụ thuộc duy nhất vào chính control plane mà nó cần khôi phục.

## 10. Trust model và trust boundary

Trust model ghi rõ hệ thống chấp nhận assertion nào, từ ai, trong bao lâu và dùng để quyết định gì. Boundary xuất hiện khi:

- principal hoặc administrative authority thay đổi;
- dữ liệu đổi classification/tenant/purpose;
- execution environment hoặc ownership thay đổi;
- control chuyển sang SaaS, partner hay shared platform;
- evidence không còn cùng mức assurance.

"Internal" không phải trust level. Mỗi boundary cần protocol, identity, authorization, validation, telemetry và failure behavior.

## 11. Hiểu đúng Zero Trust

Theo NIST SP 800-207, không cấp tin cậy ngầm chỉ vì user/asset ở LAN, thuộc tổ chức hay do tổ chức sở hữu. Trọng tâm
chuyển từ bảo vệ segment sang bảo vệ resource; authentication và authorization diễn ra tường minh trước session.

Zero Trust không có nghĩa mọi thứ luôn độc hại hoặc không bao giờ tin. Nó nghĩa là trust:

- dựa trên evidence phù hợp;
- chỉ đủ cho action/resource cần thiết;
- có thời hạn và context;
- có thể đánh giá lại và thu hồi;
- không tự động lan từ một resource sang resource khác.

## 12. Các tenet vận hành của Zero Trust

Một target architecture nên thể hiện:

1. resource và principal có inventory/identity đáng tin cậy;
2. communication được bảo vệ bất kể vị trí mạng;
3. access được cấp theo từng resource/action/session;
4. policy xét identity, device/workload state, resource và context;
5. posture được quan sát, freshness và confidence được biết;
6. authentication/authorization là động trong giới hạn kỹ thuật;
7. telemetry cải thiện policy và phát hiện bất thường.

Không phải request nào cũng gọi remote PDP; nhưng quyết định cached phải có TTL, version, revoke semantics và fallback rõ.

## 13. Năm trụ cột và ba năng lực xuyên suốt của CISA

CISA Zero Trust Maturity Model v2 dùng năm trụ cột:

1. Identity;
2. Devices;
3. Networks;
4. Applications and Workloads;
5. Data.

Ba capability xuyên suốt là Visibility and Analytics, Automation and Orchestration, Governance. Bốn mức trưởng thành
Traditional, Initial, Advanced, Optimal là gradient; không cần mọi pillar cùng mức. Chọn bước tiếp theo theo risk, dependency
và giá trị, không chạy theo badge "optimal".

## 14. Identity pillar

Identity architecture cần bao phủ workforce, customer, partner, machine và emergency identity:

- authoritative source và proofing phù hợp;
- joiner/mover/leaver cùng reconciliation;
- phishing-resistant authentication cho đường rủi ro cao;
- federation có issuer, audience, claim và trust lifecycle;
- authorization theo effective permission, không chỉ group trực tiếp;
- privileged access JIT/JEA và session evidence;
- recovery mạnh tương đương hoặc mạnh hơn login.

MFA không sửa được authorization quá rộng hay session token bị đánh cắp.

## 15. Device pillar

Device posture là **evidence**, không phải giấy thông hành vĩnh viễn. Policy có thể xét:

- device identity và ownership;
- managed/enrolled state;
- secure boot, disk encryption, screen lock;
- OS/agent version và vulnerability state;
- endpoint health, compromise signal;
- observation time, freshness và confidence.

Quyết định nên phân tầng: deny, chỉ cho remediation portal, read-only, step-up hoặc full access. Nếu posture service mất,
kiến trúc phải biết signal nào được cache bao lâu và resource nào buộc fail closed.

## 16. Network pillar

Network vẫn quan trọng nhưng trở thành một lớp signal và containment:

- authenticated/encrypted connection;
- ingress/egress control theo workload và destination;
- segmentation giới hạn reachability và blast radius;
- private connectivity cho control/management path khi cần;
- DNS, proxy và flow evidence phục vụ detection;
- chống bypass origin, alternate route và unmanaged tunnel.

IP/subnet không phải identity ổn định. Microsegmentation không thay application authorization hoặc data policy.

## 17. Application và workload pillar

Application phải biết resource, tenant, action và business invariant. Workload cần identity riêng theo environment/chức năng,
credential ngắn hạn và authorization service-to-service. Các enforcement point thường gồm API gateway, proxy/sidecar,
service framework, queue consumer và database/data gateway.

NIST SP 800-207A nhấn mạnh application/service identity và policy chi tiết trong multi-cloud. Network allow-list đơn thuần
không đủ khi workload co giãn, đổi IP hoặc chạy qua nhiều provider.

## 18. Data pillar

Data-centric architecture bảo vệ theo classification, owner, purpose, tenant và lifecycle:

- discovery/classification có confidence;
- authorization tại read, write, export, share và administrative access;
- encryption và key boundary phù hợp;
- masking/tokenization/minimization theo use case;
- lineage và provenance cho copy/derived data;
- retention, legal hold và deletion có verification;
- egress control và anomaly signal.

Chặn network path không ngăn authorized user dùng dữ liệu sai mục đích.

## 19. Visibility và analytics

Telemetry phải tái dựng được quyết định:

```text
request_id + subject + resource + action + context_snapshot
  + policy_version + decision + enforcement_result + timestamp
```

Phân biệt policy **đã quyết định allow** với PEP **đã thực thi allow**. Log cần clock discipline, provenance, access control,
retention và privacy guardrail. Analytics tốt tìm privilege drift, impossible path, bypass và control-health degradation;
không chỉ đếm login thất bại.

## 20. Automation, orchestration và governance

Automation giảm revoke latency và cấu hình lệch, nhưng có thể khuếch đại sai policy. Mọi automation quan trọng cần:

- source/authenticity của signal;
- idempotency, rate limit và blast-radius guard;
- approval theo risk;
- dry-run/canary và rollback;
- audit của input, decision, actor và outcome;
- human override có thời hạn.

Governance xác định taxonomy, owner, exception, conformance và priority giữa các pillar; không phải lớp báo cáo sau cùng.

## 21. Mô hình policy: subject, resource, action, context

Một request authorization tối thiểu gồm:

```yaml
subject: {type: workload, id: payment-api, tenant: merchant-a}
resource: {type: refund, id: r-123, owner_tenant: merchant-a}
action: approve
context: {environment: prod, amount: 900, device_assurance: high, time: "..."}
```

Policy phải định nghĩa semantics của missing/unknown/stale attributes. Không mặc định `null == false` hay dùng claim do client
tự khai. Business invariant như separation of duties và transaction limit thường phải được thực thi trong application domain.

## 22. PDP, PIP, PEP và Policy Administrator

- **PDP** (Policy Decision Point) tính allow/deny và obligation.
- **PIP** (Policy Information Point) cung cấp identity, posture, risk và resource attributes.
- **PEP** (Policy Enforcement Point) chặn request và thực thi decision.
- **Policy Administrator** thiết lập/đóng kết nối hoặc phân phối configuration theo mô hình NIST.

Luồng đơn giản:

```text
subject → PEP ── decision request ──→ PDP ← attributes ── PIP
             ← allow/deny/obligation ─┘
             → resource only after enforcement
```

PDP đúng nhưng request có đường vòng không qua PEP vẫn là kiến trúc thất bại.

## 23. Vòng đời policy

Policy là production code và cần:

1. owner, objective, scope và data contract;
2. source control, review và signed provenance;
3. static/schema test, unit/negative/property test;
4. simulation trên traffic đại diện;
5. canary/shadow evaluation;
6. staged rollout theo failure domain;
7. version trong decision log;
8. rollback, deprecation và exception expiry.

Thay đổi attribute schema có thể nguy hiểm như thay policy. Producer và consumer cần compatibility contract.

## 24. PDP tập trung hay phân tán

| Mô hình | Lợi ích | Rủi ro |
|---|---|---|
| Central PDP | semantics nhất quán, update nhanh | latency, availability, concentration |
| Local PDP | nhanh, chịu partition tốt | drift, rollout/revoke chậm, footprint lớn |
| Embedded library | domain context sâu | language/version fragmentation, bypass |
| Hybrid | cân bằng theo risk | phức tạp về cache/version/ownership |

Thực tế thường dùng central policy management, signed bundle phân phối và local evaluation. Phải đo policy propagation,
cache age và revoke-to-deny latency, không chỉ uptime của policy service.

## 25. Đặt PEP và kiểm tra coverage

Lập inventory cho mọi đường vào resource:

- public/private ingress và origin;
- synchronous API, WebSocket và callback;
- queue/topic, batch job và file import;
- database, object storage và analytics query;
- admin/debug/support route;
- backup/restore, replication và DR;
- service mesh bypass, host network và direct endpoint.

Với mỗi path ghi PEP, policy, identity, telemetry và bypass test. Coverage có mẫu số phải là tổng đường truy cập quan trọng,
không phải tổng agent đã cài.

## 26. Session, continuous evaluation và thu hồi

Không phải giao thức nào cũng hỗ trợ kiểm tra liên tục. Thiết kế cần phân biệt:

- authentication time, token issue time và last policy evaluation;
- token TTL, session TTL và idle timeout;
- event nào buộc step-up, re-evaluate hoặc terminate;
- push revoke, introspection, deny list hay chờ expiry;
- long-running stream/job xử lý policy change thế nào.

"Continuous" nên được mô tả bằng SLO như revoke-to-deny dưới N phút cho privileged session. Token ngắn hạn giảm cửa sổ
rủi ro nhưng làm tăng dependency vào issuer; cần cân bằng availability.

## 27. Human, workload và device identity

Ba loại identity có lifecycle và assurance khác nhau:

| Identity | Bootstrap | Rotation/revoke | Sai lầm phổ biến |
|---|---|---|---|
| Human | proofing + IdP | HR/event + session revoke | shared admin, group tích lũy |
| Workload | attested runtime/deployment | tự động, ngắn hạn | shared static secret |
| Device | enrollment + hardware/software evidence | lost/retired/compromised | tin device chỉ vì MDM enrolled |

Đừng nhét workload vào human service account. Identity phải bind với code/deployment/environment đủ hẹp để policy có nghĩa.

## 28. Access proxy/ZTNA và authorization trong ứng dụng

ZTNA/access proxy có thể ẩn resource, xác thực user/device và thay VPN cấp quyền vào cả subnet. Tuy nhiên proxy thường chỉ
biết user được mở ứng dụng nào; nó không luôn biết user có được hoàn tiền giao dịch cụ thể hay đọc tenant khác không.

```text
ZTNA/access proxy: có được đến application?
application/API policy: có được thực hiện action trên resource này?
data policy: có được dùng/xuất dữ liệu cho purpose này?
```

Cần cả ba lớp theo risk. Không dùng header do client có thể giả làm identity; trust chỉ assertion từ proxy đã xác thực và
chặn direct-origin bypass.

## 29. Segmentation và microsegmentation

Segmentation tách theo environment, sensitivity, tenant, workload role hoặc failure domain để giảm reachability. Thiết kế tốt:

- bắt đầu từ observed dependency nhưng không tự động allow mọi traffic lịch sử;
- default deny với explicit dependency owner;
- kiểm soát cả east-west và egress;
- có DNS/service identity thay IP tĩnh khi phù hợp;
- test alternate path và emergency access;
- quan sát deny để sửa dependency hợp lệ mà không mở rộng vô hạn.

Microsegmentation giới hạn blast radius; nó không sửa vulnerability, privilege quá rộng hoặc business authorization sai.

## 30. TLS, mTLS và giới hạn của cryptographic identity

TLS bảo vệ kênh; mTLS thêm xác thực hai peer sở hữu private key tương ứng certificate. Nhưng mTLS không tự chứng minh:

- workload đang chạy code được phê duyệt;
- principal được phép thực hiện action nghiệp vụ;
- request không replay hoặc dữ liệu đầu vào hợp lệ;
- certificate chưa bị dùng sai trong thời gian còn hạn.

Cần CA/trust-domain boundary, issuance policy, rotation, revocation, key protection và authorization dựa trên identity đã xác
thực. Không biến "có certificate" thành quyền gọi mọi service.

## 31. Chính sách lấy dữ liệu làm trung tâm

Policy data nên theo sát resource khi nó được copy, transform hoặc xuất:

```text
classification + owner + tenant + purpose + residency + retention + lineage
```

Enforcement có thể nằm ở API, query gateway, lakehouse policy, object store, DLP/egress và application logic. Mỗi lớp có
semantic khác nhau; tránh nghĩ một tag duy nhất tự động bảo vệ mọi bản sao. Derived dataset cần kế thừa hoặc tính lại policy,
và declassification phải là quyết định có evidence.

## 32. API, SaaS, event và luồng bất đồng bộ

Zero Trust không chỉ dành cho HTTP request:

- API kiểm issuer/audience/scope và resource-level authorization;
- webhook có source authentication, replay defense và idempotency;
- producer/consumer của topic có identity riêng và topic/record policy;
- message mang provenance tối thiểu, không tin tùy ý claim trong payload;
- delayed job xử lý quyền bị thu hồi theo rule đã định;
- SaaS có federation, provisioning, admin boundary, export/audit và offboarding.

Queue ACL cho phép đọc topic không đồng nghĩa consumer được xử lý mọi tenant record.

## 33. Hybrid và multi-cloud

Enterprise standard nên thống nhất **outcome và semantics**, không ép mọi provider dùng cùng API:

- canonical principal/resource/action taxonomy;
- trust giữa issuer và workload identity domain;
- policy objective và minimum evidence;
- key/data/administrative boundary;
- cross-cloud connectivity và egress;
- centralized visibility với provenance;
- provider outage, account isolation và exit/recovery plan.

NIST SP 800-207A gợi ý kết hợp API gateway, sidecar/proxy và application identity infrastructure cho policy granular. Chọn
component theo use case; service mesh không phải điều kiện bắt buộc của Zero Trust.

## 34. Kubernetes, service mesh và workload identity

Trong Kubernetes, identity không nên dừng ở cluster hoặc namespace:

- ServiceAccount riêng, token projected ngắn hạn;
- bind identity với namespace, account, cluster/trust domain và deployment metadata;
- admission kiểm image/provenance/security context;
- NetworkPolicy/mesh giới hạn reachability;
- application authorization vẫn kiểm tenant/resource/action;
- cấm direct endpoint, hostNetwork hay debug path bypass PEP;
- bootstrap node/control plane và certificate rotation được threat model.

Sidecar coverage không mặc định 100%; inventory workload không inject, init/ephemeral container và egress path.

## 35. Platform và golden path

Platform biến kiến trúc thành trải nghiệm mặc định:

- template tạo workload identity và least-privilege skeleton;
- ingress/gateway có authn, rate limit và decision logging;
- secret/key vending thay credential tĩnh;
- policy test chạy trong CI và admission;
- telemetry/evidence được bật theo mặc định;
- exception workflow có owner, expiry và compensating control.

Golden path cần dễ hơn đường tự lắp ghép. Đo adoption và conformance trên effective runtime state, không chỉ repository có
file template.

## 36. Brownfield và hệ thống legacy

Legacy có thể thiếu modern identity, TLS, API hoặc khả năng gọi PDP. Các lựa chọn chuyển tiếp:

1. đặt identity-aware proxy/gateway trước resource;
2. cô lập segment và chỉ cho broker/jump workflow truy cập;
3. vault/rotate credential, giảm quyền và theo dõi session;
4. adapter biến coarse permission thành workflow hẹp;
5. read-only hoặc giới hạn dữ liệu/chức năng;
6. lên kế hoạch replatform/decommission với deadline.

Compensating control phải ghi rõ coverage, residual risk, health signal và expiry. Không gọi proxy bọc ngoài là "đã Zero Trust"
nếu bên trong vẫn có shared admin và lateral path rộng.

## 37. Third-party, partner và external access

Partner access cần lifecycle hai phía:

- sponsor/business owner và contract purpose;
- federation trust, claim mapping và assurance;
- resource/action/tenant scope tối thiểu;
- managed/unmanaged device decision;
- data sharing, onward transfer và retention;
- monitoring, periodic review và incident notification;
- revoke khi hợp đồng, người dùng hoặc posture thay đổi.

Không đưa partner VPN vào internal network rộng. M&A integration nên coi hai bên là trust domain riêng cho tới khi inventory,
identity và control posture được xác minh.

## 38. Privileged, support và emergency path

Admin plane phải mạnh hơn user plane:

- separate privileged identity và hardened admin workstation;
- JIT/JEA, approval và purpose binding;
- session recording/evidence phù hợp privacy;
- command/action guardrail và dual control cho việc phá hủy lớn;
- break-glass credential bảo vệ ngoại tuyến, test định kỳ;
- emergency use tạo alert, retrospective review và rotation;
- đường recovery không phụ thuộc vòng tròn vào IdP/PDP đang hỏng.

Support impersonation là privileged access, không phải tính năng tiện lợi; phải hiển thị actor thật và customer/tenant context.

## 39. Availability và failure behavior

Với mỗi dependency IdP, PIP, PDP, certificate issuer, DNS hoặc policy distributor, lập bảng:

| Failure | Resource tier | Hành vi cho phép |
|---|---|---|
| PDP timeout | giao dịch ghi | fail closed hoặc quyết định local còn hạn |
| Device posture stale | portal nội bộ | read-only/remediation, không full access |
| IdP outage | public read | tiếp tục session hợp lệ trong TTL giới hạn |
| Revocation feed lag | admin | dừng cấp mới, step-up/terminate theo risk |

Fail open/closed không nên là một cờ toàn hệ thống. Thiết kế per action, có bounded cache, alert, recovery objective và drill.

## 40. Cyber resilience: anticipate, withstand, recover, adapt

NIST SP 800-160 Vol. 2 mô tả cyber resilience là khả năng dự đoán, chịu đựng, phục hồi và thích nghi trước adverse condition,
attack hoặc compromise. Áp dụng vào ZTA:

- **anticipate:** inventory, threat model, dependency/failure analysis;
- **withstand:** segmentation, diversity, least privilege, graceful degradation;
- **recover:** trusted policy/config/key restore, identity recovery, clean rebuild;
- **adapt:** học từ incident/test, đổi policy/pattern và target state.

Zero Trust giảm blast radius nhưng không tự tạo recovery. Control plane và source of truth đều cần khả năng khôi phục tin cậy.

## 41. Architecture observability và evidence

Không chỉ quan sát workload; hãy quan sát kiến trúc có còn đúng:

- % critical access paths có PEP không bypass;
- policy bundle age/version và distribution lag;
- attribute freshness/unknown rate;
- decision-to-enforcement mismatch;
- stale identity/static credential/effective privilege;
- exception hết hạn và compensating-control health;
- revoke-to-deny latency;
- recovery test result.

Evidence cần map từ principle → requirement → implementation → test → runtime signal, có scope và observation time.

## 42. Threat-informed architecture và attack path

Threat modeling giúp ưu tiên boundary và enforcement:

```text
compromised contractor identity
  → unmanaged device
    → support portal
      → tenant switch
        → export API
          → bulk customer data
```

Kiến trúc cắt path bằng device tier, JIT support role, tenant-bound authorization, export approval/rate limit và anomaly signal.
Đừng credit cùng một control nhiều lần nếu các bước cùng phụ thuộc một IdP/PDP hoặc shared administrator.

## 43. Reference pattern và anti-pattern

Reference pattern nên gồm context, forces, diagram, identity/policy flow, failure mode, controls, evidence và known limits.

Các pattern hữu ích: workforce-to-SaaS, user-to-application, service-to-service, partner access, privileged administration,
data export, legacy proxy và cross-cloud workload. Các anti-pattern:

- mua ZTNA rồi tuyên bố hoàn tất Zero Trust;
- mọi service được mTLS nên cho phép gọi lẫn nhau;
- policy engine tồn tại nhưng application có direct path;
- central PDP không có degraded mode;
- copy một policy cho mọi business domain;
- "internal" hoặc "managed" được coi là trusted vĩnh viễn.

## 44. ADR, waiver và exception

Architecture Decision Record (ADR) ghi context, options, decision, consequence và trigger xem lại. Nó giải thích **vì sao**;
standard nói **phải làm gì**. Khi solution chưa conform:

- waiver cho requirement chưa áp dụng trong scope cụ thể;
- exception cho sai lệch có owner, expiry và compensating control;
- risk acceptance do đúng authority quyết residual risk;
- technical debt item tài trợ con đường trở lại target state.

Không dùng ADR để tự cấp risk acceptance hoặc biến temporary transition thành kiến trúc vĩnh viễn.

## 45. Standard, pattern và lựa chọn công nghệ

Chọn công nghệ sau khi xác định capability và scenario. Scorecard nên xét:

- policy/resource semantics và PEP coverage;
- open protocol, interoperability và portability;
- latency, scale, partition/failure behavior;
- identity bootstrap, key/trust lifecycle;
- audit/evidence và privacy;
- administrative blast radius;
- integration/operating skill và total cost;
- data residency, supplier dependency và exit plan.

Proof of concept phải kiểm negative path, bypass và outage, không chỉ happy-path login demo.

## 46. Validation và conformance

Kiểm thử target architecture ở nhiều lớp:

1. policy unit/negative/property tests;
2. conformance test cho gateway/SDK/platform template;
3. integration test identity, attributes và obligations;
4. bypass test direct origin/admin/async path;
5. stale/missing/conflicting attribute test;
6. PDP/PIP/IdP outage và network partition;
7. revoke, key rotation và policy rollback;
8. safe adversary emulation và recovery drill.

Diagram review chỉ đánh giá design intent; runtime evidence mới chứng minh effective implementation.

## 47. Transformation roadmap từ current đến target

Không big-bang. Chia wave theo dependency và risk:

```text
Wave 0: inventory + identity/resource taxonomy + critical paths
Wave 1: strong identity + privileged path + policy/evidence foundation
Wave 2: critical apps/data + PEP coverage + segmentation
Wave 3: workload identity + hybrid/multi-cloud + legacy containment
Wave 4: automation + continuous evaluation + optimization
```

Mỗi initiative cần outcome, baseline, owner, dependency, milestone, metric, residual risk và exit criteria. Chọn lighthouse
system có giá trị đại diện nhưng blast radius kiểm soát được; sau đó productize pattern thành platform capability.

## 48. Metrics và maturity

Metric tốt đo hiệu lực và giảm exposure:

- critical resource/access-path inventory coverage;
- % đường quan trọng có non-bypassable PEP và negative test pass;
- effective least-privilege/JIT coverage;
- static/shared credentials bị loại bỏ;
- median/p95 revoke-to-deny và policy propagation;
- stale posture/attribute rate;
- exception quá hạn và control-health coverage;
- attack-path reachability/blast radius giảm;
- recovery objective đạt trong drill.

Số policy, số agent, số login MFA hoặc chi phí công cụ là activity/input, không tự chứng minh Zero Trust outcome.

## 49. Ví dụ end-to-end: partner thực hiện refund

**Scenario:** nhân viên đối tác cần refund đơn hàng của chính merchant, tối đa hạn mức được phê duyệt.

1. Federation xác thực partner user; sponsor/lifecycle còn hiệu lực.
2. Access proxy chỉ mở refund application, kiểm device posture và session risk.
3. API PEP gửi subject, merchant, order, amount, action và context tới PDP.
4. PIP lấy entitlement, merchant relationship, transaction state và approval limit.
5. PDP trả allow cùng obligation `step_up`/`dual_approval`, hoặc deny reason chuẩn hóa.
6. Application kiểm invariant: order thuộc merchant, chưa refund, amount hợp lệ.
7. Service dùng workload identity riêng tới payment service; không chuyển user token tùy tiện.
8. Decision/enforcement/business event có correlation ID và policy version.
9. Bulk/anomalous refund kích hoạt contain session và revoke; không chờ token dài hạn hết hạn.
10. IdP/PDP outage chuyển write action sang fail closed; operator dùng recovery path độc lập đã drill.

Outcome là quyền bị giới hạn theo identity, device, resource và transaction—not chỉ "partner đã qua VPN".

## 50. Checklist, anti-pattern và tài liệu chính thức

### Checklist production

- [ ] Mission outcome, risk appetite, scope, current/target/transition state đã rõ.
- [ ] Principle, capability, reference pattern, standard và solution artifact không bị trộn lẫn.
- [ ] Human, workload, device và resource có inventory/lifecycle/owner.
- [ ] Policy dùng subject–resource–action–context với semantics cho stale/missing data.
- [ ] PDP/PIP/PEP/Policy Administrator và trust boundary được mô tả rõ.
- [ ] Mọi critical sync/async/admin/DR path có PEP và bypass test.
- [ ] Network location là signal/containment, không phải nguồn tin cậy duy nhất.
- [ ] ZTNA, segmentation, mTLS và MFA không bị coi là thay application/data authorization.
- [ ] Policy bundle, attribute, token/session có version, freshness, revoke và rollback semantics.
- [ ] IdP/PDP/PIP/issuer outage có hành vi theo resource/action tier và được drill.
- [ ] Control/management plane được cô lập, audit và phục hồi độc lập.
- [ ] Brownfield/partner/SaaS/multi-cloud có transition, residual risk và exit plan.
- [ ] Roadmap theo risk/dependency, mỗi wave có measurable exit criteria.
- [ ] Metrics đo effective coverage, propagation/revoke latency, blast radius và recovery.

### Anti-pattern thường gặp

- "Zero Trust nghĩa là không bao giờ tin bất kỳ ai."
- "Mua một sản phẩm ZTNA là hoàn tất Zero Trust."
- "Đã ở private network/managed device nên không cần authorization."
- "Có mTLS nghĩa là workload được quyền làm mọi action."
- "Microsegmentation sửa được lỗi phân quyền trong ứng dụng."
- "PDP trả deny nên không cần kiểm đường bypass PEP."
- "Fail closed cho mọi thứ luôn an toàn hơn" mà không xét mission/recovery impact.
- "Continuous evaluation" nhưng token, cache và session không có revoke semantics.
- "Optimal ở mọi pillar" là mục tiêu bất kể risk và dependency.
- Đếm policy/agent/tool thay cho đo security outcome.

### Tài liệu chính thức

- [NIST SP 800-207 – Zero Trust Architecture](https://csrc.nist.gov/pubs/sp/800/207/final)
- [NIST SP 800-207A – ZTA for Cloud-Native Applications in Multi-Cloud](https://csrc.nist.gov/pubs/sp/800/207/a/final)
- [NIST SP 1800-35 – Implementing a Zero Trust Architecture](https://www.nccoe.nist.gov/publications/practice-guide/implementing-zero-trust-architecture-nist-sp-1800-35-practice-guide-6)
- [CISA Zero Trust Maturity Model Version 2.0](https://www.cisa.gov/sites/default/files/2023-04/zero_trust_maturity_model_v2_508.pdf)
- [NIST SP 800-160 Vol. 1 Rev. 1 – Systems Security Engineering](https://csrc.nist.gov/pubs/sp/800/160/v1/r1/final)
- [NIST SP 800-160 Vol. 2 Rev. 1 – Developing Cyber-Resilient Systems](https://csrc.nist.gov/pubs/sp/800/160/v2/r1/final)

### Học tiếp

1. [Business Continuity, Disaster Recovery & Cyber Resilience](../resilience/business_continuity_disaster_recovery_cyber_resilience.md) – BIA, dependency, recovery strategy,
   crisis coordination và resilience validation.
2. [Third-Party & SaaS Security Assurance](../third_party/third_party_saas_security_assurance.md) – due diligence, continuous assurance, access/data boundary,
   contract control và exit planning.

---

*Cập nhật lần cuối: 2026-08-03.*
