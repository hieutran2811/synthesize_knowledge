# Cloud IAM Governance at Scale – Quản trị quyền trên quy mô organization

Cloud IAM ở một account đơn lẻ thường được mô tả bằng câu hỏi “ai được làm gì trên
resource nào?”. Ở quy mô hàng trăm account, subscription, project và tenant, câu hỏi khó
hơn nhiều:

- identity nào là nguồn tin cậy và ai chịu trách nhiệm cho lifecycle của nó;
- policy ở organization/folder/account/resource kết hợp thành quyền thực tế ra sao;
- team được tự quản đến đâu mà không trở thành “mini-root”;
- quyền đặc quyền được cấp tạm thời, review và thu hồi thế nào;
- workload ở cloud/CI/SaaS khác nhau nhận credential mà không dùng key dài hạn ra sao;
- khi identity hoặc control plane bị compromise, blast radius được xác định và chặn thế nào.

Chương này tập trung vào governance và operating model đa account/multi-cloud. Phần cơ
bản về password, MFA, session, OAuth/OIDC, JWT, RBAC/ABAC và SCIM đã có trong chương
[Identity & Access Management](../identity/iam_authentication_authorization.md).

---

## 1. Cloud IAM governance không chỉ là authentication

Authentication chứng minh một principal là ai. Authorization quyết định request cụ thể
được phép hay không. **IAM governance** quản lý toàn bộ hệ thống tạo ra quyết định đó:

```text
authoritative identity + lifecycle
    → group / role / entitlement model
        → organization hierarchy + policy inheritance
            → access request / approve / activate
                → effective permission + session
                    → observe / review / revoke / prove
```

MFA mạnh không bù được role admin tồn tại vĩnh viễn. Policy least privilege trong một
project cũng không đủ nếu principal có quyền sửa policy ở folder cha. Governance phải
nhìn cả **quyền sử dụng resource** và **quyền thay đổi hệ thống cấp quyền**.

---

## 2. Mô hình đồ thị identity–permission–resource

Danh sách role riêng lẻ không thể hiện đầy đủ quyền. Hãy xem IAM như đồ thị:

- **principal**: user, group, workload, service account, external identity, agent;
- **credential/session**: token, certificate, role session, federated assertion;
- **entitlement**: role, permission set, policy binding, access package;
- **policy edge**: allow, deny, boundary, condition, delegation, trust;
- **resource**: organization, folder/OU, account/subscription/project, service object;
- **control principal**: IdP admin, organization admin, policy engine, automation;
- **provenance**: ai/tác vụ nào tạo edge, lúc nào, vì sao và hết hạn khi nào.

Risk thường nằm trên một đường đi, không nằm ở một node: user → group → role → ability
to pass service identity → privileged workload → data. Inventory chỉ đếm role sẽ bỏ lỡ
đường leo thang này.

---

## 3. Xác định scope: tenant, organization và cloud boundary

Trước khi thiết kế, lập bản đồ:

| Lớp | Ví dụ câu hỏi |
|---|---|
| Enterprise identity | HR, directory, partner IdP nào authoritative? |
| Cloud organization | AWS Organization, Entra tenant/Azure hierarchy, Google Cloud organization nào? |
| Resource container | OU/account, management group/subscription, folder/project dùng cho trust boundary nào? |
| SaaS/control plane | GitHub, CI, observability, support tool có thể cấp hoặc dùng cloud access không? |
| Workload | Cluster, VM, serverless, pipeline, data job dùng identity nào? |
| External party | Vendor/MSP/contractor/customer được federation hay tạo local account? |

Một tập đoàn có thể có nhiều organization/tenant vì pháp lý, M&A hoặc sovereignty. Đừng
giả định “một cloud = một boundary”. Ghi owner, purpose, lifecycle và trust relationship
cho từng organization.

---

## 4. Operating model và shared responsibility nội bộ

Cloud provider bảo vệ IAM service; tổ chức vẫn chịu trách nhiệm identity source, policy,
assignment, monitoring và response. Bên trong tổ chức cần tách rõ:

| Vai trò | Trách nhiệm chính |
|---|---|
| Enterprise IAM | Workforce lifecycle, federation, group/entitlement governance |
| Cloud foundation | Organization hierarchy, landing zone, guardrail, delegated admin |
| Platform team | Resource vending, workload identity và golden path |
| Application/data owner | Business authorization và resource-level access |
| Security | Invariant, independent review, detection, incident response |
| Risk/audit | Control objective, evidence và risk acceptance |

RACI chỉ hữu ích khi gắn với API/action thật: ai có thể tạo account, đổi parent, sửa
organization policy, thêm federated IdP, cấp role, approve JIT và revoke session.

---

## 5. Phân loại identity trước khi quản trị

Không dùng cùng policy cho mọi principal:

| Loại | Lifecycle chính | Credential phù hợp |
|---|---|---|
| Workforce | Joiner–mover–leaver từ HR/directory | Federation + MFA/passkey + session ngắn |
| External workforce | Contract/sponsor/expiry | Federation/B2B, scope và review riêng |
| Workload | Deploy/scale/replace | Platform identity hoặc federation ngắn hạn |
| Automation/pipeline | Repository/workflow/environment | OIDC federation, claim allowlist |
| Managed service | Provider tạo và vận hành | Service-linked/managed identity, scope kiểm soát |
| Emergency | Sự cố và IdP outage | Credential tách biệt, bảo vệ và drill chặt |
| Agent/bot | Task/owner/model/tool lifecycle | Identity riêng, delegated scope và action audit |

