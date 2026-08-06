# Capacity Planning & Performance Efficiency Observability – Từ Demand đến Safe Headroom

> Mục tiêu của bài này là biến demand, queue, saturation, throughput, latency và resource
> telemetry thành capacity model có thể kiểm chứng; nhờ đó biết hệ thống chịu được bao nhiêu,
> bottleneck ở đâu, cần scale lúc nào và còn đủ headroom cho burst/failover hay không.
>
> Baseline tham chiếu: Google SRE capacity/overload guidance, Kubernetes autoscaling hiện hành
> (stable v1.36), KEDA 2.20, Prometheus histogram/metric guidance và các nguyên lý queueing phổ
> biến. Công thức là mô hình khởi đầu; quyết định production phải được hiệu chỉnh bằng load test.
>
> Load test, traffic replay và failure injection có thể tạo outage hoặc xử lý dữ liệu thật.
> Chỉ chạy với authorization, rate/cost limit, synthetic/redacted data, abort condition,
> isolation và kế hoạch khôi phục.
>
> Nên đọc trước:
> [Metrics Design](metrics_design.md),
> [Alerting Strategy & SLO](alerting_strategy.md),
> [Kubernetes Observability](kubernetes_observability.md),
> [Chaos Engineering](chaos_engineering_observability.md) và
> [Cloud Cost & Sustainability](cloud_cost_sustainability_observability.md).

---

## 1. Capacity không đồng nghĩa CPU

CPU 40% không chứng minh còn 60% capacity. Bottleneck có thể là:

- connection/thread pool;
- memory/GC;
- disk IOPS;
- network/NAT port;
- database lock;
- downstream quota;
- queue age;
- serialized critical section.

Capacity phải được định nghĩa bằng workload hoàn tất trong SLO, không bằng một resource.

## 2. Demand, load, work, throughput và capacity

- **Demand:** lượng công việc muốn vào.
- **Admitted load:** phần được hệ thống nhận.
- **Work in progress:** đang queue/chạy.
- **Throughput:** hoàn tất mỗi đơn vị thời gian.
- **Capacity:** throughput tối đa còn đạt quality/SLO.

Khi overload, throughput có thể không tăng dù demand tăng.

## 3. Bottleneck quyết định capacity

Hệ nối tiếp chỉ nhanh bằng constraint hiện tại. Scale frontend không giúp nếu DB write lock là
bottleneck.

```text
effective capacity = min(capacity của các dependency bắt buộc)
```

Bottleneck có thể di chuyển sau tối ưu; đo lại toàn path.

## 4. Performance efficiency

Efficiency hỏi bao nhiêu useful work trên resource/time/cost:

```text
successful outcomes / core-hour
successful outcomes / GB-hour
successful outcomes / currency unit
```

Tối ưu throughput bằng bỏ validation làm correctness xấu không phải efficiency.

## 5. SLO là điều kiện biên

Capacity test cần tiêu chí:

- success/correctness;
- p95/p99 latency;
- freshness/deadline;
- durability;
- resource safety;
- cost;
- degraded behavior.

“Chịu 20k RPS” vô nghĩa nếu 10% request timeout.

## 6. Workload identity contract

Phân loại bounded:

- operation/journey;
- workload class: online, async, batch;
- priority;
- payload/complexity bucket;
- region;
- protocol;
- dependency path.

Không trộn request nhẹ/nặng thành một RPS trung bình.

## 7. Chọn work unit

Work unit có thể là request, transaction, message, byte, row, token hoặc task. Khi complexity
khác nhau, dùng weighted unit:

```text
work_units = Σ count(class_i) × calibrated_weight_i
```

Weight cần benchmark/version; không biến metric thành black box.

## 8. Arrival rate, service time và concurrency

Ba đại lượng:

- `λ`: arrival/throughput rate;
- `W`: time trong hệ thống;
- `L`: work in system/concurrency.

