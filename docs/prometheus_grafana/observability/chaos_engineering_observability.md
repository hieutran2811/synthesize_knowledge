---
title: "Chaos Engineering for Observability – Kiểm Chứng Pipeline Khi Có Sự Cố"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 17
---
# Chaos Engineering for Observability – Kiểm Chứng Pipeline Khi Có Sự Cố

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là kiểm chứng hệ thống observability vẫn cung cấp tín hiệu
> đáng tin cậy khi chính pipeline metrics, logs, traces và profiles gặp lỗi.
> Chaos ở đây là thí nghiệm có giả thuyết, phạm vi, điều kiện dừng và bằng chứng;
> không phải tắt ngẫu nhiên pod rồi chờ xem chuyện gì xảy ra.
>
> Baseline tham chiếu của dự án: **Prometheus 3.13.x**, **Grafana 13.1.x**,
> **Mimir 3.1.x**, **Loki 3.7.x**, **Tempo 3.0.x**, **Pyroscope 2.2.x**,
> **OpenTelemetry Java 1.64.x / Collector 0.157.x** và **Grafana Alloy 1.18.x**.
>
> Nên đọc trước:
> [Alerting Strategy & SLO](alerting_strategy.md),
> [Full Observability Stack](stack_integration.md),
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md),
> [Grafana Mimir](grafana_mimir.md) và
> [Telemetry Governance & FinOps](telemetry_governance_finops.md).

---

## 1. Vì sao observability cũng cần chaos engineering?

Một monitoring stack có thể “xanh” trong ngày bình thường nhưng thất bại đúng lúc cần nhất:

```text
application incident
  → telemetry tăng đột biến
  → Collector bị backpressure
  → backend throttle
  → query chậm
  → alert đến muộn hoặc không đến
  → on-call nhìn thấy một bức tranh thiếu dữ liệu
```

Các bài test thông thường thường xác nhận:

- process khởi động;
- endpoint `/ready` trả `200`;
- một query đơn giản chạy được;
- dashboard được provision;
- cấu hình hợp lệ.

Chúng chưa chứng minh:

- pipeline chịu được downstream outage bao lâu;
- queue đầy sẽ drop tín hiệu nào;
- restart có mất dữ liệu đang đợi hay không;
- canary có phát hiện gap/duplicate;
- alert có tới người nhận trong thời gian mục tiêu;
- hệ thống phục hồi có tạo retry storm;
- on-call còn quan sát được khi backend chính hỏng.

Chaos engineering biến các giả định này thành kết quả đo được.

---

## 2. Chaos khác load test, failover test và game day

| Hoạt động | Câu hỏi chính |
|---|---|
| Unit/integration test | component có làm đúng logic không? |
| Load test | hệ thống chịu được bao nhiêu tải? |
| Failover test | replica/region dự phòng có tiếp quản không? |
| DR exercise | có khôi phục được dữ liệu và dịch vụ sau thảm họa không? |
| Chaos experiment | trạng thái ổn định có giữ được trước một điều kiện bất lợi cụ thể không? |
| Game day | con người, quy trình và kỹ thuật phối hợp thế nào trong kịch bản gần thực tế? |

Chúng bổ sung cho nhau.

Ví dụ:

```text
load test:
  tăng 5 lần số spans/giây

chaos:
  trong lúc tải tăng, làm backend trả 429
  và kiểm chứng queue, drop policy, alert, recovery

game day:
  on-call dùng runbook để nhận biết, giảm tải và phục hồi
```

Không nên gọi một lần `kubectl delete pod` không có giả thuyết là chaos engineering.

---

## 3. Mô hình một thí nghiệm có kiểm soát

Một experiment tối thiểu:

```text
steady state
  + hypothesis
  + fault
  + blast radius
  + observation
  + abort conditions
  + recovery
  + evidence
```

Ví dụ:

```text
Steady state:
  99.9% synthetic traces query được trong 60 giây

Fault:
  chặn network từ một Collector gateway tới Tempo trong 3 phút

Hypothesis:
  ứng dụng không lỗi vì exporter;
  queue không vượt 80%;
  không mất trace;
  backlog drain trong 5 phút sau phục hồi

Abort:
  customer error tăng, queue > 90%, fault lan ngoài canary tenant
```

Kết quả “không có sự cố” chỉ có ý nghĩa nếu steady state và cách đo đã được định nghĩa
trước khi inject fault.

---

## 4. Phạm vi riêng của chaos cho observability

Bài này tập trung vào hai hướng:

1. **Chaos dùng observability để quan sát application**: inject lỗi ứng dụng và xem tín hiệu
   có phản ánh đúng không.
2. **Chaos vào chính observability pipeline**: làm Collector, queue, backend, query hoặc
   alerting gặp lỗi và kiểm chứng khả năng chịu lỗi.

Hướng thứ hai thường bị bỏ quên.

```text
Producer
  → SDK/agent
  → Collector/Alloy
  → queue/network
  → backend ingest
  → storage/index
  → query/rules
  → Grafana/notification
```

Mỗi mũi tên là một failure boundary. “Backend healthy” không chứng minh toàn bộ chuỗi hoạt
động.

---

## 5. Data plane và control plane

Tách hai mặt:

| Plane | Thành phần |
|---|---|
| Data plane | receive, transform, queue, ingest, store, query telemetry |
| Control plane | config, tenant, credentials, routing, rollout, limits, dashboards/rules |

Ví dụ lỗi data plane:

- exporter timeout;
- queue đầy;
- object storage chậm;
- Kafka lag;
- query bị timeout.

Ví dụ lỗi control plane:

- rollout config drop nhầm attribute;
- secret hết hạn;
- runtime limit sai;
- datasource UID đổi;
- rule bị disable;
- tenant header route nhầm.

Chaos plan chỉ kill pod sẽ bỏ sót nhiều lỗi control plane nguy hiểm hơn.

---

## 6. Steady state phải nhìn từ người dùng

Steady state không nên chỉ là:

```text
all pods Ready = true
```

Nó nên trả lời trải nghiệm của consumer:

- producer gửi được dữ liệu;
- dữ liệu xuất hiện đủ và đúng thời gian;
- query phổ biến trả kết quả chính xác;
- correlation link hoạt động;
- rule evaluate đúng;
- notification tới đúng nơi;
- platform không làm application chậm hoặc lỗi.

Mẫu:

```yaml
steady_state:
  write_success_ratio: ">= 99.95%"
  synthetic_freshness_p99: "<= 60s"
  query_success_ratio: ">= 99.9%"
  alert_delivery_p99: "<= 120s"
  known_sequence_loss: 0
```

