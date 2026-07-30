# 📖 Kafka Glossary – Bảng thuật ngữ Kafka

> Tra cứu nhanh các thuật ngữ Kafka bằng tiếng Việt. Sắp xếp A–Z; thuật ngữ giữ nguyên tiếng Anh để dễ đối chiếu tài liệu và cấu hình thực tế.

---

## A

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Acknowledgment (acks)** | Mức xác nhận ghi | Quy định producer chờ broker xác nhận đến mức nào (`0`, `1`, `all`/`-1`) trước khi coi send thành công. |
| **ACL (Access Control List)** | Danh sách quyền truy cập | Quy tắc authorization xác định principal được phép đọc, ghi, tạo hoặc quản trị topic/group/resource nào. |
| **Active segment** | Segment đang ghi | Segment hiện tại nhận record mới; thường không đủ điều kiện retention delete cho tới khi được đóng/roll. |
| **Apache Kafka** | Nền tảng event streaming | Hệ thống phân tán để publish, lưu giữ và xử lý event stream theo log/partition. |
| **Append-only** | Chỉ ghi nối đuôi | Mô hình thêm record ở cuối log thay vì update tại chỗ; retention/compaction về sau mới dọn segment hoặc phiên bản cũ. |
| **Application ID** | ID ứng dụng Kafka Streams | Tên định danh logic của Streams app, dùng để chia task, đặt internal topics và khôi phục state. |
| **At-least-once** | Ít nhất một lần | Commit sau xử lý giúp hạn chế mất dữ liệu nhưng crash trước commit có thể khiến record được giao lại. |
| **At-most-once** | Tối đa một lần | Commit trước xử lý giảm duplicate nhưng crash sau commit có thể làm mất record chưa xử lý. |
| **Avro** | Định dạng dữ liệu có schema | Định dạng nhị phân gọn, thường dùng cùng Schema Registry để serialize/deserialize event theo schema có version. |

## B

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Backpressure** | Điều tiết ngược | Giảm lượng record nhận hoặc tạm dừng partition khi downstream xử lý chậm, nhưng vẫn phải poll để duy trì group. |
| **Batch size** | Kích thước lô | Số byte producer gom trong một batch trước khi gửi; ảnh hưởng hiệu quả I/O và latency. |
| **Bounded context** | Bối cảnh giới hạn | Ranh giới nghiệp vụ trong DDD; topic/event nên thuộc một domain rõ ràng để tránh schema và ownership chồng chéo. |
| **Broker** | Máy chủ Kafka | Tiến trình lưu partition, nhận request client và phục vụ record; nhiều broker hợp thành cluster. |
| **Burn rate** | Tốc độ tiêu thụ ngân sách lỗi | Tỷ lệ hệ thống đốt error budget nhanh hay chậm; burn cao kéo dài là cơ sở page theo SLO thay vì page mọi metric nội bộ. |

