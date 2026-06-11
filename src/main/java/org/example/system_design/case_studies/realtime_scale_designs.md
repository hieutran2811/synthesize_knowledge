# Case Studies – Real-time & Scale (News Feed, Chat, Proximity/Geo)

> Áp dụng RESHADED ([../fundamentals/interview_framework_estimation.md](../fundamentals/interview_framework_estimation.md)). Tiếp nối [foundational_designs.md](foundational_designs.md).

---

# 1. Design a News Feed / Timeline (Twitter, Facebook)

### Requirements
- **Functional**: post, follow, xem timeline (bài của người mình follow, mới nhất trước).
- **Non-functional**: **read-heavy**, near-real-time (vài giây), HA; xử lý **celebrity** (triệu follower).

### Estimation
```
200M DAU, đọc 50 feed/ngày → ~115K read QPS; post 2/ngày → ~5K write QPS (read:write 25:1)
→ read-heavy → precompute + cache timeline
```

### How – Fan-out (mấu chốt)
| Chiến lược | Cơ chế | Ưu | Nhược |
|-----------|--------|----|----|
| **Fan-out on write (push)** | Khi post → đẩy vào timeline cache của MỌI follower | Đọc cực nhanh (đã precompute) | Celebrity 10M follower → 10M ghi/post (write amplification) |
| **Fan-out on read (pull)** | Đọc timeline → gom bài từ những người follow lúc đó | Ghi rẻ | Đọc chậm (gom + sort runtime) |
| **Hybrid** (thực tế) | Push cho user thường; **pull cho celebrity** | Cân bằng | Phức tạp |

```
Hybrid: user thường → fan-out on write vào Redis timeline (list per user)
        celebrity   → KHÔNG fan-out; lúc đọc, merge timeline cache + bài celebrity (pull)
```

### Design & Data Model
```
Post service → message queue (Kafka) → fan-out workers → Redis timeline (user_id → list post_id)
Read: GET /feed → Redis timeline (post_ids) → hydrate post content từ cache/DB
Bảng: posts(post_id, user_id, content, created_at); follows(follower_id, followee_id)
```
- Timeline lưu **post_id** (không lưu cả nội dung) → hydrate khi đọc → tiết kiệm RAM, tránh trùng lặp.
- Fan-out async qua Kafka (xem [../../kafka/patterns/event_driven_architecture.md](../../kafka/patterns/event_driven_architecture.md)) → post trả về ngay, fan-out nền.

### Deep Dive & Trade-offs
- **Celebrity problem**: push tới 50M follower/post là bất khả thi → hybrid (pull cho celebrity).
- Ranking (không chỉ thời gian): ML score → fan-out lưu post_id, ranking lúc đọc.
- Eventual consistency ok (feed trễ vài giây chấp nhận được). Liên hệ [../fundamentals/caching.md](../fundamentals/caching.md).

---

# 2. Design a Chat System (WhatsApp / Messenger)

### Requirements
- **Functional**: 1:1 & group chat, delivery + read receipts, online/last-seen, push notification, lịch sử, multi-device sync.
- **Non-functional**: low-latency real-time, ordered messages, HA, offline delivery (giao khi online lại).

### How – Connection & Routing
```
Client ⇄ WebSocket ⇄ Chat Connection Server (stateful, giữ kết nối)
                          │ (user→server mapping trong Redis)
        Message → Chat Service → lưu DB → định tuyến tới connection server của người nhận → push
        Người nhận offline → lưu + Push Notification Service (APNs/FCM)
```
- **WebSocket** cho 2 chiều real-time (xem [../fundamentals/networking_protocols.md](../fundamentals/networking_protocols.md)). Connection server **stateful** → cần service discovery (user nào đang ở connection server nào, lưu Redis).
- Stateless không hợp (cần giữ kết nối) → dùng pub/sub backplane (Redis/Kafka) route message giữa các connection server.

### Data Model & Ordering
```
messages: (chat_id, message_id, sender_id, content, created_at, seq)   ← partition theo chat_id
- message_id = Snowflake (sortable theo thời gian, xem foundational_designs.md)
- Thứ tự trong 1 chat: theo seq/timestamp; chọn DB ghi nhanh (Cassandra/HBase – write-heavy)
```
- **Delivery semantics**: at-least-once + dedup theo message_id (idempotent client).
- **Multi-device sync**: mỗi device có "last synced seq" → kéo message thiếu khi reconnect.

