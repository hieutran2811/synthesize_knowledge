---
title: "Case Studies – Real-time & Scale (News Feed, Chat, Proximity/Geo)"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Case Studies – Real-time & Scale (News Feed, Chat, Proximity/Geo)

> Áp dụng RESHADED ([../fundamentals/interview_framework_estimation.md](../fundamentals/interview_framework_estimation.md)). Tra cứu nhanh: [System Design Glossary](../glossary.md). Tiếp nối [foundational_designs.md](foundational_designs.md); tiếp theo [platform_designs.md](platform_designs.md).

---

## 1. News Feed / Timeline (Twitter, Facebook)

## 1.1 Requirements

**Functional**: post bài; follow/unfollow; xem feed của những người mình follow.
**Ngoài phạm vi**: ads, ranking bằng ML (nhắc nhưng không đào), moderation.

**Non-functional**
- **Read-heavy** (~25:1).
- Feed trễ vài giây là chấp nhận được → **eventual consistency**.
- p99 đọc feed < 200ms.
- Phải xử lý được **celebrity** (một người có hàng chục triệu follower).

## 1.2 Estimation

```text
200M DAU · đọc 50 lần feed/ngày · post 2 bài/ngày · bài ~300 B

Read  QPS ≈ 200M × 50 / 10⁵ = 100K → đỉnh 300K
Write QPS ≈ 200M × 2  / 10⁵ = 4K   → đỉnh 12K
→ đọc:ghi = 25:1 → PRECOMPUTE lúc ghi rẻ hơn tính lúc đọc

Fan-out: trung bình 200 follower/user
  → 12K post/s × 200 = 2,4M lượt ghi timeline/s  ← đây là con số quyết định thiết kế
  → celebrity 50M follower: MỘT post = 50M lượt ghi → không thể làm đồng bộ
```

Con số 2,4M lượt ghi/giây là điều làm bài này khó, và cũng là điều làm nó thú vị: chi phí không nằm ở việc đọc hay ghi bài, mà ở **fan-out**.

## 1.3 Chiến lược fan-out – mấu chốt của bài

| Chiến lược | Cơ chế | Chi phí ghi | Chi phí đọc | Vấn đề |
|---|---|---|---|---|
| **Fan-out on write (push)** | Post → đẩy id bài vào timeline của mọi follower | Rất cao (write amplification) | Rất thấp (đã có sẵn) | Celebrity; người dùng không hoạt động vẫn được ghi |
| **Fan-out on read (pull)** | Đọc feed → gom bài của những người mình follow, merge và sort | Rất thấp | Cao (gom + sort runtime) | Người follow 5.000 người → query rất nặng |
| **Hybrid** | Push cho user thường, **pull cho celebrity** | Cân bằng | Thấp | Phức tạp hơn; cần ngưỡng phân loại |

```text
Hybrid (cách thực tế):
  Ngưỡng: user có > 100K follower → đánh dấu "celebrity", KHÔNG fan-out

  Đường ghi:
    post của user thường → Kafka → fan-out worker → RPUSH id vào timeline:{follower} (Redis)
    post của celebrity   → chỉ ghi vào bảng posts, KHÔNG fan-out

  Đường đọc:
    feed = merge( timeline:{user} từ Redis ,
                  posts mới nhất của các celebrity mà user follow (pull, có cache riêng) )
    → sort theo thời gian/score → hydrate nội dung → trả
```

Hai tối ưu quan trọng cho fan-out on write:

1. **Chỉ fan-out cho user đang hoạt động.** Nếu 60% user không đăng nhập trong 30 ngày, bỏ họ khỏi fan-out giảm hơn nửa chi phí. Khi họ quay lại, dựng timeline bằng pull một lần rồi chuyển sang push.
2. **Timeline chỉ lưu `post_id`, không lưu nội dung.** Timeline 800 bài × 8 byte = 6,4 KB/user thay vì vài trăm KB; và khi bài bị sửa/xóa thì không phải cập nhật hàng triệu bản sao.

## 1.4 Design