## C

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Capacity planning** | Hoạch định năng lực | Ước lượng throughput, storage, network, partition, RF và headroom để cluster chịu tải hiện tại lẫn tăng trưởng. |
| **CDC (Change Data Capture)** | Thu thập thay đổi dữ liệu | Kỹ thuật đọc insert/update/delete từ database và phát thành event để đồng bộ hoặc xử lý gần thời gian thực. |
| **Certificate rotation** | Xoay vòng chứng thư TLS | Thay certificate/CA trước khi hết hạn bằng giai đoạn trust chồng lấp, canary và rollback để tránh ngắt kết nối cluster/client. |
| **Changelog topic** | Topic nhật ký state | Internal topic ghi thay đổi của state store để task có thể restore state sau khi chuyển instance. |
| **Classic group protocol** | Giao thức consumer group cổ điển | Protocol trong đó client tham gia assignment/rebalance; khác Consumer Group Protocol mới của Kafka 4.x. |
| **Clean leader election** | Bầu leader an toàn | Chọn leader từ ISR hoặc tập ứng viên được protocol chứng minh không thiếu committed data, tránh rollback log tùy ý. |
| **Cleanup policy** | Chính sách dọn log | Kết hợp `delete`, `compact` hoặc `delete,compact` để quyết định cách Kafka loại dữ liệu cũ. |
| **Client quota** | Hạn mức client | Giới hạn byte-rate hoặc request-rate theo user/client-id để một ứng dụng không chiếm hết tài nguyên broker. |
| **Cluster Linking** | Liên kết cluster | Cơ chế replicate/đọc topic giữa cluster theo mô hình liên kết, thường giảm nhu cầu vận hành pipeline MM2 riêng. |
| **Committed offset** | Offset đã commit | Vị trí bền vững Kafka lưu cho group, biểu thị offset kế tiếp cần đọc khi consumer khởi động lại. |
| **Compacted topic** | Topic giữ bản ghi mới nhất theo key | Topic có `cleanup.policy=compact`, thường làm bảng trạng thái; việc dọn diễn ra bất đồng bộ và có thể còn bản ghi cũ tạm thời. |
| **Compatibility mode** | Chế độ tương thích schema | Quy tắc Schema Registry dùng để kiểm tra schema mới có đọc/ghi tương thích với phiên bản trước hay không. |
| **Compression type** | Kiểu nén | Thuật toán nén batch như `gzip`, `snappy`, `lz4`, `zstd`; trade-off CPU, kích thước và latency. |
| **Connect internal topics** | Topic điều hành Kafka Connect | Ba topic compacted lưu connector config, source offset và connector/task status để distributed worker phối hợp và khôi phục. |
| **Connector** | Thành phần kết nối | Plugin Kafka Connect mô tả cách đọc dữ liệu từ source hoặc ghi dữ liệu tới sink. |
| **Connector task** | Đơn vị thực thi connector | Phần công việc connector chia cho worker; `tasks.max` chỉ là trần, số task thực tế phụ thuộc khả năng song song của nguồn/đích. |
| **Consumer** | Client đọc record | Ứng dụng chủ động `poll()` record từ broker và quản lý current position/committed offset. |
| **Consumer group** | Nhóm consumer | Các consumer dùng chung `group.id`; mỗi partition tại một thời điểm chỉ giao cho một member trong group. |
| **Consumer lag** | Độ trễ consumer | Khoảng cách giữa vị trí cuối log và offset consumer đã commit; cần đọc cùng processing latency và transaction state. |
| **Consumer offsets topic (`__consumer_offsets`)** | Topic nội bộ lưu offset group | Topic compacted lưu committed offset và group metadata; phải có replication phù hợp và chỉ quản trị qua API/tooling được hỗ trợ. |
| **Controller** | Thành phần điều phối metadata | Role quản lý metadata cluster, lãnh đạo partition và thay đổi topology; KRaft dùng controller quorum. |
| **Controller directory ID** | ID storage của controller | Định danh duy nhất trong `meta.properties` cho metadata directory; dynamic quorum dùng cùng controller ID khi add/remove voter. |
| **Converter** | Bộ chuyển đổi bytes/schema | Thành phần Kafka Connect chuyển dữ liệu giữa bytes trên Kafka và object/schema mà connector xử lý. |
| **Co-partitioning** | Đồng phân vùng | Các input liên quan có cùng số partition và quy tắc key để record cùng key đến đúng task khi join/group. |
| **Cordon** | Đánh dấu log directory không nhận assignment mới | Kafka 4.3 dùng `cordoned.log.dirs` trước khi drain broker/disk; cordon không tự di chuyển replica hiện có. |
| **CQRS (Command Query Responsibility Segregation)** | Tách luồng ghi/đọc | Pattern tách model xử lý command khỏi model query; Kafka event và compacted topic thường làm trục đồng bộ read model. |
| **Cruise Control** | Công cụ tự cân bằng cluster | Công cụ thu metric, tính goal và tạo kế hoạch di chuyển replica/leader có throttle để cân bằng tải Kafka. |
| **Current position** | Vị trí đọc hiện tại | Vị trí trong bộ nhớ của consumer sau các lần `poll()`, chưa chắc đã được commit bền vững. |

## D

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Commit log** | Nhật ký commit | Log append-only lưu record theo thứ tự trong partition; consumer dùng offset để đọc lại. |
| **Data plane** | Mặt phẳng dữ liệu | Luồng broker lưu/đọc record và replication partition, khác với control plane quản lý metadata. |
| **Day-2 operations** | Vận hành sau triển khai | Các thao tác scale, cân bằng, nâng cấp, quota, capacity và recovery cần làm liên tục sau khi cluster đã chạy. |
| **Dead-letter topic (DLT/DLQ)** | Topic chứa bản ghi lỗi | Nơi lưu poison message sau số lần retry hữu hạn để không chặn mãi partition chính. |
| **Debezium** | Nền tảng CDC | Bộ connector CDC phổ biến, đọc transaction log hoặc cơ chế capture của database rồi phát change event vào Kafka. |
| **Delivery timeout** | Thời hạn giao record | Deadline tổng từ lúc `send()` đến khi broker xác nhận hoặc producer báo lỗi; bao gồm retry và request timeout. |
| **Dirty ratio / dirty tail** | Tỷ lệ / phần log chưa compact | Dirty ratio quyết định segment đủ điều kiện cleaner; dirty tail là các record mới phát sinh sau lần compact trước. |
| **Disaster recovery (DR)** | Khôi phục sau thảm họa | Kế hoạch và bài diễn tập phục hồi Kafka/service sau mất broker, AZ hoặc cả cluster, gồm RPO/RTO và quy trình failover. |
| **Disk sizing** | Tính dung lượng đĩa | Ước lượng data, RF, index, retention, compaction, recovery và headroom thay vì chỉ nhân kích thước payload với RF. |
| **Distributed mode** | Chế độ Connect phân tán | Nhiều worker Kafka Connect phối hợp qua internal topics để chia task và tự khôi phục khi worker lỗi. |
| **Drain** | Rút dữ liệu khỏi broker | Di chuyển toàn bộ replica/leadership khỏi broker trước khi tắt hoặc bảo trì để tránh offline/under-replicated partition. |
| **DR drill** | Diễn tập khôi phục | Bài kiểm tra có kiểm soát việc restore/failover/failback để xác nhận RPO, RTO và runbook thực sự khả thi. |
| **DSL (Domain-Specific Language)** | API ngôn ngữ chuyên biệt | Kafka Streams DSL cung cấp các operation khai báo như filter, groupBy, join và window trước khi build topology. |
| **Dynamic broker config** | Cấu hình broker cập nhật động | Override per-broker hoặc cluster-wide lưu trong metadata log; có thể thắng `server.properties` và cần xóa override để rollback đúng. |
| **Dynamic controller quorum** | Quorum controller đổi membership động | KRaft `kraft.version >= 1` lưu voter membership trong metadata log và hỗ trợ add/remove controller có kiểm soát. |

