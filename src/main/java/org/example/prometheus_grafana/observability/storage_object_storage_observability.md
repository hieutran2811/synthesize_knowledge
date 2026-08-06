# Storage & Object Storage Observability – Durability, Integrity và Recoverability

> Mục tiêu của bài này là quan sát block, file và object storage từ request đến media:
> dữ liệu có ghi đúng, đọc đúng, đủ bản sao, còn toàn vẹn, hội tụ đúng hạn, phục hồi được và
> không vượt capacity/cost hay không.
>
> Baseline tham chiếu: OpenTelemetry Semantic Conventions 1.43 cho object store, Kubernetes
> CSI/Volume Health hiện hành, Ceph health/scrubbing guidance và các tài liệu S3 consistency,
> checksum, lifecycle/object-lock hiện hành. Object-store conventions và CSI Volume Health
> còn ở trạng thái Development/alpha nên phải pin schema và kiểm tra driver/provider hỗ trợ.
>
> Object key, path, bucket, metadata và access log có thể chứa tenant ID, tên tài liệu, PII
> hoặc secret. Không export raw key/path mặc định; áp dụng hashing/bucketing có kiểm soát,
> encryption, least privilege, retention và audit.
>
> Nên đọc trước:
> [Capacity Planning & Performance Efficiency](capacity_planning_performance_efficiency.md),
> [Cloud Cost & Sustainability](cloud_cost_sustainability_observability.md),
> [Kubernetes Observability](kubernetes_observability.md) và
> [Object Storage system design](../../system_design/case_studies/platform_designs.md).

---

## 1. “Storage còn sống” chưa chứng minh dữ liệu an toàn

Health endpoint xanh nhưng vẫn có thể:

- write được ACK trước khi durable;
- read trả dữ liệu cũ hoặc sai;
- replica/erasure fragment thiếu;
- checksum chưa được scrub;
- key mã hóa không dùng được;
- restore chưa từng thử;
- capacity/rebuild không còn headroom.

Storage observability phải kiểm tra semantics, không chỉ process uptime.

## 2. Block, file và object

| Model | Interface | Rủi ro nổi bật |
|---|---|---|
| Block | sector/volume | latency, queue, path, filesystem |
| File | path/directory | metadata, lock, inode, namespace |
| Object | bucket/key + API | consistency, listing, multipart, lifecycle |

Không áp dụng giả định POSIX như rename/append/lock lên object store nếu API không cam kết.

## 3. Data path end-to-end

```text
application → SDK/client → network/gateway → metadata
            → placement → device/media → replication
            → read/verify/repair
```

Instrument ở boundary đủ để biết thời gian nằm ở client retry, queue, metadata, device hay
rebuild. Provider-managed storage thường chỉ cho một phần signal.

## 4. Identity contract

Identity bounded:

- storage system/provider;
- cluster/account;
- region/zone;
- service/tier/class;
- operation;
- outcome/reason;
- workload/owner.

Bucket, volume, file path và object key có thể cardinality cao/nhạy cảm; giữ trong log/trace
được phân quyền hoặc mapping catalog.

## 5. Sáu mục tiêu

1. **Availability:** operation được phục vụ.
2. **Durability:** dữ liệu đã ACK không bị mất.
3. **Integrity/correctness:** bytes/metadata đúng.
4. **Performance:** latency/throughput trong SLO.
5. **Recoverability:** restore đạt RTO/RPO.
6. **Efficiency:** capacity/cost hợp lý.

Tách dashboard/SLO; một tỷ lệ success không bao phủ cả sáu.

## 6. SLI contract

Mỗi SLI nêu:

- operation/population;
- good event;
- measurement point;
- window;
- consistency/durability level;
- exclusions;
- coverage;
- source freshness.

Ví dụ `PUT 2xx` chỉ là availability SLI nếu chưa chứng minh checksum và durability.

## 7. Availability semantics

