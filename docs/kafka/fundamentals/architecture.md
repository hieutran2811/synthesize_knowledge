---
title: "Kafka Architecture & Core Concepts – Deep Dive"
topic: kafka
level: mixed
review_status: needs_review
content_updated: 2026-07-22
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Kafka Architecture & Core Concepts – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

---

## What – Kafka là gì?

**Apache Kafka** là distributed **event streaming platform** *(nền tảng luồng sự kiện phân tán)* với 3 khả năng chính:
1. **Publish/Subscribe** *(xuất bản/đăng ký)*: **producer** *(bên ghi sự kiện)* gửi events, **consumer** *(bên đọc sự kiện)* nhận events
2. **Store** *(lưu trữ)*: lưu event streams bền vững, có thể replay *(đọc lại)* theo offset
3. **Process** *(xử lý)*: xử lý event streams real-time (Kafka Streams)

Kafka không phải message queue thông thường:
- Record không bị xóa chỉ vì consumer đã đọc; retention policy mới quyết định lúc log segment được dọn
- Consumer có thể đọc lại từ bất kỳ offset nào
- Horizontal scale *(mở rộng ngang)* natively theo partition
- Throughput *(thông lượng)* có thể rất cao, tùy kích thước record, replication, disk/network và workload; không nên coi “hàng triệu msg/s” là cam kết cố định

> 💡 **Giải thích dễ hiểu — Kafka giống kho hàng có sổ vị trí, không phải băng chuyền dùng một lần:**
> Producer đặt kiện hàng vào các ngăn partition. Consumer ghi nhớ mình đã lấy đến vị trí nào, nhưng kiện vẫn nằm trong kho cho tới khi chính sách retention/compaction dọn đi. Nhiều nhóm consumer có thể đọc cùng một kiện theo mục đích khác nhau.

---

## Components

### Broker

**Broker** *(máy chủ lưu và phục vụ dữ liệu)* là role xử lý data plane; **KRaft** *(cơ chế đồng thuận metadata dựa trên Raft)* cung cấp control plane của cluster hiện đại.

```
Kafka server process: có thể đảm nhiệm broker, controller, hoặc cả hai role
Broker: nhận request data từ producer/consumer và lưu các partition replica
Cluster: nhiều broker; số lượng theo capacity, RF và failure domains, không bắt buộc số lẻ
KRaft mode (production-ready từ Kafka 3.3): không cần ZooKeeper
Kafka 4.x: chỉ hỗ trợ KRaft; ZooKeeper mode là legacy của Kafka 3.x

Broker roles:
  broker: lưu data, serve clients
  controller: tham gia metadata quorum, quản lý topic/partition assignment và leadership
  broker,controller: combined mode (tiện cho dev; không cô lập tải controller)
```

Trong KRaft, nhiều controller cùng duy trì **metadata quorum** *(quorum metadata)* bằng log Raft; tại một thời điểm chỉ có một active controller, các controller còn lại là standby/follower. Broker-only không tự trở thành voter của quorum controller. Đây là control plane của cluster, khác với replication log của từng data partition.

Quorum cần đa số controller còn sống để tiếp tục commit metadata: 3 controller chịu được 1 controller lỗi, 5 controller chịu được 2 lỗi. Combined mode phù hợp lab hoặc cluster nhỏ; production thường tách controller và broker để có thể scale/rolling restart độc lập.

> 💡 **Giải thích dễ hiểu — controller là ban quản lý, broker là kho hàng:**
> Ban quản lý thống nhất sơ đồ kho, ai giữ chìa khóa ngăn nào và ngăn nào chuyển sang kho khác. Nhân viên kho mới trực tiếp nhận/giao hàng. Có thể một tòa nhà vừa là văn phòng vừa là kho (combined), nhưng khi vận hành lớn nên tách hai chức năng để một bên quá tải không kéo bên kia theo.

### Topic & Partition

**Topic** *(luồng sự kiện có tên)* là namespace logic. Mỗi topic được chia thành các **partition** *(phân vùng log)*, là đơn vị ordering, replication và parallelism.

```
Topic: logical channel (ví dụ: "orders", "payments", "user-events")
  - Chỉ là metadata; data nằm trong partitions
  - Retention: theo time/size (broker default thường 7 ngày, không phải guarantee cho mọi topic)

Partition: đơn vị parallelism và scalability
  - 1 topic → N partitions
  - Mỗi partition là 1 ordered, append-only sequence of records
  - Mỗi record có offset (monotonically increasing integer, chỉ có ý nghĩa trong partition đó)
  - Partitions distributed across brokers

                  Partition 0: [0][1][2][3][4]... → Broker 1
Topic: orders  →  Partition 1: [0][1][2][3][4]... → Broker 2
                  Partition 2: [0][1][2][3][4]... → Broker 3

Replication: mỗi partition có replication factor (RF) replica
  Leader: broker replica nhận writes và thường phục vụ reads
  Followers: fetch dữ liệu từ leader
  ISR (in-sync replicas): leader + follower đã bắt kịp đủ điều kiện để được bầu làm leader
```

