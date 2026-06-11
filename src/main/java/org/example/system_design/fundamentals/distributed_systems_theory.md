# Distributed Systems Theory – Nền tảng lý thuyết

> Bổ trợ cho [availability_reliability.md](availability_reliability.md) (CAP/PACELC) và [databases_design.md](databases_design.md) (replication/sharding). File này đi sâu lý thuyết: consistency models, consensus, quorum, clocks, CRDT, distributed lock.

## What – Vì sao hệ phân tán khó?

Hệ phân tán = nhiều node giao tiếp qua mạng **không tin cậy**, không có đồng hồ chung, có thể chết bất kỳ lúc nào. **8 Fallacies of Distributed Computing** (những giả định SAI):
1. Network reliable · 2. Latency = 0 · 3. Bandwidth vô hạn · 4. Network an toàn · 5. Topology không đổi · 6. Một admin · 7. Transport cost = 0 · 8. Network đồng nhất.

> Mọi thiết kế phải giả định: message mất/trễ/lặp/đảo thứ tự, node chết, network phân mảnh (partition). CAP/PACELC (xem [availability_reliability.md](availability_reliability.md)) là hệ quả.

---

## How – Consistency Models (phổ mạnh → yếu)

```
Strong ─────────────────────────────────────────► Weak
Linearizable → Sequential → Causal → Eventual
(như 1 bản sao)                      (hội tụ cuối cùng)
```

| Model | Đảm bảo | Chi phí | Ví dụ |
|-------|---------|---------|-------|
| **Linearizable** (strong) | Mọi đọc thấy ghi mới nhất, theo real-time | Cao (đồng thuận/quorum) | etcd, ZooKeeper, Spanner |
| **Sequential** | Mọi node thấy cùng thứ tự thao tác (không cần real-time) | Cao | – |
| **Causal** | Giữ quan hệ nhân-quả (A→B thì ai cũng thấy A trước B) | TB | COPS, collaborative apps |
| **Eventual** | Ngừng ghi → cuối cùng hội tụ | Thấp | DynamoDB, Cassandra |

### Client-centric guarantees (tập con thực dụng của eventual)
- **Read-your-writes**: đọc thấy ghi của chính mình (vd: post xong tự thấy).
- **Monotonic reads**: không "lùi về quá khứ" (đọc lần 2 không cũ hơn lần 1).
- **Monotonic writes** / **Writes-follow-reads**.

> Eventual consistency thường được "vá" bằng các guarantee client-centric để UX chấp nhận được (sticky session tới cùng replica, đọc từ leader sau khi ghi).

---

## How – Consensus (đồng thuận)

**Vấn đề**: nhiều node thống nhất **một** giá trị dù có lỗi (crash). Nền tảng của: leader election, replicated log, distributed lock, config store.

- **FLP impossibility**: trong hệ async hoàn toàn, không thể có consensus đảm bảo cả an toàn lẫn liveness nếu **dù chỉ 1 node** có thể chết → thực tế dùng timeout (partial synchrony).

### Raft (dễ hiểu, phổ biến nhất)
```
Roles: Leader / Follower / Candidate
1. Leader election: term tăng, candidate xin vote, đa số (majority) → leader
2. Log replication: client → leader → replicate tới follower → commit khi MAJORITY ack
3. Safety: chỉ commit entry của term hiện tại; log matching property
```
- Cần **đa số (N/2+1)** sống → cụm 3 node chịu 1 lỗi, 5 node chịu 2 lỗi (luôn dùng **số lẻ**).
- Dùng trong: etcd, Consul, **Kafka KRaft** (xem [../../kafka/fundamentals/architecture.md](../../kafka/fundamentals/architecture.md)), CockroachDB, TiKV.

### Paxos & ZAB
- **Paxos**: tổ tiên, mạnh nhưng khó hiểu/triển khai (Multi-Paxos cho log). Google Chubby/Spanner.
- **ZAB**: ZooKeeper Atomic Broadcast (tương tự Raft, atomic broadcast cho ZooKeeper).

| | Raft | Paxos | ZAB |
|--|------|-------|-----|
| Dễ hiểu | ✅ | ❌ | TB |
| Leader | Mạnh (1 leader) | Không bắt buộc | 1 leader |
| Dùng | etcd, KRaft, Consul | Chubby, Spanner | ZooKeeper |

---

## How – Quorum (Dynamo-style tunable consistency)

Thay vì consensus chặt, leaderless replication dùng **quorum**: N replica, đọc cần **R**, ghi cần **W** ack.

```
Strong consistency khi:  R + W > N   (vùng đọc & ghi giao nhau → đọc thấy ghi mới nhất)
Ví dụ N=3:
  W=2, R=2 → R+W=4 > 3  → strong-ish, cân bằng (mặc định Cassandra QUORUM)
  W=1, R=1 → nhanh nhưng eventual (có thể đọc cũ)
  W=3, R=1 → đọc nhanh, ghi chậm (read-heavy)
```
- **Sloppy quorum + hinted handoff**: khi replica đích chết, ghi tạm vào node khác, "trao tay" lại khi hồi phục → tăng availability.
- **Conflict resolution** (ghi đồng thời): Last-Write-Wins (LWW, mất dữ liệu), **version vectors** (phát hiện concurrent → app merge), CRDT.
> DynamoDB/Cassandra/Riak. Liên hệ replication ở [databases_design.md](databases_design.md).