```text
GHI:
Client → Post Service → INSERT posts (Cassandra/sharded)
                      → publish "post.created" → Kafka
                                                   ↓
                                         Fan-out Workers (nhiều consumer)
                                                   ↓
                                    Redis: LPUSH timeline:{followerId} postId
                                           LTRIM timeline:{followerId} 0 799  ← giữ 800 gần nhất

ĐỌC:
Client → Feed Service
           → LRANGE timeline:{userId} 0 49          (id bài từ push)
           → + query bài mới của celebrity đang follow (pull, cache theo celebrity)
           → merge + sort
           → MGET post:{id} để hydrate nội dung (cache; miss → DB)
           → trả 50 bài
```

```text
Data model:
  posts        (post_id PK, author_id, content, created_at, media_ids)   ← post_id = Snowflake
  follows      (follower_id, followee_id, created_at)                    ← cần cả hai chiều index
  follow_stats (user_id, follower_count)                                 ← để phát hiện celebrity
```

Bảng `follows` cần index theo cả hai chiều: `(follower_id)` để trả lời "tôi follow ai" (đường đọc pull) và `(followee_id)` để trả lời "ai follow tôi" (đường fan-out). Đây là ví dụ denormalize cần thiết.

## 1.5 Deep dive

**Celebrity problem chi tiết**: ngoài việc không fan-out, còn cần cache riêng cho "bài mới nhất của celebrity X" — vì hàng triệu người sẽ hỏi cùng câu đó. Đây là hot key kinh điển, xử lý bằng L1 local cache TTL ngắn ([caching.md](../fundamentals/caching.md) mục 6).

**Ranking không theo thời gian**: khi feed được xếp theo điểm ML thay vì thời gian, kiến trúc đổi: timeline lưu `post_id` như cũ, nhưng **sort lúc đọc** theo điểm tính từ feature (độ mới, tương tác, quan hệ). Điều này làm đường đọc nặng hơn nhưng vẫn khả thi vì chỉ ranking ~500 ứng viên, không phải toàn bộ.

**Bài bị xóa/sửa**: vì timeline chỉ lưu id, xóa bài không cần dọn hàng triệu timeline — lúc hydrate không tìm thấy thì bỏ qua. Đây là lợi ích cụ thể thứ hai của việc lưu id.

**Unfollow**: không xóa các bài đã có trong timeline (quá đắt) — chỉ ngừng nhận bài mới, và lọc lúc đọc nếu cần chính xác.

**Fan-out worker bị lag**: theo dõi consumer lag của Kafka. Khi lag tăng, feed trễ hơn nhưng hệ thống không sập — đây là điểm mạnh của việc tách fan-out ra bất đồng bộ.

## 1.6 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| Push vs pull vs hybrid | Chi phí ghi ↔ chi phí đọc ↔ độ phức tạp |
| Chỉ fan-out user hoạt động | Tiết kiệm lớn ↔ user quay lại cần dựng timeline |
| Lưu id vs lưu nội dung | RAM và tính đúng khi sửa/xóa ↔ thêm một lần hydrate |
| Giới hạn timeline 800 bài | RAM có hạn ↔ không xem được rất xa về quá khứ (fallback sang pull) |
| Ranking ML lúc đọc | Feed liên quan hơn ↔ đường đọc nặng và phức tạp hơn |

---

## 2. Chat System (WhatsApp / Messenger)

## 2.1 Requirements

**Functional**: chat 1:1 và nhóm; trạng thái đã gửi/đã nhận/đã đọc; online/last-seen; push notification khi offline; lịch sử; đồng bộ nhiều thiết bị.

**Non-functional**
- Real-time (p99 gửi→nhận < 500ms trong cùng vùng).
- **Thứ tự tin nhắn trong một hội thoại phải đúng**.
- Không mất tin nhắn (durability cao) — đây là yêu cầu chặt nhất.
- Giao được khi người nhận online lại.

## 2.2 Estimation

```text
50M DAU · 40 tin/người/ngày · tin ~200 B (text)

Write QPS ≈ 50M × 40 / 10⁵ = 20K → đỉnh 60K
Kết nối đồng thời: giả sử 20% DAU online cùng lúc = 10M kết nối WebSocket
  → 10M / 100K kết nối mỗi node ≈ 100 connection node
Storage = 50M × 40 × 200 B = 400 GB/ngày → 1 năm ≈ 146 TB (chưa replication)
  → ghi rất nhiều, đọc theo (chat_id, thời gian) → LSM store
```

