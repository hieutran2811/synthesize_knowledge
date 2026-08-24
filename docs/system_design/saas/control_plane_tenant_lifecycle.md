---
title: "SaaS Control Plane & Tenant Lifecycle"
topic: system_design
level: advanced
review_status: verified
content_updated: 2026-08-10
last_verified: 2026-08-10
version_scope: "Kiến trúc độc lập cloud; nguồn được đối chiếu ngày 2026-08-10"
source_count: 4
---

# SaaS Control Plane & Tenant Lifecycle

> Thuật ngữ: [Glossary](../glossary.md).

Chương này đào sâu cách vận hành tenant như một **resource có lifecycle**, không lặp lại lựa chọn silo/pool, RLS và tenant context đã có trong [Multi-tenancy](multi_tenancy.md).

## 1. Control plane và data plane có failure contract khác nhau

```text
Customer/Admin
      │
      ▼
Control plane
  tenant catalog ── placement ── provisioning workflow ── policy/config
      │                                      │
      └──────── desired state/version ───────┘
                                             ▼
Data plane: cell A / cell B / dedicated cell
  API + worker + cache + database + queue
```

- **Control plane** quản lý tenant, placement, plan, cấu hình, lifecycle và desired state.
- **Data plane** phục vụ request/workload nghiệp vụ của tenant.
- Control plane hỏng không nên làm request data plane đang chạy dừng ngay.
- Data plane không được tự ý thay đổi catalog trung tâm chỉ vì local state khác desired state.
- Mọi thay đổi control plane phải có version, audit và cơ chế reconcile.

Một thiết kế tốt ưu tiên **last-known-good configuration** cho data plane. Ví dụ, nếu control plane timeout, cell có thể tiếp tục dùng tenant routing/config đã xác minh gần nhất trong một khoảng freshness cho phép; thao tác quản trị nhạy cảm như mở lại tenant bị suspend có thể fail-closed.

## 2. Tenant catalog là source of truth cho routing và lifecycle

Catalog không chỉ chứa tên khách hàng. Một record tối thiểu:

```json
{
  "tenant_id": "tn_01J...",
  "slug": "acme",
  "state": "ACTIVE",
  "state_version": 17,
  "home_region": "ap-southeast-1",
  "cell_id": "cell-apse1-03",
  "isolation_tier": "pooled",
  "plan_revision": "enterprise-2026-04",
  "config_revision": 42,
  "provisioning_operation_id": "op_01J...",
  "created_at": "2026-08-10T09:00:00Z"
}
```

Invariant quan trọng:

1. `tenant_id` bất biến; domain, slug và display name có thể đổi.
2. Routing dựa trên mapping đã ký/ủy quyền, không dựa vào header tùy ý của client.
3. Mỗi thay đổi lifecycle dùng optimistic concurrency qua `state_version`.
4. Một tenant chỉ có một write home tại một thời điểm, trừ khi kiến trúc hỗ trợ multi-writer thật sự.
5. Catalog ghi desired state; reconciler xác nhận actual state theo từng resource.

## 3. Lifecycle phải là state machine rõ ràng

```text
REQUESTED
   │ approve/contract valid
   ▼
PROVISIONING ──failure──► PROVISIONING_FAILED
   │ ready                    │ retry/compensate
   ▼                          └──────────────┐
ACTIVE ◄────────────────────────────────────┘
   │ payment/risk/admin
   ▼
SUSPENDED ──remediate──► ACTIVE
   │ terminate
   ▼
OFFBOARDING ──retention/legal hold──► DELETION_PENDING
   │ deletion verified
   ▼
DELETED
```

Không dùng một boolean `active`. Boolean không biểu diễn được provisioning dở dang, suspension có thể phục hồi, legal hold hay deletion chưa được xác minh.

Mỗi transition cần:

- actor và authority;
- precondition;
- idempotency key;
- expected state/version;
- deadline;
- side effect cần tạo;
- compensation hoặc repair action;
- audit event;
- exit criteria có thể đo.

## 4. Onboarding là workflow dài, không phải một transaction database

Một onboarding B2B thường gồm:

1. tạo tenant identity bất biến;
2. xác minh contract, plan và home region;
3. chọn cell còn capacity;
4. tạo database/schema/bucket/key namespace theo isolation tier;
5. bootstrap role, organization admin và policy version;
6. tạo billing customer/subscription mapping;
7. cấu hình domain/SSO nếu có;
8. seed configuration an toàn;
9. chạy smoke test trong tenant context;
10. publish `TenantActivated` và mở routing;
11. ghi evidence cho support/audit.