Đặt threshold trước experiment để tránh diễn giải kết quả theo cảm tính.

---

## 7. SLO bề mặt người dùng của platform

Observability platform thường có nhiều bề mặt:

| Bề mặt | Consumer | Ví dụ SLI |
|---|---|---|
| Write | SDK, agent, collector | accepted / attempted |
| Freshness | dashboard, rule | thời gian từ emit tới query được |
| Query | engineer, automation | successful queries / total |
| Correctness | on-call | expected records có đủ/đúng |
| Alerting | on-call | notification đúng hạn |
| Correlation | investigator | link có target hợp lệ |

Không gộp tất cả thành một uptime SLO.

Một hệ thống có thể:

- nhận write bình thường nhưng query history hỏng;
- query được nhưng dữ liệu trễ 20 phút;
- dashboard mở được nhưng rule evaluation thất bại;
- trace tồn tại nhưng log-to-trace link sai tenant.

Chaos experiment phải chỉ rõ SLO nào được kiểm chứng.

---

## 8. Write SLO

Write SLI nên đo gần ranh giới consumer:

```text
good writes
-----------
attempted writes
```

Nhưng “HTTP 200 từ receiver” chưa chắc dữ liệu đã durable.

Cần phân biệt:

- receiver accepted;
- processor forwarded;
- exporter enqueued;
- backend accepted;
- dữ liệu query được;
- dữ liệu đã vào durable storage.

Ví dụ contract:

```text
Critical metrics:
  >= 99.99% samples query được trong 30 giây

Debug traces:
  >= 99.0% traces đã được chọn bởi sampler query được trong 120 giây
```

Mẫu số của traces phải là số trace **đã quyết định giữ**, không phải toàn bộ request nếu
sampling chủ ý loại bỏ một phần.

---

## 9. Query SLO

Tách query theo class:

| Class | Ví dụ | Target |
|---|---|---|
| Alert/rule | recording rule, SLO burn | nghiêm nhất |
| Incident | dashboard, ad-hoc bounded query | cao |
| Interactive exploration | TraceQL/LogQL rộng | vừa |
| Batch/report | trend dài ngày | có thể chậm hơn |

SLI:

```text
availability = successful_queries / eligible_queries
latency      = p95/p99 theo query class
correctness  = expected result khớp synthetic fixture
```

Không tính query bị từ chối đúng do policy vào platform failure. Ngược lại, timeout do
capacity thiếu phải được tính.

Chaos query storm cần bảo vệ alert/rule path thay vì để một truy vấn ad-hoc làm cạn toàn bộ
concurrency.

---

## 10. Freshness SLO

Freshness đo:

```text
query_visible_timestamp - producer_event_timestamp
```

Nó bao gồm:

- SDK/export interval;
- batch delay;
- queue wait;
- network;
- backend ingest/index;
- query cache.

Ví dụ synthetic record mang:

```json
{
  "experiment_id": "obs-chaos-20260730-01",
  "sequence": 1042,
  "emitted_at": "2026-07-30T10:00:00Z"
}
```

Khi query được record, canary tính propagation latency. Dùng đồng hồ đã đồng bộ; clock skew
có thể làm freshness âm hoặc sai lớn.

---

## 11. Completeness và correctness SLO

Uptime không phát hiện dữ liệu thiếu âm thầm.

Với sequence liên tục:

```text
expected: 1001, 1002, 1003, 1004, 1005
actual:   1001, 1002,       1004, 1005, 1005

missing   = 1003
duplicate = 1005
```

Theo dõi:

- missing;
- duplicate;
- out-of-order ngoài contract;
- field bị đổi/drop;
- timestamp sai;
- tenant sai;
- query trả dữ liệu không thuộc tenant.

Correctness đặc biệt quan trọng với transform, sampling, relabel và schema migration. Một
pipeline “không lỗi” nhưng biến `service.name` thành giá trị sai vẫn là failure.

---

## 12. Correlation SLO

Một synthetic transaction có thể tạo:

```text
metric exemplar
  ↔ trace
  ↔ structured log
  ↔ profile label
```

Canary kiểm tra:

- exemplar trace ID có tồn tại trong Tempo;
- trace-to-logs trả đúng service/time range;
- log trace ID mở đúng trace;
- trace-to-metrics dùng đúng labels;
- profile link có đúng service/version/time.

SLI gợi ý:

```text
valid_correlation_links / attempted_correlation_links
```

Correlation có thể hỏng do datasource UID, tenant mapping, retention lệch hoặc identity
contract; không nhất thiết do dữ liệu gốc mất.

---

## 13. Alerting SLO

Đo toàn chuỗi:

```text
condition true
  → rule evaluation
  → alert pending/firing
  → Alertmanager/Grafana Alerting
  → group/deduplicate/route
  → contact point
  → receiver acknowledge
```

Các SLI:

- evaluation success;
- detection latency;
- notification delivery latency;
- duplicate count;
- wrong-route count;
- recovery notification correctness.

Synthetic alert phải:

- gắn `test=true`, `experiment_id`;
- route tới receiver sandbox;
- không page on-call thật trừ game day đã phê duyệt;
- có auto-resolve;
- kiểm tra cả firing và resolved.

Một webhook trả `200` chưa chứng minh con người hoặc hệ thống đích nhận đúng nội dung.

---

## 14. Meta-monitoring phải độc lập

Nếu Mimir chính hỏng và metrics của Mimir cũng chỉ nằm trong Mimir đó, platform có thể bị
mù.

Tối thiểu cần:

```text
primary observability stack
  ── emits critical health ──▶ independent small monitor
                               └── independent notification
```

Mức độc lập tùy rủi ro:

- khác tenant chưa đủ nếu chung backend;
- khác cluster nhưng chung object store vẫn có shared fate;
- khác region/provider tăng khả năng sống sót nhưng tăng chi phí;
- health probe ngoài hệ thống giúp phát hiện lỗi mạng/DNS từ góc nhìn user.

Không cần sao chép mọi telemetry. Chỉ giữ các tín hiệu sống còn: canary, SLO, queue/drop,
storage, rule và notification heartbeat.

---

## 15. Synthetic signal là “mẫu chuẩn”

Synthetic signal có input đã biết nên đo được output.

Mỗi record nên có:

| Field | Mục đích |
|---|---|
| `experiment_id` | phân biệt lần chạy |
| `sequence` | phát hiện gap/duplicate |
| `emitted_at` | đo freshness |
| `expected_tenant` | phát hiện route sai |
| `schema_version` | phát hiện transform sai |
| bounded labels | tránh tự tạo cardinality incident |

