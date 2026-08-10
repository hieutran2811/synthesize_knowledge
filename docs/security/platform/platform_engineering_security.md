---
title: "Platform Engineering Security – Golden path, guardrail và self-service an toàn"
topic: security
level: mixed
review_status: needs_review
content_updated: 2026-08-02
last_verified: null
version_scope: "unspecified"
source_count: 11
---
# Platform Engineering Security – Golden path, guardrail và self-service an toàn

> Thuật ngữ: [Glossary](../glossary.md).

Platform engineering gom nhiều quyền mạnh vào một lớp tiện dụng: tạo repository, pipeline, cloud resource,
cluster workload, secret và policy. Một platform tốt giảm cognitive load; một platform bị compromise có thể
trở thành đường tấn công đồng loạt vào toàn bộ tổ chức.

Mục tiêu của chương:

> Người dùng tự phục vụ trong phạm vi được ủy quyền, nhận mặc định an toàn và bằng chứng rõ ràng; platform
> không giữ quyền rộng hơn cần thiết, không che mất context và có thể thu hồi/khôi phục khi control plane lỗi.

---

## 1. Platform là sản phẩm nội bộ và security control plane

CNCF mô tả platform như sản phẩm phục vụ người dùng nội bộ, được phát triển từ nhu cầu và outcome của họ.
Về security, platform còn là control plane nối identity, source, CI, artifact, cloud và runtime.

```text
developer/team intent
  → portal/API/Git interface
    → template/workflow/orchestrator
      → cloud/cluster/delivery control plane
        → managed resource/workload
```

Mỗi bước vừa giảm phức tạp vừa có thể khuếch đại quyền. Threat model platform phải xem xét lỗi người dùng,
insider, plugin/template độc hại, credential theft, controller compromise và dependency failure.

## 2. Phân biệt platform, portal và PaaS

| Khái niệm | Vai trò |
|---|---|
| Internal developer platform | tập capability, API, automation, policy và operating model |
| Developer portal | giao diện khám phá/catalog/self-service; chỉ là một phần của platform |
| Platform orchestrator | phối hợp workflow/resource lifecycle qua provider |
| PaaS | sản phẩm runtime/application platform có abstraction định sẵn |
| Golden path | con đường được hỗ trợ, ưu tiên và tối ưu cho use case phổ biến |

Mua portal không tự tạo platform product hoặc security boundary. UI đẹp nhưng backend dùng admin token chung
vẫn là ticket automation có blast radius lớn.

## 3. Người dùng, tenant và trust level

Liệt kê actor:

- application developer và service owner;
- platform operator/product manager;
- security/compliance/policy owner;
- CI/GitOps/workload identity;
- template/module/plugin maintainer;
- cloud/cluster/provider operator;
- external contributor/vendor;
- incident responder/break-glass user.

“Internal user” không tự động đáng tin với confidentiality/integrity. Một developer hợp lệ có thể cố truy dữ
liệu team khác hoặc vô tình tạo public resource. Authorization cần subject, team/tenant, action, resource,
environment, data class và approval context.

## 4. Catalog capability theo risk tier

Không đưa mọi action vào cùng một self-service level.

| Tier | Ví dụ | Cơ chế phù hợp |
|---|---|---|
| Low | tạo repo/service dev chuẩn | tự động, audit |
| Medium | database non-prod, queue, namespace | quota + policy + owner |
| High | production deploy, public endpoint, KMS key | approval/risk checks |
| Critical | org IAM, policy bypass, control-plane change | dual control/JIT/break-glass |

Mỗi capability cần input/output contract, owner, supported use case, privilege, dependency, SLO, data handling,
cost/quota, audit event, revoke/delete method và runbook.

## 5. Shared responsibility của platform

RACI cần rõ cho:

- base template và dependency update;
- application code/config/data;
- build and artifact provenance;
- infrastructure module/provider;
- runtime/cluster/node;
- IAM/secret/network;
- policy exception;
- logging, incident và recovery.

Platform team không thể chịu mọi risk chỉ vì cung cấp golden path; application team không thể bỏ qua baseline
vì “platform lo rồi”. Giao diện nên hiển thị control nào platform enforce, control nào user phải cấu hình và
evidence nào chứng minh.

