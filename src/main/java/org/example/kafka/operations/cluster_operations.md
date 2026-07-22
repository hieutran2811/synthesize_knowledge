# Vận hành Kafka Cluster nâng cao (Day-2 Operations) – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> Tra cứu nhanh thuật ngữ tại [Kafka Glossary](../glossary.md). Bổ trợ cho [Kafka Production](production.md), nơi trình bày JVM/OS tuning, monitoring, security và DR.

---

## What – Day-2 Operations là gì?

**Day-2 operations** *(vận hành hệ thống sau khi đã triển khai)* là toàn bộ công việc giữ Kafka ổn định khi tải, dữ liệu, số lượng máy và phiên bản phần mềm thay đổi. Các công việc chính gồm:

- thêm hoặc gỡ **broker** *(máy chủ lưu replica và phục vụ request Kafka)*;
- **partition reassignment** *(di chuyển replica của partition giữa các broker)*;
- cân bằng dung lượng, traffic và leader;
- áp quota để một client không chiếm hết tài nguyên;
- nâng cấp tuần tự mà vẫn giữ dịch vụ hoạt động;
- thiết kế fault domain theo rack/AZ;
- lập kế hoạch dung lượng và disaster recovery đa cluster.

Một cluster “chạy được” chưa chắc “vận hành được”. Vận hành tốt nghĩa là thay đổi có kế hoạch, có giới hạn blast radius, có tiêu chí dừng và có khả năng rollback.

> 💡 **Giải thích dễ hiểu:**
> Cài Kafka giống xây xong một nhà kho; Day-2 operations là việc điều phối xe ra vào, chuyển hàng khi mở thêm kho, bảo dưỡng mà không đóng cửa và chuẩn bị kho dự phòng khi có cháy.

---

## Why – Vì sao các thao tác vận hành dễ gây sự cố?

Kafka duy trì nhiều bản sao dữ liệu và cho client đọc/ghi liên tục. Khi di chuyển một replica, broker vừa phục vụ traffic production vừa copy một lượng dữ liệu có thể rất lớn qua disk/network. Khi restart broker, các leader có thể chuyển sang broker khác và ISR tạm thời thu hẹp.

Do đó, một thay đổi đúng về mặt chức năng vẫn có thể gây:

- disk hoặc network saturation;
- request latency tăng và timeout dây chuyền;
- under-replicated/offline partition;
- đầy disk ở broker đích;
- controller phải xử lý quá nhiều metadata operation;
- recovery lâu hơn RTO dự kiến.

Nguyên tắc chung: **đo trước → preview/dry-run → giới hạn tốc độ → thay đổi theo đợt nhỏ → xác minh rồi mới tiếp tục**.

---

## Components – Những tín hiệu phải theo dõi

| Nhóm | Tín hiệu quan trọng | Ý nghĩa |
|---|---|---|
| Replication | `UnderReplicatedPartitions`, `OfflinePartitionsCount`, ISR shrink/expand | Replica có theo kịp và partition còn phục vụ được không |
| Reassignment | replica fetcher lag, bytes moved, adding/removing replicas | Tiến độ copy và nguy cơ bị đứng |
| Disk | dung lượng còn trống, disk utilization, log-dir failure | Broker đích còn chỗ và disk có nghẽn không |
| Network | bytes in/out, replication bytes in/out, request queue | Reassignment có lấn traffic ứng dụng không |
| Request | produce/fetch latency, error rate, throttle time | Ảnh hưởng nhìn thấy từ phía client |
| Controller | active controller, metadata quorum lag, event queue | Control plane có ổn định không |

Không quyết định chỉ dựa trên một metric. Ví dụ `UnderReplicatedPartitions=0` chưa chứng minh disk còn đủ chỗ, và disk còn trống chưa chứng minh network đủ băng thông để recovery trong RTO.

---

## How – Partition Reassignment và Throttle

Khi thêm broker, Kafka có thể dùng broker mới cho assignment mới, nhưng **không tự động chuyển toàn bộ partition hiện có** sang broker đó trong Apache Kafka thuần. Muốn cân bằng lại, operator phải chạy reassignment hoặc dùng một hệ thống balancer.

Reassignment cũng được dùng để:

- drain broker trước khi gỡ;
- sửa lệch replica/leader;
- thay đổi replication factor;
- di chuyển dữ liệu khỏi rack, AZ hoặc disk có rủi ro;
- khôi phục cân bằng sau sự cố.

