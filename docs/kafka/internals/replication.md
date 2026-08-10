---
title: "Kafka Replication & Fault Tolerance – Deep Dive"
topic: kafka
level: mixed
review_status: needs_review
content_updated: 2026-07-27
last_verified: null
version_scope: "unspecified"
source_count: 5
---
# Kafka Replication & Fault Tolerance – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)
>
> Phạm vi đối chiếu chính: Apache Kafka 4.3 chạy KRaft. Phần ZooKeeper chỉ dùng để hiểu cluster Kafka 3.9 trở về trước.

---

## What – Kafka Replication

**Replication** *(sao chép dữ liệu)* là cơ chế Kafka đặt log của một partition trên nhiều broker để tăng **durability** *(khả năng dữ liệu tồn tại sau lỗi)* và **availability** *(khả năng tiếp tục phục vụ)*. Mỗi partition có một leader và các follower replica; producer ghi vào leader, follower chủ động fetch dữ liệu về.

Việc dữ liệu phải được sao chép tới đâu trước khi producer nhận ACK phụ thuộc `acks`, tập **ISR (In-Sync Replicas)** *(các replica đang theo kịp theo tiêu chí Kafka)* và `min.insync.replicas`. Replication factor chỉ cho biết số bản sao được gán, không tự chứng minh mọi bản sao đang đồng bộ hoặc nằm ở các failure domain độc lập.

```
Replication factor (RF):
  RF=1: no redundancy (single point of failure)
  RF=3: có 3 replica được gán; thường là điểm bắt đầu production
  RF=5: có thêm bản sao nhưng tăng storage/network/recovery cost

  Khả năng chịu lỗi thực tế phụ thuộc:
    ISR/eligible replicas tại thời điểm lỗi
    rack/AZ placement và correlated failure
    min.insync.replicas + producer acks
    clean/unclean election, disk health và controller quorum

Data flow:
  Producer → Leader (write) → ISR Followers (replicate) → ACK producer  # acks=all path
  Consumer ← Leader (read by default, can read from follower in KIP-392)
```

> 💡 **Giải thích dễ hiểu:**
> RF giống số **kho được chỉ định giữ cùng một sổ hàng**, còn ISR là danh sách kho hiện đang chép kịp. Có ba địa chỉ kho không có nghĩa cả ba đang có bản mới nhất; nếu cả ba cùng một tòa nhà, một sự cố điện vẫn có thể làm mất cả cụm.

---

## Components – ISR (In-Sync Replicas)

```
ISR: tập replica được controller/leader xem là "in sync"
  Follower có thể vào lại ISR sau khi bắt kịp log leader

A follower falls OUT of ISR when:
  - Không gửi fetch request trong `replica.lag.time.max.ms`, hoặc
  - Không bắt kịp log end của leader trong cửa sổ thời gian đó
  - Không có một ngưỡng cố định kiểu "chậm N record là bị loại"; offset gap đơn lẻ chưa đủ kết luận

ISR changes are tracked in cluster metadata:
  Legacy ZooKeeper mode: partition state trong ZooKeeper
  KRaft: metadata log của controller quorum

Example:
  Topic: orders, Partition 0, RF=3
  Leader: Broker-1 (offset 1000)
  Follower Broker-2: LEO=998, vẫn fetch/catch up đúng hạn → có thể còn trong ISR
  Follower Broker-3: LEO=850 và không catch up quá lag window → bị loại khỏi ISR
  Chỉ snapshot offset không đủ; cần cả lịch sử fetch/catch-up và partition state
```

> 💡 **Giải thích dễ hiểu — ISR và lag time:**
> ISR giống danh sách **nhân viên đang chép sổ kịp tiến độ**. Người chậm vài dòng nhưng vẫn đều đặn bắt kịp có thể còn trong nhóm; người ngừng xin trang mới hoặc mãi không chạm được trang cuối trong cả cửa sổ thời gian sẽ bị đưa ra ngoài. Kafka đo tiến độ theo thời gian, không chỉ nhìn một ảnh chụp khoảng cách offset.

---

## How – Replication Protocol

