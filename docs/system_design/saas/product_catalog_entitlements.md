---
title: "SaaS Product Catalog, Entitlements & Quotas"
topic: system_design
level: advanced
review_status: verified
content_updated: 2026-08-10
last_verified: 2026-08-10
version_scope: "Kiến trúc vendor-neutral; ví dụ đối chiếu Stripe Billing ngày 2026-08-10"
source_count: 5
---

# SaaS Product Catalog, Entitlements & Quotas

> Thuật ngữ: [Glossary](../glossary.md).

Chương này giải quyết câu hỏi **tenant được dùng capability nào, với limit nào, trong khoảng thời gian nào**. Cách thu usage, rating, invoice và payment nằm tại [Billing & Metering](billing_metering.md).

## 1. Tách các khái niệm dễ bị trộn

| Khái niệm | Trả lời câu hỏi |
|---|---|
| Product catalog | Ta bán capability/package nào? |
| Offer/price | Giá và điều kiện thương mại là gì? |
| Contract | Khách hàng đã ký điều khoản nào? |
| Subscription | Contract đang ở lifecycle nào? |
| Entitlement | Tenant có quyền dùng capability nào? |
| Seat assignment | Principal nào chiếm/được cấp seat? |
| Quota | Giới hạn kỹ thuật trong cửa sổ nào? |
| Usage meter | Đã sử dụng bao nhiêu? |
| Feature flag | Rollout/experiment implementation nào đang bật? |
| Authorization | Principal có quyền thực hiện action trên resource không? |

```text
allow operation
  = authorized(user, action, resource)
  ∧ entitled(tenant, capability)
  ∧ within_policy(quota/budget)
  ∧ implementation_available(feature/config)
```

Feature flag không chứng minh tenant đã mua; entitlement không chứng minh user có quyền quản trị.

## 2. Catalog cần capability ổn định, offer có version

Capability là tên semantic dùng trong code/policy:

```text
audit.export
sso.saml
project.create
storage.bytes
ai.tokens.generate
```

Offer/plan tham chiếu capability và limit:

```json
{
  "offer_revision": "enterprise-2026-04",
  "effective_from": "2026-04-01T00:00:00Z",
  "entitlements": [
    {"capability": "sso.saml", "mode": "ENABLED"},
    {"capability": "project.create", "limit": 500},
    {"capability": "storage.bytes", "included": 1000000000000}
  ]
}
```

Không đổi nghĩa revision đã được contract sử dụng. Muốn đổi package, tạo revision mới và migration policy.

## 3. Entitlement là effective grant, không chỉ plan name

Effective entitlement có thể được hợp thành từ:

```text
base offer
+ purchased add-on
+ negotiated override
+ temporary promotion/trial
+ support remediation credit
- suspension/compliance restriction
= effective entitlement snapshot
```

Mỗi grant cần provenance:

- source/contract/add-on;
- effective interval;
- priority hoặc composition rule;
- value/limit;
- reason và approver;
- revision;
- audit timestamps.

Nếu chỉ lưu `plan=enterprise`, mọi exception sẽ thành `if tenant_id == ...` trong code.

## 4. Entitlement state machine

```text
PENDING ──effective time──► ACTIVE
ACTIVE ──expire───────────► EXPIRED
ACTIVE ──suspend──────────► SUSPENDED
ACTIVE ──replace──────────► SUPERSEDED
```

Không xóa grant lịch sử vì billing dispute, audit và replay cần biết policy nào có hiệu lực tại event time.

## 5. API check contract

```json
POST /entitlements/check
{
  "tenant_id": "tn_acme",
  "capability": "project.create",
  "at": "2026-08-10T09:00:00Z",
  "usage_context": {"current_projects": 418}
}
```

```json
{
  "allowed": true,
  "mode": "LIMITED",
  "limit": 500,
  "remaining": 82,
  "entitlement_revision": 73,
  "reason_code": "WITHIN_CONTRACT_LIMIT"
}
```

Response nên có revision/reason code cho support và cache invalidation. Client không parse human message để quyết định logic.

## 6. Snapshot và evaluation

Hai mô hình:

### Evaluate động

Đọc contract/add-on/override rồi tính mỗi request. Dễ nhất quán với source nhưng latency và availability phụ thuộc nhiều bảng/service.

### Materialized effective snapshot

Control plane tính snapshot versioned, data plane đọc nhanh:

```text
tenant_id | entitlement_revision | capability | mode | value | effective_until
```

Phù hợp SaaS lớn, nhưng phải reconcile snapshot với source grants và xử lý event out-of-order.