Đo theo cùng boundary và window. Client concurrency không bằng server active requests nếu có
queue/retry/cache.

## 9. Little's Law

Ở trạng thái ổn định:

```text
L = λ × W
```

Ví dụ 1.000 request/s và trung bình 0,2 s tạo khoảng 200 request trong hệ thống. Luật giúp
sanity-check metric, nhưng không áp dụng mù khi arrival/queue đang tăng không ổn định.

## 10. Utilization và saturation

- **Utilization:** phần thời gian/capacity resource bận.
- **Saturation:** công việc phải chờ vì resource không theo kịp.

CPU usage cao nhưng queue thấp có thể ổn; utilization vừa nhưng run queue/lock wait cao có thể
đã nghẽn. Luôn đo wait/backlog.

## 11. Queue là bộ nhớ của overload

Queue hấp thụ burst nhưng không tạo capacity. Theo dõi:

- depth;
- oldest age;
- enqueue/dequeue rate;
- wait time;
- drop/expiry;
- retry;
- priority/starvation.

Nếu arrival dài hạn lớn hơn service rate, queue chỉ trì hoãn failure.

## 12. Phân rã latency

```text
total =
  client + network + queue + service + dependency + serialization
```

Tách queue time khỏi run time và attempt khỏi logical operation. Tổng p99 từng stage không
bằng p99 end-to-end.

## 13. Tail latency

Tail tăng do queueing, GC, lock, cache miss, fan-out, retry, noisy neighbor hoặc mixed
complexity. Average bình thường có thể che p99 xấu.

Theo dõi histogram và exemplars/traces ở tail. Đừng thêm high-cardinality payload vào labels.

## 14. Coordinated omission

Load generator closed-loop chờ response rồi mới gửi tiếp sẽ tự giảm arrival khi server chậm,
đánh giá thấp latency đúng lúc overload.

Ưu tiên open-loop/constant-arrival test khi mô phỏng demand độc lập, ghi cả intended và actual
send rate, dropped generator work và client saturation.

## 15. Throughput curve

Tăng load theo step và vẽ:

```text
demand → admitted → successful throughput
                  ↘ latency/error/saturation
```

Sau một điểm, throughput phẳng hoặc giảm trong khi latency/error tăng. Capacity nằm trước vùng
vi phạm SLO, không phải đỉnh throughput tuyệt đối.

## 16. Knee point

Knee là vùng thêm ít load làm latency/saturation tăng nhanh. Xác định bằng curve nhiều lần,
không từ một threshold CPU cố định.

Operating point nên thấp hơn knee đủ headroom cho variance, failover và scale latency.

## 17. Saturation signals

Tùy resource:

- CPU run queue/throttling;
- memory pressure/OOM/GC;
- disk queue/latency;
- network drops/retransmit;
- pool active/wait;
- DB lock/connections;
- queue age;
- downstream quota/throttle.

Chọn signal gần constraint, không chỉ generic utilization.

## 18. Headroom

```text
headroom ratio =
  (safe capacity - current demand) / safe capacity
```

`safe capacity` đã gồm SLO và safety margin. Headroom âm nghĩa demand vượt mức an toàn dù hệ
thống chưa outage.

## 19. N+1 và zone-failure headroom

Capacity bình thường phải chịu mất instance/node/zone theo fault model:

```text
remaining capacity after failure ≥ peak admitted demand
```

Tính cả rebalance, warm-up và dependency. “N+1 instance” có thể không đủ nếu một zone chứa hơn
một instance.

## 20. Rollout, maintenance và failover

Reserved headroom cho:

- rolling update;
- node drain;
- compaction/reindex;
- backup;
- schema migration;
- cache warm-up;
- region failover;
- incident debug overhead.

Không bán toàn bộ spare capacity như idle nếu nó phục vụ resilience contract.

## 21. Workload profile

Mô tả:

- operation mix;
- payload/complexity;
- read/write ratio;
- cache hit;
- data size/skew;
- concurrency;
- client behavior;
- dependency latency;
- think time.

Benchmark sai mix cho kết quả capacity sai dù tool chạy chính xác.

## 22. Seasonality

Demand theo minute/hour/day/week, campaign, billing cycle, event và timezone. Dùng same-period
baseline, peak factor và calendar marker.

Peak trung bình tháng làm mất burst. Forecast cần cả volume và mix/complexity.

## 23. Burst

Đặc trưng burst:

- amplitude;
- duration;
- rise rate;
- recurrence;
- correlation giữa region;
- backlog/deadline.

Autoscaler phản ứng sau signal nên burst ngắn cần buffer/warm capacity/admission, không chỉ scale.

## 24. Growth forecast

Nối business driver với technical work:

```text
users × actions/user × fan-out × retry factor × bytes/action
```

Forecast service riêng lẻ phải tính feature/release thay đổi work per action, không chỉ tăng
RPS lịch sử.

## 25. Scenario planning

Ít nhất:

- expected;
- high growth;
- launch/marketing spike;
- dependency chậm;
- zone/region failure;
- delayed scale-up;
- retry storm;
- data skew.

Ghi assumption, probability/risk và action trigger.

## 26. Forecast accuracy

Đo forecast error theo horizon và direction. Under-forecast tạo outage; over-forecast tạo waste,
chi phí hai phía khác nhau.

Review bias, interval coverage và nguyên nhân: demand, mix, price, release hay model. Không
chỉ báo “forecast sai”.

## 27. Capacity model

Mô hình khởi đầu:

```text
required replicas =
  peak work units / safe work units per replica
  × failure factor
  × growth factor
```

Round theo placement/zone và thêm scale latency. Sau đó validate bằng load test.

## 28. Resource-to-capacity ratio

Calibrate:

```text
successful work units per core/GB/instance
```

Ratio thay đổi theo code, runtime, data, hardware và dependency. Google SRE khuyên dùng load
test thay tradition vì con số cũ có thể không còn đúng.

## 29. Benchmark

Benchmark micro chỉ đo một component; end-to-end đo system constraint. Ghi:

- code/config/artifact;
- hardware/runtime;
- dataset;
- workload profile;
- generator;
- warm-up;
- result;
- variance.

Không so hai run khác boundary.

## 30. Các loại load test

| Test | Mục đích |
|---|---|
| Baseline | xác minh hành vi bình thường |
| Load | target demand |
| Stress | tìm limit/knee |
| Spike | rise-rate/burst |
| Soak | leak/degradation dài |
| Capacity | safe throughput trong SLO |
| Failover | capacity sau fault |

Mỗi test có abort condition.

## 31. Synthetic và traffic replay

Synthetic dễ kiểm soát nhưng có thể thiếu skew. Replay gần thực tế nhưng phải redact, bỏ
credential/side effect và time-shift an toàn.

Không replay write/payment/email vào production dependency. Dùng sandbox/stub hoặc idempotent
test account được phép.

## 32. Warm-up và steady state

JIT, cache, connection pool, autoscaler và data page cache làm kết quả đầu khác steady state.
Định nghĩa warm-up, measurement window và reset.

So cả cold-start/recovery nếu đó là customer path; không loại warm-up chỉ để số đẹp.

## 33. Test overload và failure

Đẩy qua rated capacity trong môi trường kiểm soát để biết:

- hệ degrade thế nào;
- queue/drop ở đâu;
- có recovery không;
- retry có khuếch đại không;
- alert/runbook hoạt động không;
- data có corrupt không.

Rated capacity không đáng tin nếu chưa thử ngoài giới hạn.

## 34. Admission control

Reject sớm khi resource không đủ tốt hơn nhận rồi timeout. Decision có workload class,
priority, estimated cost, capacity state và reason.

Không tin priority do client tự gán. Giữ đường control/health/recovery khỏi bị chặn.