Con số 10M kết nối đồng thời là điều làm bài này khác các bài khác: bài toán chính không phải QPS mà là **quản lý kết nối stateful**.

## 2.3 Design

```text
Client ⇄ WebSocket ⇄ Connection Node (stateful, giữ kết nối)
                          │
                          ├─ đăng ký vào Session Registry (Redis): user:{id} → node:{addr}, TTL + heartbeat
                          │
Gửi tin:
  Client A → Connection Node 1 → Chat Service
                                   → sinh message_id (Snowflake) + seq trong hội thoại
                                   → GHI BỀN vào store (Cassandra)  ← xác nhận cho A sau bước này
                                   → tra registry: B đang ở node nào?
                                       ├─ online  → publish qua Kafka/Redis pub-sub tới node đó → node đẩy xuống B
                                       └─ offline → đưa vào inbox chờ + Push Notification (APNs/FCM)
```

Điểm thứ tự quan trọng: **xác nhận cho người gửi sau khi đã ghi bền**, không phải sau khi đã đẩy cho người nhận. Người gửi cần biết "tin đã được hệ thống nhận"; việc giao cho người nhận là bước sau và có thể chậm.

```text
Data model (Cassandra):
  messages:
    PARTITION KEY  (chat_id, bucket)      ← bucket theo tháng, tránh partition quá lớn
    CLUSTERING KEY (seq DESC)             ← đọc "50 tin gần nhất" là một range scan
    columns: message_id, sender_id, content, created_at, type

  chat_members: (chat_id, user_id, joined_at, last_read_seq)
  user_chats:   (user_id, chat_id, last_message_at)   ← để dựng danh sách hội thoại
```

Việc **bucket partition theo thời gian** là chi tiết thực tế quan trọng: một hội thoại nhóm hoạt động nhiều năm sẽ tạo partition khổng lồ, gây vấn đề với Cassandra. Bucket theo tháng giữ partition trong giới hạn hợp lý.

## 2.4 Deep dive – thứ tự tin nhắn

Đây là phần khó nhất và thường bị trả lời sai.

```text
Vấn đề: timestamp từ client KHÔNG đáng tin (đồng hồ thiết bị lệch, có thể bị sửa)
        timestamp từ server cũng lệch giữa các node ([distributed_systems_theory.md] mục 6)

Giải: mỗi hội thoại có một BỘ ĐẾM seq TĂNG DẦN, do một nơi cấp
  → mọi tin trong chat_id có seq duy nhất và tăng dần
  → client sort theo seq, không theo timestamp
  → client phát hiện thiếu tin (seq nhảy) và yêu cầu gửi lại
```

Cách cấp `seq`:

| Cách | Ưu | Nhược |
|---|---|---|
| Counter atomic trong Redis theo `chat_id` | Đơn giản, nhanh | Redis là dependency nóng cho đường ghi |
| Lightweight transaction của Cassandra | Không thêm hệ thống | Chậm (dùng Paxos) |
| **Định tuyến mọi tin của một chat qua một partition Kafka** | Thứ tự tự nhiên, không cần counter | Cần đảm bảo routing ổn định |

Cách thứ ba đáng chú ý: nếu `chat_id` là partition key của Kafka, mọi tin của một hội thoại đi qua **một** partition và được xử lý tuần tự bởi một consumer — thứ tự có được "miễn phí" từ kiến trúc, không cần coordination. Đây là ví dụ điển hình của nguyên tắc "thiết kế single-writer thay vì lock" ([distributed_systems_theory.md](../fundamentals/distributed_systems_theory.md) mục 7.2).

**Delivery semantics**: at-least-once + dedup theo `message_id` ở client. Client giữ tập id đã nhận (hoặc chỉ cần seq lớn nhất liên tục) và bỏ qua tin trùng. Exactly-once không tồn tại ở tầng vận chuyển — xem [distributed_systems_theory.md](../fundamentals/distributed_systems_theory.md) mục 1.2.

