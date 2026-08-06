# PostgreSQL Replication & High Availability

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Chương này xây mental model và runbook cho
> physical streaming replication, logical replication, synchronous commit, failover,
> fencing, timeline, replication slot và `pg_rewind`.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md) ·
[Architecture & Storage](../fundamentals/architecture_storage.md) ·
[Transactions, MVCC & Locking](../fundamentals/transactions_mvcc.md) ·
[Performance & Autovacuum](../performance/tuning_autovacuum.md) ·
[Partitioning & Large Tables](../performance/partitioning_large_tables.md).

---

## 1. HA là bài toán giữ đúng dịch vụ khi có lỗi, không phải “có một replica”

Một standby chỉ là nguyên liệu. Hệ thống HA hoàn chỉnh còn phải trả lời:

- phát hiện primary thật sự hỏng hay chỉ mất mạng bằng cách nào;
- node nào được quyền trở thành primary mới;
- chặn primary cũ ghi tiếp ra sao;
- client chuyển endpoint thế nào;
- chấp nhận mất bao nhiêu transaction và gián đoạn bao lâu;
- đưa node cũ trở lại cụm mà không tạo hai lịch sử dữ liệu thế nào.

```text
replica + health check + consensus/quorum + fencing
        + promotion + client routing + runbook + drill
        = một thiết kế HA có thể vận hành
```

PostgreSQL cung cấp cơ chế replication và promotion, nhưng không tự cung cấp toàn bộ control
plane để phát hiện lỗi, bầu leader, fencing và đổi endpoint.

---

## 2. Bắt đầu từ failure model

Thiết kế phải nêu rõ những lỗi cần chịu được:

| Sự cố | Câu hỏi phải trả lời |
|---|---|
| PostgreSQL process chết | supervisor có restart hay failover ngay? |
| VM/node chết | standby nằm trên failure domain khác chưa? |
| Disk/data directory hỏng | replica có bản sao độc lập thật sự không? |
| Mất mạng một chiều | bên nào được quyền ghi, ai thực hiện fencing? |
| Mất cả availability zone | quorum và synchronous standby được đặt ở đâu? |
| Lỗi người dùng/DDL/xóa nhầm | backup/PITR ở đâu? Replica cũng nhận lỗi này |
| Region mất hoàn toàn | RPO liên vùng và thời gian đổi traffic là bao nhiêu? |

Nếu primary và standby dùng cùng host, cùng storage hoặc cùng failure domain, số node tăng nhưng
khả năng chịu lỗi cần thiết có thể không tăng.

---

## 3. RPO và RTO là contract đo được

- **RPO** (*Recovery Point Objective*): có thể mất tối đa bao nhiêu dữ liệu đã commit.
- **RTO** (*Recovery Time Objective*): dịch vụ được phép gián đoạn bao lâu.

Ví dụ:

```text
RPO <= 5 giây
RTO <= 2 phút
```

Contract này phải được kiểm chứng bằng lag thực tế và failover drill. “Streaming gần real-time”
không tự chứng minh RPO bằng 0; “auto failover” cũng không chứng minh RTO nếu DNS, connection pool
và application retry mất nhiều phút mới hội tụ.

---

## 4. Physical replication, logical replication và backup giải ba bài toán khác nhau

| Cơ chế | Đơn vị sao chép | Điểm mạnh | Không thay thế |
|---|---|---|---|
| Physical streaming | WAL/block của cả cluster | standby gần giống primary, HA tốt | backup/PITR, lọc từng bảng |
| Logical replication | thay đổi row theo publication | chọn bảng/cột/row, khác major/platform | DDL đầy đủ, sequence, HA vật lý |
| Backup + WAL archive | ảnh chụp và lịch sử WAL | khôi phục xóa nhầm, PITR, bản sao độc lập | failover tức thời |

Physical standby nhận cả lỗi logic đã ghi WAL. Nếu chạy `DROP TABLE` nhầm, thay đổi đó cũng được
replay. Vì vậy:

> Replica giúp tiếp tục chạy khi hạ tầng hỏng; backup giúp quay lại trước lỗi dữ liệu.

---

## 5. Mental model WAL, LSN và timeline

Primary ghi thay đổi vào WAL. Mỗi vị trí WAL được biểu diễn bằng **LSN** (*Log Sequence Number*).
Standby lần lượt nhận, ghi, flush và replay WAL.

```text
primary WAL
    │ send
    ▼
standby receive → write → flush → replay → query mới nhìn thấy
```

Khi standby được promote, PostgreSQL tạo **timeline** mới. Timeline diễn tả một nhánh lịch sử WAL,
không phải timestamp. Primary cũ và primary mới sau điểm rẽ không thể ghép dữ liệu bằng cách copy
vài WAL file tùy ý.

---

## 6. Bốn vị trí lag trả lời bốn loại bottleneck

Trên primary, `pg_stat_replication` cung cấp:

| Vị trí | Ý nghĩa gần đúng |
|---|---|
| `sent_lsn` | WAL sender đã gửi đến đâu |
| `write_lsn` | standby đã ghi vào OS đến đâu |
| `flush_lsn` | standby đã flush bền đến đâu |
| `replay_lsn` | standby đã apply/hiển thị đến đâu |

Diễn giải:

```text
current - sent    → WAL sender/primary chưa gửi kịp
sent - write      → network hoặc receiver chậm
write - flush     → storage flush phía standby chậm
flush - replay    → replay/I/O/CPU/conflict phía standby chậm
```

Đây là chỉ dấu điều tra, không phải phép chứng minh nguyên nhân duy nhất.

---

## 7. Streaming replication bất đồng bộ là mặc định

Ở chế độ mặc định, primary có thể xác nhận commit trước khi standby nhận/flush WAL. Nếu primary mất
hoàn toàn tại đúng thời điểm đó, các transaction đã được client nhận `COMMIT` có thể chưa tồn tại
trên standby được promote.

```text
client ← COMMIT OK
primary ── WAL chưa tới standby ──X primary mất
```

RPO của async replication phụ thuộc lag đúng lúc failover. Lag trung bình thấp không loại bỏ tail
lag khi network, checkpoint, bulk load hoặc storage chậm.

---

## 8. Kiến trúc tối thiểu nên tách data plane và control plane

```text
                         ┌──────── control plane ────────┐
                         │ health + quorum + fencing     │
                         └───────────┬───────────────────┘
                                     │ promote/route
app → stable write endpoint → primary ─── WAL ───► standby
             │                                      │
             └──────── read endpoint ───────────────┘
```

- **Data plane**: PostgreSQL, WAL stream, query traffic.
- **Control plane**: quyết định ai là leader, lưu trạng thái/quorum, fencing và đổi route.

Không đặt quyết định leader chỉ trong hai database node: khi đường mạng giữa chúng đứt, cả hai đều
có thể tin node kia chết.

---

## 9. Primary cần đủ WAL sender và slot budget

