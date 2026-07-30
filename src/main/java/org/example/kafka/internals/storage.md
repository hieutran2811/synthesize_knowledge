# Kafka Storage – Log, Retention & Compaction – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)
>
> Phạm vi đối chiếu chính: Apache Kafka 4.3. Với cluster phiên bản khác, luôn kiểm tra lại tên property, giá trị mặc định và giới hạn tiered storage.

---

## What – Kafka Storage Model

Kafka lưu data dưới dạng **commit log** *(nhật ký append-only đã commit)* — một chuỗi record được ghi nối đuôi, giữ thứ tự trong partition và không update-in-place. Đây là nền tảng của replay, retention, compaction và tiered storage.

Record được append vào log của từng partition; việc đọc dùng offset và index để định vị. “Immutable” ở đây nói về cách ghi record đã append, không có nghĩa file segment vĩnh viễn không bị xóa hoặc compaction không tạo segment mới.

```
Kafka storage stack:
  Topic → Partition → Log (directory on disk) → Segments (files)

Physical layout:
  /data/kafka/
    orders-0/              # topic "orders", partition 0
      00000000000000000000.log    # segment file (records)
      00000000000000000000.index  # offset index
      00000000000000000000.timeindex  # timestamp index
      00000000000000000000.txnindex  # aborted-transaction index (khi cần)
      00000000000000001000.log    # next segment (after rollover)
      00000000000000001000.index
      leader-epoch-checkpoint     # leader epoch file
    orders-1/              # partition 1
    ...
```

> 💡 **Giải thích dễ hiểu — log là quyển sổ chỉ viết thêm:**
> Kafka không xóa/sửa dòng giữa quyển sổ cho mỗi update. Nó ghi dòng mới ở cuối, còn index giống mục lục giúp tìm nhanh trang cần đọc. Khi retention hoặc compaction chạy, Kafka thay các quyển sổ cũ bằng segment mới; offset lịch sử vẫn không được đánh lại.

---

## Components – Log Segments

**Log segment** *(tệp con của partition được roll theo ngưỡng)* là đơn vị Kafka đóng/mở để retention, compaction và upload remote. Một partition có đúng một active segment tại một thời điểm; các segment còn lại đã đóng.

```
Segment: unit of storage rotation
  Active segment: current segment being written to
  Closed segment: full/old segments (eligible for retention/compaction)

Segment rollover triggers:
  log.segment.bytes (thường 1GB): size threshold
  log.roll.ms/segment.ms (thường 7 days): time threshold
  log.roll.hours: legacy alias for log.roll.ms

Segment naming: base offset of first record
  00000000000000000000.log = starts at offset 0
  00000000000000001000.log = starts at offset 1000
```

### Index Files

**Sparse index** *(index thưa)* không ghi một entry cho mọi record. Nó ánh xạ một số offset/timestamp đại diện tới vị trí vật lý, rồi Kafka scan đoạn nhỏ còn lại để tìm chính xác record.

```
Offset Index (.index):
  Sparse index: relative offset → position in .log file
  Khoảng mỗi log.index.interval.bytes (thường 4KB) → 1 index entry
  Binary search for offset → jump to position

Timestamp Index (.timeindex):
  timestamp → relative offset
  Used for time-based seek (consumer offsetsForTimes)

Transaction Index (.txnindex):
  tracks aborted transactions (for read_committed consumers)
```

---

## How – Write Path

**Page cache** *(bộ đệm file của hệ điều hành)* là lớp trung chuyển chính cho file log. Kafka không giữ toàn bộ data cache trong JVM heap.

```
Producer → Broker → Log
  1. Record arrives at leader partition
  2. Producer đã gom record thành batch; broker kiểm tra và append batch vào active .log
  3. Hệ điều hành đưa ghi file vào page cache, Kafka cập nhật sparse .index/.timeindex
  4. Follower replicas fetch từ leader và append bản sao
  5. Leader trả ACK theo acks sau khi điều kiện tương ứng đạt

Kafka thường không `fsync` *(ép dữ liệu xuống storage bền vững)* cho từng message. Durability thường dựa trên replication + OS background flush; `flush.messages`/`flush.ms` chỉ ép flush theo ngưỡng và không thay thế RF/ISR. Mất điện đồng thời trên mọi replica trước khi OS flush vẫn là failure mode cần tính đến.
```