Tách read, write, list, metadata, delete, restore và admin API. `HEAD` thành công không chứng
minh object body đọc được; bucket list thành công không chứng minh key cụ thể tồn tại.

Synthetic probe nên PUT object ngẫu nhiên → GET/verify → LIST/HEAD khi cần → DELETE, trong
bucket riêng và có lifecycle cleanup.

## 8. Durability

Durability hỏi dữ liệu đã được chấp nhận có còn sau device/node/zone failure và theo thời gian.
Khó đo trực tiếp bằng request metric; dùng evidence:

- replication/erasure health;
- acknowledged write policy;
- missing/lost object;
- scrub/repair;
- restore test;
- failure-domain placement;
- audit configuration.

## 9. Integrity

Integrity gồm bytes, ordering, length, metadata và object/version identity. Ghi checksum
algorithm/type, verification point, mismatch, corruption/repair và coverage.

Checksum truyền tải không thay periodic at-rest scrub; cả hai phát hiện failure khác nhau.

## 10. Consistency

Định nghĩa per operation:

- read-after-write;
- overwrite;
- delete;
- listing;
- metadata/tag/ACL;
- cross-region replica;
- cache/CDN.

Không dùng câu “object storage eventually consistent” cho mọi provider/API; kiểm tra contract
hiện hành. S3 hiện công bố strong read-after-write cho PUT/DELETE và các read/list liên quan.

## 11. ACK semantics

ACK có thể nghĩa:

- vào client buffer;
- gateway nhận;
- journal/WAL durable;
- đủ replica/fragment;
- geo replica hoàn tất.

Client và server metric phải biết mức nào. Đổi quorum/write concern là change rủi ro cao và
phải correlate với latency/durability.

## 12. Latency

Histogram theo operation, size class, storage class, region và outcome. Phân rã:

```text
DNS/connect/TLS + queue + metadata + media + transfer + retry
```

TTFB và total download latency khác nhau. p99 theo request nhỏ không đại diện object lớn.

## 13. Throughput và IOPS

- block/file: IOPS, bytes/s, read/write mix, block size;
- object: operations/s, bytes/s, part rate;
- application: useful completed bytes/objects.

Throughput cao do retry/copy/rebuild không phải business work. Tách foreground/background.

## 14. Queue và saturation

Signal:

- device/controller queue;
- pending requests;
- metadata queue;
- thread/connection pool;
- throttling;
- object gateway backlog;
- compaction/scrub/rebuild contention.

Latency thường tăng mạnh trước khi capacity byte đầy.

## 15. Capacity

Theo dõi:

- raw, usable, used, reserved;
- provisioned vs consumed;
- inode/object count;
- metadata/journal;
- snapshot/version;
- temporary/rebuild space;
- growth rate;
- fragmentation.

Một số hệ hết metadata/inode trước bytes.

## 16. Safe headroom

Headroom phải chịu:

- growth đến khi thêm capacity;
- một/một nhóm failure;
- rebuild/rebalance;
- compaction;
- snapshot/backup;
- rollout;
- ingestion burst.

Không dùng `100% - used%` làm safe headroom nếu usable capacity giảm khi fault.

## 17. Failure domain

Replica/fragment cần trải qua device, host, rack, zone hoặc region theo threat model. Theo dõi
actual placement và policy, không chỉ replica count.

Ba bản sao trên cùng rack không bảo vệ rack failure. Placement drift cần alert theo risk.

## 18. Replication

Quan sát desired/available/in-sync replica, lag bytes/time, backlog, retry, bandwidth và
quorum. Tách synchronous/asynchronous.

Replica “online” nhưng stale không đóng góp cùng durability/read correctness. Lag SLO dựa
trên RPO.

## 19. Erasure coding

Với `k` data + `m` parity fragment, hệ chịu mất tối đa theo placement/policy, nhưng degraded
read/rebuild tốn CPU/network/I/O.

Theo dõi missing fragment, degraded object, stripe recovery, decode latency và repair backlog.
Không chỉ nhìn usable ratio.

