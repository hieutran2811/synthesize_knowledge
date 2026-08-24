---
title: "Multi-tenancy – thiết kế SaaS phục vụ nhiều tenant an toàn"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "unspecified"
source_count: 5
---
# Multi-tenancy – thiết kế SaaS phục vụ nhiều tenant an toàn

> Thuật ngữ: [Glossary](../glossary.md).

> Multi-tenancy không chỉ là thêm cột `tenant_id`. Đây là quyết định chia sẻ hay
> cô lập ở từng tầng: identity, compute, data, cache, queue, key mã hóa, deployment
> và vận hành. Một lỗi tenant isolation là sự cố bảo mật, không chỉ là bug dữ liệu.

---

## 1. Tenant không đồng nghĩa user

Trong SaaS B2B:

```text
Customer/Organization (tenant)
  ├─ user A: ADMIN
  ├─ user B: MEMBER
  └─ service account C: BILLING_READ
```

Một user có thể thuộc nhiều tenant; một customer có thể cần nhiều tenant cho
production/sandbox hoặc vùng pháp lý khác nhau.

Các định danh:

| ID | Ý nghĩa |
|---|---|
| `user_id`/`subject` | Danh tính người hoặc workload |
| `tenant_id` | Ranh giới dữ liệu, quyền và tính tiền |
| `membership_id` | Quan hệ user–tenant và role |
| `deployment_id`/`stamp_id` | Nơi tenant đang được phục vụ |
| `region` | Ràng buộc residency/latency |

Phải định nghĩa tenant theo mô hình kinh doanh trước khi thiết kế schema. Nếu
“tenant” lúc là công ty, lúc là workspace, authorization sẽ mơ hồ.

---

## 2. Các chiều isolation

Isolation không phải một nút bật/tắt:

| Chiều | Câu hỏi |
|---|---|
| Data | Tenant A có thể đọc/sửa dữ liệu B không? |
| Identity | Credential A có được dùng trong context B không? |
| Compute | A có thể làm cạn CPU/thread của B không? |
| Storage | A có thể dùng hết IOPS/dung lượng của B không? |
| Network | Workload A có kết nối tới workload B không? |
| Encryption | Tenant có key riêng hay dùng key chung? |
| Operations | Restore/export/delete một tenant có độc lập không? |
| Failure | Một deploy/schema/config lỗi ảnh hưởng bao nhiêu tenant? |
| Performance | P99 của tenant nhỏ có bị tenant lớn chi phối? |

Mỗi tầng có thể chọn mức khác nhau. Shared app + database riêng, hoặc shared
database + compute riêng đều có thể hợp lý tùy requirement.

---

## 3. Ba mô hình chính

### 3.1 Silo – tài nguyên riêng theo tenant

```text
Tenant A → App A → DB A
Tenant B → App B → DB B
```

Ưu:

- isolation và blast radius mạnh;
- tùy chỉnh region/SLA/compliance dễ hơn;
- backup/restore theo tenant tự nhiên.

Đánh đổi:

- chi phí và tài nguyên nhàn rỗi;
- fleet deployment/migration lớn;
- quota cloud và control plane phức tạp;
- khó quan sát toàn bộ phiên bản bị lệch.

Phù hợp ít tenant enterprise, hợp đồng dedicated, untrusted workload hoặc yêu cầu
residency/isolation mạnh.

### 3.2 Pool – dùng chung tài nguyên

```text
Tenant A ─┐
Tenant B ─┼─▶ shared app → shared tables (`tenant_id`)
Tenant C ─┘
```

Ưu: density cao, chi phí/tenant thấp, rollout một lần. Đánh đổi: code phải tenant-
aware ở mọi đường; noisy neighbor và blast radius lớn hơn.

### 3.3 Bridge/Hybrid

```text
Shared control plane
  ├─ shared stamp 1: tenant A, B, C
  ├─ shared stamp 2: tenant D, E
  └─ dedicated stamp: enterprise tenant F
```