> 💡 **Giải thích dễ hiểu — page cache là bàn trung chuyển, replication là bản sao dự phòng:**
> Broker đặt kiện hàng lên bàn trung chuyển của OS rồi các kho follower chép lại. Không cần khóa két sau từng kiện nên nhanh hơn, nhưng chỉ có một bàn trung chuyển là chưa đủ an toàn. Muốn bền vững, phải có đủ bản sao, `acks`/ISR đúng và kế hoạch cho sự cố mất điện toàn cụm.

```properties
# Log configuration (server.properties)
log.dirs=/data/kafka                 # can be multiple: /data/kafka1,/data/kafka2
log.segment.bytes=1073741824         # 1GB per segment
log.roll.ms=604800000                # 7 days
log.flush.interval.messages=9223372036854775807  # rely on OS flush
log.flush.interval.ms=9223372036854775807        # rely on OS flush (default)
log.index.size.max.bytes=10485760    # 10MB max index size
log.index.interval.bytes=4096        # index every 4KB
```

---

## How – Retention Policies

**Retention policy** *(chính sách vòng đời dữ liệu)* quy định khi segment cũ đủ điều kiện bị xóa hoặc chuyển remote. **Cleanup policy** *(chính sách dọn log)* có thể là `delete`, `compact` hoặc kết hợp.

```
Retention: when to delete old data

Types:
  1. Time-based:  segment đủ điều kiện sau retention.ms
  2. Size-based:  xóa segment cũ khi log vượt retention.bytes
  3. Compact:     background cleaner giữ latest value theo key
  4. Compact+Delete: compaction + time/size retention (hybrid)

Retention delete hoạt động theo segment (xóa cả file, không xóa từng record)
Active segment phải roll trước khi đủ điều kiện xóa/compact
```

Retention là chính sách “được phép dọn”, không phải timestamp xóa chính xác từng record. Segment roll, retention check interval, file-delete delay và cleaner backlog đều khiến dữ liệu có thể tồn tại lâu hơn ngưỡng cấu hình. `retention.bytes` áp dụng theo partition, nên tổng disk của topic xấp xỉ cộng qua tất cả partition và replica.

> 💡 **Giải thích dễ hiểu — Kafka dọn cả thùng hồ sơ:**
> Nếu một dòng trong thùng đã cũ nhưng các dòng khác chưa cũ, Kafka không xé riêng dòng đó; nó chờ thùng segment đủ điều kiện rồi dọn cả thùng. Segment nhỏ cho thời điểm dọn sát hơn nhưng tạo nhiều file và overhead hơn.

```bash
# Default topic retention
log.retention.hours=168          # 7 days (default)
log.retention.bytes=-1           # unlimited by default
log.retention.check.interval.ms=300000  # check every 5 min

# Per-topic override
kafka-configs.sh --bootstrap-server localhost:9092 \
  --entity-type topics --entity-name orders \
  --alter --add-config 'retention.ms=86400000,retention.bytes=10737418240'  # 24h, 10GB

# Unlimited retention (for audit, compliance)
kafka-configs.sh --bootstrap-server localhost:9092 \
  --alter --entity-type topics --entity-name audit-log \
  --add-config 'retention.ms=-1,retention.bytes=-1'
```

`retention.ms=-1` và `retention.bytes=-1` có nghĩa không giới hạn theo chính sách đó, không phải “disk vô hạn”. Topic audit cần quota, monitoring và tier/archive phù hợp; nếu local disk đầy, broker có thể mất khả năng ghi.

---

## How – Log boundaries và `__consumer_offsets`

Ba loại offset thường bị nhầm với nhau:

```text
Partition data:
  log start = 120                                      log end = 182
         │                                                   │
         ▼                                                   ▼
       [120] ... [149] | [150] ... [181] | (vị trí ghi kế tiếp)
                       ▲
                       └─ current position = 150
                          (record kế tiếp consumer sẽ fetch)

Consumer group metadata:
  committed offset = 145 (vị trí bền vững để resume)
```