**Leader epoch** *(thế hệ leader)* tăng mỗi khi partition đổi leader. Request/replica protocol dùng epoch để fence *(chặn)* broker cũ tiếp tục ghi sau khi mất leadership. Offset vẫn là vị trí riêng của partition; epoch không phải một loại offset mới.

`ISR` có thể nhỏ hơn toàn bộ replica khi follower chậm hoặc mất kết nối. Chỉ replica đủ điều kiện trong ISR mới thường được chọn làm leader an toàn; **unclean leader election** có thể giữ availability nhưng có nguy cơ mất record chưa commit.

> 💡 **Giải thích dễ hiểu — partition là một quyển sổ có một người ghi chính:**
> Leader là thư ký duy nhất ghi số trang tiếp theo; follower chép lại sổ. ISR là danh sách người đã chép kịp nên có thể tiếp quản. Leader epoch giống số phiên trên con dấu: thư ký cũ cầm con dấu phiên trước sẽ bị từ chối, tránh hai người cùng ghi một quyển.

### Record (Message)

**Record** *(bản ghi sự kiện)* chứa payload cùng metadata. **Offset** *(vị trí logic)* định danh vị trí record trong đúng partition của nó, không phải số thứ tự toàn cluster.

```
Record structure:
  Key:       optional bytes (dùng cho partitioning + compaction)
  Value:     bytes (payload)
  Timestamp: producer hoặc broker time
  Headers:   optional key-value metadata (tracing, routing)
  Partition: assigned partition
  Offset:    position trong partition

  Key = null → default producer partitioner thường sticky theo batch; không mặc định round-robin
  Key != null → hash(serialized key) → cùng partition nếu partition count/partitioner ổn định
```

Nếu record chỉ định partition tường minh, producer dùng partition đó; custom partitioner hoặc `partitioner.ignore.keys` có thể thay đổi quy tắc mặc định. Key giúp giữ ordering cho cùng key **trong một partition**, nhưng tăng số partition có thể làm hash key ánh xạ sang partition khác, nên không bảo toàn thứ tự xuyên suốt việc resize.

> 💡 **Giải thích dễ hiểu — key là mã khách hàng, sticky là gom đơn vào cùng xe:**
> Có key, các đơn của cùng khách hàng thường vào cùng ngăn để giữ thứ tự. Không có key, producer thường gom record vào partition đang có batch để tận dụng network/batching rồi đổi partition khi batch đủ; đó không phải vòng tròn round-robin cố định. Muốn định tuyến đặc biệt, phải cấu hình partitioner hoặc partition cụ thể.

---

## How – Topic Operations

```bash
# Tạo topic
kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic orders \
  --partitions 12 \
  --replication-factor 3 \
  --config retention.ms=604800000 \
  --config min.insync.replicas=2

# List topics
kafka-topics.sh --bootstrap-server localhost:9092 --list

# Describe topic
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic orders
# Topic: orders  PartitionCount: 12  ReplicationFactor: 3
# Topic: orders  Partition: 0  Leader: 1  Replicas: 1,2,3  Isr: 1,2,3

# Alter partitions (chỉ tăng, không giảm)
kafka-topics.sh --bootstrap-server localhost:9092 \
  --alter --topic orders --partitions 24

# Xóa topic
kafka-topics.sh --bootstrap-server localhost:9092 --delete --topic orders

# Config topic
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name orders \
  --alter --add-config retention.ms=86400000  # 1 day

# Describe config
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name orders --describe
```

---

## How – KRaft Mode (Kafka 3.3+ – ZooKeeper-free)

```yaml
# server.properties (KRaft mode)
# Node roles: broker, controller, hoặc broker,controller (combined)
process.roles=broker,controller  # combined mode (dev/small cluster; không cô lập tải)
# Hoặc chọn đúng một alternative:
# process.roles=broker      # dedicated broker node
# process.roles=controller  # dedicated controller node

node.id=1
# Static quorum (cấu hình cũ nhưng vẫn gặp ở cluster đã format theo static)
controller.quorum.voters=1@controller1:9093,2@controller2:9093,3@controller3:9093
# Kafka 4.1+ dynamic quorum dùng bootstrap endpoints thay cho voters:
# controller.quorum.bootstrap.servers=controller1:9093,controller2:9093,controller3:9093

# Listeners
listeners=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
advertised.listeners=PLAINTEXT://broker1.example.com:9092
controller.listener.names=CONTROLLER

# Log directories
log.dirs=/data/kafka

# Format storage (chạy 1 lần khi setup)
# kafka-storage.sh format --config server.properties --cluster-id <uuid>
```

