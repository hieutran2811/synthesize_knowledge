---
title: "Storage & Retrieval – Bên trong storage engine, encoding & schema evolution"
topic: system_design
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Storage & Retrieval – Bên trong storage engine, encoding & schema evolution

> Chủ đề bổ sung 2026-07. Giải thích **vì sao** các database có đặc tính hiệu năng khác nhau — nền tảng cho mọi lựa chọn ở [databases_design.md](databases_design.md).
>
> Tra cứu nhanh: [System Design Glossary](../glossary.md). Nên đọc trước: [Databases Design](databases_design.md). Đọc tiếp: [Distributed Systems Theory](distributed_systems_theory.md).

---

## 1. Vì sao cần biết tầng này

Một câu hỏi phỏng vấn và cũng là câu hỏi thiết kế thật: *tại sao Cassandra ghi nhanh hơn PostgreSQL, còn PostgreSQL truy vấn linh hoạt hơn?* Không thể trả lời từ tài liệu tính năng — phải hiểu **cấu trúc dữ liệu bên trong**.

Ba đặc tính vật lý chi phối toàn bộ tầng này:

```text
1. Đọc/ghi tuần tự nhanh hơn random rất nhiều
   HDD: ~100× · SSD/NVMe: ~2–10× (vẫn đáng kể vì write amplification và erase block)

2. Ghi vào RAM nhanh hơn disk ~1000×
   → mọi engine đều đệm ghi trong RAM và làm bền bằng log tuần tự

3. Đơn vị I/O là page/block (4–16KB), không phải byte
   → row hẹp hơn = nhiều row mỗi page = ít I/O hơn cho cùng số row
```

Mọi thiết kế storage engine là một cách khác nhau để **đổi random I/O thành sequential I/O**. Hiểu điều đó là hiểu 80% chủ đề này.

---

## 2. Write-Ahead Log – nền tảng của durability

```text
Ghi một bản ghi:
1. Ghi log record vào WAL (TUẦN TỰ, append-only) → fsync → mới trả OK cho client
2. Sửa page trong buffer pool (RAM) → page thành "dirty"
3. Sau đó (checkpoint/flush) mới ghi page xuống data file (RANDOM)

Crash → đọc lại WAL từ checkpoint gần nhất → redo/undo → về trạng thái nhất quán
```

Điểm cần nắm và hay bị hiểu sai: **dữ liệu bền vì log đã xuống disk, không phải vì data file đã cập nhật**. Data file có thể lạc hậu vài phút so với thực tế đã commit.

Hệ quả thực tế của thiết kế này:

| Hệ quả | Ý nghĩa vận hành |
|---|---|
| Độ trễ ghi bị chặn bởi **fsync của volume log** | Log phải nằm trên storage có latency ghi thấp nhất |
| Ghi random được biến thành ghi tuần tự | Đó là lý do database chịu được throughput ghi cao |
| Group commit gom nhiều transaction vào một fsync | Nhiều commit nhỏ tệ hơn ít commit lớn |
| WAL là nguồn cho replication, CDC, PITR | Xem [sqlserver/data_movement.md](../../sqlserver/integration/data_movement.md) |

Đánh đổi durability mà mọi database đều cho phép cấu hình:

```text
fsync mỗi commit         → RPO = 0, ghi chậm hơn
fsync theo nhóm/định kỳ  → nhanh hơn nhiều, có thể mất vài ms–giây cuối
không fsync (OS buffer)  → nhanh nhất, mất dữ liệu khi mất điện
```

PostgreSQL: `synchronous_commit`. MySQL: `innodb_flush_log_at_trx_commit`. Đây là **quyết định nghiệp vụ** (được phép mất bao nhiêu?), không phải quyết định kỹ thuật thuần.

---

## 3. B-tree – tối ưu cho đọc

```text
         [ 50 | 100 ]              ← internal node: chỉ khóa và con trỏ
        /     |      \
  [10|30]  [60|80]  [120|150]
   / | \    / | \     / | \
 leaf pages ...                     ← leaf: dữ liệu (hoặc con trỏ tới dữ liệu), liên kết đôi

Tra cứu: O(log_B N) — với fanout ~100–500, cây 3–4 tầng đủ cho hàng tỉ bản ghi
```