---

## How – Time, Ordering & Clocks

Đồng hồ vật lý các node **lệch nhau** (clock skew) → không dùng wall-clock để sắp thứ tự sự kiện phân tán.

| Cơ chế | Cho biết | Hạn chế |
|--------|----------|---------|
| **Lamport clock** (logical) | Thứ tự tổng (total order) qua counter tăng | Không phát hiện được "đồng thời" |
| **Vector clock** | Quan hệ **nhân-quả** & phát hiện concurrent | Kích thước = O(số node) |
| **Hybrid Logical Clock (HLC)** | Kết hợp physical + logical, gần real-time | – |
| **TrueTime** (Google) | Khoảng thời gian có cận sai số (GPS+atomic) | Cần hạ tầng đặc biệt (Spanner) |

```
happens-before (→): nếu A → B thì A có thể ảnh hưởng B
Vector clock: A=[2,1,0], B=[2,2,0] → A→B (B thấy A);  A=[2,1,0], C=[1,0,3] → concurrent
```

---

## How – CRDTs (Conflict-free Replicated Data Types)

Cấu trúc dữ liệu **tự hội tụ** khi merge bất kể thứ tự → cho phép ghi đa node không cần coordination (strong eventual consistency).
- **G-Counter** (grow-only), **PN-Counter** (tăng/giảm), **OR-Set** (add/remove), **LWW-Register**.
- Dùng: collaborative editing (Google Docs-like), Redis CRDT, Riak, Automerge/Yjs.
> Đánh đổi: merge tự động nghĩa là semantics cố định (không tùy biến conflict resolution như version vector + app logic).

---

## How – Distributed Lock & Leader Election

### Distributed Lock (khó hơn tưởng)
```
Yêu cầu: an toàn (không 2 client cùng giữ lock) + liveness (lock được nhả)
- Redis Redlock: lock trên đa số N Redis instance + TTL
  ⚠️ Martin Kleppmann critique: GC pause/clock skew có thể phá an toàn
       → cần FENCING TOKEN (số tăng dần; resource từ chối token cũ hơn)
- ZooKeeper/etcd: ephemeral node + lease + watch → an toàn hơn (session-based)
```
> Lock phân tán chỉ "đúng" khi resource được bảo vệ **kiểm tra fencing token**. Liên hệ Redis ở [../../redis/redis_patterns.md](../../redis/redis_patterns.md).

### Leader Election
- Raft/ZAB (consensus-based) · ZooKeeper ephemeral sequential node (node nhỏ nhất = leader) · etcd lease · Bully algorithm (đơn giản, theo id lớn nhất).

### Gossip / Membership
- **Gossip protocol** (epidemic): mỗi node định kỳ trao đổi trạng thái với vài node ngẫu nhiên → lan truyền cuối cùng tới toàn cluster. Dùng cho membership/failure detection (Cassandra, Consul **SWIM**, Dynamo).

---

## Trade-offs & Real-world

| Quyết định | Đánh đổi |
|-----------|----------|
| Strong consistency (consensus/quorum) | Chính xác nhưng latency cao, giảm availability khi partition (CP) |
| Eventual consistency | Nhanh, HA (AP) nhưng đọc cũ → cần read-your-writes/conflict resolution |
| Consensus (Raft) cho metadata | Tin cậy nhưng throughput giới hạn → chỉ dùng cho config/coordination, không cho data path nóng |
| CRDT | Ghi đa node không coordination nhưng semantics merge cố định |
| Distributed lock | Tránh nếu được (dùng partition/single-writer); nếu cần → fencing token bắt buộc |

**Thực chiến:** etcd/ZooKeeper (Raft/ZAB) cho coordination/config/leader; Cassandra/Dynamo (quorum) cho data store AP; Spanner/CockroachDB (Raft + TrueTime/HLC) cho strong-consistent distributed SQL; Kafka KRaft (Raft) cho metadata.

---

## Ghi chú
**Sub-topic liên quan:**
- [availability_reliability.md](availability_reliability.md) – CAP/PACELC, SLA/SLO/SLI
- [databases_design.md](databases_design.md) – replication models, sharding, conflict
- [../advanced/distributed_transactions.md](../advanced/distributed_transactions.md) – 2PC, SAGA, idempotency (consensus ứng dụng)
- [../../kafka/fundamentals/architecture.md](../../kafka/fundamentals/architecture.md) – KRaft (Raft), ISR
- **Keywords:** linearizability, FLP, Multi-Paxos, Raft term/log matching, R+W>N, hinted handoff, version vector, Lamport/vector clock, HLC, TrueTime, fencing token, Redlock, SWIM gossip, split-brain, quorum loss.

*Cập nhật lần cuối: 2026-06-11*