## 6. Secure by default, secure by design và enforce

Ba mức khác nhau:

- **Default:** template tạo cấu hình an toàn nhưng user có thể đổi.
- **Guardrail:** policy chặn hoặc yêu cầu approval khi vượt boundary.
- **Inherent design:** interface không cung cấp capability nguy hiểm, ví dụ không phát static admin key.

Ưu tiên loại bỏ lựa chọn không cần thiết, rồi default tốt, cuối cùng policy cho invariant quan trọng. Nếu mọi
field đều bị lock, user sẽ fork/bypass platform; nếu mọi thứ chỉ là default, drift sẽ nhanh chóng phá baseline.

## 7. Golden path không phải chiếc lồng

Golden path nên là con đường dễ nhất cho 80% use case, có documentation, support, upgrade và compliance evidence.
Ngoài golden path cần:

- tiêu chí khi nào được dùng;
- threat/risk review tương xứng;
- owner và support boundary;
- exception có scope/expiry;
- đường quay lại paved path;
- không âm thầm nhận full platform credential.

Đo adoption và lý do bỏ đường chuẩn. Bypass lặp lại thường là product signal: golden path thiếu capability hoặc
guardrail quá khó hiểu, không chỉ là “developer không tuân thủ”.

## 8. Nhiều interface, một authorization contract

UI, CLI, API, IDE hoặc Git PR phải dẫn đến cùng policy decision. Không để UI chặn action nhưng API backend
cho phép; không tin field `team`/`environment` do client gửi.

Canonical request:

```text
authenticated subject + current team membership
  + capability/action + target scope
  + validated inputs + policy version
  + approval/change context + idempotency key
```

Backend derive tenant/owner từ trusted directory/catalog, authorize lại ở execution time và ghi decision.

## 9. Identity propagation, delegation và confused deputy

Platform thường gọi provider thay user. Nếu dùng một admin identity chung, provider log chỉ thấy platform và
không biết requester. Cần:

- short-lived workload identity cho platform component;
- delegation/on-behalf-of context có chữ ký và audience;
- policy ràng buộc caller, requester, capability, target và TTL;
- immutable audit nối user request → workflow → provider API;
- không forward user token tới plugin/provider không cần.

Confused deputy xảy ra khi user khiến platform dùng quyền cao của nó lên resource ngoài phạm vi user. Backend
phải authorize target, không chỉ action/template.

## 10. Self-service là transaction có state

Provisioning không phải một HTTP call đơn giản:

```text
request → validate/authorize → approve (nếu cần)
  → plan → execute → verify → publish ownership/evidence
  → reconcile → update/delete
```

Dùng request ID/idempotency key; state machine rõ; retry không tạo resource trùng. Lưu requester, inputs đã
chuẩn hóa, policy/template/module version, approval, provider operations, outputs và rollback.

Không trả secret/admin credential trong UI/log. Nếu partial failure, workflow phải biết resource nào đã tạo,
ai sở hữu và cleanup có an toàn không.

## 11. Tenant/team isolation của platform

Isolation cần ở nhiều lớp:

- portal/catalog permission;
- workflow queue/executor/cache;
- source repository/project;
- cloud account/project/subscription;
- cluster/namespace/node;
- secret/key, network và data store;
- log/cost/quota.

Một template của team A không được tham chiếu arbitrary secret/resource của B. Queue cần fairness; untrusted
template/build không dùng executor/cache có credential production.

Namespace/project là scope quản trị, không phải hard boundary cho hostile tenant. Chọn account/cluster riêng
khi blast radius hoặc compliance yêu cầu.

## 12. Tách platform control plane và tenant data plane

Portal/orchestrator cần metadata để quản lý lifecycle nhưng thường không cần đọc customer data. Tách:

- platform metadata DB khỏi tenant application DB;
- reconciliation credential khỏi data credential;
- control-plane network khỏi workload data path;
- catalog read khỏi production admin;
- backup/key/incident quyền theo purpose.

Plugin/template không nên mặc nhiên truy mọi platform secret. Nếu component cùng process/database/credential,
coi chúng cùng trust boundary dù UI hiển thị như module riêng.

