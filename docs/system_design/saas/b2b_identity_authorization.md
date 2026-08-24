---
title: "B2B SaaS Identity, SSO, SCIM & Authorization"
topic: system_design
level: advanced
review_status: verified
content_updated: 2026-08-10
last_verified: 2026-08-10
version_scope: "OIDC Core 1.0, SCIM RFC 7643/7644 và OAuth BCP RFC 9700"
source_count: 9
---

# B2B SaaS Identity, SSO, SCIM & Authorization

> Thuật ngữ: [Glossary](../glossary.md).

Chương này tập trung vào identity model đặc thù của B2B SaaS. Cryptography, token validation tổng quát và IAM governance sâu hơn nằm tại [IAM Authentication & Authorization](../../security/identity/iam_authentication_authorization.md).

## 1. Tách authentication, membership, authorization và entitlement

```text
Authentication: principal này là ai?
Membership:     principal thuộc organization/workspace nào?
Authorization:  principal được action gì trên resource cụ thể?
Entitlement:    organization đã mua/có capability đó chưa?
```

Một request chỉ được phép khi tất cả lớp cần thiết đều đúng:

```text
allow = authenticated
     ∧ active_membership(subject, tenant)
     ∧ authorized(subject, action, resource)
     ∧ entitled(tenant, capability)
     ∧ contextual_policy(time, device, risk, data_region)
```

Không dùng feature flag thay authorization, cũng không dùng role thay commercial entitlement.

## 2. Domain model B2B

```text
Principal/User
  ├── Membership ──► Organization/Tenant
  │                     ├── Workspace/Project
  │                     ├── SSO connection
  │                     ├── SCIM directory
  │                     └── Subscription/Entitlement
  ├── Service account
  └── External collaborator
```

Nguyên tắc:

- một user có thể thuộc nhiều tenant;
- email không phải tenant ID và có thể đổi;
- verified domain không tự động chứng minh mọi user dùng domain đó thuộc tenant;
- membership có lifecycle riêng: invited, active, suspended, removed;
- external collaborator không nhất thiết thuộc corporate directory;
- service account/workload identity không dùng lifecycle giống human user.

## 3. Tenant selection phải chống confused deputy

Nguồn tenant có thể là custom domain, subdomain, route, session hoặc token. Server phải:

1. xác thực principal;
2. derive tenant candidate từ route/session được tin cậy;
3. kiểm tra active membership hoặc workload binding;
4. load resource bằng composite tenant scope;
5. kiểm tra authorization trên resource thực;
6. ghi audit decision.

Không chấp nhận `X-Tenant-Id` từ client như bằng chứng quyền. Header có thể là input chọn context, nhưng phải được đối chiếu membership/authorization.

## 4. Organization discovery và domain verification

Domain discovery giúp tìm SSO connection, nhưng có rủi ro takeover. Quy trình an toàn:

- tenant chứng minh quyền domain qua DNS TXT hoặc phương thức được phê duyệt;
- domain claim là unique hoặc có conflict workflow rõ;
- thay đổi DNS không tự động chuyển ownership ngay;
- consumer/free-email domain không được dùng auto-join;
- subdomain và parent domain có policy riêng;
- admin takeover/recovery yêu cầu step-up và audit;
- auto-join tách khỏi domain verification và mặc định opt-in.

## 5. SSO connection là configuration có version

Một organization có thể có nhiều connection trong migration hoặc merger:

```text
connection_id
tenant_id
protocol: OIDC | SAML
issuer/entity_id
client_id / metadata revision
allowed_domains
claim_mapping_revision
status: TESTING | ACTIVE | DRAINING | DISABLED
created_by / approved_by
```

Không activate connection chỉ vì metadata parse được. Test cần:

- issuer/audience/signature/time validation;
- redirect URI exact match;
- nonce/state/PKCE theo flow;
- claim mapping và subject stability;
- group overage/missing group behavior;
- IdP-initiated flow policy nếu hỗ trợ;
- break-glass login;
- logout/session revoke expectation.

## 6. OIDC subject mapping

Identity key không nên chỉ là email. Thường dùng tuple ổn định:

```text
(issuer, subject) → external_identity → internal_principal_id
```

Email là attribute có thể thay đổi hoặc tái sử dụng. Khi account linking:

- yêu cầu authenticated proof từ cả identity hoặc admin-approved workflow;
- không auto-link chỉ vì email giống nhau;
- lưu history và audit;
- chống link nhầm giữa hai tenant/issuer;
- có rollback/recovery khi IdP đổi subject mapping.

## 7. Invitation, JIT và SCIM giải quyết bài toán khác nhau

