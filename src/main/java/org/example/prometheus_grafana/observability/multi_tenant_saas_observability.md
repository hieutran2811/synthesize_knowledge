# Multi-Tenant & SaaS Observability – Isolation, Fairness và Tenant Experience

> Mục tiêu của bài này là quan sát hệ thống phục vụ nhiều tenant mà không biến mỗi tenant
> thành Prometheus label, không làm rò dữ liệu giữa khách hàng và không để một noisy neighbor
> làm suy giảm toàn nền tảng. Bài tập trung vào telemetry architecture; phần thiết kế SaaS
> tổng quát được liên kết ở cuối.
>
> Baseline tham chiếu: Prometheus metric/label guidance, OpenTelemetry Semantic Conventions
> 1.43 và Baggage, Kubernetes multi-tenancy, Grafana Mimir 3.1 multi-tenancy/shuffle sharding
> và FinOps Unit Economics.
>
> Tenant ID là security/privacy-sensitive metadata. Không tin tenant context do client tự khai,
> không dùng telemetry làm authorization source, không cho cross-tenant query mặc định và phải
> audit mọi truy cập/federation/export.
>
> Nên đọc trước:
> [Business & Product Observability](business_product_observability.md),
> [Grafana Mimir](grafana_mimir.md),
> [Telemetry Governance & FinOps](telemetry_governance_finops.md) và
> [SaaS multi-tenancy architecture](../../system_design/saas/multi_tenancy.md).

---

## 1. Tenant không chỉ là một label

Thêm `tenant_id` vào mọi metric nghe đơn giản nhưng số tenant tăng sẽ tạo hàng triệu series,
query chậm và chi phí cao. Nguy hiểm hơn, label có thể xuất hiện trong dashboard hoặc alert
không đúng quyền.

Tenant observability là bài toán identity, isolation, fairness, cost và diagnosis—không phải
chỉ enrichment.

## 2. Định nghĩa tenant trước

Tenant có thể là:

- khách hàng/doanh nghiệp;
- workspace/project;
- đội nội bộ;
- reseller và sub-account;
- workload được cung cấp như dịch vụ.

Một request có thể có account, workspace và user cùng lúc. Chọn `tenant.id` canonical cho
boundary và lưu hierarchy/version riêng.

## 3. Silo, pool và bridge

| Mô hình | Chia sẻ | Quan sát chính |
|---|---|---|
| Silo | ít hoặc không | fleet consistency, cost, version drift |
| Pool | compute/data chung | isolation, fairness, noisy neighbor |
| Bridge | kết hợp | routing đúng model, migration, policy khác nhau |

Telemetry schema chung phải hoạt động ở cả ba để operator không cần ba hệ điều tra riêng.

## 4. Isolation là một phổ

Các chiều độc lập:

- identity/authorization;
- compute;
- network;
- storage/data;
- encryption/key;
- telemetry;
- failure/blast radius;
- operations;
- cost.

“Namespace riêng” không tự chứng minh mọi chiều đã isolate. Ghi rõ threat model và assurance
mong muốn cho từng service tier.

## 5. Tenant identity contract

Contract tối thiểu:

```text
tenant.id          canonical, opaque
tenant.tier        tập bounded
tenant.region      coarse, bounded
tenant.shard       internal routing class
tenant.generation  identity/config version
```

Không dùng company name, domain hay email làm ID. Rename tenant không được phá correlation.

## 6. Derive identity tại trust boundary

Tenant context nên được suy ra từ credential/session đã xác minh tại gateway hoặc service có
thẩm quyền:

```text
credential → authenticated principal → authorized tenant scope
```

Không tin `X-Tenant-ID` từ Internet chỉ vì header tồn tại. Strip header bên ngoài rồi inject
context đã ký/xác minh ở boundary.

## 7. Propagation

Truyền tenant context qua HTTP/RPC, queue message, async job và data pipeline với schema rõ,
size limit và integrity control phù hợp.

Tại mỗi hop:

1. lấy từ trusted context;
2. kiểm tra scope;
3. đặt vào execution context;
4. dùng cho data access;
5. xóa context khi request kết thúc.

Context leak giữa thread/task có thể thành cross-tenant incident.

## 8. Baggage và ranh giới tin cậy

OpenTelemetry Baggage có thể truyền metadata nhưng có thể bị forward tới bên thứ ba và không
có integrity check tích hợp. Chỉ allowlist opaque tenant reference nếu thực sự cần cho
diagnostics.