Đây thường là mô hình phát triển bền: tenant nhỏ dùng pool; tenant lớn hoặc regulated
được chuyển sang dedicated resource. Nhưng cần routing, placement và automation
thống nhất — không duy trì hai sản phẩm khác nhau bằng copy-paste.

---

## 4. Deployment stamp và cell

Không nên cho mọi tenant toàn cầu vào một deployment duy nhất:

```text
Global tenant directory
        │ tenant_id → stamp_id
        ├─▶ Stamp SEA-1: app + cache + DB
        ├─▶ Stamp SEA-2: app + cache + DB
        └─▶ Stamp EU-1 : app + cache + DB
```

Mỗi stamp phục vụ một tập tenant và có giới hạn công suất. Lợi ích:

- scale bằng cách thêm stamp;
- giới hạn blast radius;
- residency/latency theo region;
- canary rollout theo stamp;
- di chuyển “whale tenant” khỏi pool nóng.

Cần control plane quản lý placement, capacity, version và migration. Tenant directory
là dữ liệu quan trọng: cache được nhưng phải có version/TTL và đường phục hồi.

Đọc [Scalability](../fundamentals/scalability.md) mục cell-based architecture.

---

## 5. Control plane và data plane

### Control plane

Quản lý vòng đời:

- tạo/suspend/xóa tenant;
- plan, entitlement và quota;
- mapping tenant → region/stamp/database;
- identity federation, domain và key;
- migration/version;
- billing metadata;
- operator workflow.

### Data plane

Phục vụ request:

- xác định tenant đã được chứng thực;
- route tới stamp/data store;
- enforce authorization/quota;
- xử lý dữ liệu nghiệp vụ.

```text
Admin/automation → Control Plane → Tenant Registry
                                      │
User request → Gateway → Data Plane ──┘ lookup/cache placement
```

Không gọi control plane chậm trên mọi request nếu có thể dùng signed context/cache.
Nhưng cache placement phải xử lý tenant đang migrate hoặc suspend.

---

## 6. Xác định tenant: derive, đừng tin mù

Các tín hiệu có thể có:

- hostname/subdomain;
- access token claim;
- API key đã gắn tenant;
- path/header;
- resource ownership trong database.

`X-Tenant-ID` do client gửi **không phải bằng chứng authorization**:

```text
1. Authenticate credential → subject
2. Resolve requested tenant → canonical tenant_id
3. Verify subject có active membership/scope trong tenant
4. Tạo trusted TenantContext nội bộ
5. Service vẫn kiểm tra quyền trên resource/action
```

Nếu token chứa `tenant_id`, kiểm tra issuer, audience và membership lifecycle. Khi
user chuyển tenant trong UI, nên lấy token/session context phù hợp hoặc server xác
minh membership; không chỉ đổi header.

---

## 7. Tenant context propagation

Context cần qua:

```text
HTTP/gRPC → service → database/cache
                   → event/job → worker
```

Một `TenantContext` nên immutable:

```java
public record TenantContext(
    UUID tenantId,
    UUID subjectId,
    Set<String> roles,
    String deploymentId,
    String correlationId
) {}
```

Nguyên tắc:

- tạo sau authentication + membership check;
- không cho business code tự thay `tenantId`;
- propagate rõ trong method/message, không phụ thuộc hoàn toàn global ThreadLocal;
- nếu dùng ThreadLocal phải `clear()` trong `finally`;
- reactive/coroutine cần context mechanism riêng vì thread có thể đổi;
- background job/event phải mang tenant ID đã được producer tin cậy;
- log/trace có tenant dimension đã kiểm soát, nhưng không tạo metric cardinality vô hạn.

Context mất không được fallback sang “all tenants”.

---

## 8. Authentication khác tenant authorization

Ba kiểm tra độc lập:

```text
Who are you?                  Authentication
Can you enter tenant T?       Membership/tenant access
Can you perform action X
on resource R in tenant T?    Authorization
```

Mọi query theo ID cần xác minh ownership trong cùng predicate:

```sql
SELECT *
FROM orders
WHERE tenant_id = :tenant_id
  AND id = :order_id;
```

Không:

```sql
SELECT * FROM orders WHERE id = :order_id;
-- rồi mới kiểm tra tenant ở application
```