Cấu hình khởi đầu minh họa:

```conf
# postgresql.conf trên mọi node, để standby đã promote sẵn sàng làm primary
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
```

Budget phải gồm:

- physical standby trực tiếp;
- base backup đang stream WAL;
- logical subscriber/decoder;
- công cụ nhận WAL;
- headroom cho rebuild, maintenance và failover.

Các tham số này cần restart khi thay đổi theo yêu cầu của phiên bản; không đợi đến lúc incident mới
phát hiện hết slot hoặc WAL sender.

---

## 10. Replication role là quyền nhạy cảm

Dùng role riêng, không dùng superuser ứng dụng:

```sql
CREATE ROLE repl_physical
WITH LOGIN REPLICATION;
```

Ví dụ `pg_hba.conf` giới hạn đúng subnet/node:

```conf
hostssl  replication  repl_physical  10.20.30.41/32  scram-sha-256
```

WAL có thể chứa dữ liệu đặc quyền, nên cần TLS, network policy, secret rotation và audit. Không ghi
password thật trong repository hay command history; provision secret/verifier qua quy trình quản lý
secret, rồi dùng `.pgpass` được bảo vệ hoặc cơ chế tương đương ở standby.

---

## 11. Bootstrap standby bằng base backup nhất quán

Ví dụ minh họa:

```bash
pg_basebackup \
  --host=primary.internal \
  --username=repl_physical \
  --pgdata=/var/lib/postgresql/18/main \
  --format=plain \
  --wal-method=stream \
  --slot=standby_a \
  --create-slot \
  --write-recovery-conf \
  --progress
```

`--write-recovery-conf` (`-R`) tạo `standby.signal` và ghi connection/slot setting vào
`postgresql.auto.conf`. `pg_basebackup` sao chép cả cluster, không chọn riêng một database.

Trong production cần thêm:

- truyền secret an toàn;
- kiểm tra tablespace mapping và dung lượng;
- giới hạn tác động I/O/network;
- theo dõi `pg_stat_progress_basebackup`;
- xác minh backup manifest bằng `pg_verifybackup` khi phù hợp.

---

## 12. `standby.signal` quyết định server vào standby mode

Khi khởi động và thấy `standby.signal`, PostgreSQL chạy recovery liên tục. Một cấu hình điển hình:

```conf
primary_conninfo = 'host=primary.internal port=5432 user=repl_physical application_name=standby_a sslmode=verify-full'
primary_slot_name = 'standby_a'
recovery_target_timeline = 'latest'
hot_standby = on
```

`application_name` còn được dùng để nhận diện standby trong synchronous replication. Đừng copy
nguyên config chứa identity/endpoint cũ sang node mới mà không rà lại.

---

## 13. Standby thử nhiều nguồn WAL theo vòng lặp

Trong standby mode, PostgreSQL tìm WAL theo thứ tự khái quát:

1. WAL archive qua `restore_command`;
2. WAL đã có trong `pg_wal`;
3. streaming qua `primary_conninfo`.

Khi một nguồn hết hoặc lỗi, standby quay lại thử tiếp cho đến khi bị stop hoặc promote. Vì vậy WAL
archive độc lập có thể giúp standby bắt kịp nếu stream mất và primary đã recycle segment cũ.

`recovery_target_timeline = 'latest'` là mặc định phù hợp để standby theo timeline mới sau failover.

---

## 14. Xác định role từ server, không đoán từ hostname

```sql
SELECT pg_is_in_recovery();
SHOW in_hot_standby;
SHOW transaction_read_only;
```

Diễn giải thông thường:

- `pg_is_in_recovery() = true`: server đang recovery/standby;
- `in_hot_standby = on`: session đang trên hot standby;
- sau promotion, recovery kết thúc và server có thể nhận write.

Health check write endpoint nên xác minh role, không chỉ kiểm tra TCP 5432 mở.

---

## 15. Monitor trực tiếp từ primary bằng `pg_stat_replication`

```sql
SELECT application_name,
       client_addr,
       state,
       sync_state,
       sent_lsn,
       write_lsn,
       flush_lsn,
       replay_lsn,
       write_lag,
       flush_lag,
       replay_lag,
       reply_time
FROM pg_stat_replication
ORDER BY application_name;
```

View này chỉ có một dòng cho mỗi WAL sender kết nối **trực tiếp**. Primary không tự hiện các
downstream standby nằm sau một cascading standby.

---

## 16. Đo byte lag bằng phép trừ LSN

```sql
SELECT application_name,
       pg_size_pretty(
         pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)
       ) AS replay_byte_lag
FROM pg_stat_replication
WHERE state = 'streaming';
```

Byte lag hữu ích để ước lượng backlog và thời gian catch-up theo replay throughput. Nhưng cùng 1 GB
WAL có thể replay nhanh/chậm khác nhau tùy loại thay đổi, storage, full-page image và contention.

Đừng alert chỉ bằng một ngưỡng byte cố định; kết hợp:

- tốc độ sinh WAL;
- xu hướng lag;
- thời gian từ lần reply cuối;
- disk headroom;
- RPO/RTO và recovery rate đã đo.

---

## 17. Các cột `*_lag` không phải backlog timer tuyệt đối

`write_lag`, `flush_lag`, `replay_lag` ước lượng độ trễ gần đây của từng giai đoạn đối với WAL commit.
Khi hệ thống không phát sinh transaction mới hoặc vừa bắt kịp, giá trị có thể giữ lại một lúc rồi
thành `NULL`.

Không diễn giải `replay_lag = NULL` thành “replica khỏe”. Có thể standby không còn kết nối. Luôn kiểm
tra `state`, LSN, `reply_time`, receiver và end-to-end probe.

---

## 18. Monitor trên standby bằng `pg_stat_wal_receiver`

```sql
SELECT status,
       sender_host,
       sender_port,
       slot_name,
       written_lsn,
       flushed_lsn,
       latest_end_lsn,
       latest_end_time
FROM pg_stat_wal_receiver;
```

Kết hợp thêm:

```sql
SELECT pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();
```

`now() - pg_last_xact_replay_timestamp()` chỉ có nghĩa khi primary có transaction đều. Trên hệ thống
nhàn, nó tăng dù replica hoàn toàn bắt kịp; cần heartbeat transaction nếu muốn đo freshness theo thời
gian một cách có chủ đích.

---

## 19. Replication slot là lời hứa giữ tài nguyên cho consumer

Physical slot giữ WAL cần cho standby. Logical slot còn có thể giữ WAL và catalog row cần cho logical
decoding. Lợi ích là consumer ngắt kết nối vẫn có thể tiếp tục từ vị trí cũ; rủi ro là primary giữ
tài nguyên vô hạn nếu consumer biến mất mà slot còn tồn tại.

```sql
SELECT slot_name,
       slot_type,
       active,
       restart_lsn,
       confirmed_flush_lsn,
       wal_status,
       safe_wal_size,
       inactive_since,
       invalidation_reason
FROM pg_replication_slots
ORDER BY slot_name;
```