## E

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Eager rebalancing** | Rebalance thu hồi toàn bộ | Protocol thu hồi toàn bộ assignment rồi phân lại, thường tạo khoảng dừng lớn hơn cooperative rebalance. |
| **Eligible Leader Replicas (ELR)** | Replica đủ điều kiện làm leader | Tập replica ngoài ISR nhưng được KRaft chứng minh không thiếu committed data; dùng sau ISR trong thứ tự election của Kafka mới. |
| **EMIT CHANGES** | Phát kết quả thay đổi | Tùy chọn truy vấn ksqlDB phát kết quả mỗi khi aggregate/table thay đổi thay vì chờ window đóng. |
| **EMIT FINAL** | Chỉ phát kết quả cuối | Tùy chọn windowed query chỉ phát kết quả sau khi window đóng và hết grace period. |
| **Error budget** | Ngân sách lỗi theo SLO | Phần request/thời gian không đạt SLO được chấp nhận trong một cửa sổ; dùng để cân bằng độ tin cậy và tốc độ thay đổi. |
| **Event-carried state transfer** | Event mang theo state | Event chứa đủ dữ liệu cần thiết để consumer cập nhật state mà không phải callback sang service phát event. |
| **Event-Driven Architecture (EDA)** | Kiến trúc hướng sự kiện | Kiến trúc trong đó service giao tiếp chủ yếu bằng event bất biến, giúp producer và nhiều consumer độc lập hơn. |
| **Event notification** | Event thông báo | Event mỏng báo đã xảy ra việc gì và thường chỉ mang ID; consumer phải gọi API hoặc đọc nguồn khác để lấy chi tiết. |
| **Event sourcing** | Lưu lịch sử bằng event | Dùng chuỗi event bất biến làm nguồn sự thật, rồi replay để dựng lại state hiện tại hoặc audit theo thời gian. |
| **Event streaming** | Luồng sự kiện liên tục | Mô hình publish, lưu giữ, replay và xử lý các event theo thời gian thay vì chỉ giao một lần rồi xóa. |
| **Event-time** | Thời gian của sự kiện | Timestamp gắn với event, thường dùng để xếp record vào window thay vì chỉ dựa vào thời điểm máy nhận. |
| **Exactly-once semantics (EOS)** | Ngữ nghĩa đúng một lần | Trong Kafka, transaction có thể nguyên tử hóa việc đọc–xử lý–ghi Kafka; không tự bao phủ DB/API bên ngoài. |

## F

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Failback** | Chuyển dịch vụ về site chính | Sau khi DR ổn định, chuyển traffic hoặc workload từ site dự phòng về site chính theo runbook có kiểm soát. |
| **Failover** | Chuyển sang site dự phòng | Chuyển workload sang cluster/site khác khi site chính lỗi; cần kiểm soát duplicate, offset và DNS/traffic. |
| **Failure domain** | Miền lỗi | Nhóm hạ tầng có thể hỏng cùng nhau, như broker, rack hoặc AZ; replica nên được phân tán qua các miền này. |
| **Fan-out** | Phân phối ra nhiều nhánh | Nhiều consumer group độc lập cùng đọc một topic theo offset riêng. |
| **Feature finalization** | Chốt feature/metadata version | Bước nâng feature level sau khi toàn cluster chạy binary mới; có thể bật thay đổi metadata khiến downgrade không còn khả thi. |
| **Fenced broker** | Broker bị cô lập | Broker bị controller xem là không hợp lệ để nhận leadership hoặc cập nhật state cho tới khi đăng ký/session hợp lệ trở lại. |
| **Fencing** | Cô lập instance cũ | Broker từ chối producer/consumer instance cũ hoặc trùng danh tính để tránh hai owner cùng ghi/giữ partition. |
| **Follower** | Bản sao theo leader | Replica sao chép dữ liệu từ partition leader và có thể trở thành leader khi failover hợp lệ. |

## G

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **GlobalKTable** | Bảng trạng thái toàn cục | KTable được nạp đầy đủ trên mỗi Streams instance, phù hợp lookup nhỏ theo foreign key nhưng tăng storage và restore cost. |
| **Grace period** | Khoảng ân hạn của window | Thời gian cho phép event đến muộn sau window end trước khi bị bỏ qua. |
| **Grafana** | Dashboard quan sát | Công cụ trực quan hóa metric từ Prometheus/JMX exporter để theo dõi throughput, lag, lỗi và saturation. |
| **Group coordinator** | Coordinator của consumer group | Broker chịu trách nhiệm quản lý membership, heartbeat, committed offsets và điều phối rebalance của một group. |

