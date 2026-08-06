# Feature Flags – tách deploy khỏi release một cách có kỷ luật

> Feature flag cho phép cùng một artifact chạy nhiều code path theo runtime context.
> Nó giảm rủi ro rollout nhưng tạo thêm state, nhánh kiểm thử và control plane. Flag
> không được quản lý vòng đời sẽ trở thành “configuration debt” khó xóa hơn code cũ.

---

## 1. Deploy khác release

```text
Deploy  : đưa code/artifact vào production
Release : cho một nhóm user thật sử dụng behavior mới
```

```java
boolean enabled = flags.getBooleanValue(
    "checkout-v2",
    false,
    evaluationContext
);

return enabled
    ? checkoutV2.process(command)
    : checkoutV1.process(command);
```

Artifact có cả hai path nhưng decision runtime chọn một path. Điều này giúp canary,
kill switch và trunk-based development; đổi lại cả hai path cùng tồn tại và phải
được hiểu/test.

---

## 2. Phân loại flag theo mục đích

| Loại | Tuổi thọ | Dynamism | Ví dụ |
|---|---|---|---|
| Release | Ngắn | Theo cohort/percentage | Checkout v2 |
| Experiment | Theo thử nghiệm | Per subject | Control vs treatment |
| Operational | Có thể dài hơn | Global/region | Tắt recommendation |
| Entitlement/permission | Dài | Per tenant/account | Export thuộc plan Pro |
| Configuration | Dài | Per service/region | Batch size/model version |
| Migration | Ngắn–vừa | Theo shard/tenant | Read old vs new store |

Không dùng cùng lifecycle cho mọi loại. Release flag cần ngày xóa; operational flag
cần runbook; entitlement cần source thương mại/audit; experiment cần assignment và
phân tích thống kê.

---

## 3. Flag không thay authorization hoặc entitlement

Sai:

```java
if (flags.isEnabled("admin-export", userId)) {
    exportAllTenantData(); // flag vô tình cấp quyền
}
```

Đúng:

```text
authorized = user has EXPORT permission
entitled   = tenant contract includes EXPORT
released   = rollout flag enables new export implementation

allow feature = authorized AND entitled
implementation = released ? v2 : v1
```

Feature flag có thể **tắt** một capability để bảo vệ hệ thống, nhưng bật flag không
được vượt authorization/contract. Entitlement source nằm ở plan/billing service,
không phải một boolean chỉnh tay trong dashboard flag.

---

## 4. Một flag là contract có metadata

```json
{
  "key": "checkout-v2",
  "type": "boolean",
  "variations": [false, true],
  "default": false,
  "owner": "team-checkout",
  "category": "release",
  "description": "Use the v2 checkout state machine",
  "createdAt": "2026-07-31T00:00:00Z",
  "expiresAt": "2026-08-31T00:00:00Z",
  "safeFallback": false,
  "ticket": "CHK-2048",
  "rulesVersion": 17,
  "tags": ["checkout", "temporary"]
}
```

Cần:

- stable key không tái sử dụng cho nghĩa khác;
- typed value: boolean/string/number/object;
- default/fallback rõ trong code;
- owner, category, expiry và removal ticket;
- audit rule change;
- environment tách biệt;
- description semantics, không chỉ “new feature”.

---

## 5. Control plane và evaluation plane

```text
                   Control Plane
 Admin/API ─▶ rules/version/audit/RBAC
                    │ stream/poll
          ┌─────────┴─────────┐
          ▼                   ▼
     SDK cache A         SDK cache B       Evaluation Plane
          │                   │
     local evaluate      local evaluate
```

**Control plane** quản lý rule, approval, audit, environment và distribution.

**Evaluation plane** trả variation trên request path. Nên local evaluation từ cache
để không gọi remote service cho mỗi request.

Nếu flag service là synchronous dependency của mọi request, outage control plane có
thể thành outage toàn sản phẩm.

---

## 6. Server-side và client-side evaluation

### Server-side

- context và rule có thể chứa thuộc tính nhạy cảm;
- SDK key có quyền đọc environment;
- decision dùng cho backend behavior/authorization-adjacent path;
- config thường stream/poll về local cache.

### Client-side

- mọi flag/rule/value gửi xuống client có thể bị xem;
- client có thể sửa decision;
- chỉ dùng cho presentation/UX không phải security;
- dùng public/client token với scope hạn chế;
- backend vẫn enforce entitlement/authorization.