Không giữ distributed transaction qua các bước. Dùng persisted workflow/Saga với step state:

```text
operation_id | tenant_id | step              | status    | attempt | output_ref
op_123       | tn_123    | ALLOCATE_CELL     | SUCCEEDED | 1       | cell-03
op_123       | tn_123    | CREATE_NAMESPACE  | SUCCEEDED | 2       | ns-88
op_123       | tn_123    | CREATE_KEY        | RUNNING   | 1       | null
```

## 5. Idempotency ở từng step

Retry toàn workflow không đủ; mỗi adapter phải idempotent:

```text
ensureNamespace(tenant_id, desired_revision)
ensureKeyAlias(tenant_id)
ensureBillingAccount(tenant_id, contract_id)
ensureAdminMembership(tenant_id, principal_id)
```

Nguyên tắc:

- tên external resource derive từ stable ID hoặc lưu mapping duy nhất;
- create timeout phải chuyển sang **read-after-unknown**, không create mù lần hai;
- response external ID được persist trước khi chạy step tiếp;
- compensation chỉ xóa resource chắc chắn thuộc operation và không còn consumer;
- retry có exponential backoff, jitter và attempt budget;
- operator có thể resume từ step hỏng thay vì chạy lại mọi thứ.

## 6. Tenant placement là quyết định có version

Input placement thường gồm:

- home region/data residency;
- isolation tier;
- workload class và predicted usage;
- compliance boundary;
- feature/capability cần có;
- current headroom của cell;
- affinity/anti-affinity;
- release ring;
- cost và commercial commitment.

```text
eligible cells
  = region compatible
  ∩ isolation compatible
  ∩ capability compatible
  ∩ release compatible
  ∩ capacity above safety margin
```

Không chỉ đếm tenant. Một tenant nhỏ và một tenant chạy batch 10 TB không có cùng weight. Capacity model cần proxy như request concurrency, DB working set, queue throughput, connection và storage growth.

## 7. Cell/deployment stamp giới hạn blast radius

Mỗi cell chứa tập resource đủ để phục vụ một nhóm tenant và có thể deploy/scale độc lập. Cell giúp:

- giữ failure trong một phần tenant;
- mở rộng bằng cách thêm scale unit;
- đặt tenant theo region/compliance;
- rollout theo ring;
- tách hot tenant hoặc khách hàng cần dedicated isolation.

Đổi lại:

- control plane và router trở thành critical dependency;
- fleet deployment/config drift khó hơn;
- cross-cell analytics cần aggregation;
- move tenant phức tạp;
- cell nhỏ làm baseline cost tăng.

Nên có ít nhất hai cell từ sớm trong môi trường staging hoặc production nhỏ để phát hiện assumption hard-code về “cell duy nhất”.

## 8. Tenant routing

Request path tham chiếu:

```text
Host/token/session
   │ derive authenticated tenant
   ▼
Tenant resolver ──► signed/cacheable placement record
   │                         │
   │ mismatch               └─ revision + expiry
   ▼
deny/audit
   │ valid
   ▼
regional gateway ──► cell endpoint ──► tenant-aware service
```

Router cần:

- cache bounded theo revision/TTL;
- negative caching ngắn cho tenant không tồn tại;
- chống client tự chọn `cell_id`;
- dual-read/redirect contract khi migration;
- health-aware route nhưng không chuyển write sang cell khác nếu data chưa sẵn sàng;
- metrics theo cell và result, tránh label tenant không giới hạn.

## 9. Reconciliation thay vì tin provisioning một lần

Provision thành công hôm nay không chứng minh resource còn đúng sau một tháng. Reconciler định kỳ so:

```text
desired tenant state
vs
actual namespace/key/policy/routing/billing integration state
```

Mỗi finding phân loại:

- drift an toàn để tự sửa;
- drift cần approval;
- drift có nguy cơ xóa/mất dữ liệu, chỉ cảnh báo;
- external dependency chưa xác định trạng thái.

Không auto-delete resource lạ chỉ vì không có trong desired state; trước tiên phải xác minh ownership, retention và operation history.

## 10. Suspension không đồng nghĩa deletion

Các mức enforcement có thể khác nhau:

| Trạng thái | Login | Read | Write | Background job | Billing |
|---|---:|---:|---:|---:|---:|
| Active | Có | Có | Có | Có | Bình thường |
| Grace period | Có | Có | Hạn chế | Có chọn lọc | Dunning |
| Suspended | Có thể chỉ admin | Có thể export | Không | Pause/fence | Theo policy |
| Offboarding | Không | Export có kiểm soát | Không | Chỉ cleanup | Finalize |
| Deleted | Không | Không | Không | Không | Chỉ ledger bắt buộc giữ |