Không dùng baggage để authorize. Drop/sanitize ở egress và boundary không tin cậy.

## 9. Telemetry identity khác authorization

Span có `tenant.id="A"` chỉ là claim trong telemetry. Quyền đọc dữ liệu tenant A phải đến từ
IAM/policy server-side, không từ filter UI do người dùng chọn.

Mọi query phải được scope trước khi thực thi; post-filter kết quả sau khi backend đã đọc dữ
liệu tenant khác làm tăng rủi ro rò rỉ.

## 10. Multi-tenancy của telemetry plane

Quan sát bốn đường:

```text
write → store → query → alert/notify
```

Isolation phải tồn tại ở cả bốn. Write đúng tenant nhưng query federation mở, hoặc rule đúng
scope nhưng notification chứa dữ liệu tenant khác, vẫn là thất bại.

## 11. Tenant trong Grafana Mimir

Mimir yêu cầu tenant ID qua `X-Scope-OrgID` khi multi-tenancy bật, nhưng authentication và
authorization được đặt ở reverse proxy bên ngoài. Vì vậy:

- proxy xác minh caller;
- derive tenant scope;
- overwrite header;
- chặn bypass trực tiếp;
- audit write/query;
- dùng TLS.

Header không tự là credential.

## 12. Metrics storage isolation

Backend multi-tenant nên có namespace/TSDB logic riêng, quota, retention và encryption policy.
Kiểm tra block/object path, cache key, compaction và deletion không trộn tenant.

Meta-metric của backend có thể chứa tenant dimension; chỉ operator được truy cập và vẫn phải
giới hạn cardinality/retention.

## 13. Logs storage isolation

Log dễ chứa PII/business data hơn metric. Tenant được gán tại trusted ingestion, không parse
từ message tự do.

Áp dụng per-tenant stream/index hoặc authorization filter backend, encryption, retention và
query audit. Test cả saved query, alert preview, export và autocomplete để tránh side channel.

## 14. Trace storage isolation

Trace đi qua nhiều dịch vụ/tenant context có thể phức tạp. Định nghĩa một owning tenant cho
trace và redaction ở boundary; không cho tenant A đọc span chứa dữ liệu tenant B.

Shared dependency trace có thể chỉ hiển thị aggregate hoặc sanitized view cho customer, còn
operator view cần quyền đặc biệt và audit.

## 15. Pool, silo và bridge telemetry

Với silo, mỗi tenant backend riêng cho isolation mạnh nhưng vận hành đắt. Pool tiết kiệm nhưng
policy/query bug có blast radius lớn. Bridge thường:

- aggregate bounded platform metrics ở shared plane;
- chi tiết tenant lớn/regulatory ở isolated plane;
- route theo tenant placement metadata.

Theo dõi routing mismatch như security incident.

## 16. Control plane và data plane

- **Control plane:** onboarding, policy, quota, config, placement, billing.
- **Data plane:** request/job/data thực thi.

Control-plane success chưa chứng minh data plane đã effective. Lưu desired placement/quota
version và observed/effective version trên workload.

## 17. Service tier và SLO contract

Plan/tier có thể khác SLO, support, retention và quota. Dùng enum bounded như `free`, `pro`,
`enterprise`; không encode hợp đồng riêng vào label.

Contract version hóa và effective-dated. Billing plan không nên trực tiếp quyết định runtime
priority nếu chưa qua entitlement/policy đã kiểm tra.

## 18. Per-tenant SLI không gây nổ series

Không cần metric series cho mọi tenant. Kết hợp:

1. global/tier/region metrics liên tục;
2. tenant ID trong sampled trace/log/event;
3. top-K/heavy-hitter telemetry;
4. on-demand diagnostic window;
5. warehouse aggregation theo tenant.

Tenant SLO có thể được tính batch/stream ngoài Prometheus rồi export trạng thái bounded.

## 19. Aggregate theo cohort bounded

Metric online thường label theo:

- tier;
- region;
- workload class;
- isolation model;
- shard;
- outcome/reason class.

Danh mục phải bounded và governance. Tier tổng tốt vẫn có thể che một tenant quan trọng nên
kết hợp heavy-hitter và complaint/synthetic signal.

## 20. Heavy-hitter detection

Phát hiện tenant chiếm CPU, bytes, requests, queue hoặc error bằng streaming top-K/approximate
algorithm ở data pipeline, không giữ series vĩnh viễn cho mọi tenant.