## 35. Load shedding

Drop một phần load để bảo vệ useful throughput. Chọn:

- optional work;
- stale/low-priority request;
- duplicate/retry;
- expensive feature;
- consistent client subset.

Theo dõi shed rate, reason, affected outcome và recovery. Tránh random làm mọi user đều có trải
nghiệm dở nếu consistent subset an toàn hơn.

## 36. Graceful degradation

Ví dụ:

- trả cache stale có marker;
- bỏ recommendation phụ;
- giảm search breadth;
- chuyển async;
- giảm fidelity;
- read-only mode.

Degraded response phải correct/safe trong contract và quan sát riêng, không tính chung success.

## 37. Retry amplification

```text
attempt load =
  logical load × average attempts
```

Timeout làm client retry, tăng load và gây cascade. Dùng deadline, exponential backoff + jitter,
retry budget, idempotency và upstream shedding. Theo dõi logical operation và attempt riêng.

## 38. Backpressure

Downstream chậm phải truyền tín hiệu upstream qua bounded queue, credit/window, rate limit hoặc
pull. Nếu không, memory/queue tăng tới crash.

Đo propagation delay, blocked producer, queue age và dropped work. Backpressure không thay
capacity; nó kiểm soát failure.

## 39. Chọn autoscaling signal

Signal nên:

- gần demand/constraint;
- có quan hệ monotonic với replicas;
- đủ mới;
- bounded cardinality;
- không biến mất lúc cần scale;
- khó bị spoof;
- có fallback.

CPU không phù hợp nếu bottleneck là queue hoặc external quota.

## 40. Horizontal Pod Autoscaler

HPA định kỳ điều chỉnh replicas theo resource/custom/external metric. Quan sát:

- current/desired replicas;
- metric current/target;
- conditions/reason;
- recommendation;
- scale event;
- pending/not-ready Pod;
- SLO sau scale.

Metric missing không được mặc định hiểu là demand thấp.

## 41. HPA metric semantics

Per-pod utilization phù hợp khi mỗi replica chia tải tương đối đều. Total queue depth cần target
items per replica và service rate/deadline.

Tránh autoscale theo latency nếu latency tăng sau saturation và scale quá chậm; kết hợp leading
load signal với SLO guardrail.

## 42. KEDA 2.20

KEDA đưa event-source metric cho HPA và quản lý activation/scale-to-zero cho workload; bản
stable latest trong baseline là 2.20.

Theo dõi scaler authentication, polling, metric freshness/error, active state, HPA handoff,
cooldown và source lag. Scaler unavailable cần fallback rõ.

## 43. Scale-to-zero

Tiết kiệm tài nguyên nhưng tạo activation/cold-start latency. Cần event source tồn tại ngoài
workload để đánh thức.

Đo zero→one, one→ready, backlog growth, first-success latency và lost event. CPU/memory của Pod
đã về zero không thể tự là wake-up signal.

## 44. Vertical Pod Autoscaler

VPA là add-on, đưa recommendation/điều chỉnh request CPU/memory theo policy. Quan sát
recommendation, applied target, eviction/recreate, min/max và OOM/throttling sau đổi.

Kubernetes v1.36 hỗ trợ in-place Pod resize ở core, nhưng tài liệu hiện hành nêu VPA chưa hỗ
trợ áp dụng resize in-place; không giả định VPA không restart Pod.

## 45. Node autoscaling

Workload replica tăng không giúp nếu Pod pending vì thiếu node. Theo dõi:

- unschedulable reason;
- node provision time;
- quota/stockout;
- placement constraint;
- initialization;
- consolidation;
- disruption;
- allocatable sau scale.

Node ready chưa chắc application ready.

## 46. HPA, VPA và node autoscaler tương tác

Loop:

```text
metric → HPA replicas → Pod requests → scheduler
       → node autoscaler → node ready → Pod ready → metric
```