```
KRaft benefits vs ZooKeeper (tùy version/topology):
✅ Simpler: không cần maintain ZooKeeper cluster riêng
✅ Faster metadata operations (fewer round trips)
✅ Metadata quorum và broker dùng cùng control plane Kafka
✅ Có thể vận hành cluster lớn; giới hạn thực tế vẫn phụ thuộc workload
✅ Single security model
```

`controller.quorum.voters` và `controller.quorum.bootstrap.servers` không phải hai danh sách cần bật đồng thời: voters mô tả static membership đã được format, còn bootstrap servers giúp node tìm quorum trong dynamic configuration. Hãy theo đúng mode/feature version của cluster, không copy nguyên xi giữa các version.

---

## How – Producer, Replication & Durability Flow

```text
Producer
  → lấy cluster metadata
  → serialize key/value
  → chọn partition
  → gom batch + compression
  → gửi partition leader
  → follower replicas fetch từ leader
  → leader trả acknowledgment theo cấu hình acks
```

- `acks=0`: producer không chờ broker xác nhận; latency thấp nhưng không biết record có được nhận hay không.
- `acks=1`: leader xác nhận sau khi append local; leader chết trước khi follower bắt kịp có thể mất record.
- `acks=all`: chờ mọi replica đang ở trong ISR xác nhận. `min.insync.replicas` đặt sàn số ISR cần có để write được chấp nhận.

Ví dụ RF=3, `min.insync.replicas=2`, producer dùng `acks=all`: khi ISR còn 2 replica, write vẫn được; khi ISR chỉ còn 1, broker từ chối write để ưu tiên durability. Replication factor một mình không tạo guarantee này nếu producer chọn acknowledgment yếu hoặc cho phép unclean election.

**High watermark** *(mốc dữ liệu đã commit)* phân tách phần log an toàn cho consumer thông thường với phần leader đã append nhưng chưa được ISR xác nhận đầy đủ. Log end offset có thể đi trước high watermark.

> 💡 **Giải thích dễ hiểu — RF là số bản sổ, acks là số chữ ký cần chờ:**
> Có ba bản sao chưa có nghĩa người gửi đã đợi chúng được chép. `acks=all` yêu cầu các thư ký đang trong ISR ký nhận; `min.insync.replicas=2` nói rằng ít nhất hai thư ký phải còn làm việc. Nếu chỉ còn một người, Kafka khóa quầy ghi thay vì nhận đơn có nguy cơ mất.

---

## How – Consumer Group & Offset Flow

```text
subscribe(topic)
  → group coordinator phân công partition
  → consumer fetch batch từ partition leader
  → poll() trả records cho application
  → application xử lý
  → commit offset của record kế tiếp cần đọc
```

Trong classic **consumer group** *(nhóm consumer chia việc)*, mỗi partition chỉ được gán cho tối đa một consumer đang hoạt động trong cùng group; consumer dư có thể idle. Group khác có offset độc lập nên đọc lại cùng topic mà không tranh record với group thứ nhất.

Committed consumer offsets được lưu trong internal compacted topic `__consumer_offsets`; chúng không nằm trong data record và có retention riêng. `auto.offset.reset=earliest/latest` chỉ được dùng khi group không có offset hợp lệ hoặc offset đã ra ngoài log, không phải mỗi lần consumer restart.

- Xử lý xong rồi commit: thường là **at-least-once**; crash giữa hai bước có thể xử lý lại.
- Commit trước rồi mới xử lý: **at-most-once**; crash có thể bỏ sót.
- Rebalance có thể thu hồi và gán lại partition, nên consumer phải phối hợp commit, state và cleanup đúng lifecycle.

> 💡 **Giải thích dễ hiểu — offset là bookmark của từng đội đọc sách:**
> Quyển sách vẫn nằm trong thư viện; mỗi đội lưu bookmark riêng chỉ vào trang kế tiếp. Đặt bookmark sau khi ghi chép xong có thể phải đọc lại một trang khi mất điện; đặt trước thì có thể bỏ qua trang chưa kịp ghi. Rebalance giống đổi người phụ trách từng quyển giữa ca.

---

## How – Retention & Log Compaction