Slot là resource có owner, SLA và lifecycle; không phải checkbox “an toàn hơn”.

---

## 20. Hiểu `wal_status` trước khi disk đầy

| Trạng thái | Ý nghĩa vận hành |
|---|---|
| `reserved` | WAL cần giữ còn nằm trong phạm vi `max_wal_size` |
| `extended` | đã vượt `max_wal_size` nhưng vẫn được slot/`wal_keep_size` giữ |
| `unreserved` | slot không còn giữ được một phần WAL; segment có thể bị xóa ở checkpoint tiếp theo |
| `lost` | slot không còn dùng được |

`safe_wal_size` cho biết còn có thể ghi khoảng bao nhiêu byte WAL trước khi slot có nguy cơ thành
`lost`; nó là `NULL` khi slot đã mất hoặc `max_slot_wal_keep_size = -1`.

Alert sớm theo tốc độ WAL:

```text
time_to_slot_danger ≈ safe_wal_size / current_wal_bytes_per_second
```

---

## 21. Giới hạn retention của slot là trade-off có chủ đích

```conf
max_slot_wal_keep_size = '100GB'
```

- `-1` cho phép slot giữ WAL không giới hạn: consumer dễ catch-up hơn nhưng có thể làm đầy disk.
- giới hạn hữu hạn bảo vệ primary: consumer quá chậm có thể mất WAL và phải rebuild/resync.

Chọn giá trị từ:

```text
peak WAL rate × thời gian outage cần chịu + safety margin
```

Và vẫn cần alert dung lượng `pg_wal`; giới hạn không thay thế capacity monitoring.

---

## 22. PostgreSQL 18 có thể vô hiệu hóa slot idle quá lâu

```conf
idle_replication_slot_timeout = '24h'
```

PostgreSQL 18 bổ sung khả năng invalidate replication slot không hoạt động quá thời gian cấu hình.
Khi xảy ra, `pg_replication_slots.invalidation_reason` có thể là `idle_timeout`.

“Không hoạt động” ở đây nghĩa là slot không được replication connection sử dụng, không phải connection
vẫn mở nhưng tạm thời không có change. Invalidation diễn ra tại checkpoint nên có thể muộn hơn timeout.
Cơ chế này không áp dụng cho slot không reserve WAL hoặc logical slot đang được sync trên standby
(`synced = true`).

Đây là guardrail, không phải garbage collector để bật tùy ý:

- consumer hợp lệ có lịch dừng dài có thể bị mất slot;
- timeout cần lớn hơn maintenance/outage window;
- team phải có runbook tái tạo subscriber/standby khi slot bị invalidate.

---

## 23. `wal_keep_size`, slot và WAL archive không giống nhau

| Cơ chế | Contract |
|---|---|
| `wal_keep_size` | giữ tối thiểu một lượng WAL gần đây, không gắn riêng consumer |
| replication slot | giữ theo tiến độ cụ thể của consumer, có rủi ro disk retention |
| WAL archive | lưu segment ra kho độc lập để recovery/catch-up theo retention policy |

Một thiết kế mạnh có thể dùng slot để stream liên tục và archive để có đường phục hồi độc lập. Không
xóa archive theo nhu cầu một standby nếu archive còn phục vụ PITR cho backup.

---

## 24. Cascading replication giảm tải kết nối và băng thông upstream

```text
primary ──► standby_region_a ──► standby_a2
    └────► standby_region_b ──► standby_b2
```

Mỗi standby chỉ kết nối một upstream, nhưng có thể stream tiếp cho downstream. Giá phải trả:

- downstream có thêm hop và lag;
- primary chỉ thấy standby trực tiếp;
- cascading streaming hiện là asynchronous;
- failure/runbook phải biết đổi upstream và theo timeline mới.

Named synchronous standby phải kết nối trực tiếp primary; downstream không thể trực tiếp thỏa ack
cho commit trên primary.

---

## 25. Synchronous replication đổi latency lấy durability acknowledgment

```conf
synchronous_standby_names = 'FIRST 1 (standby_a, standby_b)'
```

Với `synchronous_commit = on` mặc định cho transaction, commit đợi một standby được chọn xác nhận WAL
đã được flush bền. RTT, flush latency và queue phía standby đi vào latency của write.

Quan trọng: synchronous replication bảo đảm PostgreSQL **không trả thành công cho client** trước ack
yêu cầu. Sau một kết nối bị đứt đúng lúc commit, client vẫn có thể không biết transaction đã commit
hay chưa; retry phải idempotent.

---

## 26. Các mức `synchronous_commit` là các contract khác nhau

| Giá trị | Primary chờ gì | Ghi chú |
|---|---|---|
| `off` | không nhất thiết đợi local WAL flush | có thể mất recent commit khi primary crash |
| `local` | local durable flush | không đợi standby |
| `remote_write` | standby ghi vào OS | chưa bảo đảm standby flush disk |
| `on` | standby durable flush | lựa chọn sync phổ biến |
| `remote_apply` | standby đã replay | query snapshot mới trên standby có thể thấy commit |

`remote_apply` có thể hỗ trợ causal read trong topology đơn giản, nhưng latency gồm cả replay. Nó
không tự thiết kế read routing, session consistency hay retry cho ứng dụng.

---

## 27. `FIRST` và `ANY` chọn standby theo hai chiến lược

```conf
# Ưu tiên: đợi 2 standby có thứ tự ưu tiên cao nhất đang đủ điều kiện
synchronous_standby_names = 'FIRST 2 (az_a, az_b, az_c)'

# Quorum: đợi bất kỳ 2 trong 3 standby
synchronous_standby_names = 'ANY 2 (az_a, az_b, az_c)'
```

- `FIRST`: dễ biểu đạt preferred local/remote candidate; standby sau làm dự phòng.
- `ANY`: commit dùng quorum phản hồi nhanh trong tập ứng viên.

Tên được so với `application_name`. Kiểm tra thực tế bằng `pg_stat_replication.sync_state` và
`sync_priority`, không chỉ nhìn file cấu hình.

---

## 28. Synchronous commit có thể làm write dừng vô hạn

Nếu số synchronous standby cần thiết không còn phản hồi, transaction commit có thể tiếp tục chờ.
Trong lúc chờ, transaction lock vẫn được giữ, làm contention lan rộng.

Runbook phải chọn trước:

1. chờ standby trở lại để giữ durability contract;
2. giảm quorum/tắt sync để ưu tiên availability và chấp nhận RPO mới;
3. failover sang phía còn quorum nếu primary bị cô lập.

Thay config trong incident là quyết định business về durability, không phải mẹo performance vô hại.

---

## 29. Có thể chọn durability theo transaction

```sql
BEGIN;
SET LOCAL synchronous_commit = 'remote_apply';

INSERT INTO payments(...);

COMMIT;
```