## 13. Software catalog là source of context, không tự là source of truth

Catalog hữu ích cho owner, lifecycle, dependency, system/domain, API, environment và link evidence. Nhưng metadata
có thể stale hoặc bị user sửa.

Định nghĩa authoritative source cho identity/group, repository, deployed digest, cloud resource và on-call.
Reconcile catalog với observed provider state; ghi confidence/last verified.

Không authorize critical action chỉ dựa vào `owner` label trong repo do requester kiểm soát. Ownership change,
entity registration/deletion và import source cần permission/audit.

## 14. Developer portal và plugin là attack surface đặc quyền

Threat model Backstage nhấn mạnh plugin chạy cùng host thường không có isolation và có thể chạm config/secret;
plugin phải được vet như dependency/code đặc quyền.

Control:

- allowlist plugin/source/version, lock dependency và scan provenance;
- permission cho catalog/template/action;
- tách service/database/credential khi cần boundary thật;
- protect portal khỏi public exposure ngoài thiết kế;
- least-privilege proxy/URL reader và egress allowlist;
- audit plugin install/config/update;
- CSP/input/output sanitization cho frontend/content;
- rate/size/depth limit chống resource exhaustion.

Portal compromise không được tự động đồng nghĩa cloud organization admin.

## 15. Template/scaffolder là chương trình, không chỉ YAML

Template có thể tạo repository, workflow, cloud resource, secret và deployment. Maintainer template gần như
platform developer.

Template cần:

- trusted repository + protected review/CODEOWNERS;
- semantic/versioned release và changelog;
- signed/provenance artifact nếu đóng gói;
- input JSON schema và output contract;
- unit/integration/security test;
- action allowlist, network/secret policy;
- migration/deprecation path;
- immutable version pin cho execution production.

Không chạy template “latest” rồi không lưu version nào đã tạo service.

## 16. Input validation, template injection và SSRF

User input như service name, repo URL, branch, path, namespace, cloud region hoặc template expression có thể
đi vào shell, filesystem, YAML, HTTP và provider API.

Nguyên tắc:

- allowlist format/enum; canonicalize rồi authorize;
- không ghép shell command string;
- chống path traversal/symlink/archive extraction;
- URL reader/proxy chỉ tới host/protocol được phép, chặn metadata/link-local/private endpoint;
- không render template hai lần;
- validate object sau render bằng schema/policy;
- giới hạn size/count/time/network.

Preview/diff phải dùng cùng renderer/version với execution để tránh time-of-check/time-of-use.

## 17. Secret trong portal và workflow

Platform nên phát hành identity/credential ngắn hạn theo request context thay vì giữ một vault đầy static admin
key. Secret cần tách theo component, environment, tenant và purpose.

Không đưa secret vào template values, catalog annotation, generated repo, build output, plan/diff hoặc workflow
log. Masking chỉ là lớp cuối, không phải permission model.

Plugin/action nhận secret tối thiểu, qua file/handle/sidecar phù hợp, có lease/revoke. Khi workflow fail, log
secret ID/version chứ không value; cleanup/revoke temporary credential.

## 18. Resource vending thay vì trao quyền provider rộng

Thay vì cấp developer quyền tạo mọi cloud resource, platform cung cấp capability hẹp:

```text
create-postgres {
  team, environment, region, dataClass, sizeClass, retentionClass
}
```

Backend map class sang network, encryption, backup, patch, IAM, quota và cost policy. User không cần chọn mọi
provider flag nhưng vẫn thấy trade-off và ownership.

Escape hatch cho provider feature mới phải có risk review; không thêm field `extraConfig: any` làm mất toàn bộ
guardrail.

## 19. IaC module là sản phẩm supply-chain nội bộ

Terraform/OpenTofu module, Helm library, Kustomize base hoặc composition có thể tạo hàng nghìn resource. Quản lý:

- source/release owner và support window;
- pin version/digest, provider/toolchain/lock;
- provenance/signature khi phân phối;
- input/output schema và sensitive output;
- policy/security/unit/integration test;
- changelog, migration, rollback và EOL;
- dependency graph tới mọi consumer.

Không cho module tự tải script/binary tùy ý trong apply. Review provider/plugin như executable dependency.