Kết quả có window, rank, estimated value/error và link tới chi tiết được phân quyền. Heavy
usage không tự là abuse; có thể là khách hàng lớn hợp lệ.

## 21. On-demand diagnostics

Khi có ticket/incident, bật capture chi tiết cho tenant:

- có approval/role;
- scope signal/service;
- TTL tự tắt;
- sampling/rate limit;
- redaction;
- cost budget;
- audit actor/reason.

Không để debug mode tồn tại vô hạn hoặc biến tenant ID thành label toàn hệ thống.

## 22. Drill-down qua trace, log và event

Luồng điều tra:

```text
tier/region SLO → affected trace sample
                → tenant-scoped logs/events
                → business transaction
```

UI phải giữ tenant scope xuyên mọi datasource/link. Một link sang Explore bỏ mất scope có thể
trở thành data exposure.

## 23. Cardinality budget

Ước lượng:

```text
series ≈ metrics × bounded dimensions × active combinations
```

Tenant, user, request, invoice và order là unbounded. Prometheus khuyến cáo không dùng label
cho user ID/email hoặc tập lớn tương tự. Theo dõi active series, churn, ingestion và query
latency theo producer.

## 24. Sampling công bằng

Head sampling ngẫu nhiên có thể bỏ gần hết trace của tenant nhỏ và giữ quá nhiều tenant lớn.
Chiến lược:

- baseline probability;
- error/slow retention;
- per-tier floor;
- rate cap cho tenant lớn;
- on-demand override;
- tail-sampling theo policy bounded.

Ghi sampling rate để không suy số tuyệt đối sai.

## 25. Dashboard access control

Dashboard-as-code cần:

- datasource tenant scope server-side;
- folder/team RBAC;
- variable không mở rộng quyền;
- query template allowlist;
- export/snapshot policy;
- audit;
- test impersonation.

Ẩn panel bằng UI không phải authorization. Shared/public dashboard không được chứa tenant data.

## 26. Alert và notification isolation

Rule evaluation chạy trong tenant scope hoặc trên aggregate operator scope rõ ràng. Notification
template chỉ dùng field đã allowlist.

Kiểm tra grouping/dedup không trộn tenant, contact point đúng owner và screenshot/link không
mở dữ liệu ngoài scope.

## 27. Operator view và customer view

Operator cần toàn platform để tìm systemic issue; customer chỉ cần tenant experience. Tách
role, datasource/token, query policy và redaction.

Customer-facing metric nên ổn định, giải thích được và phù hợp SLA; internal debug metric có
thể đổi nhanh nhưng không nên lộ topology hoặc tenant khác.

## 28. Federation

Cross-tenant query hữu ích cho platform capacity và incident, nhưng quyền rất mạnh. Mimir có
tenant federation khi cấu hình bật; coi đây là privileged capability.

Giới hạn caller, tenant set, query cost, result export và audit. Không nhận danh sách tenant
từ input người dùng chưa authorize.

## 29. Query fairness

Một query regex/range lớn có thể làm chậm mọi tenant. Theo dõi:

- queue time;
- scanned series/bytes;
- execution time;
- cancellation/timeout;
- cache;
- concurrency;
- rejected/throttled reason.

Áp dụng scheduler, per-tenant limit và fairness; dashboard auto-refresh cũng là workload.

## 30. Noisy neighbor

Noisy neighbor là tenant làm giảm chất lượng tenant khác qua resource chung. Evidence cần:

```text
aggressor usage ↑ → shared resource saturation ↑
                 → victim SLI ↓
```

Tương quan chưa đủ; thử throttling/sharding có kiểm soát và loại trừ systemic load.

## 31. Resource fairness

Fairness không nhất thiết chia đều. Có thể weighted theo tier/reservation nhưng phải có:

- minimum guarantee;
- burst policy;
- max cap;
- queue discipline;
- overload mode;
- reason/visibility.

Theo dõi offered, admitted, served và throttled load theo bounded class.

## 32. Rate limiting

Đo allowed/rejected, remaining/quota state, decision latency và reason. Distributed rate limit
cần quan sát consistency, backend availability và fallback.

Fail-open tăng rủi ro overload; fail-closed tăng customer denial. Chọn theo operation và ghi
fallback outcome thay vì trả lỗi chung.

## 33. Quota

Quota có thể theo requests, concurrent jobs, storage, tokens, seats hoặc objects. Ghi unit,
window, limit version, used/reserved và reset time.