Workload có thể dùng mức mạnh cho ledger/payment và mức nhẹ hơn cho telemetry tái tạo được. Contract
phải được code review, test và quan sát; không để một thư viện âm thầm `SET synchronous_commit = off`
trên cả connection pool.

---

## 30. Read replica là eventually consistent theo mặc định

Sau khi write thành công trên primary, đọc ngay từ async standby có thể chưa thấy row mới:

```text
write(primary) → COMMIT OK → read(standby) → old snapshot
```

Các chiến lược:

- read-your-writes từ primary trong một cửa sổ/session;
- truyền LSN token và chờ replica replay đến LSN đó;
- dùng `remote_apply` cho transaction cần contract này;
- cho phép stale read rõ ràng ở use case reporting/catalog.

Không gắn nhãn chung “read endpoint” mà không định nghĩa freshness SLA.

---

## 31. Hot standby chỉ cho phép read nghiêm ngặt

Hot standby nhận `SELECT`, nhưng không cho DML/DDL, `nextval()`, `LISTEN`/`NOTIFY`, tạo temp table hay
`SELECT ... FOR UPDATE`. Nó không giống một primary được đặt `default_transaction_read_only`.

Application cần tránh route sang standby các request có side effect ẩn như:

- ORM tự cập nhật sequence;
- session setup tạo temp table;
- advisory workflow cần write;
- query dùng row lock.

Sau promotion, session đang kết nối có thể chuyển sang trạng thái bình thường, nhưng application vẫn
cần refresh routing/role awareness theo thiết kế.

---

## 32. Query standby và WAL replay có thể xung đột

Ví dụ primary đã vacuum row version mà query dài trên standby vẫn cần nhìn thấy. Standby phải chọn:

- trì hoãn replay, làm dữ liệu stale hơn; hoặc
- cancel query để replay tiếp.

Hai giới hạn chính:

```conf
max_standby_streaming_delay = '30s'
max_standby_archive_delay = '30s'
```

Giới hạn là tổng thời gian apply WAL đã bị trì hoãn, không phải mỗi query luôn được đủ 30 giây. Một
standby dành cho HA nên ưu tiên replay; một replica reporting có thể chọn khác nhưng không nên đồng
thời là failover candidate tốt nhất.

---

## 33. `hot_standby_feedback` chuyển áp lực cleanup về primary

```conf
hot_standby_feedback = on
```

Feedback giúp primary tránh vacuum bỏ row version standby còn cần, giảm recovery conflict. Đổi lại,
long query hoặc standby lag có thể giữ dead tuple trên primary và gây bloat.

Đây không phải “bật là tốt”:

- đặt timeout cho reporting query;
- theo dõi dead tuple/bloat và xmin horizon;
- tách HA replica khỏi analytics replica nếu SLA xung đột;
- hiểu feedback có thể gián đoạn khi standby mất kết nối.

---

## 34. Đo recovery conflict trên chính standby

```sql
SELECT datname,
       confl_tablespace,
       confl_lock,
       confl_snapshot,
       confl_bufferpin,
       confl_deadlock
FROM pg_stat_database_conflicts
ORDER BY datname;
```

Kết hợp:

```conf
log_recovery_conflict_waits = on
```

Counter là cumulative; đọc theo delta cùng timestamp reset. Phân biệt query bị cancel vì recovery
conflict với statement timeout, application cancel hay failover connection reset.

---

## 35. Pause replay là công cụ sắc bén

`pg_wal_replay_pause()` có thể hữu ích khi điều tra hoặc giữ một recovery point, nhưng standby vẫn có
thể tiếp tục nhận WAL trong khi không replay. Hệ quả:

- replay lag tăng;
- `pg_wal`/slot/archive pressure tăng;
- node trở thành failover candidate kém;
- read freshness giảm.

Mọi thao tác pause phải có owner, deadline, alert và bước `pg_wal_replay_resume()`. Không dùng như
cách giữ “bản sao trước lỗi” thay backup/PITR.

---

## 36. Promotion tạo primary mới và timeline mới

```sql
SELECT pg_promote(wait => true, wait_seconds => 60);
```

Hoặc:

```bash
pg_ctl promote -D /var/lib/postgresql/18/main
```

Promotion không tự:

- xác minh primary cũ đã bị fence;
- chọn candidate có WAL mới nhất;
- đổi endpoint client;
- sửa synchronous topology;
- rewind/rebuild primary cũ;
- chứng minh không mất transaction.

Do đó không đưa lệnh promote rời rạc thành “runbook failover”.

---

## 37. Switchover khác failover

| Thuộc tính | Switchover | Failover |
|---|---|---|
| Primary cũ | còn kiểm soát được | có thể chết/mất liên lạc |
| Có thể dừng write sạch | thường có | không chắc |
| Đồng bộ WAL cuối | chủ động xác minh | chọn candidate tốt nhất hiện có |
| Rủi ro mất dữ liệu | có thể gần 0 | theo replication state/RPO |
| Fencing | vẫn cần | bắt buộc, khó hơn |

Rehearse switchover trước vì nó kiểm tra phần lớn đường promotion/routing với rủi ro thấp hơn. Nhưng
đừng coi đó là bằng chứng đầy đủ cho network partition hay primary mất đột ngột.

---

## 38. PostgreSQL không tự quyết định primary đã chết

Một health check thất bại có thể do:

- PostgreSQL chết;
- host chết;
- network giữa checker và primary lỗi;
- DNS/TLS/auth lỗi;
- primary bận và timeout;
- checker bị cô lập trong khi primary vẫn phục vụ client khác.

Control plane cần nhiều tín hiệu và quorum/witness độc lập. Failover quá nhanh làm tăng nguy cơ false
positive; quá chậm làm tăng RTO. Threshold phải dựa trên SLA và failure drill, không copy mặc định
của một blog.

---

## 39. Fencing là điều kiện trước khi cho primary mới nhận write

**Fencing** bảo đảm primary cũ không thể tiếp tục ghi. Cách thực hiện phụ thuộc hạ tầng:

- tắt/STONITH VM hoặc host;
- revoke network/storage lease;
- cô lập port/network policy;
- tháo endpoint và chặn application credential;
- dùng distributed lock/lease do control plane quản lý.

Chỉ “không ping được primary cũ” không phải fencing. Nếu không thể chứng minh nó mất quyền ghi,
promotion có thể tạo split-brain.

---

## 40. Split-brain tạo hai lịch sử hợp lệ cục bộ nhưng xung đột toàn cục

```text
              network partition
primary A  X────────────────────X  standby B
   │ vẫn nhận write                  │ promote và nhận write
   └──── timeline/history A          └──── timeline/history B
```

Physical replication không có cơ chế merge hai timeline thành một database đúng nghiệp vụ. Sau đó
thường phải chọn một phía làm nguồn chuẩn và reconcile dữ liệu phía kia bằng quy trình riêng, rất
khó và có thể không hoàn toàn tự động.

