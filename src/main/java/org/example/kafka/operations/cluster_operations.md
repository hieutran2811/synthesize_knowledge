# Cluster Operations Advanced (Day-2 Ops) – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
> Bổ trợ cho [./production.md](production.md) (JVM/OS tuning, monitoring, security, DR). File này tập trung **day-2 ops**: reassignment, scaling, Cruise Control, quotas, rack awareness, rolling upgrade, capacity planning.

---

## What – Day-2 Operations là gì?

Sau khi cluster chạy, vận hành liên tục: **scale** (thêm/bớt broker), **cân bằng** dữ liệu/leader, **giới hạn** client lạm dụng, **nâng cấp** không downtime, **đảm bảo fault tolerance** qua rack/AZ. Đây là phần phân biệt "chạy được" với "vận hành được ở quy mô lớn".

---

## How – Partition Reassignment

### Vì sao cần
Thêm broker → Kafka **KHÔNG tự** chuyển partition cũ sang broker mới (chỉ partition mới mới dùng broker mới). Phải **reassign** thủ công để cân bằng. Cũng cần khi gỡ broker, sửa lệch tải, đổi replication factor.

```bash
# 1) Tạo file topics cần move, sinh kế hoạch đề xuất
kafka-reassign-partitions --bootstrap-server b:9092 \
  --topics-to-move-json-file topics.json --broker-list "1,2,3,4" --generate

# 2) Thực thi kế hoạch + THROTTLE (giới hạn băng thông để không bão hòa cluster)
kafka-reassign-partitions --bootstrap-server b:9092 \
  --reassignment-json-file plan.json --execute --throttle 50000000   # 50 MB/s

# 3) Theo dõi & gỡ throttle khi xong
kafka-reassign-partitions --bootstrap-server b:9092 \
  --reassignment-json-file plan.json --verify
```
> ⚠️ Reassignment copy dữ liệu giữa broker → **luôn throttle** để không nuốt hết network/disk làm chậm traffic production. Theo dõi `UnderReplicatedPartitions` (xem [./production.md](production.md)).

---

## How – Scaling (thêm/bớt broker)

### Thêm broker
1. Khởi động broker mới (cùng cluster id, KRaft controller biết — xem [../fundamentals/architecture.md](../fundamentals/architecture.md)).
2. Reassign một phần partition sang broker mới (có throttle).
3. Trigger preferred leader election để cân bằng leader (xem [../internals/replication.md](../internals/replication.md)).

### Gỡ broker
1. Reassign **toàn bộ** partition của broker đó sang broker khác (drain).
2. Xác nhận không còn replica nào trên broker → shutdown.
> Không drain trước khi tắt → under-replicated/offline partition nếu mất quá min.insync.replicas.

---

## How – Cruise Control (tự động cân bằng)

Công cụ (LinkedIn open-source) **tự động hóa** reassignment/cân bằng — thay vì làm thủ công.

| Khả năng | Mô tả |
|----------|-------|
| Workload balancing | Cân bằng theo **goals**: disk, network in/out, CPU, replica count, leader count, rack |
| Self-healing | Tự phát hiện & sửa broker lỗi, under-replicated, lệch tải |
| Anomaly detection | Cảnh báo broker chết, disk đầy, lệch metric |
| Right-sizing | Đề xuất thêm/bớt broker theo tải |

```
Cruise Control thu metric → mô hình hóa tải → sinh kế hoạch reassignment tối ưu theo goals
→ thực thi (có throttle) → cluster cân bằng mà không cần ops tính tay
```
> Cluster lớn (chục–trăm broker) gần như **bắt buộc** Cruise Control (hoặc tương đương ở Confluent/managed). Cluster nhỏ → reassign thủ công đủ.

---

## How – Client Quotas

Giới hạn tài nguyên client tiêu thụ → chống "noisy neighbor" làm sập cluster.

```bash
# Quota theo byte rate (produce/consume) cho 1 user/client-id
kafka-configs --bootstrap-server b:9092 --alter \
  --add-config 'producer_byte_rate=10485760,consumer_byte_rate=10485760' \
  --entity-type users --entity-name analytics-app

# Request rate quota (% thời gian xử lý trên broker) — chống client gửi quá nhiều request nhỏ
  --add-config 'request_percentage=200'
```
| Quota | Giới hạn | Chống |
|-------|----------|-------|
| `producer_byte_rate` | MB/s ghi | Producer floods |
| `consumer_byte_rate` | MB/s đọc | Consumer hút băng thông |
| `request_percentage` | % CPU broker | Nhiều request nhỏ/metadata storm |

> Broker **throttle** (làm chậm response) client vượt quota thay vì từ chối. Áp theo user (SASL) / client-id / default. Liên hệ security/SASL ở [./production.md](production.md).

---

## How – Rack Awareness

Phân bố replica qua **rack/AZ khác nhau** → mất nguyên 1 rack/AZ vẫn còn replica.

```properties
# Mỗi broker khai rack của nó (= AZ trong cloud)
broker.rack=us-east-1a
```
- Kafka đặt các replica của 1 partition lên **rack khác nhau** → 1 AZ chết không mất partition.
- Kết hợp `replication.factor >= 3` qua 3 AZ + `min.insync.replicas=2` → chịu lỗi 1 AZ. Liên hệ ISR/acks ở [../internals/replication.md](../internals/replication.md).
- **Follower fetching (KIP-392)**: consumer đọc từ replica **cùng rack** → giảm cross-AZ traffic (giảm chi phí cloud). Đã đề cập ở [../internals/replication.md](../internals/replication.md).

---

## How – Rolling Upgrade (không downtime)