Nguyên tắc:

- volume nhỏ, liên tục;
- không chứa PII/secret;
- TTL/retention rõ;
- query bằng API giống consumer thật;
- có dashboard và alert riêng;
- không phụ thuộc duy nhất vào stack đang kiểm tra.

Synthetic data không thay telemetry thật, nhưng tạo một “thước đo” ổn định.

---

## 16. Experiment contract

Mẫu version-control:

```yaml
id: obs-tempo-gateway-partition-v1
owner: observability-platform
environment: staging
target:
  component: otel-gateway
  selector: app=otel-gateway,chaos-canary=true
steady_state:
  trace_visible_p99: 60s
  trace_loss: 0
fault:
  type: network_partition
  destination: tempo-distributor
  duration: 180s
blast_radius:
  tenants: [chaos-test]
  replicas: 1
abort:
  queue_utilization: "> 90%"
  application_error_delta: "> 0.5%"
rollback:
  deadline: 60s
evidence:
  dashboard_uid: obs-chaos
  result_bucket: obs-chaos-evidence
```

Contract cần review như code. Thay duration, selector hoặc abort threshold là thay đổi hành
vi, không phải chỉnh tài liệu vô hại.

---

## 17. Preconditions trước khi inject fault

Không chạy nếu:

- baseline đang ngoài SLO;
- có incident/maintenance khác;
- người có quyền rollback không sẵn sàng;
- kill switch chưa test;
- selector chưa xác nhận;
- canary hoặc meta-monitoring không hoạt động;
- backup/restore chưa phù hợp với fault có nguy cơ dữ liệu;
- capacity không có headroom;
- stakeholder không biết experiment production.

Readiness checklist:

```text
steady state green
  → target resolved
  → blast radius verified
  → abort automation armed
  → rollback rehearsed
  → communication open
  → inject
```

Nếu không quan sát được experiment, điều kiện an toàn mặc định là dừng.

---

## 18. Blast radius

Giảm blast radius theo nhiều chiều:

| Chiều | Ví dụ |
|---|---|
| Environment | lab → staging → production |
| Tenant | chỉ `chaos-test` |
| Replica | 1/10 gateway |
| Zone | một zone có capacity dự phòng |
| Signal | traces debug trước critical metrics |
| Time | 30 giây trước 5 phút |
| Traffic | 1% canary producers |

Đừng chỉ dựa vào label selector. Xác nhận resolved targets:

```text
declared selector
  → list concrete pods/nodes/endpoints
  → compare allowlist
  → refuse if count or namespace unexpected
```

Một selector rỗng hoặc quá rộng phải fail closed.

---

## 19. Điều kiện dừng và kill switch

Abort ngay khi:

- SLO/error budget burn vượt ngưỡng;
- customer errors hoặc latency tăng ngoài dự kiến;
- phát hiện mất/cross-tenant data;
- fault lan ngoài target;
- meta-monitoring mất;
- rollback không hoạt động;
- queue/disk/memory vượt safety limit;
- người điều phối yêu cầu dừng.

Kill switch cần:

- một lệnh/API rõ;
- quyền đã cấp trước;
- không phụ thuộc thành phần đang phá;
- timeout tự động;
- xác nhận fault đã thực sự biến mất.

```text
stop injection
  ≠ system recovered
```

Sau khi dừng vẫn phải theo dõi backlog drain, retries, cache warm-up và data reconciliation.

---

## 20. Control group

Không có control group, khó biết thay đổi đến từ fault hay tải nền.

Ví dụ:

```text
experiment:
  1 gateway bị network delay 500 ms

control:
  1 gateway cùng version/traffic, không inject
```

So sánh:

- accepted/refused;
- queue utilization;
- CPU/memory;
- export latency/error;
- synthetic freshness/loss;
- downstream response.

Control group phải đủ giống nhưng không chung fault boundary. Nếu cả hai dùng cùng network
path đang bị chặn, nó không còn là control.

---

## 21. Baseline và cửa sổ quan sát

Thu ít nhất:

```text
pre-fault → fault active → recovery → stable again
```

Ví dụ:

| Giai đoạn | Thời gian |
|---|---:|
| Baseline | 15 phút |
| Inject | 3 phút |
| Recovery | tới khi backlog về baseline |
| Post-check | thêm 15 phút |

Đừng kết thúc khi pod Ready. Recovery complete khi:

- queue/lag về bình thường;
- synthetic gap đã reconcile hoặc xác nhận lost;
- query latency bình thường;
- retry rate hạ;
- rule evaluation không còn lỗi;
- resource không còn saturation;
- không tạo duplicate storm.

Lưu cả giá trị tuyệt đối và delta so với control.

---

## 22. Taxonomy failure

Nhóm fault:

```text
Compute:
  crash, CPU, memory, OOM

Network:
  latency, loss, partition, DNS, TLS

Storage:
  disk full/slow, object store error, corruption

Dependency:
  Kafka lag/outage, auth, metadata service

Load:
  cardinality spike, volume spike, query storm

Configuration:
  bad route, wrong tenant, expired credential, schema change

Time:
  clock skew, delayed data, retention boundary
```

Test taxonomy theo failure modes thực tế và architecture, không theo danh sách tính năng
của chaos tool.

---

## 23. Process và pod termination

Các experiment khác nhau:

- kill một stateless replica;
- rolling restart toàn deployment;
- SIGTERM với grace period;
- SIGKILL không cleanup;
- crash loop;
- readiness false nhưng process còn sống.

Kiểm chứng:

- traffic có route khỏi replica lỗi;
- dữ liệu in-memory queue có mất;
- WAL/persistent queue resume;
- replica mới warm-up bao lâu;
- ring/memberlist cập nhật;
- retry có duplicate;
- PDB/anti-affinity có giữ capacity.

Không xóa StatefulSet/PVC như một “pod kill”. Đó là fault dữ liệu có rủi ro và recovery
khác hoàn toàn.

---

## 24. Node và availability zone outage

Zone outage kiểm tra:

- replicas có trải zone thật không;
- quorum/ring còn hoạt động;
- topology-aware routing;
- cross-zone traffic/cost;
- capacity còn lại;
- persistent volumes có attach được;
- canary ở zone khác có query được.

Hypothesis mẫu:

```text
Mất một zone:
  critical writes tiếp tục >= SLO
  alert/rule query không bị starve
  p99 freshness <= 2 × baseline
  không mất synthetic sequence
```