Mô hình thực tế thường materialize snapshot, giữ ledger/grant nguồn để rebuild.

## 7. Cache và consistency

Cache key tối thiểu:

```text
(tenant_id, capability, entitlement_revision)
```

Invalidation:

- event `EntitlementSnapshotPublished`;
- TTL giới hạn stale window;
- data plane nhận minimum required revision ở thao tác nhạy cảm;
- suspension/credit exhaustion có fast-path invalidation;
- last-known-good chỉ dùng theo operation policy.

Failure semantics khác nhau:

| Operation | Entitlement service hỏng |
|---|---|
| Đọc feature không nhạy cảm | cached grant ngắn hạn có thể chấp nhận |
| Tạo resource gây cost lớn | fail-closed hoặc degraded quota |
| Export dữ liệu/compliance | fail-closed |
| Existing workload critical | grace window theo contract |

## 8. Seat entitlement

Phân biệt:

- purchased seats;
- assigned seats;
- active users;
- invited users;
- billable seats theo contract.

Race điển hình: hai admin assign seat cuối cùng. Dùng atomic reservation/unique invariant:

```text
available = purchased + temporary_overage - active_assignments - reservations
```

Invitation không nhất thiết chiếm seat ngay; policy phải rõ khi nào seat được reserve và bao lâu.

## 9. Quota, rate limit và budget

| Cơ chế | Mục tiêu | Ví dụ |
|---|---|---|
| Entitlement limit | Contract/product | tối đa 500 project |
| Rate limit | Bảo vệ capacity/fairness | 100 request/s |
| Concurrency limit | Bảo vệ resource đang chạy | 10 export đồng thời |
| Usage budget | Giới hạn consumption/cost | 1M AI token/tháng |
| Billing meter | Tính tiền/reconcile | 1.23M token billable |

Không dùng Redis rate-limit counter làm billing ledger. Counter realtime có thể approximate; financial usage cần immutable event/correction và reconciliation.

## 10. Hard, soft và elastic limits

- **Hard:** từ chối ngay khi vượt; phù hợp security/compliance hoặc resource hữu hạn.
- **Soft:** cảnh báo nhưng cho tiếp tục; phù hợp adoption/trial.
- **Elastic overage:** tiếp tục và tính phí; cần customer visibility.
- **Grace:** cho vượt trong interval ngắn để tránh outage.

Mỗi limit contract cần:

```text
window + reset rule + timezone + aggregation key
+ threshold + enforcement mode + overage behavior
+ notification thresholds + source of truth
```

## 11. Reservation cho operation dài

Check-then-create bị race. Với export, storage hoặc job đắt:

```text
reserve(amount, idempotency_key, expires_at)
  → commit(actual_amount)
  → release/expire
```

Invariant:

- reservation idempotent;
- expiry không giải phóng job vẫn chạy mà không reconcile;
- commit có thể nhỏ/lớn hơn estimate theo policy;
- stuck reservation được monitor;
- billing usage event liên kết operation/reservation nhưng là record riêng.

## 12. Upgrade và downgrade theo effective time

Upgrade thường có thể mở capability sớm, nhưng downgrade nguy hiểm:

- tenant đang có 500 project nhưng plan mới cho 100;
- SSO bị mất có thể khóa admin;
- retention giảm ảnh hưởng dữ liệu cũ;
- API version/add-on đang được integration dùng;
- background job đang chạy.

Chọn policy theo capability:

1. grandfather existing resource, chặn create mới;
2. grace period và remediation workflow;
3. archive/read-only;
4. hard revoke tại effective time;
5. require pre-downgrade validation và không cho đổi nếu chưa đạt.

## 13. Trial và promotion

Trial không nên là plan đặc biệt hard-code. Dùng grant có:

- start/end;
- capability/limit;
- conversion target;
- extension policy;
- abuse controls;
- notification schedule;
- expiry transition;
- data behavior khi không convert.

Clock phải là server time; job expiry và request-time evaluation cùng semantics.

## 14. Enterprise override và contract amendment

Override cần scope hẹp, expiry và approval. Tránh “enterprise=true” mở mọi thứ.

```json
{
  "tenant_id": "tn_acme",
  "capability": "storage.bytes",
  "operation": "REPLACE_LIMIT",
  "value": 5000000000000,
  "effective_from": "2026-09-01T00:00:00Z",
  "effective_until": "2027-09-01T00:00:00Z",
  "contract_ref": "ctr_88",
  "approved_by": "usr_finops_7"
}
```

## 15. Subscription và payment state không map 1:1 vào entitlement

Payment failure không luôn đồng nghĩa revoke tức thì. Cần policy:

```text
invoice overdue
  → dunning/grace
  → restrict cost-growing operations
  → suspend selected capabilities
  → tenant suspension/offboarding nếu hết grace
```

Entitlement service nhận commercial decision đã chuẩn hóa, không tự diễn giải mọi webhook provider.

## 16. Event contract

```json
{
  "event_id": "evt_01J...",
  "type": "EntitlementSnapshotPublished",
  "tenant_id": "tn_acme",
  "revision": 73,
  "effective_at": "2026-08-10T09:00:00Z",
  "source_operation_id": "op_contract_amendment_4"
}
```

Consumer:

- dedupe theo event ID;
- chỉ apply revision lớn hơn;
- fetch snapshot nếu bỏ lỡ event;
- không suy ra full state từ một delta không có base;
- hỗ trợ replay/rebuild.

## 17. Reconciliation

Đối soát ít nhất ba chiều:

```text
commercial contract/subscription
        ↕
effective entitlement snapshot
        ↕
observed enforcement/usage
```

Finding ví dụ:

- tenant trả tiền nhưng capability bị deny;
- tenant đã downgrade nhưng cached grant vẫn cho create;
- assigned seat vượt purchased seat;
- usage tăng nhưng meter không nhận event;
- provider subscription không map tới internal contract revision.

## 18. Observability

- check latency/error/cache-hit;
- deny theo reason code/capability;
- snapshot publication lag;
- revision stale theo cell;
- reservation stuck/expired;
- seat utilization;
- approaching/exceeded quota;
- override sắp hết hạn;
- contract↔entitlement reconciliation mismatch;
- estimated cost per capability/tenant cohort.

Không label raw tenant ID lên mọi metric. Dùng log/trace có access control cho điều tra tenant cụ thể và metric aggregate theo plan/cell/reason.

## 19. Test matrix

- upgrade effective đúng timestamp;
- downgrade khi current usage vượt limit;
- duplicate/out-of-order snapshot event;
- check trong lúc cache/control plane hỏng;
- concurrent seat assignment cuối cùng;
- reservation timeout/commit/retry;
- trial expiry khi job đang chạy;
- suspension fast invalidation;
- override precedence và expiry;
- billing correction không mutate historical entitlement decision.

Property quan trọng:

```text
Không có operation được commit nếu reservation/decision không thuộc cùng tenant.
Một revision entitlement đã publish là immutable.
Rebuild từ grant ledger tạo cùng effective snapshot tại cùng timestamp.
```

## 20. Failure modes

| Failure mode | Hậu quả | Guardrail |
|---|---|---|
| Code check `plan == PRO` khắp nơi | khó đổi catalog | stable capability ID |
| Flag thay entitlement | tenant chưa mua vẫn dùng | check entitlement riêng |
| Entitlement thay authorization | user thường làm admin action | cả hai decision |
| Update catalog revision cũ | đổi contract lịch sử | immutable revision |
| Check-then-create quota | vượt limit do race | reservation/atomic invariant |
| Revoke ngay khi webhook payment lỗi | outage khách hàng | dunning/grace policy |
| Cache không có revision | stale không kiểm soát | versioned snapshot |
| Override không expiry | entitlement vĩnh viễn ngoài contract | expiry/approval/audit |

## 21. Checklist production

- [ ] Capability ID ổn định, offer/catalog revision immutable.
- [ ] Grant có source, effective interval, priority và audit.
- [ ] Entitlement, authorization, feature flag và billing meter được tách.
- [ ] Cache/snapshot có revision và stale policy.
- [ ] Seat/quota operation chống race bằng reservation hoặc atomic invariant.
- [ ] Upgrade/downgrade định nghĩa behavior cho resource đang tồn tại.
- [ ] Payment failure đi qua commercial policy trước khi revoke.
- [ ] Có reconciliation contract→entitlement→enforcement/usage.
- [ ] Customer xem được usage, limit, overage và effective change.

## 22. Nguồn và học tiếp

- [Stripe – Usage-based billing](https://docs.stripe.com/billing/subscriptions/usage-based)
- [Stripe – Subscription lifecycle](https://docs.stripe.com/billing/subscriptions/overview)
- [Stripe – Entitlements](https://docs.stripe.com/billing/entitlements)
- [AWS SaaS Lens – Tenant activity and consumption](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-activity-and-consumption.html)
- [AWS SaaS Lens – Tenant tiers](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-tiers.html)

Học tiếp: [Billing & Metering](billing_metering.md), [Rate Limiting](rate_limiting.md) và [Feature Flags](feature_flags.md).

