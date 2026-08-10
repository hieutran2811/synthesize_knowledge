---
title: "Redis Glossary"
topic: redis
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Redis Glossary

> Bảng tra cứu nhanh các thuật ngữ dùng trong learning path Redis. Cách giải thích ưu tiên góc nhìn thực hành với Redis Open Source 8.8.

| Thuật ngữ | Nghĩa ngắn gọn | Điểm cần nhớ |
|---|---|---|
| **Access Control List (ACL)** | Hệ thống user và quyền command/key của Redis | Application chỉ nên được cấp command category và key pattern tối thiểu cần thiết. |
| **Active Defragmentation** | Redis chủ động di chuyển allocation để allocator có thể thu hồi memory | Đổi CPU lấy RSS/fragmentation thấp hơn; chỉ bật sau khi đo headroom và latency. |
| **Active Expiration** | Redis chủ động lấy mẫu và xóa key đã hết TTL | Hoạt động cùng passive expiration; expiration không phải một timer riêng cho từng key. |
| **Allocator** | Thư viện quản lý các vùng memory Redis cấp phát và tái sử dụng | Memory được Redis free chưa chắc được allocator trả ngay về OS. |
| **Append Only File (AOF)** | Persistence log ghi lại các write command | RPO thường thấp hơn RDB nhưng cần fsync, rewrite và backup đúng multi-part AOF. |
| **Array** | Cấu trúc index → string, có thể sparse, từ Redis 8.8 | Random access O(1); `ARLEN` khác `ARCOUNT` khi có khoảng trống. |
| **ASK Redirection** | Redirect tạm thời khi một Cluster slot đang migrate | Client gửi `ASKING` rồi chạy đúng command đó ở node đích; chưa nên đổi slot map vĩnh viễn. |
| **Asynchronous Replication** | Primary trả response mà không đợi mọi replica xác nhận write | Tăng availability/throughput nhưng tạo cửa sổ mất write khi failover. |
| **At-least-once Delivery** | Message được giao ít nhất một lần nếu retry/recovery thành công | Có thể giao trùng; consumer side effect phải idempotent. |
| **At-most-once Delivery** | Message được giao tối đa một lần | Không giao trùng do retry, nhưng có thể mất trước khi consumer xử lý. |
| **Atomic Command** | Command không bị command khác xen vào giữa operation của nó | Không đồng nghĩa đã fsync, replicate hoặc atomic với database bên ngoài. |
| **Backpressure** | Làm chậm hoặc giới hạn producer khi downstream chưa xử lý kịp | Cần cho pipeline/batch để tránh buffer tăng không giới hạn và timeout dây chuyền. |
| **Big Key** | Key có value lớn hoặc collection nhiều phần tử | Có thể gây latency, network spike, slow deletion và mất cân bằng shard. |
| **Bitmap** | String được thao tác theo từng bit | Tiết kiệm cho ID nguyên dày; offset rất lớn làm String phải mở rộng. |
| **Bloom Filter** | Cấu trúc xác suất kiểm tra membership | Có false positive nhưng không có false negative khi dùng đúng và chưa xóa dữ liệu. |
| **Cache** | Bản sao dữ liệu giúp giảm latency/tải nguồn gốc | Cache phải chấp nhận miss và có chiến lược invalidation. |
| **Cache Miss** | Không tìm thấy dữ liệu cần thiết trong cache | Application thường đọc source of truth rồi có thể nạp lại cache. |
| **Cache Stampede** | Nhiều request đồng thời nạp lại cùng dữ liệu khi cache miss/hết hạn | Dùng singleflight, stale-while-revalidate, jitter và fallback budget. |
| **Cache-Aside** | Application đọc cache, fallback source of truth khi miss rồi nạp lại | Đơn giản nhưng cần TTL, invalidation, negative cache và chống stampede. |
| **Cardinality** | Số phần tử phân biệt trong một tập | `SCARD` cho Set chính xác; HyperLogLog ước tính với ít memory. |
| **Client-side Caching** | Cache Redis response trong memory của application với invalidation hỗ trợ từ server | Giảm RTT/load nhưng phải xử lý disconnect, TTL, memory bound và stale data. |
| **Command Complexity** | Chi phí command theo kích thước input/data | O(N) trên big collection có thể chặn các client khác trên cùng shard. |
| **Compare-and-Set (CAS)** | Chỉ cập nhật nếu value/version hiện tại còn đúng | Redis 8.4 có điều kiện `SET`; hệ thống cũ thường dùng `WATCH` hoặc script. |
| **Configuration Epoch** | Số phiên bản logic dùng để xác định authority của Cluster node trên slot | Epoch giúp cluster hội tụ khi topology và slot ownership thay đổi. |
| **Consumer Group** | Trạng thái phối hợp nhiều consumer đọc một Stream | Mỗi group có vị trí đọc và Pending Entries List riêng. |
| **Consumer Lag** | Khoảng cách giữa dữ liệu đã append và vị trí group đã xử lý | Xem cùng PEL/oldest pending để phân biệt thiếu capacity với message bị kẹt. |
| **Copy-on-Write (COW)** | OS chỉ copy memory page khi parent sửa sau `fork()` | RDB/AOF rewrite trên workload write-heavy cần memory headroom. |
| **Dead Letter Queue (DLQ)** | Nơi giữ message không thể xử lý sau policy retry | Phải lưu original ID, lỗi, attempts và có quy trình replay/audit. |
| **Delivery Semantics** | Cam kết message có thể mất, lặp hoặc được giao lại như thế nào | At-most-once, at-least-once và hiệu ứng “như một lần” đòi hỏi thiết kế khác nhau. |
| **Event Loop** | Vòng lặp nhận connection/event và điều phối command của Redis | Command chậm trên một shard có thể làm các client khác phải chờ. |
| **Eviction** | Redis loại key khi vượt `maxmemory` | Phụ thuộc eviction policy và khác với key hết TTL. |
| **Eviction Policy** | Quy tắc chọn key bị loại khi memory đầy | Cache có thể dùng `allkeys-*`; source of truth thường không được phép evict tùy ý. |
| **Expiration** | Vòng đời key/field kết thúc do TTL | Có active và passive expiration; khác eviction do memory pressure. |
| **Failover** | Chuyển vai trò primary sang một replica khi bảo trì hoặc sự cố | Failover tự động không đồng nghĩa zero data loss; client cũng phải khám phá và reconnect. |
| **Failure Domain** | Nhóm tài nguyên có thể hỏng cùng lúc như host, rack hoặc zone | Primary, replica và các phiếu bầu phải được phân bố qua các domain độc lập. |
| **Fencing Token** | Số tăng đơn điệu để downstream từ chối holder cũ của lease | Downstream phải lưu/so token; safe unlock một mình không chặn stale writer. |
| **Fragmentation** | Memory trống bị chia nhỏ hoặc chưa được allocator/OS thu hồi | Phải xem cả ratio, số byte, peak và swap; không đồng nghĩa memory leak. |
| **Full Synchronization** | Replica nạp snapshot rồi nhận phần write phát sinh trong lúc đồng bộ | Tốn network, CPU và memory hơn partial sync; lặp lại thường báo backlog/capacity có vấn đề. |
| **Geospatial Index** | Tập tọa độ hỗ trợ tìm theo bán kính/box | Dựa trên Sorted Set; `GEOADD` nhận longitude trước latitude. |
| **Gossip Protocol** | Cách các Cluster node trao đổi topology và failure report | Gossip giúp hội tụ phân tán nhưng không loại bỏ hoàn toàn cửa sổ split brain/mất write. |
| **Hash** | Map field-value nằm trong một Redis key | Hợp với object phẳng và update từng field; field value vẫn là string. |
| **Hash Field Expiration** | TTL áp cho một field trong Hash | Độc lập với TTL của cả key và cần Redis/client version hỗ trợ. |
| **Hash Slot** | Một trong 16.384 phần logical keyspace của Redis Cluster | Primary sở hữu slot; client route key tới node theo slot map. |
| **Hash Tag** | Phần trong `{...}` của key được dùng để tính Cluster slot | Ép key cùng slot cho multi-key operation nhưng lạm dụng có thể tạo hot shard. |
| **Head-of-Line Blocking** | Công việc chậm ở đầu hàng làm các việc phía sau phải đợi | Batch/pipeline hoặc response quá lớn có thể làm tail latency xấu hơn. |
| **Hit Rate** | Tỷ lệ request được phục vụ từ cache thay vì nguồn gốc | Phải xem theo endpoint/key class cùng miss cost, không chỉ số trung bình toàn hệ thống. |
| **Hot Key** | Key nhận tỷ lệ request quá cao | Có thể làm một shard quá tải dù key rất nhỏ. |
| **HyperLogLog** | Cấu trúc ước tính số phần tử unique | Memory nhỏ, kết quả xấp xỉ và không lưu danh sách member để đọc lại. |
| **I/O Threading** | Dùng nhiều thread cho network I/O/parsing trong Redis hiện đại | Redis 8 cải thiện cơ chế này; chỉ tăng thread sau benchmark đúng workload. |
| **Idempotency Key** | ID ổn định đại diện cho một request/operation logic | Retry cùng ID phải trả cùng kết quả hoặc không lặp side effect trong dedup window. |
| **In-memory** | Dữ liệu làm việc chủ yếu nằm trong RAM | Đem lại latency thấp nhưng memory sizing và persistence vẫn bắt buộc theo use case. |
| **Intrinsic Latency** | Độ trễ nền do OS/hypervisor không cấp CPU cho process | Là sàn latency của môi trường; đo trên Redis host bằng chế độ chuyên dụng có kiểm soát. |
| **JSON** | Data type lưu document lồng nhau và thao tác bằng JSONPath | Linh hoạt hơn Hash nhưng thường tốn memory/CPU hơn. |
| **Key** | Chuỗi byte định danh một value trong keyspace | Tên key cũng tốn memory; nên có convention dễ quan sát. |
| **Keyspace** | Toàn bộ ánh xạ key → typed value của Redis | Logical database chỉ chia namespace, không cô lập process hay memory. |
| **Latency** | Thời gian hoàn thành một operation từ điểm đo đã chọn | Luôn ghi rõ end-to-end hay server execution và quan sát percentile, không chỉ average. |
| **Lazy Free** | Giải phóng memory của object ở background | `UNLINK` dùng cơ chế này để tránh chặn lâu khi xóa big key. |
| **Lease** | Quyền sở hữu tài nguyên chỉ hợp lệ trong một khoảng thời gian | Holder phải hoàn tất/renew đúng hạn và không được tiếp tục ghi sau khi mất lease. |
| **Least Frequently Used (LFU)** | Chính sách ưu tiên giữ key có tần suất truy cập cao | Cần thời gian warm-up/decay và Redis dùng bộ đếm xấp xỉ. |
| **Least Recently Used (LRU)** | Chính sách ưu tiên giữ key vừa được truy cập gần đây | Redis dùng sampling xấp xỉ, không duy trì danh sách LRU tuyệt đối. |
| **List** | Sequence string tối ưu push/pop ở hai đầu | Truy cập giữa list có thể O(N); Stream phù hợp hơn khi cần ack/replay. |
| **Listpack** | Encoding compact cho collection nhỏ | Tiết kiệm memory nhưng threshold cao hơn có thể đổi lấy nhiều CPU hơn. |
| **Logical Database** | Namespace chọn bằng `SELECT` trong standalone | Dùng chung tài nguyên; Redis Cluster chỉ hỗ trợ database 0. |
| **Lua Script** | Logic server-side chạy atomic trên Redis | Script dài có thể chặn shard; ưu tiên command built-in khi có. |
| **Majority Partition** | Phía network partition còn nhìn thấy đa số thành phần có quyền biểu quyết | Sentinel/Cluster dùng majority để hạn chế hai phía cùng tự động nhận quyền primary. |
| **maxmemory** | Giới hạn memory dùng làm mốc eviction/OOM | Phải chừa headroom cho fork, allocator, replication buffer và OS. |
| **MOVED Redirection** | Cluster báo slot đã thuộc một node khác | Client nên cập nhật slot map; khác `ASK` là redirect tạm trong migration. |
| **Multi-part AOF** | AOF gồm base, incremental files và manifest | Có từ Redis 7; backup phải lấy cả directory nhất quán. |
| **Negative Caching** | Cache ngắn hạn kết quả “không tồn tại” | Giảm cache penetration nhưng không được biến backend error thành not-found. |
| **Network Round-trip Time (RTT)** | Thời gian request đi tới server và response quay lại client | Command nhỏ vẫn phải trả RTT; aggregate/pipeline giảm số vòng mạng. |
| **ODOWN** | Sentinel đánh giá primary objectively down sau khi đủ quorum đồng ý | ODOWN cho phép bước bầu leader; failover vẫn cần majority authorize. |
| **Optimistic Locking** | Phát hiện conflict rồi abort/retry thay vì giữ lock | Redis cung cấp `WATCH` kết hợp `MULTI`/`EXEC`. |
| **Output Buffer** | Memory Redis giữ response chưa gửi hết cho client | Slow consumer hoặc response/pipeline lớn có thể làm buffer tăng và connection bị đóng. |
| **Partial Synchronization** | Replica reconnect và chỉ nhận phần replication stream còn thiếu | Chỉ làm được khi replication ID/offset hợp lệ và dữ liệu vẫn còn trong backlog. |
| **Passive Expiration** | Xóa key hết hạn khi client truy cập nó | Bổ sung cho active expiration để key hết hạn không được trả về. |
| **Pending Entries List (PEL)** | Danh sách Stream entry đã giao nhưng chưa ack của một group | Dùng `XPENDING` và claim để phục hồi consumer chết. |
| **Persistence** | Ghi dữ liệu Redis xuống durable storage để nạp lại | RDB/AOF không thay thế backup, replication hoặc DR. |
| **Pipeline** | Gửi nhiều command trước khi chờ response | Giảm round trip nhưng không biến các command thành transaction atomic. |
| **Primary** | Redis node nhận write cho dataset hoặc một Cluster shard | Primary có thể trả thành công trước khi replica nhận write do replication bất đồng bộ. |
| **Probabilistic Data Structure** | Cấu trúc trả kết quả xấp xỉ để tiết kiệm memory/CPU | Bloom, Cuckoo, Count-Min Sketch, Top-K, t-digest và HLL có sai số riêng. |
| **Pub/Sub** | Fan-out message tới subscriber đang online | Delivery at-most-once, không persistence, ack hay replay. |
| **Rate Limiting** | Giới hạn operation theo identity, scope và thời gian | Phải định nghĩa burst, clock, fail-open/closed và response `retry-after`. |
| **RDB Snapshot** | Ảnh chụp point-in-time của dataset | File gọn, hợp backup; có thể mất write sau snapshot gần nhất. |
| **Redis Function** | Server-side function được lưu cùng Redis | Có lifecycle tốt hơn ad-hoc script nhưng vẫn phải giới hạn thời gian chạy. |
| **Redis Serialization Protocol (RESP)** | Giao thức client-server của Redis | Client library encode command và decode response qua TCP/TLS. |
| **Redlock** | Thuật toán lock trên majority các Redis primary độc lập | Có clock/failure assumptions; vẫn cần đánh giá stale holder và fencing. |
| **Replica** | Redis node sao chép dữ liệu từ primary | Có thể phục vụ stale read hoặc được promote, nhưng không thay thế backup. |
| **Replica Read** | Đọc trực tiếp từ replica để chia tải hoặc giảm khoảng cách mạng | Phải chấp nhận stale data và không mặc định có read-after-write. |
| **Replication** | Sao chép write từ primary tới replica | Thường bất đồng bộ; không tự bảo đảm zero data loss. |
| **Replication Backlog** | Vùng nhớ primary giữ một đoạn replication stream gần nhất | Backlog đủ lớn giúp replica reconnect bằng partial sync thay vì full sync. |
| **Resident Set Size (RSS)** | Phần memory của Redis process hiện nằm trong RAM theo OS | Có thể lớn hơn `used_memory` do allocator, COW, buffer và process overhead. |
| **Restore** | Nạp dữ liệu từ RDB/AOF hoặc serialized key | Phải test compatibility, integrity và thời gian phục hồi. |
| **Round-trip Time (RTT)** | Một vòng request-response giữa client và Redis | Xem **Network Round-trip Time (RTT)**. |
| **SCAN** | Duyệt keyspace theo cursor từng đợt | Không phải snapshot, có thể trả duplicate; `COUNT` chỉ là hint. |
| **SDOWN** | Một Sentinel tự đánh giá primary subjectively down | Chưa đủ để kết luận toàn hệ thống; các Sentinel khác có thể vẫn thấy primary. |
| **Sentinel** | Hệ thống monitor, discovery và automatic failover cho Redis không sharding | Nên có ít nhất ba Sentinel trên failure domain độc lập và client phải Sentinel-aware. |
| **Set** | Collection các string duy nhất, không có thứ tự | Tối ưu membership và phép hợp/giao/hiệu. |
| **Shard** | Phần keyspace được một Redis primary quản lý | Key phân bố không đều hoặc hot key làm shard mất cân bằng. |
| **Singleflight** | Chỉ một worker nạp/tính cùng key, các request khác dùng chung kết quả hoặc chờ | Lease phải có token, timeout và fallback để không biến miss thành deadlock. |
| **Sliding Window** | Cửa sổ thời gian di chuyển theo thời điểm hiện tại | Rate limit chính xác hơn fixed window nhưng thường tốn state/CPU hơn. |
| **Slow Log** | Ring buffer lưu command có server execution time vượt threshold | Không gồm network I/O; entry có thể chứa argument nhạy cảm và bị truncate. |
| **Sorted Set** | Collection member duy nhất được xếp theo score | Hợp leaderboard, range theo score và scheduling index. |
| **Source of Truth** | Nơi giữ bản dữ liệu có thẩm quyền | Nếu Redis là source of truth, eviction, persistence và DR phải nghiêm ngặt hơn cache. |
| **Split Brain** | Hai phía bị partition cùng tin mình có quyền nhận write | Majority, timeout và fencing giúp giảm rủi ro nhưng application vẫn phải xử lý conflict/unknown outcome. |
| **Stale Read** | Kết quả đọc cũ hơn state mới nhất đã ghi ở primary | Thường gặp khi đọc replica; chỉ phù hợp với luồng nghiệp vụ chấp nhận độ trễ. |
| **Stale-While-Revalidate** | Tạm trả cache cũ trong khi một worker làm mới dữ liệu | Cần fresh/stale deadline rõ ràng và không dùng cho read bắt buộc mới nhất. |
| **Stream** | Append-only log có ID, trimming và consumer group | `XACK` xóa khỏi PEL, không tự xóa entry khỏi Stream. |
| **String** | Data type chuỗi byte cơ bản của Redis | Dùng cho text, binary, counter, bitmap hoặc serialized object. |
| **Tail Latency** | Latency của nhóm request chậm ở cuối phân phối như p99/p99.9 | Thường tăng mạnh gần saturation dù average vẫn đẹp. |
| **Throughput** | Số operation hoàn thành trong một đơn vị thời gian | Phải đọc cùng latency, error và saturation; throughput cao không tự nghĩa hệ thống khỏe. |
| **Time Series** | Data type timestamp-value có retention và aggregation | Phù hợp metric; có label, compaction và range query chuyên biệt. |
| **Time-to-Live (TTL)** | Thời gian còn lại trước khi key/field hết hạn | `TTL=-1` là không expiry; `TTL=-2` là key không tồn tại. |
| **Token Bucket** | Rate limiter tích lũy token theo thời gian đến một capacity | Cho phép burst có giới hạn và kiểm soát tốc độ dài hạn. |
| **Transaction** | Nhóm command được queue bởi `MULTI` và chạy tại `EXEC` | Redis không rollback runtime error như relational database. |
| **Transactional Outbox** | Ghi business change và event dự định phát trong cùng DB transaction | Relay có thể gửi trùng nên consumer vẫn cần idempotency. |
| **TTL Avalanche** | Nhiều cache key hết hạn gần như cùng lúc | Có thể tạo miss burst về nguồn gốc; dùng TTL jitter và request coalescing để giảm. |
| **UNLINK** | Xóa key khỏi keyspace rồi free memory bất đồng bộ | Thường an toàn latency hơn `DEL` cho big key. |
| **Vector Set** | Data type lưu embedding và tìm member tương tự | Cần sizing dimension, quantization, recall và memory của index. |
| **Visibility Timeout** | Khoảng thời gian job/message đã claim chưa được worker khác reclaim | Quá ngắn gây xử lý song song; quá dài kéo chậm recovery. |
| **WAIT** | Chờ replica xác nhận offset của write trước đó trên cùng connection | Return thấp hơn yêu cầu không rollback write; lệnh không tạo strong consistency. |
| **WAITAOF** | Chờ write trước đó được fsync vào AOF local và/hoặc replica | Tăng durability nhưng vẫn phải kiểm tra kết quả và chấp nhận giới hạn failover. |
| **Working Set** | Phần dữ liệu được truy cập thường xuyên trong một khoảng thời gian | Nếu working set không vừa memory, hit rate giảm và eviction/miss tăng liên tục. |
| **Write Safety** | Mức bảo đảm acknowledged write còn tồn tại sau failure/failover | Redis Cluster cung cấp best-effort write safety, không phải linearizable zero-loss write. |
| **Write-Behind** | Trả accepted trước rồi ghi source of truth bất đồng bộ | Cần durable log, ordering, idempotency, backpressure và reconciliation. |
| **Write-Through** | Cập nhật source và cache trên write path | Redis và database không cùng transaction nên vẫn có partial-failure window. |
| **XAUTOCLAIM** | Claim các Stream pending entry idle quá ngưỡng sang consumer khác | Dùng cho recovery; visibility timeout phải phản ánh thời gian xử lý thật. |
| **XNACK** | Redis 8.8 command trả pending message về consumer group mà không ack | Có `SILENT`, `FAIL`, `FATAL`; không tự ghi DLQ. |