Kubernetes labels/anti-affinity đẹp không chứng minh storage, load balancer và DNS cũng độc
lập theo zone.

---

## 25. Network latency, loss và partition

Ba fault có hành vi khác:

| Fault | Tác động thường gặp |
|---|---|
| Latency | timeout, queue tăng, goroutine/connections giữ lâu |
| Packet loss | retry, TCP backoff, throughput giảm khó đoán |
| Partition | endpoint hoàn toàn không tới được |

Chạy theo hop:

```text
SDK → agent
agent → gateway
gateway → backend
backend → object store/Kafka
query frontend → querier/store
Grafana → datasource
Alertmanager → contact point
```

Fault toàn cluster không cho biết hop nào thiếu resilience.

Theo dõi timeout hierarchy để tránh request ngoài chờ lâu hơn bên trong rồi tạo work vô
ích.

---

## 26. DNS và service discovery

Các kịch bản:

- DNS timeout;
- NXDOMAIN tạm thời;
- record trỏ endpoint cũ;
- TTL/cache quá dài;
- headless service trả pod chưa Ready;
- service discovery stale.

Kiểm chứng:

- client re-resolve sau lỗi;
- connection pool không giữ địa chỉ chết vô hạn;
- fallback không bypass TLS/auth;
- retry có jitter;
- alert phân biệt DNS với backend 5xx;
- recovery không cần restart thủ công.

Nhiều test dùng IP trực tiếp vô tình bỏ qua failure mode DNS production.

---

## 27. CPU pressure

Inject CPU vào:

- Collector;
- compactor/ingester/querier;
- Grafana;
- node chứa nhiều thành phần.

Quan sát:

- throttling;
- receive/export latency;
- queue;
- dropped/refused items;
- rule evaluation duration;
- query latency;
- readiness/liveness;
- application latency nếu agent sidecar tranh CPU.

CPU limit quá thấp có thể làm batching/retry chậm, khiến queue tăng dù backend khỏe.

Test cả:

```text
steady load + CPU pressure
incident volume spike + CPU pressure
```

Vì sự cố thật thường tạo nhiều logs/traces hơn ngày bình thường.

---

## 28. Memory pressure và OOM

Experiment:

- tăng input đến memory limiter;
- giảm memory limit ở canary;
- làm tail-sampling buffer lớn;
- OOM kill gateway;
- kiểm tra memory leak kéo dài.

Expected behavior:

- memory limiter từ chối có metric rõ;
- application không bị OOM theo agent;
- queue bounded;
- persistent data resume sau restart;
- alert trước OOM;
- không restart loop do backlog.

Không coi OOM recovery thành công nếu pod trở lại nhưng dữ liệu trong in-memory queue đã
mất mà không được phát hiện.

---

## 29. Disk chậm hoặc đầy

Áp dụng cho:

- Prometheus WAL/TSDB;
- Collector `file_storage`;
- Loki/Tempo/Mimir local state/cache;
- compactor working directory;
- Grafana database.

Fault:

- I/O latency;
- IOPS throttling;
- disk 90%/100%;
- inode exhaustion;
- read-only filesystem;
- volume detach.

Kiểm chứng:

- alert có đủ lead time;
- component fail rõ thay vì silent drop;
- retention/cleanup không xóa nhầm;
- persistent queue xử lý disk full;
- recovery không cần xóa WAL tùy tiện;
- evidence xác nhận gap.

Không làm đầy disk production bằng file rác. Dùng volume canary/quota hoặc fault tool có
phạm vi.

---

## 30. Object storage failure

Object storage là failure domain chung của Mimir, Loki, Tempo và Pyroscope nếu dùng cùng
provider/account.

Kịch bản:

- 5xx;
- latency cao;
- throttling/429;
- DNS/network partition;
- credential denied;
- bucket policy sai;
- list/read/write khác nhau;
- một prefix unavailable.

Quan sát riêng:

- ingest có tiếp tục nhờ local buffer/ingester không;
- historical query có lỗi;
- compaction/retention lag;
- upload backlog;
- cache che lỗi trong bao lâu;
- recovery có request storm.

Không giả lập “object store down” bằng xóa bucket/object. Đó là destructive data-loss test
chỉ được chạy trong bucket disposable.

---

## 31. Kafka hoặc durable queue

Tempo 3 microservices và Mimir ingest storage có thể phụ thuộc Kafka-compatible queue.

Fault:

- broker unavailable;
- leader election;
- partition under-replicated;
- producer timeout;
- consumer chậm;
- retention quá ngắn;
- disk pressure;
- auth/TLS lỗi.

SLI:

- produce success/latency;
- consumer lag theo thời gian và bytes;
- oldest message age;
- under-replicated partitions;
- replay duration;
- duplicate/loss;
- downstream freshness.

Queue decouple producer và consumer, nhưng không xóa failure. Nếu Kafka hỏng, producer vẫn
cần bounded queue/retry; nếu retention hết trước replay, dữ liệu mất.

---

## 32. Clock skew và time failure

Telemetry phụ thuộc timestamp mạnh:

- Prometheus reject sample quá cũ/tương lai;
- logs nằm ngoài time picker;
- spans có duration âm hoặc sai;
- alert window/burn rate lệch;
- certificates có vẻ chưa hiệu lực/hết hạn;
- sequence freshness sai;
- out-of-order tăng.

Thử skew nhỏ trên node canary hoặc dùng application timestamp abstraction; không đổi đồng
hồ node production dùng chung.

Kiểm chứng:

- NTP/time-source alert;
- backend reject có reason;
- UI/runbook hướng dẫn kiểm tra time;
- canary phân biệt clock error và propagation latency;
- correlation dùng window có safety margin hữu hạn.

---

## 33. TLS, certificate và credential

Kịch bản gần thực tế:

- certificate hết hạn;
- CA bundle thiếu;
- hostname mismatch;
- mTLS client cert rotate;
- token hết hạn;
- secret mount không reload;
- IAM permission bị thu hồi;
- tenant header bị gateway strip.

Expected:

- lỗi authentication khác network timeout;
- alert trước expiry;
- rotation không mất dữ liệu ngoài budget;
- retry không hammer lỗi permanent;
- credential không xuất hiện trong log;
- rollback secret version hoạt động;
- cross-tenant access không xảy ra.

Không hạ `insecure_skip_verify` để “phục hồi” experiment. Điều đó che failure và tạo lỗ hổng
mới.

---

## 34. Bad configuration rollout

Config chaos an toàn dùng mutation đã biết:

- đổi endpoint sang blackhole;
- drop một synthetic attribute;
- giảm queue canary;
- đặt tenant route sai nhưng bị policy chặn;
- rule expression invalid;
- datasource UID không tồn tại;
- runtime limit thấp cho tenant test.

Pipeline:

```text
lint/render
  → unit test
  → canary config
  → synthetic validation
  → progressive rollout
  → auto rollback
```

Mục tiêu không phải chứng minh parser bắt mọi lỗi. Cần chứng minh lỗi semantic được canary
phát hiện trước khi rollout rộng.

---

## 35. Cardinality và volume spike

Incident thường tự khuếch đại telemetry:

```text
request lỗi
  → retry nhiều
  → log nhiều
  → trace nhiều
  → error label chứa giá trị động
  → series/streams tăng
```

Thí nghiệm bounded:

- tăng RPS;
- tạo nhiều route/status hợp lệ;
- đưa unbounded ID vào canary metric để kiểm tra policy reject;
- tăng stack traces/log size;
- bật tail sampling nhiều hơn.

Kiểm chứng:

- source/collector/backend limits;
- critical signals được ưu tiên;
- drop theo reason/tenant;
- noisy tenant không phá tenant khác;
- cost alert đủ sớm;
- degraded mode kích hoạt và tự thoát.

Không tạo cardinality không giới hạn vào shared production backend.

---

## 36. Query storm và noisy neighbor

Kịch bản:

- nhiều dashboard refresh cùng lúc;
- query time range rất rộng;
- regex/TraceQL/LogQL tốn tài nguyên;
- report batch trùng giờ incident;
- một tenant dùng hết concurrency.

Kiểm chứng:

- query fairness;
- per-tenant limits;
- cache;
- splitting/sharding;
- cancellation;
- timeout;
- alert/rule priority;
- dashboard partial failure rõ ràng.

Success không phải “mọi query đều chạy”. Hệ thống có thể từ chối query expensive đúng policy
để giữ SLO cho critical queries.

---

## 37. Backend throttle và error responses

Exporter phải phân biệt:

| Response | Hành vi mong đợi |
|---|---|
| Retryable 429/5xx | backoff + jitter + bounded retry |
| Permanent 400/schema | không retry vô hạn, báo/drop có reason |
| 401/403 | alert credential/policy, tránh retry storm |
| Timeout | retry theo budget và idempotency |

Chaos proxy có thể trả tỷ lệ lỗi đã định:

```text
10% 429 trong 2 phút
  → queue tăng có kiểm soát
  → retry có jitter
  → backend không bị herd sau phục hồi
  → synthetic loss = 0 trong durability window
```

Đừng chỉ test “connection refused”; lỗi application-level thường tạo hành vi khác.

---

## 38. Downstream của OpenTelemetry Collector bị lỗi

Collector cần được kiểm tra theo exporter:

- endpoint không tới được;
- response chậm;
- 429/5xx;
- 400 permanent;
- TLS/auth fail;
- partial success;
- DNS stale.

Theo dõi internal telemetry:

- accepted/refused items;
- exporter sent;
- failed to enqueue;
- failed to send;
- queue size/capacity;
- process CPU/memory/restarts.

Hypothesis phải ghi rõ:

```text
outage_duration <= buffering_window
  → no loss expected

outage_duration > buffering_window
  → controlled loss expected
  → exact loss detected and alerted
```

Không hứa “zero loss” nếu queue và retry đều hữu hạn.

---

## 39. Sending queue, retry và persistent storage

In-memory queue bảo vệ khỏi downstream outage ngắn nhưng mất khi Collector crash.

```text
buffering_window xấp xỉ
  queue_capacity_items / incoming_items_per_second
```

Cần tính bằng bytes và batch distribution thực tế, không chỉ số request.

Persistent queue với `file_storage` giúp sống qua restart, nhưng vẫn mất dữ liệu khi:

- disk hỏng/đầy;
- queue đầy;
- retry budget hết;
- config/credential không phục hồi;
- WAL corrupt;
- volume không attach.

Experiment matrix:

| Downstream | Collector | Storage | Expected |
|---|---|---|---|
| down ngắn | up | memory | buffer + drain |
| down | restart | memory | gap được phát hiện |
| down | restart | persistent | resume nếu disk tốt |
| down dài | up | persistent đầy | controlled drop + alert |

Queue không phải backup và không thay dedicated durable message queue.

---

## 40. Collector restart, backpressure và loss accounting

Đo các counter tại từng hop:

```text
producer emitted
  - receiver accepted
  - processor output
  - exporter enqueued
  - backend accepted
  - query observed
```

Delta giúp khoanh vùng:

```text
emitted - accepted      → trước/ở receiver
accepted - enqueued     → processor/exporter admission
enqueued - sent         → backlog hoặc drop
sent - query observed   → backend/index/query
```

Counter nội bộ có thể reset khi restart; lưu `service.instance.id` và dùng rate/increase phù
hợp. Synthetic sequence là bằng chứng end-to-end độc lập hơn.

Sau recovery, kiểm tra duplicate do retry “at least once”. Duplicate có thể được backend
deduplicate hoặc xuất hiện thật tùy signal/protocol.

---

## 41. Prometheus local TSDB và remote write

Kịch bản:

- scrape target timeout;
- local disk/WAL chậm;
- remote endpoint down;
- remote-write queue shard saturation;
- relabel config drop nhầm series;
- restart trong lúc backlog;
- out-of-order samples.

Kiểm chứng:

- scrape gap khác remote-write gap;
- local query còn dữ liệu khi remote unavailable;
- remote-write backlog/dropped samples;
- WAL disk headroom;
- recovery time;
- duplicate/out-of-order handling;
- critical rules chạy ở lớp nào.

Nếu alert rules chỉ chạy ở remote backend, remote outage có thể làm mất alert dù local
Prometheus vẫn scrape tốt. Architecture phải ghi rõ nơi evaluate rule và failure domain.

---

## 42. Grafana Mimir experiment matrix

Theo path:

| Fault | Tác động cần kiểm chứng |
|---|---|
| Distributor loss | write routing/HA còn SLO |
| Kafka unavailable | producer queue, write errors, no silent loss |
| Consumer/ingester chậm | lag, recent query freshness |
| Querier loss | query availability |
| Store-gateway/object store chậm | historical query |
| Compactor outage | compaction/retention backlog |
| Query frontend storm | fairness, cache, limits |
| Ring/memberlist partition | ownership/quorum |