**Đồng bộ nhiều thiết bị**: mỗi thiết bị giữ `last_synced_seq` cho từng hội thoại; khi kết nối lại thì kéo `seq > last_synced_seq`. Đơn giản và đúng — và là lý do nữa để dùng seq thay vì timestamp.

## 2.5 Deep dive – kết nối và presence

**Session registry**: `user:{id} → node_addr` trong Redis với TTL, được gia hạn bằng heartbeat. Node chết → TTL hết → entry tự dọn. Cần xử lý một user có nhiều thiết bị: lưu set các `(device_id, node_addr)`.

**Presence (online/offline/last-seen)**:

```text
Online:  heartbeat qua WebSocket mỗi 30s → SET user:{id}:online = 1 EX 60
Offline: TTL hết → coi là offline (không cần event tường minh)
Last-seen: cập nhật khi ngắt kết nối hoặc theo heartbeat cuối
```

Cạm bẫy về presence mà hay bị over-engineer: **broadcast trạng thái online tới mọi bạn bè là bài toán fan-out lớn hơn cả chat**. Một user có 1.000 bạn, mỗi lần online/offline là 1.000 lượt thông báo; với 10M user thì không khả thi. Cách thực tế:

- Chỉ trả trạng thái khi **được hỏi** (khi mở danh sách hội thoại hoặc mở một chat).
- Chấp nhận độ trễ vài chục giây.
- Không đảm bảo chính xác tuyệt đối — không ai khiếu nại vì last-seen lệch 30 giây.

**Chat nhóm**: nhóm nhỏ (< 500) → fan-out tới từng thành viên như 1:1. Nhóm lớn (hàng nghìn) → không fan-out, thành viên **pull** khi mở chat, kèm một tín hiệu nhẹ "có tin mới". Cùng logic hybrid của bài news feed.

**Deploy connection node**: rolling deploy làm ngắt hàng loạt kết nối. Cần drain có kiểm soát: ngừng nhận kết nối mới → gửi tín hiệu "hãy kết nối lại" cho client → client reconnect với backoff **có jitter** (không có jitter thì 100K client cùng reconnect một lúc).

## 2.6 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| WebSocket vs long polling/SSE | Hai chiều, độ trễ thấp ↔ stateful, khó scale và khó deploy |
| seq tập trung vs Kafka partition | Đơn giản ↔ thứ tự "miễn phí" nhưng ràng buộc routing |
| Cassandra vs RDBMS | Ghi rất nhanh, scale ngang ↔ mất transaction, truy vấn cứng nhắc |
| Fan-out nhóm nhỏ vs pull nhóm lớn | Đơn giản ↔ hai đường code |
| Presence chính xác | UX tốt hơn ↔ fan-out rất lớn (nên chấp nhận gần đúng) |
| Mã hóa đầu-cuối (E2EE) | Bảo mật cao nhất ↔ server không tìm kiếm/kiểm duyệt được, đồng bộ đa thiết bị khó hơn nhiều |

Hàng cuối đáng nhắc nếu người phỏng vấn hỏi: E2EE đổi hoàn toàn bài toán — server chỉ là bộ chuyển tin, mọi tính năng cần đọc nội dung (tìm kiếm, backup phía server, moderation) phải làm ở client hoặc bỏ.

---

## 3. Proximity / Geo Service (Yelp nearby, Uber)

## 3.1 Requirements

**Functional**: tìm đối tượng trong bán kính R quanh một điểm; xếp theo khoảng cách.

**Phân biệt hai loại workload — đây là điều đầu tiên cần làm rõ:**

| | Static (nhà hàng, cửa hàng) | Dynamic (tài xế, người giao hàng) |
|---|---|---|
| Tần suất cập nhật vị trí | Rất thấp | Mỗi 3–5 giây |
| Số đối tượng | Hàng triệu | Hàng trăm nghìn đang hoạt động |
| Bài toán chính | Truy vấn nhanh | **Ghi nhiều** + truy vấn nhanh |
| Store phù hợp | Index geo bền (PostGIS, Elasticsearch) | In-memory (Redis GEO) |

## 3.2 Estimation