| Đặc tính | Chi tiết |
|---|---|
| **Cập nhật tại chỗ** | Sửa trực tiếp page chứa bản ghi → random write |
| **Đọc dải rất tốt** | Leaf được liên kết → scan tuần tự theo thứ tự khóa |
| **Độ trễ đọc dự đoán được** | Luôn 3–4 lần đọc page, không phụ thuộc lịch sử ghi |
| **Page split khi chèn vào page đầy** | Gây fragmentation và ghi thêm |
| **Write amplification** | Sửa 1 byte → ghi cả page (8–16KB) + log |

### 3.1 Page split và vì sao khóa tăng dần quan trọng

```text
Khóa TĂNG DẦN (auto-increment, timestamp):
  luôn chèn vào page cuối → page đầy → tạo page mới → không split ở giữa
  → cây gọn, ít fragmentation
  ⚠ nhưng: mọi thread cùng ghi vào page cuối → tranh chấp latch ("hot last page")

Khóa RANDOM (UUID v4):
  chèn rải rác khắp cây → page đầy ở giữa → SPLIT → nửa dữ liệu chuyển sang page mới
  → fragmentation cao, page chỉ đầy ~70%, cần nhiều page hơn cho cùng dữ liệu
  → log nhiều hơn, cache kém hiệu quả hơn
```

Đây là lý do kỹ thuật cho lời khuyên "đừng dùng UUID v4 làm clustered/primary key", và lý do UUID v7 (time-ordered) tồn tại. Xem thêm [foundational_designs.md](../case_studies/foundational_designs.md) mục 2.

---

## 4. LSM-tree – tối ưu cho ghi

```text
Ghi:
  → memtable (cấu trúc sắp xếp trong RAM) + append vào WAL
  → memtable đầy → flush thành SSTable BẤT BIẾN trên disk (ghi TUẦN TỰ)
  → nhiều SSTable tích tụ → compaction gộp lại, loại bỏ bản cũ và tombstone

Đọc:
  → memtable → SSTable mới nhất → ... → SSTable cũ nhất
  → mỗi SSTable có bloom filter để bỏ qua nhanh nếu chắc chắn không chứa khóa
```

| Đặc tính | Chi tiết |
|---|---|
| **Ghi luôn tuần tự** | Không random write, không page split → throughput ghi rất cao |
| **Nén tốt hơn B-tree** | SSTable bất biến, được đóng gói chặt (không cần chỗ trống cho update) |
| **Đọc có thể phải xem nhiều SSTable** | Bloom filter giảm nhiều nhưng không loại bỏ hẳn |
| **Compaction tiêu tốn I/O ở background** | Có thể gây tăng p99 không đoán được |
| **Xóa là ghi tombstone** | Dữ liệu chỉ mất thật sau compaction |

### 4.1 Ba loại amplification – ngôn ngữ để so sánh

```text
Write amplification : mỗi byte logic ghi → bao nhiêu byte thật xuống disk
Read amplification  : mỗi lần đọc logic → bao nhiêu lần đọc thật
Space amplification : dữ liệu logic → chiếm bao nhiêu dung lượng thật
```

Không thể tối ưu cả ba; mỗi chiến lược compaction chọn một điểm cân bằng:

| Chiến lược compaction | Write amp | Read amp | Space amp | Dùng ở |
|---|---|---|---|---|
| **Size-tiered (STCS)** | Thấp | Cao | Cao (~2×) | Cassandra mặc định, workload ghi nhiều |
| **Leveled (LCS)** | Cao | Thấp | Thấp | RocksDB, khi đọc quan trọng |
| **Time-window (TWCS)** | Thấp | Thấp cho dải thời gian | Thấp | Time-series, dữ liệu có TTL |

TWCS đáng chú ý cho hệ time-series/log: mỗi cửa sổ thời gian là một nhóm SSTable riêng, hết TTL thì **xóa cả file** thay vì compaction — gần như không tốn I/O.

### 4.2 B-tree vs LSM – bảng quyết định