## H

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Hard delete** | Xóa vật lý | Xóa record hoặc key khỏi hệ thống lưu trữ; khác soft delete, vốn giữ event đánh dấu đã xóa. |
| **Headless mode** | Chế độ không giao diện | Chạy ksqlDB hoặc Connect chỉ qua REST/config mà không cần UI tương tác. |
| **Headroom** | Dung lượng dự phòng | Phần CPU, network, disk và broker capacity để hấp thụ peak, mất node hoặc recovery mà không vượt ngưỡng an toàn. |
| **Heartbeat** | Tín hiệu sống | Tín hiệu consumer gửi theo protocol để broker biết member còn hoạt động; không thay thế việc gọi `poll()` đúng hạn. |
| **High watermark** | Biên dữ liệu đã commit | Vị trí exclusive mà consumer được đọc tới; tiến theo trạng thái replication/ISR và không đồng nghĩa log end offset. |
| **Hot partition** | Partition nóng | Partition nhận lệch quá nhiều traffic do key skew, dễ gây broker saturation dù tổng tải cluster còn dư. |

## I

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Idempotent consumer** | Consumer lũy đẳng | Consumer xử lý cùng record nhiều lần nhưng dùng key/deduplication/unique constraint để hiệu ứng nghiệp vụ tương đương một lần. |
| **Idempotent producer** | Producer chống ghi trùng | Producer dùng PID và sequence để broker loại duplicate retry trong phạm vi session và partition phù hợp. |
| **Incrementing mode** | Chế độ JDBC tăng dần | JDBC source connector đọc các dòng có cột số tăng dần, phù hợp dữ liệu chỉ append nhưng không bắt được update/delete. |
| **In-flight request** | Request đang bay | Request đã gửi nhưng chưa nhận response; số lượng quá lớn có thể ảnh hưởng ordering và memory. |
| **Interactive Queries** | Truy vấn state store đang chạy | API cho phép đọc local state store của Streams app; cần định tuyến tới instance đang giữ partition hoặc dùng metadata. |
| **ISR (in-sync replicas)** | Các replica đồng bộ | Tập replica đang theo kịp leader theo điều kiện Kafka dùng để đánh giá commit và failover. |

## J

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **JMX (Java Management Extensions)** | Giao diện metric Java | Cơ chế broker/Connect/Streams phơi bày metric và operational bean để exporter hoặc công cụ giám sát đọc. |

## K

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **KRaft** | Kafka Raft metadata mode | Cơ chế dùng quorum Raft cho metadata Kafka, thay ZooKeeper trong kiến trúc hiện đại. |
| **KRaft controller quorum** | Quorum controller KRaft | Nhóm controller voter sao chép metadata log bằng Raft; cần đa số để election và commit metadata. |
| **KStream** | Luồng sự kiện Kafka Streams | Abstraction cho chuỗi record độc lập, không giới hạn; mỗi record được xử lý như một event thay vì update trạng thái của key. |
| **KTable** | Bảng trạng thái Kafka Streams | Changelog theo key biểu diễn giá trị hiện tại; record mới cùng key thay thế trạng thái trước và tombstone xóa key. |

## L

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Last known leader** | Leader hợp lệ gần nhất | Leader gần nhất controller biết cho một partition; protocol ELR có thể xét lại nếu ISR/ELR rỗng và broker chưa bị fenced. |
| **Last Stable Offset (LSO)** | Offset ổn định cuối | Mốc consumer `read_committed` không vượt qua khi transaction vẫn đang mở. |
| **Leader** | Replica dẫn đầu | Replica nhận write/read chính cho một partition và điều phối replication tới follower. |
| **Leader epoch** | Thế hệ leader | Số thế hệ tăng khi leadership đổi, giúp broker phát hiện log/metadata cũ và bảo vệ truncate/fetch. |
| **Linger** | Thời gian chờ gom batch | Khoảng thời gian producer chờ thêm record để batch đầy hơn trước khi gửi. |
| **Local retention** | Retention tại broker | Thời gian/kích thước giữ segment trên local disk khi dùng tiered storage, khác với vòng đời remote tổng thể. |
| **Log cleaner** | Tiến trình dọn log compact | Background thread đọc dirty segments, giữ phiên bản cần thiết theo key rồi rewrite segment mới. |
| **Log compaction** | Nén log theo key | Giữ bản ghi mới nhất theo key, thường dùng làm changelog; không đồng nghĩa xóa ngay mọi bản ghi cũ. |
| **Log end offset** | Vị trí cuối log dạng exclusive | Offset ngay sau record cuối hiện có; thường dùng làm mốc tính consumer lag, không phải offset của chính record cuối. |
| **Log start offset** | Offset nhỏ nhất còn đọc được | Mốc đầu phạm vi broker còn phục vụ; tăng khi total retention hoặc log truncation loại dữ liệu cũ. |
| **LSN (Log Sequence Number)** | Vị trí trong transaction log | Mốc byte/sequence của WAL hoặc transaction log database, dùng CDC để resume và phát hiện khoảng dữ liệu còn thiếu. |