### Quy trình an toàn

```bash
# 1. Sinh kế hoạch đề xuất cho danh sách topic
kafka-reassign-partitions --bootstrap-server b1:9092 \
  --topics-to-move-json-file topics.json \
  --broker-list "1,2,3,4" \
  --generate

# 2. Review plan.json rồi thực thi với replication throttle 50 MB/s
kafka-reassign-partitions --bootstrap-server b1:9092 \
  --reassignment-json-file plan.json \
  --execute \
  --throttle 50000000

# 3. Kiểm tra tiến độ; khi hoàn tất tool sẽ gỡ throttle liên quan
kafka-reassign-partitions --bootstrap-server b1:9092 \
  --reassignment-json-file plan.json \
  --verify
```

**Throttle** *(giới hạn tốc độ)* bảo vệ traffic production bằng cách giới hạn replication bytes. Tool cấu hình rate ở broker và danh sách replica bị throttle ở topic, tương ứng với các config như:

```properties
leader.replication.throttled.rate=50000000
follower.replication.throttled.rate=50000000
leader.replication.throttled.replicas=...
follower.replication.throttled.replicas=...
```

Throttle không phải “càng thấp càng an toàn”. Nếu tốc độ copy thấp hơn tốc độ dữ liệu mới tiếp tục ghi vào partition, lag có thể không bao giờ giảm. Chọn rate bằng thử nghiệm, theo dõi replica lag, latency, disk/network headroom rồi tăng hoặc giảm từng bước.

> 💡 **Giải thích dễ hiểu:**
> Reassignment giống chuyển hàng sang kho mới trong khi cửa hàng vẫn bán. Không giới hạn xe chuyển kho sẽ chặn xe giao hàng cho khách; giới hạn quá thấp thì hàng mới vào nhanh hơn hàng được chuyển và công việc không bao giờ xong.

### Checklist trước và sau reassignment

Trước khi chạy:

- lưu current assignment để rollback;
- kiểm tra broker đích đủ disk, network và rack constraint;
- không chạy đồng thời nhiều maintenance job tranh cùng tài nguyên;
- chia plan lớn thành batch và đặt change window;
- xác định ngưỡng dừng: latency, error, URP, disk utilization.

Sau khi chạy:

- `--verify` đến khi hoàn tất và xác nhận throttle đã được gỡ;
- kiểm tra `UnderReplicatedPartitions=0`, không offline partition;
- so sánh disk/leader/traffic distribution trước và sau;
- kiểm tra client latency/error đã về baseline.

---

## How – Scaling Broker

### Thêm broker

1. Cấp `node.id` duy nhất, đúng `cluster.id`, listener, security và `broker.rack`.
2. Khởi động broker, xác minh broker đã đăng ký với KRaft controller và metric khỏe mạnh.
3. Tính target assignment theo dung lượng thực tế; broker cấu hình khác nhau không nên nhận tải như nhau một cách mù quáng.
4. Reassign theo batch có throttle hoặc dùng balancer.
5. Cân bằng leader nếu distribution lệch; ưu tiên preferred replica bằng công cụ leader election phù hợp.

```bash
kafka-leader-election --bootstrap-server b1:9092 \
  --election-type PREFERRED \
  --all-topic-partitions
```

Preferred leader election chỉ đổi leader trong replica set; nó không chuyển dữ liệu và không sửa assignment sai.

### Gỡ broker

1. Chặn broker nhận assignment mới nếu phiên bản Kafka/công cụ vận hành hỗ trợ **cordon** *(đánh dấu không nhận thêm dữ liệu)*.
2. Reassign toàn bộ replica khỏi broker, kể cả internal topic cần thiết.
3. Chờ reassignment hoàn tất và ISR ổn định.
4. Xác nhận không còn replica/leader trên broker.
5. Shutdown có kiểm soát; với Kafka mới có thể unregister broker sau khi drain theo tài liệu đúng phiên bản.

```bash
# Ví dụ ở Kafka mới: cordon toàn bộ log directory của broker 1
kafka-configs --bootstrap-server b1:9092 --alter \
  --entity-type brokers --entity-name 1 \
  --add-config 'cordoned.log.dirs=*'

# Chỉ unregister sau khi broker đã drain và shutdown
kafka-cluster unregister --bootstrap-server b1:9092 --id 1
```