```text
Static: 10M địa điểm · 5K QPS truy vấn "nearby"
  → index geo trong PostgreSQL/Elasticsearch là đủ; cache kết quả phổ biến

Dynamic (Uber-like): 200K tài xế hoạt động · cập nhật mỗi 4s
  Write QPS = 200K / 4 = 50K QPS cập nhật vị trí   ← đây là bài toán
  Query QPS = 20K (khách tìm xe)
  State = 200K × ~100 B ≈ 20 MB → vừa RAM thoải mái
  → in-memory store, shard theo vùng địa lý
```

## 3.3 Kỹ thuật index không gian

| Kỹ thuật | Cơ chế | Mạnh | Yếu |
|---|---|---|---|
| **Geohash** | Mã hóa lat/lng thành chuỗi; prefix chung = gần nhau | Đơn giản, query bằng prefix, dùng được với mọi KV store | Ô có kích thước cố định → kém với mật độ không đều; **vấn đề biên** |
| **Quadtree** | Chia không gian thành 4 ô đệ quy tới khi đủ thưa | Thích nghi với mật độ | Phải giữ cây trong RAM; rebalance khi dữ liệu đổi |
| **Google S2** | Hilbert curve → cell id, nhiều mức | Bảo toàn locality tốt hơn geohash, chuẩn thực tế | Phức tạp hơn |
| **R-tree / PostGIS GiST** | Cây bao hình chữ nhật | Truy vấn hình phức tạp, có sẵn trong PostgreSQL | Ghi chậm hơn |
| **Redis GEO** | Sorted set với score là geohash 52-bit | Rất nhanh, `GEOADD`/`GEOSEARCH` sẵn có | Trong RAM; không hình phức tạp |

### 3.3.1 Vấn đề biên của geohash – chi tiết hay bị bỏ

```text
Geohash "9q8yy" ≈ ô 5km × 5km

Hai điểm cách nhau 100m nhưng nằm hai bên biên ô
→ prefix geohash HOÀN TOÀN KHÁC NHAU
→ query chỉ theo prefix sẽ BỎ SÓT chúng

Giải: luôn query ô của điểm + 8 Ô LÂN CẬN, rồi lọc lại theo khoảng cách thật
```

Đây là chi tiết phân biệt câu trả lời có kinh nghiệm với câu trả lời từ sách: bất kỳ ai nói "dùng geohash rồi query theo prefix" mà không nhắc ô lân cận đều sẽ có bug bỏ sót kết quả.

Việc chọn độ chính xác (số ký tự geohash) cũng là đánh đổi:

```text
Prefix dài (ô nhỏ):  ít đối tượng mỗi ô, nhưng phải quét NHIỀU ô cho bán kính lớn
Prefix ngắn (ô lớn): ít ô, nhưng mỗi ô nhiều đối tượng phải lọc
→ chọn theo bán kính truy vấn phổ biến; hoặc dùng nhiều mức và chọn động
```

## 3.4 Design

```text
STATIC (nhà hàng):
  Places DB (PostgreSQL + PostGIS, hoặc Elasticsearch geo_point)
  Query: ST_DWithin / geo_distance → lọc theo bán kính → sort → phân trang
  Cache: kết quả cho (geohash prefix, bộ lọc) với TTL vài phút
         → truy vấn "nhà hàng gần đây" ở cùng khu vực rất trùng lặp → hit ratio cao

DYNAMIC (tài xế):
  Driver app → gửi vị trí mỗi 4s → Location Ingest Service
                                     → Redis GEOADD drivers:{cityShard} lng lat driverId
                                     → (tùy chọn) publish vào Kafka cho analytics/lịch sử

  Rider app → Matching Service → GEOSEARCH drivers:{cityShard}
                                   BYRADIUS 3 km ASC COUNT 20
                                 → lọc theo trạng thái (rảnh/đang chở) → ghép
```

**Shard theo vùng địa lý** cho dynamic là quyết định quan trọng: một sorted set chứa toàn bộ tài xế toàn quốc sẽ là hot key. Shard theo thành phố/vùng cho phép mở rộng ngang và cô lập sự cố theo vùng.

## 3.5 Deep dive