| | B-tree | LSM-tree |
|---|---|---|
| Throughput ghi | Trung bình | **Cao** |
| Độ trễ đọc điểm | **Thấp, dự đoán được** | Cao hơn, biến động |
| Đọc dải | **Rất tốt** | Tốt (nếu cùng partition) |
| Nén | Trung bình | **Tốt** |
| p99 ổn định | **Tốt hơn** | Có thể tăng vọt khi compaction |
| Transaction/lock | Tự nhiên hơn | Khó hơn |
| Ví dụ | PostgreSQL, MySQL InnoDB, SQL Server | Cassandra, RocksDB, LevelDB, ScyllaDB, HBase, MongoDB (WiredTiger có cả hai) |

Cách chọn thực dụng:

```text
Ghi rất nhiều, chủ yếu append, đọc theo partition+dải thời gian → LSM
Đọc điểm nhiều, cần p99 ổn định, transaction phức tạp            → B-tree
Không chắc                                                        → B-tree (dễ suy luận hơn)
```

Đây chính là câu trả lời cho câu hỏi ở mục 1, và là lý do case study chat ở [realtime_scale_designs.md](../case_studies/realtime_scale_designs.md) chọn Cassandra: workload ghi nhiều, đọc theo `(chat_id, thời gian)`.

---

## 5. Row-oriented vs column-oriented

```text
Row store — một hàng nằm liền nhau:
  [id=1,name=A,city=HN,amount=100][id=2,name=B,city=SG,amount=200]...
  → đọc cả hàng rẻ; SELECT SUM(amount) phải đọc MỌI cột của MỌI hàng

Column store — một cột nằm liền nhau:
  id:     [1,2,3,4,...]
  name:   [A,B,C,D,...]
  amount: [100,200,300,400,...]
  → SELECT SUM(amount) chỉ đọc một dải liên tục; đọc cả một hàng thì đắt
```

Ba nguồn tốc độ của columnar cho phân tích:

| Nguồn | Cơ chế |
|---|---|
| **Chỉ đọc cột cần** | Query dùng 3/50 cột → đọc 6% dữ liệu |
| **Nén rất cao** | Cùng cột = cùng kiểu, giá trị tương tự → RLE, dictionary, delta, bit-packing cho tỉ lệ 5–20× |
| **Xử lý vector hóa** | Một lệnh CPU xử lý nhiều giá trị (SIMD); không có overhead per-row |

Thêm một cơ chế quan trọng: **min/max theo block** cho phép bỏ qua toàn bộ block không thỏa điều kiện (segment elimination / zone map) — hiệu quả cực cao khi dữ liệu được sắp theo cột filter.

```text
Row store:    OLTP  — nhiều query nhỏ, chạm ít bản ghi, cập nhật từng bản ghi
Column store: OLAP  — ít query lớn, quét hàng triệu bản ghi, chủ yếu append
```

Chi tiết engine columnar: [clickhouse package](../../clickhouse/roadmap.md).

---

## 6. Encoding – định dạng dữ liệu trên dây và trên disk

Chọn format ảnh hưởng băng thông, CPU, và **khả năng tiến hóa schema** — yếu tố cuối quan trọng nhất mà ít được cân nhắc.

| Format | Schema | Kích thước | Đọc được bằng mắt | Đặc điểm |
|---|---|---|---|---|
| **JSON** | Không | Lớn | Có | Phổ biến nhất; không có kiểu số chính xác (mọi số là double) |
| **JSON Schema / OpenAPI** | Bên ngoài | Lớn | Có | Có validation nhưng vẫn là JSON trên dây |
| **Protobuf** | Bắt buộc (.proto) | Nhỏ | Không | Field number là hợp đồng; tiến hóa tốt; gRPC dùng |
| **Avro** | Bắt buộc | Nhỏ | Không | **Writer schema + reader schema** → tiến hóa mạnh nhất; Kafka/Hadoop dùng |
| **Thrift** | Bắt buộc | Nhỏ | Không | Tương tự Protobuf |
| **MessagePack / CBOR** | Không | Nhỏ hơn JSON | Không | "JSON nhị phân"; không giải quyết tiến hóa |
| **Parquet** | Bắt buộc | Rất nhỏ | Không | **Columnar trên disk**; chuẩn của data lake |
| **ORC** | Bắt buộc | Rất nhỏ | Không | Tương tự Parquet, hệ sinh thái Hive |