Phân biệt:

- entitlement;
- safety limit;
- capacity reservation;
- abuse control.

Chúng không nên dùng chung một reason mơ hồ.

## 34. Admission control

Khi overload, reject sớm có kiểm soát tốt hơn nhận rồi timeout. Admission decision dùng
priority/tier/workload class bounded, không tin client tự gán.

Theo dõi admitted/rejected, queue estimate, reason và customer impact; đảm bảo request quản
trị/khôi phục không bị chặn bởi chính overload policy.

## 35. Queue fairness

Queue shared cần tenant-aware scheduling, per-tenant concurrency và max backlog. Theo dõi
oldest age, wait/run time, retry và starvation.

Một tenant gửi nhiều job nhỏ không được chiếm hết slot; một job lớn cũng không nên head-of-line
block mọi tenant. Chọn fair queuing hoặc weighted policy theo contract.

## 36. Database isolation

Quan sát theo model database-per-tenant, schema-per-tenant hoặc shared-table:

- pool saturation;
- query/lock;
- storage;
- replica lag;
- migration;
- row-policy/tenant predicate failure;
- hot partition.

Tenant ID chi tiết nằm trong query event có kiểm soát, không trong mọi DB metric label.

## 37. Cache isolation

Cache key phải namespace theo tenant khi dữ liệu không share. Theo dõi hit/miss, eviction,
memory và hot key theo bounded class/heavy hitter.

Test cross-tenant key collision, invalidation và context leak. Cache hit cao nhưng trả dữ liệu
tenant khác là correctness/security failure nghiêm trọng.

## 38. Messaging isolation

Mô hình topic/queue shared hay per-tenant ảnh hưởng cardinality và operations. Quan sát backlog
age, throughput, retry/DLQ và fairness.

Message phải mang tenant context trusted, schema version và idempotency key. Consumer xác minh
scope trước data access; không dựa vào topic name tự do.

## 39. Storage và object namespace

Bucket/prefix/object ACL, encryption key và lifecycle phải phù hợp tenant placement. Theo dõi:

- denied/cross-scope access;
- bytes/objects;
- request latency/error;
- quota;
- replication/residency;
- orphan;
- deletion progress.

Không log full object path nếu chứa tên khách hàng hoặc dữ liệu nhạy cảm.

## 40. Network isolation

Network policy, service identity, mTLS và egress control giảm cross-tenant reachability. Flow
telemetry giúp phát hiện kết nối ngoài policy nhưng có thể lộ topology.

Theo dõi denied flow, policy version, DNS, bandwidth và connection exhaustion theo namespace/
workload class; tenant-specific chi tiết cần access control.

## 41. Kubernetes Namespace

Kubernetes mô tả namespace là một cơ chế cô lập tài nguyên có scope, nhưng cần RBAC, quota,
network policy và thực hành khác để có isolation đầy đủ.

Theo dõi namespace mapping, policy coverage, resource quota, workload health và object
không namespaced. Namespace riêng không phải security boundary tuyệt đối.

## 42. RBAC

Quan sát allowed/denied authorization, role/binding change, wildcard privilege và service
account use. Audit query phải trả lời ai truy cập tenant nào, action/resource nào và outcome.

Không đặt raw token/credential trong log. Alert privilege expansion và cross-namespace access
bất thường.

## 43. NetworkPolicy

Kubernetes pod traffic mặc định không tự bị cô lập; NetworkPolicy còn phụ thuộc CNI hỗ trợ.
Kiểm tra default-deny, DNS exception, allowed path và effective enforcement.

Policy object tồn tại nhưng dataplane không enforce là false assurance; dùng flow test/canary.

## 44. ResourceQuota và LimitRange

Quota giảm khả năng tenant chiếm toàn namespace/control plane nhưng không bảo vệ mọi resource
như network bandwidth. Theo dõi usage/hard limit, admission rejection và request/limit quality.

Limit quá thấp tạo throttling/OOM; quá cao làm noisy neighbor. Điều chỉnh bằng workload
distribution, không chỉ average.

## 45. Node, virtual control plane và cluster riêng

Khi namespace chưa đủ, có thể dùng node isolation, sandboxed runtime, virtual control plane
hoặc dedicated cluster. Isolation mạnh hơn đổi lấy chi phí và operational complexity.

Telemetry cần thống nhất fleet identity để so health/version, đồng thời giữ data boundary.
Control plane riêng vẫn không tự giải quyết data-plane isolation.

