---
title: "Kubernetes Observability Deep Dive – Từ Cluster State đến User Impact"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 14
---
# Kubernetes Observability Deep Dive – Từ Cluster State đến User Impact

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là xây mô hình quan sát Kubernetes theo nhiều lớp: control plane,
> node, runtime, network, workload và application. Kubernetes object “Ready” chỉ là một tín
> hiệu; nó không tự chứng minh dịch vụ đang đáp ứng SLO.
>
> Baseline tham chiếu: tài liệu Kubernetes stable hiện hành, Prometheus Operator,
> kube-state-metrics, Metrics Server và OpenTelemetry Collector. Pin phiên bản theo cluster
> thực tế vì metric, feature gate và stability level thay đổi giữa các release.
>
> Không `exec` tùy tiện vào container, lấy heap dump/core dump, bật audit/verbose logging
> diện rộng, drain node, xóa Pod/PVC hoặc sửa control-plane flag trên production chỉ để điều tra.
>
> Nên đọc trước:
> [Metrics Design](metrics_design.md),
> [Service Discovery](../prometheus/service_discovery.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [eBPF Observability](ebpf_observability.md) và
> [Incident Response](incident_response_observability.md).

---

## 1. Vì sao Kubernetes observability khó?

Một lỗi người dùng có thể đi qua:

```text
DNS → load balancer → ingress/gateway → Service
→ EndpointSlice → Pod → sidecar → application
→ database/cache/external dependency
```

Trong khi đó Kubernetes còn có vòng điều khiển bất đồng bộ:

```text
desired state → API server → controller/scheduler
→ kubelet/runtime/network/storage → observed state
```

Phải quan sát cả data plane lẫn control plane.

---

## 2. Sáu lớp cần nối với nhau

| Lớp | Câu hỏi |
|---|---|
| user/service | người dùng có thành công đúng latency không? |
| workload | replica, rollout, probe và dependency có ổn không? |
| Kubernetes state | desired và current state có hội tụ không? |
| node/runtime | CPU, memory, disk, cgroup, runtime có pressure không? |
| network/storage | packet, DNS, CNI, CSI, volume có lỗi không? |
| control plane | API, scheduler, controller, etcd có điều khiển được không? |

Dashboard theo namespace đơn thuần thường bỏ sót mối quan hệ này.

---

## 3. Bắt đầu từ SLO dịch vụ

SLO nên dựa trên request/job/business outcome, không dựa trên số Pod Ready.

Ví dụ:

```text
checkout availability ≥ 99,95%
checkout p99 ≤ 800 ms
order worker: 99% message hoàn tất dưới 2 phút
```

Kubernetes signals giúp giải thích vi phạm SLO, không thay SLO.

---

## 4. Bốn loại sự thật

Phân biệt:

- **desired state**: spec muốn gì;
- **observed state**: controller báo gì;
- **resource usage**: process/container thực dùng gì;
- **user outcome**: request/job thực sự ra sao.

Ví dụ Deployment muốn 10 replica, status có 10 Available, nhưng mọi request vẫn 500 vì cấu
hình ứng dụng sai. Không loại tín hiệu nào thay được loại còn lại.

---

## 5. Identity model

Một telemetry contract thường cần:

```text
cluster
environment
region
namespace
workload kind/name
pod
container
service
team
```

Không phải signal nào cũng cần mọi label. `pod` hữu ích để debug nhưng có churn cao; SLO và
dashboard dài hạn nên aggregate theo service/workload.

---

## 6. Multi-cluster và multi-tenant

Tên namespace không unique giữa cluster. Luôn có cluster identity ổn định tại ingestion.

Quản trị:

- tenant isolation;
- RBAC/query boundaries;
- per-cluster scrape health;
- global và regional view;
- data residency;
- label collision;
- chargeback/showback.

Không tin label `cluster` do workload tùy ý gửi nếu nó quyết định security boundary.

---

## 7. Kiến trúc signal

```text
components/kubelet/apps
  ├─ metrics → Prometheus/remote storage
  ├─ logs    → node agent/Collector → log backend
  ├─ traces  → OTel Collector → trace backend
  ├─ Events  → API watcher/exporter
  └─ audit   → protected audit backend
```

Mỗi pipeline cần SLO, queue/backpressure, authentication và data-loss detection.

---

## 8. Hai metrics pipeline khác mục đích

Kubernetes có resource metrics pipeline tối thiểu cho autoscaling và `kubectl top`. Hệ thống
monitoring như Prometheus thu thập lịch sử và nhiều metric hơn.

Không dùng một pipeline làm health proxy cho pipeline kia:

```text
Metrics API hỏng → HPA/top có thể hỏng
Prometheus hỏng  → alert/dashboard/history có thể hỏng
```

---

## 9. Metrics Server không phải Prometheus

Metrics Server:

- lấy CPU/memory từ kubelet;
- expose Metrics API;
- phục vụ HPA/VPA và `kubectl top`;
- giữ view ngắn hạn phù hợp autoscaling.

Nó không phải giải pháp monitoring lịch sử, alerting hay phân tích toàn diện. Quan sát chính
Metrics Server vì lỗi của nó có thể làm autoscaler ra quyết định trên dữ liệu thiếu/cũ.

---

## 10. kube-state-metrics

kube-state-metrics chuyển object state từ Kubernetes API thành metrics, ví dụ:

- desired/available replicas;
- Pod phase/conditions;
- resource requests/limits;
- Job/CronJob status;
- PVC state;
- labels/annotations được allowlist.

Nó không đo CPU/memory thực dùng và không chuyển tiếp metric application.

---

## 11. Kubelet và cAdvisor signals

Kubelet expose nhiều endpoint, gồm resource, cAdvisor và probe metrics tùy phiên bản/cấu hình.
Chúng cung cấp container/node usage nhưng cần hiểu:

- cgroup version/runtime;
- working set không đồng nghĩa “memory không thể reclaim”;
- container restart làm series đổi;
- terminated container biến mất;
- scrape kubelet cần TLS/RBAC đúng.

---

## 12. Metric stability

Kubernetes component metrics có stability level và lifecycle. Khi nâng cluster:

- đọc release note;
- inventory metric đang dùng;
- kiểm tra deprecated/hidden metrics;
- chạy rule/dashboard tests;
- canary một cluster;
- theo dõi missing series.

Không buộc alert vào metric alpha mà không có compatibility plan.

---

## 13. API server

Theo dõi:

- request rate theo verb/resource/code;
- latency và inflight requests;
- admission latency/rejection;
- watch count/termination;
- authentication/authorization failure;
- saturation và error;
- request payload bất thường.

Không gắn object name/user tùy ý vào metric nếu làm nổ cardinality hoặc lộ dữ liệu.

---

## 14. Scheduler

Scheduler cần trả lời:

- pending Pod bao nhiêu và bao lâu;
- scheduling attempts/latency;
- unschedulable reason;
- queue depth;
- plugin latency/error;
- node feasibility;
- throughput khi burst.

Pending Pod là triệu chứng; nguyên nhân có thể là resource, affinity, taint, topology, PVC
hoặc quota.

---

## 15. Controller Manager

Quan sát:

- workqueue depth/add/retry;
- queue duration;
- reconcile rate/error;
- leader election;
- controller-specific latency;
- desired/current state gap.

Workqueue tăng kéo dài cho thấy control loop không theo kịp, nhưng phải xác định controller
nào trước khi hành động.

---

## 16. etcd

etcd giữ state của cluster. Theo dõi:

- request latency/error;
- leader changes;
- peer/network round trip;
- database size/quota;
- disk WAL/backend commit latency;
- proposal failed/pending;
- compaction/defragmentation;
- snapshot/restore.

Disk latency của etcd có thể lan thành API và controller latency.

---

## 17. Kubelet

Theo dõi theo node:

- Pod lifecycle operation;
- runtime/image operation latency;
- probe results;
- PLEG/runtime health;
- volume operation;
- certificate expiry/rotation;
- node condition;
- scrape availability.

Kubelet lỗi có thể làm Pod đang chạy nhưng control plane không cập nhật state chính xác.

---

## 18. Container runtime

Cần signal cho:

- create/start/stop container;
- image pull/unpack;
- runtime API latency/error;
- sandbox;
- storage snapshot;
- garbage collection;
- daemon CPU/memory/file descriptors.

`ImagePullBackOff` là biểu hiện; registry, DNS, credential, quota, disk hoặc runtime mới là
nguyên nhân.

---

## 19. kube-proxy, CNI và service networking

Quan sát:

- rule/programming latency;
- endpoint propagation;
- conntrack usage/drop;
- CNI add/delete latency/error;
- packet drop/retransmit;
- policy deny;
- cross-node/zone traffic;
- SNAT/port exhaustion.

Nếu dùng eBPF dataplane, metric và failure mode khác iptables/IPVS; dashboard phải khớp
implementation thực tế.

---

## 20. CoreDNS

Theo dõi:

- query rate;
- response code;
- latency histogram;
- cache hit/miss;
- upstream error/latency;
- reload/panic;
- CPU/memory;
- request theo protocol/type ở cardinality an toàn.

DNS timeout thường biểu hiện như application dependency timeout, vì vậy cần trace/log
correlation theo thời gian và node.

---

## 21. Node health

Một node overview nên có:

- Ready/pressure conditions;
- CPU/memory/ephemeral storage;
- load, steal, throttling;
- disk latency/space/inode;
- network errors;
- container/runtime/kubelet health;
- Pod count;
- allocatable so với requests;
- time sync và certificate.

Aggregate toàn cluster có thể che một node lỗi.

---

## 22. CPU usage, requests và throttling

Ba khái niệm khác nhau:

```text
usage      = CPU thực tiêu thụ
request    = cơ sở scheduling và share
limit      = trần có thể gây throttling
```

CPU usage thấp không loại trừ throttling theo burst ngắn. Correlate throttled periods/time với
application latency, quota và limit.

---

## 23. Memory, OOM và working set

Theo dõi:

- usage/working set/RSS;
- request/limit;
- major page faults;
- container OOM/restart;
- node memory pressure;
- kernel OOM;
- eviction;
- growth theo deploy/version.

`OOMKilled` là sự kiện quá khứ; hiện tại Pod mới có thể trông khỏe. Dùng restart reason và
timeline.

---

## 24. Ephemeral storage và inode

Disk còn bytes nhưng hết inode vẫn gây lỗi. Quan sát:

- filesystem available bytes/inodes;
- container writable layer;
- log growth/rotation;
- image filesystem;
- eviction threshold;
- emptyDir usage;
- runtime garbage collection.

Log storm có thể biến thành node eviction incident.

---

## 25. Network signals

Cần cả:

- request-level RED;
- TCP retransmit/reset;
- packet drop;
- DNS;
- connection establishment;
- conntrack/SNAT;
- bandwidth;
- topology zone/node;
- NetworkPolicy verdict nếu có.

Packet-level telemetry có cardinality/cost lớn; aggregate trước và chỉ drill down có thời hạn.

---

## 26. Pod lifecycle

Các phase/condition/reason cần đặt theo timeline:

```text
Pending → Scheduled → Pulling → Created → Started
→ Ready → Terminating
```

Theo dõi time-to-schedule, image pull, startup, readiness, restart và termination. Pod phase
không phải state machine hoàn chỉnh cho mọi tình huống.

---

## 27. Deployment và rollout

Quan sát:

- desired/current/updated/available replicas;
- unavailable duration;
- observed generation;
- rollout progress/deadline;
- ReplicaSet churn;
- version/image đang phục vụ;
- user SLI theo old/new version.

“Rollout complete” không chứng minh release không tăng error.

---

## 28. StatefulSet và storage identity

Ngoài replica, cần:

- ordinal nào unavailable;
- ordered rollout bị chặn ở đâu;
- PVC binding/mount;
- volume latency/error/capacity;
- replication của chính application;
- quorum;
- failover/recovery time.

Không xóa PVC để chữa Pending Pod nếu chưa xác định ownership và khả năng phục hồi.

---

## 29. Job và CronJob

SLI phù hợp:

- success/failure;
- queue/start delay;
- run duration;
- deadline miss;
- retries;
- active/completed;
- CronJob last schedule;
- duplicate/overlap;
- business rows/messages processed.

Pod “Succeeded” không chứng minh output nghiệp vụ đúng.

---

## 30. HPA, VPA và autoscaling

Theo dõi:

- current/desired replicas;
- metric availability/freshness;
- target so với current value;
- scale event;
- stabilization/cooldown;
- max/min saturation;
- pending capacity;
- user SLI sau scale.

HPA chạm max kéo dài là capacity signal; scale liên tục có thể do metric nhiễu hoặc readiness
chậm.

---

## 31. Requests, limits và scheduling economics

So sánh:

```text
actual usage ↔ request ↔ limit ↔ node allocatable
```

- request quá cao: lãng phí, Pod khó schedule;
- request quá thấp: overcommit và contention;
- limit quá thấp: throttle/OOM;
- không limit: blast radius lớn tùy workload/policy.

Right-sizing cần percentiles dài hạn và headroom cho burst/failover.

---

## 32. QoS, pressure và eviction

QoS class ảnh hưởng cách kubelet chọn Pod khi pressure, nhưng không nên dùng như lời giải thích
duy nhất. Correlate:

- node pressure;
- eviction reason;
- requests/limits;
- priority;
- local storage;
- workload disruption;
- rescheduling capacity.

Node eviction khác application process OOM.

---

## 33. Startup, readiness và liveness probes

| Probe | Mục đích |
|---|---|
| startup | cho ứng dụng đủ thời gian khởi động |
| readiness | có nên nhận traffic không |
| liveness | có cần restart container không |

Liveness phụ thuộc downstream dễ tạo restart cascade. Readiness quá nhạy làm mất capacity khi
load cao. Theo dõi probe duration/result cùng endpoint traffic và restart.

---

## 34. PodDisruptionBudget

PDB giới hạn voluntary disruption theo mức availability khai báo; nó không ngăn mọi loại
failure.

Quan sát:

- disruptions allowed;
- current/desired healthy;
- drain/upgrade bị chặn;
- workload thực có đủ replica đa node/zone;
- user SLO.

PDB sai có thể vừa không bảo vệ đủ vừa chặn bảo trì.

---

## 35. Kubernetes Events

Events là tín hiệu best-effort, bổ trợ và retention giới hạn. Chúng hữu ích để dựng timeline:

- scheduling failure;
- image pull;
- probe failure;
- eviction;
- volume mount;
- backoff.

Không dùng Events làm audit log hay nguồn duy nhất cho alert lịch sử. Export có dedup,
rate-limit và schema/cardinality control.

---

## 36. Logging architecture

Kubernetes không cung cấp native cluster-level log storage. Container thường ghi `stdout` và
`stderr`; runtime/kubelet quản lý file cục bộ, còn agent/backend chịu trách nhiệm thu thập và
lưu trữ.

Thiết kế phải trả lời:

- log có mất khi Pod/node biến mất không;
- multiline xử lý ở đâu;
- metadata enrich thế nào;
- backpressure và disk buffer;
- retention/tenant/privacy.

---

## 37. CRI logs và rotation

Kubelet thực hiện rotation theo cấu hình; `kubectl logs` có giới hạn đối với container đã
restart và file còn trên node.

Theo dõi:

- log bytes/rate;
- rotation errors;
- file descriptor;
- node disk/inode;
- agent lag/drop;
- multiline parse error.

Không coi `kubectl logs` là kho log bền vững.

---

## 38. Node logging agent

DaemonSet agent/Collector thường đọc log mọi node. Nó cần:

- resource request/limit hợp lý;
- priority và toleration;
- checkpoint;
- bounded disk buffer;
- retry/backoff;
- drop counters;
- tenant routing;
- self-telemetry.

Agent phải sống sót đủ lâu trong node pressure để gửi bằng chứng mà không làm pressure nặng
hơn.

---

## 39. Control-plane logs

Control-plane logs hữu ích khi metric báo symptom nhưng không nói chi tiết. Với managed
Kubernetes, quyền truy cập và schema phụ thuộc provider.

Không bật verbosity cao lâu dài nếu chưa ước lượng:

- volume/cost;
- sensitive fields;
- CPU/I/O;
- retention;
- access control.

---

## 40. Audit logs

Audit ghi chuỗi hành động liên quan bảo mật trên Kubernetes API: ai, làm gì, khi nào, trên
resource nào và kết quả gì.

Audit policy chọn level/stage/resource. Body request/response có thể chứa secret hoặc dữ liệu
nhạy cảm. Cần:

- policy tối thiểu cần thiết;
- protected backend;
- integrity/access control;
- retention pháp lý;
- alert hành vi quan trọng;
- capacity test.

---

## 41. Control-plane tracing

Distributed tracing giúp thấy thời gian qua API request, admission và downstream component khi
component/feature hỗ trợ.

Trước khi bật:

- kiểm tra feature/version;
- sampling và overhead;
- propagation;
- sensitive attributes;
- Collector capacity;
- trace completeness.

Trace không thay metrics cho alert tổng thể.

---

## 42. Application traces trên Kubernetes

Span/resource attributes nên nối:

```text
service.name + service.version
↔ cluster + namespace + pod + container
↔ deployment/workload
```

Pod UID/name hữu ích debug; service/workload/version hữu ích aggregate. Resource detector và
metadata enrichment cần RBAC tối thiểu và tránh API lookup trên mỗi span.

---

## 43. OpenTelemetry Collector deployment patterns

Các pattern phổ biến:

```text
agent/DaemonSet → gateway/Deployment → backend
sidecar         → gateway            → backend
application OTLP trực tiếp → gateway
```

Chọn theo node-local collection, tenant isolation, tail sampling và failure domain. Quan sát
accepted, refused, dropped, queue, retry, export latency và memory limiter.

---

## 44. Prometheus Operator

Prometheus Operator quản lý Prometheus-family components và custom resources. Nó giảm thao tác
thủ công nhưng thêm một control plane cần quan sát:

- reconciliation;
- CR status;
- generated configuration;
- rejected resources;
- operator/webhook availability;
- version compatibility.

Operator “Running” không chứng minh target đã được scrape.

---

## 45. ServiceMonitor, PodMonitor và scrape contract

Chọn discovery object theo endpoint thực:

- `ServiceMonitor`: qua Service;
- `PodMonitor`: chọn Pod trực tiếp;
- `Probe`: blackbox target nếu stack hỗ trợ.

Kiểm tra label selector, namespace selector, port name, scheme, TLS/auth, interval, timeout và
sample limits. Một selector sai thường tạo im lặng hơn là lỗi rõ ràng.

---

## 46. Relabeling và metadata

Target relabeling quyết định scrape target/labels; metric relabeling xử lý samples sau scrape.

Quy tắc:

- giữ identity cần thiết;
- loại meta-label tạm;
- chuẩn hóa cluster/environment;
- không copy mọi Pod label;
- drop metric vô ích;
- đặt sample/label limits;
- test rule trước rollout.

---

## 47. Cardinality và churn

Nguồn bùng nổ thường gặp:

- Pod UID/name;
- container ID/image digest;
- raw path;
- node/zone kết hợp quá nhiều dimensions;
- labels/annotations tự do;
- status reason/message;
- histogram buckets dày.

Đo active series, churn, samples/s và top label pairs theo team/workload. Chặn ở ingestion
không thay việc sửa instrumentation.

---

## 48. Correlation theo ownership

Luồng drill-down:

```text
service SLO
→ workload/version
→ Pod/container
→ node/zone
→ Kubernetes Events/logs/traces
→ control plane hoặc dependency
```

Cần mapping Service → workload → owner từ catalog hoặc label contract. Không đoán owner từ
namespace nếu tổ chức không đảm bảo quy ước đó.

---

## 49. Dashboard hierarchy

```text
Fleet
  → cluster
    → namespace/team
      → service/workload
        → pod/container
          → node/runtime/network/storage
```

Mỗi tầng hiển thị SLO/symptom trước, saturation/state sau, rồi change annotations và link
runbook.

---

## 50. Alert hierarchy

Ưu tiên:

1. user SLO burn;
2. workload không đạt objective;
3. shared infrastructure có blast radius;
4. capacity risk có thời gian hành động;
5. telemetry pipeline mất.

Không page cho mọi Pod restart hoặc mọi Event Warning. Dùng ticket/dashboard khi chưa có
user impact và chưa cần hành động tức thời.

---

## 51. Symptom khác state

Ví dụ:

```text
Symptom: checkout error budget burn
State:   3 Pod NotReady
Cause:   node disk full do log storm
```

Page theo symptom; dùng state để route và điều tra. Alert state thuần túy chỉ nên page khi nó
có blast radius rõ và hành động khẩn cấp.

---

## 52. Cluster/platform SLO

Các SLI khả dụng:

- API request availability/latency;
- Pod scheduling latency;
- workload readiness convergence;
- DNS success/latency;
- admission availability;
- telemetry delivery;
- node replacement/recovery.

Định nghĩa từ góc nhìn tenant, có synthetic probes nếu cần. `up{job="apiserver"}` không đủ làm
API SLO.

---

## 53. Workload onboarding contract

Golden path nên yêu cầu:

- owner/service catalog;
- resource requests;
- health probes đúng semantics;
- metrics endpoint;
- structured logs;
- traces/context propagation;
- dashboards/alerts/SLO;
- PII classification;
- runbook;
- version/deploy annotation.

Admission/policy có thể kiểm tra phần tĩnh; runtime test kiểm tra telemetry thực sự đến backend.

---

## 54. RBAC cho observability

Collector/exporter chỉ được:

- list/watch resource cần thiết;
- đọc endpoint cần thiết;
- dùng ServiceAccount riêng;
- giới hạn namespace nếu có thể;
- rotate credential;
- không đọc Secret mặc định.

Cluster-wide watch giúp enrich nhưng tăng blast radius. Audit mọi quyền đặc biệt.

---

## 55. Sensitive telemetry

Rủi ro:

- Secret trong environment/log;
- token trong header/span;
- request/response body trong audit;
- customer ID trong label;
- command từ `kubectl exec`;
- node/system path.

Áp dụng data classification, allowlist, redaction, tenant isolation, encryption, retention và
break-glass access.

---

## 56. Managed Kubernetes

Provider có thể:

- ẩn control-plane targets/logs;
- cung cấp metrics đã đổi tên;
- quản lý etcd;
- có audit integration riêng;
- thay upgrade cadence;
- tính phí egress/log ingestion.

Giữ dashboard portable ở tầng workload, nhưng có adapter/runbook riêng cho provider.

---

## 57. Upgrade và version skew

Trước nâng cấp:

```text
inventory API/metrics/features
→ kiểm tra deprecation
→ test rules/dashboards/collectors
→ canary cluster/node pool
→ so telemetry completeness
→ rollout + rollback criteria
```

Theo dõi version của control plane, kubelet, runtime, CNI, CSI, agents và CRDs; không chỉ
Kubernetes version.

---

## 58. Capacity engineering

Capacity model cần:

- node allocatable và failure headroom;
- requests/actual/burst;
- Pod density;
- API/watch load;
- scheduler throughput;
- etcd size/latency;
- network/SNAT/conntrack;
- storage IOPS;
- telemetry volume;
- zone loss scenario.

Cluster còn 30% CPU tổng không chứng minh schedule được Pod lớn hoặc chịu mất một zone.

---

## 59. Incident workflow

```text
1. Xác nhận user impact, cluster/region/version
2. Kiểm tra deploy/config/traffic
3. Xem service RED và dependency
4. Kiểm tra workload desired/current, probe, restart
5. Kiểm tra Events theo timeline
6. Kiểm tra node/runtime/network/storage
7. Kiểm tra control plane nếu phạm vi rộng
8. Mitigate có rollback và ghi evidence
```

Giảm phạm vi truy vấn và thời gian trước; tránh query cardinality lớn giữa incident.

---

## 60. `kubectl` diagnostics an toàn

Ưu tiên read-only:

```text
kubectl get
kubectl describe
kubectl logs --since=...
kubectl top
kubectl get events
```

Nhưng output vẫn có thể chứa dữ liệu nhạy cảm. `exec`, `debug`, port-forward và API proxy mở
rộng quyền/truy cập; cần audit, time-box và không sửa state ngoài kế hoạch.

---

## 61. Chaos và failure-mode tests

Trong môi trường kiểm soát, thử:

- Pod/process crash;
- readiness fail;
- node unavailable;
- DNS/CNI latency;
- volume attach chậm;
- registry lỗi;
- API rate limit;
- Metrics Server/Prometheus/Collector mất;
- zone loss;
- log storm.

Success criteria gồm user SLO, alert, autoscaling, evidence, mitigation và recovery.

---

## 62. Cost và FinOps

Quan sát:

- requested/used/wasted resources;
- idle/shared cost;
- storage/network egress;
- telemetry bytes/samples/series;
- tenant/team allocation;
- cost per request/job;
- retention/query cost.

Không right-size chỉ theo average; giữ burst, failover và rollout headroom. Cost optimization
không được phá SLO.

---

## 63. Backup và disaster recovery

Cluster manifests trong Git không thay backup stateful data. Với control plane/self-managed
etcd và workload state, cần:

- RPO/RTO;
- encrypted backup;
- off-cluster/off-region copy;
- restore validation;
- dependency/credential plan;
- DNS/traffic cutover;
- telemetry trong DR;
- định kỳ diễn tập.

Backup success metric không chứng minh restore thành công.

---

## 64. Workshop, anti-patterns và checklist

### Workshop

1. Chọn một service và vẽ đường request qua Kubernetes.
2. Map service → workload → Pod → node.
3. Dựng SLO panel, rollout panel và resource panel.
4. Làm một readiness failure có kiểm soát.
5. Dùng Events/logs/traces để dựng timeline.
6. Xác nhận alert, owner và runbook.

### Anti-patterns

- coi Pod Ready là service healthy;
- coi Metrics Server là monitoring backend;
- alert mọi restart/Event;
- copy mọi Pod label vào metric;
- dashboard chỉ theo cluster average;
- dùng audit log như application log;
- bật verbose logging khi chưa có cost/privacy guardrail;
- chữa incident bằng xóa Pod mà chưa tìm failure mode.

### Checklist

- [ ] Có cluster identity và ownership chuẩn.
- [ ] User SLO nối được tới workload/version.
- [ ] Metrics Server và monitoring pipeline được quan sát riêng.
- [ ] kube-state-metrics và resource metrics không bị nhầm.
- [ ] Control-plane/node/runtime/network/storage có coverage.
- [ ] Events chỉ là supplemental signal.
- [ ] Logs/traces/audit có privacy control.
- [ ] Cardinality và telemetry cost có budget.
- [ ] Upgrade có telemetry compatibility test.
- [ ] Failure/restore đã được diễn tập.

### Câu hỏi

1. Desired state khác resource usage thế nào?
2. Vì sao Ready không chứng minh user SLO?
3. Metrics Server và Prometheus khác mục đích gì?
4. kube-state-metrics không cung cấp điều gì?
5. CPU throttling có thể xảy ra khi usage trung bình thấp không?
6. Event có thể dùng làm audit log không?
7. Readiness và liveness khác nhau ở hành động nào?
8. Vì sao aggregate toàn cluster che rủi ro capacity?
9. ServiceMonitor sai selector biểu hiện thế nào?
10. Tại sao Pod label gây churn?
11. Agent logging nên xử lý node pressure thế nào?
12. Backup success khác restore readiness ra sao?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Kubernetes

- [Kubernetes observability](https://kubernetes.io/docs/concepts/cluster-administration/observability/)
- [System component metrics](https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/)
- [Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)
- [Logging architecture](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
- [Kubernetes Events](https://kubernetes.io/docs/reference/kubernetes-api/events/)
- [Kubernetes auditing](https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/)
- [Liveness, readiness and startup probes](https://kubernetes.io/docs/concepts/workloads/pods/probes/)
- [Kubernetes components](https://kubernetes.io/docs/concepts/overview/components/)
- [Node-pressure eviction](https://kubernetes.io/docs/concepts/scheduling-eviction/node-pressure-eviction/)
- [Resource management for Pods and containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

### Ecosystem

- [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics)
- [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
- [Prometheus Operator](https://prometheus-operator.dev/docs/getting-started/introduction/)
- [OpenTelemetry Collector for Kubernetes](https://opentelemetry.io/docs/platforms/kubernetes/collector/)

Chủ đề tiếp theo:
[**Messaging & Kafka Observability**](messaging_kafka_observability.md) – producer/consumer
latency, delivery semantics, consumer lag, partition skew, retries, rebalances và end-to-end
message freshness.

---

*Cập nhật lần cuối: 2026-07-30*