Điểm khác biệt cốt lõi giữa Protobuf và Avro về mặt tiến hóa:

```text
Protobuf: mỗi field có SỐ cố định. Reader bỏ qua field số lạ, dùng default cho field thiếu.
          → tiến hóa dựa vào việc KHÔNG BAO GIỜ tái sử dụng field number.

Avro:     reader biết CẢ writer schema (đi kèm dữ liệu hoặc qua schema registry) VÀ reader schema
          → có thể resolve theo TÊN field, đổi tên qua alias, tiến hóa linh hoạt hơn
          → nhưng bắt buộc phải có cách lấy writer schema → schema registry
```

Với dữ liệu lưu lâu dài (data lake, event log), Avro/Parquet + schema registry là lựa chọn bền vững; với RPC nội bộ, Protobuf gọn và đủ. Chi tiết schema registry: [kafka/schema_registry.md](../../kafka/ecosystem/schema_registry.md).

---

## 7. Schema evolution – tương thích tiến và lùi

Đây là chủ đề quyết định việc bạn có thể deploy độc lập các service hay không.

```text
Backward compatible : code MỚI đọc được dữ liệu CŨ
Forward compatible  : code CŨ đọc được dữ liệu MỚI
Full compatible     : cả hai
```

Vì sao cần cả hai: trong một rolling deploy, phiên bản mới và cũ **cùng chạy** và cùng đọc/ghi một luồng dữ liệu.

| Thay đổi | Backward? | Forward? | Ghi chú |
|---|---|---|---|
| Thêm field **optional có default** | ✅ | ✅ | Thay đổi an toàn nhất |
| Thêm field **required** | ✅ | ❌ | Code cũ ghi thiếu field → code mới lỗi |
| Xóa field optional | ✅ | ✅ | An toàn nếu chưa ai bắt buộc dùng |
| Xóa field required | ❌ | ✅ | Code cũ đọc sẽ thiếu |
| Đổi tên field | ❌ | ❌ | Trừ khi có alias (Avro) |
| Đổi kiểu (thu hẹp) | ❌ | ❌ | `long` → `int` mất dữ liệu |
| Đổi kiểu (mở rộng) | ✅ | ❌ | `int` → `long` an toàn một chiều |
| **Tái sử dụng field number** (Protobuf) | ❌ | ❌ | Lỗi nghiêm trọng nhất — dữ liệu bị đọc sai kiểu |

Quy tắc thực dụng có thể áp dụng ngay:

```text
1. Mọi field mới là OPTIONAL và có DEFAULT
2. Không bao giờ xóa field — đánh dấu deprecated, dừng dùng, xóa sau nhiều chu kỳ
3. Không bao giờ đổi tên — thêm field mới, backfill, bỏ field cũ sau
4. Protobuf: dùng `reserved` cho field number đã bỏ, để không ai tái sử dụng
5. Enum: LUÔN có giá trị UNKNOWN = 0 để reader cũ xử lý được giá trị mới
```

```protobuf
message Order {
  reserved 4, 7;                 // đã xóa — không ai được dùng lại
  reserved "legacy_status";

  int64  order_id  = 1;
  string tenant_id = 2;
  Status status    = 3;
  optional string channel = 8;   // field mới: optional
}

enum Status {
  STATUS_UNKNOWN = 0;            // BẮT BUỘC: reader cũ gặp giá trị mới sẽ map về đây
  STATUS_PENDING = 1;
  STATUS_PAID    = 2;
}
```

Quy tắc enum ở trên là thứ hay bị bỏ và gây bug khó tìm: không có `UNKNOWN = 0`, service cũ nhận giá trị enum mới sẽ hoặc lỗi parse hoặc mặc định về một giá trị nghiệp vụ sai.

Điều tương tự áp dụng cho REST/JSON API dù không có schema bắt buộc: **client phải bỏ qua field lạ** (tolerant reader), server không được đổi nghĩa field đã có. Đó là nền tảng của versioning API — xem `advanced/api_design.md`.

---