Không đưa secret, danh sách tenant nhạy cảm hoặc internal kill switch vào bundle
client.

---

## 7. Evaluation context phải tin cậy

```java
EvaluationContext context = new ImmutableContext(
    tenantId.toString(),
    Map.of(
        "tenantId", new Value(tenantId.toString()),
        "plan", new Value(entitlement.planCode()),
        "region", new Value(deploymentRegion),
        "userIdHash", new Value(userHash)
    )
);
```

Context có thể gồm:

- targeting key ổn định;
- tenant/subject đã xác thực;
- plan từ entitlement source;
- region/stamp/app version;
- cohort/internal/beta membership.

Không tin `plan=enterprise` hoặc `country=...` do client tự gửi. Context phải derive
từ identity/registry tin cậy.

PII: email/IP thường không cần. Hash/pseudonymous ID và attribute allowlist giúp
giảm rò dữ liệu sang provider/log.

---

## 8. Thứ tự rule cần xác định

Ví dụ:

```text
1. Emergency OFF
2. Explicit tenant deny
3. Internal/beta allow
4. Entitled plan + regional constraint
5. Percentage rollout
6. Default
```

Document precedence. Nếu hai rule cùng match mà hệ thống/engine dùng thứ tự khác,
decision sẽ khó giải thích.

Evaluation detail hữu ích:

```text
flag=checkout-v2
value=true
variant=treatment
reason=TARGETING_MATCH
ruleId=beta-tenants
rulesVersion=17
```

Không log full context/PII.

---

## 9. Percentage rollout phải deterministic

Không dùng `random()` mỗi request; user sẽ nhảy giữa hai behavior.

```text
bucket = unsignedHash(flag_key + salt + targeting_key) mod 100_000
enabled nếu bucket < rollout_percentage × 1_000
```

Thuộc tính:

- cùng subject + flag + salt → cùng bucket;
- tăng 10% lên 20% chỉ thêm cohort;
- flag khác có salt/key khác để tránh cohort tương quan ngoài ý muốn;
- targeting key ổn định; không dùng session ID nếu cần stickiness user;
- hash algorithm/version không đổi giữa SDK hoặc rollout.

`Math.abs(hash) % 100` có corner case số âm nhỏ nhất và chỉ 100 bucket khá thô.
Dùng unsigned conversion và bucket space lớn.

---

## 10. Progressive rollout

Một sequence tham khảo:

```text
internal → selected tenant → 1% → 5% → 20% → 50% → 100%
```

Mỗi bước có:

- minimum observation window;
- technical guardrail: error, latency, saturation;
- business guardrail: conversion, completion, support issue;
- segment/stamp/region;
- stop/rollback condition;
- owner on-call;
- kiểm tra sample size đủ.

Không tăng theo lịch cứng khi tín hiệu chưa đủ. `100%` chưa phải hoàn tất: cần xóa
fallback path và flag sau observation period.

---

## 11. Kill switch

Operational flag cần:

- tên và description dễ hiểu khi khẩn cấp;
- safe state được test thường xuyên;
- quyền thay đổi chặt nhưng thao tác nhanh;
- runbook: khi nào tắt/bật lại;
- audit/alert;
- local cached fallback khi provider lỗi;
- không phụ thuộc chính dependency đang cần tắt.

```text
recommendations-enabled=false
→ fallback danh sách phổ biến đã cache
```

Kill switch không hữu dụng nếu old path đã mục hoặc schema mới không còn tương thích.
Test fallback trong production/canary định kỳ.

---

## 12. Failure semantics

Các lỗi:

- provider/config service unavailable;
- SDK chưa initialized;
- cache quá cũ;
- flag không tồn tại;
- type mismatch;
- invalid context;
- parse/rule error;
- config version rollback.

Mỗi evaluation truyền fallback tại code:

```java
boolean value = client.getBooleanValue(
    "optional-recommendations",
    false, // fail safe: tắt feature optional
    context
);
```

Fallback theo risk:

| Feature | Fallback |
|---|---|
| Optional recommendation | Off/simple algorithm |
| Fraud protection | Conservative/on |
| New write path | Old path nếu còn compatible |
| Entitlement | Deny hoặc cached signed entitlement |
| Kill switch | Giá trị cuối đã cache + emergency local config |

Không có một “default off” đúng cho mọi flag.

---

## 13. Cache, freshness và bootstrap