- **Log start offset** là offset nhỏ nhất broker còn có thể phục vụ. Retention hoặc truncate có thể làm mốc này tăng.
- **Log end offset** là vị trí ngay sau record cuối hiện có, không phải offset của chính record cuối.
- **Current position** nằm trong consumer đang chạy và tiến theo `poll()`.
- **Committed offset** được lưu bền cho group và cũng biểu thị record kế tiếp cần đọc sau restart.

Kafka lưu committed offset và group metadata trong internal topic compacted `__consumer_offsets`. Key của bản ghi nhận diện group/topic/partition; value chứa offset và metadata liên quan. Compaction giữ trạng thái mới nhất, còn tombstone cho phép dọn state của group hoặc offset đã hết hạn.

```properties
# Broker defaults trong Kafka 4.3; quyết định sớm trước production.
offsets.topic.num.partitions=50
offsets.topic.replication.factor=3
offsets.topic.segment.bytes=104857600
offsets.retention.minutes=10080
```

`offsets.topic.num.partitions` quyết định cách tải coordinator được chia và không nên đổi sau khi triển khai. Internal topic chỉ được tạo khi cluster đáp ứng replication factor đã cấu hình; cluster dev một broker thường phải override phù hợp, nhưng production không nên hạ durability chỉ để che thiếu broker.

Offset hết hạn không đơn giản là “sau 7 ngày kể từ commit” trong mọi trường hợp. Với subscribed group, Kafka xét thời gian group không còn consumer hoặc partition không còn thuộc subscription; với manual assignment, thời gian tính từ commit cuối. Xóa group hoặc topic có thể xóa metadata offset liên quan mà không chờ retention.

Nếu committed/current offset nhỏ hơn log start offset vì data đã bị retention xóa, consumer gặp **offset out of range**. Khi đó:

- `auto.offset.reset=earliest`: đọc từ record cũ nhất còn tồn tại, không thể khôi phục phần đã xóa.
- `auto.offset.reset=latest`: bỏ qua tới cuối log hiện tại; có nguy cơ mất xử lý mà không thấy lỗi nghiệp vụ rõ ràng.
- `auto.offset.reset=none`: ném lỗi để operator hoặc ứng dụng quyết định có chủ đích.

> 💡 **Giải thích dễ hiểu — bookmark và số trang còn lại:**
> Committed offset là bookmark của một nhóm đọc, còn log start/end là phạm vi trang vẫn nằm trong thư viện. Nếu bookmark ở trang 50 nhưng thư viện đã hủy mọi trang trước 120, Kafka không thể “replay từ 50”; ứng dụng phải chọn đọc từ trang 120, nhảy tới cuối, hoặc dừng để báo lỗi.

Không chỉnh sửa `__consumer_offsets` trực tiếp. Dùng `kafka-consumer-groups.sh` hoặc Admin API để xem/reset/delete group và lưu audit cho mọi thao tác reset.

---

## How – Log Compaction

**Log compaction** *(gom/dọn log theo key)* là background rewrite giữ trạng thái mới nhất theo key trong từng partition. Đây khác với retention `delete`, vốn xóa segment theo tuổi/kích thước.

**Tombstone** *(marker xóa)* là record có key và value `null`; cleaner giữ nó đủ lâu để consumer rebuild state nhận biết key đã bị xóa.

```
Compaction: eventually retain the latest record per key trong từng partition
  - Useful for: state snapshots, changelog topics, user profiles
  - Tombstone: record with value=null → mark key for deletion
    (tombstone được giữ theo delete.retention.ms, thường 24h, rồi mới có thể bị dọn)

  Before compaction:
    [k1:v1] [k2:v1] [k1:v2] [k3:v1] [k2:v2] [k1:v3]

  After compaction:
    [k3:v1] [k2:v2] [k1:v3]          # retained records keep their original order

  Compaction guarantees:
    - Cleaner không đổi thứ tự các record còn lại
    - Offset không được đánh lại; sau compaction có thể có offset holes
    - Consumer đọc trước khi cleaner chạy có thể thấy nhiều version của key
    - Consumer rebuild từ đầu phải bắt kịp trước khi tombstone bị dọn nếu cần thấy delete
    - Active segment không compact cho tới khi roll

Compacted topic use cases:
  - Kafka Streams changelog (state store backup)
  - Event sourcing: current state of each entity
  - User settings, configurations
  - CDC final state
```