Phòng split-brain rẻ hơn chữa split-brain: quorum, fencing, một write endpoint và rehearsal.

---

## 41. Candidate tốt nhất không chỉ là node “đang chạy”

Đánh giá:

- replay LSN mới nhất và timeline phù hợp;
- `pg_is_in_recovery()` và receiver/replay health;
- không pause replay;
- disk đủ chỗ, không lỗi I/O;
- configuration/auth/archive sẵn sàng làm primary;
- logical failover slots đã sync nếu cần;
- topology/failure domain còn sống;
- application có thể route tới node.

Nếu nhiều standby async, chọn sai node có thể tăng data loss dù một node khác giữ WAL mới hơn.

---

## 42. Stable endpoint cần role-aware health check

Client không nên hard-code hostname node hiện tại. Có thể dùng proxy/load balancer/service discovery
hoặc virtual IP, nhưng health check write endpoint phải xác minh:

```sql
SELECT NOT pg_is_in_recovery() AS is_writable_primary;
```

Đồng thời bảo vệ bằng database permission và transaction mode; health check không phải authorization.

Đổi DNS đơn thuần có thể bị chậm bởi TTL, resolver cache, JVM DNS cache và connection pool còn giữ
socket cũ. RTO phải đo từ góc nhìn request thực, không dừng ở lúc `pg_promote()` trả về.

---

## 43. Connection pool và retry quyết định phần lớn RTO ứng dụng

Khi failover:

- connection cũ có thể treo rồi mới timeout;
- pool có thể trả lại connection chết;
- transaction đang chạy bị mất session;
- commit result có thể ambiguous;
- prepared/session state cần tạo lại.

Ứng dụng cần:

- connect/socket/query timeout hợp lý;
- evict connection lỗi;
- retry toàn transaction chỉ với lỗi transient phù hợp;
- idempotency key/outbox cho external side effect;
- không retry mù mọi SQLSTATE hoặc DDL.

---

## 44. Failback không phải “bật primary cũ lên lại”

Sau khi B được promote, A chứa lịch sử cũ. Khởi động A như primary sẽ tạo split-brain hoặc expose dữ
liệu stale. Quy trình đúng:

1. giữ A bị fence;
2. chọn B là source of truth;
3. rewind A hoặc tạo lại từ base backup của B;
4. cấu hình A theo B bằng slot/endpoint mới;
5. start A như standby và chờ catch-up;
6. chỉ cân nhắc switchover về A bằng một change riêng.

“Failback ngay để trở về kiến trúc cũ” thường làm incident dài và nguy hiểm hơn.

---

## 45. `pg_rewind` tái đồng bộ node đã diverge nhanh hơn full copy

`pg_rewind` so sánh timeline, tìm checkpoint trước điểm diverge rồi copy các block/file khác biệt từ
source sang target. Use case điển hình: primary cũ trở thành standby của primary mới.

Điều kiện quan trọng trên target từ trước:

- data checksums được bật **hoặc** `wal_log_hints = on`;
- `full_page_writes = on`;
- target dừng sạch;
- WAL cần từ checkpoint trước điểm diverge còn có thể lấy từ target/source/archive.

Nếu điều kiện không chắc, fresh base backup an toàn và dễ hiểu hơn.

---

## 46. Runbook `pg_rewind`

Khung thao tác, cần thay đường dẫn/credential theo môi trường:

```text
1. Fence và stop target cũ.
2. Xác minh source mới là primary đúng và có backup.
3. Chạy pg_rewind --dry-run nếu phiên bản/workflow hỗ trợ kiểm tra mong muốn.
4. Chạy pg_rewind với --target-pgdata và source server/data directory.
5. Rà lại config bị copy từ source.
6. Tạo standby.signal, sửa primary_conninfo/primary_slot_name.
7. Start như standby; xác minh timeline, receiver, replay và slot.
```

Ví dụ:

```bash
pg_rewind \
  --target-pgdata=/var/lib/postgresql/18/main \
  --source-server='host=new-primary.internal dbname=postgres user=rewind_user sslmode=verify-full' \
  --restore-target-wal \
  --progress
```

`pg_rewind` có thể copy configuration file từ source; sửa recovery config **trước khi restart** để
target không khởi động nhầm thành một primary mới.

---

## 47. Nếu rewind thất bại, ưu tiên tính đúng hơn tốc độ

Tài liệu PostgreSQL cảnh báo target data directory có thể không còn ở trạng thái dễ phục hồi sau một
lần `pg_rewind` thất bại. Không lặp lệnh mù hoặc start thử.

Quyết định:

- nếu biết chính xác thiếu WAL và archive còn giữ: sửa đường lấy WAL theo runbook đã test;
- nếu integrity không chắc: bỏ target copy và tạo fresh standby từ base backup;
- luôn giữ source primary ổn định, không “sửa” cả hai phía cùng lúc.

Một rebuild chậm nhưng có thể chứng minh đúng thường tốt hơn một shortcut không thể chứng minh.

---

## 48. Replica rebuild là hoạt động capacity lớn

Fresh base backup tạo tải đọc primary/source, tải network, write/I/O standby và WAL mới trong lúc copy.
Nếu copy mất lâu hơn retention window, standby mới có thể thiếu WAL trước khi start.

Lập budget:

```text
copy_duration ≈ cluster_bytes / effective_copy_throughput
required_WAL_retention >= peak_WAL_rate × copy_duration + margin
```

Theo dõi progress, slot retention, archive health và disk hai phía. Rebuild trong giờ cao điểm có thể
làm primary đang khỏe trở thành sự cố thứ hai.

---

## 49. Logical replication làm việc ở mức row/object

```text
publisher: publication
      │ logical decoding + slot
      ▼
subscriber: subscription → apply worker → target tables
```

Use case phù hợp:

- chọn một tập bảng/cột/row;
- nâng major theo blue-green;
- chuyển đổi platform;
- đưa dữ liệu sang reporting/integration database;
- hợp nhất dữ liệu có thiết kế conflict rõ ràng.

Logical replication không phải mặc định tốt hơn physical HA: nó có nhiều schema, key và conflict
contract hơn.

Publisher phải dùng mức WAL phù hợp và đủ worker/slot budget:

```conf
wal_level = logical
max_replication_slots = 20
max_wal_senders = 24
```

Subscriber cũng cần budget cho `max_logical_replication_workers`, table synchronization/parallel apply
worker, replication origin và `max_worker_processes`; tính theo số subscription cùng initial copy peak.

---

## 50. Publication/subscription tối thiểu

Trên publisher:

```sql
CREATE PUBLICATION billing_pub
FOR TABLE billing.invoice, billing.payment;
```

Trên subscriber, schema/table phải tồn tại trước:

```sql
CREATE SUBSCRIPTION billing_sub
CONNECTION 'host=publisher.internal dbname=billing user=repl_logical sslmode=verify-full'
PUBLICATION billing_pub
WITH (
  copy_data = true,
  create_slot = true,
  enabled = true
);
```

