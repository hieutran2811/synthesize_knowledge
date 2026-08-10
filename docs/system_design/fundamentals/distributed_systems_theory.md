---
title: "Distributed Systems Theory – Nền tảng lý thuyết"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Distributed Systems Theory – Nền tảng lý thuyết

> Tra cứu nhanh: [System Design Glossary](../glossary.md). Nên đọc trước: [Availability & Reliability](availability_reliability.md) (CAP/PACELC), [Databases Design](databases_design.md). Đọc tiếp: [Networking & Protocols](networking_protocols.md).

---

## 1. Vì sao hệ phân tán khó

Hệ phân tán là nhiều node giao tiếp qua mạng **không tin cậy**, không có đồng hồ chung, và có thể chết bất kỳ lúc nào. Mọi khó khăn quy về một điều: **bạn không thể phân biệt "node kia chết" với "mạng tới node kia bị đứt" hay "node kia đang chậm"**.

### 1.1 Tám ngộ nhận (Fallacies of Distributed Computing)

| Ngộ nhận | Thực tế |
|---|---|
| Mạng đáng tin cậy | Gói tin mất, trễ, lặp, đảo thứ tự |
| Độ trễ bằng 0 | RTT cùng DC ~0,5ms; cross-region 30–200ms |
| Băng thông vô hạn | Có giới hạn, và egress tốn tiền |
| Mạng an toàn | Cần mã hóa và xác thực ở mọi hop |
| Topology không đổi | Node lên/xuống, IP đổi, scale liên tục |
| Có một người quản trị | Nhiều team, nhiều hệ thống, nhiều chính sách |
| Chi phí vận chuyển bằng 0 | Serialize/deserialize tốn CPU đáng kể |
| Mạng đồng nhất | Nhiều loại link, MTU, chất lượng khác nhau |

### 1.2 Hai điều bất khả thi cần biết

**FLP impossibility**: trong hệ hoàn toàn bất đồng bộ, không thể có thuật toán consensus vừa đảm bảo an toàn (safety) vừa đảm bảo hoàn thành (liveness) nếu **dù chỉ một node** có thể chết.

Điều này không có nghĩa consensus bất khả thi trong thực tế. Nó có nghĩa mọi hệ thống thật đều dùng **timeout** — tức là giả định "partial synchrony": mạng thường hoạt động, và khi nghi ngờ thì dùng đồng hồ để quyết định. Đó là lý do mọi cấu hình Raft/ZAB đều có `election timeout`, và tại sao đặt timeout quá ngắn gây bầu leader liên tục.

**Two Generals / không thể biết chắc**: không có số lượng message hữu hạn nào đảm bảo hai bên biết chắc bên kia đã nhận. Hệ quả trực tiếp và rất thực tế: **exactly-once delivery không tồn tại ở tầng vận chuyển**. Chỉ có at-most-once và at-least-once; "exactly-once processing" đạt được bằng at-least-once + **idempotency** ở phía nhận.

---

## 2. Consistency model – phổ từ mạnh đến yếu

```text
Linearizable → Sequential → Causal → Eventual
(như một bản sao duy nhất)            (cuối cùng hội tụ)
     ← chi phí phối hợp cao                thấp →
```

| Model | Đảm bảo | Chi phí | Ví dụ |
|---|---|---|---|
| **Linearizable** | Mọi thao tác như xảy ra tức thời tại một điểm, theo thứ tự thời gian thật | Cao — cần consensus hoặc quorum đọc+ghi | etcd, ZooKeeper, Spanner |
| **Sequential** | Mọi node thấy cùng một thứ tự, không cần khớp thời gian thật | Cao | – |
| **Causal** | Giữ quan hệ nhân quả: nếu A gây ra B thì ai cũng thấy A trước B | Trung bình | COPS, một số hệ collaborative |
| **Eventual** | Ngừng ghi thì cuối cùng mọi replica giống nhau | Thấp | DynamoDB, Cassandra (mức thấp) |

Điểm dễ nhầm: **"strong consistency" trong tài liệu sản phẩm thường không phải linearizability**. Nhiều hệ gọi "strongly consistent read" cho nghĩa "đọc từ leader" — mạnh hơn eventual nhưng không phải linearizable trong mọi tình huống partition.

### 2.1 Client-centric guarantee – phần thực dụng nhất

Eventual consistency thuần khiến UX rất tệ ("tôi vừa đổi tên, tải lại thấy tên cũ"). Bốn đảm bảo yếu nhưng đủ dùng, và là những gì cần cho ứng dụng thật:

| Đảm bảo | Nghĩa | Cách đạt |
|---|---|---|
| **Read-your-writes** | Đọc thấy ghi của chính mình | Đọc từ leader trong N giây sau ghi ([databases_design.md](databases_design.md) mục 3.3) |
| **Monotonic reads** | Không thấy dữ liệu lùi về quá khứ | Ghim một client vào một replica |
| **Monotonic writes** | Ghi của cùng client giữ thứ tự | Ghi qua cùng một đường/partition |
| **Writes-follow-reads** | Ghi dựa trên một lần đọc sẽ xuất hiện sau lần đọc đó | Mang theo version đã đọc khi ghi |

Đây là nơi lý thuyết gặp thực tế: rất ít hệ thống cần linearizability toàn cục; phần lớn cần **eventual + bốn đảm bảo trên cho các đường đi người dùng nhìn thấy**.

---

## 3. Consensus

**Bài toán**: nhiều node phải thống nhất **một** giá trị, dù có node chết. Đây là nền tảng của: bầu leader, replicated log, distributed lock, config store, metadata của cluster.

### 3.1 Raft

```text
Vai trò: Leader / Follower / Candidate

1. Bầu leader: follower hết election timeout → tăng term → thành candidate → xin vote
               nhận được ĐA SỐ vote → thành leader
2. Replicate log: client → leader → append vào log → gửi tới follower
                  → commit khi ĐA SỐ đã ghi bền → áp dụng vào state machine → trả client
3. An toàn: log matching property; chỉ candidate có log đủ mới được bầu
```

Ba con số quyết định hành vi Raft trong thực tế:

| Tham số | Ảnh hưởng |
|---|---|
| **Số node (luôn lẻ)** | 3 node chịu 1 lỗi; 5 node chịu 2 lỗi. Số chẵn không tăng khả năng chịu lỗi mà chỉ tăng chi phí |
| **Election timeout** | Quá ngắn → bầu lại liên tục khi mạng chập chờn; quá dài → RTO cao |
| **Heartbeat interval** | Thường bằng 1/10 election timeout |

Điểm rất quan trọng về throughput: **mọi ghi đều đi qua leader và cần round-trip tới đa số**. Vì vậy consensus phù hợp cho **metadata và coordination** (config, membership, lock), không phù hợp làm đường đi dữ liệu nóng với hàng trăm nghìn QPS. Đây là lý do kiến trúc phổ biến là "consensus cho metadata + quorum/leaderless cho dữ liệu".

### 3.2 Paxos, ZAB, và biến thể

| | Raft | Multi-Paxos | ZAB |
|---|---|---|---|
| Dễ hiểu/triển khai | Cao | Thấp | Trung bình |
| Leader | Mạnh, bắt buộc | Không bắt buộc | Bắt buộc |
| Dùng ở | etcd, Consul, **Kafka KRaft**, CockroachDB, TiKV | Chubby, Spanner | ZooKeeper |

Với hệ thống mới, Raft là mặc định — không vì nó mạnh hơn mà vì **dễ triển khai đúng hơn**, và trong hệ phân tán "triển khai đúng" quan trọng hơn tối ưu lý thuyết.

### 3.3 Quorum trong consensus

```text
Cần đa số (N/2 + 1) node sống để tiến hành:
  3 node → cần 2 → chịu được mất 1
  5 node → cần 3 → chịu được mất 2

Cluster 4 node bị chia 2–2 → KHÔNG nửa nào có đa số → cả hai dừng ghi
  → đây là hành vi ĐÚNG (chống split-brain), nhưng nghĩa là mất availability
```

Với triển khai đa vùng, đặt node theo số lẻ vùng: 3 node ở 3 AZ chịu được mất một AZ. 4 node ở 2 AZ **không** chịu được mất một AZ (mất 2/4 → không còn đa số). Đây là lỗi thiết kế hạ tầng rất phổ biến.

---

## 4. Quorum kiểu Dynamo – tunable consistency

Thay vì consensus chặt cho mọi ghi, hệ leaderless dùng quorum có thể điều chỉnh:

```text
N = số replica,  W = số ack cần khi ghi,  R = số replica đọc

R + W > N  → vùng đọc và vùng ghi giao nhau → đọc thấy được ghi mới nhất

N=3:  W=2, R=2 → R+W=4 > 3  ✓ cân bằng (mặc định QUORUM của Cassandra)
      W=1, R=1 → 2 ≤ 3      ✗ nhanh nhất, eventual
      W=3, R=1 → 4 > 3      ✓ đọc nhanh, ghi chậm (read-heavy)
      W=1, R=3 → 4 > 3      ✓ ghi nhanh, đọc chậm (write-heavy)
```