## 20. Versioning và compatibility contract

Tách version của API/capability, template/module, policy và runtime implementation. Request cần lưu tất cả version
effective để tái hiện decision.

Breaking change gồm đổi default encryption/network/retention, rename output, thay resource ownership hoặc delete-
recreate. Dùng versioned schema, migration plan, canary và consumer impact query.

Không sửa tag module/chart đã phát hành. Nếu vá khẩn, phát version mới và promote; mutable reference làm drift
không audit được.

## 21. Policy hierarchy và ownership

Policy có nhiều tầng:

```text
law/regulation/contract
  → organization invariant
    → platform baseline
      → environment/product policy
        → scoped exception
```

Mỗi rule cần owner, rationale/threat, scope, enforcement point, severity, data dependency, test, remediation,
version, rollout và review date.

Platform team vận hành engine không nhất thiết sở hữu risk decision. Security/compliance định nghĩa invariant;
service/platform owner cùng chịu usability và implementation.

## 22. Policy-as-code ở đúng enforcement point

Policy nên chạy nhiều nơi nhưng có source logic rõ:

- template/module lint cho feedback sớm;
- PR/plan check cho diff và approval;
- cloud organization policy/admission cho hard boundary;
- runtime/config scan cho drift;
- deploy/promotion verifier cho artifact evidence.

Đừng copy rule thủ công giữa năm engine rồi diverge. Chia sẻ test case/requirement ID; mapping implementation
theo backend. Admission webhook là critical infrastructure: scope hẹp, timeout, HA, failure/recovery design.

## 23. Exception là resource có lifecycle

Exception tối thiểu có:

- policy ID/version và exact resource/action;
- requester, owner và risk approver;
- business/technical rationale;
- compensating control;
- start/expiry và review trigger;
- detection/monitoring tăng cường;
- remediation/migration plan;
- immutable audit.

Không dùng label `skip-policy: true` do tenant tự gắn. Engine phải xác minh exception từ authority riêng và alert
khi dùng. Expiry tự động fail/revoke theo policy đã thống nhất, không âm thầm kéo dài.

## 24. GitOps: bốn nguyên tắc và security implication

OpenGitOps nêu desired state phải declarative, versioned/immutable, pulled automatically và continuously
reconciled. Security implication:

- Git/object store cần protection và history integrity;
- reconciler là privileged deployer;
- rendered dependency/remote base cũng là input;
- drift có thể là attacker, emergency change hoặc controller bug;
- source of truth không đồng nghĩa source luôn đúng.

Git chứa desired state và reference secret, không chứa plaintext secret. Admission/provider policy vẫn phải chặn
manifest độc hại đã được merge hợp lệ.

## 25. Repository, review và promotion

Tách source app, platform module, policy và environment config theo ownership/risk. Bảo vệ branch/tag, require
review/status/provenance và owner riêng cho production/policy/workflow.

Promotion nên thay immutable digest/version qua PR; không render/rebuild artifact mới per environment. Approval
cần thấy effective diff, policy result, provenance, impacted fleet/tenant và rollback.

Không để bot có quyền merge thay đổi do chính nó tạo nếu không có invariant independent. Audit bypass, force
push, deleted branch/tag và direct provider change.

## 26. GitOps controller là cluster/fleet principal đặc quyền

Controller có read source và write cluster; multi-cluster controller có blast radius toàn fleet. Giảm quyền:

- AppProject/tenant scope source, destination, namespace và resource kind;
- credential riêng theo cluster/project/environment;
- short-lived/federated identity khi khả thi;
- deny cluster-scoped/sensitive resource trừ platform app;
- repo-server/renderer cô lập khỏi controller secret;
- egress allowlist, signed artifact và audit;
- không cho arbitrary user tạo Application/ApplicationSet trỏ nguồn/đích tùy ý.

Cluster admin mặc định cho mọi app là failure isolation.

## 27. Reconciliation, drift và emergency change

Reconciler có thể tự sửa drift nhưng auto-sync/prune cũng có thể nhân lỗi hoặc xóa resource hàng loạt.

Phân loại drift:

- expected controller/default mutation;
- emergency authorized change;
- manual snowflake;
- attacker/policy bypass;
- source/render nondeterminism.

Alert critical drift và actor; emergency change phải có case/expiry rồi back-port vào source hoặc revert. Prune,
replace và destructive sync cần policy, wave/canary, deletion protection và backup validation.

## 28. Rendering Helm/Kustomize và custom plugin

Renderer xử lý input không tin cậy và có thể thực thi plugin, fetch remote base/chart hoặc đọc environment.

Control:

- pin chart/base/plugin/tool version và digest;
- lock/allowlist remote source;
- render trong sandbox không có cluster/admin secret;
- network off/allowlist, filesystem read-only và resource limit;
- không pass arbitrary Helm parameter thành command;
- validate rendered manifest, không chỉ source template;
- cache tách theo trust và content-addressed;
- store rendered digest/evidence.

Custom config-management plugin là code execution và phải review như build plugin.

## 29. Environment promotion và separation of duties

Một artifact/version đi qua dev → staging → production; environment config riêng nhưng schema/policy nhất quán.

Production promotion cần actor khác hoặc independent control cho high-risk change. Platform admin không nên vừa
sửa template/policy, approve, vừa deploy và xóa audit.

Preview environment từ untrusted PR không nhận production secret/network/cluster credential; có TTL/quota,
owner, randomized identity và cleanup verified.

Rollback dùng known-good immutable revision và kiểm tra data/schema compatibility, không chỉ `git revert`.

## 30. Fleet inventory và multi-cluster identity

Fleet catalog cần cluster immutable ID, provider/account/region, owner, purpose, tenant/trust tier, version,
node/runtime, policy baseline, registered controller, credential, data residency và lifecycle state.

Cluster name/label có thể trùng hoặc đổi. Controller phải bind credential với exact cluster identity/CA/audience,
không chỉ URL/name.

Reconcile registered clusters với provider/observed state; alert unknown/stale cluster, version unsupported,
policy drift và credential dùng sau decommission.

## 31. Đăng ký cluster và credential distribution

Cluster onboarding là ceremony nhạy cảm:

1. verify creator/provider/account và cluster identity;
2. bootstrap baseline network/IAM/audit/policy;
3. cấp controller identity scoped;
4. attest version/config/trust tier;
5. register inventory và ownership;
6. canary reconciliation;
7. mở tenant workload sau verification.

Không copy kubeconfig admin tĩnh vào central secret. Federation/agent pull giúp giảm central credential nhưng
agent/source trust vẫn cần bảo vệ. Offboarding phải revoke credential và remove stale fleet target.

## 32. Rollout theo ring và failure domain

Không đồng bộ module/policy/controller mới vào toàn fleet một lần. Ring ví dụ:

```text
test → internal/non-critical → canary production
  → regional wave → regulated/high-criticality
```

Mỗi wave có entry/exit criteria, soak time, security/business signal, max blast radius, pause/rollback. Chọn canary
đại diện feature/provider/version nhưng không chứa duy nhất workload critical.

Global control plane cần regional/failure-domain isolation; một bad policy/source outage không được chặn mọi
cluster recovery.

## 33. Tenant model trên account, cluster, namespace và node

Chọn boundary theo hostility, data, compliance, privilege và noisy-neighbor risk:

- namespace cho team tin cậy tương đối;
- node pool cho runtime/device/trust tier;
- cluster cho hard hơn về control plane/node blast radius;
- cloud account/project/subscription cho IAM, quota, billing và provider boundary;
- organization/folder guardrail ở tầng cao.

Không dùng một label `tenant` thay toàn bộ isolation. Platform phải derive tenant từ identity/registry, enforce
quota/network/RBAC/secret/data và kiểm thử chéo tenant.

## 34. Service API và resource claim

Platform có thể expose CRD/API như `DatabaseClaim`, `BucketClaim`, `QueueClaim`. Claim controller dùng quyền cao
để tạo external resource, nên là confused-deputy target.

Validate requester/namespace, class, region, data classification, quota và reference. Không cho claim tham chiếu
arbitrary provider credential, secret namespace hoặc external resource của tenant khác.

Status/output không lộ connection secret; publish secret reference/identity binding. Controller phải idempotent,
handle orphan/import/late initialization và audit external API.