Vì dữ liệu đã được tải/log/cache trước kiểm tra. Với policy che sự tồn tại, trả
`404` cho resource ngoài tenant có thể phù hợp hơn `403`.

---

## 9. Mô hình dữ liệu

| Mô hình | Isolation | Density | Vận hành |
|---|---|---|---|
| Shared table + `tenant_id` | Logic/RLS | Cao | Một schema/migration |
| Schema per tenant | Namespace | Vừa | Nhiều schema/migration |
| Database per tenant | Connection/database | Mạnh hơn | Fleet DB |
| Cluster/account per tenant | Hạ tầng | Rất mạnh | Chi phí/control plane cao |

Không có mô hình “phổ biến nhất” cho mọi SaaS. Chọn theo số tenant, kích thước,
compliance, restore, noisy neighbor và khả năng automation.

---

## 10. Shared table: tenant phải là một phần của key

```sql
CREATE TABLE orders (
  tenant_id uuid NOT NULL,
  order_id uuid NOT NULL,
  external_ref text NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL,
  PRIMARY KEY (tenant_id, order_id),
  UNIQUE (tenant_id, external_ref)
);

CREATE INDEX orders_tenant_created_idx
  ON orders (tenant_id, created_at DESC, order_id DESC);
```

Vì sao composite key:

- unique `external_ref` thường chỉ cần trong một tenant;
- query tenant có index prefix phù hợp;
- foreign key mang tenant scope;
- giảm nguy cơ join chéo tenant.

```sql
CREATE TABLE order_items (
  tenant_id uuid NOT NULL,
  order_id uuid NOT NULL,
  item_id uuid NOT NULL,
  PRIMARY KEY (tenant_id, order_id, item_id),
  FOREIGN KEY (tenant_id, order_id)
    REFERENCES orders (tenant_id, order_id)
);
```

ID UUID toàn cục không thay thế `tenant_id`: isolation và authorization vẫn cần.

---

## 11. PostgreSQL Row-Level Security (RLS)

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders FORCE ROW LEVEL SECURITY;