| Cơ chế | Dùng cho | Điểm yếu chính |
|---|---|---|
| Invitation | Cộng tác có chủ đích | link forward, email đổi, stale invite |
| JIT provisioning | Tạo membership lúc SSO login | không offboard user chưa login lại |
| SCIM | Đồng bộ lifecycle/group từ directory | eventual consistency, duplicate/out-of-order |
| Manual admin | Ngoại lệ/support | drift, human error |

SSO không tự động offboard account. Deprovision thường cần SCIM/event và phải revoke session/token riêng.

## 8. Invitation contract

Invitation nên có:

- opaque random token, chỉ lưu hash;
- tenant, intended email/domain và role template;
- expiry, max-use và status;
- inviter authority snapshot;
- accept transaction idempotent;
- step-up khi cấp quyền nhạy cảm;
- invalidate khi inviter mất quyền hoặc tenant bị suspend;
- audit cho create/resend/revoke/accept.

Sau accept, tạo membership mới; không giữ invitation làm permission source.

## 9. SCIM provisioning là asynchronous reconciliation

SCIM server phải xử lý:

- `Users` và `Groups` với stable external identifier;
- filter/pagination đúng contract;
- PUT/PATCH idempotency;
- deactivate khác hard delete;
- group membership delta và replace;
- retry/duplicate/out-of-order;
- rate limit và bulk limit;
- schema extension;
- tenant-scoped bearer credential;
- correlation/audit không lộ token hoặc PII quá mức.

Mapping khuyến nghị:

```text
(tenant_id, scim_connection_id, externalId)
        → internal principal/membership
```

Không dùng `userName` đơn độc làm unique toàn hệ thống.

## 10. Deprovisioning exit criteria

Khi directory gửi `active=false` hoặc user bị remove:

1. membership chuyển disabled với version;
2. chặn login/mint token mới;
3. revoke hoặc giảm TTL session/refresh token;
4. rotate/reassign personal credential nếu có;
5. pause scheduled job do user sở hữu;
6. xử lý ownership tài liệu/workflow;
7. remove group-derived relation;
8. giữ audit và business record theo retention;
9. phát event idempotent;
10. xác minh authorization cache đã invalidated.

Offboarding “SCIM trả 200” chưa đủ nếu session cũ vẫn hoạt động nhiều ngày.

## 11. Session và token trong multi-tenant SaaS

Token chỉ chứa claim cần thiết và có semantics rõ:

```json
{
  "iss": "https://id.example.com",
  "sub": "usr_123",
  "aud": "api.example.com",
  "exp": 1786352400,
  "sid": "sess_456",
  "tenant": "tn_789",
  "membership_version": 12
}
```

Trade-off:

- nhét mọi permission vào token giảm lookup nhưng permission stale và token phình;
- token chỉ mang subject/tenant rồi query policy tăng dependency/latency;
- mô hình hybrid mang coarse context, còn resource authorization được check online/cached ngắn.

Luôn validate issuer, audience, signature, expiry và flow-specific protection. Không chấp nhận token phát cho API/tenant khác.

## 12. RBAC, ABAC và ReBAC

### RBAC

Phù hợp role ổn định: organization admin, billing admin, member, viewer. Dễ giải thích nhưng role explosion khi mỗi resource có sharing riêng.

### ABAC

Policy dựa attribute như department, classification, region, device posture. Linh hoạt nhưng khó debug nếu attribute stale hoặc nguồn không rõ authority.

### ReBAC

Biểu diễn quan hệ:

```text
user:alice member organization:acme
team:finance member organization:acme
document:q3 parent folder:finance
team:finance viewer folder:finance
```

Phù hợp sharing, hierarchy và delegated administration. Cần quản model version, tuple consistency, list/filter semantics và authorization latency.

Thực tế B2B SaaS thường kết hợp cả ba: RBAC cho coarse role, ReBAC cho resource relation, ABAC cho condition.

## 13. Authorization service contract

```json
POST /authorization/check
{
  "subject": "user:alice",
  "tenant": "tn_acme",
  "action": "document.read",
  "resource": "document:q3",
  "context": {"ip_risk": "low"},
  "policy_version": "optional-minimum"
}
```

Response cần `allowed`, decision ID, model version và reason code an toàn. Không trả graph/policy nhạy cảm cho end user.

Failure semantics:

- admin/write/export: thường fail-closed;
- public content: có thể fallback theo policy riêng;
- cache chỉ dùng khi key gồm subject, tenant, action, resource và policy/model revision;
- timeout budget nhỏ hơn request deadline;
- decision logging phải sampling/cardinality có kiểm soát.

## 14. Policy/model versioning

Thay authorization model có thể làm mất hoặc mở quyền hàng loạt. Quy trình:

1. version immutable;
2. static validation và test matrix;
3. shadow evaluate old/new trên sampled traffic;
4. report allow→deny và deny→allow;
5. canary tenant;
6. activation timestamp/revision;
7. rollback model;
8. migrate tuple/role assignment nếu schema đổi;
9. lưu decision evidence trong cửa sổ audit.

## 15. Service account và workload identity

- scope vào một tenant hoặc provider control plane rõ ràng;
- credential ngắn hạn nếu có thể;
- không chia sẻ user credential cho automation;
- owner, purpose, expiry và last-used bắt buộc;
- rotate/revoke không downtime;
- client credential không mặc nhiên có quyền của tenant admin;
- token exchange/delegation phải giới hạn audience và downstream scope.

## 16. Support impersonation là privileged access

Support access không nên là “login as user” không kiểm soát. Contract tốt gồm:

- user support có role riêng và JIT approval;
- ticket/reason bắt buộc;
- tenant opt-in hoặc notice theo policy;
- step-up MFA;
- scope/time limit;
- banner rõ đang impersonate;
- cấm hành động đặc biệt như đổi SSO, tạo key hoặc xem secret nếu không có approval riêng;
- audit phân biệt actor thật và effective subject;
- emergency path được review sau sử dụng.

```text
actor=support_42
effective_subject=user_7
tenant=tn_acme
reason=ticket_981
session_expires=...
```

## 17. Audit log là security product surface

Audit event cần:

- event ID/time;
- tenant;
- actor và authentication context;
- effective subject nếu delegation;
- action/resource/result;
- policy/model revision;
- source IP/device khi phù hợp;
- correlation/request ID;
- change before/after đã redact;
- integrity/retention/export contract.

Audit log không được trở thành kho secret/token/PII không giới hạn.

## 18. Test matrix

- user thuộc tenant A không đọc object tenant B dù đoán ID;
- cùng user thuộc A và B phải chọn đúng active context;
- removed membership làm session/cache mất hiệu lực trong SLA;
- role downgrade không giữ permission cũ;
- group remove qua SCIM rút quyền derived;
- connection SSO sai issuer/audience bị từ chối;
- invitation replay/expired/revoked thất bại;
- support impersonation vượt scope bị chặn;
- authorization model mới được shadow diff;
- list endpoint chỉ trả object user có quyền, không filter sau pagination sai.

## 19. Failure modes

| Failure mode | Hậu quả | Guardrail |
|---|---|---|
| Dùng email làm identity key | takeover/link nhầm | `(issuer, sub)` + internal ID |
| SSO được coi là offboarding | session/account tồn tại | SCIM + revoke + verification |
| Tin tenant header | cross-tenant access | membership/resource check |
| Permission nằm hết trong token dài hạn | stale privilege | short TTL/version/online check |
| SCIM PATCH không idempotent | duplicate/drift | externalId + reconciliation |
| Support login-as không audit | insider risk | JIT, actor/effective subject |
| Role explosion | khó quản | RBAC + ReBAC/ABAC có ranh giới |
| Authz timeout fail-open cho write | unauthorized mutation | operation-specific failure policy |

## 20. Checklist production

- [ ] User, tenant, membership và external identity là entity riêng.
- [ ] Tenant context luôn được đối chiếu membership/authorization.
- [ ] OIDC/SAML connection có test, version, rollback và break-glass.
- [ ] SCIM credential, external ID và deprovisioning SLA tenant-scoped.
- [ ] Authorization bao gồm resource, action, tenant và model version.
- [ ] Entitlement tách khỏi permission.
- [ ] Service account có owner, expiry, scope và last-used.
- [ ] Support access JIT và audit actor/effective subject.
- [ ] Có tenant-isolation và deprovisioning integration test.

## 21. Nguồn và học tiếp

- [OpenID Connect Core 1.0](https://openid.net/specs/openid-connect-core-1_0-final.html)
- [RFC 9700 – OAuth 2.0 Security Best Current Practice](https://www.rfc-editor.org/rfc/rfc9700)
- [RFC 7643 – SCIM Core Schema](https://www.rfc-editor.org/rfc/rfc7643)
- [RFC 7644 – SCIM Protocol](https://www.rfc-editor.org/rfc/rfc7644)
- [OpenFGA – Authorization concepts](https://openfga.dev/docs/concepts)
- [OWASP Authorization Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)
- [OWASP API Security Top 10 – 2023](https://owasp.org/API-Security/editions/2023/en/0x11-t10/)
- [NIST SP 800-63-4 – Digital Identity Guidelines](https://pages.nist.gov/800-63-4/)

Học tiếp: [Product Catalog & Entitlements](product_catalog_entitlements.md) và [Integration Platform](integration_platform.md).