```
Fetch-based replication:
  Followers continuously send FETCH requests to leader
  Leader responds with records from the follower's current offset
  No push from leader → follower controls fetch rate

High-water mark (HWM):
  Ranh giới offset mà protocol xem là committed/safe để trả cho consumer
  Leader suy ra từ tiến độ replica; follower nhận HWM qua fetch response
  Consumer không đọc phần log vượt quá ranh giới committed của replica đang phục vụ
  Với strict min ISR, HWM không tiến khi ISR nhỏ hơn min.insync.replicas

Log End Offset (LEO):
  Offset kế tiếp sẽ được append ở một replica (không phải offset của record cuối)
  LEO có thể đi trước HWM khi record chưa được commit

Leader epoch:
  Tăng khi partition đổi leader
  Giúp client/replica phát hiện metadata cũ và tìm điểm truncate log phân kỳ sau failover

Producer ACK flow (acks=all):
  1. Producer sends batch to leader
  2. Leader appends to local log (LEO advances)
  3. Followers FETCH and append to their logs
  4. Followers report their LEO back to leader
  5. Leader cập nhật trạng thái committed/HWM theo replication protocol
  6. Leader ACKs producer khi điều kiện `acks=all` được thỏa

Timeline:
  t0: Leader LEO=100, HWM=95, ISR=[B1,B2,B3]
  t1: Producer sends msg → Leader LEO=101
  t2: B2 fetches → LEO=101; B3 fetches → LEO=101
  t3: Leader sees all ISR at LEO=101 → HWM=101
  t4: Leader ACKs producer
```

Timeline trên là mô hình khái niệm; propagation của HWM tới follower có thể trễ thêm fetch cycle. HWM bảo vệ consumer khỏi phần đuôi chưa committed, còn leader epoch bảo vệ khỏi dùng log/metadata của nhiệm kỳ leader cũ. Hai khái niệm giải quyết hai rủi ro khác nhau.

> 💡 **Giải thích dễ hiểu — LEO, HWM và epoch:**
> LEO là **trang trống kế tiếp trong sổ của từng kho**; HWM là dấu “đã đối chiếu, được phép công bố”; leader epoch là số nhiệm kỳ của người giữ sổ chính. Khi đổi thủ kho, số nhiệm kỳ giúp phát hiện ai đang cầm bản hướng dẫn cũ và cắt bỏ phần ghi chép phân kỳ.

## How – KRaft metadata replication khác data replication

- **Data replication** sao chép record của topic-partition giữa broker leader và follower theo RF/ISR.
- **KRaft metadata replication** dùng Raft trong controller quorum để sao chép metadata cluster: broker registration, topic/partition assignment, leader, ISR và configuration.
- Controller quorum không chứa thay cho dữ liệu topic. Mất quorum controller ảnh hưởng khả năng điều phối/metadata availability; mất replica broker ảnh hưởng log dữ liệu. Hai quorum/failure model phải được capacity và monitor riêng.

> 💡 **Giải thích dễ hiểu — hai loại sổ:**
> Broker giữ **sổ hàng hóa thật**; KRaft controller giữ **sổ mục lục ai đang giữ kho nào và ai là leader**. Sao chép mục lục không tạo thêm bản sao hàng hóa, và sao chép hàng hóa không thay thế đa số controller cần để cập nhật mục lục.

---

## How – Leader Election

```
Trigger: leader broker fails or network partition

Legacy ZooKeeper mode (Kafka 3.9 trở về trước):
  1. ZK detects broker failure (ZK session expires)
  2. Controller broker (elected by ZK) handles leader election
  3. Controller selects first ISR replica as new leader
  4. Controller updates ZK with new leader metadata
  5. All brokers notified (LeaderAndIsr request)

KRaft mode:
  1. Active controller detects broker failure
  2. Controller selects new leader from ISR
  3. Updates metadata log (Raft)
  4. Followers apply metadata change
  Thời gian failover phụ thuộc session/heartbeat timeout, controller load, partition count và network; không có số cố định cho mọi cluster

Election order khi ELR được bật:
  1. Chọn replica trong ISR nếu còn
  2. Nếu ISR rỗng, chọn ELR chưa bị fenced
  3. Nếu không còn ELR, xét last known leader chưa bị fenced
  4. Nếu không có ứng viên hợp lệ: partition offline hoặc unclean election theo policy
```