CREATE POLICY orders_tenant_policy ON orders
USING (
  tenant_id = current_setting('app.tenant_id', true)::uuid
)
WITH CHECK (
  tenant_id = current_setting('app.tenant_id', true)::uuid
);
```

Trong transaction:

```sql
BEGIN;
SELECT set_config('app.tenant_id', :tenant_id, true); -- local transaction
SELECT * FROM orders;
COMMIT;
```

Điểm dễ sai:

- table owner thường có thể bypass RLS nếu không `FORCE`;
- role có `BYPASSRLS` bỏ qua policy;
- thiếu policy mặc định là deny khi RLS bật, nhưng phải test;
- chỉ `USING` mà thiếu `WITH CHECK` có thể cho ghi sai tenant tùy policy;
- session setting rò qua connection pool nếu đặt session-wide;
- migration/admin/backup cần role và quy trình riêng;
- RLS không bảo vệ cache, search index, object storage hoặc log.

Dùng transaction-local setting và reset/rollback connection trước khi trả pool.
RLS là defense-in-depth, không thay authorization nghiệp vụ.

---

## 12. Schema-per-tenant và database-per-tenant

### Schema per tenant

Ưu: namespace và restore/migration có thể tách hơn shared table. Nhược:

- số schema/object lớn làm catalog và migration nặng;
- `search_path` sai có thể truy cập nhầm;
- connection pool/prepared statement cần cẩn thận;
- cross-tenant analytics phức tạp.

Không ghép tên schema trực tiếp từ input:

```text
tenant slug → validated registry → immutable physical schema name
```

Identifier SQL không parameterize như value; dùng allowlist/quoting và mapping do
server quản lý.

### Database per tenant

Ưu: isolation, backup/restore, noisy neighbor và encryption key có thể tốt hơn.
Nhược:

- nhiều connection pool và giới hạn kết nối;
- rollout schema theo fleet;
- tenant nhỏ gây resource waste;
- query toàn fleet cần data pipeline riêng.

Connection manager phải có pool budget; không tạo pool lớn cho hàng nghìn tenant ít
hoạt động.

---

## 13. Cache phải tenant-aware

```text
❌ order:123
✅ tenant:{tenantId}:order:{orderId}:v3
```

Mọi thành phần key:

- tenant;
- resource/version;
- authorization-sensitive variant nếu cần;
- locale/feature/config ảnh hưởng representation.

Failure modes:

| Lỗi | Hậu quả |
|---|---|
| Thiếu tenant trong key | Rò dữ liệu chéo tenant |
| Cache negative không scope | B tenant thấy 404 của A |
| Shared CDN cache key thiếu auth/host | Rò response |
| Flush một tenant bằng `KEYS` | Block/cache-wide impact |
| Tenant lớn chiếm hết memory | Evict dữ liệu tenant nhỏ |

Áp quota/key namespace và theo dõi eviction/hit theo tier/stamp. Không dùng raw
tenant ID có cardinality cực lớn làm label metric.

Đọc [Caching](../fundamentals/caching.md).

---

## 14. Search, object storage và analytics

### Search

- document luôn có trusted `tenant_id`;
- filter tenant được inject phía server, client không được bỏ;
- alias/index-per-tenant chỉ khi scale/isolation cần;
- test query, suggest, aggregation và export — không chỉ search chính.

### Object storage

```text
bucket/shared/tenants/{tenant_id}/objects/{object_id}
```

Path prefix không tự là authorization. Signed URL phải scope đúng object, TTL ngắn
và không cho client tự ghép key. Tenant regulated có thể dùng bucket/account/key riêng.

### Analytics

Sao chép sang warehouse vẫn phải giữ tenant lineage, row policy và purpose. Data
đã xóa khỏi OLTP nhưng còn trong lake/backup là chưa hoàn tất offboarding.

---

## 15. Messaging và background job

Envelope:

```json
{
  "eventId": "evt-789",
  "tenantId": "tenant-123",
  "type": "OrderPlaced",
  "subject": "orders/ord-7",
  "data": {}
}
```

Quy tắc:

- producer derive tenant từ trusted context/data owner;
- consumer không lấy tenant từ payload domain không tin cậy rồi query;
- idempotency key scope theo `consumer + tenant + event`;
- DLQ/replay giữ tenant metadata và authorization;
- queue chung cần per-tenant fairness/concurrency;
- queue riêng mỗi tenant tăng isolation nhưng khó vận hành ở cardinality lớn;
- scheduled job phải enumerate tenant có checkpoint, không load tất cả đồng thời.

Noisy neighbor thường xuất hiện trong worker/queue trước cả HTTP API.

---

## 16. Noisy neighbor và fairness

Một tenant có thể làm cạn:

- request concurrency/thread;
- database connection/IOPS;
- cache memory;
- broker partition/consumer;
- search query CPU;
- export worker;
- third-party quota;
- log volume và chi phí.

Phòng vệ nhiều tầng:

```text
Global safety limit
  └─ plan/tenant rate + concurrency
       └─ operation cost limit
            └─ downstream pool/bulkhead
```

Không chỉ rate-limit request count: export 10 năm khác `GET /orders/1`.
Dùng weighted cost, queue riêng theo workload, fair scheduling và per-tenant budget.

Đọc [Rate Limiting](rate_limiting.md) và
[Availability & Reliability](../fundamentals/availability_reliability.md).

---

## 17. Tenant placement và di chuyển

Tenant registry:

```text
tenant_id → stamp_id, database_id, region, state, placement_version
```

Migration online:

```text
ACTIVE_SOURCE
  → COPYING_SNAPSHOT
  → CATCHING_UP_CHANGES
  → QUIESCE/DUAL-READ VALIDATE
  → SWITCH_ROUTING(version++)
  → SOURCE_READ_ONLY
  → CLEANUP sau retention