Cần cẩn thận: `R + W > N` **không** cho linearizability. Nó chỉ đảm bảo vùng giao nhau; vẫn có thể đọc dữ liệu cũ trong các tình huống như ghi thất bại một phần, sloppy quorum, hoặc đọc song song với ghi.

| Kỹ thuật đi kèm | Mục đích |
|---|---|
| **Sloppy quorum + hinted handoff** | Replica đích chết → ghi tạm vào node khác, trao lại khi hồi phục. Tăng availability, giảm đảm bảo |
| **Read repair** | Khi đọc phát hiện replica lệch → cập nhật ngay |
| **Anti-entropy (Merkle tree)** | Đối chiếu định kỳ giữa các replica để hội tụ |

---

## 5. Xung đột ghi và cách hòa giải

Khi hai node cùng ghi một khóa mà không thấy nhau, phải có cách quyết định.

| Cách | Cơ chế | Vấn đề |
|---|---|---|
| **LWW (Last Write Wins)** | Giữ bản có timestamp lớn hơn | **Mất dữ liệu âm thầm**; phụ thuộc đồng hồ (clock skew) |
| **Version vector** | Phát hiện được "đồng thời" → trả cả hai bản cho ứng dụng | Ứng dụng phải biết merge; kích thước tăng theo số node |
| **CRDT** | Cấu trúc tự hội tụ khi merge | Semantics merge cố định, không tùy biến |
| **Tránh xung đột bằng thiết kế** | Mỗi khóa chỉ có một writer (phân vùng theo khóa) | **Tốt nhất khi khả thi** |

Hàng cuối là lời khuyên quan trọng nhất của mục này: **cách xử lý xung đột tốt nhất là thiết kế để không có xung đột**. Nếu mỗi tenant/user "thuộc" một region hoặc một partition, bài toán biến mất. Multi-leader ghi cùng khóa từ nhiều nơi nên là lựa chọn cuối, không phải mặc định.

### 5.1 CRDT

Cấu trúc dữ liệu tự hội tụ bất kể thứ tự merge (strong eventual consistency):

| CRDT | Hỗ trợ | Ghi chú |
|---|---|---|
| **G-Counter** | Chỉ tăng | Mỗi node giữ counter riêng, merge = tổng |
| **PN-Counter** | Tăng và giảm | Hai G-Counter (P và N) |
| **G-Set / 2P-Set** | Thêm (và xóa một lần) | 2P-Set không cho thêm lại sau khi xóa |
| **OR-Set** | Thêm/xóa lặp lại | Dùng tag duy nhất cho mỗi lần thêm |
| **LWW-Register** | Ghi giá trị đơn | Vẫn là LWW, vẫn có thể mất |
| **RGA / Yjs / Automerge** | Text collaborative | Nền của Google Docs-like |

Đánh đổi của CRDT: nó **đảm bảo hội tụ nhưng không đảm bảo hội tụ về kết quả nghiệp vụ đúng**. Một PN-Counter cho phép số dư âm; nếu nghiệp vụ cấm âm, CRDT không giúp được — cần coordination.

---

## 6. Thời gian, thứ tự và đồng hồ

Đồng hồ vật lý các node lệch nhau (clock skew), và NTP có thể **nhảy lùi**. Vì vậy **không dùng wall-clock để sắp thứ tự sự kiện phân tán**.

| Cơ chế | Cho biết | Hạn chế |
|---|---|---|
| **Lamport clock** | Thứ tự tổng (total order) qua counter | Không phân biệt được "đồng thời" với "có nhân quả" |
| **Vector clock** | Quan hệ nhân quả **và** phát hiện đồng thời | Kích thước O(số node) |
| **Hybrid Logical Clock (HLC)** | Gần thời gian thật + đảm bảo nhân quả | Cần đồng hồ tương đối đồng bộ |
| **TrueTime (Google)** | Khoảng thời gian có cận sai số (GPS + atomic clock) | Cần hạ tầng đặc biệt |

```text
happens-before (→): nếu A → B thì A có thể đã ảnh hưởng B

Vector clock:
  A=[2,1,0], B=[2,2,0] → mọi thành phần của A ≤ B → A → B
  A=[2,1,0], C=[1,0,3] → không so sánh được → ĐỒNG THỜI → có xung đột thật
```

Hai hệ quả thực tế:

1. **Đừng dùng `NOW()` của các node khác nhau để quyết định thứ tự.** Đây là gốc của bug LWW mất dữ liệu và của bug Snowflake ID trùng khi NTP lùi giờ.
2. **Spanner đạt được strong consistency toàn cầu bằng cách trả tiền cho đồng hồ chính xác** — nó chờ hết khoảng bất định trước khi commit. Đây là ví dụ đẹp về việc đổi latency lấy consistency một cách tường minh.

---

## 7. Distributed lock – khó hơn nhiều so với cảm giác

```text
Yêu cầu: SAFETY (không bao giờ hai client cùng giữ lock)
         + LIVENESS (lock cuối cùng phải được nhả, kể cả khi client chết)

TTL giải quyết liveness → nhưng phá safety:
  client A lấy lock TTL 30s → GC pause 40s → TTL hết → client B lấy lock
  → A tỉnh lại, TƯỞNG vẫn giữ lock → hai client cùng ghi
```

Đây là phê bình nổi tiếng của Martin Kleppmann với Redlock, và nó áp dụng cho **mọi** lock dựa trên TTL — kể cả ZooKeeper/etcd. TTL không thể vừa đảm bảo safety vừa đảm bảo liveness khi process có thể bị treo tùy ý.

### 7.1 Fencing token – điều kiện để lock thực sự đúng

```text
Mỗi lần cấp lock, tăng một số đơn điệu (fencing token) và trả cho client.
Client gửi token kèm mọi thao tác lên resource.
RESOURCE từ chối token nhỏ hơn token lớn nhất đã thấy.

A nhận token 33 → treo
B nhận token 34 → ghi với token 34 → resource ghi nhận max=34
A tỉnh, ghi với token 33 → resource TỪ CHỐI  ✓
```

Kết luận cần nhớ: **lock phân tán chỉ đúng khi resource được bảo vệ tự kiểm tra fencing token**. Nếu resource (database, file, API) không hỗ trợ điều đó, lock chỉ là tối ưu hiệu năng (giảm tranh chấp), **không phải** bảo đảm đúng đắn.

### 7.2 Các lựa chọn thay thế, tốt hơn khi khả thi

```text
1. Single-writer bằng phân vùng: mỗi khóa chỉ do một consumer/partition xử lý
   (Kafka partition, sharding) → không cần lock
2. Optimistic concurrency: version/compare-and-swap → phát hiện xung đột thay vì ngăn trước
3. Idempotency: làm thao tác an toàn khi lặp → lock trở nên không cần thiết
4. Điều kiện trong chính câu ghi: UPDATE ... WHERE stock >= @qty
```

Thứ tự này nên là thứ tự cân nhắc: chỉ dùng distributed lock khi cả bốn cách trên không áp dụng được.

### 7.3 So sánh triển khai

| | Redis (Redlock) | ZooKeeper / etcd |
|---|---|---|
| Cơ chế | SET NX PX trên đa số instance | Ephemeral node / lease + watch |
| Safety khi GC pause | Yếu (cần fencing token) | Tốt hơn (session-based) nhưng vẫn cần fencing |
| Độ trễ | Rất thấp | Cao hơn (consensus) |
| Phát hiện client chết | Chỉ qua TTL | Qua session/heartbeat, nhanh hơn |
| Phù hợp | Giảm tranh chấp, không phải bảo đảm | Coordination cần đúng đắn |

---

## 8. Leader election, membership, failure detection

### 8.1 Leader election

| Cách | Cơ chế |
|---|---|
| Consensus-based (Raft/ZAB) | Đúng đắn nhất; leader có log đầy đủ nhất |
| ZooKeeper ephemeral sequential | Node có số nhỏ nhất là leader; node chết → node tiếp theo lên |
| etcd lease + campaign | Giữ lease, gia hạn; mất lease thì mất leader |
| Bully algorithm | Node id lớn nhất thắng; đơn giản nhưng dễ dao động |

Điều cần biết dù dùng cách nào: **có thể có hai node cùng tin mình là leader trong một khoảng ngắn** (leader cũ chưa biết mình mất quyền). Vì vậy mọi hành động của leader lên resource dùng chung cũng cần fencing token — cùng lý do ở mục 7.1.

### 8.2 Failure detection

```text
Không thể phân biệt: node chết / mạng đứt / node rất chậm
→ mọi failure detector đều là HEURISTIC dựa trên timeout

Timeout ngắn → phát hiện nhanh nhưng nhiều báo động sai (false positive)
Timeout dài  → ít báo động sai nhưng phát hiện chậm
```