## 8. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| B-tree engine | Đọc điểm nhanh, p99 ổn định, transaction dễ | Throughput ghi thấp hơn, write amplification | OLTP nói chung |
| LSM engine | Ghi rất nhanh, nén tốt | Đọc phải xem nhiều SSTable, p99 biến động do compaction | Ghi nhiều, time-series, log |
| Leveled compaction | Đọc tốt, space amp thấp | Write amp cao | Đọc quan trọng |
| Size-tiered compaction | Write amp thấp | Read/space amp cao | Ghi rất nhiều |
| Row store | Đọc/ghi cả bản ghi rẻ | Quét phân tích đắt | OLTP |
| Column store | Phân tích nhanh, nén cao | Đọc một hàng đắt, update từng bản ghi kém | OLAP |
| fsync mỗi commit | RPO = 0 | Độ trễ ghi cao hơn | Dữ liệu tiền tệ |
| fsync theo nhóm | Throughput cao hơn nhiều | Có thể mất vài ms cuối | Log, metric, event |
| JSON trên dây | Dễ đọc, phổ biến | Lớn, không có tiến hóa có kiểm soát | API công khai |
| Avro + registry | Tiến hóa mạnh nhất, gọn | Cần hạ tầng registry | Event log, data lake |
| Protobuf | Gọn, nhanh, tiến hóa tốt | Không đọc được bằng mắt | RPC nội bộ |
| Parquet | Nén và quét cực tốt | Không phù hợp ghi từng bản ghi | Data lake, archive |

---

## 9. Áp dụng vào thiết kế

| Bài toán | Suy luận từ chương này |
|---|---|
| Lưu tin nhắn chat, ghi rất nhiều, đọc theo `(chat_id, time)` | LSM (Cassandra/ScyllaDB); TWCS nếu có TTL |
| Lưu đơn hàng, cần transaction, truy vấn đa dạng | B-tree quan hệ (PostgreSQL) |
| Đếm view/like, ghi cực nhiều, chính xác tuyệt đối không cần | Ghi vào Redis (write-behind) rồi flush; hoặc LSM |
| Log/metric, giữ 30 ngày rồi xóa | LSM với TWCS, hoặc columnar với partition theo thời gian |
| Báo cáo doanh thu theo tháng trên 2 tỉ dòng | Columnar (ClickHouse), partition theo thời gian |
| Archive dữ liệu lạnh nhưng vẫn truy vấn được | Parquet trên object storage + engine query ngoài |
| Event stream giữa nhiều service, nhiều năm | Avro + schema registry, quy tắc tiến hóa ở mục 7 |
| Primary key cho bảng lớn ghi nhiều | Tăng dần (không UUID v4); cân nhắc hot-last-page |

---

## 10. Ghi chú – chủ đề tiếp theo

- [databases_design.md](databases_design.md): áp dụng vào chọn công nghệ, sharding, replication.
- [distributed_systems_theory.md](distributed_systems_theory.md): các engine này khi phân tán ra nhiều node.
- [caching.md](caching.md): buffer pool là một dạng cache; vì sao page 8KB quan trọng.
- [sqlserver/architecture.md](../../sqlserver/fundamentals/architecture.md): một ví dụ B-tree engine mô tả chi tiết.
- [clickhouse package](../../clickhouse/roadmap.md): một ví dụ columnar engine.
- [kafka/schema_registry.md](../../kafka/ecosystem/schema_registry.md): schema evolution trong thực tế.

Từ khóa mở rộng: fractal tree / Bε-tree, WiredTiger, RUM conjecture (Read–Update–Memory: chọn 2 trong 3), bloom vs cuckoo filter, zone map / min-max index, dictionary encoding, run-length encoding, Zstandard vs LZ4, `fsync` vs `fdatasync`, double-write buffer, torn page, checksum page verify.

Một khung tư duy đáng nhớ để kết chương: **RUM conjecture** — mọi access method chỉ tối ưu được hai trong ba: Read overhead, Update overhead, Memory/space overhead. B-tree chọn Read + Memory; LSM chọn Update + Memory; index dày đặc chọn Read + Update. Không có engine nào "tốt hơn" — chỉ có engine phù hợp hơn với đánh đổi bạn cần.

---

*Cập nhật lần cuối: 2026-07-30*