Ví dụ bỏ password có chủ đích. Trong production dùng secret handling phù hợp và kiểm tra quyền
`SELECT` cần cho initial copy.

---

## 51. Initial copy là một phase riêng

Khi bắt đầu subscription, PostgreSQL thường chụp snapshot và copy dữ liệu hiện có, rồi apply thay
đổi phát sinh sau đó. Với bảng lớn, phase này có thể:

- tốn network/I/O;
- tạo nhiều table-sync worker/slot;
- cạnh tranh autovacuum và workload;
- thất bại nếu schema/constraint subscriber không tương thích;
- kéo dài thời điểm subscriber thật sự ready.

Theo dõi `pg_stat_subscription`, `pg_subscription_rel`, log và slot; đừng coi `CREATE SUBSCRIPTION`
thành công là migration đã hoàn tất.

---

## 52. `REPLICA IDENTITY` giúp tìm row cho UPDATE/DELETE

Mặc định primary key là replica identity. Nếu không có key phù hợp, publication có UPDATE/DELETE sẽ
không hoạt động đúng contract.

```sql
ALTER TABLE billing.invoice
REPLICA IDENTITY USING INDEX invoice_external_id_uq;
```

Hoặc bất đắc dĩ:

```sql
ALTER TABLE billing.invoice REPLICA IDENTITY FULL;
```

`FULL` gửi/so khớp toàn row và có thể đắt; datatype không có operator class B-tree/Hash mặc định còn
có giới hạn apply. Ưu tiên key nhỏ, ổn định, unique và `NOT NULL`.

---

## 53. DDL, sequence và large object không tự được replicate

Giới hạn PostgreSQL 18 quan trọng:

- schema/DDL không replicate;
- sequence state không replicate;
- large object không replicate;
- view, materialized view và foreign table không phải target logical replication;
- `TRUNCATE` có thể lỗi khi foreign key liên quan bảng ngoài subscription;
- table/partition target phải tương thích với publication contract.

Identity/serial column value trong row vẫn được copy, nhưng sequence phía subscriber có thể còn thấp.
Trước khi cho subscriber nhận write sau migration, phải đồng bộ/đặt lại sequence an toàn.

---

## 54. Schema migration nên additive ở subscriber trước

Với thay đổi tương thích:

```text
1. Add nullable column/type-compatible object ở subscriber.
2. Add tương ứng ở publisher.
3. Deploy producer ghi shape mới.
4. Backfill/validate.
5. Contract/drop cột cũ sau khi mọi consumer đã rời đi.
```

Nếu publisher gửi row không fit schema subscriber, apply dừng cho đến khi schema được sửa. DDL tool
phải biết thứ tự hai phía; không chạy cùng một migration mù quáng nếu subscriber có topology khác.

---

## 55. Row filter và column list giảm scope, không thay security review

Ví dụ:

```sql
CREATE PUBLICATION active_customer_pub
FOR TABLE crm.customer (customer_id, email, status)
WHERE (status = 'ACTIVE');
```

Lưu ý:

- filter có quy tắc riêng cho UPDATE và partition;
- publication có UPDATE/DELETE thì column list phải chứa replica identity;
- `FOR TABLES IN SCHEMA` không hỗ trợ column list;
- đổi filter/list là data contract migration;
- dữ liệu cũ ở subscriber không tự biến mất chỉ vì filter mới hẹp hơn.

Không dùng publication như lớp kiểm soát truy cập duy nhất cho dữ liệu nhạy cảm.

---

## 56. Partitioned table có hai cách biểu diễn logical change

Mặc định change phát từ leaf partition, nên target tương ứng phải tồn tại. Với:

```sql
CREATE PUBLICATION event_pub
FOR TABLE events
WITH (publish_via_partition_root = true);
```

Change dùng identity/schema của root, cho phép subscriber có partition layout khác hoặc table không
partition. Nhưng cần kiểm tra row filter, column list và `TRUNCATE` trực tiếp trên leaf; khi
`publish_via_partition_root = true`, truncate trực tiếp leaf không được replicate theo contract đó.

---

## 57. Subscriber có write riêng thì conflict trở thành bài toán dữ liệu

Logical apply giống DML lên subscriber. Một số conflict:

- insert/update vi phạm unique constraint: apply error và dừng;
- UPDATE/DELETE không tìm thấy row: change bị skip;
- permission/RLS không cho apply;
- row đã được nguồn khác sửa;
- schema/type/constraint khác publisher.

PostgreSQL 18 ghi thống kê conflict trong `pg_stat_subscription_stats`; chi tiết nằm trong subscriber
log. Không quảng bá built-in logical replication thành active-active tự động.

---

## 58. Skip transaction conflict có thể làm mất thay đổi hợp lệ

`ALTER SUBSCRIPTION ... SKIP` có thể bỏ qua toàn transaction tại finish LSN. Transaction đó có thể
chứa nhiều row không conflict, nên skip dễ làm subscriber không nhất quán.

Runbook ưu tiên:

1. dừng/disable apply nếu cần;
2. lưu log, origin, finish LSN và conflicting row;
3. quyết định publisher-wins/subscriber-wins theo business contract;
4. sửa data/permission/schema;
5. chỉ skip khi đã đánh giá toàn transaction;
6. re-enable và xác minh checksum/count/business invariant.

---

## 59. Monitor logical replication ở cả hai phía

Subscriber:

```sql
SELECT subname,
       worker_type,
       relid::regclass,
       received_lsn,
       latest_end_lsn,
       latest_end_time
FROM pg_stat_subscription
ORDER BY subname, worker_type, relid;
```

Conflict:

```sql
SELECT *
FROM pg_stat_subscription_stats
ORDER BY subname;
```

Publisher:

```sql
SELECT slot_name,
       active,
       restart_lsn,
       confirmed_flush_lsn,
       wal_status,
       safe_wal_size
FROM pg_replication_slots
WHERE slot_type = 'logical';
```

Kiểm tra thêm table sync state và log; một main apply worker khỏe không chứng minh mọi table đã sync.

---

## 60. Logical replication security cần quyền tối thiểu ở hai phía

Connection role trên publisher cần `LOGIN REPLICATION`, được phép qua `pg_hba.conf`, và cần `SELECT`
trên published table cho initial copy. Nếu role không phải `BYPASSRLS`/superuser, RLS phía publisher
có thể được áp dụng.

Với table owner không hoàn toàn tin cậy, tài liệu đề xuất cân nhắc:

```text
options=-crow_security=off
```

để replication dừng thay vì âm thầm chạy policy do owner thêm. Phía subscriber, apply chạy với quyền
của subscription owner; permission hoặc RLS không phù hợp có thể làm replication conflict.

---

## 61. Logical subscription cũng cần failover plan cho publisher

Nếu publisher physical primary failover, logical slot thông thường không tự xuất hiện đúng trạng thái
trên primary mới. PostgreSQL hỗ trợ **logical failover slots** để sync slot sang physical standby.