- `cleanup.policy=delete`: xóa log segment đủ điều kiện theo `retention.ms`/`retention.bytes`. Việc dọn theo segment và chạy nền, nên retention không phải thời điểm xóa chính xác cho từng record.
- `cleanup.policy=compact`: cuối cùng giữ ít nhất giá trị mới nhất cho mỗi key trong từng partition. Compaction không đổi thứ tự hay đánh lại offset; các offset bị dọn tạo thành khoảng trống hợp lệ.
- `cleanup.policy=delete,compact`: kết hợp giới hạn thời gian/kích thước với latest-value semantics.
- Record có key và value `null` là **tombstone** *(dấu xóa)* trong compacted topic; tombstone cũng chỉ được giữ trong một khoảng cấu hình để consumer thấy việc xóa.

Compaction là asynchronous và cần key ổn định, không đồng nghĩa topic ngay lập tức chỉ còn đúng một record cho mỗi key. Consumer bám sát head vẫn có thể thấy toàn bộ phiên bản trước khi cleaner dọn; consumer rebuild state lâu hơn phải dựa vào guarantee “ít nhất trạng thái cuối cùng”.

> 💡 **Giải thích dễ hiểu — retention dọn theo thùng, compaction dọn theo mã hồ sơ:**
> Retention vứt cả thùng hồ sơ cũ khi thùng đủ tuổi hoặc kho quá đầy. Compaction duyệt mã khách hàng và giữ bản cập nhật mới nhất, nhưng số trang cũ không được đánh lại nên bookmark vẫn ổn định. Tombstone là phiếu “hồ sơ này đã xóa”.

---

## How – Exactly-once Semantics (EOS)

**Idempotent producer** *(producer chống trùng do retry)* dùng producer ID và sequence number theo partition để broker loại bản gửi lại do retry. Nó không tự loại hai lệnh nghiệp vụ giống nhau do application chủ động gửi.

**Kafka transaction** *(giao dịch Kafka)* cho phép commit/abort atomically các record trên nhiều partition và consumer offsets. Mô hình consume–process–produce cần transactional producer ghi output cùng offset qua transaction; consumer downstream dùng `isolation.level=read_committed` để không thấy record từ transaction bị abort. Kafka Streams đóng gói cơ chế này qua `processing.guarantee=exactly_once_v2`.

EOS này mạnh nhất cho luồng Kafka → xử lý → Kafka. Khi ghi database, gọi HTTP hoặc thanh toán bên ngoài, cần sink phối hợp transaction hoặc idempotency/deduplication; Kafka không thể một mình bảo đảm exactly-once side effect trên hệ thống khác.

> 💡 **Giải thích dễ hiểu — EOS là đóng dấu cả kiện hàng và bookmark trong một giao dịch:**
> Hoặc output mới cùng bookmark đều được chấp nhận, hoặc cả hai bị hủy; vì vậy restart không tạo thêm output đã commit. Nhưng nếu trong lúc đó đã gọi một ngân hàng ngoài Kafka, con dấu Kafka không thể thu hồi giao dịch ngân hàng — bên ngoài vẫn cần mã idempotency hoặc cơ chế phối hợp riêng.

---

## How – Partition Assignment & Balancing

```bash
# Xem partition assignment
kafka-topics.sh --bootstrap-server localhost:9092 --describe --topic orders

# Reassign partitions (load balancing)
# 1. Tạo reassignment plan
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --topics-to-move-json-file topics.json \
  --broker-list "1,2,3,4" \
  --generate

# 2. Execute reassignment
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment.json \
  --execute \
  --throttle 50000000  # 50MB/s; giới hạn bandwidth reassignment, cần theo dõi production

# 3. Verify
kafka-reassign-partitions.sh --bootstrap-server localhost:9092 \
  --reassignment-json-file reassignment.json \
  --verify
```

---

## Why – Kafka vs Alternatives

```
Kafka vs Traditional MQ (RabbitMQ, ActiveMQ):
  MQ:    classic queue thường xóa sau khi ack; replay không phải mô hình chính
  Kafka: message retained → replay, multiple consumers, rewind

Kafka vs Database:
  DB:    tối ưu query/index, transaction và random access
  Kafka: tối ưu append/fetch tuần tự và fan-out stream; nhanh hơn hay không tùy workload

Kafka vs Kinesis/Pulsar:
  Kinesis: managed service gắn với AWS, giảm gánh vận hành
  Pulsar:  kiến trúc compute/storage tách rời, mạnh về multi-tenancy/geo features
  Kafka:   ecosystem rộng, mô hình partition log và nhiều lựa chọn managed/self-hosted
```

