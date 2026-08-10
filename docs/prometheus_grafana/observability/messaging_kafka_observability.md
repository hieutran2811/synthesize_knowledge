---
title: "Messaging & Kafka Observability – Từ Producer đến Business Outcome"
topic: prometheus_grafana
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 11
---
# Messaging & Kafka Observability – Từ Producer đến Business Outcome

> Thuật ngữ: [Glossary](../glossary.md).

> Mục tiêu của bài này là quan sát một message từ lúc được tạo, ghi nhận bởi Kafka, chờ trong
> partition, được consumer xử lý cho đến khi tạo ra kết quả nghiệp vụ. Consumer lag chỉ là một
> lát cắt; nó không tự chứng minh dữ liệu còn mới, xử lý đúng hay không bị trùng.
>
> Baseline tham chiếu: **Apache Kafka 4.3.x**, KRaft, Prometheus JMX Exporter và
> OpenTelemetry Semantic Conventions 1.43.x. Tên metric sau khi qua exporter phụ thuộc rule;
> luôn kiểm tra JMX và `/metrics` của chính phiên bản đang chạy.
>
> Không chạy lệnh reset offset, reassignment, leader election, xóa consumer group/topic,
> thay retention hoặc bật remote JMX không bảo vệ trên production chỉ để điều tra.
>
> Nên đọc trước:
> [Kafka Architecture](../../kafka/fundamentals/architecture.md),
> [Producer](../../kafka/fundamentals/producers.md),
> [Consumer](../../kafka/fundamentals/consumers.md),
> [Kafka Production](../../kafka/operations/production.md),
> [Metrics Design](metrics_design.md) và
> [OpenTelemetry Deep Dive](opentelemetry_deep_dive.md).

---

## 1. Vì sao messaging observability khó?

HTTP request thường có điểm bắt đầu và kết thúc gần nhau. Message có thể:

- được batch trước khi gửi;
- chờ trong broker nhiều giờ;
- được nhiều consumer group đọc độc lập;
- retry hoặc vào DLQ;
- được replay;
- tạo thêm message;
- hoàn tất sau khi producer request đã kết thúc.

“Kafka healthy” và “business workflow healthy” là hai câu hỏi khác nhau.

---

## 2. Vòng đời end-to-end

```text
business event
  → serialize
  → producer buffer/batch
  → Kafka produce
  → leader + replicas
  → partition log
  → consumer fetch
  → application queue
  → handler
  → database/API/output topic
  → business outcome
```

Mỗi đoạn cần latency, error, ownership và correlation.

---

## 3. Ba loại thời gian

Phân biệt:

| Mốc | Ý nghĩa |
|---|---|
| event time | sự kiện xảy ra trong nghiệp vụ |
| append/ingest time | broker hoặc platform nhận message |
| processing time | consumer xử lý |

Clock skew hoặc producer gửi trễ có thể làm “consumer lag thấp” nhưng dữ liệu vẫn cũ. Chuẩn
hóa timestamp, timezone và time synchronization.

---

## 4. Viết business contract trước metric

Ví dụ:

```text
OrderCreated phải được inventory xử lý dưới 30 giây
không mất event đã xác nhận
có thể nhận trùng nhưng side effect phải idempotent
schema tương thích ngược
DLQ phải có owner và thời hạn xử lý
```

Từ contract mới chọn SLI, alert và delivery semantics.

---

## 5. SLO cho pipeline bất đồng bộ

Các SLI hữu ích:

- tỷ lệ message đạt business outcome;
- end-to-end processing latency;
- message freshness/age;
- duplicate hoặc reconciliation gap;
- dead-letter rate/age;
- publish success/latency;
- recovery time khi backlog.

Broker availability là dependency SLI, không thay workflow SLO.

---

## 6. Delivery semantics phải được quan sát

| Semantics | Điều phải kiểm chứng |
|---|---|
| at-most-once | có mất message khi lỗi không |
| at-least-once | side effect có idempotent không |
| exactly-once trong Kafka | transaction có bao phủ đúng read-process-write không |

“Exactly once” không tự mở rộng tới database hoặc external API nếu không có protocol/pattern
phối hợp.

---

## 7. Mô hình nhiều lớp

```text
business
  → producer application/client
  → network/auth/quota
  → broker/request path
  → storage/replication
  → group coordinator
  → consumer client
  → handler/dependencies
```

Dashboard phải drill-down qua các lớp thay vì chỉ hiển thị broker CPU.

---

## 8. Identity và labels