Nâng cấp từng broker một, giữ cluster phục vụ liên tục.
```
1. Nâng từng broker (restart) lần lượt; chờ partition re-sync (UnderReplicated=0) rồi mới sang broker kế.
2. (ZooKeeper-era) đặt inter.broker.protocol.version & log.message.format.version = version CŨ,
   nâng cấp hết broker, RỒI mới bump các version đó (2 pha) → cho phép rollback.
3. KRaft: nâng controller quorum + broker; dùng feature flags / metadata version (KIP-778) thay cho 2 cờ trên.
```
> ⚠️ Không restart broker kế tiếp khi còn under-replicated partition → tránh mất quá min.insync.replicas → offline partition. KRaft đơn giản hóa (không cần đồng bộ ZooKeeper). Xem KRaft ở [../fundamentals/architecture.md](../fundamentals/architecture.md).

---

## How – Capacity Planning / Sizing

| Yếu tố | Ước lượng |
|--------|-----------|
| **Storage/broker** | `throughput_MBps × retention_seconds × replication_factor / #brokers` + headroom (đầy ≤ 60-70%) |
| **Partition count** | theo throughput & song song consumer; tránh quá nhiều (overhead controller/rebalance) |
| **Broker count** | đủ throughput + chịu mất N broker (RF≥3) + headroom reassignment |
| **RAM** | phần lớn cho **OS page cache** (Kafka đọc/ghi qua page cache); JVM heap nhỏ (~6GB) là đủ |
| **Disk** | nhiều disk (JBOD) hoặc RAID; throughput sequential quan trọng hơn IOPS |
| **Network** | thường là **bottleneck** (replication nhân RF lần traffic) |

> Page cache là chìa khóa hiệu năng Kafka (zero-copy sendfile) → đừng cấp hết RAM cho JVM heap. Liên hệ storage/zero-copy ở [../internals/storage.md](../internals/storage.md), JVM tuning ở [./production.md](production.md).

---

## Compare – Multi-Cluster: MirrorMaker2 vs Cluster Linking vs Stretch

| | MirrorMaker 2 | Cluster Linking (Confluent) | Stretch Cluster |
|--|----------------|------------------------------|-----------------|
| Cơ chế | Connect-based, consume→produce sang cluster khác | Broker tự fetch trực tiếp (byte-for-byte) | 1 cluster trải nhiều AZ/region |
| Offset | Cần dịch offset (offset sync) | **Giữ nguyên offset** | Cùng cluster, không cần |
| Độ trễ | Cao hơn (qua Connect) | Thấp hơn | Thấp (nhưng nhạy latency liên vùng) |
| Dùng | DR, migrate, aggregate (OSS) | DR/geo (Confluent) | HA đồng bộ trong vùng latency thấp |
| Active-active | Phức tạp (dedup, vòng lặp) | Hỗ trợ tốt hơn | Tự nhiên nhưng rủi ro latency |

```
Active-Passive (DR): cluster chính → MM2/Linking → cluster DR (chờ failover)
Active-Active:       2 cluster cùng nhận write → cần tránh vòng lặp + dedup (phức tạp)
```
> DR setup chi tiết MM2: [./production.md](production.md) & [../streams/connect.md](../streams/connect.md). Stretch cluster cần inter-AZ latency thấp (cùng region) — không hợp cross-region.

---

## Trade-offs

- (+) Reassignment/Cruise Control: cân bằng & scale linh hoạt; quotas chống noisy neighbor; rack awareness chịu lỗi AZ; rolling upgrade không downtime.
- (−) Reassignment tốn network/disk → phải throttle, có thể kéo dài hàng giờ với cluster lớn.
- (−) Cruise Control là thành phần thêm phải vận hành; tự động sai goal → cân bằng không như ý.
- (−) Multi-cluster active-active phức tạp (dedup, conflict, offset); thường active-passive đơn giản & đủ.
- (−) Quá nhiều partition / sai capacity plan → rebalance chậm, recovery lâu, controller tải nặng.

---

## Real-world Runbook

```
Thêm dung lượng (disk sắp đầy):
  1. Thêm broker → 2. Cruise Control rebalance (hoặc reassign thủ công có throttle)
  3. Verify UnderReplicated=0 → 4. preferred leader election cân bằng leader

Broker chết:
  - RF≥3 + min.insync.replicas=2 → vẫn phục vụ; thay broker → reassign/self-heal
  - Theo dõi UnderReplicatedPartitions, OfflinePartitionsCount (xem production.md)

Nâng cấp version:
  - Rolling restart từng broker, chờ re-sync; KRaft: bump metadata version sau cùng
```

---

## Ghi chú – Chủ đề tiếp theo
> Đã hoàn thành cụm bổ sung Kafka (Schema Registry, ksqlDB, EDA, Cluster Ops). Xem lại nền tảng nếu cần: [../fundamentals/architecture.md](../fundamentals/architecture.md) (KRaft), [../internals/replication.md](../internals/replication.md) (ISR/leader), [./production.md](production.md) (tuning/monitoring/security/DR).

> Liên quan: [./production.md](production.md), [../internals/replication.md](../internals/replication.md), [../streams/connect.md](../streams/connect.md) (MM2), [../patterns/event_driven_architecture.md](../patterns/event_driven_architecture.md) (partition count theo design).

> Keywords: `kafka-reassign-partitions`, throttle (`leader.replication.throttled.rate`), Cruise Control goals/self-healing, `kafka-configs` quotas, `broker.rack`, `replica.selector.class` (rack-aware fetching), `inter.broker.protocol.version`, metadata version (KIP-778), JBOD, preferred leader (`auto.leader.rebalance.enable`), partition limit per broker, `kafka-leader-election`.

---

*Cập nhật lần cuối: 2026-06-04*
