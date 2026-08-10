---
title: "RabbitMQ Glossary"
topic: rabbitmq
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# RabbitMQ Glossary

> Bảng tra cứu nhanh các thuật ngữ dùng trong tài liệu RabbitMQ. Cách hiểu ở đây ưu tiên tính thực hành với AMQP 0-9-1.

| Thuật ngữ | Nghĩa ngắn gọn | Điểm cần nhớ |
|---|---|---|
| **Acknowledgement (Ack)** | Xác nhận consumer đã xử lý delivery | Chỉ ack sau khi side effect quan trọng đã hoàn tất; ack sai channel làm channel bị đóng. |
| **Alternate Exchange** | Exchange nhận message mà exchange chính không route được | Là phương án phía broker; khác với `mandatory` trả message về publisher. |
| **AMQP 0-9-1** | Giao thức messaging chính được RabbitMQ hỗ trợ | Định nghĩa connection, channel, exchange, queue, binding và các method publish/consume. |
| **At-least-once** | Gửi/xử lý lại khi kết quả chưa chắc chắn | Giảm nguy cơ mất message nhưng có thể tạo duplicate; consumer cần idempotent. |
| **At-most-once** | Không thử lại khi kết quả chưa chắc chắn | Tránh chủ động tạo duplicate nhưng có thể mất message. |
| **Auto-delete Queue** | Queue tự xóa sau khi consumer cuối cùng rời đi | Queue phải từng có consumer; đây không phải TTL của queue. |
| **Availability Zone** | Failure domain độc lập trong cùng một region cloud | Phân tán node/replica qua zone giúp chịu lỗi hạ tầng, nhưng vẫn cần kiểm tra latency. |
| **Binding** | Quy tắc nối exchange với queue hoặc exchange khác | Direct/topic dùng binding key; headers exchange dùng binding arguments. |
| **Blocked Connection** | Publish connection bị dừng do memory/disk alarm | Không reconnect liên tục; backpressure upstream và để consumer drain backlog. |
| **Blue-Green Deployment** | Duy trì môi trường cũ và mới song song rồi chuyển traffic | Hữu ích khi rolling upgrade không phù hợp; cần kế hoạch đồng bộ message và rollback. |
| **Channel** | Kết nối logic nhẹ chạy bên trong một TCP connection | Nên sống lâu, không chia sẻ tùy tiện giữa các thread; delivery tag có phạm vi theo channel. |
| **Classic Queue** | Queue truyền thống, không replicated trong RabbitMQ 4.x | Phù hợp dữ liệu tạm/có thể tạo lại; classic mirroring đã bị loại bỏ. |
| **Cluster Operator** | Kubernetes operator quản lý vòng đời RabbitMQ cluster | Tạo StatefulSet, Service, PVC, peer discovery và hỗ trợ rolling operation. |
| **Competing Consumers** | Nhiều consumer cùng đọc một queue để chia việc | Mỗi delivery đi tới một consumer; tăng throughput nhưng thứ tự hoàn tất có thể thay đổi. |
| **Confirm Timeout** | Publisher không nhận confirm trong thời hạn | Trạng thái unknown, không chứng minh publish thất bại; retry có thể tạo duplicate. |
| **Connection** | Kết nối TCP thật giữa client và broker | Tốn chi phí thiết lập, nên tái sử dụng và bật heartbeat. |
| **Consistent Hash Exchange** | Plugin exchange phân vùng theo hash ring | Cùng key vào cùng shard khi topology ổn định và ít key bị remap khi đổi shard. |
| **Consumer** | Thành phần nhận delivery từ queue để xử lý | Nhiều consumer trên một queue thường chia nhau công việc. |
| **Consumer Tag** | Mã định danh một subscription | Dùng để hủy hoặc theo dõi consumer; khác với delivery tag. |
| **Continuous Membership Reconciliation (CMR)** | Cơ chế tự đưa nhóm replica quorum queue về target size | Giảm thao tác membership thủ công nhưng không thay thế giám sát và xử lý node mất vĩnh viễn. |
| **Dead-letter Exchange (DLX)** | Exchange nhận message bị reject, hết TTL hoặc vượt giới hạn phù hợp | DLX định tuyến tiếp; bản thân nó không phải một queue. |
| **Dead-letter Queue (DLQ)** | Queue được bind để giữ dead-lettered message | Dùng cho điều tra, sửa dữ liệu và replay có kiểm soát. |
| **Definition Export** | File JSON chứa topology và metadata của broker | Có queue/exchange/user/policy nhưng không chứa message body; cần bảo vệ vì có dữ liệu nhạy cảm. |
| **Delayed Retry** | Giữ message lỗi tạm thời trước khi giao lại | Quorum queue 4.3 hỗ trợ native linear backoff; khác với scheduling message mới. |
| **Delivery Mode** | Thuộc tính transient hoặc persistent của message AMQP | `2` là persistent nhưng vẫn cần durable topology và publisher confirm. |
| **Delivery Tag** | Số thứ tự định danh một delivery trên channel | Ack/nack phải dùng đúng tag và đúng channel đã nhận. |
| **Direct Exchange** | Exchange khớp chính xác routing key với binding key | Hợp với routing đơn giản theo loại lệnh/sự kiện cụ thể. |
| **Direct Reply-To** | Cơ chế RPC trả response không cần reply queue thật | Zero-buffer và at-most-once; reply mất nếu requester ngắt kết nối. |
| **Durable** | Resource metadata sống qua lần restart broker | Durable queue không tự biến mọi message thành persistent. |
| **Erlang Cookie** | Shared secret dùng để xác thực node và CLI trong Erlang distribution | Các node cluster phải dùng cùng cookie; lưu như secret và giới hạn quyền truy cập file. |
| **Exactly-once** | Một business effect duy nhất trong phạm vi xác định | RabbitMQ không cung cấp end-to-end tự động; thường cần transaction và idempotency. |
| **Exchange** | Thành phần nhận message và quyết định route | Thường không lưu message; message chỉ chờ sau khi vào queue/stream. |
| **Exclusive Queue** | Queue chỉ connection khai báo được dùng | Bị xóa khi connection đóng; thường dùng tên do server sinh. |
| **Failure Domain** | Phạm vi hạ tầng có thể hỏng cùng lúc | Node cùng máy, rack hoặc zone không tạo khả năng chịu lỗi độc lập. |
| **Fanout Exchange** | Exchange broadcast đến mọi destination đã bind | Bỏ qua routing key. |
| **Feature Flag** | Cờ kích hoạt capability/format mới trong quá trình nâng cấp | Thường không thể đảo ngược sau khi bật; mọi node phải hỗ trợ. |
| **Federation** | Plugin liên kết exchange/queue giữa các RabbitMQ cluster | Phù hợp WAN và luồng theo nhu cầu; không phải replication đồng bộ toàn cluster. |
| **Flow Control** | Broker/client làm chậm phía gửi khi tài nguyên bị áp lực | Memory/disk alarm có thể khiến publisher bị block; phải quan sát thay vì retry mù. |
| **Headers Exchange** | Exchange route theo các header của message | `x-match=all` giống AND, `x-match=any` giống OR. |
| **Heartbeat** | Tín hiệu định kỳ để phát hiện connection không còn hoạt động | Không thay thế timeout nghiệp vụ hoặc publisher confirms. |
| **Idempotency** | Xử lý lặp cùng message mà không tạo kết quả sai/lặp | Cần thiết vì gửi lại và redelivery có thể tạo duplicate. |
| **Inbox Pattern** | Ghi message ID và business update cùng consumer transaction | Unique constraint biến redelivery sau commit thành thao tác an toàn. |
| **Khepri** | Metadata store dựa trên Raft của RabbitMQ hiện đại | Là metadata store duy nhất trong RabbitMQ 4.3; thay thế Mnesia. |
| **Leader Rebalancing** | Phân phối lại leader queue/stream giữa các node | Chạy sau khi thêm node hoặc bảo trì để tránh một node gánh quá nhiều leader. |
| **Mandatory Flag** | Yêu cầu broker trả message nếu không route tới queue nào | Không bảo đảm message đã được ghi bền vững và không thay thế confirm. |
| **Message** | Body byte cùng properties/headers | Broker không tự hiểu JSON hay schema nghiệp vụ bên trong. |
| **Modulus Hash Exchange** | Exchange built-in phân queue bằng `hash mod N` | Route ổn định khi bindings không đổi; đổi số shard làm phần lớn key bị remap. |
| **Negative Acknowledgement (Nack)** | Consumer báo xử lý thất bại | Có thể requeue hoặc loại/dead-letter; requeue vô hạn tạo retry loop. |
| **Node Name** | Danh tính ổn định của một RabbitMQ node | Có liên hệ với dữ liệu và cluster membership; đổi tùy tiện có thể làm restore/rejoin thất bại. |
| **Operator Policy** | Guardrail do operator áp lên resource | Có ưu tiên cao hơn policy thường và nhiều client-provided argument. |
| **Outbox Pattern** | Ghi event cùng transaction với business data rồi relay ra broker | Loại dual-write loss nhưng relay có thể publish duplicate. |
| **Peer Discovery** | Cơ chế để node tìm các peer khi tạo/join cluster | Nên được tự động hóa bởi nền tảng hoặc Operator thay vì hard-code thao tác join. |
| **Pending Confirm** | Publish đã gửi nhưng chưa có ack/nack từ broker | Phải giới hạn count/bytes/age và lưu đủ dữ liệu để retry. |
| **Persistent Message** | Message có `delivery_mode=2` | Cần durable queue và publisher confirm để biết persistence condition đã hoàn tất. |
| **Poison Message** | Message luôn làm consumer thất bại | Cần delivery limit, retry có backoff và DLQ. |
| **Policy** | Cấu hình áp theo regex lên nhóm resource | Phù hợp TTL, DLX và length limit vì đổi được không cần redeploy app. |
| **Prefetch** | Số delivery chưa ack tối đa được đẩy tới consumer | Là cửa sổ xử lý, không phải số thread; quá cao dễ làm lệch tải và tăng memory. |
| **Publish Sequence Number** | Số thứ tự publish trên channel ở confirm mode | Dùng ghép asynchronous ack/nack với pending message. |
| **Publisher** | Thành phần gửi message vào exchange | Cần xử lý confirm, unroutable message và connection recovery. |
| **Publisher Confirm** | Broker xác nhận đã nhận trách nhiệm cho publish | Không có nghĩa consumer đã xử lý; confirm thất lạc có thể khiến publisher gửi trùng. |
| **Queue** | Bộ đệm có thứ tự giữ message chờ consumer | Thường xóa message sau ack; ordering quan sát được có thể đổi do priority/redelivery. |
| **Quorum** | Số thành viên đa số cần đồng thuận | Với 3 replica cần 2; mất đa số làm quorum queue không khả dụng. |
| **Quorum Critical** | Trạng thái chỉ cần mất thêm một member là resource mất quorum | Cần alert trước khi bảo trì hoặc sự cố kế tiếp làm queue unavailable. |
| **Quorum Queue** | Queue replicated dựa trên Raft | Lựa chọn mặc định khi cần queue HA và data safety trong RabbitMQ hiện đại. |
| **Raft** | Thuật toán đồng thuận leader–followers | Quorum queue dùng Raft để replicate log và bầu leader. |
| **Ready** | Message đang nằm trong queue, chưa giao cho consumer | `messages_ready` tăng liên tục thường báo consumer không theo kịp. |
| **Recovery Point Objective (RPO)** | Mức dữ liệu tối đa chấp nhận mất sau thảm họa | Phải đo từ cơ chế replication/backup thực tế, không chỉ ghi trong tài liệu. |
| **Recovery Time Objective (RTO)** | Thời gian tối đa để khôi phục dịch vụ | Bao gồm phát hiện, quyết định, chuyển traffic và xác minh dữ liệu. |
| **Redelivery** | Giao lại một message đã từng được deliver | Có thể xảy ra sau requeue hoặc connection/channel mất; consumer phải idempotent. |
| **Request/Reply** | Pattern gửi request và nhận response qua broker | Dùng `reply_to` và `correlation_id`; timeout không chứng minh request chưa chạy. |
| **Resource Alarm** | Cảnh báo broker chạm ngưỡng memory hoặc disk | Có thể block publisher toàn cluster trong khi consumer tiếp tục drain. |
| **Retry Queue** | Queue giữ message trong thời gian chờ thử lại | Thường dùng TTL + DLX ở hệ thống cũ; có rủi ro duplicate khi republish/ack. |
| **Return** | Message được broker trả lại publisher | Xảy ra với publish `mandatory=true` mà không có route phù hợp. |
| **Rolling Upgrade** | Nâng từng node trong khi phần còn lại tiếp tục phục vụ | Cần đúng upgrade path, quorum, feature flag và kiểm tra node bắt kịp trước bước tiếp theo. |
| **Routing Key** | Chuỗi publisher gắn khi publish để exchange định tuyến | Direct so khớp chính xác; topic so khớp theo `*` và `#`. |
| **Shovel** | Plugin chuyển message một chiều từ source tới destination | Hoạt động như client consume rồi republish; `on-confirm` ưu tiên data safety. |
| **Single Active Consumer (SAC)** | Chỉ một consumer active trên queue, các consumer khác standby | Broker tự failover; hữu ích khi cần ordering và continuity. |
| **Stream** | Log replicated, đọc không phá hủy và có retention | Phù hợp replay/fan-out lớn; semantics không giống queue giao task. |
| **Super Stream** | Một logical stream được chia thành nhiều partition stream | Scale throughput bằng cách phân phối storage và traffic qua nhiều node. |
| **Time-to-live (TTL)** | Thời gian message hoặc queue được phép tồn tại | Message TTL và queue TTL là hai cơ chế khác nhau; thường quản lý bằng policy. |
| **Topic Exchange** | Exchange route theo pattern của routing key | `*` khớp một từ, `#` khớp không hoặc nhiều từ. |
| **Unacknowledged** | Delivery đã gửi nhưng consumer chưa ack/nack | Tăng cao có thể do xử lý chậm, consumer treo hoặc prefetch quá lớn. |
| **Unconfirmed Message** | Message publisher chưa nhận confirm | Khi connection mất, phải xem là unknown và retry idempotently. |
| **Unroutable Message** | Message không khớp destination nào từ exchange | Xử lý bằng `mandatory`, alternate exchange và metric/alert. |
| **Virtual Host (Vhost)** | Namespace logic chứa topology và permissions | Cô lập tên/quyền, nhưng vẫn dùng chung tài nguyên vật lý của cluster. |
| **Work Queue** | Một queue có nhiều worker cạnh tranh xử lý | Phù hợp giao task; khác pub/sub vì không nhân một bản cho từng service. |
| **x-death** | Header ghi lịch sử dead-letter của AMQP 0-9-1 | Là mảng record nén theo queue/reason, không phải retry counter đơn giản. |