## M

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Magic byte** | Byte nhận diện wire format | Byte đầu trong một số serializer wire format, giúp deserializer biết cách diễn giải payload phía sau. |
| **Materialized state store** | State store được vật hóa | State store được đặt tên và materialize để truy vấn hoặc khôi phục qua changelog/standby. |
| **Materialized view** | View đã tính sẵn | Kết quả truy vấn hoặc aggregate được lưu thành state để đọc nhanh thay vì tính lại toàn bộ input. |
| **max.block.ms** | Thời gian chờ thao tác producer | Giới hạn thời gian `send()` chờ metadata hoặc buffer còn chỗ trước khi ném lỗi. |
| **max.in.flight.requests.per.connection** | Số request đồng thời tối đa | Giới hạn request chưa hoàn tất trên connection; cần cân bằng throughput với ordering/retry. |
| **max.poll.interval.ms** | Khoảng cách poll tối đa | Thời gian tối đa giữa hai lần `poll()` trước khi consumer bị xem là không tiến triển trong group. |
| **Metadata log** | Nhật ký metadata KRaft | Log Raft lưu thay đổi broker registration, topic, assignment, leader, ISR và configuration; không chứa payload topic. |
| **Metadata quorum** | Quorum metadata | Nhóm controller duy trì log Raft và cần đa số đồng thuận để cập nhật metadata cluster. |
| **Metadata version** | Phiên bản metadata/protocol | Feature level của cluster quyết định protocol/metadata feature nào được bật sau khi các broker đã chạy binary tương thích. |
| **min.insync.replicas** | Số replica đồng bộ tối thiểu | Ngưỡng replica ISR cần có để request `acks=all` được chấp nhận khi topic cấu hình phù hợp. |
| **MirrorMaker 2 (MM2)** | Sao chép topic liên cluster | Bộ connector Kafka Connect replicate topic và metadata giữa cluster; cần quy ước tên topic, offset sync và ACL. |

## N

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Noisy neighbor** | Hàng xóm gây nhiễu | Client hoặc tenant tiêu thụ quá nhiều broker resource, làm latency/throughput của ứng dụng khác suy giảm; quota giúp giảm tác động. |

## O

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Offline log directory** | Thư mục log ngừng phục vụ | Log directory bị Kafka đánh dấu offline sau lỗi storage; các replica trong đó không còn khả dụng cho tới khi được khôi phục/di chuyển. |
| **Offset** | Vị trí record | Số thứ tự tăng trong từng partition; offset chỉ có ý nghĩa trong phạm vi partition đó. |
| **Offset flush** | Ghi bền offset Connect | Worker Kafka Connect định kỳ ghi offset source vào internal offset topic để restart có thể resume gần vị trí cũ. |
| **Offset index** | Index offset | Sparse index ánh xạ offset tương đối tới vị trí byte trong file log để broker tìm record nhanh hơn. |
| **Offset out of range** | Offset nằm ngoài dữ liệu còn giữ | Consumer yêu cầu vị trí nhỏ hơn log start hoặc lớn hơn log end; reset policy quyết định nhảy mốc hay báo lỗi. |
| **Offset reset** | Chính sách đặt lại offset | Quyết định đọc từ `earliest`, `latest` hoặc báo lỗi khi group chưa có committed offset hợp lệ. |
| **Offset translation** | Ánh xạ offset liên cluster | Metadata/record mapping dùng khi chuyển consumer giữa cluster để tìm vị trí tương ứng, không phải phép cộng offset đơn giản. |
| **Optimization goals** | Mục tiêu tối ưu tải | Các tiêu chí balancer như disk, network, CPU, replica/leader count và rack dùng để chọn kế hoạch di chuyển. |
| **Outbox pattern** | Mẫu hộp thư ngoài | Ghi thay đổi nghiệp vụ và outbox event trong cùng transaction DB, rồi CDC/relay phát event sang Kafka để tránh dual-write. |