### Deep Dive & Trade-offs
- **Presence/online status**: heartbeat qua WebSocket; lưu Redis với TTL; broadcast tới bạn bè (eventual, đừng over-engineer — chấp nhận trễ vài giây).
- **Group chat**: small group → fan-out tới từng member's connection; large group → pull/shared.
- Storage write-heavy → Cassandra/HBase (LSM, ghi nhanh) thay RDBMS. Liên hệ [../fundamentals/databases_design.md](../fundamentals/databases_design.md).

---

# 3. Design a Proximity / Geo Service (Yelp nearby, Uber drivers)

### Requirements
- **Functional**: tìm đối tượng trong bán kính R quanh điểm (nhà hàng gần đây; tài xế gần khách).
- **Non-functional**: low-latency query, cập nhật vị trí real-time (Uber: tài xế di chuyển liên tục).
- Phân biệt: **static** (nhà hàng – ít đổi) vs **dynamic** (tài xế – vị trí đổi mỗi vài giây).

### How – Geospatial Indexing
| Kỹ thuật | Cơ chế | Ghi chú |
|----------|--------|---------|
| **Geohash** | Mã hóa lat/lng → string; prefix chung = gần nhau | Đơn giản, query theo prefix; biên có thể sai |
| **Quadtree** | Chia không gian thành 4 ô đệ quy tới khi đủ thưa | Tốt cho mật độ không đều |
| **Google S2** | Hilbert curve → cell id | Dùng thực tế nhiều |
| **Redis GEO** | GEOADD/GEOSEARCH (geohash bên trong) | Nhanh cho dynamic, in-memory |

```
Geohash: lat/lng → "9q8yy" (5 ký tự ≈ 5km × 5km); query: tìm geohash của điểm
         + 8 ô lân cận (neighbor) → lấy đối tượng có cùng prefix → lọc theo bán kính thật
```

### Design – Static vs Dynamic
```
Static (nhà hàng): geohash index trong DB (hoặc Elasticsearch geo_point — xem elasticsearch/),
                   query bán kính → cache kết quả phổ biến.
Dynamic (tài xế):  vị trí đổi liên tục → Redis GEO (in-memory, ghi nhanh);
                   tài xế gửi vị trí mỗi 3-5s → cập nhật Redis; khách query GEOSEARCH bán kính.
```

### Deep Dive & Trade-offs
- **Geohash precision vs recall**: precision cao (ô nhỏ) → ít đối tượng/ô nhưng nhiều ô để quét; thấp → ngược lại. Query phải gồm **ô lân cận** (đối tượng gần biên).
- **Hot spot** (downtown đông): ô dày → quadtree/S2 thích nghi tốt hơn geohash đều.
- **Dynamic update tải cao**: triệu tài xế × cập nhật/3s → Redis GEO (in-memory) + shard theo vùng địa lý.
- Static → Elasticsearch geo query (xem package `elasticsearch/`); dynamic → Redis GEO ([../../redis/redis_patterns.md](../../redis/redis_patterns.md)).

---

## Ghi chú
**Sub-topic liên quan:**
- [foundational_designs.md](foundational_designs.md) – URL shortener, Snowflake, rate limiter
- [../fundamentals/networking_protocols.md](../fundamentals/networking_protocols.md) – WebSocket/SSE (chat real-time)
- [../advanced/event_driven_architecture.md](../advanced/event_driven_architecture.md) + [../../kafka/patterns/event_driven_architecture.md](../../kafka/patterns/event_driven_architecture.md) – fan-out async
- [../fundamentals/databases_design.md](../fundamentals/databases_design.md) – chọn store (Cassandra write-heavy, Redis GEO)
- **Keywords:** fan-out on write/read, hybrid feed, celebrity problem, write amplification, timeline cache (post_id hydrate), WebSocket connection server, pub/sub backplane, presence heartbeat, message ordering, geohash, quadtree, Google S2, Redis GEO/GEOSEARCH, neighbor cells.

*Cập nhật lần cuối: 2026-06-11*