Policy phải quyết định rõ API key, session, webhook, scheduled job và message đang nằm trong queue được xử lý thế nào khi transition.

## 11. Offboarding và deletion là workflow có bằng chứng

Một offboarding production:

1. fence write và job mới;
2. revoke session, API key, OAuth grant và connector token;
3. ngừng webhook delivery hoặc chuyển sang terminal event theo contract;
4. tạo export nếu contract yêu cầu;
5. finalize usage/invoice và giữ financial record theo policy;
6. áp retention/legal hold;
7. xóa primary data, cache, search, object, analytics copy và derived artifact;
8. xử lý backup theo crypto-shredding/expiry policy đã công bố;
9. xác minh không còn route/credential active;
10. lưu deletion certificate/evidence không chứa dữ liệu đã xóa.

“Đã xóa row chính” không đủ nếu object storage, search index, lake, log hoặc connector cache vẫn còn dữ liệu tenant.

## 12. Tenant migration giữa cell

```text
PLANNED → COPYING → CATCHING_UP → WRITE_FENCED
        → CUTOVER → VERIFYING → COMPLETED
                         └──────► ROLLBACK/RECONCILE
```

Runbook tối thiểu:

1. check source/target compatibility và headroom;
2. tạo target namespace/key/policy;
3. copy snapshot và checksum business invariant;
4. stream delta với ordered checkpoint;
5. giảm TTL placement trước cutover;
6. fence source writer/background job;
7. catch up tới checkpoint xác định;
8. CAS update placement revision;
9. canary read/write qua ingress thật;
10. giữ source read-only trong rollback window;
11. cleanup sau khi recovery path mới đã được xác minh.

Rollback sau khi target đã nhận write là bài toán data reconciliation, không chỉ đổi router về source.

## 13. Observability và SLO control plane

Theo dõi:

- onboarding success rate và p50/p95 duration;
- step retry/failure theo adapter;
- tuổi operation ở trạng thái non-terminal;
- placement capacity/headroom theo cell;
- routing lookup latency, stale revision và mismatch;
- desired/actual drift;
- suspension enforcement lag;
- offboarding/deletion overdue;
- migration lag, fence duration và verification failure.

Không dùng metric “tenant created” làm success nếu tenant chưa login, gọi API hoặc hoàn thành smoke test.

## 14. Failure modes

| Failure mode | Hậu quả | Guardrail |
|---|---|---|
| Create external resource timeout rồi retry mù | duplicate/orphan | idempotency + read-after-unknown |
| Mở routing trước smoke test | tenant active nhưng unusable | activation gate |
| Placement chỉ theo tenant count | hot cell | weighted capacity/headroom |
| Router tin header tenant/cell | cross-tenant access | derive từ identity + catalog |
| Control plane down kéo data plane down | outage diện rộng | cached last-known-good |
| Suspension chỉ chặn UI | API/job vẫn ghi | centralized enforcement + tests |
| Migration không fence writer | split-brain | single-writer lease/fence |
| Delete không inventory derived data | retention breach | data map + deletion evidence |

## 15. Checklist production

- [ ] Tenant lifecycle là state machine có version và transition authority.
- [ ] Provisioning persist step, retry idempotent và hỗ trợ resume.
- [ ] Catalog là source of truth cho placement; request không tự chọn tenant/cell.
- [ ] Cell có capacity model, safety margin và quy trình thêm cell.
- [ ] Control plane failure không làm data plane đang ổn định dừng ngay.
- [ ] Suspension được enforce trên UI, API, job, queue và credential.
- [ ] Migration có fence, checkpoint, verification và reconciliation plan.
- [ ] Offboarding bao phủ primary, cache, search, object, analytics và backup policy.
- [ ] Có SLO/alert cho operation stuck và deletion overdue.

## 16. Nguồn và học tiếp

- [AWS SaaS Lens – Tenant onboarding](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/tenant-onboarding.html)
- [AWS SaaS Lens](https://docs.aws.amazon.com/wellarchitected/latest/saas-lens/saas-lens.html)
- [Azure – Deployment Stamps pattern](https://learn.microsoft.com/en-us/azure/architecture/patterns/deployment-stamp)
- [Azure – Multitenant architecture](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/overview)
- [Multi-tenancy](multi_tenancy.md)

Học tiếp: [B2B Identity & Authorization](b2b_identity_authorization.md) và [Product Catalog & Entitlements](product_catalog_entitlements.md).