## 35. Lifecycle, deletion và ownership transfer

Resource platform-managed cần state:

```text
requested → active → changing → deprecated
  → deletion-requested → retained/quarantined → destroyed
```

Delete cần xác minh owner, dependency, retention/legal hold, backup/restore, data export, key/secret revoke và
provider completion. Finalizer giúp cleanup nhưng có thể treo; không force-remove mà chưa hiểu orphan.

Ownership transfer phải reauthorize IAM, budget, on-call, data purpose và keys. Offboarding team/service không
được để orphan admin credential hoặc resource không owner.

## 36. Data classification, residency và backup trong golden path

Capability input nên yêu cầu data class/purpose/region/retention class, rồi derive encryption, key scope, access,
backup, replication, logging và deletion workflow.

Không cho user chọn region tùy ý nếu data residency cấm; không replicate backup/snapshot ngoài boundary. Platform
metadata/catalog cũng có thể chứa topology, owner và endpoint nhạy cảm.

Golden path phải test restore và deletion, không chỉ create. Exception data cần privacy/security owner và expiry.

## 37. Network, egress và shared service

Platform tạo network baseline: private-by-default, explicit ingress, default-deny/egress control, DNS/metadata/
management endpoint protection, service identity và certificate lifecycle.

Shared ingress, service mesh, DNS, secret broker, CI runner, registry hoặc database proxy là concentration risk.
Tách tenant/purpose, rate/quota, config ownership và failure domain; audit route/policy/certificate change.

Không cấp plugin/controller arbitrary outbound Internet. Egress allowlist/proxy vừa giảm exfiltration vừa làm
dependency resolution reproducible hơn.

## 38. Auditability và evidence của platform

Ghi end-to-end:

```text
requester + team + capability + normalized input
→ policy/approval + template/module version
→ workflow/controller identity + provider operations
→ resource ID/output + verification + lifecycle changes
```

Audit ra ngoài blast radius, không chứa secret, có correlation/request ID và immutable raw event. Người dùng cần
xem “vì sao bị deny” và remediation; security cần exact decision/version.

Detection quan trọng: template/plugin/policy change, platform credential use ngoài workflow, mass provision/delete,
new cluster registration, exception/break-glass, reconciliation drift và audit impairment.

## 39. Supply chain của chính platform

Platform gồm portal, plugin, template, module, controller, runner, provider, chart, base image và policy bundle.
Mọi thành phần cần inventory/SBOM, pin, provenance/signature, dependency update, isolated build, verified deploy và
runtime monitoring.

Một plugin portal có thể thừa hưởng secret/DB; một IaC provider chạy code trong executor; một Helm chart có hook.
Đánh giá privilege khi ưu tiên remediation, không chỉ CVSS.

Platform update phải dùng chính golden path hoặc một bootstrap path có control tương đương—không miễn trừ vì
“đây là platform”.

## 40. SLO và resilience của control plane platform

SLO không chỉ uptime UI:

- provisioning success/latency và reconciliation lag;
- policy decision latency/availability;
- credential issue/revoke;
- deployment/promotion availability;
- audit completeness;
- deletion/cleanup completion;
- recovery point/time cho metadata/config;
- blast radius của failed change.

Thiết kế degraded mode rõ: read-only catalog, freeze high-risk change, cached policy nào được dùng, action nào
fail-closed. Không tự động fail-open production vì portal/webhook outage.

## 41. Upgrade, deprecation và brownfield adoption

Inventory consumer/version và classify unsupported. Cung cấp migration tool/diff, canary, compatibility window,
deadline, exception và owner escalation.

Không auto-upgrade destructive module mà không preview/approval. Đồng thời không giữ version vulnerable vô hạn;
policy có minimum supported version và remediation path.

Brownfield onboarding: discover existing resource, verify/import ownership, evaluate drift và đưa về baseline theo
wave. Không “adopt” resource bằng cách gắn label mà chưa kiểm tra IAM/data/network/lifecycle.

## 42. Break-glass và đường phục hồi độc lập

Break-glass cần khi Git, IdP, portal, policy engine hoặc GitOps controller hỏng. Thiết kế:

- identity/credential tách, hardware/phishing-resistant MFA;
- dual approval khi khả thi;
- JIT, scope/action/time nhỏ;
- out-of-band access nhưng vẫn audit ngoài hệ thống lỗi;
- command/runbook đã test;
- auto-expiry và reconcile/back-port sau sự cố;
- alert ngay và mandatory review.

Không để break-glass phụ thuộc hoàn toàn vào cùng IdP/secret store/DNS đang được khôi phục.

## 43. Threat detection và incident scope của platform

Nếu platform identity/controller bị compromise, scope theo:

- credential/session lifetime và mọi provider/cluster nó quản lý;
- template/module/plugin/policy bị sửa;
- resource/digest được tạo hoặc reconcile;
- secret/data endpoint component có thể đọc;
- audit/sink/config bị impair;
- downstream tenant và failure domain.

Freeze high-risk self-service/promotion, preserve portal/workflow/Git/provider/audit, revoke exact identity và chuyển
sang clean management path. Không xóa controller trước khi biết persistence/source of truth và thu evidence.

## 44. Runbook: template hoặc plugin độc hại

1. Dừng version/action và chặn execution mới; preserve package/source/provenance/config/log.
2. Xác định portal/backend/executor credential, DB, secret, network mà component tiếp cận.
3. Query mọi execution/service/resource tạo từ version trong cửa sổ nghi vấn.
4. Revoke credential/secret có thể lộ; hunt provider/cluster/data action.
5. Remove component và dependency trên build/deploy sạch; không chỉ rollback UI.
6. Re-verify output/resource; repair hoặc replace theo wave.
7. Cập nhật vetting, sandbox, permission và detection.

Template sinh code xấu có thể tồn tại trong hàng trăm repo sau khi template bị gỡ.

## 45. Runbook: GitOps controller bị compromise

1. Freeze sync/promotion phù hợp và bảo toàn controller/repo/cluster audit.
2. Revoke controller cluster/repository/provider credential; chặn issuance mới.
3. Liệt kê cluster/app/resource/digest bị sync trong cửa sổ; tìm out-of-band object/static workload.
4. Verify source history/approval, renderer/plugin và desired-vs-observed state.
5. Rebuild controller trên management plane sạch với credential scoped mới.
6. Reconcile known-good revision theo canary/wave; tránh mass prune.
7. Hunt persistence, secret access và tenant impact; update isolation.

Git đúng không chứng minh cluster sạch nếu compromised controller đã tạo resource ngoài source.

## 46. Runbook: policy engine hoặc admission outage

1. Xác định failure là availability, misconfiguration hay compromise; freeze rule/engine changes.
2. Kiểm tra failurePolicy/degraded behavior và workload/resource được admit trong blind window.
3. Khôi phục replica/network/certificate/dependency bằng clean config; giữ audit.
4. Không chuyển fail-open toàn fleet mà thiếu risk approval, scope và expiry.
5. Rescan/revalidate object đã tạo khi enforcement thiếu.
6. Reconcile exception/bypass và alert owner.
7. Test canary deny/allow, latency và recovery trước mở lại change.

Recovery path phải cho phép sửa chính engine mà không trao bypass vô hạn cho application tenant.

## 47. Kiểm thử platform như một sản phẩm nhiều tenant

Test layers:

- contract/schema và authorization unit test;
- template/module snapshot + security test;
- policy positive/negative/exception/expiry;
- integration với provider sandbox/cluster;
- two-tenant isolation dùng ID/resource trùng có chủ đích;
- idempotency/retry/partial failure/rollback;
- load/resource exhaustion/fairness;
- dependency outage/degraded mode;
- adversary test SSRF, template injection, confused deputy, malicious plugin;
- disaster recovery và break-glass.

Test effective rendered/applied resource, không chỉ input YAML hoặc portal response.

## 48. Product/adoption metric có ý nghĩa security

| Metric | Ý nghĩa |
|---|---|
| Golden-path adoption theo service/environment | guardrail có được dùng thật không |
| Time-to-first-safe-deploy/provision | friction của đường an toàn |
| Self-service success + retry/partial failure | reliability và duplicate/orphan risk |
| Top bypass/exception reason | capability/product gap |
| Template/module version distribution | upgrade/security debt |
| User satisfaction + support ticket cause | abstraction có đúng nhu cầu không |
| Brownfield coverage/orphan owner rate | unmanaged attack surface |