Compaction không phải snapshot tức thời và không phải guarantee rằng consumer đang chạy luôn chỉ thấy một giá trị. Nó là background process; trong khoảng dirty tail, các phiên bản cũ vẫn có thể xuất hiện. Record key `null` không cung cấp identity để đạt semantics latest-per-key; compacted topic nên dùng key ổn định. Tombstone chỉ là marker xóa, không phải payload `null` được giữ vĩnh viễn.

> 💡 **Giải thích dễ hiểu — compaction là dọn hồ sơ theo mã, không phải tua lại số trang:**
> Hồ sơ khách hàng có thể có nhiều bản cập nhật. Nhân viên kho sau khi dọn chỉ giữ bản cuối, nhưng số trang cũ không được đánh lại nên bookmark vẫn có khoảng trống. Nếu người đọc đi quá chậm, phiếu xóa (tombstone) có thể đã bị hủy trước khi họ nhìn thấy.

```bash
# Create compacted topic
kafka-topics.sh --bootstrap-server localhost:9092 \
  --create --topic user-profiles \
  --config cleanup.policy=compact \
  --config min.cleanable.dirty.ratio=0.5 \
  --config segment.ms=3600000  # roll mỗi giờ; không ép cleaner chạy ngay

# Compact + delete (hybrid)
kafka-configs.sh --alter --entity-type topics --entity-name user-activity \
  --add-config cleanup.policy=compact,delete,retention.ms=604800000
```

```properties
# Compaction configuration (server.properties)
log.cleanup.policy=delete                 # default
log.cleaner.enable=true                   # Kafka 4.3: deprecated; kiểm tra version trước khi dùng
log.cleaner.threads=1                     # dedicated cleaner threads
log.cleaner.min.cleanable.ratio=0.5       # compact when dirty > 50% of log
log.cleaner.min.compaction.lag.ms=0       # min time before record can be compacted
log.cleaner.max.compaction.lag.ms=9223372036854775807  # max time record can stay uncompacted
log.cleaner.delete.retention.ms=86400000   # broker default for tombstones (1 day)
# Topic override: delete.retention.ms=86400000
# Topic override: min.compaction.lag.ms=0
```

`min.cleanable.dirty.ratio` chỉ là ngưỡng eligibility cùng với min/max compaction lag; cleaner backlog, I/O throttle và số cleaner thread vẫn quyết định lúc compaction thực sự hoàn tất. Đừng dùng `segment.ms` như nút “force compaction”.

---

## How – Compaction Internals

**Log cleaner** *(tiến trình dọn log nền)* đọc dirty tail, tạo bản rewrite và thay segment cũ; nó không chạy đồng bộ trong đường ghi của producer.

```
Log Cleaner architecture:
  CleanerThread: background thread per log.cleaner.threads
  OffsetMap: in-memory hash map (key → latest offset)
    Size: log.cleaner.dedupe.buffer.size (default 128MB)

Cleaning process:
  1. Select "dirtiest" partition (highest dirty ratio)
  2. Build OffsetMap: scan tail (dirty) portion, map key → latest offset
  3. Copy clean head + filtered dirty portion → new segment
  4. Replace old segments atomically

Log sections:
  Clean head: already compacted (no duplicates)
  Dirty tail: new records since last compaction
```

---

## How – Tiered Storage *(lưu phân tầng, Kafka 4.3)*

**Remote Log Metadata Manager (RLMM)** *(bộ quản lý metadata log ở remote)* theo dõi segment và index đang ở local hay object storage để broker phục vụ fetch.