## 20. Degraded và rebuild

Khi fault:

```text
detect → mark degraded → choose source/target
       → copy/reconstruct → verify → healthy
```

Đo time-to-detect, degraded exposure, rebuild throughput/ETA, failed repair và foreground SLO.
Rebuild quá nhanh có thể gây outage workload.

## 21. Rebalance và backfill

Thêm/xóa capacity hoặc đổi placement kích hoạt data movement. Theo dõi planned/moved/remaining
bytes/objects, throttling, skew và error.

Thay đổi đồng thời nhiều node làm tăng blast radius; đặt concurrency/rate bound và abort theo
customer SLI.

## 22. Scrubbing

Scrub so metadata/checksum/replica để phát hiện corruption ẩn; deep scrub đọc nhiều hơn và tốn
I/O. Theo dõi:

- last scrub/deep scrub;
- overdue count/age;
- scanned bytes/objects;
- mismatch;
- repaired/unrepairable;
- duration/resource.

Ceph phát health check khi PG quá hạn scrub/deep scrub.

## 23. Bit rot và checksum

Checksum algorithm/type có semantics khác, nhất là multipart/composite. Không giả định ETag
luôn là MD5 của toàn object.

Verify ở upload, download và at-rest sample/batch. Giữ trusted checksum/version bên ngoài vùng
có thể cùng bị corrupt khi cần assurance cao.

## 24. Device health

Block layer theo dõi media error, wear, temperature, power cycle, unsafe shutdown, controller,
path failover và firmware. SMART/vendor counters cần model-aware interpretation.

Predictive signal không thay redundancy. Thay device theo risk và kiểm tra rebuild headroom.

## 25. Block storage

Quan sát attach/detach, path/multipath, latency/IOPS/throughput, queue, error, discard, capacity,
snapshot và filesystem phía trên.

Volume “available” ở provider nhưng mount read-only hoặc filesystem corrupt vẫn làm application
fail; synthetic read/write qua mount mới kiểm tra end-to-end.

## 26. File storage

Ngoài bytes còn có inode, directory/metadata latency, lock, open file, cache, delegation,
permission và namespace operation.

Small-file storm có thể nghẽn metadata dù throughput byte thấp. NFS cần quan sát RPC/retransmit/
server và mount semantics.

## 27. Object storage

Object thường immutable theo API design; update là ghi object/version mới. Theo dõi PUT/GET/
HEAD/LIST/DELETE/COPY, byte range, multipart, tag/ACL, version và lifecycle.

Tách data-plane request khỏi control-plane bucket/policy operation.

## 28. Operation contract

Event/trace operation cần:

- provider/system;
- operation;
- bucket/container class;
- object size class;
- storage class;
- region;
- outcome/error type;
- retry/attempt;
- checksum verification.

Không đưa raw key hoặc presigned URL chứa credential vào telemetry.

## 29. OpenTelemetry object-store conventions

OpenTelemetry 1.43 có semantic conventions cho object-store operation và AWS S3 client span,
nhưng status hiện là Development.

Pin version, review attribute cardinality/privacy và có migration plan. Auto-instrumentation
không thay server/storage health metrics.

## 30. Cardinality

Nguồn nổ series:

- bucket/volume/object/key/path;
- request/upload/version ID;
- checksum;
- user/tenant;
- error message;
- arbitrary storage class/tag.

Metric dùng dimension bounded; chi tiết ở sampled trace/log/event với access/retention phù hợp.

## 31. Provider consistency contract

S3-compatible không đảm bảo giống S3 ở mọi operation. Kiểm tra:

- overwrite/list/delete;
- multipart;
- conditional request;
- versioning;
- locking;
- replication;
- error code;
- checksum;
- range read.

Viết contract test khi đổi provider/gateway/version.

## 32. Multipart upload

Theo dõi initiated/completed/aborted, active age, parts, retries, bytes, checksum type và orphan
part storage.

Complete thành công mới tạo logical object theo API; từng part thành công chưa đủ. Lifecycle
abort stale multipart và cảnh báo backlog.