**Hot spot theo địa lý**: trung tâm thành phố vào giờ cao điểm có mật độ cực cao, vùng ngoại ô gần như rỗng. Geohash với ô đều xử lý kém tình huống này (một ô có 10.000 đối tượng, ô khác có 2). Quadtree/S2 thích nghi tốt hơn vì chia sâu hơn ở nơi dày. Với Redis GEO, cách thực dụng là shard theo vùng có kích thước không đều — vùng đông được chia nhỏ hơn.

**Giảm tần suất cập nhật vị trí**: 50K QPS ghi có thể giảm đáng kể bằng cách chỉ gửi khi **di chuyển đủ xa** (ví dụ > 30m) hoặc **đổi hướng đáng kể**, thay vì mỗi 4 giây cố định. Với tài xế đang đứng chờ, điều này giảm gần như toàn bộ lưu lượng.

**Lịch sử vị trí**: Redis chỉ giữ vị trí hiện tại. Nếu cần lịch sử (đối soát chuyến đi, phân tích), publish song song vào Kafka → store time-series/LSM. Đây là ví dụ tách "trạng thái hiện tại" và "chuỗi sự kiện" — hai nhu cầu, hai store.

**Khoảng cách đường đi vs đường thẳng**: `GEOSEARCH` trả khoảng cách theo đường chim bay. Người dùng quan tâm thời gian di chuyển thật. Mẫu thực tế: dùng geo để lấy ~20 ứng viên gần nhất (rẻ), rồi gọi routing engine cho 20 ứng viên đó (đắt) để xếp theo ETA. Đây là mẫu **filter rẻ trước, xếp hạng đắt sau** — cùng mẫu với ranking feed và với typeahead.

**Xử lý ghép trùng** (hai khách cùng ghép một tài xế): cần một bước atomic khi ghép — `SET NX` trên `driver:{id}:assignment`, hoặc điều kiện trong chính câu ghi. Đây là nơi cần bảo đảm đúng đắn, khác với phần tìm kiếm gần đúng là được.

## 3.6 Trade-offs

| Quyết định | Đánh đổi |
|---|---|
| Geohash vs quadtree/S2 | Đơn giản, dùng KV store bất kỳ ↔ thích nghi mật độ tốt hơn nhưng phức tạp |
| Prefix dài vs ngắn | Ít đối tượng mỗi ô ↔ ít ô phải quét |
| Redis GEO vs PostGIS | Ghi rất nhanh, trong RAM ↔ bền, truy vấn hình phức tạp |
| Cập nhật định kỳ vs theo ngưỡng di chuyển | Đơn giản ↔ giảm lưu lượng rất nhiều |
| Chỉ trạng thái hiện tại vs có lịch sử | Đơn giản, ít dung lượng ↔ đối soát và phân tích được |
| Đường chim bay vs ETA thật | Rẻ, nhanh ↔ đúng nhu cầu người dùng (dùng hai bước) |

---

## Ghi chú – chủ đề tiếp theo

- [platform_designs.md](platform_designs.md): object storage, typeahead, payment, notification.
- [foundational_designs.md](foundational_designs.md): URL shortener, ID, rate limiter.
- [../fundamentals/networking_protocols.md](../fundamentals/networking_protocols.md): WebSocket vs SSE, cái giá của stateful.
- [../fundamentals/storage_retrieval.md](../fundamentals/storage_retrieval.md): vì sao Cassandra (LSM) phù hợp chat.
- [../fundamentals/distributed_systems_theory.md](../fundamentals/distributed_systems_theory.md): thứ tự, đồng hồ, single-writer.
- [../fundamentals/caching.md](../fundamentals/caching.md): hot key (celebrity, vùng đông).
- [websocket package](../../websocket/roadmap.md), [kafka event-driven](../../kafka/patterns/event_driven_architecture.md), [redis patterns](../../redis/redis_patterns.md).

Từ khóa mở rộng: fan-out on write/read, write amplification, celebrity problem, timeline trimming, hydrate, session registry, pub/sub backplane, presence TTL, message seq vs timestamp, partition bucketing theo thời gian, geohash neighbor cells, Hilbert curve, S2 cell level, `GEOSEARCH BYRADIUS`, filter-then-rank.

---

*Cập nhật lần cuối: 2026-07-30*
