---
title: "MongoDB Glossary"
topic: mongodb
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# MongoDB Glossary

> Bảng tra cứu nhanh các thuật ngữ dùng trong learning path MongoDB. Nội dung ưu tiên cách hiểu thực hành với MongoDB 8.2.

| Thuật ngữ | Nghĩa ngắn gọn | Điểm cần nhớ |
|---|---|---|
| **Abort** | Kết thúc transaction attempt mà không công bố các write của attempt đó | Business/external side effect ngoài MongoDB không tự được hoàn tác. |
| **Access Pattern** | Cách ứng dụng lọc, sort, đọc và ghi dữ liệu trong một workflow | Là đầu vào của schema/index design; phải kèm tần suất, SLA, cardinality và growth. |
| **Accumulator** | Phép tổng hợp state qua nhiều document như `$sum`, `$avg`, `$first` | Context quyết định cú pháp và semantics; accumulator không phải pipeline stage. |
| **ACID** | Atomicity, Consistency, Isolation, Durability của transaction | Là guarantee kỹ thuật; application vẫn phải định nghĩa invariant và retry đúng. |
| **Aggregation Expression** | Biểu thức tính một giá trị từ field, literal hoặc expression khác | Dùng bên trong stage như `$project`, `$set`, `$group`; cần giữ đúng BSON type. |
| **Aggregation Pipeline** | Chuỗi stage biến đổi, lọc, nhóm hoặc kết hợp document | Tối ưu stage order và index; pipeline không tự miễn phí chỉ vì chạy server-side. |
| **Approximation Pattern** | Lưu hoặc tính giá trị xấp xỉ thay vì kết quả chính xác tuyệt đối | Chỉ dùng khi business chấp nhận sai số; phải công bố error/freshness contract. |
| **Arbiter** | Replica set member chỉ bỏ phiếu election và không giữ dataset | Không tăng data redundancy, không phục vụ read và không xác nhận durability. |
| **Archive Pattern** | Di chuyển dữ liệu lạnh khỏi working set chính | Cần retention, query path và restore/audit rõ ràng. |
| **Atomicity** | Operation hoàn tất toàn bộ hoặc không tạo thay đổi trung gian nhìn thấy | MongoDB write atomic tự nhiên ở mức một document; nhiều document có thể cần transaction. |
| **Attribute Pattern** | Gom các field cùng bản chất thành danh sách key-value | Giảm số index cho tên field động nhưng array/type vẫn cần bound và validation. |
| **Audit Log** | Chuỗi event phục vụ điều tra ai làm gì, khi nào và từ đâu | Gửi sang storage/SIEM tách biệt, immutable; filter và volume phải được benchmark. |
| **Authentication** | Quá trình xác minh identity đang kết nối | Khác authorization; password/certificate vẫn phải đi qua TLS an toàn. |
| **Authorization** | Quyết định identity đã xác thực được phép làm operation nào | MongoDB dùng RBAC; nhiều role được union chứ không phủ định lẫn nhau. |
| **Backup Artifact** | Snapshot, archive hoặc dump dùng làm đầu vào cho recovery | Phải có integrity, encryption, version/key metadata và restore evidence. |
| **Backup Window** | Khoảng thời gian dành cho backup với change/write constraints đã định | Phải đủ dài và có cleanup nếu lock/balancer state không trở lại bình thường. |
| **Balancer** | Tiến trình nền di chuyển data range để sửa phân bố và thực thi zone policy | Cân ownership/ranges, không tự cân CPU, cache, QPS hay hot tenant. |
| **Blocking Stage** | Stage phải giữ nhiều input/state trước khi có thể trả output | `$group`, sort không có index và window lớn có thể dùng nhiều RAM hoặc spill. |
| **Bounded Array** | Array có giới hạn số phần tử hoặc kích thước được enforce | Bound phải đến từ invariant/update logic, không chỉ từ quan sát dữ liệu hiện tại. |
| **Broadcast Operation** | `mongos` gửi operation tới mọi shard liên quan rồi merge kết quả | Có thể hợp analytics hiếm; hot OLTP path thường cần targeted routing. |
| **BSON** | Binary serialization format MongoDB dùng cho document | Có type giàu hơn JSON như ObjectId, Decimal128, Date, Binary và Int64. |
| **BSON Date** | Số millisecond từ Unix epoch biểu diễn UTC instant | Không giữ timezone/format ban đầu; khác BSON Timestamp nội bộ. |
| **BSON Timestamp** | Type gồm time và ordinal, chủ yếu dùng nội bộ MongoDB | Không dùng thay Date cho business timestamp. |
| **Bucket Pattern** | Gom nhiều measurement/event vào document bounded theo time/count | Giảm số document/index entry nhưng phải kiểm soát kích thước và late arrival. |
| **Bulk Write** | Gửi nhiều insert/update/delete trong một call | Giảm round trip nhưng có thể thành công một phần; unordered không phải transaction. |
| **Capped Collection** | Collection fixed-size tự ghi đè dữ liệu cũ theo insertion order | Không có ack/retry nên không phải durable message queue. |
| **Cardinality** | Số lượng phần tử hoặc số giá trị distinct trong một relationship/field | Thiết kế theo P99/max và tốc độ tăng, không chỉ average của dữ liệu mẫu. |
| **Case-Insensitive Index** | Index có collation cho phép so sánh string không phân biệt hoa/thường | Query phải dùng collation tương thích; identifier vẫn nên có normalization contract rõ. |
| **Causal Consistency** | Giữ thứ tự phụ thuộc như read-your-writes trong logical session | Guarantee đầy đủ cần majority read/write concern và operation tuần tự. |
| **Chained Replication** | Secondary copy oplog từ secondary khác thay vì trực tiếp từ primary | Có thể giảm WAN traffic nhưng sync-source lag sẽ lan xuống chuỗi. |
| **Change Stream** | API subscribe thay đổi collection/database/deployment từ replication history | Dùng thay việc ứng dụng tự tail oplog; cần resume token và oplog window đủ. |
| **Child Reference** | Parent document lưu ID các node con | Đọc con trực tiếp nhanh nhưng array children phải bounded; không tối ưu subtree. |
| **Chunk / Data Range** | Khoảng shard-key values liên tiếp do một shard sở hữu | Lower bound inclusive, upper bound exclusive; balancer có thể chuyển ownership. |
| **Client Session** | Context phía driver gắn các operation bằng session identity và cluster time | Transaction thuộc session; không dùng một session đồng thời trên nhiều thread. |
| **Clustered Collection** | Collection lưu document theo thứ tự clustered index `{_id: 1}` | Phải chọn khi tạo collection; khác collection thường có `_id` index tách riêng. |
| **Cold Data** | Dữ liệu ít được truy cập trong workload hiện tại | Có thể tách/archive để giảm working set nhưng vẫn cần query và restore path. |
| **Collation** | Quy tắc so sánh/sort string theo locale, case và dấu | Index và query cần collation tương thích để planner dùng index cho string. |
| **Collection** | Nhóm BSON document trong một database | Document có thể khác shape nhưng thường chia cùng schema contract và indexes. |
| **Commit** | Công bố toàn bộ write của transaction attempt thành công | Commit response có thể mất; `UnknownTransactionCommitResult` cần retry commit. |
| **Commit Quorum** | Số voting data-bearing member phải sẵn sàng trước khi primary commit index build | Khác write concern; cần tính đến member unavailable khi lập kế hoạch build. |
| **Compound Index** | Một index chứa nhiều field theo thứ tự xác định | Thiết kế từ equality, sort, range và các query shape cần tái sử dụng prefix. |
| **Compound Sort** | Sort theo nhiều field theo thứ tự xác định | Thêm field duy nhất như `_id` làm tie-breaker để pagination ổn định. |
| **Computed Pattern** | Lưu sẵn kết quả tính toán để tối ưu read | Phải có owner và cơ chế cập nhật/reconciliation khi dữ liệu nguồn đổi. |
| **Config Shard** | Shard vừa giữ sharding metadata vừa có thể giữ application data | Có từ MongoDB 8.0; dedicated config servers cho cách ly tốt hơn khi workload lớn. |
| **Consistency** | Trạng thái dữ liệu luôn thỏa invariant đã định nghĩa | Database constraint và transaction hỗ trợ, nhưng invariant phải do application/model xác định. |
| **Covered Query** | Query được trả hoàn toàn từ index mà không đọc document | Filter, projection và index phải tương thích; `_id` cũng cần được xét trong projection/index. |
| **Cursor** | Handle cho tập kết quả được lấy dần theo batch | Stream/đóng cursor và đặt bound; tránh gom query lớn bằng `toArray()`. |
| **Customer Master Key (CMK)** | Key ngoài MongoDB dùng để bọc các Data Encryption Key | Lưu trong KMS/HSM, tách quyền và recovery path khỏi database/backup artifact. |
| **Data Encryption Key (DEK)** | Key trực tiếp mã hóa field/data và được CMK bọc lại | Mất DEK/key vault có thể làm ciphertext không thể giải mã. |
| **Data Ownership** | Quy ước entity/field nào là nguồn có quyền quyết định giá trị | Dữ liệu duplicate phải có một owner và cơ chế đồng bộ/reconciliation. |
| **Database** | Namespace chứa collections và metadata liên quan | Không nên dựa khác biệt hoa/thường để phân biệt tên database. |
| **Decimal128** | BSON decimal floating-point 128-bit | Hợp với tiền/decimal exact hơn double; driver phải map đúng. |
| **Delayed Member** | Secondary cố ý áp dụng oplog trễ một khoảng thời gian | Nên hidden/priority 0; delay phải nằm trong oplog window và không thay backup. |
| **Denormalization** | Lưu cùng hoặc duplicate dữ liệu để tối ưu access pattern | Giảm join/round trip nhưng tăng chi phí đồng bộ và storage. |
| **Discriminator** | Field cho biết subtype của document polymorphic | Dùng trong query, validator và partial index; giá trị phải có contract ổn định. |
| **Distributed Transaction** | Multi-document transaction có thể trải qua collection, database hoặc shard | Coordination và conflict cost tăng khi chạm nhiều shard. |
| **Document** | Tập field-value BSON có thể chứa object và array | Là đơn vị lưu trữ và atomic write tự nhiên của MongoDB. |
| **Document Database** | Database tổ chức dữ liệu quanh aggregate document | Schema nên khớp workload và lifecycle, không chỉ mô phỏng table/row. |
| **Document Versioning** | Giữ các trạng thái lịch sử của business document | Khác schema version mô tả shape và optimistic version phát hiện conflict. |
| **Dot Notation** | Cú pháp truy cập nested field như `address.city` | Dùng trong query, projection và update; array semantics cần chú ý `$elemMatch`. |
| **Durability** | Mức dữ liệu đã commit sống sót qua crash/failover | Phụ thuộc write concern, journal, topology và effective deployment defaults. |
| **Election** | Quá trình voting member chọn primary mới | Cần majority vote; trong lúc chưa có primary, replica set không nhận write. |
| **Election Term** | Số epoch tăng theo leadership mới | Giúp phân biệt/fence primary cũ và gắn lịch sử oplog với election. |
| **Embedding** | Đặt dữ liệu liên quan trong cùng parent document | Tốt khi đọc/ghi cùng và cardinality bounded; cho phép single-document atomicity. |
| **Encryption at Rest** | Mã hóa data khi nằm trên disk/snapshot storage | Không bảo vệ plaintext trong memory, authenticated query hay network không TLS. |
| **Envelope Encryption** | Dùng CMK bọc DEK thay vì mã hóa mọi dữ liệu trực tiếp bằng CMK | Cho phép phân quyền và rotation key theo lớp; cần backup cả key metadata. |
| **Error Label** | Nhãn driver/server gắn vào lỗi để hướng dẫn retry protocol | Không retry chỉ dựa message text; phân biệt transient attempt và unknown commit. |
| **ERS Guideline** | Sắp compound key theo Equality → Range → Sort | Cân nhắc khi range rất selective và lợi ích giảm scan lớn hơn chi phí sort. |
| **ESR Guideline** | Sắp compound key theo Equality → Sort → Range | Guideline phổ biến để giữ index-provided sort; vẫn phải đo với distribution thật. |
| **Expand-and-Contract** | Migration online mở rộng tương thích, backfill rồi mới loại contract cũ | Deploy reader trước writer, đo/reconcile và giữ rollback window. |
| **Explain Plan** | Mô tả cách query engine dự kiến hoặc thực sự thực thi query | Đọc index/scan, keys/docs examined, returned rows, sort và spill thay vì chỉ nhìn latency. |
| **Extended JSON** | Cách biểu diễn BSON type qua JSON | Canonical ưu tiên giữ type; relaxed ưu tiên dễ đọc. |
| **Extended Reference Pattern** | Reference entity nhưng duplicate một số field hay đọc | Cần quy định field nào là snapshot, field nào phải đồng bộ. |
| **Facet Stage** | `$facet` chạy nhiều sub-pipeline trên cùng tập input | Không spill ra disk; giới hạn 100 MB và final BSON document vẫn tối đa 16 MiB. |
| **Failover** | Chuyển quyền primary sau khi primary cũ không còn khả dụng | Bao gồm detection, election, driver reselection và application recovery. |
| **Failure Domain** | Nhóm tài nguyên có thể hỏng cùng lúc như host, AZ hoặc region | Phân bố member phải giữ majority sau failure domain đã chọn. |
| **Filter** | Predicate chọn document cho read, update hoặc delete | Là hàng rào correctness; nên chứa tenant, state hoặc version khi invariant yêu cầu. |
| **Flexible Schema** | Document cùng collection không bắt buộc hoàn toàn cùng field/type | Không đồng nghĩa schema-less; production vẫn cần contract và validation. |
| **Flow Control** | Cơ chế hạn chế primary write khi majority commit lag tăng | Write latency có thể tăng vì secondary chậm; xử lý bottleneck trước khi tune. |
| **Freshness** | Độ mới của dữ liệu duplicate/computed so với source of truth | Nên biểu diễn bằng SLA và metadata như `computedAt`, không dùng “gần real-time” mơ hồ. |
| **Geospatial Index** | Index `2dsphere`/`2d` hỗ trợ truy vấn vị trí và hình học | GeoJSON dùng `[longitude, latitude]`; `$near`/`$geoNear` cần index phù hợp. |
| **GridFS** | API chia file lớn thành nhiều chunk/document | Dùng khi cần lưu file vượt 16 MiB trong MongoDB; vẫn nên so với object storage. |
| **Hashed Index** | Index lưu hash của field value | Hợp equality/hashed sharding, không giữ range order và không thể là multikey. |
| **Hashed Sharding** | Phân phối theo hash của shard-key value | Giảm monotonic hotspot nhưng không sửa repeated-value skew hay query thiếu key. |
| **Heartbeat** | Ping định kỳ giữa replica set members để theo dõi reachability/topology | Không phải replication-lag metric; lag phải đo bằng optime. |
| **Hidden Index** | Index bị ẩn khỏi query planner nhưng chưa bị xóa | Vẫn duy trì trên write, chiếm tài nguyên và tiếp tục enforce unique/TTL behavior. |
| **Hidden Member** | Priority-0 member bị ẩn khỏi normal driver discovery | Dùng cho workload chuyên biệt; vẫn replicate và có thể vẫn vote nếu cấu hình. |
| **Hot Range** | Data range nhận tỷ lệ read/write lớn bất thường | Có thể do monotonic key, whale tenant hoặc traffic skew; thêm shard chưa chắc sửa được. |
| **ID Field** | `_id` duy nhất và immutable của standard collection document | Driver thường tạo ObjectId nếu application không cung cấp. |
| **Immutable Backup** | Backup không thể sửa/xóa trong retention period bằng normal credential | Giảm ransomware risk; vẫn cần key recovery và restore verification. |
| **Index** | Cấu trúc tăng tốc query/sort bằng key được sắp xếp | Tốn disk/RAM và làm write đắt hơn; phải xuất phát từ query pattern. |
| **Index Bounds** | Khoảng key mà execution plan phải scan trong index | Bounds càng hẹp thường càng ít work; đọc trong `explain()` cùng keys/docs examined. |
| **Index Build** | Quá trình scan collection, tạo key, xử lý concurrent write và commit index | Cần disk/CPU/I/O, theo dõi replica set và commit quorum như một production change. |
| **Index Intersection** | Query plan kết hợp nhiều index để giải một query | Có thể hữu ích nhưng không thay việc đo compound index cho hot query shape. |
| **Index Prefix** | Các field đầu liên tiếp của compound index | Query theo prefix thường tái sử dụng được index; bỏ leading field thường làm scan rộng. |
| **Index Selectivity** | Mức độ predicate/index thu hẹp tập document | Phải xét distribution chứ không chỉ số giá trị distinct. |
| **Initial Sync** | Quá trình clone data/index và catch up oplog cho member mới/resync | Oplog window và capacity của source phải đủ suốt thời gian copy. |
| **Isolation** | Quy tắc transaction nhìn thấy/che giấu thay đổi concurrent | Snapshot có thể stale; outside read visibility còn phụ thuộc concern và sharding. |
| **Journaling** | Ghi recovery log trước khi data page được checkpoint đầy đủ | Bảo vệ durability qua crash; phải hiểu cùng storage engine và write concern. |
| **Jumbo Range** | Range vượt kích thước mục tiêu nhưng không thể chia nhỏ thêm | Thường do một shard-key value lặp quá nhiều; cần refine hoặc reshard key. |
| **Key Vault** | Collection/service giữ DEK đã được CMK bọc | Bảo vệ bằng least privilege và backup riêng; mất vault có thể mất khả năng decrypt. |
| **Keyset Pagination** | Lấy trang kế bằng range trên sort key cuối trang trước | Tránh chi phí offset sâu; sort key cần deterministic và index phù hợp. |
| **Least Privilege** | Chỉ cấp đúng resource/action cần cho identity trong đúng thời gian | Role hẹp không giảm quyền nếu identity vẫn giữ một role rộng khác. |
| **Logical Session** | Session server-side theo dõi operation time, causal metadata và transaction | Driver quản lý qua `ClientSession`; kết thúc session sẽ abort transaction còn mở. |
| **Lookup Stage** | `$lookup` thực hiện left outer join với collection khác | Kiểm soát fan-out và tạo index cho foreign join key; không phải join miễn phí. |
| **Majority Commit Point** | Mốc oplog đã được majority voting member ghi nhận theo replication semantics | Majority read thường trả view tại hoặc trước mốc này. |
| **Majority Vote** | Số vote tối thiểu `floor(votingMembers/2)+1` | Quyết định khả năng election; không đồng nghĩa số bản sao dữ liệu. |
| **Map-Reduce** | Cơ chế xử lý dữ liệu kiểu map/reduce cũ của MongoDB | Đã deprecated từ MongoDB 5.0; dùng Aggregation Pipeline cho workload mới. |
| **Match Stage** | `$match` lọc document trong aggregation pipeline | Đặt sớm khi đúng semantics để giảm input và tận dụng index. |
| **Materialized Path** | Mỗi tree node lưu sẵn đường dẫn hoặc danh sách ancestor | Đọc subtree nhanh nhưng move node gây update nhiều descendant. |
| **Max Staleness** | Ngưỡng driver dùng để loại secondary bị ước lượng quá stale | Là estimated routing bound, không tạo strong consistency. |
| **Member Priority** | Trọng số ảnh hưởng khả năng/thời điểm member trở thành primary | Priority 0 không thể primary; priority không thay majority math. |
| **Mirrored Reads** | Primary gửi mẫu read fire-and-forget để làm ấm cache secondary | Giảm cold-cache shock sau election, không tăng read guarantee. |
| **Missing Field** | Field không tồn tại trong document | Khác `null` và empty value; query phải dùng `$exists` khi cần phân biệt. |
| **mongos** | Stateless query router của sharded cluster | Application kết nối qua `mongos`, không đọc/ghi business data trực tiếp trên shard. |
| **Multikey Index** | Index được tạo khi index field chứa array | Một document có thể sinh nhiều index entry và có constraint compound riêng. |
| **Network Partition** | Các nhóm member còn chạy nhưng không liên lạc được với nhau | Chỉ partition có majority mới có thể bầu/duy trì primary hợp lệ. |
| **Normalization** | Tách dữ liệu thành collection/entity riêng và liên kết bằng reference | Giảm duplication nhưng có thể tăng query/`$lookup`/transaction. |
| **Null** | BSON value biểu diễn field tồn tại nhưng không có giá trị cụ thể | Query equality với `null` có thể match cả null và missing nếu không thêm điều kiện. |
| **ObjectId** | ID 12 byte gồm timestamp, random value và counter | Chỉ xấp xỉ thứ tự creation; không monotonic tuyệt đối. |
| **Oplog** | Capped collection `local.oplog.rs` lưu rolling replication history | Ứng dụng dùng change stream thay vì tự parse oplog. |
| **Oplog Window** | Khoảng thời gian giữa oplog entry cũ nhất và mới nhất | Member gián đoạn lâu hơn window thường phải initial sync/resync. |
| **Optime** | Vị trí logical của member trong replication history | So applied/durable/committed optime để đo lag và durability progress. |
| **Optimistic Concurrency** | Update chỉ thành công nếu version hiện tại còn đúng | Đặt version trong filter, `$inc` version và kiểm tra `matchedCount`. |
| **Outbox Pattern** | Ghi business change và event record atomically rồi publish bất đồng bộ | Publisher/consumer vẫn cần event ID, retry và deduplication. |
| **Outlier Pattern** | Tách trường hợp kích thước/cardinality cực lớn khỏi model phổ biến | Giữ fast path gọn mà vẫn xử lý được ngoại lệ. |
| **Parent Reference** | Child document lưu ID của parent node | Hợp parent/direct-child query; subtree thường dùng `$graphLookup`. |
| **Partial Index** | Index chỉ chứa document thỏa `partialFilterExpression` | Query phải bảo đảm kết quả nằm trong subset; thường linh hoạt hơn sparse index. |
| **Pipeline Stage** | Một bước nhận document stream và phát stream đã xử lý | Stage có thể streaming hoặc blocking và làm thay đổi shape/cardinality. |
| **Point-in-Time Recovery (PITR)** | Restore base snapshot rồi replay history đến một thời điểm đã chọn | Chỉ khả dụng trong restore window và phụ thuộc continuous log/key health. |
| **Polymorphic Pattern** | Lưu nhiều subtype có common query trong cùng collection | Nên có discriminator/schema version và validation phù hợp từng subtype. |
| **Primary** | Replica set member hiện nhận write và ghi oplog | Role có thể đổi sau election; application không được hard-code hostname primary. |
| **Projection** | Chọn field được trả về từ query | Giảm network/decode nhưng không tự sửa bloated storage model. |
| **Query Predicate** | Điều kiện boolean dùng để match document | Predicate selectivity và thứ tự field liên quan trực tiếp đến index design. |
| **Query Shape** | Cấu trúc filter, sort, projection và options của một nhóm query | Là đầu vào chính để thiết kế/đánh giá index, cùng data distribution và SLA. |
| **Queryable Encryption** | Client encrypts randomized data nhưng server vẫn xử lý query được hỗ trợ | Equality/range production ở 8.2; keys, metadata và overhead phải được vận hành đúng. |
| **Range Migration** | Quá trình clone, catch up và chuyển ownership một data range giữa hai shard | Tiêu thụ disk/network/oplog; bản donor được range deleter dọn sau commit. |
| **Ranged Sharding** | Phân phối document theo thứ tự/range của shard-key values | Hợp range locality nhưng key tăng tuần tự dễ làm hot max-key range. |
| **Read Concern** | Mức consistency/isolation MongoDB dùng khi đọc | Transaction hỗ trợ `local`, `majority`, `snapshot`; đặt ở transaction level. |
| **Read Preference** | Quy tắc driver chọn replica set member để đọc | Transaction có read phải dùng `primary` và các operation route cùng member. |
| **Reconciliation** | Job so dữ liệu dẫn xuất/duplicate với source of truth và sửa sai lệch | Là safety net cho retry, event thất lạc và bug; cần metric/cảnh báo. |
| **Recovery Point Objective (RPO)** | Lượng dữ liệu tối đa được phép mất khi recovery | Quyết định tần suất/retention backup và durability strategy. |
| **Recovery Time Objective (RTO)** | Thời gian tối đa để phục hồi dịch vụ | Phải được kiểm chứng bằng restore/failover drill, không chỉ ghi trong tài liệu. |
| **Reference** | Lưu ID liên kết tới document khác | Hợp với child unbounded, lifecycle riêng hoặc many-to-many. |
| **Replica Set** | Nhóm `mongod` duy trì cùng dataset bằng oplog replication | Cung cấp redundancy/HA nhưng không thay backup. |
| **Replication Lag** | Độ trễ giữa operation trên primary và apply trên secondary | Đo bằng optime; lag lớn đe dọa freshness, oplog window và failover. |
| **Resharding** | Online operation đổi shard key và phân phối lại collection | Cần disk/I/O/network headroom, oplog catch-up và một critical section khi commit. |
| **Restore Drill** | Diễn tập khôi phục artifact vào target cô lập và xác minh service | Là phép đo thực tế của RPO/RTO, key recovery và runbook completeness. |
| **Retryable Write** | Write đủ điều kiện được driver retry khi gặp một số lỗi tạm thời | Không áp dụng cho mọi write và không thay idempotency của business side effect. |
| **Rollback** | Former primary loại bỏ divergent writes khi gia nhập history thắng majority | Giảm rủi ro bằng majority durability và cần business reconciliation khi xảy ra. |
| **Saga** | Workflow nhiều bước dùng durable state và compensation thay distributed DB transaction | Mỗi step phải idempotent; compensation không phải lúc nào cũng khôi phục tuyệt đối. |
| **Schema** | Hợp đồng về field, type, relationship, invariant và lifecycle | Tồn tại dù database cho phép document linh hoạt. |
| **Schema Migration** | Quá trình chuyển dữ liệu/code từ schema version cũ sang mới | Nên idempotent, chạy theo batch, có checkpoint, reconcile và rollback plan. |
| **Schema Validation** | Rule database kiểm tra document khi insert/update | Là hàng rào cuối, bổ sung chứ không thay application validation. |
| **Schema Version** | Giá trị cho biết document đang dùng shape nào | Hỗ trợ reader tương thích và backfill expand-and-contract. |
| **SCRAM** | Cơ chế password authentication mặc định của MongoDB | Ưu tiên SCRAM-SHA-256; password vẫn cần TLS và secret rotation. |
| **Secondary** | Replica set member copy và apply oplog bất đồng bộ | Có thể stale, phục vụ read khi được phép và có thể được bầu primary. |
| **Secondary Index** | Index bổ sung ngoài clustered/default `_id` access path | Tăng tốc read nhưng tăng write, storage và cache pressure. |
| **Server Selection** | Logic driver chọn member phù hợp topology, role, tags và latency | Timeout chọn server khác connect/socket timeout; cần budget theo SLO. |
| **Shard** | Replica set giữ một phần application data của sharded cluster | Mỗi data range có một owner shard; shard vẫn cần replication/HA riêng. |
| **Shard Key** | Field hoặc compound fields quyết định phân phối/routing document | Cần cardinality, frequency và distribution tốt; khó sửa hơn schema field thường. |
| **Shard Key Analyzer** | `analyzeShardKey` đo đặc tính key và routing từ sampled workload | Thu mẫu qua chu kỳ đại diện; kết quả không thay production-like load test. |
| **Sharded Cluster** | Cluster gồm shards, `mongos` và config-server metadata plane | Scale-out đổi lấy nhiều topology, routing, backup và failure modes hơn. |
| **Snapshot Read Concern** | Đọc từ một snapshot nhất quán, đồng bộ giữa shard trong transaction | Guarantee majority-committed đầy đủ cần commit với write concern majority. |
| **Sort Stability** | Tính xác định của thứ tự khi nhiều document có cùng sort value | Thêm unique tie-breaker để tránh page trùng hoặc bỏ sót. |
| **Source of Truth** | Bản dữ liệu có thẩm quyền để tái tạo các bản duplicate/computed | Mỗi derived field phải trỏ về một source rõ ràng. |
| **Sparse Index** | Index bỏ qua document không có indexed field | Field tồn tại với `null` vẫn có thể được index; partial index thường rõ hơn. |
| **Spill to Disk** | Blocking stage ghi file tạm khi vượt memory limit và được phép | Giúp operation hoàn tất nhưng tăng I/O/latency; cần theo dõi `usedDisk`. |
| **Subset Pattern** | Embed một phần hot/bounded và reference toàn bộ dữ liệu | Hữu ích cho recent reviews, latest events hoặc summary. |
| **Sync Source** | Member mà secondary đang copy oplog từ đó | Có thể là primary hoặc secondary; source lag/network ảnh hưởng downstream. |
| **Targeted Operation** | `mongos` route operation tới một shard hoặc subset shard xác định được | Xác minh bằng `explain()`; có key trong filter chưa chắc chỉ chạm một shard. |
| **Text Index** | Index cổ điển hỗ trợ `$text` trên string | Một index/collection và có nhiều hạn chế; MongoDB khuyến nghị MongoDB Search cho search mới. |
| **Time Series Collection** | Collection tối ưu dữ liệu measurement theo time + metadata | MongoDB quản lý bucket nội bộ; cần chọn time/meta/granularity/retention đúng. |
| **TLS** | Transport encryption xác thực endpoint và mã hóa network traffic | Phải verify CA + hostname; private network không thay TLS. |
| **Topology Discovery** | Quá trình driver dùng seed hosts/`hello` để học role và member hiện tại | Cho phép tự tìm primary mới; không hard-code một primary endpoint. |
| **Transaction** | Nhóm operation commit hoặc abort như một đơn vị atomic | Chỉ dùng khi invariant vượt một document và eventual consistency không đủ. |
| **Transaction Callback** | Hàm driver có thể chạy lại để retry một transaction attempt | Không chứa external side effect; ID/time cần ổn định qua các attempt. |
| **Transaction Lifetime** | Thời gian transaction được phép tồn tại phía server | Mặc định dưới một phút nhưng transaction application nên ngắn hơn nhiều. |
| **TransactionTooLargeForCache** | Lỗi khi transaction vượt khả năng giữ state/history trong cache | Giảm scope/batch; server không tự retry lỗi này từ MongoDB 6.2. |
| **TransientTransactionError** | Error label cho biết toàn transaction attempt có thể retry | Abort attempt và chạy lại callback, không chỉ retry operation lỗi. |
| **Tree Pattern** | Nhóm cách lưu hierarchy bằng parent, child, ancestors hoặc path | Chọn theo operation parent/child/subtree/move và giới hạn fan-out/depth. |
| **TTL Index** | Index khiến TTL monitor xóa document hết hạn ở background | Không phải scheduler chính xác; TTL index thông thường chỉ có một field. |
| **Unbounded Array** | Array có thể tăng mãi theo tuổi parent document | Gây document/index phình và hotspot; dùng reference, subset hoặc bucket. |
| **Unique Index** | Index từ chối indexed key bị trùng | Enforce invariant tại database; có thể kết hợp partial filter cho active subset. |
| **Unknown Write Outcome** | Client không biết write đã apply/replicate đến đâu sau timeout hoặc mất response | Dùng idempotency key, retry protocol và read-back/reconciliation. |
| **UnknownTransactionCommitResult** | Error label cho biết client chưa biết commit đã thành công hay chưa | Retry commit thay vì chạy lại business callback ngay. |
| **Upsert** | Update document match hoặc insert document mới nếu không match | Business key cần unique index để tránh duplicate khi request cạnh tranh. |
| **Validator** | Cấu hình `$jsonSchema`/query expression áp cho collection writes | Có level `strict`/`moderate` và action `error`/`warn`. |
| **Voting Member** | Replica set member có `votes: 1` tham gia election | Vote ảnh hưởng majority; chỉ data-bearing member mới tăng durability. |
| **Wildcard Index** | Index các field động bằng `$**` | Chỉ dùng khi tên field không ổn định; targeted index thường hiệu quả hơn cho hot path. |
| **Window Function** | Tính rank, running total hoặc moving metric trên các document lân cận | Giữ từng row khác `$group`; partition/sort lớn có thể tốn memory. |
| **WiredTiger** | Storage engine mặc định của MongoDB | Quản lý cache, compression, checkpoint và concurrency ở tầng storage. |
| **Working Set** | Dữ liệu và index thường xuyên được truy cập | Working set vượt RAM thường làm disk I/O và latency tăng. |
| **Write Amplification** | Một business write kéo theo nhiều storage/index/replication write | Số index và indexed array càng lớn, write amplification thường càng cao. |
| **Write Concern** | Mức xác nhận MongoDB yêu cầu cho một write | Tác động durability/latency; `acknowledged` phải được hiểu cùng write concern. |
| **Write Conflict** | Hai transaction/write cạnh tranh khiến một attempt phải abort | Retry toàn transaction với backoff/budget; giảm contention và transaction duration. |
| **Write Majority** | Write được acknowledgment theo calculated majority durability semantics | Arbiter không lưu data; topology/lag quyết định latency và availability. |
| **Write Result** | Metadata trả về sau write như matched, modified, deleted hoặc upserted | Ứng dụng phải kiểm tra để phân biệt success, no-op, conflict và partial failure. |
| **X.509 Authentication** | Xác thực client/member bằng certificate subject và PKI trust | Cần TLS, CA/SAN/EKU đúng cùng certificate rotation/revocation runbook. |
| **Zone Sharding** | Placement policy gắn shard-key ranges với nhóm shard | Hỗ trợ locality/residency nhưng không thay TLS, backup, audit hay capacity planning. |