### Eligible Leader Replicas (ELR)

ELR xuất hiện từ Kafka 4.0 và được bật mặc định cho cluster mới từ Kafka 4.1. Khi strict `min.insync.replicas` khiến HWM không thể tiến vì ISR đã nhỏ hơn min ISR, một replica vừa rời ISR vẫn có thể được controller chứng minh không thiếu committed data. KRaft lưu replica đó trong ELR để có thêm ứng viên failover an toàn.

```text
ISR = replica đang in-sync theo lag/session rule
ELR = replica ngoài ISR nhưng vẫn đủ an toàn theo committed boundary
Unclean candidate = replica ngoài hai tập trên, có thể thiếu committed record
```

ELR không làm tăng RF và không biến replica stale bất kỳ thành an toàn. Trước/sau nâng cấp cần kiểm tra feature level:

```bash
kafka-features.sh --bootstrap-server localhost:9092 --describe
# eligible.leader.replicas.version phải phù hợp kế hoạch upgrade/downgrade
```

Thay đổi `min.insync.replicas` ở cluster hoặc topic sẽ xóa ELR state liên quan vì bằng chứng an toàn được xây dựng dựa trên min ISR cũ. Đây là thay đổi vận hành, không nên chỉnh min ISR giữa incident mà không đánh giá ảnh hưởng election.

| Loại election | Ứng viên | Mục tiêu | Rủi ro chính |
|---|---|---|---|
| Clean từ ISR | Replica trong ISR | Failover an toàn thông thường | Có thể unavailable nếu ISR rỗng |
| ELR election | ELR chưa fenced | Khôi phục availability mà vẫn giữ committed data | Phụ thuộc feature/version và ELR state còn hợp lệ |
| Last known leader | Leader gần nhất chưa fenced | Phương án sau ISR/ELR theo protocol ELR | Phải hiểu đúng version và trạng thái fencing |
| Unclean election | Replica ngoài ISR/ELR | Ưu tiên availability cuối cùng | Có thể rollback log và mất committed record |

Không nên dự đoán failover chỉ từ “KRaft nhanh hơn ZooKeeper”. Đo thời gian phát hiện lỗi, election, metadata propagation và client recovery trên chính partition count/cấu hình của cluster.

---

## How – min.insync.replicas & acks

```
Configuration interaction:
  acks=all + min.insync.replicas=2 + RF=3

  Scenario 1: All 3 brokers up → ISR=[1,2,3]
    - Write succeeds nếu cả ISR đáp ứng `acks=all`; không chỉ chờ đúng 2 replica

  Scenario 2: 1 broker down → ISR=[1,2]
    - Write có thể succeeds: 2 ISR ≥ min.insync.replicas=2 và cả hai ACK

  Scenario 3: 2 brokers down → ISR=[1]
    - Write FAILS: 1 ISR < min.insync.replicas=2 ❌
    - Producer gets NotEnoughReplicasException
    - Chính sách từ chối write làm giảm cửa sổ chỉ còn một copy; không bảo vệ khỏi mọi kiểu mất dữ liệu

  Scenario 4: acks=1, min.insync.replicas=2
    - min.insync.replicas only checked with acks=all
    - acks=1: leader ACKs immediately → min.insync.replicas ignored

Rule:
  RF=3, min.insync.replicas=2, acks=all
  → Nếu ban đầu ISR đủ 3 và placement độc lập, write có thể tiếp tục sau một broker failure
  → Không đảm bảo mọi chuỗi lỗi/AZ loss đều không mất data; phải kiểm tra ISR và failure domain thực tế
```

`min.insync.replicas` là **ngưỡng được phép nhận write**, không phải “số ACK cố định” khi ISR lớn hơn ngưỡng. Với `acks=all`, mọi replica trong ISR hiện tại phải xác nhận theo protocol; min ISR quyết định khi nào broker phải từ chối vì tập đồng bộ đã quá nhỏ.

> 💡 **Giải thích dễ hiểu — min ISR:**
> `min.insync.replicas=2` giống nội quy **“dưới hai người chép sổ thì ngừng nhận đơn mới”**. Khi đang có ba người, đơn vẫn chờ cả nhóm đang được công nhận, chứ không tùy ý chọn hai người rồi bỏ người thứ ba. Nội quy tăng an toàn bằng cách hy sinh write availability khi nhóm co quá nhỏ.