Mỗi identity cần owner, purpose, environment, trust source, maximum privilege, expiry và
revoke method. “Service account dùng chung” che mất attribution và lifecycle.

---

## 6. Tách management plane, identity plane và workload plane

Ba plane có blast radius khác nhau:

- **identity plane**: directory, federation, authenticator, group và provisioning;
- **management plane**: organization hierarchy, account lifecycle, IAM/policy, billing,
  security service delegation;
- **workload/data plane**: application API, compute, storage, database và business data.

Compromise workload không nên tự dẫn tới sửa organization policy. Compromise developer
portal cũng không nên cho phép thay IdP hoặc management-account role. Tách credential,
repository, runner, network path, admin workstation và logging cho từng plane.

---

## 7. Thiết kế resource hierarchy theo trust và policy

Hierarchy không chỉ để báo cáo chi phí. Nó là attachment point cho policy inheritance.
Tổ chức thường cần nhánh theo:

- production so với non-production;
- regulated/sensitive so với general;
- platform/shared services so với product workload;
- sandbox/experimentation với quota và isolation mạnh;
- security/log archive với administrator riêng;
- suspended/quarantine và decommissioned resource;
- geography/legal entity khi policy khác nhau thật sự.

Không sao chép sơ đồ tổ chức nhân sự một cách máy móc: team thay đổi nhanh, còn trust
boundary và compliance policy thường ổn định hơn. Hierarchy quá sâu làm effective policy
khó hiểu; quá phẳng khiến scope delegation/guardrail quá rộng.

---

## 8. Bảo vệ root/management organization

Root hoặc management account/tenant có thể thay hierarchy, policy và delegated service,
nên là concentration risk lớn nhất.

Nguyên tắc:

- không chạy workload thông thường ở management scope;
- số người có quyền trực tiếp cực ít, phishing-resistant MFA;
- tách daily admin khỏi emergency/root identity;
- không dùng access key dài hạn;
- admin từ hardened workstation/path;
- mọi thay đổi organization/identity federation tạo alert;
- billing/support task được cấp role hẹp riêng;
- credential recovery và ownership được kiểm soát nhiều người;
- log đưa ra security boundary độc lập.

Lưu ý provider-specific: AWS SCP không hạn chế principal trong management account. Vì
vậy việc giữ account này gần như không có workload và hạn chế access là control cốt lõi.

---

## 9. Account, subscription và project vending

Resource container phải được tạo qua workflow có lifecycle thay vì ticket thủ công:

```text
request intent
    → verify requester / owner / cost center / data class
        → select trust tier and parent
            → create + baseline + log + guardrail
                → handoff scoped admin
                    → reconcile / transfer / suspend / close
```

Baseline tối thiểu gồm owner, contacts, tags/labels, federation, log sink, security service,
network default, budget/quota, region restriction và deletion protection phù hợp.

Vending workflow phải idempotent, audit được và không trao credential bootstrap vĩnh viễn.
Account tạo ngoài workflow cần được phát hiện, quarantine hoặc tự đưa về baseline.

---

## 10. Delegated administration không phải mini-root

Delegation giúp central team không thành bottleneck, nhưng cần capability hẹp:

- service và action nào được quản trị;
- scope OU/folder/account/resource nào;
- principal có được đổi policy của chính mình không;
- có được tạo delegation cấp hai không;
- dữ liệu nào delegation có thể đọc;
- thay đổi nào cần separation of duties;
- session/approval/expiry và audit ra sao;
- revoke/decommission thế nào.

Ưu tiên delegate một service/capability cụ thể sang account/project quản trị riêng. Không
cấp broad organization admin chỉ vì team chịu trách nhiệm nhiều account. AWS delegated
administrator vẫn chịu SCP của member account; đây là guardrail hữu ích nhưng không thay
permission design bên trong account đó.

---

## 11. Centralize invariant, phân quyền operation

Một operating model cân bằng:

**Central team sở hữu:**

- root/organization lifecycle và federation trust;
- hard guardrail: region, external sharing, public exposure, key policy baseline;
- privileged role taxonomy và emergency process;
- audit/identity graph/evidence;
- policy framework và exception protocol.

**Local team sở hữu:**

- assignment cho role nghiệp vụ trong scope của họ;
- resource policy không vượt guardrail;
- workload identity và application authorization;
- owner review, offboarding và remediation.

Local autonomy chỉ an toàn khi scope derive từ nguồn tin cậy, self-service không cho sửa
guardrail, và central team có thể quan sát effective state.

---

## 12. Một authoritative identity source và federation

Workforce user nên bắt đầu từ HR/directory authoritative, rồi federation vào cloud. Lợi ích:

- một lifecycle và một nơi enforce authenticator policy;
- giảm cloud-local user/password;
- group/attribute có provenance;
- disable tập trung có thể chặn cấp session mới;
- audit nối cloud principal với stable person ID.

Federation trust cần pin issuer, audience, signature, subject/attribute mapping và certificate/
key rotation. Không map role từ attribute người dùng có thể tự sửa. Tách production admin
group khỏi group dùng cho collaboration thông thường.

Federation làm giảm credential dài hạn nhưng cũng tập trung blast radius vào IdP; cần bảo
vệ IdP admin, connector, sync service và signing key như Tier-0 control plane.

---

## 13. Joiner–mover–leaver là transaction xuyên hệ thống

Lifecycle không kết thúc ở việc disable directory account:

| Sự kiện | Hành động cần reconcile |
|---|---|
| Joiner | Tạo identity, baseline group theo job/location, training và sponsor |
| Mover | Xóa quyền cũ trước/đồng thời thêm quyền mới; review toxic combination |
| Leave | Disable, revoke session/token/key, xóa assignment trực tiếp, chuyển ownership |
| Return | Không tái dùng entitlement/session cũ mà không re-evaluate |
| Contractor expiry | Auto-disable theo contract, sponsor phải gia hạn chủ động |

Giữ stable immutable subject ID; email/name có thể đổi. Theo dõi propagation lag từ HR →
IdP → SCIM/group → cloud role → application/cache. Offboarding SLO phải đo tới effective
access, không chỉ tới “workflow completed”.

---

## 14. Group là entitlement boundary có owner

Group-based assignment dễ quản lý hơn cấp trực tiếp, nhưng group cũng là privileged object.
Mỗi group cần:

- business purpose và resource/role được mở;
- owner và backup owner;
- nguồn membership: dynamic, HR, request hay manual;
- ai được thêm/xóa member và owner;
- nested group có được phép không;
- guest/service principal có được tham gia không;
- review cadence và auto-expiry;
- alert khi group nhạy cảm đổi membership/owner.

Nested group xuyên directory dễ che effective privilege. Với Tier-0/admin group, ưu tiên
membership trực tiếp, ít owner, JIT eligibility và independent review.

---

## 15. External workforce, guest và partner access

Vendor/contractor cần một lifecycle khác employee:

- sponsor nội bộ chịu trách nhiệm;
- contract/end date bắt buộc;
- federation/B2B tốt hơn local password khi đối tác có IdP đáng tin;
- entitlement theo task/resource, không theo “partner” chung;
- tenant restriction và data-use condition;
- step-up/JIT cho privileged action;
- review thường xuyên hơn;
- session/access revoke khi sponsor, contract hoặc risk thay đổi.

Đừng giả định mọi external identity có `guest` flag chuẩn; chúng có thể được tạo như member,
được share trực tiếp ở SaaS hoặc tồn tại trong resource policy ngoài directory. Inventory
phải nối cả cloud, application và data-sharing edge.

---

## 16. Federation mapping và confused deputy

Federation sai mapping có thể biến claim nhỏ thành quyền lớn. Kiểm tra:

- issuer và tenant/org nguồn chính xác;
- audience dành riêng cho workload/cloud target;
- subject ổn định, không dựa tên repo/email dễ chiếm lại;
- group/role claim từ authoritative source;
- wildcard branch/repository/namespace không quá rộng;
- external ID/nonce/subject condition chống confused deputy khi phù hợp;
- session tags/attributes không do caller tùy ý chọn;
- maximum session duration và reauthentication cho privilege;
- trust policy và permission policy được review cùng nhau.

Một role permission hẹp nhưng trust policy cho phép bất kỳ repository/tenant assume vẫn
là exposure lớn. Effective access phải xét cả “ai có thể trở thành principal này”.

---

## 17. Context-aware access và Conditional Access

Access decision có thể dùng thêm context:

- authentication strength;
- user/workload risk;
- managed/compliant device;
- network/location như một signal, không phải bằng chứng duy nhất;
- application/resource sensitivity;
- action và requested privilege;
- session age và recent step-up;
- emergency/service identity exception.

Policy nên viết theo outcome và triển khai report-only/canary trước enforce. Luôn test đường
recovery để tránh khóa toàn bộ admin. Network location dễ thay đổi/NAT/shared nên không
được xem như identity.

Conditional access chỉ tác động nơi IdP và resource hỗ trợ signal/enforcement; legacy
protocol, local account hoặc token cũ có thể là đường vòng.

---

## 18. Session lifecycle và continuous access evaluation

Short-lived token giảm cửa sổ nhưng không đảm bảo revoke tức thì. Cần hiểu:

- token nào tự chứa quyền và sống tới expiry;
- resource có introspection/callback/continuous evaluation không;
- group/role change tác động session hiện tại khi nào;
- disable user, reset password, tăng risk hay revoke grant được propagate ra sao;
- CLI/browser/workload cache credential ở đâu;
- long-running job và offline operation xử lý thế nào.

Microsoft Entra Continuous Access Evaluation minh họa việc issuer và relying party phối
hợp để phản ứng sớm với critical event, nhưng support khác nhau theo workload/resource.
Governance cần đo **revoke-to-deny latency** thực tế cho từng critical path thay vì suy ra
từ token lifetime.

---

## 19. Workload identity là principal hạng nhất

Mỗi workload cần identity riêng theo application, environment và trust boundary. Identity
không nên dùng chung giữa:

- dev/staging/production;
- deployment và runtime;
- frontend và privileged worker;
- tenant hoặc data domain có isolation yêu cầu;
- human operator và automation;
- read path và high-impact write path nếu blast radius khác.

Bind identity vào platform attestation: cloud resource, Kubernetes ServiceAccount, VM,
serverless function, repository/workflow/environment. Authorization vẫn kiểm tra action,
resource và context; “chạy trong cluster/account” không tự đáng tin.

---

## 20. Federation cho workload, loại bỏ static key

Workload Identity Federation đổi assertion từ nguồn tin cậy lấy credential cloud ngắn hạn:

```text
CI / Kubernetes / external cloud identity
    → signed assertion with bounded claims
        → cloud trust policy validates issuer/audience/subject
            → short-lived role/service credential
                → resource policy enforces action and scope
```

Ưu điểm là không phân phối key dài hạn và revoke bằng trust/policy. Nhưng cần bảo vệ:

- issuer signing key và tenant;
- repository/workflow/branch/environment claim;
- subject reuse sau rename/delete;
- audience và token replay;
- role-chaining làm kéo dài session;
- permission của identity đích;
- audit nối assertion source với cloud session.

Federation kém ràng buộc chỉ thay một static secret bằng “máy phát credential” quá rộng.

---

## 21. Service account, managed identity và ownership

Service account/managed identity cần record:

- owner team và service catalog link;
- workload/resource nào được attach/assume;
- permissions trực tiếp và qua group/role;
- key/certificate còn tồn tại;
- last authentication và last permission use;
- downstream resource trust;
- rotation/revoke/deletion method;
- behavior khi workload decommission.

Chặn tạo key mặc định bằng organization policy khi platform hỗ trợ. Nếu buộc dùng key,
key phải có owner, vault, expiry, rotation và usage detection—not nằm trong CI variable
vĩnh viễn.

Không xóa service identity chỉ vì “không login gần đây” trước khi xét batch/DR/seasonal job;
quyết định dựa vào dependency graph và owner verification.

---

## 22. Identity cho agent, bot và automation mới

Agent hoặc bot có thể nhận goal rộng rồi gọi nhiều tool, nên cần identity riêng cho mỗi
runtime/deployment, không mượn user token hoặc service admin chung.

Control contract nên gồm:

- action/tool/resource allowlist;
- delegated user/tenant context được giữ xuyên call;
- maximum transaction value và rate/cost limit;
- approval cho irreversible/high-impact action;
- data classification và egress restriction;
- credential ngắn hạn theo task;
- audit cả requested intent, tool call, effective principal và result;
- kill switch/revoke độc lập với agent runtime.

Model output không phải authorization decision đáng tin. Policy enforcement phải nằm ở
deterministic gateway/resource và derive scope từ identity/context đã xác thực.

---

## 23. Chuẩn hóa permission model xuyên cloud

Mỗi provider có semantics khác nhau, nhưng inventory nội bộ có thể chuẩn hóa:

```text
subject
  + action / permission
  + resource / scope
  + effect (allow / deny)
  + condition
  + source policy and ancestor
  + delegation / trust path
  + validity window
```

Không ép mọi provider vào một RBAC abstraction làm mất deny, resource policy, boundary
hoặc condition. Normalized model dùng để query/risk analysis; quyết định enforcement vẫn
phải tôn trọng evaluation logic gốc của provider.

Giữ raw policy và provider resource ID để có thể tái tính khi parser/model thay đổi.

---

## 24. Effective permission khác assigned role

Assigned role chỉ là một input. Effective permission có thể chịu tác động của:

- inherited allow từ ancestor;
- explicit deny/organization guardrail;
- permissions boundary/session policy;
- resource-based policy hoặc ACL;
- trust/assume-role relationship;
- group/nested group/dynamic membership;
- attribute/condition theo request;
- service-specific authorization;
- ownership quyền sửa policy/role khác;
- session đã cấp trước khi policy đổi.

Vì vậy câu hỏi “Alice có role gì?” yếu hơn “Alice hoặc identity Alice có thể trở thành,
trong context nào, có đường nào thực hiện action X trên resource Y?”.

---

## 25. Allow, deny, guardrail và permissions boundary

Các loại policy không thay thế nhau:

| Control | Vai trò |
|---|---|
| Identity/role allow | Cấp khả năng cho principal |
| Resource policy | Quy định principal nào truy cập resource, kể cả cross-boundary |
| Organization guardrail | Giới hạn maximum permission hoặc cấu hình được phép |
| Explicit deny | Chặn action/resource dù có allow phù hợp theo evaluation model |
| Permissions boundary | Giới hạn maximum permission của identity trong scope hỗ trợ |
| Session policy | Thu hẹp quyền của session cụ thể |
| Condition | Chỉ cho phép khi request/resource/principal context thỏa |

Ví dụ AWS SCP **không cấp quyền**; nó đặt trần cho principal trong member account và cần
kết hợp IAM/resource policy. Guardrail “allow service” không đồng nghĩa user đã có quyền
dùng service đó.

---

## 26. Policy inheritance và precedence

Hierarchy giúp áp policy quy mô lớn nhưng semantics khác provider:

- Google Cloud allow policy ở ancestor được thừa kế và hợp với allow ở resource con;
- organization policy/deny có evaluation model và supported permission riêng;
- AWS SCP/RCP đặt giới hạn qua root/OU/account nhưng management account có ngoại lệ quan trọng;
- Azure role assignment và policy scope theo management group/subscription/resource hierarchy;
- resource/service policy có thể thêm một lớp logic riêng.

Không dùng trực giác “policy gần resource nhất thắng”. Xây evaluator hoặc dùng provider API
để truy effective state. Khi move account/project sang parent khác, coi đó là security
change lớn vì inherited permissions và guardrail có thể đổi ngay.

---

## 27. Permission set, custom role và role taxonomy

Role/permission set nên biểu diễn job capability ổn định:

- `Viewer` theo data class, không phải xem mọi thứ;
- operator cho action vận hành thường ngày;
- deployer tách khỏi runtime admin;
- security-auditor read-only có đủ log/policy;
- incident responder với entitlement JIT;
- organization-policy admin tách identity admin;
- break-glass chỉ cho recovery objective cụ thể.

Tránh hai cực: hàng nghìn custom role gần giống nhau hoặc vài role `Admin/PowerUser` quá
rộng. Version role-as-code, có owner, compatibility policy và migration plan.