SDK local cache cần:

- bootstrap config đi cùng artifact hoặc persistent cache;
- streaming/polling + version;
- atomic config swap;
- last-known-good;
- stale age metric;
- reconnect backoff + jitter;
- readiness policy;
- không chặn application startup vô hạn.

Trade-off:

```text
freshness cao ↔ phụ thuộc control plane/network nhiều hơn
availability cao ↔ chấp nhận stale config
```

Emergency change cần propagation SLO và xác nhận bao nhiêu instance đã nhận version.
UI báo “saved” không có nghĩa toàn fleet đã áp dụng.

---

## 14. Multi-region consistency

Flag rollout global có thể lệch vài giây/phút giữa region:

```text
Region A rulesVersion=18
Region B rulesVersion=17
```

Thiết kế:

- monotonic config version;
- region-local cache/provider replica;
- atomic publish;
- audit effective time;
- propagation status;
- critical change có acknowledgement/quorum nếu thật sự cần;
- tránh rule phụ thuộc wall clock giữa máy;
- safe behavior trong mixed-version window.

Strong consistency cho mọi evaluation thường quá đắt; code path phải chịu rollout
không đồng thời.

---

## 15. Flag prerequisite và dependency

```text
checkout-v2 requires:
  payment-api-v2 compatible
  order-schema-expanded
```

Dependency graph có thể giúp, nhưng dễ tạo:

- cycle;
- evaluation khó giải thích;
- tắt parent ảnh hưởng hàng chục flag;
- cleanup không biết thứ tự.

Ưu tiên ít prerequisite, DAG được validate và max depth. Với migration, dùng explicit
phase/state machine thay mạng boolean:

```text
OLD_READ_OLD_WRITE
DUAL_WRITE
NEW_READ_DUAL_WRITE
NEW_READ_NEW_WRITE
```

Một enum typed rõ hơn hai flag `read-new` và `write-new` có tổ hợp nguy hiểm.

---

## 16. Feature flag cho data migration

Expand–migrate–contract:

```text
1. Expand schema, code đọc cũ
2. Bật dual-write theo cohort/shard
3. Backfill + verify
4. Bật read-new
5. Tắt old-write
6. Xóa old path/schema sau retention
```

Guard:

- version/checksum đối chiếu;
- tenant/shard stickiness;
- rollback trước contract;
- dual-write idempotent;
- không cho user tùy chọn migration flag;
- flag lifecycle gắn migration state/ticket.

Rollback code không thể phục hồi dữ liệu đã ghi sai. Flag là công cụ điều phối, không
thay migration/reconciliation.

---

## 17. Multi-tenant targeting

Rule:

```text
eligible = entitlement includes ANALYTICS_V2
target   = internal OR beta tenant OR percentage cohort
enabled  = eligible AND target AND not emergency-disabled
```

Tenant-level rollout tránh hai user cùng công ty thấy workflow/schema khác nhau.
User-level phù hợp UX cá nhân/experiment.

Khi tenant di chuyển stamp hoặc user đổi tenant:

- targeting key/context ổn định;
- membership và plan lấy từ trusted source;
- cache key chứa tenant;
- decision không bị reuse giữa tenant;
- support biết flag/variation áp cho tenant nào.

Đọc [Multi-tenancy](multi_tenancy.md).

---

## 18. Experiment không chỉ là percentage rollout

Feature flag phân phối variant; experimentation còn cần:

- hypothesis và primary metric trước khi chạy;
- randomization unit (user/tenant/session);
- exposure event chỉ khi subject thực sự thấy treatment;
- sticky assignment;
- sample ratio mismatch check;
- guardrail metric;
- sample size/duration;
- tránh peeking rồi dừng khi vừa “đẹp”;
- novelty/seasonality/carryover;
- phân tích theo policy thống kê được thống nhất.

```text
assignment ≠ exposure ≠ conversion
```

Nếu evaluate flag nhưng UI không render, không ghi exposure. Nếu B2B feature ảnh
hưởng cả tổ chức, randomize user có thể gây contamination; randomize tenant.

Experiment flag cần đóng, chọn winner và xóa instrumentation/path thua.

---

## 19. Typed variations và configuration

Boolean explosion:

```text
new-checkout
new-checkout-layout
new-checkout-payment
```

Có thể thay bằng typed variation:

```json
{
  "flow": "v2",
  "layout": "compact",
  "paymentTimeoutMs": 3000
}
```