```properties
# Site-level overrides minh họa (Kafka product defaults có thể khác)
default.replication.factor=3
min.insync.replicas=2

# Per-topic
kafka-configs.sh --alter --entity-type topics --entity-name orders \
  --add-config min.insync.replicas=2

# Verify
kafka-configs.sh --describe --entity-type topics --entity-name orders
```

---

## How – Unclean Leader Election

```
Unclean leader election: elect a leader from OUT-OF-ISR replicas
  Trigger: no ISR replica available (all ISR brokers are down)

  unclean.leader.election.enable=false (default, production):
    - Partition có thể offline cho tới khi replica đủ điều kiện quay lại
    - ✅ Tránh mất dữ liệu do riêng việc bầu một replica stale bất kỳ
    - ❌ Partition unavailable (potential downtime)

  unclean.leader.election.enable=true:
    - Elect any available replica (out-of-sync)
    - ✅ Partition stays available
    - ❌ Có thể mất các record chỉ tồn tại trên leader/ISR cũ
    - Use for: non-critical topics where availability > durability

Decision matrix:
  Financial/critical:  thường unclean=false; vẫn cần backup/DR và kiểm thử failure
  Metrics/logs:        chỉ bật khi business chấp nhận rollback/mất dữ liệu rõ ràng
  Event streaming:     ưu tiên clean election; quyết định theo RPO/RTO
```

Clean election không đồng nghĩa “không bao giờ mất dữ liệu”: correlated disk/AZ failure, vận hành sai, retention hoặc disaster vượt quá số replica vẫn có thể làm mất dữ liệu. Ngược lại, ELR ở Kafka mới là tập replica được protocol đánh dấu đủ an toàn và không nên bị đánh đồng với unclean election tùy ý.

> 💡 **Giải thích dễ hiểu — clean và unclean:**
> Clean election là chọn **người có cuốn sổ đã được xác nhận**; unclean election là chọn người còn sống nhưng cuốn sổ có thể thiếu trang. Cách thứ hai mở cửa kho sớm hơn nhưng chấp nhận lịch sử bị lùi. ELR giống một người tạm rời danh sách trực ca nhưng có bằng chứng sổ vẫn an toàn, khác với chọn ngẫu nhiên.

```bash
# Per-topic unclean election
kafka-configs.sh --alter --entity-type topics --entity-name app-metrics \
  --add-config unclean.leader.election.enable=true

# KRaft kiểm tra election định kỳ; nếu incident đã được phê duyệt mất dữ liệu,
# operator có thể yêu cầu ngay thay vì chờ chu kỳ.
kafka-leader-election.sh --bootstrap-server localhost:9092 \
  --election-type unclean --topic app-metrics --partition 0
```

Lệnh unclean phía trên là thao tác phá vỡ durability và cần approval, snapshot trạng thái, phạm vi partition rõ ràng cùng kế hoạch đối soát dữ liệu. Không chạy `--all-topic-partitions` như phản xạ đầu tiên.

---

## How – Preferred Replica Election

```
Problem: Sau failover/restart, leadership có thể chưa quay về preferred replica ngay
  → Có thể imbalanced: một broker giữ quá nhiều partition leader

Solution: Preferred replica election
  preferred replica = first broker listed in partition's replicas list
  Auto leader rebalance có thể đưa leadership về preferred replica theo config/version
    - Background check every leader.imbalance.check.interval.seconds (300s)
    - Rebalance if any broker's leadership imbalance > leader.imbalance.per.broker.percentage (10%)

Manual rebalance:
  kafka-leader-election.sh --bootstrap-server localhost:9092 \
    --election-type preferred --all-topic-partitions
```

Preferred leader election chỉ đổi leader sang replica đầu tiên trong assignment khi replica đó đủ điều kiện; nó không di chuyển log sang broker khác. Nếu replica placement hoặc disk usage đã lệch, phải dùng partition reassignment. Chạy election hàng loạt cũng tạo metadata/load spike, nên quan sát và chia đợt ở cluster lớn.

---

## How – Follower Fetching (KIP-392, Kafka 2.4+)