```
Tiered Storage: offload old log segments to remote storage (S3, GCS, Azure Blob)
  Local tier:  recent data (fast access, limited disk)
  Remote tier: historical data (cheap storage, higher latency)

Benefits:
  - Longer retention without large local disks
  - Independent scaling of storage vs compute
  - Cheaper long-term retention

Architecture:
  Broker: maintain local segments + upload to remote storage
  Consumer: transparent fetch (broker proxies from remote if needed)
  Remote Log Metadata Manager (RLMM): tracks segment locations
```

Tiered storage không tự biến mọi object storage thành Kafka backend. Kafka server cung cấp interface và cơ chế quản lý; RemoteStorageManager implementation thường do vendor/operator cung cấp. Kafka 4.3 docs ghi rõ feature mặc định tắt và không có implementation remote storage production built-in; LocalTieredStorage chủ yếu phục vụ thử nghiệm. Compacted topics hiện không được tiered storage hỗ trợ trong implementation chuẩn, nên phải kiểm tra release notes trước khi bật.

```properties
# server.properties (Tiered Storage)
remote.log.storage.system.enable=true
remote.log.storage.manager.class.name=<vendor.RemoteStorageManager implementation>
remote.log.storage.manager.class.path=/opt/kafka/plugins/tiered-storage/*
# Kafka default RLMM uses an internal topic; configure its listener
remote.log.metadata.manager.listener.name=PLAINTEXT
# Optional provider-specific RemoteLogMetadataManager:
# remote.log.metadata.manager.class.name=<vendor.RemoteLogMetadataManager implementation>

# Provider-specific settings (ví dụ S3 plugin; tên key phụ thuộc vendor)
s3.bucket.name=my-kafka-tiered-storage
s3.region=ap-southeast-1

# Per-topic: how long to keep locally
kafka-configs.sh --bootstrap-server localhost:9092 \
  --alter --entity-type topics --entity-name orders \
  --add-config 'remote.storage.enable=true,local.retention.ms=86400000'  # 1 day local
```

`local.retention.ms/bytes` quyết định thời gian/kích thước giữ ở broker; `retention.ms/bytes` quyết định vòng đời tổng ở cả local và remote. Segment local chỉ được xóa sau khi upload remote thành công. Remote tier giảm local disk nhưng không xóa yêu cầu sizing/network/monitoring: backfill từ remote có latency và chi phí request khác tail read từ page cache.

> 💡 **Giải thích dễ hiểu — tiered storage là kho gần và kho xa:**
> Kho gần cạnh quầy phục vụ đơn mới nên rất nhanh nhưng đắt. Khi kiện hàng cũ, broker chuyển nó sang kho S3/GCS rẻ hơn; nhân viên vẫn có thể lấy lại qua broker nhưng phải chờ vận chuyển. “Đã upload” chưa đồng nghĩa “được xóa ngay”: phải tôn trọng local retention và remote retention riêng.

---

## Why – Kafka's Storage Design Choices

**Zero-copy** *(giảm sao chép qua user space)* là kỹ thuật để kernel chuyển dữ liệu file tới socket với ít lần copy CPU hơn khi điều kiện filesystem/OS cho phép.

```
Why append-only log?
  Sequential appends thường tận dụng disk/page cache tốt hơn random update
  SSD: vẫn hưởng lợi từ access pattern tuần tự và đơn giản hóa write path
  Simplicity: không update-in-place → write path ít lock/index mutation hơn
  Lưu ý: compaction vẫn cần thiết cho keyed state và tạo rewrite I/O riêng

Why rely on OS page cache?
  Kafka chủ yếu dùng OS page cache thay vì giữ toàn bộ data cache trên JVM heap
  OS page cache: shared between producer writes + consumer reads
  Producer writes → page cache → consumer có thể đọc lại từ cùng cache
  JVM heap pressure avoided: data lives in OS memory, not JVM

Why zero-copy?
  Normal: disk → kernel buffer → user space → kernel buffer → socket
  Zero-copy (sendfile): disk → kernel buffer → socket (skip user space copy)
  → có thể giảm copy CPU cho fetch từ local file, tùy OS/filesystem/workload
  → Linux sendfile() syscall qua Java NIO khi đường đi hỗ trợ

Why separate index files?
  Offset lookup without scanning entire log
  Sparse index: good balance between memory and lookup speed
  Binary search on sparse index: O(log n) entries, then scan bounded range to record
```