Một contract thường cần:

```text
cluster, environment, region
topic, consumer_group
client_id/service
broker_id
```

Partition hữu ích để tìm skew nhưng tạo nhiều series. Không gắn message key, offset, event ID,
user ID hoặc schema payload vào metric label.

---

## 9. Bốn nhóm tín hiệu

- **metrics**: rate, latency, error, saturation, lag;
- **logs**: lỗi protocol, request, rebalance, serialization;
- **traces**: causal path producer → consumer → dependency;
- **business reconciliation**: message có tạo outcome đúng hay không.

Không signal nào đủ một mình.

---

## 10. Kafka metrics và JMX

Broker dùng Yammer Metrics; Java clients dùng Kafka Metrics. Cả hai có thể expose qua JMX và
metrics reporter.

Khi chuyển sang Prometheus:

- pin JMX Exporter/rules;
- đặt type/unit đúng;
- allowlist MBean cần thiết;
- kiểm tra label cardinality;
- test khi nâng Kafka;
- quan sát chính exporter.

---

## 11. Bảo vệ JMX

Remote JMX mặc định không phải endpoint an toàn để mở ra mạng production. Nếu sử dụng:

- authentication và TLS;
- network policy/firewall;
- read-only exposure phù hợp;
- không public Internet;
- credential rotation;
- audit truy cập.

Java agent HTTP mode thường đơn giản hơn remote RMI nhưng endpoint metrics vẫn cần bảo vệ.

---

## 12. Broker availability

Theo dõi:

- broker/target up;
- request success;
- listener/network;
- JVM/process;
- log directories;
- broker registration;
- cluster membership;
- restart/recovery duration.

Một broker down có thể chưa gây user impact nhờ replication nhưng đã làm mất failure
headroom.

---

## 13. Traffic

Các chiều chính:

- messages/records in;
- bytes in/out;
- produce/fetch requests;
- replication/reassignment traffic;
- message/batch size;
- topic và broker distribution.

Đọc rate từ counter bằng `rate()`/`increase()`. Không cộng metric rate và total cùng nhau.

---

## 14. Request latency decomposition

Kafka tách request time thành:

```text
request queue
  + local processing
  + remote wait
  + response queue
  + response send
```

Produce chậm vì chờ replica khác với chậm vì broker request queue bão hòa. Client latency còn
thêm buffer wait, network và retry.

---

## 15. Network và request-handler saturation

Theo dõi:

- network processor idle;
- request handler idle;
- request queue size;
- connection count/rate;
- request/response bytes;
- socket error/retransmit;
- TLS/SASL latency.

Average idle toàn cluster che một broker leader-heavy.

---

## 16. Queue và purgatory

Delayed produce/fetch requests chờ điều kiện hoàn tất có thể xuất hiện trong purgatory. Giá
trị khác zero không luôn là lỗi.

Correlate:

- produce/fetch purgatory size;
- `acks`;
- fetch wait/min bytes;
- replica lag;
- request latency;
- traffic change.

---

## 17. Error taxonomy

Phân biệt ít nhất:

- timeout/network;
- authentication/authorization;
- quota/throttling;
- not leader/metadata stale;
- not enough replicas;
- message too large;
- serialization/schema;
- transaction/fencing;
- offset/group;
- application handler.

Retryable và non-retryable error cần counter riêng.

---

## 18. Storage và disk

Theo dõi:

- log size/growth;
- disk used/free/inode;
- read/write latency/throughput;
- offline log directories;
- segment count;
- flush/recovery;
- page cache;
- retention/compaction backlog.

Kafka phụ thuộc page cache; “JVM heap còn trống” không chứng minh broker còn memory headroom.

---

## 19. Partition health

Các câu hỏi:

- partition/leader phân bố đều không;
- partition offline không;
- replica có bắt kịp không;
- disk usage lệch không;
- traffic có hot partition không;
- reassignment có tiến triển không.

Tổng cluster che skew theo broker, topic và partition.

---

## 20. ISR và `min.insync.replicas`

Theo dõi:

- under-replicated partitions;
- under-min-ISR;
- at-min-ISR;
- ISR shrink/expand;
- failed ISR update.

At-min-ISR chưa mất availability nhưng không còn thêm failure headroom cho produce yêu cầu
`acks=all`.

---

## 21. Leader election

Alert và timeline cần:

- leader election;
- unclean election;
- ELR election nếu dùng;
- offline partition;
- preferred leader imbalance;
- client metadata refresh/error.