```
Consumer Fetch from Follower:
  Default: consumers read from leader (all reads concentrated)
  KIP-392: broker có thể chỉ định preferred read replica cho consumer
    → Reduce cross-AZ network costs
    → Có thể giảm latency/cross-AZ cost khi topology phù hợp
    → Chỉ trả dữ liệu được biết là committed theo HWM local; propagation delay có thể làm dữ liệu mới tạm chưa đọc được
```

```properties
# Consumer config
client.rack=us-east-1a  # consumer's AZ/rack

# Broker replica config
broker.rack=us-east-1a  # for rack-aware replica placement

# Broker phải chọn replica theo rack; default selector thường vẫn chọn leader
replica.selector.class=org.apache.kafka.common.replica.RackAwareReplicaSelector

# Topic: assign replicas across AZs
# Kafka cố gắng phân tán replica theo rack khi rack metadata/assignment hợp lệ
```

Chỉ đặt `client.rack` chưa tự bật closest-replica fetch; broker cần `replica.selector.class` phù hợp. Follower fetching không cố ý trả uncommitted data, nhưng HWM truyền từ leader sang follower có độ trễ nên consumer có thể chờ lâu hơn hoặc tạm quay lại leader. Kiểm tra metric preferred-read-replica và network theo AZ để xác nhận cấu hình thực sự có tác dụng.

> 💡 **Giải thích dễ hiểu — đọc từ follower:**
> Consumer ở AZ-a có thể đọc tại **chi nhánh kho gần nhất** thay vì qua leader ở AZ-b. Chi nhánh chỉ giao tới dấu sổ đã được xác nhận; vì dấu này truyền từ kho chính sang hơi trễ, hàng mới có thể chưa thấy ngay nhưng không được phép giao phần chưa committed.

---

## How – Monitoring Replication

```bash
# Under-Replicated Partitions
kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-replicated-partitions
# → Target 0 ở steady state; có thể tăng tạm trong maintenance/reassignment

# Under minimum ISR partitions
kafka-topics.sh --bootstrap-server localhost:9092 --describe --under-min-isr-partitions

# Offline partitions (no leader!)
kafka-topics.sh --bootstrap-server localhost:9092 --describe --unavailable-partitions

# Describe all topics with replica details
kafka-topics.sh --bootstrap-server localhost:9092 --describe
# Partition: 0  Leader: 1  Replicas: 1,2,3  Isr: 1,2,3

# Log dirs and sizes
kafka-log-dirs.sh --bootstrap-server localhost:9092 \
  --describe --topic-list orders

# Replica lag (JMX)
# kafka.server:type=ReplicaFetcherManager,name=MaxLag,clientId=Replica
```

```
JMX Metrics to monitor:
  UnderReplicatedPartitions:   replica chưa bắt kịp; alert theo duration/scope
  UnderMinIsrPartitionCount:   partition dưới write durability threshold
  OfflinePartitionsCount:      partition không có leader khả dụng
  Controller/quorum health:    active controller, voter lag và majority availability
  IsrShrinks/IsrExpands:       high sustained rate = instability
  LeaderElectionRateAndTimeMs: high = broker restarts or network issues
  ReplicationBytesInPerSec:    replication traffic
  FetcherLag/MaxLag:           follower/reassignment progress (tên metric tùy version)
```

KRaft có bộ metric riêng cho **metadata log**, không phải data partition:

| MBean | Metric/attribute trong tài liệu Kafka | Ý nghĩa |
|---|---|---|
| `kafka.server:type=raft-metrics` | Current Leader, Current Epoch | Quorum có leader ổn định hay election liên tục |
| `kafka.server:type=raft-metrics` | High Watermark, Log End Offset | Tiến độ commit/replicate của metadata log |
| `kafka.server:type=raft-metrics` | Average/Maximum Commit Latency | Độ trễ commit metadata |
| `kafka.server:type=raft-metrics` | Average/Maximum Election Latency | Thời gian bầu active controller |
| `kafka.server:type=broker-metadata-metrics` | Last Applied Record Lag Ms | Broker chậm áp dụng metadata bao lâu |
| `kafka.server:type=broker-metadata-metrics` | Metadata Load/Apply Error Count | Lỗi load/apply metadata |