## Phân biệt nhanh

| Cặp dễ nhầm | Khác nhau |
|---|---|
| Atomic command ↔ Transaction | Command atomic là một operation; transaction nhóm nhiều command bằng `MULTI/EXEC`. |
| Cache ↔ Source of truth | Cache có thể tái tạo từ nguồn khác; source of truth phải có durability và recovery độc lập. |
| Expiration ↔ Eviction | Expiration do TTL; eviction do memory pressure và policy. |
| Hash ↔ JSON | Hash là object phẳng field-string; JSON hỗ trợ cấu trúc lồng nhau và JSONPath. |
| List ↔ Stream | List là sequence đơn giản; Stream có ID, retention, consumer group và PEL. |
| Persistence ↔ Replication ↔ Backup | Persistence sống qua restart; replication tạo replica; backup giữ bản độc lập theo thời gian. |
| Pipeline ↔ Transaction | Pipeline tối ưu network; transaction cung cấp nhóm thực thi tuần tự nhưng không rollback. |
| RDB ↔ AOF | RDB là snapshot; AOF ghi/replay write command. |
| SCAN ↔ KEYS | SCAN duyệt theo cursor; KEYS trả toàn bộ và có thể chặn lâu. |
| Latency ↔ Throughput | Latency đo thời gian mỗi operation; throughput đo số operation/time và có thể tăng trong khi tail latency xấu đi. |
| Slow Log ↔ Latency Monitor | Slow Log ghi command execution chậm; Latency Monitor phân loại nhiều nguồn spike nội bộ như command, fork, eviction. |
| TTL ↔ maxmemory | TTL quản lý tuổi dữ liệu; `maxmemory` giới hạn memory và kích hoạt eviction/OOM. |

## Đọc tiếp

- [Redis Fundamentals](redis_fundamentals.md)
- [Redis High Availability](redis_ha.md)
- [Redis Performance & Internals](redis_performance.md)
- [Redis Design Patterns](redis_patterns.md)

*Cập nhật lần cuối: 2026-07-29*