## Phân biệt nhanh

| Cặp dễ nhầm | Khác nhau |
|---|---|
| Authentication ↔ Authorization | Authentication xác minh identity; authorization quyết định identity đó được làm gì. |
| Broadcast ↔ Targeted operation | Broadcast chạm mọi shard liên quan; targeted chỉ chạm shard/subset suy ra được từ routing metadata và predicate. |
| BSON Date ↔ BSON Timestamp | Date là business UTC instant; Timestamp chủ yếu phục vụ cơ chế nội bộ MongoDB. |
| Causal consistency ↔ Transaction | Causal giữ ordering/read-your-writes; transaction cung cấp all-or-nothing cho nhiều operation. |
| CSFLE ↔ Queryable Encryption | CSFLE deterministic hỗ trợ equality với frequency leakage; QE dùng randomized searchable encryption và hỗ trợ equality/range. |
| Embedding ↔ Reference | Embed tối ưu dữ liệu đọc/ghi cùng và bounded; reference tách lifecycle hoặc cardinality lớn. |
| Encryption at rest ↔ In use ↔ TLS | At rest bảo vệ disk; in use bảo vệ field khỏi server; TLS bảo vệ network traffic. |
| Flexible schema ↔ Schema-less | Flexible cho phép shape tiến hóa; schema-less ngụ ý sai rằng không có contract. |
| Hashed ↔ Ranged sharding | Hashed ưu tiên phân phối equality key; ranged giữ locality/order nhưng key monotonic dễ tạo hot range. |
| Heartbeat ↔ Replication lag | Heartbeat đo reachability; lag đo chênh lệch applied optime so với primary. |
| Hidden ↔ Dropped index | Hidden chỉ loại index khỏi planner và có thể unhide nhanh; dropped phải rebuild để khôi phục. |
| `IXSCAN` ↔ Query hiệu quả | `IXSCAN` chỉ nói có scan index; vẫn phải đọc bounds, keys/docs examined, sort và latency. |
| Majority read ↔ Latest read | Majority chỉ trả history đã committed mà member biết; secondary vẫn có thể chưa biết commit point mới nhất. |
| `null` ↔ Missing | `null` là field có value null; missing là field không tồn tại. |
| `matchedCount` ↔ `modifiedCount` | Matched cho biết filter tìm thấy document; modified cho biết dữ liệu thực sự thay đổi. |
| ObjectId time ↔ `createdAt` | ObjectId chỉ xấp xỉ creation time; `createdAt` là business field có contract rõ. |
| Offset ↔ Keyset pagination | Offset nhảy theo số lượng bỏ qua và chậm dần; keyset đi tiếp từ sort key cuối trang. |
| Ordered ↔ Unordered bulk | Ordered dừng ở lỗi đầu; unordered tiếp tục operation độc lập nhưng có thể partial success. |
| Partial ↔ Sparse index | Partial chọn subset bằng expression; sparse chỉ dựa indexed field có tồn tại hay không. |
| Read preference ↔ Read concern | Preference chọn member; concern chọn visibility/consistency trên member đó. |
| Read concern ↔ Write concern | Read concern chọn consistency/isolation khi đọc; write concern chọn mức acknowledgment/durability khi ghi. |
| Refine ↔ Reshard shard key | Refine chỉ thêm suffix và không redistrib ngay; reshard đổi key/distribution bằng online data movement. |
| Replica set ↔ Backup | Replica set cung cấp HA/redundancy và replicate cả lỗi; backup giữ recovery history độc lập. |
| RPO ↔ RTO | RPO là lượng dữ liệu có thể mất; RTO là thời gian tối đa để dịch vụ phục hồi. |
| Schema version ↔ Document version | Schema version theo dõi shape; document version lưu lịch sử trạng thái nghiệp vụ. |
| Transient transaction ↔ Unknown commit | Transient retry toàn attempt; unknown commit retry riêng thao tác commit. |
| Validator ↔ Application validation | Validator bảo vệ mọi writer tại DB; application validation cung cấp business rule và lỗi thân thiện. |
| `wtimeout` ↔ Write thất bại | Timeout chỉ nói chưa đủ acknowledgment đúng hạn; write có thể đã apply và tiếp tục replicate. |

## Đọc tiếp

- [MongoDB Data Model & BSON](fundamentals/data_model.md)
- [CRUD & Aggregation Pipeline](fundamentals/crud_aggregation.md)
- [Indexing](fundamentals/indexing.md)
- [Transactions](fundamentals/transactions.md)
- [Schema Design Patterns](performance/schema_design.md)
- [Replica Set](operations/replication.md)
- [Sharding](operations/sharding.md)
- [Backup & Security](operations/backup_security.md)
- [MongoDB Roadmap](roadmap.md)

*Cập nhật lần cuối: 2026-07-29*