Nhưng object flag lớn biến flag system thành config database không schema. Cần:

- schema/version;
- validation range;
- backward-compatible parsing;
- immutable typed config object;
- safe default;
- không chứa secret;
- size/depth limit.

Business config dài hạn có thể phù hợp configuration service hơn feature flag.

---

## 20. OpenFeature để giảm coupling SDK

OpenFeature cung cấp API trung lập cho:

- typed evaluation;
- provider abstraction;
- evaluation context;
- hooks;
- evaluation details/reason;
- events/tracking.

```java
Client client = OpenFeatureAPI.getInstance()
    .getClient("checkout-service");

boolean enabled = client.getBooleanValue(
    "checkout-v2",
    false,
    context
);
```

Provider có thể bọc vendor SDK, file hoặc service nội bộ. Abstraction giúp đổi
backend ít ảnh hưởng business code, nhưng rule semantics/capability giữa provider
vẫn khác; cần portability test chứ không chỉ compile.

---

## 21. Security và governance

Quyền:

| Role | Hành động |
|---|---|
| Developer | Tạo draft ở dev/test |
| Product/experiment owner | Thay targeting trong phạm vi |
| On-call | Dùng approved kill switch |
| Approver | Production high-risk change |
| Auditor | Read audit history |

Phòng vệ:

- SSO/MFA và least privilege;
- environment/project separation;
- approval cho global/financial/security flag;
- audit before/after, actor, reason, ticket;
- secret rotation cho SDK credential;
- change notification;
- no direct DB edit;
- break-glass có expiry và post-review;
- backup/export config;
- context PII minimization.

Control plane bị chiếm có thể đổi behavior toàn sản phẩm; bảo vệ như production
deployment system.

---

## 22. Testing

### Unit

Inject fake flag client và test cả variations:

```text
checkout-v2=false → old path invariant
checkout-v2=true  → new path invariant
provider error    → fallback invariant
```

### Contract/integration

- type/default/context key;
- rule precedence;
- deterministic bucketing;
- config version propagation;
- stale/offline bootstrap;
- entitlement + flag composition;
- migration mixed versions.

### Combinatorial explosion

N boolean flag tạo tối đa `2^N` tổ hợp. Không test tất cả; giảm bằng:

- tránh flag tương tác;
- pairwise/risk-based test;
- validate prerequisite/DAG;
- snapshot active flag matrix;
- xóa flag sớm.

---

## 23. Lifecycle và flag debt

State:

```text
PROPOSED → ACTIVE → ROLLED_OUT → READY_FOR_REMOVAL → REMOVED
```

Automation:

- bắt buộc owner/category/expiry;
- alert flag quá hạn;
- scan code reference;
- dashboard flag ở 0%/100% lâu;
- ticket cleanup;
- đo age theo category;
- không cho tạo key đã retired;
- removal PR xóa cả true/false path, test, rule và analytics.

Release flag tại 100% vẫn có chi phí: branch, cognitive load, test matrix và old
dependency. “Để phòng khi cần rollback” vô thời hạn là code chết được điều khiển từ xa.

---

## 24. Quan sát evaluation mà không nổ cardinality

Theo dõi:

- evaluation count/error/fallback;
- provider ready/stale/config version;
- variation distribution;
- propagation delay;
- flag change audit;
- rollout guardrail;
- kill switch activation;
- overdue flag.

Không label metric bằng `user_id`/`tenant_id`/mọi flag nếu cardinality lớn. Dùng:

- bounded flag/variant cho các rollout đang active;
- sampling;
- logs/traces với decision detail khi cần;
- top tenant/cohort;
- experiment exposure pipeline riêng.

Không gửi event mạng đồng bộ cho mọi evaluation; batch/async và có backpressure.

---

## 25. Ví dụ: rollout checkout v2

### Điều kiện

```text
authorized checkout
AND tenant ACTIVE
AND payment provider v2 available in region
AND not emergency-disabled
AND (
  internal tenant
  OR beta allowlist
  OR deterministic percentage cohort
)
```

### Quy trình

1. Expand schema và deploy code cả hai path.
2. Flag mặc định `false`, test fallback.
3. Bật internal tenant.
4. Bật 5 tenant beta; theo dõi invariant/payment/support.
5. Rollout tenant-level 1% → 10% → 50%.
6. Nếu payment error vượt guardrail, emergency off.
7. Đạt 100%, giữ observation window.
8. Xóa v1, flag, rule, test cũ và schema cũ theo migration plan.