AWS IAM Identity Center permission set là template tạo role được quản lý trong account được
gán; việc sửa template cần kiểm tra rollout/provisioning state ở mọi account đích.

---

## 28. ABAC, tag và condition governance

ABAC mở rộng tốt khi attribute đáng tin và có taxonomy. Governance phải trả lời:

- ai được tạo/sửa principal attribute;
- ai được gắn resource tag nhạy cảm;
- tag nào là security-relevant, required và immutable sau tạo;
- missing/null/multi-value xử lý ra sao;
- naming/case/encoding có canonical không;
- condition dựa thời gian, network hay device có clock/source nào;
- tag propagation sang child/copy/restore có đảm bảo không;
- principal có thể sửa tag để tự mở quyền không.

Nếu một developer vừa sửa resource tag `environment=prod` vừa có policy dựa vào tag đó,
ABAC có thể biến thành self-escalation. Tách quyền quản trị attribute khỏi quyền hưởng lợi
từ attribute.

---

## 29. Resource policy và cross-account access

Cross-account access thường xuất hiện ở object storage, KMS, queue, secret, registry và
data warehouse. Mỗi edge cần:

- source organization/account/project/tenant cụ thể;
- principal/role cụ thể, tránh wildcard;
- action và resource prefix hẹp;
- condition chống confused deputy khi service/provider hỗ trợ;
- encryption-key policy tương thích;
- data classification và purpose;
- owner hai phía, expiry và revoke path;
- audit cả source session lẫn target resource.

Public access block hay organization guardrail không thay review resource policy. Một
resource có thể trust principal ngoài organization dù local identity inventory trông sạch.

---

## 30. Privilege escalation graph

Đừng chỉ tìm role chứa `*`. Các quyền gián tiếp nguy hiểm gồm:

- sửa policy/role/group hoặc permission set;
- assume/pass/impersonate service identity mạnh hơn;
- tạo compute/function/job với privileged identity;
- sửa startup script, image, deployment hoặc CI workflow;
- đọc secret/token/state file;
- thay federation trust/issuer/claim mapping;
- đổi KMS/resource policy;
- tạo key/credential cho identity khác;
- vô hiệu log, detection hoặc organization guardrail;
- approve chính access request của mình.

Graph analysis nên tìm path đến high-value action/resource, kèm precondition và condition.
Sau remediation, test lại path chứ không chỉ xóa một policy edge.

---

## 31. JIT/PIM: permanent eligibility, temporary activation

Privileged access nên chuyển từ **permanently active** sang **eligible** rồi activate trong
thời gian ngắn:

```text
eligible principal
    → request scoped entitlement + justification
        → policy/risk/approval checks
            → short activation/session
                → perform audited task
                    → expire/revoke + review
```

Entitlement cần role, resource scope, maximum duration, authentication strength, approval,
ticket/context và notification. Duration theo task: đọc log có thể khác đổi organization
policy.

PIM/JIT giảm standing privilege nhưng không tự tạo least privilege nếu entitlement vẫn là
global admin hoặc requester luôn tự approve.

---

## 32. Approval và separation of duties

Approval có giá trị khi approver hiểu scope và không có conflict:

- requester không approve chính mình;
- approver không chỉ click vào tên role mơ hồ;
- hiển thị resource, actions, duration, business ticket và risk;
- high-impact action cần second control hoặc dual authorization;
- automated approval chỉ dựa policy có input/provenance đáng tin;
- emergency path bỏ approval phải alert và post-review;
- delegation của approver có expiry;
- timeout mặc định deny, không auto-approve.

Tách người **định nghĩa entitlement**, **approve activation**, **sử dụng quyền** và **review
evidence** cho Tier-0. Một người kiểm soát cả bốn bước có thể tạo và che giấu quyền.

---

## 33. Break-glass và root access

Break-glass dành cho failure mode cụ thể như IdP/federation/PIM outage, không phải role admin
tiện dụng. Thiết kế:

- hai hoặc nhiều emergency identities độc lập;
- credential/phishing-resistant authenticator tách khỏi daily IdP dependency;
- không dùng cho email/collaboration;
- secret/physical custody chia người khi phù hợp;
- access path và recovery contact luôn còn dùng được;
- alert tức thì khi login/attempt/policy change;
- session ngắn, action scope rõ;
- rotate/reseal sau dùng;
- drill định kỳ cả success và cleanup.

Không khóa break-glass bằng chính Conditional Access hoặc vault đang cần phục hồi. Nhưng
“độc lập” không nghĩa bỏ logging, monitoring hay ownership.

---

## 34. Access request và entitlement catalog

Người dùng nên request business capability, không tự chọn hàng trăm raw permission:

| Catalog item | Nội dung |
|---|---|
| Capability | “Deploy service A production”, không phải “Role X” |
| Eligibility | Team/job/training/device/region điều kiện |
| Scope | Account/project/resource/data domain |
| Duration | Permanent baseline hay temporary activation |
| Approval | Owner, manager, data custodian hoặc policy auto-check |
| Conflicts | Toxic combination và current privilege |
| Evidence | Requester, reason, ticket, decision, provision result |
| Lifecycle | Expiry, review, revoke và owner change |

Catalog phải versioned. Khi role bên dưới đổi, đánh giá mọi assignment đang dùng catalog
item đó; tên entitlement không đổi nhưng blast radius có thể tăng.

---

## 35. Access review không phải chiến dịch click “approve all”

Reviewer cần context để ra quyết định:

- principal là ai, còn thuộc team/contract không;
- access trực tiếp hay qua group/ancestor;
- role cho phép action nào trên resource nào;
- last used chỉ là signal, không phải bằng chứng duy nhất;
- toxic combination/privilege path;
- owner và criticality của resource;
- active, eligible và emergency assignment;
- recommendation, confidence và consequence khi remove.

Chọn reviewer gần business context nhưng có escalation khi owner không phản hồi. Auto-remove
chỉ sau khi test dependency và có recovery path. Review outcome phải thực sự cập nhật
effective access, không chỉ đóng campaign.

---

## 36. Usage analysis và right-sizing

Permission usage giúp tìm quyền dư thừa:

1. chọn observation window bao phủ seasonal/DR/batch activity;
2. kết hợp provider last-accessed, audit log và application context;
3. phân biệt permission chưa dùng với telemetry không hỗ trợ;
4. tạo candidate policy hẹp hơn;
5. mô phỏng/test trên canary principal;
6. rollout theo ring với rollback;
7. theo dõi denied action và business impact;
8. giữ JIT path cho nhu cầu hiếm nhưng hợp lệ.

Không tự xóa permission chỉ vì 30/90 ngày không dùng. Emergency recovery và year-end job
có pattern khác daily operation. Mục tiêu là right-size theo capability cần thiết và failure
mode, không tối thiểu hóa số permission bằng mọi giá.

---

## 37. Dormant, orphaned và shadow access

Tìm các đối tượng:

- user không còn authoritative record;
- group không owner hoặc owner đã rời đi;
- role/permission set không assignment nhưng resource vẫn trust;
- service account không workload owner;
- key/certificate không provenance;
- guest hết sponsor/contract;
- project/account không business owner;
- local cloud user né federation;
- SaaS/API token cấp ngoài central IAM;
- resource policy trỏ principal đã xóa/recreated.

Quarantine trước delete nếu dependency chưa rõ: chặn cấp session mới, giảm permission hoặc
move resource vào suspended boundary; quan sát rồi xóa theo runbook có rollback.

---

## 38. Policy-as-code và change management

IAM policy, role, group-to-entitlement mapping và organization guardrail nên được quản lý
như code:

- canonical source và immutable revision;
- schema/lint/semantic validation;
- positive/negative policy tests;
- impact analysis trên effective permission graph;
- reviewer theo ownership và risk tier;
- signed CI identity, không dùng admin key;
- plan/diff hiển thị principal–action–resource, không chỉ JSON lines;
- canary/ring rollout cho hierarchy rộng;
- post-deploy reconcile và drift detection;
- emergency change có expiry và back-port về source.

Git approval không đủ nếu renderer/deployer có thể sửa output hoặc destination ngoài code.
Audit phải nối commit → pipeline identity → cloud API → effective state.

---

## 39. Exception có scope, owner và expiry

Exception IAM cần record:

- invariant/policy bị miễn;
- principal, action, resource và environment cụ thể;
- business/risk rationale;
- owner có thẩm quyền và approver độc lập;
- compensating control;
- start, expiry, review trigger;
- detection/monitoring riêng;
- remediation/migration plan;
- hành vi khi hết hạn.

Tránh exempt cả OU/folder vì một workload legacy. Nếu policy engine chỉ hỗ trợ exemption
rộng, tạo boundary riêng hoặc thêm control tại resource. Exception không được tự gia hạn
vì owner im lặng.

---

## 40. Inventory và effective-access graph

Inventory định kỳ nên thu:

- hierarchy và parent history;
- principal/group/identity source;
- role/permission set/custom policy version;
- allow/deny/boundary/resource/trust policy;
- JIT eligibility, active grant và break-glass;
- keys/certificates/federation providers;
- ownership, classification và resource metadata;
- session/audit usage theo retention phù hợp;
- exceptions và provenance của change.

Lưu cả `observed_at`, source API và parser version. Cloud state thay đổi liên tục; snapshot
không timestamp tạo kết luận sai. Graph cần hỗ trợ câu hỏi “nếu principal/IdP/pipeline này
bị compromise, resource/action nào reachable?”.

---

## 41. Audit và attribution xuyên federation

Một event IAM hữu ích cần nối:

```text
human/workload stable ID
    → source IdP/assertion/session
        → assumed role / service identity / delegation chain
            → API action + target resource
                → policy/config revision + outcome
```

Giữ issuer, subject, session name/ID, source workload/repository, requester, approver,
ticket/test-run ID và target. Không dùng email hoặc IP làm identity duy nhất.

Centralize organization, directory, federation, PIM/JIT, IAM, KMS và resource-access log ra
ngoài blast radius. Bảo vệ log khỏi identity có quyền thay policy được ghi nhận.

---

## 42. Detection cho high-risk IAM change

Ưu tiên detection theo behavior và blast radius:

- thêm/sửa federated identity provider hoặc trust policy;
- cấp organization/root/global admin;
- thay management group/OU/folder parent;
- disable/nới guardrail, deny, logging hoặc security service;
- tạo access key/certificate cho privileged identity;
- thêm owner vào Tier-0 group;
- pass/impersonate privileged service account;
- resource/KMS policy mở cross-account/external access;
- break-glass use hoặc failed attempt;
- JIT activation bất thường về scope/duration/time/requester;
- mass assignment hoặc permission-set rollout ngoài pipeline.

Alert phải enrich current/historical privilege, effective path, resource criticality và
change provenance. “Admin action” chung chung tạo quá nhiều noise.

---