Unclean election có thể ưu tiên availability bằng cách chấp nhận data-loss risk; không tự động
bật trong incident khi chưa hiểu contract.

---

## 22. KRaft quorum

Quan sát controller quorum:

- active controller;
- leader changes;
- voter health;
- high-watermark/committed offset;
- follower lag;
- append/fetch latency;
- controller event queue;
- metadata snapshot/log growth.

Broker data plane còn chạy tạm thời không có nghĩa control plane đang khỏe.

---

## 23. Producer client metrics

Theo dõi:

- record send/error/retry rate;
- request latency;
- record queue time;
- buffer available/exhaustion;
- batch size;
- compression ratio;
- request in flight;
- metadata age;
- throttle time.

Broker metrics không thấy thời gian record chờ trong producer buffer.

---

## 24. Producer send latency

```text
application enqueue
  → buffer/linger
  → serialization/compression
  → network
  → broker queue/process/replication
  → acknowledgement
```

Đo cả API-call latency và callback/ack latency. `send()` trả nhanh vì async không có nghĩa
record đã được broker xác nhận.

---

## 25. Batching và compression

Batch/compression tăng throughput nhưng có trade-off:

- `linger` thêm latency;
- batch lớn giữ memory;
- compression dùng CPU;
- batch ít record làm hiệu quả thấp;
- message lớn tăng network và broker memory.

Quan sát batch-size average, records/request, compression rate, queue time và end-to-end SLO.

---

## 26. Retry và idempotent producer

Retry có thể tăng latency và tạo duplicate nếu cấu hình/consumer side không bảo vệ. Producer
idempotence giảm duplicate do retry trong phạm vi producer session/partition.

Theo dõi retry rate, error, sequence/fencing, delivery timeout và out-of-order business signal.
Không coi retry “thành công cuối cùng” là miễn phí.

---

## 27. `acks` và durability

`acks=all` kết hợp replication/min-ISR phù hợp giúp tăng durability nhưng có thể tăng latency
hoặc giảm availability khi replica thiếu.

Dashboard phải nối:

```text
producer config
↔ under/at min ISR
↔ request remote wait
↔ produce error
↔ business RPO
```

---

## 28. Transactions

Với transactional producer/read-process-write, theo dõi:

- transaction begin/commit/abort;
- transaction duration;
- coordinator error/latency;
- fencing;
- verification error;
- open transaction lâu;
- consumer isolation phù hợp.

Transaction timeout hoặc abort storm có thể tạo lag dù broker throughput chưa bão hòa.

---

## 29. Partitioner và skew

Hot partition thường do:

- key distribution lệch;
- null key/batching behavior;
- một customer/entity quá nóng;
- partition count không đủ;
- producer custom partitioner;
- leader placement.

So sánh bytes/records/lag/size theo partition bằng top-k có kiểm soát, không giữ mọi partition
trên dashboard tổng.

---

## 30. Record size, serialization và schema

Theo dõi:

- serialized bytes;
- serialization latency/error;
- rejected oversized record/batch;
- schema lookup latency/error;
- unknown schema;
- payload growth theo version.

Không ghi payload vào telemetry. Metric size histogram thường an toàn hơn raw message logs.

---

## 31. Consumer client metrics

Cần:

- records/bytes consumed;
- fetch latency/rate/size;
- records lag max;
- records lead min;
- poll idle ratio;
- commit latency/error;
- rebalance;
- assigned partitions;
- throttle;
- handler throughput/latency.

Kafka client không biết business side effect nếu application không instrument.

---

## 32. Consumer lag là gì?

Đơn giản:

```text
lag_records = log_end_offset - committed_or_current_offset
```

Nhưng phải nói rõ:

- dùng committed hay position;
- group/topic/partition nào;
- inactive group xử lý ra sao;
- compacted/deleted offsets;
- transaction/read isolation;
- nguồn collector và sampling interval.

---

## 33. Lag theo record khác lag theo thời gian

100.000 record có thể là vài giây hoặc vài giờ tùy rate. SLI gần business hơn:

```text
freshness_age = now - event_time_of_oldest_unprocessed_message
```

Nếu không đo oldest message, có thể ước lượng lag seconds từ rate nhưng phải ghi rõ sai số,
đặc biệt khi traffic burst hoặc bằng zero.

---

## 34. Aggregate lag đúng cách

- `sum`: backlog tổng;
- `max`: partition tệ nhất;
- distribution/top-k: skew;
- per group/topic: ownership;
- age: user impact.