## P

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Page cache** | Bộ đệm file của hệ điều hành | RAM do OS dùng cache log/index; Kafka tận dụng cho append và tail read thay vì giữ toàn bộ dữ liệu trong JVM heap. |
| **Partition** | Phân vùng log | Chuỗi record có thứ tự, là đơn vị parallelism, replication và assignment cho consumer group. |
| **Partitioner** | Bộ chọn partition | Logic chọn partition từ topic/key/cluster metadata; key thường giúp giữ record liên quan cùng partition. |
| **Partition reassignment** | Di chuyển replica partition | Kế hoạch chuyển replica giữa broker để scale/drain/cân bằng; nên thực hiện từng bước với throttle và theo dõi ISR. |
| **Pause / resume** | Tạm dừng / tiếp tục partition | Tạm ngưng trả record từ partition cụ thể trong khi consumer vẫn `poll()` để duy trì membership. |
| **Persistent query** | Truy vấn chạy liên tục | Truy vấn ksqlDB tạo topology và ghi kết quả vào Kafka topic/state thay vì chỉ trả một response tức thời. |
| **Plugin isolation** | Cô lập dependency plugin | Kafka Connect nạp plugin trong classloader riêng để giảm xung đột dependency; mọi worker vẫn phải có cùng artifact/version. |
| **Poison message** | Bản ghi độc | Record luôn thất bại khi xử lý, cần retry hữu hạn rồi chuyển DLT/DLQ để không chặn tiến trình. |
| **Preferred leader election** | Bầu leader ưu tiên | Đưa replica preferred lên leader sau reassignment/restart để phân bổ leadership theo kế hoạch. |
| **ProcessingExceptionHandler** | Handler lỗi xử lý Streams | Policy quyết định fail hay tiếp tục khi code processor/DSL ném lỗi; skip không có audit có thể gây mất dữ liệu im lặng. |
| **Processor API** | API xử lý mức thấp | API Kafka Streams cho phép tự định nghĩa processor, context, state store và forward record thay vì chỉ dùng DSL. |
| **Producer** | Client ghi record | Ứng dụng serialize và gửi `ProducerRecord` tới broker, chịu trách nhiệm partitioning, batching và retry. |
| **ProducerRecord** | Bản ghi gửi đi | Object chứa topic, key, value, partition/timestamp tùy chọn và headers trước khi serialize. |
| **Prometheus** | Hệ thống thu metric | Hệ thống scrape metric dạng time series từ broker/exporter để alert và làm nguồn dữ liệu cho Grafana. |
| **Protobuf** | Định dạng dữ liệu schema | Định dạng nhị phân do Protocol Buffers định nghĩa, thường kết hợp Schema Registry để quản lý version và compatibility. |
| **Publication (PostgreSQL)** | Tập bảng phát logical replication | Đối tượng PostgreSQL xác định bảng/thao tác được gửi qua `pgoutput`; Debezium có thể dùng publication được DBA tạo sẵn. |
| **Pull query** | Truy vấn trạng thái hiện tại | ksqlDB pull query đọc giá trị hiện có của table/materialized state cho một key, phù hợp request/response. |
| **Push query** | Truy vấn phát liên tục | ksqlDB push query mở luồng kết quả và gửi record mới khi stream/table thay đổi. |

## R

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Rack awareness** | Nhận biết rack/AZ | Phân bố replica trên failure domain khác nhau để một rack/AZ hỏng không làm mất toàn bộ bản sao. |
| **Rebalance** | Phân phối lại partition | Quá trình group coordinator thay đổi assignment khi member, subscription hoặc metadata thay đổi. |
| **Record** | Bản ghi Kafka | Đơn vị dữ liệu gồm key, value, timestamp, headers, partition và offset. |
| **RecordAccumulator** | Bộ đệm record của producer | Cấu trúc bộ nhớ gom record thành batch theo topic-partition trước khi sender thread gửi. |
| **RecordNameStrategy** | Đặt subject theo record name | Subject naming strategy dùng full name của Avro/Protobuf record, cho phép nhiều topic dùng cùng schema theo loại record. |
| **Recovery bandwidth** | Băng thông dành cho phục hồi | Throughput disk/network còn lại để rebuild replica trong RTO khi cluster vẫn phục vụ client traffic. |
| **Remote Log Metadata Manager (RLMM)** | Bộ quản lý metadata log từ xa | Thành phần theo dõi mapping/metadata của segment đã offload trong tiered storage; implementation tùy provider. |
| **Remote retention** | Retention ở kho xa | Vòng đời segment trong remote object storage, có thể dài hơn local retention nhưng vẫn chịu chi phí lưu trữ/egress. |
| **Repartition topic** | Topic tái phân vùng | Internal topic Kafka Streams dùng sau khi đổi key để shuffle record về đúng partition trước stateful operation. |
| **Replica** | Bản sao partition | Một bản log của topic-partition trên broker; một replica làm leader và các replica còn lại thường làm follower. |
| **Replica lag** | Độ trễ replica | Khoảng replica follower chậm fetch/catch-up so với leader; phải đánh giá theo thời gian và workload, không chỉ một offset gap. |
| **Replication factor (RF)** | Hệ số nhân bản | Số replica của mỗi partition; RF cao tăng khả năng chịu lỗi nhưng tốn storage/network. |
| **Replication slot (PostgreSQL)** | Điểm giữ WAL cho subscriber | Logical slot giữ vị trí/segment WAL cần cho CDC; connector dừng lâu có thể làm WAL và disk tăng mạnh. |
| **Replication throttle** | Giới hạn tốc độ replication | Giới hạn băng thông reassignment/catch-up để di chuyển replica không làm nghẽn cluster production. |
| **Request latency breakdown** | Phân rã độ trễ request | Tách total time thành queue, local processing, chờ follower, response queue và send time để khoanh vùng bottleneck. |
| **Retention policy** | Chính sách lưu giữ | Quy tắc theo thời gian/kích thước hoặc compaction quyết định khi log segment đủ điều kiện được dọn. |
| **Retry topic** | Topic thử lại | Topic trung gian giữ record lỗi để retry sau backoff; cần giới hạn số lần, theo dõi lag và cân nhắc ordering. |
| **Rolling upgrade** | Nâng cấp lần lượt | Nâng binary từng broker/controller với capacity, ISR và compatibility đủ để cluster tiếp tục phục vụ. |
| **RPO (Recovery Point Objective)** | Mục tiêu mất dữ liệu | Lượng dữ liệu tối đa chấp nhận mất khi DR, thường tính theo thời gian hoặc offset/event. |
| **RTO (Recovery Time Objective)** | Mục tiêu thời gian khôi phục | Thời gian tối đa từ lúc sự cố đến khi dịch vụ đạt trạng thái phục vụ theo SLO. |
| **Runbook** | Sổ tay vận hành | Tài liệu thao tác có điều kiện dừng, lệnh, metric xác minh, rollback và người chịu trách nhiệm. |