Với ingest storage, write có thể được Kafka nhận nhưng recent read vẫn trễ vì consumer lag.
Do đó phải đo cả:

```text
write acknowledgement
  + consumer lag
  + query freshness
```

Không xóa StatefulSet/PVC để “thử HA” khi chưa hiểu state và recovery. Thực hành destructive
chỉ trên tenant/cluster disposable có restore plan.

---

## 43. Loki experiment matrix

Kịch bản:

- distributor/ingester replica loss;
- object store latency;
- index gateway/query frontend outage;
- log volume/stream cardinality spike;
- malformed/oversized line;
- compactor/retention lag;
- tenant limit;
- clock-skewed logs.

Dùng Loki Canary để đo end-to-end:

- missing entries;
- unexpected entries;
- duplicate entries;
- write-to-query latency;
- chuyển từ in-memory sang object store;
- stored rate so với expected rate.

Experiment thành công khi canary phản ánh đúng fault và recovery; không phải khi metrics
component đơn lẻ vẫn xanh.

---

## 44. Tempo experiment matrix

Kịch bản:

- distributor/receiver unavailable;
- Kafka produce/consume lag trong microservices mode;
- live-store/block-builder issue;
- object store lỗi;
- query frontend/querier outage;
- metrics-generator drop/cardinality;
- trace quá lớn;
- span đến trễ/out-of-order.

Tempo Vulture có thể:

- ghi synthetic traces;
- đọc lại theo trace ID;
- search bằng TraceQL;
- kiểm tra TraceQL metrics.

Theo dõi riêng:

```text
ingest accepted
  ≠ trace complete
  ≠ search indexed
  ≠ metrics-derived correct
```

Một trace query được nhưng thiếu spans vẫn là correctness failure.

---

## 45. Pyroscope và continuous profiling

Nếu backend không có canary chuyên dụng, tạo workload profile đã biết:

```text
function chaosHotLoop()
  chạy CPU bounded trong 60 giây
  với service/version/experiment labels cố định
```

Sau đó kiểm tra:

- profile được ingest;
- function xuất hiện trong time range;
- sample proportion nằm trong tolerance;
- labels đúng;
- symbolization hoạt động;
- query/diff profile trả kết quả;
- agent overhead trong budget.

Fault:

- agent restart;
- backend unavailable;
- symbol store/object storage chậm;
- label cardinality spike;
- CPU throttling;
- profiling permission bị thu hồi.

Không dùng workload CPU không giới hạn trên node shared.

---

## 46. Grafana, datasource và UI

Kịch bản:

- một Grafana replica chết;
- database/session store chậm;
- datasource timeout;
- datasource UID đổi;
- auth provider unavailable;
- provisioning lỗi;
- dashboard query một datasource trong nhiều datasource bị lỗi;
- plugin failure.

Kiểm chứng:

- HA/session;
- error message chỉ rõ datasource;
- dashboard critical có partial/degraded view;
- explore/API còn dùng được;
- alerting có phụ thuộc UI availability không;
- runbook có direct backend query;
- datasource credentials rotate.

Grafana down không đồng nghĩa dữ liệu mất. Runbook cần phân biệt presentation outage với
ingest/query backend outage.

---

## 47. Ruler, Alertmanager và notification

Fault:

- rule evaluator replica loss;
- query dependency timeout;
- rule group quá chậm;
- Alertmanager peer partition;
- notification endpoint 429/5xx;
- DNS/TLS/auth failure;
- template lỗi;
- silence/inhibition sai.

Kiểm chứng:

- missed evaluations;
- duplicate notifications;
- group/dedup correctness;
- resend behavior;
- silence replication;
- firing và resolved;
- dead-man/heartbeat alert;
- independent fallback route.

Fault notification chỉ dùng receiver sandbox trước. Khi game day cần page người thật, phải
có lịch, nhãn và thông báo trước để tránh alert fatigue.

---

## 48. Sampling, retention và correlation failure

Chaos không chỉ là hạ tầng.

Experiment semantic:

- tăng head sampling drop;
- tail sampler không nhận đủ spans cùng trace;
- retention trace ngắn hơn exemplar;
- drop `trace_id` khỏi logs;
- đổi `service.name`;
- route tenant khác nhau giữa signals;
- metrics-generator label mapping sai.

Expected detection:

- correlation canary fail;
- schema/identity policy alert;
- sampling decision metrics thay đổi;
- dashboard giải thích expired target;
- rollout tự dừng.

Các lỗi này thường im lặng hơn pod crash và dễ dẫn on-call đến kết luận sai.

---

## 49. Degraded modes

Khi quá tải, không phải mọi telemetry có cùng giá trị.

Thứ tự bảo vệ gợi ý:

```text
1. paging/SLO/security-critical metrics
2. platform meta-monitoring và synthetic canaries
3. error traces/logs có kiểm soát
4. operational metrics/logs
5. debug logs, success traces, high-frequency profiles
```

Degraded actions:

- giảm debug log;
- giảm success-trace sampling;
- hạ profile frequency;
- drop attributes đắt nhưng giữ identity;
- giới hạn expensive queries;
- ưu tiên rule/alert queries;
- tạm read-only một số chức năng;
- rút ngắn retry cho permanent errors.

Policy phải tự động, quan sát được, có expiry và recovery hysteresis; tránh flap.

---

## 50. Fail-open hay fail-closed?

Với application telemetry thông thường:

```text
telemetry exporter down
  → application vẫn phục vụ
  → telemetry buffer/drop có kiểm soát
```

Đây thường là fail-open cho business request.

Nhưng không có một đáp án cho mọi signal:

| Use case | Quyết định cần contract |
|---|---|
| Debug trace | thường fail-open |
| SLO metric | bảo vệ mạnh nhưng không block request |
| Security audit bắt buộc | có thể cần durable local queue hoặc fail-closed theo policy |
| Billing event | không nên giả làm telemetry best-effort |

Nếu một event yêu cầu exactly-once/durability nghiệp vụ, hãy dùng transactional/event
pipeline phù hợp, không đặt kỳ vọng đó lên observability exporter rồi block application vô
hạn.

---

## 51. Loki Canary trong experiment

Loki Canary liên tục tạo log đã biết và query lại.

Runbook nên theo dõi:

- `missing`;
- `unexpected`;
- `duplicate`;
- response/query errors;
- propagation latency;
- metric test deviation;
- spot-check từ memory sang long-term store.

Thiết kế:

```text
canary writer ở failure domain A
reader/query từ failure domain B
critical result export sang meta-monitor độc lập
```