## 43. Runbook: workforce identity bị compromise

1. Xác minh stable subject, session, authenticator và dấu hiệu compromise.
2. Chặn sign-in/cấp session mới; revoke session/refresh token nơi hỗ trợ.
3. Tìm mọi cloud role, group, direct assignment, external share và delegated grant.
4. Xác định role được assume, resource/action thực tế và credential được tạo thêm.
5. Revoke key/token/service identity do attacker tạo; thu hẹp trust path.
6. Preserve IdP, PIM, cloud audit và resource evidence ngoài blast radius.
7. Reset/re-enroll authenticator và khôi phục từ thiết bị/admin path sạch.
8. Xác minh deny bằng synthetic attempt và theo dõi session propagation lag.
9. Reconcile policy/resource change, secret/data exposure và persistence.
10. Thêm detection/regression cho root cause.

Reset password đơn lẻ không chặn mọi access token, role session hay credential attacker đã
tạo từ quyền cloud.

---

## 44. Runbook: organization IAM control plane bị compromise

Đây là severity khác workload incident:

1. Kích hoạt emergency authority ngoài identity plane nghi bị compromise.
2. Đóng băng change automation hoặc chuyển read-only có kiểm soát.
3. Preserve hierarchy, policy, federation, keys, assignments và audit snapshots.
4. Xác định clean root/management ownership và out-of-band communication.
5. Revoke attacker/session nhưng tránh tự khóa recovery path.
6. Khôi phục trusted federation/signing key/admin workstation.
7. So sánh desired–observed toàn organization; tìm parent/policy/log sink bị đổi.
8. Rotate credential có thể được mint/read; rebuild privileged automation.
9. Roll out guardrail theo ring, xác minh effective deny và business continuity.
10. Review downstream data/resource impact trước declare clean.

Xóa một malicious admin không đủ: attacker có thể tạo delegation, workload identity, key,
resource policy hoặc federation trust tồn tại độc lập.

---

## 45. M&A, divestiture và tenant migration

M&A làm hai identity/hierarchy/trust model va chạm. Trước federation hoặc move resource:

- inventory identity, domain, group, service account và external trust;
- map role semantics thay vì map theo tên;
- phân loại resource/data và legal boundary;
- quarantine/pre-integration landing zone;
- giới hạn bidirectional federation và transitive trust;
- xử lý duplicate/recycled email/subject;
- tách day-1 access khỏi target-state migration;
- review key, KMS, log ownership và incident authority;
- đặt expiry cho transitional admin role.

Divestiture cần revoke trust, copy/delete dữ liệu theo thỏa thuận, chuyển ownership, rotate
shared credential và chứng minh bên tách ra không còn access. DNS/domain ownership thay đổi
có thể làm claim/federation mapping cũ trở nên nguy hiểm.

---

## 46. Multi-cloud normalization và giới hạn

Một control objective chung có thể có implementation khác:

| Objective | AWS | Azure/Entra | Google Cloud |
|---|---|---|---|
| Hierarchy | Organization → OU → account | Tenant/management group → subscription → resource group/resource | Organization → folder → project → resource |
| Workforce assignment | IAM Identity Center permission set | Entra group/role + Azure RBAC | Cloud Identity/Workforce federation + IAM binding |
| Organization guardrail | SCP/RCP và các organization policies | Azure Policy + RBAC/Conditional Access theo đúng plane | Organization Policy + deny/allow policy |
| JIT privilege | Temporary role/session/workflow phù hợp | Entra PIM | Privileged Access Manager |
| Workload federation | IAM role trust + OIDC/SAML phù hợp | Managed/workload identity federation | Workload Identity Federation |

Bảng chỉ để định hướng, không khẳng định semantic tương đương. Ví dụ Azure Policy không
thay Azure RBAC; AWS SCP không cấp quyền; Google Cloud inherited allow là union nhưng deny/
organization policy có logic riêng. Giữ control objective chung và provider-specific tests.

---

## 47. Validation và negative tests cho IAM governance

Mỗi critical invariant cần test effective behavior:

- account/project mới nhận đúng parent, guardrail và log sink;
- local admin không sửa organization policy hoặc federation;
- SCP/deny/boundary chặn action dù role local allow;
- cross-account resource không nhận principal ngoài allowlist;
- workload assertion sai issuer/audience/subject bị từ chối;
- JIT grant hết hạn và session/action thực sự bị chặn;
- offboarded user không lấy session mới và session cũ bị xử lý theo SLO;
- break-glass hoạt động khi IdP/PIM giả lập outage nhưng tạo alert;
- move resource giữa parent kích hoạt impact review;
- policy engine/deployer outage không fail-open vô hạn.

Test deny phải kiểm tra không có side effect và có audit/detection. Gắn evidence với policy
revision, hierarchy snapshot, principal/session và resource ID.

---

## 48. Metrics đo control outcome

Metrics hữu ích:

- % organization/account/project có owner, trust tier và baseline đạt chuẩn;
- % workforce access qua federation, % workload không còn static key;
- số/TTR local user, orphan identity và unmanaged external trust;
- standing privileged assignments so với eligible/JIT;
- JIT activation scope/duration và revoke-to-deny latency;
- offboarding effective-access removal SLO;
- % Tier-0 group/role/access package được review đúng hạn;
- exception quá hạn và assignment ngoài catalog;
- % priority privilege paths đã test/đóng;
- policy drift và desired–observed reconciliation latency;
- IAM high-risk change có provenance pipeline/approval;
- time scope/contain organization identity incident.