VPA đổi request có thể đổi HPA utilization và bin packing. Mô phỏng/tách ownership để tránh các
controller đánh nhau.

## 47. Stabilization, tolerance và hysteresis

Metric nhiễu gây scale flap. HPA v2 có behavior/stabilization window; default scale-down window
hiện là 300 giây khi không cấu hình.

Đặt scale-up/down rate, cooldown và tolerance theo workload. Window quá dài giữ waste; quá ngắn
gây thrash/cold cache.

## 48. Scaling latency

Phân rã:

```text
detect → decide → provision → schedule → start
       → warm → ready → receive traffic
```

Headroom/buffer phải chịu demand trong tổng thời gian này. Autoscaler nhanh trên giấy nhưng
image pull hoặc node stockout chậm vẫn làm SLO burn.

## 49. Min, max, quota và external limit

`minReplicas` giữ availability/warmth; `maxReplicas` bảo vệ cost/downstream. Max quá thấp gây
overload, quá cao có thể DDoS database.

Correlate namespace/provider quota, IP/connection, API rate limit và license. Alert khi desired
replicas bị cap.

## 50. Scheduling và bin packing

Request quá cao tạo stranded capacity; quá thấp tạo overcommit/noisy neighbor. Theo dõi
allocatable/request/usage, fragmentation, affinity, topology spread, taint và priority.

Tối ưu bin packing phải giữ zone-failure, rollout và system-daemon headroom.

## 51. CPU capacity

Đo usage, throttling, run queue, steal, frequency và work/core. Multi-threaded speedup bị giới
hạn bởi serial section và contention.

Benchmark cùng CPU family/runtime; một “core” không luôn cùng hiệu năng.

## 52. Memory capacity

Theo dõi working set, RSS/heap/native, page cache, allocation/GC, pressure, swap và OOM. Leak
thường chỉ hiện ở soak test.

Capacity theo peak concurrent working set + reserve, không theo free memory tức thời.

## 53. Disk và I/O capacity

Đo IOPS/bytes, latency, queue depth, utilization, fs capacity/inode, burst credit, compaction
và write amplification.

Disk còn nhiều GB vẫn có thể hết throughput. Backup/recovery và compaction thường tạo peak
khác traffic.

## 54. Network capacity

Đo bandwidth, packets, connections, retransmission/drop, conntrack/NAT port, handshake và
load-balancer limit.

Bytes/s thấp không chứng minh còn capacity nếu packet rate hoặc connection churn là constraint.

## 55. Database, cache và messaging

Dependency constraint:

- DB connections/locks/IO/replication;
- cache memory/hot key/eviction;
- broker partitions/ISR/disk;
- consumer service rate/lag;
- third-party quota.

Scale application phải có dependency budget; fan-out nhân tải downstream.

## 56. Multi-tenant fairness

Capacity tổng đủ nhưng tenant nhỏ vẫn chậm nếu tenant lớn chiếm queue/pool. Theo dõi aggregate
bounded class, heavy hitters và victim SLI.

Áp dụng quota, weighted fairness và per-tenant concurrency có policy; không dùng tenant ID làm
Prometheus label không giới hạn.

## 57. Cost và sustainability

Headroom có giá trị reliability; idle không phải lúc nào waste. Tối ưu:

```text
safe successful capacity / cost / energy / carbon
```

Right-size/autoscale giữ SLO/failure reserve. Scale-out nhiều instance nhỏ và scale-up ít
instance lớn cần benchmark trên cùng workload.

## 58. Dashboard

Các tầng:

1. demand/admitted/successful throughput;
2. SLO/latency/error;
3. queue/saturation/bottleneck;
4. current/safe capacity/headroom;
5. replicas/nodes/autoscaler timeline;
6. forecast/scenario;
7. cost/efficiency.

Overlay release, incident, campaign và failure.

## 59. Alerting

Alert có hành động:

- headroom thấp với forecast breach;
- oldest queue age/deadline;
- throughput collapse;
- autoscaler desired bị cap;
- metric/scaler stale;
- Pod pending/node stockout;
- failure reserve không đủ;
- retry amplification;
- SLO burn do saturation.

Không page từ CPU cao đơn lẻ.

## 60. Capacity review

Cadence tuần/tháng hoặc trước peak:

- demand/mix/growth;
- safe capacity calibration;
- bottleneck;
- failure headroom;
- autoscaler event;
- forecast error;
- quota/commitment;
- planned release/migration;
- action/owner/date.

Review assumption, không chỉ dashboard.

## 61. Launch readiness

Trước launch:

- expected/peak scenario;
- load test gần artifact production;
- dependency confirmation;
- quota increase;
- scale latency;
- cache/data warm;
- overload/degraded mode;
- rollback/feature flag;
- dashboard/alert/on-call.

Day-one traffic có thể khác steady state.

## 62. Automation safety

Automated scaling/right-sizing cần:

- min/max/rate bound;
- trusted fresh signal;
- SLO/cost guardrail;
- approval theo blast radius;
- dry-run;
- change event;
- rollback;
- circuit breaker;
- manual override có expiry.

Không để anomaly telemetry scale vô hạn.

## 63. Reconcile model với production

Sau change/peak:

```text
predicted demand/capacity ↔ observed
load-test curve          ↔ production curve
desired replicas         ↔ ready/effective capacity
forecast cost            ↔ billed cost
```

Version model, lưu residual và cập nhật weight/resource ratio bằng evidence.

## 64. Workshop, checklist và câu hỏi tự kiểm tra

Workshop: chọn một API/consumer, dựng workload profile, Little's Law sanity check, throughput
curve, safe capacity/headroom rồi thử HPA/KEDA dưới burst và mất một zone giả lập.

- [ ] Capacity gắn với successful work trong SLO?
- [ ] Demand khác admitted/throughput?
- [ ] Queue age và saturation được đo?
- [ ] Load generator tránh coordinated omission?
- [ ] Failure/rollout headroom tồn tại?
- [ ] Scale latency được phân rã?
- [ ] HPA/KEDA metric có freshness/fallback?
- [ ] Max scale bảo vệ downstream/cost?
- [ ] Model được reconcile sau test?

Câu hỏi:

1. CPU thấp nhưng hệ thống hết capacity khi nào?
2. Little's Law dùng và bị sai trong trường hợp nào?
3. Knee point khác throughput cực đại ra sao?
4. Vì sao queue không tạo capacity?
5. Scale-to-zero cần signal đánh thức ở đâu?
6. HPA, VPA và node autoscaler có thể tương tác xấu thế nào?
7. Headroom nào không nên bị coi là waste?

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Capacity và overload

- [Google SRE – Production Services Best Practices](https://sre.google/sre-book/service-best-practices/)
- [Google SRE – Addressing Cascading Failures](https://sre.google/sre-book/addressing-cascading-failures/)
- [Kubernetes autoscaling workloads](https://kubernetes.io/docs/concepts/workloads/autoscaling/)
- [Kubernetes HPA v2 API](https://kubernetes.io/docs/reference/kubernetes-api/autoscaling/horizontal-pod-autoscaler-v2/)
- [Kubernetes Vertical Pod Autoscaling](https://kubernetes.io/docs/concepts/workloads/autoscaling/vertical-pod-autoscale/)

### Event-driven scaling

- [KEDA 2.20 scalers](https://keda.sh/docs/2.20/scalers/)
- [KEDA 2.20 deployment scaling](https://keda.sh/docs/2.20/concepts/scaling-deployments/)

Chủ đề tiếp theo:
[Storage & Object Storage Observability](storage_object_storage_observability.md) – durability,
consistency, replication, lifecycle, capacity, data integrity, restore và cost của
object/file/block storage.

---

*Cập nhật lần cuối: 2026-07-30*