## 33. Large và hot object

Object lớn cần range/parallel transfer, resumability và checksum; object hot cần CDN/cache/
request spreading. Theo dõi TTFB, transfer rate, range error và origin amplification.

Object store không tự giải quyết edge delivery. CDN miss/revalidation có thể tạo thundering herd.

## 34. Small-object workload

Nhiều object nhỏ làm metadata/request cost lớn hơn byte cost. Theo dõi operations/object,
average size distribution, listing, compact/pack trade-off và delete lifecycle.

Gộp object giảm request nhưng tăng read amplification và blast radius; benchmark.

## 35. Metadata và listing

LIST theo prefix có pagination, latency và cost; inventory lớn nên dùng manifest/catalog/batch
inventory nếu provider hỗ trợ.

Đừng scan toàn bucket liên tục để monitor. Theo dõi continuation/pagination, missing/duplicate
entry và catalog freshness.

## 36. Versioning và delete marker

Versioning hỗ trợ recovery nhưng tăng bytes/object count và có semantics delete marker. Theo
dõi current/non-current versions, marker, expired version, restore và lifecycle effect.

“Delete thành công” có thể chỉ thêm marker chứ chưa xóa vật lý hoặc đáp ứng deletion policy.

## 37. Lifecycle và tiering

State:

```text
hot → cool → archive → expired/deleted
```

Theo dõi eligible/transitioned/failed, age, retrieval latency/cost, minimum-duration charge và
restore status. Policy đổi cần simulation trên inventory.

## 38. Retention và Object Lock

Retention/Object Lock/WORM bảo vệ khỏi sửa/xóa trong window nhưng cần governance vs compliance
mode, legal hold và privileged bypass.

Theo dõi protected coverage, expiry, policy change, bypass attempt và restore. Immutable
malware/corrupt data vẫn là dữ liệu xấu; cần clean recovery point.

## 39. Encryption và key

Phân biệt provider-managed, customer-managed và client-side encryption. Theo dõi key version,
encrypt/decrypt error, KMS latency/quota, rotation, disabled/expired key và policy.

Không log key material/presigned URL. Backup không restore được nếu key mất.

## 40. Access và audit

Audit read/write/delete/list/policy/replication/retention/key action với actor, scope, source,
outcome và reason.

Phát hiện public access, unusual bulk read/delete, policy weakening và cross-tenant access.
Data-plane access log volume lớn cần sampling/aggregation nhưng security-critical event giữ đủ.

## 41. Cross-region replication

Đo eligible, pending, replicated, failed bytes/objects, replication time, delete/version
semantics và destination health.

Replication không tự là backup: deletion/corruption/credential compromise có thể lan. RPO/RTO
và failover/failback cần thử riêng.

## 42. Event notification

Object-created/deleted event có thể duplicate, delayed hoặc out-of-order tùy contract. Consumer
cần idempotency, object version và reconciliation.

Theo dõi publish/delivery lag, retry/DLQ, invalid event và event-vs-inventory gap. Notification
không thay source-of-truth scan/reconciliation.

## 43. CDN và cache

Đo hit/miss, origin bytes/requests, fill latency/error, eviction, stale serve, invalidation và
regional coverage.

Cache làm giảm origin load nhưng có thể trả stale/wrong authorization. Key phải gồm tenant/
variant cần thiết mà không lộ PII.

## 44. Backup không tự là DR

Backup tồn tại chưa chứng minh:

- complete;
- consistent;
- không corrupt;
- key/credential còn;
- catalog tìm được;
- environment đích có capacity;
- application chạy đúng sau restore.

DR là khả năng phục hồi dịch vụ trong RTO/RPO đã thử.

## 45. Restore observability

State:

```text
requested → located → authorized → transferred
          → verified → mounted/imported → application validated
```

Đo queue, restore bytes/rate/ETA, error, checksum, dependency, manual wait và business
verification. `restore job succeeded` chưa đủ.