## S

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Saga pattern** | Mẫu giao dịch phân tán | Chuỗi local transaction giữa service, mỗi bước có compensation khi bước sau thất bại; Kafka event thường làm kênh điều phối. |
| **SASL (Simple Authentication and Security Layer)** | Cơ chế xác thực | Framework xác thực client/broker bằng cơ chế như SCRAM, OAUTHBEARER hoặc GSSAPI trước khi cấp quyền truy cập. |
| **Schema compatibility** | Tương thích schema | Quy tắc cho phép schema mới/cũ đọc dữ liệu của nhau, ví dụ BACKWARD, FORWARD hoặc FULL. |
| **Schema ID** | ID schema | Số định danh schema trong Schema Registry, thường được serializer ghi vào wire format để consumer tra schema tương ứng. |
| **Schema normalization** | Chuẩn hóa schema | Biến các schema tương đương về biểu diễn chuẩn để tránh đăng ký trùng chỉ vì khác thứ tự hoặc cách viết. |
| **Schema reference** | Tham chiếu schema | Liên kết một schema với schema khác, giúp tái sử dụng type chung thay vì nhúng lặp lại định nghĩa. |
| **Schema Registry** | Kho quản lý schema | Dịch vụ lưu schema, version và compatibility; producer/consumer dùng schema ID để serialize/deserialize nhất quán. |
| **Schema version** | Phiên bản schema | Số version tăng theo subject khi schema mới được đăng ký hợp lệ. |
| **Segment rollover** | Cuộn segment | Đóng segment active và mở segment mới khi đạt ngưỡng size/time; tên segment dùng base offset. |
| **Serializer** | Bộ tuần tự hóa | Chuyển key/value Java thành bytes để producer gửi; deserializer làm chiều ngược lại ở consumer. |
| **Session timeout** | Thời gian hết phiên | Khoảng không nhận heartbeat trước khi broker loại consumer khỏi group trong classic protocol. |
| **Sink connector** | Connector đích | Kafka Connect đọc record từ Kafka và ghi sang hệ thống ngoài như JDBC, Elasticsearch hoặc object storage. |
| **SLO (Service Level Objective)** | Mục tiêu cấp dịch vụ | Mục tiêu đo được về availability, latency, throughput hoặc lag dùng để đánh giá Kafka/service có đáp ứng cam kết hay không. |
| **SMT (Single Message Transform)** | Biến đổi từng message | Bước biến đổi stateless trên từng record trong Kafka Connect, ví dụ đổi tên field hoặc route topic. |
| **Snapshot (CDC)** | Ảnh dữ liệu ban đầu | Lần đọc nhất quán dữ liệu hiện có trước khi CDC tiếp tục stream thay đổi từ vị trí transaction log tương ứng. |
| **Soft delete** | Xóa logic | Ghi event/flag biểu thị bản ghi đã xóa nhưng vẫn giữ dữ liệu hoặc lịch sử để downstream xử lý. |
| **Source connector** | Connector nguồn | Kafka Connect đọc dữ liệu từ hệ thống ngoài và chuyển thành record để ghi vào Kafka. |
| **Source offset** | Checkpoint của nguồn Connect | Vị trí riêng của source connector như file position hoặc LSN, được Connect lưu để resume; sửa sai có thể replay hoặc bỏ dữ liệu. |
| **Sparse index** | Index thưa | Index chỉ lưu một số mốc offset/byte theo interval, sau đó broker scan phần nhỏ còn lại trong segment. |
| **Standby replica** | State store dự phòng | Bản sao state store của Streams task trên instance khác, giúp giảm thời gian restore khi active task chuyển máy. |
| **State store** | Kho trạng thái cục bộ | Cấu trúc lưu state theo task, có thể in-memory hoặc persistent; changelog giúp restore nhưng không biến nó thành DB phân tán. |
| **Static membership** | Membership tĩnh | Dùng `group.instance.id` ổn định để restart ngắn không nhất thiết gây rebalance ngay. |
| **Sticky partitioning** | Phân partition dạng bám dính | Với record không key, producer tạm giữ partition để gom batch hiệu quả rồi mới chuyển. |
| **Streams Rebalance Protocol** | Giao thức cân bằng Kafka Streams | Protocol broker-driven dành riêng cho Streams group từ Kafka 4.2, dùng coordinator tính task assignment và group metadata. |
| **Streams task** | Đơn vị thực thi topology | Phần topology gắn với nhóm input partition và state tương ứng; task được phân cho stream thread/instance khi rebalance. |
| **Stream-time** | Thời gian tiến theo stream | Clock logic lấy timestamp lớn nhất đã xử lý; dùng để đóng window và đánh giá event đến muộn. |
| **Stretch cluster** | Cluster kéo dài nhiều site | Một cluster Kafka trải trên nhiều AZ/site; latency, quorum và network partition khiến thiết kế này khó hơn multi-cluster DR. |
| **Subject** | Tên không gian schema | Khóa logic Schema Registry dùng để gom các version schema, thường gắn với topic và key/value. |
| **Subject naming strategy** | Quy tắc đặt subject | Cách ánh xạ topic/key/value hoặc record name thành subject, quyết định phạm vi compatibility. |
| **Suppression** | Trì hoãn phát kết quả Streams | Buffer update của aggregation và chỉ phát theo điều kiện như khi window đóng; cần sizing memory và grace rõ ràng. |