```

Cần:

- idempotent orchestration;
- checksum/count/sample validation;
- write ordering/CDC;
- routing cache invalidation bằng version;
- rollback trước điểm cleanup;
- audit và customer communication;
- không dual-write vô thời hạn.

Di chuyển tenant là distributed workflow; xem
[Distributed Transactions](../advanced/distributed_transactions.md).

---

## 18. Encryption và key management

Các mức:

| Mức | Isolation | Chi phí |
|---|---|---|
| Một platform key | Thấp hơn | Đơn giản |
| Key theo stamp/region | Giới hạn blast radius | Vừa |
| Envelope key theo tenant | Crypto isolation tốt | Rotation/lookup phức tạp |
| Customer-managed key | Enterprise/compliance | Availability và support cao |

Envelope encryption:

```text
tenant DEK encrypt data
DEK được KEK/KMS key mã hóa
```

Cần key ID/version bên metadata, rotation, revoke, backup/restore và behavior khi
KMS lỗi. “Xóa key để xóa dữ liệu” chỉ đúng nếu không còn plaintext/cache/backup và
policy pháp lý chấp nhận.

---

## 19. Data residency, backup và restore

Residency là placement invariant:

```text
tenant.region = EU
→ primary, replica, backup, search, analytics, log liên quan phải theo policy
```

Backup shared database dễ tạo vấn đề: restore một tenant không thể restore cả DB
production. Pattern:

1. Restore backup vào environment cô lập.
2. Export row/object của tenant với kiểm tra referential integrity.
3. Validate và merge qua controlled workflow.
4. Audit mọi truy cập.

RPO/RTO enterprise có thể buộc database/stamp riêng. Test restore theo tenant, không
chỉ test backup tồn tại.

---

## 20. Cấu hình và tùy biến

Ưu tiên configuration thay code fork:

```text
platform defaults
  → plan defaults
    → tenant overrides
      → user preferences
```

Mỗi config có:

- schema/type;
- owner và default;
- version/audit;
- validation;
- rollout/rollback;
- cache invalidation;
- giới hạn override.

Không cho tenant tùy biến tùy ý SQL/template/code trong process chung. Untrusted
code cần sandbox mạnh hoặc dedicated compute.

Feature flag theo tenant đọc ở [Feature Flags](feature_flags.md).

---

## 21. Onboarding

State machine:

```text
REQUESTED
 → IDENTITY_READY
 → RESOURCES_PROVISIONING
 → SCHEMA_MIGRATED
 → ADMIN_INVITED
 → ACTIVE
```

Workflow phải:

- idempotent theo onboarding request;
- reserve canonical tenant ID/slug;
- chọn plan/region/stamp theo capacity;
- tạo key/schema/database/bucket/config;
- chạy migration và seed;
- thiết lập identity/domain;
- không đánh dấu `ACTIVE` trước khi readiness check đạt;
- compensation/cleanup resource nếu fail;
- có manual review cho domain/compliance.

Không xử lý onboarding dài trong một HTTP transaction; trả operation ID.

---

## 22. Suspension và offboarding

Phân biệt:

- **suspend access**: ngừng login/write nhưng giữ dữ liệu;
- **cancel subscription**: theo retention;
- **legal hold**: không xóa dù người dùng yêu cầu;
- **erase tenant**: xóa theo policy;
- **export**: bàn giao dữ liệu có authorization.

Offboarding:

```text
ACTIVE → SUSPENDED → EXPORTING → DELETION_PENDING
       → DELETING → VERIFIED_DELETED