Hai metric High Watermark/Log End Offset trong `raft-metrics` nói về metadata partition của controller quorum. Không dùng chúng thay cho HWM/LEO hoặc lag của các topic-partition dữ liệu.
Exporter có thể chuẩn hóa tên attribute thành format khác; đối chiếu MBean thực tế của đúng Kafka/JMX exporter version trước khi viết alert rule.

Alert cần phân biệt maintenance dự kiến với sự cố kéo dài. Một URP trong vài giây khi rolling restart khác hoàn toàn hàng nghìn URP tăng dần do disk/network saturation; ghép metric với ISR size, broker health, disk latency, network và reassignment state.

## How – Partition reassignment và replication throttle

Reassignment dùng để đổi broker chứa replica, tăng/giảm RF hoặc cân bằng disk/rack. Đây là data movement thật, khác preferred leader election chỉ đổi vai trò leader.

```bash
# Generate/execute plan bằng kafka-reassign-partitions.sh --bootstrap-server ...
# Khi execute có thể đặt --throttle <bytes-per-second>
# Dùng --verify để theo dõi hoàn tất và kiểm tra/remove throttle sau migration
```

Throttle quá cao có thể bóp nghẹt produce/fetch bình thường; quá thấp hơn tốc độ dữ liệu mới vào thì replica có thể không bắt kịp. Theo dõi lag có giảm hay không, disk/network headroom và chắc chắn dọn các throttle config sau khi hoàn tất.

> 💡 **Giải thích dễ hiểu — reassignment:**
> Reassignment là **chuyển cả kho hàng sang địa điểm mới**, còn preferred election chỉ đổi ai ngồi bàn trưởng kho. Throttle là giới hạn số xe chuyển nhà mỗi giây: quá nhiều xe làm tắc đường production, quá ít xe thì hàng mới vào nhanh hơn hàng chuyển đi và công việc không bao giờ xong.

## How – Failure scenarios và capacity planning

| Sự cố | Điều cần kiểm tra | Hành vi có thể xảy ra |
|-------|-------------------|-----------------------|
| Một follower lỗi/chậm | ISR còn bao nhiêu, min ISR, disk/network | URP tăng; write tiếp tục hoặc bị từ chối tùy ISR/acks |
| Leader broker lỗi | Replica clean/ELR khả dụng, controller quorum | Election, client refresh metadata; partition offline nếu không có ứng viên an toàn |
| Mất một AZ/rack | Replica/controller placement có thật sự trải AZ | Ảnh hưởng nhiều partition cùng lúc; RF=3 không cứu được nếu placement tương quan |
| Network partition | Broker fencing, ISR shrink, controller majority | Có thể mất write availability; leader epoch ngăn client/replica cũ tiếp tục như leader hợp lệ |
| Mất controller majority | KRaft voter placement | Không thể điều phối metadata/election an toàn cho tới khi quorum hồi phục |

Capacity không chỉ là `data size × RF`. Cần thêm index/log overhead, retention/tiered storage policy, disk headroom cho segment/recovery, leader ingress, `(RF-1)` luồng replication, consumer/follower-fetch traffic, cross-AZ cost và băng thông catch-up sau broker/AZ outage. Nhiều partition còn làm tăng metadata, election và recovery work.

---

## Why – Kafka Replication vs Database Replication

```
Kafka:
  Pull-based: followers pull from leader
  ✅ Follower controls rate (no overwhelming slow followers)
  ✅ Batching/fetch loop phù hợp replicated log
  ❌ Leader vẫn phải theo dõi fetch/catch-up state của replica để quản lý ISR/HWM

Database replication:
  Có thể dùng physical/logical log shipping, synchronous/asynchronous standbys hoặc consensus tùy hệ quản trị
  Guarantee không thể suy ra chỉ từ nhãn "push" hay "pull"; phải xem commit quorum và failover policy cụ thể

Kafka ISR vs Database quorum:
  Kafka ISR: dynamic set (falls out when lagging)
    → Flexible: faster writes when followers are slow
  Database Quorum (Raft/Paxos): majority must confirm
    → Strict: write waits for majority regardless of lag

  Kafka trade-off: ISR can shrink to 1 (leader only) during lag
    → Potential durability window if leader fails during lag
    → Mitigated by min.insync.replicas
```