## 46. Data residency

Tenant policy có thể giới hạn nơi lưu/xử lý telemetry. Gắn residency class từ trusted metadata
và enforce tại router/storage, không từ user-supplied label.

Audit region placement, replication, backup, support access và export. Alert khi data route
sang region không cho phép.

## 47. Encryption và key isolation

Mã hóa in transit/at rest là baseline; mức cao hơn dùng key per tenant/group hoặc dedicated
store. Theo dõi key version, rotation, decrypt denial, expiry và KMS dependency.

Không đưa key ID nhạy cảm/cardinality cao vào public metric. Restore phải kiểm tra key còn
khả dụng và đúng residency.

## 48. Access audit

Audit cả application data lẫn telemetry:

- actor/service;
- tenant scope;
- action/query/export;
- reason/ticket;
- time/source;
- outcome;
- privileged federation;
- break-glass expiry.

Log audit cần integrity protection và quyền tách biệt với operator thông thường.

## 49. Phát hiện data leakage

Signal:

- tenant mismatch giữa auth context và resource;
- cross-scope query denied;
- response chứa canary marker tenant khác;
- cache/object namespace mismatch;
- unusual export;
- support impersonation bất thường;
- telemetry routing sai.

Synthetic isolation canary dùng dữ liệu vô hại giúp phát hiện leakage mà không cần đọc nội
dung khách hàng.

## 50. Cost allocation

Phân bổ direct cost khi đo được và shared cost theo driver hợp lý:

```text
tenant_cost =
  direct_compute + storage + egress
  + allocated_shared_platform + observability
```

Driver/version phải minh bạch. Request count đơn thuần có thể sai nếu workload khác CPU, bytes
hoặc retention.

## 51. Unit economics và gross margin

Kết hợp cost với successful value event hoặc revenue:

```text
cost_per_outcome = allocated_cost / successful_outcomes
gross_margin     = (revenue - cost_to_serve) / revenue
```

Không publish per-tenant margin rộng rãi. Kèm reliability và quality để tránh tối ưu bằng
throttling làm mất khách hàng.

## 52. Metering khác observability

Billing meter cần correctness, audit và khả năng replay cao hơn operational metric. Prometheus
counter có thể reset, relabel hoặc bị downsample nên không phải ledger.

Emit immutable usage event vào metering pipeline; observability theo dõi health của pipeline
và reconciliation với invoice/source.

## 53. Entitlement và plan

Entitlement quyết định capability/quota; telemetry chỉ ghi decision và reason bounded. Không
dùng client-provided plan hoặc stale dashboard label để authorize.

Theo dõi plan-change propagation, denied hợp lệ/sai, cache staleness và version compatibility.

## 54. Onboarding

State machine:

```text
requested → identity created → resources provisioned
          → policy/telemetry ready → verified → active
```

SLO đo time-to-ready và correctness. Chỉ active khi data, quota, keys, dashboards/alerts và
synthetic isolation check đều đạt.

## 55. Offboarding và deletion

Inventory dữ liệu tenant qua DB, cache, queue, object store, search, telemetry, backup và
export. Theo dõi deletion request, legal hold, progress, failure và verification.

Xóa control-plane record trước khi data-plane cleanup có thể tạo orphan không còn owner.
Pseudonymized/aggregated retention phải theo policy rõ.

## 56. Tenant migration

Migration giữa shard/region/model cần:

- source/target placement;
- snapshot/version;
- copy/catch-up lag;
- dual-read/write phase;
- validation;
- cutover;
- rollback;
- cleanup.

Theo dõi correctness và request routing; hai bản cùng tồn tại tăng rủi ro stale/cross-scope.

## 57. Custom configuration và flag

Per-tenant override tạo số tổ hợp lớn. Lưu default + override digest/version, owner và expiry;
không dùng từng value làm metric label.

Khi incident, correlate code version, global config và tenant override. Override lâu ngày cần
debt dashboard và compatibility test.

## 58. Release waves

Rollout theo tenant cohort giúp giới hạn blast radius:

```text
internal → canary tenants → low-risk cohort → broad rollout
```

Có consent/contract khi dùng khách hàng làm canary. Guardrail theo aggregate và affected
tenant, xử lý missing data là inconclusive, có stop/rollback.

## 59. Incident và blast radius

Xác định:

- tenant/cohort bị ảnh hưởng;
- shared component/shard;
- journey và transaction;
- data exposure hay chỉ availability;
- start/end;
- workaround;
- contractual impact.

Không đưa tenant name/PII vào public incident channel. Security leakage cần workflow riêng.

## 60. Customer status và support

Status page nên phản ánh customer impact nhưng không tiết lộ tenant khác hoặc topology nhạy
cảm. Customer view có thể hiển thị health tenant-scoped sau authentication.

Support impersonation/break-glass phải time-bound, consent/policy phù hợp và audit. Liên kết
ticket với trace qua opaque reference.

## 61. Backup và disaster recovery

RTO/RPO có thể khác tier, region và data class. Backup catalog cần tenant mapping, encryption
key, residency, retention và restore test.

Thử restore một tenant mà không overwrite tenant khác; kiểm tra application data, config,
entitlement, metering và audit consistency.

## 62. SLO cho SaaS platform

Ba lớp:

1. platform aggregate SLO;
2. tier/region/shard SLO;
3. contractual/per-tenant SLO tính bằng pipeline thích hợp.

Aggregate xanh không bù được tenant đỏ. Đồng thời per-tenant window quá ít traffic cần
synthetic hoặc longer window và uncertainty rõ.

## 63. Kiểm thử isolation và noisy neighbor

Test:

- spoof tenant header/baggage;
- context leak qua thread/queue;
- cross-tenant DB/cache/object access;
- dashboard/query federation;
- notification trộn tenant;
- load tenant lớn ảnh hưởng tenant nhỏ;
- quota/rate-limit fallback;
- telemetry route sai;
- delete/restore một tenant.

Chạy trong môi trường kiểm soát với synthetic tenant/data.

## 64. Workshop, checklist và câu hỏi tự kiểm tra

Workshop: tạo ba synthetic tenant thuộc hai tier; tăng tải một tenant, mở diagnostic có TTL,
kiểm tra victim SLI, throttling, cost allocation và access isolation.

- [ ] Tenant identity được derive tại trusted boundary?
- [ ] Baggage/header không dùng để authorize?
- [ ] Tenant ID không nằm trong metric label không giới hạn?
- [ ] Write/store/query/alert đều isolate?
- [ ] Operator và customer view tách quyền?
- [ ] Fairness có minimum/cap và reason?
- [ ] Metering có ledger riêng?
- [ ] Residency/deletion đi qua cả telemetry?
- [ ] Cross-tenant và noisy-neighbor test tự động?

Câu hỏi:

1. Vì sao `tenant_id` label không scale?
2. Header tenant khác authentication thế nào?
3. Khi nào dùng heavy hitter và on-demand capture?
4. Namespace Kubernetes còn thiếu những lớp isolation nào?
5. Metering event khác Prometheus counter ở đâu?
6. Làm sao chứng minh một noisy neighbor gây ảnh hưởng?
7. Restore một tenant cần kiểm tra những boundary nào?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Multi-tenancy và telemetry

- [Kubernetes multi-tenancy](https://kubernetes.io/docs/concepts/security/multi-tenancy/)
- [Grafana Mimir architecture](https://grafana.com/docs/mimir/latest/get-started/about-grafana-mimir-architecture/)
- [Grafana Mimir HTTP API và tenant header](https://grafana.com/docs/mimir/latest/references/http-api/)
- [Grafana Mimir shuffle sharding](https://grafana.com/docs/mimir/latest/configure/configure-shuffle-sharding/)
- [Prometheus metric and label naming](https://prometheus.io/docs/practices/naming/)
- [OpenTelemetry Baggage](https://opentelemetry.io/docs/concepts/signals/baggage/)

### Kiến trúc SaaS liên quan

- [Multi-tenancy](../../system_design/saas/multi_tenancy.md)
- [Rate limiting](../../system_design/saas/rate_limiting.md)
- [Billing & Metering](../../system_design/saas/billing_metering.md)
- [Feature Flags](../../system_design/saas/feature_flags.md)
- [SaaS Observability overview](../../system_design/saas/observability_saas.md)
- [FinOps Unit Economics](https://www.finops.org/framework/capabilities/unit-economics/)

Chủ đề tiếp theo:
[Cloud Cost & Sustainability Observability](cloud_cost_sustainability_observability.md) –
allocation, unit cost, idle/waste, carbon signals, efficiency guardrails và tối ưu mà không
làm giảm reliability.

---

*Cập nhật lần cuối: 2026-07-30*