## T

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Tasks.max** | Số task tối đa mỗi connector | Giới hạn số task mà Kafka Connect tạo cho một connector; throughput thực tế còn phụ thuộc partition và source/sink. |
| **Throttle** | Giới hạn tốc độ | Giới hạn replication/reassignment hoặc client traffic để thao tác bảo trì không bão hòa network/disk production. |
| **Tiered storage** | Lưu trữ phân tầng | Offload segment cũ từ local broker disk sang remote storage; cần provider/plugin và theo dõi local/remote retention. |
| **Time index** | Index timestamp | Ánh xạ timestamp gần đúng tới offset để hỗ trợ seek theo thời gian. |
| **TimestampExtractor** | Bộ lấy timestamp record | Kafka Streams component chọn event/ingestion time từ record để điều khiển stream-time, window, join và late-event handling. |
| **Timestamp+incrementing mode** | Chế độ JDBC kết hợp | JDBC source connector lọc theo timestamp và cột tăng dần để bắt update/insert với thứ tự ổn định hơn. |
| **TLS (Transport Layer Security)** | Mã hóa đường truyền | Bảo vệ traffic client-broker, broker-broker và REST bằng encryption, certificate và xác thực tùy cấu hình. |
| **Tombstone** | Bản ghi xóa logic | Record có key và value `null`, báo log compaction xóa key sau khi tombstone đủ điều kiện hết hạn. |
| **Topic** | Kênh logic | Tên logic gom các partition; retention, compaction và ACL thường được cấu hình ở cấp topic. |
| **Topic naming strategy** | Quy tắc đặt tên topic | Quy ước ghép domain/entity/event hoặc environment để topic dễ quản trị, phân quyền và khám phá. |
| **Topic prefix** | Tiền tố tên topic | Chuỗi đặt trước tên topic khi connector hoặc MM2 tạo topic, giúp phân biệt nguồn/cluster. |
| **Topology** | Đồ thị xử lý | DAG các source, processor, stateful operation và sink mà Kafka Streams build thành task chạy được. |
| **TopologyTestDriver** | Bộ chạy test topology | Công cụ test Kafka Streams topology trong memory bằng input/output topic giả lập, không cần cluster thật. |
| **Transaction** | Giao dịch Kafka | Nhóm ghi Kafka và offset liên quan được commit/abort nguyên tử khi producer cấu hình transaction đúng cách. |
| **Transactional.id** | Danh tính producer giao dịch | ID ổn định cho logical producer để broker quản lý transaction và fence instance zombie. |
| **Transaction index** | Index transaction | File index hỗ trợ theo dõi transaction/aborted batches để consumer `read_committed` lọc dữ liệu phù hợp. |

## U

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **UDAF (User-Defined Aggregate Function)** | Hàm aggregate tự định nghĩa | Hàm ksqlDB nhận nhiều row/event và duy trì trạng thái để trả một giá trị tổng hợp. |
| **UDF (User-Defined Function)** | Hàm tự định nghĩa | Hàm ksqlDB xử lý từng row/event và trả giá trị mới, không tự duy trì aggregate state. |
| **UDTF (User-Defined Table Function)** | Hàm trả nhiều row | Hàm ksqlDB có thể biến một input thành nhiều row để mở rộng stream/table. |
| **Unclean leader election** | Bầu leader không đồng bộ | Cho replica ngoài ISR lên leader khi cần availability, nhưng có thể làm mất record chưa replicate. |
| **Under-replicated partition (URP)** | Partition thiếu replica đồng bộ | Partition có follower chưa theo kịp leader; URP kéo dài là tín hiệu cluster chịu tải hoặc broker/network có vấn đề. |

## W

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **WAL (Write-Ahead Log)** | Nhật ký ghi trước | Transaction log PostgreSQL ghi thay đổi trước data page; Debezium đọc logical changes từ WAL qua replication slot. |
| **Windowing** | Chia dữ liệu theo cửa sổ thời gian | Gom record theo tumbling, hopping, sliding hoặc session window để aggregate/join theo thời gian. |
| **Wire format** | Định dạng truyền bytes | Quy ước sắp xếp magic byte, schema ID và payload để serializer/consumer hiểu cùng một message. |
| **Worker** | Tiến trình Kafka Connect | JVM chạy connector/task; distributed worker phối hợp với worker khác qua internal topics. |

## Z

| Thuật ngữ | Nghĩa | Giải thích ngắn |
|-----------|-------|-----------------|
| **Zero-copy / sendfile** | Sao chép bằng kernel | Cách broker truyền file log qua socket với ít copy user-space hơn, giảm CPU nhưng vẫn phụ thuộc OS/storage. |

---

> Glossary được bổ sung cùng từng vòng rà soát tài liệu để thuật ngữ, cấu hình và mô hình vận hành luôn có cùng cách giải thích.