Tên lệnh/khả năng cordon thay đổi theo release; không copy runbook của Kafka 4.x cho cluster cũ mà chưa kiểm tra upgrade guide.

> 💡 **Giải thích dễ hiểu:**
> Gỡ broker giống đóng một chi nhánh kho. Cordon là ngừng gửi hàng mới tới đó; drain là chuyển hết hàng cũ đi; shutdown chỉ được làm sau khi sổ kho xác nhận không còn món nào bị bỏ lại.

### Scale controller KRaft là bài toán khác

Broker chứa data partition; **controller quorum** *(nhóm controller quyết định metadata)* duy trì control plane. Thêm broker không đồng nghĩa phải thêm controller. Khi thay đổi controller, phải giữ quorum majority, đợi controller mới bắt kịp metadata log và dùng quy trình dynamic/static voter đúng phiên bản Kafka. Không restart quá nửa controller cùng lúc.

---

## How – Cruise Control và Balancer tự động

**Cruise Control** *(dịch vụ mã nguồn mở tối ưu phân bố tải Kafka)* do LinkedIn khởi tạo. Nó thu broker metrics, xây mô hình tải, đánh giá các **optimization goals** *(mục tiêu tối ưu)* rồi đề xuất hoặc thực thi reassignment.

```text
Broker metrics
      ↓
Load model → kiểm tra goal/capacity → optimization proposal
      ↓                              ↓
   anomaly detector             operator review
                                      ↓
                              execute + throttle
```

Các goal thường bao phủ rack awareness, disk/network/CPU capacity, replica distribution và leader distribution. Goal có thứ tự ưu tiên; một phương án cân disk tốt hơn có thể không được phép nếu vi phạm rack awareness hoặc capacity hard goal.

| Thành phần | Vai trò |
|---|---|
| Metrics reporter | Gửi số liệu tải của broker/partition |
| Load monitor | Xây dựng cửa sổ metric đủ tin cậy |
| Analyzer | Tìm proposal thỏa các goal |
| Executor | Thực thi replica/leader movement |
| Anomaly detector | Phát hiện broker failure hoặc load bất thường |

Cruise Control không nên được bật auto-healing ngay ngày đầu. Bắt đầu bằng proposal/dry-run, kiểm tra capacity model, goal order, excluded broker/topic và giới hạn concurrency/throttle. Cluster nhỏ có thể vận hành bằng plan thủ công; cluster lớn hưởng lợi nhiều hơn từ tự động hóa nhưng vẫn cần guardrail.

> 💡 **Giải thích dễ hiểu:**
> Cruise Control giống hệ thống điều phối kho tự tính xem nên chuyển pallet nào sang kho nào. Nếu bản đồ sức chứa sai hoặc mục tiêu chỉ ưu tiên “chia đều số pallet” mà bỏ qua trọng lượng, kế hoạch tự động vẫn có thể làm tình hình xấu hơn.

### Phân biệt với Confluent Self-Balancing

Confluent Self-Balancing Cluster là tính năng của Confluent Platform, tích hợp balancer vào nền tảng và tự động xử lý add/remove broker hoặc uneven load theo cấu hình. Đây không phải là Apache Cruise Control dù hai hệ thống cùng giải bài toán balancing. Managed Kafka cũng có cơ chế riêng; luôn dùng API/runbook của nhà cung cấp.

---

## When – Chọn reassignment thủ công hay balancer?

| Bối cảnh | Cách tiếp cận hợp lý |
|---|---|
| Cluster nhỏ, thay đổi hiếm, workload dễ dự đoán | Plan thủ công, review JSON, chạy theo batch có throttle |
| Cluster lớn, partition nhiều, tải thay đổi thường xuyên | Cruise Control hoặc balancer tương đương, ban đầu ở chế độ proposal |
| Managed Kafka | Dùng cơ chế rebalance/scale của nhà cung cấp; tránh thao tác ngoài control plane được hỗ trợ |
| Sự cố khẩn cấp, metric chưa đủ tin cậy | Ưu tiên plan nhỏ có người review; không bật automation mới giữa incident |
| Heterogeneous broker hoặc placement phức tạp | Khai báo capacity/constraint rõ ràng và xác minh proposal trước khi execute |

Không lấy số broker làm tiêu chí duy nhất. Tần suất thay đổi, mức độ skew, thời gian operator có thể phản ứng và chất lượng metrics mới quyết định giá trị của automation.