Page cache không phải cache vô hạn: nó cạnh tranh với page cache của OS khác, cgroups và process khác. Tail reads thường được cache tốt; backfill/remote reads có thể gây eviction và làm latency tăng. Hãy đo page faults, disk latency, cache hit và network thay vì dùng phần trăm “zero-copy improvement” cố định.

> 💡 **Giải thích dễ hiểu — page cache là bàn sách dùng chung:**
> Producer đặt sách lên bàn, consumer sau đó có thể đọc ngay mà không xuống kho. Nếu quá nhiều người đem sách cũ lên (backfill), sách nóng bị đẩy ra và mọi người phải xuống kho lại. Kafka tiết kiệm heap Java nhưng vẫn phải tính RAM OS và tranh chấp I/O.

---

## Trade-offs

```
Segment size:
  Small:   faster retention (more precise), more files, more overhead
  Large:   fewer files, slower retention, large single files
  → Bắt đầu từ broker default rồi benchmark; chỉnh theo throughput, retention và recovery SLA

Compaction vs Delete:
  Delete:   simple, predictable size
  Compact:  always retain latest, unbounded size (unless + delete)
  → Compact for entity state; delete for time-series events; hybrid for both

Flush interval:
  Per-message fsync: thêm latency I/O cho mỗi flush; mức chậm phụ thuộc thiết bị/filesystem
  OS-managed:        thường nhanh hơn, kết hợp replication cho durability
  → Không coi fsync là thay thế replication hoặc ngược lại

Cleaner buffer (log.cleaner.dedupe.buffer.size):
  Too small: multi-pass compaction → slower
  Too large: OOM risk
  → Monitor cleaner stats: kafka.log.LogCleaner:type=LogCleaner

Tiered storage:
  ✅ Có thể rẻ hơn cho retention dài (phụ thuộc provider/request/egress)
  ❌ Higher fetch latency for historical data
  ❌ Additional operational complexity
  ❌ Implementation/version/compacted-topic limitations cần kiểm tra
  → Good for: log analytics, audit, compliance với retention dài khi đã tính chi phí
```

### Disk sizing

```text
Usable storage (xấp xỉ) = ingest bytes/s
                         × retention seconds
                         × replication factor
                         + index/segment overhead
                         + compaction/recovery headroom

Per-broker capacity phải tính replica placement, failure domain, rebalance traffic,
OS/page-cache needs và ngưỡng disk utilization an toàn; không chỉ lấy tổng data chia đều.
```

Với compacted topic, cần chừa dung lượng cho cleaner rewrite và các segment cũ chưa xóa. Với tiered storage, tính riêng local retention và remote retention, cộng chi phí upload/fetch/egress. Dùng throughput đã benchmark theo record size, compression, RF và acks; các con số kiểu “MB/s mỗi partition” chỉ là điểm đo của một môi trường cụ thể.

> 💡 **Giải thích dễ hiểu — sizing là tính cả kho, lối đi và lúc chuyển kho:**
> Nếu cần chứa 1.000 thùng hàng, kho ba bản sao phải có chỗ cho 3.000 thùng, lối đi, hàng đang sang kệ và khoảng trống khi một kho đóng cửa. Compaction/recovery cũng cần chỗ tạm; chỉ đủ chỗ cho dữ liệu “đang thấy” sẽ khiến broker đầy đúng lúc sự cố.

### Disk failure và log directories

`log.dirs` có thể chứa nhiều thư mục/volume, nhưng đây không phải bản sao dữ liệu bên trong một broker. Mỗi replica partition nằm ở một log directory; durability đến từ replica trên broker/failure domain khác.

Khi Kafka gặp I/O error sau lúc load log, directory có thể bị đánh dấu offline. Replica nằm trong directory đó không còn phục vụ; client nhận lỗi retriable/metadata refresh và partition leader có thể chuyển sang replica hợp lệ trên broker khác. Nếu topic thiếu replica khỏe, sự cố một volume vẫn có thể làm partition unavailable hoặc mất durability.