## 46. Ransomware và destructive action

Defense:

- least privilege;
- separate backup identity/account;
- versioning/immutability;
- MFA/approval khi phù hợp;
- delete anomaly;
- clean recovery point;
- offline/logically isolated copy;
- restore drill.

Audit plane phải khó bị attacker xóa cùng dữ liệu.

## 47. Kubernetes CSI/PV

Theo dõi StorageClass/CSI driver, PV/PVC phase, provision/attach/mount/resize/snapshot, capacity,
topology và Pod-visible I/O.

PVC Bound không chứng minh volume healthy hoặc application đọc/ghi được. Correlate Kubernetes
Events, CSI logs, node/device và workload.

## 48. CSI Volume Health

Kubernetes Volume Health Monitoring hiện alpha. Khi CSI driver/controller/node hỗ trợ, abnormal
condition có thể xuất hiện qua PVC/Pod Events và kubelet volume stats metric.

Không mặc định metric có ở mọi cluster. Kiểm tra feature gate, driver capability và event
retention.

## 49. Snapshot và clone

Theo dõi request, ready time, size/incremental bytes, consistency method, parent dependency,
retention và restore test.

Crash-consistent không tự application-consistent. Cần quiesce/checkpoint cho database tùy
contract.

## 50. Database storage

Database có WAL/journal, data, temp, index, backup và replication với I/O profile khác nhau.
Storage p99 xấu có thể tạo lock/commit/replication lag.

Correlate fsync, checkpoint, cache hit, queue, device và query. Không tối ưu volume mà bỏ
durability setting.

## 51. Observability backend storage

Prometheus/Mimir/Loki/Tempo/Pyroscope dùng local disk, WAL, Kafka hoặc object store khác nhau.
Theo dõi ingest durable point, upload lag, block integrity, compaction, query read và retention.

Object store reachable không chứng minh recent telemetry đã upload/query được.

## 52. Data lake/lakehouse

Ngoài object còn catalog/table metadata, manifest, partition, commit protocol và compaction.
Theo dõi data freshness/completeness, orphan file, small file, snapshot age, schema và
catalog-object consistency.

Query engine success trên dữ liệu stale vẫn là data incident.

## 53. S3-compatible không đồng nghĩa giống hệt

Kiểm tra endpoint addressing, signature/auth, checksum, multipart, conditional request,
versioning, consistency, object lock, lifecycle, error/retry và limits.

Pin implementation/version; test bằng SDK thực của workload. “API chạy được” chưa đủ semantic
compatibility.

## 54. Capacity forecast

```text
forecast used =
  current + ingest - lifecycle delete - compaction saving
  + replica/rebuild overhead
```

Dùng growth theo bytes lẫn object/inode/metadata. Tính lead time mua/provision/rebalance và
failure headroom.

## 55. Cost

Phân rã:

- provisioned capacity;
- stored byte-month;
- operation/request;
- retrieval;
- egress/inter-region;
- replication;
- snapshot/version;
- minimum duration/early delete;
- compute for scrub/rebuild.

Tối ưu class/lifecycle phải giữ restore SLO và access pattern.

## 56. Metrics, traces, logs và events

- metrics: aggregate rate/latency/capacity/health;
- traces: client operation và retry path;
- logs: error/repair/audit detail;
- events: lifecycle/placement/state transition;
- synthetic: semantic read/write/restore.

Correlation dùng operation/change ID; không đưa object key vào metric.

## 57. Dashboard

Các tầng:

1. customer SLI;
2. durability/integrity;
3. degraded/rebuild/scrub;
4. performance/saturation;
5. capacity/headroom;
6. replication/backup/restore;
7. security/access;
8. cost/lifecycle.

Overlay maintenance, device failure và policy change.

## 58. Alerting

Page khi:

- lost/unfound/corrupt data;
- write/read SLO burn;
- degraded vượt failure tolerance;
- rebuild không kịp;
- capacity below failure headroom;
- replication lag vượt RPO;
- key/access/retention critical failure;
- restore drill/customer restore fail.