---

## How – Client Quotas

**Client quota** *(hạn mức tài nguyên cho client)* chống **noisy neighbor** *(một ứng dụng chiếm tài nguyên làm ảnh hưởng ứng dụng khác)* trong cluster nhiều tenant.

| Quota | Đơn vị | Bảo vệ khỏi |
|---|---|---|
| `producer_byte_rate` | byte/giây/broker | Producer bơm quá nhiều dữ liệu |
| `consumer_byte_rate` | byte/giây/broker | Consumer chiếm băng thông fetch |
| `request_percentage` | % thời gian network + I/O thread của broker | Nhiều request nhỏ, metadata/request storm |
| controller mutation quota | tốc độ mutation metadata | Tạo topic/partition quá mức |

```bash
# Quota theo user principal
kafka-configs --bootstrap-server b1:9092 --alter \
  --entity-type users --entity-name analytics \
  --add-config 'producer_byte_rate=10485760,consumer_byte_rate=10485760'

# Quota request theo client-id
kafka-configs --bootstrap-server b1:9092 --alter \
  --entity-type clients --entity-name analytics-app \
  --add-config 'request_percentage=50'
```

Kafka có thể áp quota theo user, client-id, cặp user/client-id hoặc default; rule cụ thể hơn có độ ưu tiên cao hơn. Byte-rate quota là **per broker**, không phải hard limit toàn cluster. Client kết nối nhiều broker có tổng throughput lớn hơn một rate đơn lẻ.

Khi vượt quota, broker tính delay, trả `throttle_time_ms` và tạm ngừng xử lý channel thay vì coi mỗi lần vượt là lỗi vĩnh viễn. Theo dõi throttle time phía client/broker; quota quá thấp thường biểu hiện thành latency tăng trước khi application timeout.

> 💡 **Giải thích dễ hiểu:**
> Quota giống làn thu phí có giới hạn số xe mỗi phút. Xe vượt định mức không bị phá hủy; nó phải chờ lâu hơn để đường cao tốc còn chỗ cho các đoàn xe khác.

---

## How – Rack/AZ Awareness

**Rack awareness** *(nhận biết miền lỗi vật lý)* giúp Kafka đặt replica của cùng partition lên các rack hoặc availability zone khác nhau.

```properties
# Broker ở AZ A
broker.rack=ap-southeast-1a
```

Các điểm cần nhớ:

- `replication.factor=3` chỉ chịu được lỗi một AZ nếu ba replica thực sự nằm ở các AZ độc lập và cluster còn đủ capacity.
- Số fault domain nên ít nhất bằng replication factor nếu muốn mỗi replica ở một domain khác nhau.
- `min.insync.replicas=2` kết hợp producer `acks=all` giúp bảo vệ ghi khi một replica/AZ mất; nếu ISR thấp hơn ngưỡng, Kafka ưu tiên an toàn và từ chối ghi.
- Reassignment/balancer phải giữ rack constraint; phân bố broker quá lệch giữa AZ có thể khiến tối ưu không khả thi.
- Đổi `broker.rack` không tự chuyển replica đã tồn tại; cần đánh giá/reassign lại.

> 💡 **Giải thích dễ hiểu:**
> Ba bản sao đặt trên ba máy trong cùng một phòng vẫn có thể mất cùng lúc khi phòng mất điện. Rack awareness giống cất ba chìa khóa ở ba tòa nhà khác nhau, nhưng chỉ hữu ích nếu đường đi và sức chứa của các tòa nhà đều đủ.

### Follower fetching và chi phí liên AZ

Kafka hỗ trợ rack-aware replica selection khi broker và client được cấu hình phù hợp, giúp consumer đọc từ replica gần hơn thay vì luôn đi xuyên AZ tới leader.

```properties
# Broker
replica.selector.class=org.apache.kafka.common.replica.RackAwareReplicaSelector

# Consumer
client.rack=ap-southeast-1a
```

Follower fetching giảm cross-AZ egress/latency cho read, nhưng không loại bỏ replication traffic giữa AZ và phải kiểm tra freshness/behavior theo phiên bản hoặc distribution đang dùng. Xem thêm [Replication](../internals/replication.md).

---

## How – Rolling Upgrade không gián đoạn có điều kiện