Nếu writer và Loki cùng chết, “không thấy missing” có thể chỉ vì canary không còn emit. Cần
heartbeat của chính canary.

---

## 52. Tempo Vulture trong experiment

Tempo Vulture tạo trace có cấu trúc dự đoán được rồi validate:

- read by trace ID;
- search;
- TraceQL metrics;
- missing spans;
- request failures;
- kết quả metrics không chính xác.

Hai cách dùng:

- **continuous mode**: theo dõi propagation/correctness liên tục;
- **validation mode**: chạy job hữu hạn sau deploy/migration/experiment.

Validation job phải có timeout và lưu kết quả. “Job completed” không đủ; cần parse error
metrics/result và gắn với `experiment_id`.

---

## 53. Synthetic canary cho Mimir

Một thiết kế đơn giản:

```text
writer:
  counter sequence tăng đều
  gauge emitted timestamp
  labels bounded: tenant, region, canary_id

reader:
  instant/range query
  kiểm tra freshness, gaps, duplicates/resets
  kiểm tra recording rule
```

Không chỉ query `up`. Tạo metric riêng qua đúng remote-write/OTLP path production dùng.

Kiểm tra ba lớp:

1. raw sample;
2. recording rule;
3. alert/notification heartbeat.

Đặt canary ở nhiều zone/tenant nếu cần phân biệt write path, query path và isolation.

---

## 54. External blackbox probes

Blackbox probe nhìn từ ngoài:

- DNS resolve;
- TCP/TLS;
- HTTP status;
- authentication;
- endpoint latency;
- API query có expected response.

Prometheus Blackbox Exporter có thể cung cấp `probe_success` và timing theo phase.

Probe hữu ích:

```text
outside cluster
  → Grafana login/API
  → Mimir/Loki/Tempo query gateway
  → notification receiver
```

Blackbox không thay whitebox metrics. Nó nói người dùng không truy cập được; internal
telemetry giúp giải thích vì sao.

---

## 55. Chaos Mesh, Litmus và fault proxy

Chọn tool theo fault và safety:

| Tool/pattern | Phù hợp |
|---|---|
| Chaos Mesh | pod/network/stress/I/O/time và workflow Kubernetes |
| LitmusChaos | experiment/workflow với probes/steady-state |
| Toxiproxy/fault proxy | latency, reset, timeout, response behavior ở một hop |
| Application feature flag | lỗi semantic/nghiệp vụ có kiểm soát |
| Cloud fault service | zone/network/managed dependency theo provider |

Tool không định nghĩa experiment. Manifest tốt vẫn cần:

- hypothesis;
- exact selector;
- duration;
- abort;
- cleanup;
- evidence.

Ưu tiên fault nhỏ, có thể đảo ngược và quan sát được.

---

## 56. Kubernetes PDB làm được và không làm được gì

PodDisruptionBudget giới hạn số pod đồng thời unavailable do **voluntary disruptions** như
node drain.

PDB không bảo vệ đầy đủ khỏi:

- node crash;
- kernel panic;
- network partition;
- OOM;
- application crash;
- zone outage;
- storage failure;
- direct pod deletion trong mọi trường hợp.

Vì vậy:

```text
PDB configured
  ≠ HA proven
```

Chaos test cần xác nhận capacity/quorum thật. PDB quá chặt cũng có thể chặn maintenance;
kiểm tra cả safety và operability.

---

## 57. Security của chaos platform

Chaos controller có quyền mạnh nên cần:

- namespace/target allowlist;
- RBAC tối thiểu;
- admission policy;
- signed/versioned manifests;
- audit log;
- approval cho production;
- maximum duration;
- concurrency limit;
- deny host/root/broad selectors;
- secret redaction;
- network egress control.

Tách vai trò:

```text
author experiment
  ≠ approve production
  ≠ execute emergency abort
```

Không cho một workflow tùy ý chạy shell privileged trên mọi node chỉ vì tiện inject fault.

---

## 58. Staging, canary production và production

Staging phù hợp:

- destructive faults;
- schema/config mutation;
- disk full;
- bucket disposable;
- lần đầu chạy experiment.

Production cần vì staging thường khác:

- volume;
- topology;
- quota;
- managed dependencies;
- traffic shape;
- operational process.

Tiến cấp:

```text
local/lab
  → staging
  → production synthetic tenant
  → one replica/zone canary
  → bounded shared-path experiment
```

Mỗi cấp chỉ mở rộng khi cấp trước đạt exit criteria và phát hiện đã được sửa.

---

## 59. CI, post-deploy và continuous verification

Phân lớp:

| Stage | Test |
|---|---|
| CI | lint config, schema, rules, chaos manifest |
| Ephemeral | synthetic write/read/correlation |
| Staging | fault injection đầy đủ |
| Post-deploy | Tempo Vulture validation, Loki/Mimir canary |
| Continuous | small safe network/pod experiments |
| Scheduled | zone/DR/game day |

Không đưa fault có blast radius lớn vào mỗi commit.

Post-deploy gate:

```text
rollout canary
  → synthetic data visible
  → correlation valid
  → rule/notification test
  → no queue/drop regression
  → continue rollout
```

Rollback khi validation sai, kể cả mọi pod đều Ready.

---

## 60. Game day

Game day kiểm tra cả hệ thống xã hội-kỹ thuật.

Vai trò:

| Vai trò | Trách nhiệm |
|---|---|
| Coordinator | timeline, quyết định start/stop |
| Injector | áp/remove fault |
| Observer | thu bằng chứng, không can thiệp |
| On-call | xử lý như incident |
| Safety | theo dõi abort conditions |
| Scribe | ghi quyết định và mốc thời gian |

Kịch bản không nên tiết lộ toàn bộ triệu chứng cho responder, nhưng safety team phải biết
fault chính xác.

Sau game day đo:

- time to detect;
- time to understand;
- time to mitigate;
- time to recover;
- runbook gaps;
- telemetry gaps;
- coordination gaps.

---

## 61. Disaster recovery và restore exercise

Backup tồn tại chưa chứng minh restore được.

Exercise:

```text
declare recovery point
  → provision isolated recovery environment
  → restore config/secrets/metadata/data
  → validate integrity
  → synthetic write/query
  → validate rules/dashboards/correlation
  → measure RTO/RPO
  → destroy isolated environment safely
```

Kiểm tra:

- object/version compatibility;
- encryption keys;
- IAM/DNS;
- tenant mapping;
- rule/dashboard Git source;
- partial restore;
- query history;
- new writes sau restore;
- data gap đúng RPO.