Ticket cho lifecycle/cost/scrub trend còn đủ thời gian.

## 59. Incident workflow

1. bảo vệ dữ liệu và dừng destructive automation;
2. xác định scope/version/failure domain;
3. kiểm tra read/write/integrity;
4. quyết định repair/failover/restore;
5. throttle background/foreground hợp lý;
6. verify bytes/application;
7. lưu evidence;
8. reconcile và khôi phục redundancy.

Không xóa “bản lỗi” trước khi biết nó có phải bản mới nhất duy nhất.

## 60. Chaos và failure test

Thử trong phạm vi kiểm soát:

- mất device/node/zone;
- slow I/O;
- checksum mismatch;
- KMS unavailable;
- network partition;
- replication lag;
- capacity gần full;
- stale multipart;
- delete/restore;
- scrub/rebuild cạnh foreground load.

Xác minh alert, throttle, RTO/RPO và data correctness.

## 61. Upgrade và maintenance

Rolling upgrade/firmware/filesystem/driver đổi semantics và performance. Theo dõi version skew,
drain/backfill, compatibility, health và workload SLO.

Giới hạn đồng thời theo failure domain. Không upgrade khi đang degraded hoặc thiếu rebuild
headroom nếu không có emergency justification.

## 62. Governance

Catalog cần owner, data class, residency, encryption, retention, replication, checksum, RPO/
RTO, storage class, lifecycle và deletion policy.

Policy-as-code có version/decision/reason; exception có expiry. Review public bucket, object
lock và KMS change như security change.

## 63. Runbook và DR evidence

Runbook gồm:

- triệu chứng và query;
- safe freeze/throttle;
- source-of-truth xác định bản mới;
- rebuild/restore decision;
- key/credential;
- verification;
- communication;
- rollback/failback;
- evidence cần giữ.

DR drill tạo report actual RTO/RPO, missing data và remediation owner.

## 64. Workshop, checklist và câu hỏi tự kiểm tra

Workshop: PUT dataset có checksum, tạo version/snapshot, giả lập mất một failure domain, theo
dõi degraded/rebuild rồi restore sang environment sạch và verify application.

- [ ] ACK durability level rõ?
- [ ] Read/write/list/delete SLI tách?
- [ ] Checksum transit và at-rest scrub?
- [ ] Placement theo failure domain?
- [ ] Rebuild có ETA/headroom/throttle?
- [ ] Object key không nằm trong metric label?
- [ ] Version/lifecycle/delete semantics được test?
- [ ] Backup restore được cùng key/config?
- [ ] Cost gồm request/retrieval/egress?

Câu hỏi:

1. Availability, durability và integrity khác nhau thế nào?
2. Vì sao ETag không luôn là checksum toàn object?
3. Rebuild nhanh quá gây hại gì?
4. Cross-region replication khác backup ra sao?
5. PVC Bound còn thiếu evidence nào?
6. Khi nào capacity byte chưa đầy mà storage đã nghẽn?
7. Restore success cần xác minh ở lớp application thế nào?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Telemetry và storage health

- [OpenTelemetry object-store semantic conventions](https://opentelemetry.io/docs/specs/semconv/object-stores/)
- [Kubernetes Volume Health Monitoring](https://kubernetes.io/docs/concepts/storage/volume-health-monitoring/)
- [Ceph health checks](https://docs.ceph.com/en/latest/rados/operations/health-checks/)

### Object integrity và semantics

- [Amazon S3 consistency model](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html#ConsistencyModel)
- [Amazon S3 object integrity](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity.html)
- [Amazon S3 Object Lock considerations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-managing.html)

Chủ đề tiếp theo:
[Search & Indexing Observability](search_indexing_observability.md) – indexing pipeline,
freshness, shard/segment, query latency, relevance, vector search, capacity và cost.

---

*Cập nhật lần cuối: 2026-07-30*