**Rolling upgrade** *(nâng cấp lần lượt từng node)* cho phép cluster tiếp tục phục vụ trong khi từng broker/controller được thay binary và restart. “Không downtime” chỉ khả thi nếu replication, ISR, client compatibility và capacity đều đủ.

### Trước khi nâng cấp

1. Đọc upgrade guide cho **chính xác** source version → target version; không nhảy qua bước trung gian bị cấm.
2. Kiểm tra Java/client/plugin/Connect/Streams compatibility và breaking changes.
3. Xác nhận cluster khỏe: không offline partition, URP về 0, disk có headroom, controller quorum ổn định.
4. Backup config/metadata cần thiết, kiểm thử downgrade path và đặt rollback criteria.
5. Canary trên môi trường giống production hoặc một broker ít rủi ro trước.

### Trong khi nâng cấp

```text
1. Dừng có kiểm soát một broker.
2. Nâng binary/config rồi khởi động lại.
3. Chờ broker đăng ký, replica catch-up, ISR và latency về ngưỡng an toàn.
4. Chỉ khi đạt health gate mới chuyển sang broker tiếp theo.
5. Với controller KRaft: làm từng controller và luôn giữ majority hoạt động.
```

Sau khi tất cả server chạy target binary và cluster đã soak ổn định, mới finalize **metadata version/feature level** bằng `kafka-features` nếu upgrade guide yêu cầu. Finalize có thể bật protocol/metadata feature mới và làm downgrade khó hoặc không thể; không chạy nó ngay khi broker cuối vừa lên.

```bash
# Ví dụ hình thức lệnh; release-version phải theo target release thực tế
kafka-features --bootstrap-server b1:9092 \
  upgrade --release-version <target-version>
```

Các hướng dẫn cũ dùng `inter.broker.protocol.version` hoặc `log.message.format.version` chỉ áp dụng cho release còn hỗ trợ chúng. Kafka 4.x chỉ hỗ trợ KRaft; cluster ZooKeeper phải có lộ trình migrate trước khi nâng lên 4.x. Không trộn metadata migration với version upgrade trong cùng change nếu tài liệu không cho phép.

> 💡 **Giải thích dễ hiểu:**
> Rolling upgrade giống thay từng bánh xe khi xe đang được nâng trên nhiều trụ. Chỉ tháo một bánh khi các trụ còn lại chắc chắn; “finalize feature” giống khóa bộ phụ tùng cũ sau khi đã chạy thử đủ lâu, nên làm quá sớm sẽ mất đường quay lại.

---

## How – Capacity Planning và Headroom

**Capacity planning** *(lập kế hoạch sức chứa)* phải tính cả tải bình thường, tăng trưởng và thời điểm mất broker/AZ hoặc đang reassignment. Sizing chỉ theo trung bình ngày thường thường thất bại đúng lúc cần recovery.

### Ước lượng storage

```text
Dung lượng dữ liệu gốc
  ≈ retained_bytes_per_second × retention_seconds

Dung lượng cluster
  ≈ dữ liệu gốc × replication_factor × overhead_factor

Dung lượng trung bình mỗi broker
  ≈ dung lượng cluster / số broker chứa data
```

`retained_bytes_per_second` nên lấy từ dữ liệu sau compression đo thực tế. `overhead_factor` bao gồm index, segment, compaction headroom, skew và tăng trưởng. Với compacted topic, retention không đủ để dự đoán kích thước: cần đo tỷ lệ key update và hiệu quả cleaner.

### Các chiều capacity

| Chiều | Cần tính |
|---|---|
| Disk capacity | retention, RF, skew, compaction, segment, tiered storage, headroom recovery |
| Disk throughput/latency | produce + fetch + replication + log cleaner + reassignment đồng thời |
| Network | client in/out, replication theo RF, cross-AZ, replication đa cluster |
| CPU | compression, TLS, request handling, log cleaning |
| RAM | JVM heap và phần lớn RAM còn lại cho OS page cache |
| Partition/leader | metadata/controller cost, file handles, recovery time, consumer parallelism |
| Failure reserve | tải khi mất broker/AZ và thời gian rebuild replica |

Không có con số heap hoặc “disk đầy tối đa” đúng cho mọi cluster. Đặt target headroom dựa trên thời gian bổ sung capacity và RTO. Ví dụ, nếu provision broker mới mất hai giờ thì mức cảnh báo phải đủ sớm để cluster vẫn chịu được peak + một broker hỏng trong hai giờ đó.