So sánh phải gắn với loại sản phẩm/version cụ thể: RabbitMQ Streams có replay khác classic queue; các cloud service thay đổi retention, pricing và giới hạn theo thời gian. Không chọn hệ thống chỉ từ một con số throughput tổng quát.

---

## Compare – Kafka vs RabbitMQ

| Feature | Kafka | RabbitMQ |
|---------|-------|---------|
| Model | Log-based, pull | Queue-based, push |
| Replay | Native theo retention/offset | Hạn chế với classic queue; RabbitMQ Streams hỗ trợ replay |
| Throughput | Tối ưu log tuần tự/batching | Tối ưu routing và queue semantics; phải benchmark |
| Ordering | Per partition | Per queue |
| Consumer groups | Yes (parallel) | Competing consumers |
| Protocols | Custom binary | AMQP, MQTT, STOMP |
| Message routing | Topic + partition | Exchange + routing key |
| Backpressure | Consumer pull/poll và tự quản tiến độ offset | Broker delivery kết hợp prefetch/flow control |
| Use case | Event streaming, log | Task queue, RPC |
| Persistence | Record append vào log; durability phụ thuộc RF/acks/ISR | Durable queue/message là cấu hình |

> 💡 **Giải thích dễ hiểu — Kafka và RabbitMQ là thư viện lưu kho và quầy giao việc:**
> Kafka giữ nhiều bản sự kiện để các đội tự đặt bookmark và đọc lại. Classic queue thường giao một việc cho một worker rồi xóa sau ack. Cả hai đã mở rộng tính năng theo thời gian, nên hãy chọn theo replay, routing, ordering, latency và vận hành thay vì nhãn “nhanh hơn”.

---

## Trade-offs

```
Nhiều partitions:
✅ Higher throughput (more parallelism)
✅ More consumers in group
❌ Tăng metadata, file/index, replication traffic và thời gian recovery/reassignment
❌ Cannot reduce partitions
❌ Tăng partition có thể đổi mapping của keyed records
→ Chọn từ throughput đã benchmark, số consumer tối đa, SLA recovery và headroom tăng trưởng

Replication factor:
RF=1: fast, no redundancy → data loss on broker failure
RF=3: baseline production phổ biến; có thể chịu 1 failure khi ISR/acks/min ISR đúng
RF=5: thêm khả năng chịu lỗi nhưng tăng disk/network/replication cost
→ RF phải đi cùng rack awareness, acks=all, min.insync.replicas và election policy

Retention:
High: more replay capability, more disk
Low: less disk, cannot replay old data
→ Size-based + time-based hybrid retention
```

---

## Real-world

```
Partition sizing rule of thumb:
  partitions_by_write = target write throughput / measured write throughput per partition
  partitions_by_read  = target read throughput / measured read throughput per partition
  partitions_by_group = max consumers cần chạy song song trong một classic consumer group
  Chọn giá trị lớn nhất rồi thêm headroom có kiểm soát.

  Phải benchmark với record size, compression, acks, RF, disk/network,
  producer concurrency và consumer processing thật; không có MB/s cố định cho mọi cluster.

Cluster sizing:
  Capacity bị chặn bởi disk throughput/latency, network, CPU compression,
  page cache, replication traffic và failure headroom.
  Số broker phải đủ đặt RF replica trên failure domains khác nhau.
  Controller quorum sizing là bài toán metadata availability riêng với broker data capacity.

Monitoring (Critical metrics):
  OfflinePartitionsCount > 0 → partition không có leader, data unavailable
  UnderReplicatedPartitions/UnderMinIsrPartitionCount tăng kéo dài → replication/durability risk
  KRaft quorum: CurrentLeader, CurrentEpoch, HighWatermark, MaxFollowerLag/Time
  RequestHandlerAvgIdlePercent giảm kéo dài → kiểm tra broker saturation theo baseline
  Consumer group lag tăng liên tục → consumer không theo kịp hoặc bị lỗi
  Disk usage/latency, network saturation, request latency/error rate
```

> 💡 **Giải thích dễ hiểu — sizing Kafka giống thiết kế đường cao tốc có làn dự phòng:**
> Không thể lấy “mỗi làn chở 10 MB/s” cho mọi loại xe và thời tiết. Hãy đo một partition với đúng record/compression/acks, tính số làn cần thiết rồi giữ chỗ để một broker hỏng mà đường vẫn chịu tải. Theo dõi cả kho dữ liệu lẫn ban điều hành KRaft.

---

## Ghi chú – Chủ đề tiếp theo
> [producers.md](producers.md): Producer configs, acks, idempotence, transactions, partitioning strategies, compression, batching

---

*Cập nhật lần cuối: 2026-07-22*