```

Inventory cần bao phủ:

- primary/replica;
- cache/search;
- object/file;
- broker/outbox/DLQ;
- analytics/ML feature;
- log/trace;
- backup;
- secret/key và third-party integration.

Xóa nên có tombstone tối thiểu để tránh tenant ID cũ được tái sử dụng nhầm. Ghi bằng
chứng xóa nhưng không lưu lại dữ liệu vừa xóa.

---

## 23. Schema migration trong fleet

Với shared DB: một migration có blast radius mọi tenant. Với database-per-tenant:
fleet có thể lệch version.

Pattern:

- expand → migrate/backfill → contract;
- backward-compatible app trong suốt rollout;
- canary stamp/tenant không chứa dữ liệu nhạy cảm đặc biệt;
- rate-limit migration để không chiếm IOPS;
- checkpoint/resume;
- registry lưu schema version;
- dashboard số tenant pending/failed;
- không chạy hàng nghìn migration đồng thời;
- rollback application không phụ thuộc rollback DDL.

Migration tenant-specific phải dùng cùng artifact chuẩn, tránh sửa tay tạo snowflake.

---

## 24. Observability và cost attribution

Theo dõi:

- latency/error/saturation theo stamp và plan;
- top tenant theo request, cost unit, storage, queue lag;
- fairness và throttling;
- tenant placement/schema/config version;
- isolation denial và cross-tenant access attempt;
- onboarding/migration/offboarding state;
- unit economics: compute/storage/egress/third-party.

Không đưa `tenant_id` vào mọi metric label nếu có hàng triệu tenant. Dùng:

- bounded dimension: plan, region, stamp;
- logs/traces cho tenant cụ thể;
- top-K/heavy hitter;
- usage pipeline có cardinality được quản lý.

Đọc [SaaS Observability](observability_saas.md) khi chủ đề đó được chuẩn hóa.

---

## 25. Kiểm thử tenant isolation

Test matrix tối thiểu:

| Test | Mong đợi |
|---|---|
| User A đọc ID của B | 404/403, không có dữ liệu trong log/cache |
| User thuộc A và B đổi context | Chỉ quyền của tenant đang chọn |
| Request thiếu tenant context | Deny, không fallback global |
| Connection pool tái sử dụng | RLS context không rò |
| Cache cùng resource ID ở A/B | Hai entry tách biệt |
| Search/export/aggregation | Filter tenant bắt buộc |
| Event giả `tenantId` | Consumer reject/derive trusted owner |
| Admin/support impersonation | Approval + audit + thời hạn |
| Backup restore một tenant | Không ghi đè tenant khác |
| Tenant lớn gây tải | Tenant nhỏ vẫn đạt SLO |

Thêm static analysis/query wrapper không đủ; cần integration/security test với ít
nhất hai tenant và ID trùng nhau có chủ đích.

---

## 26. Kubernetes multi-tenancy

Namespace là ranh giới quản lý hữu ích nhưng **không tự tạo hard isolation**.
Cần phối hợp:

- RBAC/service account;
- NetworkPolicy và CNI thực sự enforce;
- ResourceQuota/LimitRange;
- Pod Security;
- secret/service account tách;
- node pool/sandbox cho untrusted workload;
- admission policy;
- cluster-scoped resource/webhook governance.

Tenant không tin nhau hoặc chạy code tùy ý có thể cần virtual control plane,
dedicated cluster/node/hardware. Container chia sẻ kernel nên requirement phải quyết
định isolation boundary.

---

## 27. Ví dụ kiến trúc SaaS B2B

```text
                         ┌─ Tenant Registry / Control Plane
User → Gateway/Auth ─────┤
                         └─ trusted tenant context
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
              Shared Stamp SEA-1          Dedicated Stamp EU-1
              tenant A/B/C                tenant Enterprise-X
              app/cache/DB                app/cache/DB/key riêng
                    │
              usage + audit pipeline