> 💡 **Giải thích dễ hiểu:**
> Thiết kế thang máy không chỉ theo số người trung bình lúc trưa mà còn theo giờ cao điểm và lúc một thang hỏng. Kafka cũng cần chỗ trống để vừa phục vụ khách vừa chuyển dữ liệu khi một broker biến mất.

Page cache và sequential I/O là nền tảng hiệu năng Kafka; cấp toàn bộ RAM cho JVM có thể làm cache dữ liệu kém hiệu quả. Xem [Storage](../internals/storage.md) và [Kafka Production](production.md).

---

## Compare – MirrorMaker 2, Cluster Linking và Stretch Cluster

**MirrorMaker 2 (MM2)** *(công cụ replicate giữa cluster dựa trên Kafka Connect)*, **Cluster Linking** *(cơ chế tạo mirror topic của Confluent)* và **stretch cluster** *(một cluster trải qua nhiều fault domain)* giải quyết các bài toán khác nhau; không nên gọi tất cả là “HA đa vùng”.

| Tiêu chí | MirrorMaker 2 (MM2) | Cluster Linking | Stretch Cluster |
|---|---|---|---|
| Bản chất | Kafka Connect consume từ source rồi produce sang target | Confluent broker-side fetch tạo mirror topic | Một Kafka cluster trải nhiều fault domain |
| Giấy phép/hệ sinh thái | Apache Kafka, linh hoạt | Tính năng Confluent | Apache Kafka hoặc distribution, tùy thiết kế |
| Offset record | Target offset có thể khác; checkpoint giúp translate/sync group offset | Mirror topic copy byte-for-byte và giữ record offset | Cùng topic/offset vì chỉ có một cluster |
| Replication | Bất đồng bộ | Bất đồng bộ | Replica protocol nội cluster; ack có thể chịu latency liên vùng |
| Failover | Cần promote traffic, translate/sync offset và runbook | Mirror topic cần failover/promote; offset sync là tùy chọn | Leader election nội cluster |
| Tách blast radius | Tốt: hai cluster độc lập | Tốt: hai cluster độc lập | Thấp hơn: chung control plane |
| Phù hợp | DR/migration/aggregation cần OSS và Connect | DR/migration/data sharing trong Confluent | Nhiều AZ hoặc DC gần nhau, latency thấp và ổn định |

### MirrorMaker 2

MM2 có source connector để mirror data, checkpoint connector để ánh xạ/sync consumer offset và heartbeat connector để quan sát connectivity. Failover không tự động chỉ vì record đã được copy; phải test topic filter, ACL/config sync, consumer offset, lag và DNS/client cutover.

### Cluster Linking

Cluster Linking tạo mirror topic read-only ở destination. Record được copy bất đồng bộ, byte-for-byte và giữ offset; consumer group offset/ACL/config có cơ chế sync riêng và cần bật/cấu hình đúng. Khi DR, `promote` hoặc `failover` biến mirror thành topic writable theo runbook của Confluent. Cluster Linking không mirror mọi internal topic như `_schemas` hoặc transaction state, nên Schema Registry và transactional workload cần kế hoạch riêng.

### Stretch Cluster

Stretch cluster giữ một control plane và một namespace, nhưng latency/packet loss giữa broker ảnh hưởng trực tiếp replication, ISR và produce latency. Nó hợp hơn với nhiều AZ trong một region hoặc site có network ổn định; kéo một cluster qua region xa thường làm failure mode khó dự đoán hơn hai cluster độc lập.

> 💡 **Giải thích dễ hiểu:**
> MM2/Cluster Linking giống hai kho độc lập có xe chở bản sao hàng hóa; hỏng một kho vẫn còn kho kia nhưng cần quy trình đổi địa chỉ giao hàng. Stretch cluster giống một kho duy nhất có nhiều tòa nhà nối bằng băng chuyền: quản lý đơn giản hơn, nhưng đường nối chậm sẽ ảnh hưởng cả hệ thống.

### Active-passive hay active-active?

```text
Active-passive:
  Primary ── async replication ──► DR
  Producer/consumer chỉ chạy ở Primary cho tới failover.

Active-active:
  Cluster A ◄──── replicate có chọn lọc ────► Cluster B
  Hai phía có write → phải xử lý ownership, loop, conflict và dedup.
```