Không tối ưu vanity metric như “số role ít” hoặc “100% access review hoàn thành” nếu reviewer
approve all và effective access không đổi.

---

## 49. Ví dụ end-to-end: cấp quyền production cho SRE

**Mục tiêu:** SRE xử lý incident production nhưng không có admin thường trực.

```text
HR/directory confirms active SRE
    → eligible group with owner and quarterly review
        → request incident-responder entitlement for service/account
            → phishing-resistant step-up + incident ticket
                → independent/on-call approval
                    → 60-minute scoped session
                        → action audit + sensitive-change alert
                            → expiry/revoke verified
```

**Guardrail:** không sửa organization policy/federation/log sink, không pass role ngoài
allowlist, data access cần entitlement riêng.

**Evidence:** stable subject, eligibility source, requester/approver, ticket, policy/role
revision, session ID, effective permissions, API actions, expiry và negative test sau revoke.

**Failure mode:** PIM/IdP outage dùng break-glass riêng; alert ngay, two-person custody khi
phù hợp, rotate sau sử dụng và post-incident review bắt buộc.

---

## 50. Checklist, anti-pattern và tài liệu chính thức

### Checklist production

- [ ] Mọi organization/tenant/account/subscription/project có owner, purpose và trust tier.
- [ ] Root/management scope không chạy workload thường; daily admin tách emergency identity.
- [ ] Hierarchy phản ánh trust/policy boundary và mọi move đều có impact review.
- [ ] Workforce dùng authoritative source + federation; JML đo tới effective access.
- [ ] External identity có sponsor, scope, expiry và review riêng.
- [ ] Workload/pipeline dùng identity riêng và credential ngắn hạn/federation khi khả thi.
- [ ] Guardrail, allow, deny, boundary, trust và resource policy được tính cùng nhau.
- [ ] Privilege graph bao phủ pass/assume/impersonate, policy change và deployment path.
- [ ] Tier-0 privilege là eligible/JIT, có step-up, scope, duration, approval và audit.
- [ ] Break-glass độc lập dependency cần phục hồi và đã drill cả cleanup.
- [ ] Policy/entitlement as code có semantic diff, negative test, rollout ring và reconcile.
- [ ] Audit nối stable identity → federation/session → role/delegation → action/resource.
- [ ] Exception, guest, key, group, role và account không owner đều có expiry/quarantine path.
- [ ] Có runbook workforce compromise và organization control-plane compromise riêng.

### Anti-pattern thường gặp

- “MFA mạnh nên permanent global admin vẫn ổn.”
- “SCP/organization policy allow nghĩa là đã cấp quyền.”
- “Role name giống nhau thì semantics giống nhau giữa các cloud.”
- “Group-based access luôn dễ review hơn direct assignment.”
- “Disable user ở IdP đã revoke mọi cloud session và credential.”
- “Workload trong account/cluster nội bộ tự động đáng tin.”
- “JIT global admin vẫn là least privilege vì chỉ tồn tại một giờ.”
- “Last used trống nghĩa là permission chắc chắn không cần.”
- “Access review hoàn thành nghĩa là stale access đã bị xóa.”
- “Break-glass đặt trong cùng IdP/PIM/vault đang phục hồi là đủ.”
- “Git là source of truth nên effective cloud IAM chắc chắn không drift.”
- “Một abstraction RBAC chung mô tả chính xác mọi provider.”

### Tài liệu chính thức

- [NIST SP 800-207 – Zero Trust Architecture](https://csrc.nist.gov/pubs/sp/800/207/final)
- [NIST SP 800-207A – Access Control in Multi-Cloud Cloud-Native Applications](https://csrc.nist.gov/pubs/sp/800/207/a/final)
- [AWS Organizations – Service Control Policies](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_scps.html)
- [AWS Organizations – Management Account Best Practices](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_best-practices_mgmt-acct.html)
- [AWS IAM Identity Center – Configure Access to AWS Accounts](https://docs.aws.amazon.com/singlesignon/latest/userguide/manage-your-accounts.html)
- [AWS IAM Identity Center – Permission Sets](https://docs.aws.amazon.com/singlesignon/latest/userguide/permissionsetsconcept.html)
- [Microsoft Entra – Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/overview)
- [Microsoft Entra – Privileged Identity Management](https://learn.microsoft.com/en-us/entra/id-governance/privileged-identity-management/pim-configure)
- [Microsoft Entra – Access Reviews Deployment](https://learn.microsoft.com/en-us/azure/active-directory/governance/deploy-access-reviews)
- [Microsoft Entra – Continuous Access Evaluation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/concept-continuous-access-evaluation)
- [Google Cloud – Resource Hierarchy for Access Control](https://cloud.google.com/iam/docs/resource-hierarchy-access-control)
- [Google Cloud – Organization Policy Overview](https://cloud.google.com/organization-policy/overview)
- [Google Cloud IAM – Deny Policies](https://cloud.google.com/iam/docs/deny-overview)
- [Google Cloud IAM – Privileged Access Manager](https://cloud.google.com/iam/docs/pam-overview)
- [Google Cloud IAM – Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)

### Học tiếp

1. [Vulnerability Management & Exposure Prioritization](../vulnerability/vulnerability_management_exposure_prioritization.md) – asset context, exploitability,
   attack path, remediation SLA và risk acceptance.
2. [Security Governance & Risk Engineering](../governance/security_governance_risk_engineering.md) – control objective, evidence, risk register,
   exception governance và continuous assurance.

---

*Cập nhật lần cuối: 2026-08-03.*