## Phân biệt nhanh

| Cặp dễ nhầm | Khác nhau |
|---|---|
| Publisher confirm ↔ Consumer ack | Confirm bảo vệ chặng publisher → broker; ack bảo vệ chặng broker → consumer. |
| DLX ↔ DLQ | DLX định tuyến dead letter; DLQ là nơi lưu chúng. |
| Durable ↔ Persistent | Durable nói về resource; persistent nói về message. |
| Mandatory ↔ Confirm | Mandatory phát hiện không có route; confirm xác nhận broker nhận trách nhiệm. |
| Outbox ↔ Inbox | Outbox bảo vệ DB → broker; Inbox bảo vệ broker → consumer DB. |
| Persistent ↔ Confirmed | Persistent là yêu cầu lưu; confirmed là tín hiệu broker đã đạt điều kiện nhận trách nhiệm. |
| Queue ↔ Stream | Queue thường xóa sau ack; stream giữ theo retention và cho đọc lại. |
| Redelivery ↔ Duplicate | Redelivery là tín hiệu broker giao lại; duplicate nghiệp vụ còn có thể đến từ publisher gửi lại. |
| Retry ↔ Scheduling | Retry trì hoãn message đã xử lý lỗi; scheduling lên lịch message/công việc mới tại thời điểm tương lai. |
| Work Queue ↔ Pub/Sub | Work Queue chia một bản giữa workers; Pub/Sub tạo queue/bản riêng cho từng subscriber. |
| At-most-once ↔ At-least-once | At-most-once chấp nhận mất để không retry; at-least-once retry và chấp nhận duplicate. |
| Cluster replication ↔ Queue replication | Cluster nhân bản metadata; message chỉ được nhân bản khi queue type/replica group hỗ trợ. |
| Definitions backup ↔ Message backup | Definitions lưu topology/metadata; message store cần chiến lược backup hoặc DR riêng. |

## Đọc tiếp

- [RabbitMQ Fundamentals](rabbitmq_fundamentals.md)
- [Messaging Patterns](rabbitmq_patterns.md)
- [Reliability & Guarantees](rabbitmq_reliability.md)
- [Production & Operations](rabbitmq_production.md)

*Cập nhật lần cuối: 2026-07-29*