Active-passive thường dễ đạt tính đúng đắn hơn. Active-active không chỉ là bật replication hai chiều; cần quy định topic nào có source of truth, tránh replication loop, unique key toàn cục và diễn tập conflict/failback.

---

## Trade-offs

- Reassignment và balancer giúp scale linh hoạt nhưng tiêu thụ chính disk/network cần cho production traffic.
- Automation giảm thao tác tay nhưng thêm service, metrics pipeline, goal configuration và quyền thực thi có blast radius lớn.
- Quota bảo vệ multi-tenant cluster nhưng quota quá thấp biến thành latency/timeout khó chẩn đoán.
- Rack/AZ awareness tăng fault tolerance nhưng làm tăng cross-AZ traffic và có thể giảm lựa chọn placement.
- Rolling upgrade giảm downtime nhưng kéo dài change window và đòi hỏi health gate nghiêm ngặt.
- Multi-cluster tách blast radius nhưng thêm replication lag, duplicate/gap risk, offset/ACL/schema và failback complexity.

---

## Real-world – Runbook mẫu

### Broker sắp đầy disk

```text
1. Xác minh nguyên nhân: retention, skew, partition nóng, cleaner hoặc disk lỗi.
2. Nếu thêm broker: provision + health check + rack/security config.
3. Preview assignment; chia batch và đặt throttle ban đầu.
4. Execute; theo dõi replica lag, URP, disk/network và client latency.
5. Pause/giảm concurrency nếu vượt ngưỡng; tăng throttle nếu lag không giảm.
6. Verify hoàn tất, gỡ throttle và kiểm tra leader/disk distribution.
```

### Rolling upgrade

```text
Preflight → canary broker → health gate → từng broker → từng controller nếu cần
→ soak test → finalize metadata feature theo upgrade guide → kiểm tra rollback window
```

### DR drill

```text
1. Đo replication lag/RPO thực tế.
2. Chặn hoặc chuyển producer khỏi primary theo runbook.
3. Đợi/cân nhắc remaining lag; promote/failover topic.
4. Sync/translate consumer offsets và chuyển client endpoint.
5. Xác minh duplicate/gap, schema, ACL, transaction và downstream.
6. Ghi lại RTO; diễn tập failback thay vì giả định nó đối xứng.
```

Mỗi runbook cần owner, approval, health gate, abort condition, dashboard và bằng chứng hoàn tất. Không chạy maintenance lớn khi không có người quan sát client-side SLO.

---

## Nguồn chính thức

- [Apache Kafka – Basic Kafka Operations](https://kafka.apache.org/43/operations/basic-kafka-operations/)
- [Apache Kafka – Upgrading](https://kafka.apache.org/43/getting-started/upgrade/)
- [Apache Kafka – KRaft Operations](https://kafka.apache.org/41/operations/kraft/)
- [Apache Kafka – Quotas](https://kafka.apache.org/41/design/design/#design_quotas)
- [Apache Kafka – MirrorMaker 2 Configuration](https://kafka.apache.org/41/configuration/mirrormaker-configs/)
- [LinkedIn – Cruise Control](https://github.com/linkedin/cruise-control)
- [Confluent – Self-Balancing Clusters](https://docs.confluent.io/platform/current/clusters/sbc/index.html)
- [Confluent – Cluster Linking mirror topics](https://docs.confluent.io/platform/current/multi-dc-deployments/cluster-linking/mirror-topics-cp.html)
- [Confluent – Multi-Region Clusters](https://docs.confluent.io/platform/current/multi-dc-deployments/multi-region.html)

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [Kafka Production](production.md), [Architecture/KRaft](../fundamentals/architecture.md), [Replication/ISR](../internals/replication.md), [Storage](../internals/storage.md), [Kafka Connect/MM2](../streams/connect.md), [Event-driven architecture](../patterns/event_driven_architecture.md).

> Keywords: `kafka-reassign-partitions`, `leader.replication.throttled.rate`, `follower.replication.throttled.rate`, Cruise Control goals, Self-Balancing Cluster, `kafka-configs`, client quotas, `broker.rack`, `client.rack`, `replica.selector.class`, preferred leader election, metadata version, `kafka-features`, KRaft quorum, MirrorMaker 2, checkpoint/heartbeat connector, Cluster Linking, mirror topic, RPO/RTO.

---

*Cập nhật lần cuối: 2026-07-22*