Trên subscriber:

```sql
CREATE SUBSCRIPTION billing_sub
CONNECTION 'host=publisher-write.internal dbname=billing user=repl_logical sslmode=verify-full'
PUBLICATION billing_pub
WITH (failover = true);
```

Slot sync là asynchronous. Bật `failover = true` chưa đủ chứng minh standby đã ready.

---

## 62. Cấu hình đồng bộ logical failover slot

Luồng khái quát:

```text
subscriber consumes logical slot
              ▲
publisher primary ── physical slot ──► publisher standby
       │                                  │
       └── failover logical slot ─sync───►│
```

Các mảnh cấu hình chính:

```conf
# Publisher primary: logical sender chỉ tiến khi physical slot này đã giữ WAL
synchronized_standby_slots = 'publisher_standby_a'

# Publisher physical standby
primary_slot_name = 'publisher_standby_a'
primary_conninfo = 'host=publisher-primary.internal dbname=postgres user=repl_physical sslmode=verify-full'
hot_standby_feedback = on
sync_replication_slots = on
```

Physical slot nêu trong `synchronized_standby_slots` phải tồn tại và hợp lệ. Nếu nó thiếu/hỏng,
logical replication có thể block. `primary_conninfo` phải chứa `dbname` hợp lệ; physical slot và
`hot_standby_feedback` giúp giữ WAL/catalog row mà logical slot cần. Cần capacity và availability
design cho chính cơ chế bảo vệ này.

---

## 63. Xác minh failover-ready trước khi promote publisher standby

Trên standby sắp promote, mọi slot cần thiết phải thỏa:

```sql
SELECT slot_name,
       synced,
       temporary,
       invalidation_reason,
       (synced AND NOT temporary AND invalidation_reason IS NULL)
         AS failover_ready
FROM pg_replication_slots
WHERE slot_name IN ('billing_sub');
```

Phải xét cả table synchronization slot khi initial copy liên quan. Vì sync bất đồng bộ, “đã cấu hình”
không đồng nghĩa “đã sẵn sàng”. Sau promotion, đổi subscription connection về primary mới, thường nên
disable subscription trước, đổi connection rồi enable theo runbook.

---

## 64. Multi-master không xuất hiện chỉ vì nối nhiều publication

Bidirectional/multi-master cần giải quyết:

- loop prevention/replication origin;
- key generation không đụng nhau;
- write ownership và conflict resolution;
- sequence;
- DDL ordering;
- partition/filter semantics;
- latency và read consistency;
- node quay lại sau outage.

Built-in logical replication cung cấp primitive, không cung cấp business conflict resolver tổng quát.
Nếu không có yêu cầu thật sự, một write primary với HA thường đơn giản và an toàn hơn.

---

## 65. Monitoring tối thiểu cho HA

Không phụ thuộc một dashboard cụ thể, cần có tín hiệu:

| Nhóm | Tín hiệu |
|---|---|
| Role | recovery/primary state, timeline, unexpected writable node |
| Stream | sender/receiver state, last reply, reconnect count |
| Lag | sent/write/flush/replay byte và trend |
| Slot | active, retained WAL, `wal_status`, `safe_wal_size`, invalidation |
| Storage | `pg_wal` bytes/free disk, archive backlog/failure |
| Replay | replay paused, recovery conflicts, replay throughput |
| Sync | `sync_state`, waiting commits, required standby count |
| Logical | worker/table sync state, conflict counters, apply error |
| Client | write/read endpoint success, reconnect/RTO, stale-read probe |

Alert phải dẫn tới runbook và owner. Dashboard đẹp nhưng không ai biết fence node nào vẫn không tạo HA.

---

## 66. Capacity planning dùng peak WAL rate

Đo ít nhất:

```text
WAL bytes/second ở peak
network throughput và RTT
standby write/flush/replay throughput
slot/archive retention window
base backup/rebuild throughput
disk headroom trong outage dài nhất
```

Điều kiện ổn định dài hạn:

```text
standby_replay_rate > primary_WAL_generation_rate
```

Nếu chỉ nhanh hơn ở trung bình nhưng chậm hơn trong peak kéo dài, lag sẽ tích lũy. Phải biết mất bao
lâu để catch-up sau peak, không chỉ biết lag cuối ngày về 0.

---

## 67. Failure modes thường gặp

| Failure mode | Hậu quả | Guardrail |
|---|---|---|
| promote khi primary cũ chưa fence | split-brain | quorum + fencing bắt buộc |
| slot consumer chết | `pg_wal` đầy | owner, `safe_wal_size`, timeout/limit, runbook |
| không có archive/slot đủ lâu | standby thiếu WAL | retention từ peak rate và outage window |
| sync quorum thiếu | write treo, lock giữ lâu | nhiều candidate, policy giảm quorum rõ ràng |
| reporting query dài trên HA replica | replay lag/cancel hoặc primary bloat | tách role, timeout, monitor conflict/xmin |
| DNS đổi nhưng pool giữ connection | RTO ứng dụng dài | role-aware proxy, timeout, pool eviction |
| start primary cũ sau failover | hai primary | fence, rewind/rebuild thành standby |
| logical DDL lệch | apply dừng | subscriber-first additive migration |
| sequence không sync khi cutover | duplicate key | sequence cutover checklist |
| logical slot chưa sync trước failover | subscriber không tiếp tục | kiểm tra `failover_ready` |
| replica được coi là backup | xóa nhầm lan sang mọi node | backup độc lập + PITR drill |

---

## 68. Decision matrix

| Nhu cầu chính | Lựa chọn khởi đầu |
|---|---|
| HA cùng major, toàn cluster | physical streaming standby |
| RPO gần 0 trong một failure domain hợp lý | synchronous physical standby + fencing |
| read scale chấp nhận stale | async hot standby |
| reporting query dài | replica riêng, không ưu tiên làm HA candidate |
| nâng major ít downtime | logical replication + schema/cutover plan |
| chỉ chọn một số bảng/row/cột | logical publication/subscription |
| khôi phục xóa nhầm/ransomware | backup + WAL archive/PITR |
| DR liên vùng | async standby/archive với RPO đo được |
| active-active | chỉ khi có conflict/key/DDL contract chuyên biệt |

Một hệ production thường dùng nhiều cơ chế, nhưng mỗi cơ chế phải có mục tiêu và owner riêng.

---

## 69. Runbook switchover có kế hoạch

Khung an toàn:

1. Thông báo change, freeze DDL/maintenance và xác minh backup/archive.
2. Xác minh target standby khỏe, đúng timeline/config, đủ disk và không pause replay.
3. Drain hoặc chặn write mới ở application/endpoint.
4. Chờ transaction đang chạy kết thúc; xử lý prepared transaction theo policy.
5. Xác minh target nhận/flush/replay đến LSN cuối cần thiết.
6. Fence hoặc stop primary cũ để nó không còn nhận write.
7. Promote target và xác minh nó thực sự writable.
8. Sửa synchronous topology/slot/archive config nếu cần.
9. Chuyển write endpoint; kiểm tra request end-to-end và business invariant.
10. Rewind/rebuild node cũ thành standby, chờ catch-up.
11. Mở lại read route/maintenance có kiểm soát.
12. Ghi RTO, lỗi, ambiguous transaction và cập nhật runbook.

Rollback trước promotion khác rollback sau promotion; sau timeline switch thường cần một switchover mới,
không đơn giản “đổi DNS ngược”.

---

## 70. Runbook failover ngoài kế hoạch

Khung điều tra/hành động:

1. Mở incident, ghi thời điểm và freeze automation xung đột.
2. Xác minh lỗi từ nhiều vantage point; xác định có network partition không.
3. Dùng quorum/control plane chọn phía có quyền tiếp tục.
4. **Fence primary cũ** bằng cơ chế có thể chứng minh.
5. So sánh candidate: timeline, replay LSN, health, logical slot readiness.
6. Ghi lại last known LSN/RPO evidence và chấp nhận data-loss decision nếu async.
7. Promote đúng một candidate.
8. Cấu hình lại sync/slot/archive và xác minh primary role.
9. Chuyển endpoint; buộc pool loại connection cũ và test write/read end-to-end.
10. Điều tra ambiguous commits bằng idempotency/business key, không replay mù.
11. Giữ node cũ cô lập; rewind hoặc rebuild thành standby.
12. Theo dõi lag/capacity khi cụm đang giảm redundancy.
13. Khôi phục redundancy rồi mới đóng incident.
14. Postmortem bằng timeline và số đo RPO/RTO thực tế.

---

## 71. Checklist production

### Topology và contract

- [ ] RPO/RTO được business phê duyệt và đo qua drill.
- [ ] Primary/standby nằm ở failure domain phù hợp.
- [ ] Có control plane/quorum độc lập và cơ chế fencing đã test.
- [ ] Write/read endpoint có role-aware health check.

### Replication

- [ ] `max_wal_senders`/`max_replication_slots` có headroom.
- [ ] Mọi slot có owner, purpose, retention limit và alert.
- [ ] WAL archive/retention đủ cho outage và rebuild window.
- [ ] Theo dõi sender, receiver, byte lag, replay, disk và conflict.
- [ ] Synchronous quorum failure policy được ghi rõ.

### Failover

- [ ] Candidate có config để trở thành primary.
- [ ] `pg_rewind` prerequisite được bật hoặc chấp nhận fresh rebuild.
- [ ] Application retry/idempotency xử lý ambiguous commit.
- [ ] Failover drill đo đến request thành công, không chỉ đến promotion.
- [ ] Runbook failback bắt đầu bằng fence và rejoin-as-standby.

### Logical replication

- [ ] Replica identity, schema, constraint và sequence có contract.
- [ ] Initial copy progress và table sync state được theo dõi.
- [ ] Conflict owner/resolution policy tồn tại.
- [ ] Nếu publisher HA, logical failover slot được sync và kiểm tra ready.
- [ ] Secret, TLS, RLS và privilege hai phía được review.

### Backup

- [ ] Replica không được tính thay backup.
- [ ] Backup/WAL archive nằm ngoài failure domain cần bảo vệ.
- [ ] Restore/PITR được drill độc lập.

---

## 72. Câu hỏi phỏng vấn

### Vì sao asynchronous streaming replication vẫn có thể mất transaction đã commit?

Vì primary có thể trả commit sau local WAL flush nhưng trước khi standby nhận/flush WAL. Primary mất
hoàn toàn trong cửa sổ đó thì standby được promote không có transaction.

### Synchronous replication có loại bỏ mọi lỗi không?

Không. Nó cải thiện durability acknowledgment nhưng tăng latency/availability coupling, không thay
fencing, backup, client retry hay xử lý ambiguous commit.

### Vì sao replication slot làm đầy disk?

Slot giữ WAL/catalog horizon cho consumer. Consumer chết hoặc quá chậm nhưng slot còn tồn tại khiến
primary không recycle được WAL cần thiết.

### `hot_standby_feedback` giải quyết gì và đánh đổi gì?

Nó giảm cleanup conflict trên standby bằng cách báo horizon về upstream, nhưng có thể trì hoãn vacuum
cleanup và gây bloat trên primary.

### Failover và switchover khác nhau thế nào?

Switchover có thể drain write và đồng bộ có kế hoạch. Failover xử lý primary có thể mất liên lạc, nên
candidate selection, data-loss decision và fencing khó hơn.

### Vì sao phải fence trước promote?

Vì không liên lạc được không chứng minh primary cũ đã ngừng ghi. Promote khi nó còn ghi tạo split-brain
và hai timeline không thể merge tự động.

### `pg_rewind` dùng khi nào?

Dùng để đưa node đã diverge về lịch sử của primary mới nhanh hơn full backup, nếu prerequisite và WAL
cần thiết còn đủ. Nếu integrity không chắc, rebuild từ base backup.

### Logical replication có replicate DDL và sequence không?

Không. Schema/DDL và sequence state phải được đồng bộ bằng migration/cutover plan riêng.

---

## 73. Nguồn và chủ đề tiếp theo

Nguồn chính thức PostgreSQL 18:

- [High Availability, Load Balancing, and Replication](https://www.postgresql.org/docs/18/high-availability.html)
- [Log-Shipping Standby Servers](https://www.postgresql.org/docs/18/warm-standby.html)
- [Streaming Replication Failover](https://www.postgresql.org/docs/18/warm-standby-failover.html)
- [Hot Standby](https://www.postgresql.org/docs/18/hot-standby.html)
- [Replication configuration](https://www.postgresql.org/docs/18/runtime-config-replication.html)
- [`pg_stat_replication` and `pg_stat_wal_receiver`](https://www.postgresql.org/docs/18/monitoring-stats.html)
- [`pg_replication_slots`](https://www.postgresql.org/docs/18/view-pg-replication-slots.html)
- [`pg_basebackup`](https://www.postgresql.org/docs/18/app-pgbasebackup.html)
- [`pg_rewind`](https://www.postgresql.org/docs/18/app-pgrewind.html)
- [Logical Replication](https://www.postgresql.org/docs/18/logical-replication.html)
- [Logical Replication Failover](https://www.postgresql.org/docs/18/logical-replication-failover.html)
- [Logical Decoding Concepts và Slot Synchronization](https://www.postgresql.org/docs/18/logicaldecoding-explanation.html)
- [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)

Học tiếp:

1. [Backup, PITR & Upgrade](backup_pitr_upgrade.md).
2. [Security & Row-Level Security](security_rls.md).
3. [PostgreSQL từ Java/Spring](../integration/jdbc_spring.md).

---

*Cập nhật lần cuối: 2026-07-31.*