Không tối ưu số resource được tạo hoặc số policy deny. Platform thành công khi team đạt outcome nhanh hơn với
blast radius và toil thấp hơn.

## 49. Security metric và maturity

Đo:

- % capability có owner/threat model/SLO/runbook/audit/revoke;
- % execution dùng short-lived scoped identity;
- verified template/module/plugin/digest coverage;
- tenant isolation test coverage;
- policy enforcement và exception age/expiry;
- direct-provider/out-of-band change + drift;
- critical credential/blast-radius concentration;
- provisioning/deletion evidence completeness;
- time revoke platform identity và scope affected output;
- fleet rollout/rollback/break-glass drill success.

Maturity không phải “đã mua portal”. Nó là khả năng sản phẩm, governance, security và operations cùng tạo outcome
có thể đo, lặp lại và phục hồi.

## 50. Checklist production, anti-pattern và tài liệu chính thức

### Checklist tối thiểu

- [ ] Platform có product owner, user research, capability catalog, trust model và responsibility rõ.
- [ ] Mọi interface dùng cùng authorization; tenant/owner derive từ source tin cậy.
- [ ] Self-service request idempotent, versioned, audit được và có revoke/delete/rollback.
- [ ] Portal plugin, template, action, module, provider và renderer được coi là privileged supply chain.
- [ ] Platform dùng scoped short-lived identity; delegation/requester được giữ trong audit.
- [ ] Golden path secure by default; invariant enforce độc lập; exception có owner/scope/expiry.
- [ ] GitOps source/controller/renderer/cluster credential được tách; deploy/sync theo immutable revision.
- [ ] Fleet có stable identity, trust tier, wave/canary và decommission credential cleanup.
- [ ] Break-glass/degraded mode không fail-open vô hạn và được drill ngoài common dependency.
- [ ] Có runbook plugin/template, GitOps controller và policy-engine compromise/outage.

### Anti-pattern thường gặp

- “Mua developer portal là đã làm platform engineering.”
- “Internal user/plugin/template đều đáng tin.”
- “Default an toàn nghĩa là user không thể đổi thành nguy hiểm.”
- “Git là source of truth nên mọi commit đã merge đều an toàn.”
- “Một controller cluster-admin cho cả fleet đơn giản hơn.”
- “Exception chỉ là label bỏ qua policy.”
- “Platform admin cần mọi quyền để hỗ trợ nhanh.”
- “Số lần provision tăng nghĩa platform thành công.”

### Tài liệu chính thức

- [CNCF Platforms White Paper](https://tag-app-delivery.cncf.io/whitepapers/platforms/)
- [CNCF Platform Engineering Maturity Model](https://tag-app-delivery.cncf.io/whitepapers/platform-eng-maturity-model/)
- [CNCF Platform Engineering Technical Community Group](https://contribute.cncf.io/community/tcgs/platform-engineering/)
- [OpenGitOps Principles](https://opengitops.dev/)
- [Backstage Threat Model](https://backstage.io/docs/overview/threat-model/)
- [Argo CD Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/security/)
- [Kubernetes Multi-tenancy](https://kubernetes.io/docs/concepts/security/multi-tenancy/)
- [Kubernetes Admission Webhook Good Practices](https://kubernetes.io/docs/concepts/cluster-administration/admission-webhooks-good-practices/)
- [Kubernetes Validating Admission Policy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/)
- [NIST SP 800-218 – Secure Software Development Framework](https://csrc.nist.gov/pubs/sp/800/218/final)
- [SLSA Specification v1.2](https://slsa.dev/spec/v1.2/)

### Học tiếp

1. [Security Testing & Validation Engineering](../validation/security_testing_validation_engineering.md) – adversary emulation, control validation và security regression.
2. [Cloud IAM Governance at Scale](../cloud/cloud_iam_governance_at_scale.md) – organization hierarchy, delegated administration và permission lifecycle.

---

*Cập nhật lần cuối: 2026-08-02.*