Production cần:

- Alert disk usage, inode, I/O latency, offline log directory và under-replicated/offline partition.
- Giữ headroom cho compaction, replica catch-up và reassignment; không chờ 100% disk mới hành động.
- Dùng `kafka-log-dirs.sh --describe` để xác định replica nằm ở directory nào.
- Dùng partition reassignment để di chuyển dữ liệu; không copy/move file segment thủ công khi broker đang chạy.
- Thay volume lỗi theo runbook đã thử nghiệm, rồi xác minh ISR và replica lag trước khi đóng incident.

> 💡 **Giải thích dễ hiểu — nhiều ổ không đồng nghĩa có bản sao:**
> Hai tủ hồ sơ trong cùng văn phòng chỉ giúp chia chỗ, không tự tạo hai bản của mỗi hồ sơ. Khi một tủ hỏng, chỉ hồ sơ đã được sao sang văn phòng broker khác mới giúp hệ thống tiếp tục phục vụ.

---

## Real-world

```bash
# Monitor log compaction
kafka-log-dirs.sh --bootstrap-server localhost:9092 \
  --topic-list user-profiles --describe
# Shows replica/partition placement, size, offsetLag, isFuture theo log directory

# Check cleaner stats (JMX)
# kafka.log:type=LogCleanerManager,name=max-dirty-percent
# kafka.log:type=LogCleaner,name=cleaner-recopy-percent
# → Alert: cleaner falling behind (dirty ratio consistently high)

# Force compaction (testing/emergency)
# Không có lệnh force. Hạ min.cleanable.dirty.ratio chỉ làm log sớm đủ điều kiện;
# cleaner backlog/I/O vẫn quyết định khi nào hoàn tất. Khôi phục config sau thử nghiệm.

# Segment inspection tool
kafka-dump-log.sh --files /data/kafka/orders-0/00000000000000000000.log \
  --print-data-log

# Check offset and timestamp indexes
kafka-dump-log.sh --files /data/kafka/orders-0/00000000000000000000.index \
  --index-sanity-check
kafka-dump-log.sh --files /data/kafka/orders-0/00000000000000000000.timeindex
```

```
Production retention strategy:
  Transactional events (orders, payments):
    retention.ms=604800000 (7 days), cleanup.policy=delete
    Downstream systems should have their own persistence

  User state (profiles, settings):
    cleanup.policy=compact
    Có thể không đặt size/time delete nếu muốn giữ latest state lâu dài; vẫn cần tính disk

  Application logs:
    retention.ms=86400000 (1 day), cleanup.policy=delete
    Short retention: Elasticsearch/Splunk as long-term store

  Audit trail:
    retention.ms=-1 (unlimited local disk) hoặc tiered/archive storage
    Regulatory requirement: thời hạn tùy ngành; phải có policy/backup kiểm chứng

  Kafka Streams changelog topics:
    cleanup.policy thường có compact; để Kafka Streams quản lý config phù hợp
    Không tự đặt retention vô hạn nếu chưa tính local disk/recovery
```

---

## Nguồn tham khảo chính thức

- [Apache Kafka 4.3 – Design](https://kafka.apache.org/43/design/design/)
- [Apache Kafka 4.3 – Broker Configs](https://kafka.apache.org/43/configuration/broker-configs/)
- [Apache Kafka 4.3 – Tiered Storage](https://kafka.apache.org/43/operations/tiered-storage/)
- [KafkaConsumer API – Offsets and Consumer Position](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/KafkaConsumer.html)
- [OffsetOutOfRangeException API](https://kafka.apache.org/43/javadoc/org/apache/kafka/clients/consumer/OffsetOutOfRangeException.html)

---

## Ghi chú – Chủ đề tiếp theo
> [replication.md](replication.md): Leader election, ISR (In-Sync Replicas), acks & min.insync.replicas, unclean leader election, replica lag monitoring, preferred replica election, partition leadership rebalancing

---

*Cập nhật lần cuối: 2026-07-27*