**Phi accrual failure detector** (Cassandra dùng) không trả lời có/không mà trả về một mức "độ nghi ngờ" tăng dần, để tầng trên tự quyết định ngưỡng — cách tiếp cận thực dụng hơn so với timeout cứng.

### 8.3 Gossip

Mỗi node định kỳ trao đổi trạng thái với vài node ngẫu nhiên; thông tin lan ra toàn cluster theo kiểu dịch bệnh.

| Đặc điểm | Chi tiết |
|---|---|
| Không có điểm trung tâm | Chịu lỗi tốt, scale tới hàng nghìn node |
| Hội tụ theo O(log N) vòng | Nhanh một cách đáng ngạc nhiên |
| Eventual, không tức thời | Không dùng cho quyết định cần nhất quán ngay |
| Dùng ở | Cassandra, Consul (SWIM), Dynamo, Serf |

---

## 9. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| Linearizability | Suy luận đơn giản như một node | Latency cao mỗi request, mất availability khi partition | Metadata, tồn kho, số dư |
| Eventual + client-centric guarantee | Nhanh, HA | Cần xử lý từng đường đi | Phần lớn hệ thống người dùng |
| Consensus cho dữ liệu nóng | Đúng đắn | Throughput bị chặn bởi leader | Không nên — dùng cho metadata |
| Quorum tunable (R+W>N) | Điều chỉnh theo workload | Không phải linearizable | Data store AP |
| LWW | Đơn giản | Mất dữ liệu âm thầm, phụ thuộc đồng hồ | Khi mất một bản ghi là chấp nhận được |
| Version vector | Không mất dữ liệu | Ứng dụng phải merge | Khi xung đột có ý nghĩa nghiệp vụ |
| CRDT | Ghi đa node không coordination | Semantics cố định, không ràng buộc nghiệp vụ được | Collaborative, counter, presence |
| Thiết kế single-writer | Không có xung đột | Ràng buộc mô hình dữ liệu | **Ưu tiên hàng đầu khi khả thi** |
| Distributed lock | Tuần tự hóa được | Chỉ đúng khi có fencing token | Sau khi loại trừ 4 lựa chọn ở mục 7.2 |
| Gossip | Không SPOF, scale lớn | Eventual | Membership, failure detection |

---

## 10. Áp dụng vào thiết kế

| Nhu cầu | Công cụ |
|---|---|
| Config/metadata nhất quán, bầu leader | etcd, ZooKeeper, Consul (Raft/ZAB) |
| Data store ưu tiên availability, ghi nhiều | Cassandra, DynamoDB (quorum, LSM) |
| SQL phân tán, strong consistency | Spanner, CockroachDB (Raft + HLC/TrueTime) |
| Metadata của message broker | Kafka KRaft (Raft) |
| Collaborative editing | CRDT (Yjs, Automerge) |
| Presence, counter gần đúng | CRDT hoặc gossip |
| Tuần tự hóa xử lý theo khóa | Partition theo khóa (Kafka), không lock |
| Chống xử lý trùng | Idempotency key ở phía nhận |

---

## 11. Ghi chú – chủ đề tiếp theo

- [availability_reliability.md](availability_reliability.md): CAP/PACELC, split-brain, quorum ở góc vận hành.
- [databases_design.md](databases_design.md): replication, sharding, xung đột trong database cụ thể.
- [storage_retrieval.md](storage_retrieval.md): các engine này lưu dữ liệu ra sao.
- [networking_protocols.md](networking_protocols.md): tầng vận chuyển mà mọi thứ ở đây phụ thuộc.
- `advanced/distributed_transactions.md`: 2PC, Saga, idempotency — lý thuyết này áp dụng vào transaction.
- [kafka/architecture.md](../../kafka/fundamentals/architecture.md): KRaft, ISR — Raft trong thực tế.

Từ khóa mở rộng: linearizability vs serializability (khác nhau!), FLP, Two Generals, CALM theorem, sloppy quorum, hinted handoff, read repair, Merkle tree anti-entropy, phi accrual failure detector, SWIM, lease, fencing/STONITH, HLC, TrueTime, external consistency, exactly-once processing.

Một phân biệt hay bị lẫn và đáng ghi nhớ: **serializability** là thuộc tính của transaction (kết quả tương đương một thứ tự tuần tự nào đó); **linearizability** là thuộc tính của từng thao tác trên một đối tượng (khớp thứ tự thời gian thật). Một hệ có thể serializable mà không linearizable, và ngược lại. "Strict serializability" là có cả hai.

---

*Cập nhật lần cuối: 2026-07-30*