Không ghi đè production trong một restore drill. Dùng environment/bucket/tenant cô lập.

---

## 62. RTO, RPO và durability window

| Khái niệm | Câu hỏi |
|---|---|
| RTO | mất bao lâu để dịch vụ dùng lại được? |
| RPO | chấp nhận mất dữ liệu tới thời điểm nào? |
| Buffering window | queue hấp thụ outage bao lâu trước drop? |
| Detection time | mất bao lâu biết có lỗi/gap? |
| Drain time | backlog mất bao lâu để về bình thường? |

Ví dụ:

```text
buffering window = 10 phút
backend outage   = 8 phút
drain time       = 6 phút
freshness SLO    = 2 phút
```

Dù không mất dữ liệu, freshness SLO vẫn bị vi phạm trong recovery. “Zero loss” không đồng
nghĩa service quality đạt yêu cầu.

---

## 63. Evidence và scoring

Mỗi experiment lưu:

- manifest/config commit;
- approver;
- exact targets;
- start/stop timestamps;
- baseline;
- fault confirmation;
- dashboards/query snapshots;
- synthetic sequence result;
- alerts/notifications;
- abort/rollback actions;
- recovery completion;
- kết luận và follow-up.

Score:

| Kết quả | Ý nghĩa |
|---|---|
| Pass | hypothesis và recovery criteria đạt |
| Pass with observation | đạt nhưng có rủi ro/cải tiến |
| Failed safely | hypothesis sai, guardrail dừng đúng |
| Unsafe failure | blast radius/abort/visibility sai |
| Inconclusive | fault hoặc measurement không được xác nhận |

“Failed safely” tạo kiến thức có giá trị; không nên sửa dashboard rồi ghi thành pass.

---

## 64. Learning loop, checklist và câu hỏi tự kiểm tra

### Learning loop

```text
experiment
  → evidence
  → finding
  → owner + deadline
  → code/runbook/capacity change
  → regression experiment
  → close
```

Không đóng finding chỉ vì tạo ticket.

### Checklist production

- [ ] Steady state đo từ góc nhìn consumer.
- [ ] Write/query/freshness/correctness/alert SLO tách rõ.
- [ ] Synthetic sequence phát hiện missing/duplicate.
- [ ] Meta-monitoring có failure domain đủ độc lập.
- [ ] Exact targets và blast radius đã xác nhận.
- [ ] Abort conditions có automation.
- [ ] Kill switch đã thử.
- [ ] Control group tồn tại khi phù hợp.
- [ ] Fault có timeout tự dừng.
- [ ] Queue/retry/disk capacity đã tính.
- [ ] Degraded mode ưu tiên critical signals.
- [ ] Notification test dùng sandbox.
- [ ] Stateful/data-destructive faults chỉ ở môi trường disposable.
- [ ] Recovery gồm backlog drain, không chỉ pod Ready.
- [ ] Evidence gắn `experiment_id`.
- [ ] Finding có owner/deadline và regression test.

### Câu hỏi tự kiểm tra

1. Vì sao pod Ready không phải steady state đủ tốt?
2. Write accepted khác query visible thế nào?
3. Freshness khác availability ra sao?
4. Sequence ID phát hiện những lỗi nào?
5. Vì sao meta-monitoring cùng backend tạo shared fate?
6. Experiment contract cần những trường tối thiểu nào?
7. Khi mất visibility, nên tiếp tục hay abort?
8. Control group giúp loại bỏ nhiễu thế nào?
9. Network latency khác partition về hành vi queue ra sao?
10. Persistent queue vẫn có thể mất dữ liệu khi nào?
11. Kafka thêm durability nhưng tạo failure modes nào?
12. Clock skew làm canary báo sai ra sao?
13. Vì sao không retry vô hạn lỗi 400/401?
14. Cardinality spike nên bị cô lập thế nào?
15. Query rejection khi quá tải có thể là hành vi đúng không?
16. Mimir write ack có chứng minh recent read không?
17. Loki Canary đo gì ngoài endpoint health?
18. Tempo Vulture kiểm tra những query path nào?
19. PDB không bảo vệ khỏi failure nào?
20. Fail-open cho telemetry có luôn đúng không?
21. Degraded mode nên giữ signal nào trước?
22. RTO khác RPO và buffering window thế nào?
23. Tại sao zero loss vẫn có thể vi phạm freshness SLO?
24. “Failed safely” có giá trị gì?
25. Khi nào một finding được coi là đóng?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Chaos engineering

- [Principles of Chaos Engineering](https://principlesofchaos.org/)
- [Chaos Mesh basic features](https://chaos-mesh.org/docs/basic-features/)
- [Chaos Mesh workflows](https://chaos-mesh.org/docs/create-chaos-mesh-workflow/)
- [LitmusChaos](https://litmuschaos.io/)

### OpenTelemetry

- [Collector resiliency](https://opentelemetry.io/docs/collector/resiliency/)
- [Collector internal telemetry](https://opentelemetry.io/docs/collector/internal-telemetry/)
- [Collector troubleshooting](https://opentelemetry.io/docs/collector/troubleshooting/)
- [OpenTelemetry Demo failure scenarios](https://opentelemetry.io/docs/demo/feature-flags/)

### Grafana stack

- [Loki Canary](https://grafana.com/docs/loki/latest/operations/loki-canary/)
- [Loki troubleshooting](https://grafana.com/docs/loki/latest/operations/troubleshooting/troubleshoot-operations/)
- [Tempo Vulture](https://grafana.com/docs/tempo/latest/operations/tempo-vulture/)
- [Tempo troubleshooting](https://grafana.com/docs/tempo/latest/troubleshooting/)
- [Mimir runbooks](https://grafana.com/docs/mimir/latest/manage/mimir-runbooks/)
- [Mimir HTTP API](https://grafana.com/docs/mimir/latest/references/http-api/)

### Kubernetes và Prometheus

- [Kubernetes PodDisruptionBudget](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [Prometheus multi-target exporter pattern](https://prometheus.io/docs/guides/multi-target-exporter/)
- [Prometheus Blackbox Exporter](https://github.com/prometheus/blackbox_exporter)

### Chủ đề tiếp theo

Sau Chaos Engineering for Observability, chủ đề mở rộng tiếp theo là:

> **Observability Platform Engineering – self-service onboarding, control plane,
> golden paths, multi-tenancy và platform SLOs.**
>
> Đọc tiếp:
> [Observability Platform Engineering](observability_platform_engineering.md).

---

*Cập nhật lần cuối: 2026-07-30*