KRaft dùng Raft cho **cluster metadata**, không biến replication của mọi topic-partition thành một Raft majority log. Vì vậy không lấy số controller voter để suy ra số data replica đã ACK, và cũng không lấy RF của topic để suy ra metadata quorum health.

> 💡 **Giải thích dễ hiểu — ISR và quorum:**
> ISR giống **danh sách đội trực có thể co giãn**, còn quorum consensus giống quy định biểu quyết theo đa số thành viên cố định của một nhiệm kỳ. Kafka dùng ISR cho data partition và Raft quorum cho metadata controller; trộn hai danh sách sẽ dẫn tới tính durability sai.

---

## Trade-offs

```
RF=1:
  ✅ Ít storage/replication traffic nhất
  ❌ Data loss on broker failure
  → Dev/test only

RF=3 + min.insync.replicas=2:
  ✅ Thường cho phép write khi ISR giảm từ 3 còn 2
  ❌ Không tự bảo vệ khỏi correlated/AZ/disk failures hoặc ISR đã co trước sự cố
  → Common starting point, phải xác nhận bằng failure model/SLA

RF=3 + min.insync.replicas=3:
  ✅ Từ chối `acks=all` write khi ISR dưới 3
  ❌ Một replica rời ISR có thể làm writes fail
  → Min ISR là availability gate; khi ISR=3, `acks=all` vốn đã chờ cả 3 dù min ISR là 2 hay 3

replica.lag.time.max.ms:
  Low (10s):  ISR shrinks/expands more aggressively (GC pauses cause false shrinks)
  High (60s): tolerates slow followers, but lag detection slower
  → Kafka 4.3 mặc định 30s; tune sau khi đo GC/disk/network và recovery objective

Leader election speed:
  Phụ thuộc heartbeat/session timeout, controller quorum, partition count và client metadata refresh
  → Benchmark controlled failure; không dùng con số ZK/KRaft cố định làm SLA
```

---

## Real-world

```
Production replication checklist:
  ✅ Chọn RF theo failure domain/RPO/RTO; RF=3 chỉ là common starting point
  ✅ Đặt min.insync.replicas ở broker/topic và kiểm tra effective config
  ✅ acks=all for critical producers
  ✅ Quyết định clean/unclean election có phê duyệt business
  ✅ Theo dõi preferred leader imbalance; không phụ thuộc mù vào default theo version
  ✅ broker.rack configured for AZ-aware replica placement
  ✅ Monitor ISR/under-min/offline/controller quorum/reassignment lag
  ✅ Regularly test broker, disk, network partition và AZ failure recovery

Rack-aware assignment (production multi-AZ setup):
  3 brokers: broker-1 (AZ-a), broker-2 (AZ-b), broker-3 (AZ-c)
  RF=3 có thể trải 3 AZ nếu assignment/rack metadata đúng và mỗi AZ đủ broker/capacity
  → Khả năng sống sót còn phụ thuộc min ISR, controller placement và failure đồng thời

MirrorMaker2 (disaster recovery, multi-datacenter):
  See [connect.md](../streams/connect.md) for cross-cluster replication setup
```

---

## Ghi chú – Chủ đề tiếp theo
> [kafka_streams.md](../streams/kafka_streams.md): Kafka Streams API, KStream/KTable/GlobalKTable, stateful operations, joins, windowing, state stores (in-memory, RocksDB), exactly-once processing, topology

### Tài liệu Apache Kafka chính thức

- [Kafka 4.3 replication design](https://kafka.apache.org/43/design/design/#replication)
- [Kafka 4.3 broker configs](https://kafka.apache.org/43/configuration/broker-configs/)
- [Kafka 4.3 monitoring](https://kafka.apache.org/43/operations/monitoring/)
- [Eligible Leader Replicas](https://kafka.apache.org/43/operations/eligible-leader-replicas/)
- [KIP-392: fetch from closest replica](https://cwiki.apache.org/confluence/spaces/KAFKA/pages/95653762/KIP-392%2BAllow%2Bconsumers%2Bto%2Bfetch%2Bfrom%2Bclosest%2Breplica)

---

*Cập nhật lần cuối: 2026-07-27*