### Điều không được làm

- bật theo user khiến cùng tenant có order format khác nhau;
- dùng flag để bỏ payment authorization;
- rollback sau khi schema contract đã xóa;
- đổi hash salt giữa rollout;
- coi evaluate=true là exposure nếu checkout chưa render.

---

## 26. Failure modes thường gặp

| Sự cố | Hậu quả | Phòng vệ |
|---|---|---|
| Remote evaluate mỗi request | Flag service lỗi kéo sập app | Local SDK cache |
| Client context tự khai plan | Bypass entitlement | Trusted server context |
| Flag cấp authorization | Data/security leak | AuthZ + entitlement riêng |
| Random mỗi request | User nhảy variant | Deterministic bucket |
| Hash/key đổi giữa SDK | Cohort churn | Algorithm contract/test |
| Default luôn false | Tắt fraud/security control khi lỗi | Risk-based fallback |
| Client-side chứa internal rule | Lộ tenant/strategy | Server-side evaluation |
| Global change không canary | Blast radius toàn fleet | Staged rollout/approval |
| Experiment ghi assignment như exposure | Metric bias | Exposure tại render/use |
| Hai migration boolean độc lập | Tổ hợp read/write nguy hiểm | Typed phase state |
| Flag 100% không xóa | Code debt `2^N` | Owner/expiry/automation |
| Kill switch chưa từng test | Không cứu được khi sự cố | Runbook + exercise |

---

## 27. Decision checklist

- [ ] Flag category, owner, safe fallback và expiry rõ.
- [ ] Authorization/entitlement không phụ thuộc flag để cấp quyền.
- [ ] Evaluation context derive từ nguồn tin cậy và tối thiểu PII.
- [ ] Rule precedence và evaluation reason giải thích được.
- [ ] Percentage rollout deterministic với targeting key ổn định.
- [ ] Local cache/bootstrap chịu được control-plane outage.
- [ ] Config version và propagation SLO được theo dõi.
- [ ] Multi-region mixed-version behavior an toàn.
- [ ] Kill switch có runbook, quyền và fallback đã test.
- [ ] Migration dùng phase rõ, không tổ hợp boolean nguy hiểm.
- [ ] Experiment phân biệt assignment/exposure/conversion.
- [ ] Client-side không chứa secret/internal targeting.
- [ ] Production change có RBAC, approval và audit.
- [ ] Test cả true, false, error/stale và flag interaction.
- [ ] Có kế hoạch xóa code path và flag.

---

## 28. Câu hỏi phỏng vấn thường gặp

1. Deploy khác release thế nào?
2. Release, operational, experiment và entitlement flag khác nhau ra sao?
3. Vì sao feature flag không được thay authorization?
4. Remote evaluation trên request path nguy hiểm gì?
5. Percentage rollout giữ user trong cohort thế nào?
6. Khi provider lỗi, fallback nên on hay off?
7. Client-side flag có thể bảo vệ paid feature không?
8. Multi-region config propagation gây trạng thái gì?
9. Feature flag hỗ trợ database migration thế nào?
10. Assignment khác exposure trong A/B test ra sao?
11. Vì sao nhiều boolean migration flag nguy hiểm?
12. Làm sao phát hiện và xóa flag debt?

---

## 29. Nguồn và chủ đề tiếp theo

Nguồn tham khảo chính:

- [OpenFeature Specification](https://openfeature.dev/specification/)
- [OpenFeature – Evaluation Context](https://openfeature.dev/docs/reference/concepts/evaluation-context/)
- [OpenFeature – Providers](https://openfeature.dev/docs/reference/concepts/provider/)
- [Martin Fowler – Feature Toggles](https://martinfowler.com/articles/feature-toggles.html)
- [AWS SaaS Lens – Tenant-specific customizations](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/operate.html)

Đọc tiếp:

- [Multi-tenancy](multi_tenancy.md) – trusted tenant context và configuration.
- [Billing & Metering](billing_metering.md) – entitlement/plan source.
- [Rate Limiting](rate_limiting.md) – rollout policy và tenant limits.
- [Databases Design](../fundamentals/databases_design.md) – expand–migrate–contract.
- [Availability & Reliability](../fundamentals/availability_reliability.md) –
  canary, fallback và blast radius.

---

*Cập nhật lần cuối: 2026-07-31*