Average partition lag che một partition đứng yên. Tổng lag giữa các group độc lập không phản
ánh cùng một workflow.

---

## 35. Poll khác process

Consumer có thể poll nhanh rồi đưa record vào queue nội bộ, khiến Kafka lag thấp nhưng handler
chậm.

Instrument:

```text
poll/fetch
→ application queue depth/oldest age
→ handler duration/error
→ dependency
→ commit
```

Đây là lý do cần end-to-end freshness, không chỉ broker offset.

---

## 36. Rebalance

Theo dõi:

- rebalance count/rate/duration;
- group state;
- join/sync latency;
- partition revoked/assigned;
- consumer restarts;
- processing pause;
- lag sau rebalance.

Rebalance loop có thể đến từ session timeout, poll quá lâu, deploy churn, coordinator hoặc
protocol/config mismatch.

---

## 37. Consumer group protocol

Kafka hiện có nhiều group/protocol/client generation. Metric và state có thể khác giữa classic,
consumer và Streams group.

Khi migrate:

- pin client/broker compatibility;
- baseline rebalance;
- kiểm tra group coordinator metrics;
- canary một group;
- so lag/availability;
- có rollback criteria.

---

## 38. Offset commit

Phân biệt:

- auto/manual commit;
- sync/async commit;
- commit trước hay sau side effect;
- committed offset và processed offset;
- commit failure/retry.

Commit sớm có nguy cơ mất xử lý; commit muộn có nguy cơ xử lý trùng. SLI nghiệp vụ phải phát
hiện cả hai.

---

## 39. Poison message

Một message không thể deserialize hoặc xử lý có thể:

- chặn partition;
- retry vô hạn;
- tạo log storm;
- làm consumer crash/rebalance;
- bị bỏ qua im lặng.

Theo dõi failure theo reason/schema/version, retry attempts và oldest blocked age; không label
theo message ID.

---

## 40. Retry và DLQ

Retry topic/DLQ cần metric:

- ingress/egress rate;
- message age;
- attempts;
- reason hữu hạn;
- recovery/replay success;
- retention headroom;
- owner/SLA.

DLQ tăng rồi nằm yên không phải “đã xử lý lỗi”; nó là backlog nghiệp vụ khác.

---

## 41. Idempotent consumer

Quan sát:

- duplicate detected;
- dedup store latency/error/size;
- idempotency-key collision;
- side-effect conflict;
- reconciliation mismatch;
- dedup retention.

Dedup retention ngắn hơn replay window có thể làm duplicate tái xuất hiện.

---

## 42. End-to-end freshness

Đưa timestamp tạo event hoặc business timestamp trong envelope chuẩn:

```text
message_age_at_process = process_start - event_created_at
end_to_end_latency      = business_outcome_at - event_created_at
```

Đồng hồ phải tin cậy. Không dùng broker append time thay event time nếu contract nói về lúc
nghiệp vụ xảy ra.

---

## 43. Trace-context propagation

Producer inject context vào message headers; consumer extract và tạo processing span. Cần:

- header allowlist;
- tương thích qua bridge/connector;
- trust boundary;
- không ghi PII;
- không để header tăng vô hạn;
- test end-to-end.

Nếu retry tạo message mới, ghi rõ nó tiếp tục hay bắt đầu workflow mới.

---

## 44. Span links cho fan-out và batch

Messaging không luôn là cây parent-child:

- một batch chứa nhiều message;
- một message tới nhiều consumer group;
- một consumer tạo nhiều output.

OpenTelemetry dùng span links để nối processing với creation contexts khi phù hợp. Không ép
mọi consumer span làm child trực tiếp của producer request đã kết thúc từ lâu.

---

## 45. Sampling

Head sampling ở producer có thể bỏ trace của message sau này lỗi. Tail sampling cần giữ trace
đủ lâu và route đúng để thấy consumer muộn.

Giải pháp thường kết hợp:

- metrics 100%;
- trace sample có budget;
- ưu tiên error/slow;
- exemplar;
- business event ID trong log có kiểm soát;
- synthetic canary không sample.

---

## 46. Schema Registry

Quan sát:

- availability/latency;
- schema register/lookup error;
- compatibility rejection;
- cache hit/miss client;
- schema ID/version usage;
- deploy correlation;
- deserialize failure theo schema family.

Không đưa schema definition có dữ liệu nhạy cảm vào log cảnh báo.

---

## 47. Kafka Connect

Cần metric theo worker, connector và task:

- state;
- poll/write/read rate;
- batch;
- error/retry;
- source/sink record lag;
- offset commit;
- task restart;
- DLQ;
- external system latency.

Worker healthy nhưng một task failed vẫn làm dữ liệu ngừng.

---

## 48. CDC

Với database CDC, đo:

```text
source commit time
→ connector capture
→ Kafka append
→ consumer process
→ destination apply
```

Thêm WAL/binlog position, replication slot/log retention, snapshot progress, transaction size,
schema change và source pressure.

---

## 49. Kafka Streams

Theo dõi:

- client/thread/task state;
- process/punctuate latency;
- record-lateness/drop;
- commit;
- repartition/changelog;
- state-store latency;
- standby;
- rebalance;
- output freshness.

Input lag thấp nhưng state store lỗi hoặc output bị drop vẫn là pipeline failure.

---

## 50. State store và restore

Quan sát:

- RocksDB/store size;
- get/put latency;
- cache/memtable;
- compaction;
- disk;
- changelog lag;
- restore records/rate/time;
- standby readiness.

Recovery objective phải bao gồm thời gian restore state, không chỉ thời gian process restart.

---

## 51. MirrorMaker và DR

Theo dõi:

- replication throughput/latency;
- source-to-target offset/freshness;
- checkpoint sync;
- topic/config/ACL coverage;
- loop prevention;
- target capacity;
- failover/failback;
- RPO/RTO.

Cluster target “up” không chứng minh dữ liệu đủ mới để cut over.

---

## 52. Tiered storage

Thêm signals:

- local/remote log size;
- upload/copy/delete;
- remote fetch rate/latency/error;
- cache hit;
- metadata;
- object-store dependency;
- restore/cold-read latency;
- cost.

Consumer replay cũ có performance khác đọc page cache/local disk.

---

## 53. Quota và throttling

Theo dõi throttle time/rate theo tenant hoặc client group có cardinality kiểm soát. Throttle
có thể là policy đúng nhưng vẫn gây SLO impact.

Dashboard cần:

- configured quota;
- actual bytes/request rate;
- throttle;
- affected services;
- noisy neighbor;
- capacity headroom.

---

## 54. Security signals

Quan sát:

- TLS handshake/certificate;
- SASL authentication failure;
- authorization denial;
- expired connection;
- ACL/config change;
- unusual client/topic access;
- audit source của platform.

Không expose username/client ID tự do nếu vừa nhạy cảm vừa high-cardinality.

---

## 55. Capacity model

Model gồm:

- messages/bytes per second;
- record/batch size;
- partition/leader count;
- replication factor;
- retention;
- compression;
- disk/network;
- request CPU;
- failover/reassignment/recovery traffic;
- consumer catch-up rate.

Capacity recovery phải lớn hơn ingest rate; nếu không, backlog không bao giờ giảm.

---

## 56. Dashboard hierarchy

```text
Business workflow/freshness
  → producer/service
  → topic/partition
  → broker/storage/replication
  → consumer group
  → handler/dependency/DLQ
```

Overview: SLO, age, throughput, error, lag, ISR, broker saturation và changes. Drill-down:
client, group, topic, broker, partition top-k.

---

## 57. Alert strategy

Page khi:

- business SLO burn;
- oldest message age vượt objective;
- publish/process error gây impact;
- partition offline hoặc dưới min-ISR có blast radius;
- DLQ/poison message chặn workflow;
- cluster/control plane mất khả năng phục vụ.

Ticket cho skew/capacity trend còn đủ thời gian. Alert lag cần volume và age context.

---

## 58. Incident: lag tăng

```text
1. Xác nhận age và business impact
2. Xác định group/topic/partition
3. So ingest với process rate
4. Kiểm tra consumer instances/assignment/rebalance
5. Kiểm tra application queue/handler/dependency
6. Kiểm tra fetch/throttle/broker/network
7. Ước lượng catch-up time
8. Mitigate có giới hạn và theo dõi duplicate
```

Tăng consumer không giúp nếu chỉ một partition nóng.

---

## 59. Incident: broker/partition

Kiểm tra theo thứ tự:

- user/client error;
- broker/process/listener;
- offline/under-replicated/min-ISR;
- controller/quorum;
- disk/log directory;
- request queue/idle;
- network/replication;
- change/reassignment.

Không chạy unclean election hoặc xóa data khi chưa ghi nhận RPO và approval.

---

## 60. Change correlation

Annotate:

- application deploy;
- client config;
- topic/config/ACL;
- partition increase;
- broker rolling restart;
- reassignment;
- schema release;
- quota;
- certificate;
- traffic campaign.

Partition count tăng là thay đổi ordering/key mapping có thể ảnh hưởng producer và consumer.

---

## 61. Cardinality và retention

Nguồn cardinality lớn:

- partition;
- client ID ngẫu nhiên;
- consumer member ID;
- transaction ID;
- topic động;
- exception text;
- schema ID;
- message key/ID.

Giữ aggregate dài hạn; partition/client detail có retention ngắn hoặc on-demand. Metric contract
phải pin exporter mapping.

---

## 62. Failure-mode tests

Trong môi trường kiểm soát:

- broker/controller loss;
- replica lag/min-ISR;
- disk đầy/chậm;
- producer timeout/retry;
- consumer crash/rebalance;
- poison message;
- schema registry outage;
- DLQ/replay;
- network partition;
- DR cutover.

Đo SLO, alert, duplicate/loss, catch-up time và evidence completeness.

---

## 63. Ownership và runbook

Mỗi topic/group cần:

- producer owner;
- consumer owner;
- platform owner;
- schema/data classification;
- SLO/freshness;
- retention/RPO;
- retry/DLQ policy;
- dashboard/alert;
- escalation;
- replay/reset-offset approval.

Tên topic không đủ để suy ra owner.

---

## 64. Workshop, checklist và câu hỏi

### Workshop

1. Chọn một business event.
2. Vẽ producer → topic → consumer → outcome.
3. Thêm event-time/freshness metric.
4. Nối producer, broker, consumer và handler dashboard.
5. Mô phỏng consumer chậm hoặc poison message.
6. Xác nhận alert và runbook không cần raw payload.

### Checklist

- [ ] Workflow có SLO và owner.
- [ ] Event, append và process time được phân biệt.
- [ ] Producer buffer/retry/error được quan sát.
- [ ] Broker request/storage/replication có coverage.
- [ ] Lag có cả records, max partition và age.
- [ ] Application queue/handler được instrument.
- [ ] Rebalance, commit và duplicate có signal.
- [ ] Retry/DLQ có SLA.
- [ ] Trace context qua header đã test.
- [ ] JMX/exporter được bảo vệ và version hóa.
- [ ] Recovery/catch-up/DR đã diễn tập.

### Câu hỏi

1. Vì sao lag records không đủ làm freshness SLI?
2. Producer `send()` trả về chứng minh điều gì?
3. At-min-ISR khác under-min-ISR thế nào?
4. Poll nhanh có thể che handler chậm ra sao?
5. Commit sớm và muộn tạo rủi ro gì?
6. Tại sao messaging trace thường cần span links?
7. DLQ có phải xử lý lỗi hoàn tất không?
8. Tăng consumer khi nào không tăng throughput?
9. Exactly-once trong Kafka có bao phủ external API không?
10. Catch-up capacity phải thỏa điều kiện gì?
11. Remote JMX có rủi ro nào?
12. Restore state store ảnh hưởng RTO ra sao?

---

## 65. Tài liệu chính thức và chủ đề tiếp theo

### Apache Kafka 4.3

- [Kafka monitoring](https://kafka.apache.org/43/operations/monitoring/)
- [Producer configuration](https://kafka.apache.org/43/configuration/producer-configs/)
- [Consumer and Share Consumer configuration](https://kafka.apache.org/43/configuration/consumer-configs/)
- [KRaft operations](https://kafka.apache.org/43/operations/kraft/)
- [Consumer rebalance protocol](https://kafka.apache.org/43/operations/consumer-rebalance-protocol/)
- [Tiered storage](https://kafka.apache.org/43/operations/tiered-storage/)
- [Kafka security](https://kafka.apache.org/43/security/security-overview/)

### Observability

- [Prometheus JMX Exporter](https://prometheus.github.io/jmx_exporter/)
- [JMX Exporter rules](https://prometheus.github.io/jmx_exporter/configuration/rules/)
- [OpenTelemetry messaging semantic conventions](https://opentelemetry.io/docs/specs/semconv/messaging/)
- [OpenTelemetry messaging spans](https://opentelemetry.io/docs/specs/semconv/messaging/messaging-spans/)

Chủ đề tiếp theo:
[API & HTTP Observability](api_http_observability.md) – request lifecycle, RED, route
cardinality, latency histograms, retries, deadlines, gateways và distributed tracing.

---

*Cập nhật lần cuối: 2026-07-30*