```

Request order:

1. Gateway authenticate user.
2. Membership service xác nhận user thuộc tenant.
3. Registry/cache resolve stamp.
4. App tạo immutable tenant context.
5. RLS/query/cache/search đều scope tenant.
6. Rate limiter enforce global + tenant + operation budget.
7. Audit ghi actor, tenant, action và outcome.

---

## 28. Failure modes thường gặp

| Sự cố | Hậu quả | Phòng vệ |
|---|---|---|
| Tin `X-Tenant-ID` | Truy cập tenant khác | Derive + membership check |
| Unique key không có tenant | Tenant B không tạo được ref giống A | Composite unique |
| RLS setting session-wide | Connection pool rò context | Transaction-local + reset |
| Table owner bypass RLS | Query admin vô tình thấy tất cả | Role tách + FORCE + test |
| Cache/search thiếu tenant | Data leak | Tenant bắt buộc trong key/filter |
| Một shared deployment toàn cầu | Blast radius/noisy neighbor | Stamps/cells |
| Pool riêng mỗi tenant không budget | Cạn DB connection | Lazy/bounded pool/proxy |
| Queue chung không fairness | Tenant lớn làm trễ tenant nhỏ | Per-tenant concurrency/fair queue |
| Config code fork | Không thể rollout/patch đồng đều | Versioned configuration |
| Xóa chỉ OLTP | Dữ liệu còn ở lake/DLQ/backup | Data inventory + deletion workflow |
| Metric label mỗi tenant | Cardinality/cost bùng nổ | Stamp/plan + top-K + logs |

---

## 29. Decision checklist

- [ ] Tenant, user, membership và environment được định nghĩa rõ.
- [ ] Isolation requirement được đánh giá riêng cho từng tầng.
- [ ] Silo/pool/bridge gắn với pricing, compliance và automation.
- [ ] Có tenant registry và placement/version rõ.
- [ ] Tenant context được derive từ credential/membership tin cậy.
- [ ] Mọi key, unique constraint, FK, cache, search và event đều tenant-scoped.
- [ ] RLS role/policy/connection-pool behavior đã được kiểm thử.
- [ ] Có rate/concurrency/cost budget chống noisy neighbor.
- [ ] Backup/restore/export/xóa được thực hiện theo tenant.
- [ ] Encryption/residency policy bao phủ replica, log, analytics và backup.
- [ ] Onboarding/migration/offboarding là workflow idempotent.
- [ ] Fleet migration có version, canary, checkpoint và capacity control.
- [ ] Isolation test dùng hai tenant với ID trùng có chủ đích.
- [ ] Operator/support access có approval, expiry và audit.

---

## 30. Câu hỏi phỏng vấn thường gặp

1. Tenant khác user như thế nào?
2. Silo, pool và bridge đánh đổi gì?
3. Vì sao cột `tenant_id` chưa đủ isolation?
4. Tenant ID từ header/token được tin ở mức nào?
5. PostgreSQL RLS có thể bị bypass bằng cách nào?
6. Connection pool làm rò tenant context ra sao?
7. Vì sao unique/FK/index nên chứa `tenant_id`?
8. Cache và search gây cross-tenant leak thế nào?
9. Bạn bảo vệ tenant nhỏ khỏi noisy neighbor ra sao?
10. Di chuyển tenant giữa hai stamp mà không mất write thế nào?
11. Restore một tenant trong shared DB ra sao?
12. Namespace Kubernetes có phải security boundary hoàn chỉnh không?

---

## 31. Nguồn và chủ đề tiếp theo

Nguồn tham khảo chính:

- [Azure Architecture Center – Tenancy models](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/considerations/tenancy-models)
- [Azure Architecture Center – Multitenant architectural approaches](https://learn.microsoft.com/en-us/azure/architecture/guide/multitenant/approaches/overview)
- [AWS – SaaS Tenant Isolation Strategies](https://docs.aws.amazon.com/whitepapers/latest/saas-tenant-isolation-strategies/saas-tenant-isolation-strategies.html)
- [PostgreSQL – Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
- [Kubernetes – Multi-tenancy](https://kubernetes.io/docs/concepts/security/multi-tenancy/)

Đọc tiếp:

- [Control Plane & Tenant Lifecycle](control_plane_tenant_lifecycle.md) – provisioning,
  placement, cell routing, migration, suspension và deletion evidence.
- [B2B Identity & Authorization](b2b_identity_authorization.md) – organization membership,
  SSO, SCIM, resource authorization và support access.
- [Rate Limiting](rate_limiting.md) – fairness, quota và bảo vệ noisy neighbor.
- [Billing & Metering](billing_metering.md) – entitlement, usage và tính tiền.
- [Feature Flags](feature_flags.md) – cấu hình/rollout theo tenant.
- [Databases Design](../fundamentals/databases_design.md) – sharding, migration
  và connection pool.
- [API Design](../advanced/api_design.md) – tenant authorization và idempotency.

---

*Cập nhật lần cuối: 2026-07-31*
