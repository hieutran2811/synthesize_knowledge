# PostgreSQL Backup, PITR & Upgrade

> Mục tiêu phiên bản: **PostgreSQL 18.x**. Chương này xây mental model và runbook cho
> logical dump/restore, physical base backup, WAL archive, Point-in-Time Recovery,
> incremental backup, restore drill, minor/major upgrade, `pg_upgrade` và logical blue-green.

Đọc cùng: [roadmap](../roadmap.md) ·
[trang tổng hợp](../postgresql_knowledge.md) ·
[Architecture & Storage](../fundamentals/architecture_storage.md) ·
[Transactions, MVCC & Locking](../fundamentals/transactions_mvcc.md) ·
[Performance & Autovacuum](../performance/tuning_autovacuum.md) ·
[Replication & High Availability](replication_ha.md).

---

## 1. Backup thành công khi restore đúng, không phải khi job có màu xanh

Một file đã upload không tự chứng minh rằng:

- file không bị thiếu/hỏng;
- WAL chain liên tục tới recovery target;
- key giải mã còn dùng được;
- tablespace/config/extension tồn tại ở nơi khôi phục;
- database start được;
- dữ liệu đúng business invariant;
- restore hoàn thành trong RTO.

```text
backup artifact + metadata + WAL + key + runbook + restore drill
                         = khả năng khôi phục
```

Metric quan trọng nhất không phải “lần backup cuối thành công”, mà là **lần restore đã kiểm chứng cuối
cùng**, recovery point đạt được và tổng thời gian khôi phục.

---

## 2. Bắt đầu từ failure model và phạm vi mất mát

| Sự cố | Cơ chế chính |
|---|---|
| Một row/bảng bị xóa nhầm | logical restore chọn lọc hoặc PITR ra cluster cô lập |
| Data directory/disk hỏng | physical base backup + WAL |
| Node/zone mất | standby cho HA; backup độc lập cho DR |
| Ransomware/credential bị lộ | immutable/offline copy, key và account tách biệt |
| DDL/application bug phát hiện muộn | PITR với retention đủ dài |
| Major upgrade thất bại | rollback plan theo phương thức upgrade |
| Extension/plugin không tương thích | rehearsal và inventory dependency |
| Toàn region mất | off-site/cross-region backup cùng restore automation |

Không có một loại backup tối ưu cho mọi tình huống. Một hệ quan trọng thường kết hợp physical backup
để restore nhanh, WAL archive để PITR và logical dump có chọn lọc cho portability/điều tra.

---

## 3. RPO và RTO phải được phân rã thành số đo

- **RPO**: điểm dữ liệu mới nhất có thể khôi phục; khoảng mất dữ liệu tối đa.
- **RTO**: thời gian từ lúc quyết định recover đến khi dịch vụ đáp ứng đúng.

```text
RPO thực tế ≈ now - latest recoverable WAL/backup point

RTO = phát hiện + quyết định + provision
    + tải/giải mã backup + combine/extract
    + WAL replay + validation + route application
```

“Backup mỗi ngày” không đồng nghĩa RPO 24 giờ nếu có continuous WAL archive; ngược lại archive job
xanh nhưng có một segment bị thiếu có thể làm PITR dừng giữa đường.

---

## 4. Ba họ backup chính của PostgreSQL

| Họ | Công cụ/cơ chế | Đơn vị restore | Điểm mạnh |
|---|---|---|---|
| Logical | `pg_dump`, `pg_dumpall`, `pg_restore` | database/schema/table/object | portable, chọn lọc, cross-major |
| Physical | `pg_basebackup`, filesystem backup đúng protocol | cả cluster | nhanh với cluster lớn, giữ binary state |
| Continuous archive | physical base backup + WAL archive | cả cluster tới một thời điểm | PITR và DR |

`pg_dump` không tạo physical base backup và không thể làm nguồn cho WAL replay. Physical backup không
restore riêng một table trực tiếp. Chọn cơ chế từ restore scenario, không từ file nhỏ nhất.

---

## 5. Replica không phải backup

Replication thường truyền rất nhanh:

- `DROP TABLE` nhầm;
- `DELETE` thiếu `WHERE`;
- transaction ứng dụng sai;
- corruption có thể được ghi/đọc lan theo failure mode;
- attacker dùng credential hợp lệ.

Standby tối ưu cho availability. Backup cần lịch sử, retention, failure domain và quyền xóa độc lập.
Hai cơ chế bổ sung cho nhau nhưng không thay thế nhau.

---

## 6. 3-2-1 là điểm khởi đầu, không phải bằng chứng hoàn tất

Mental model phổ biến:

```text
3 copies
2 loại storage/failure path
1 copy off-site hoặc offline/immutable
```

Với cloud/object storage, cần diễn giải cụ thể:

- versioning/object lock/retention có thật sự chặn xóa không;
- backup writer có quyền xóa hoặc đổi policy không;
- key mã hóa có nằm cùng account bị compromise không;
- cross-region copy có sao chép cả corruption/xóa không;
- restore account/network path có được test không.

Số bản sao không quan trọng bằng sự độc lập của failure và khả năng đọc lại.

---

## 7. Inventory đầy đủ hơn data file

Runbook phải lưu/khôi phục:

- data directory và mọi tablespace;
- roles, ownership, grants và tablespace definitions;
- `postgresql.conf`, include file, `pg_hba.conf`, `pg_ident.conf`;
- extension name/version và shared library/package;
- collation/locale/ICU environment;
- TLS certificate, nhưng key phải qua secret process riêng;
- scheduled job, external FDW/server mapping và secret;
- connection endpoint, pooler, monitoring và alert;
- backup catalog, manifest, checksum và encryption-key reference.

WAL archive không ghi lại thay đổi thủ công trong config file. Database restore được nhưng auth/config
thiếu vẫn chưa phải dịch vụ đã phục hồi.

---

## 8. Threat model cho backup

Backup thường chứa toàn bộ dữ liệu, kể cả row mà application user bình thường không thấy. Cần:

- encryption in transit và at rest;
- key rotation nhưng không làm mất khả năng giải mã backup cũ;
- least privilege cho writer, reader, deleter và restore operator;
- audit truy cập/tải/xóa;
- immutable retention cho cửa sổ quan trọng;
- không nhúng password vào command, log, manifest hay repository;
- quy trình xử lý backup hết retention chứa dữ liệu nhạy cảm.

Checksum phát hiện thay đổi không chủ ý; tính chống giả mạo chỉ có ý nghĩa nếu digest/manifest được bảo
vệ tách khỏi kẻ có thể sửa cả backup lẫn manifest.

---

## 9. `pg_dump` tạo snapshot nhất quán của một database

`pg_dump` đọc một snapshot nhất quán trong khi database vẫn phục vụ reader/writer. Nó không chặn DML
thông thường, nhưng lấy lock đủ để object không bị drop giữa lúc dump; DDL cần `ACCESS EXCLUSIVE` có
thể chờ hoặc làm dump gặp contention.

```bash
pg_dump \
  --host=source.internal \
  --username=backup_logical \
  --format=custom \
  --file=/backup/appdb.dump \
  appdb
```

`pg_dump` chỉ dump **một database**. Roles và tablespaces là global object nên phải xử lý riêng.

---

## 10. Chọn format logical dump từ cách restore

| Format | Option | Restore | Đặc điểm |
|---|---|---|---|
| Plain SQL | `-Fp` mặc định | `psql` | dễ đọc/sửa, restore tuần tự |
| Custom archive | `-Fc` | `pg_restore` | nén, chọn object, parallel restore |
| Directory | `-Fd` | `pg_restore` | parallel dump và restore, nhiều file |
| Tar | `-Ft` | `pg_restore` | archive tar, ít linh hoạt hơn directory/custom |

Custom là mặc định thực dụng cho database vừa; directory phù hợp khi cần parallel dump/restore và
storage hỗ trợ nhiều file. Plain SQL hữu ích cho review nhưng khó selective/parallel restore hơn.

---

## 11. Parallel dump chỉ có ở directory format

```bash
pg_dump \
  --format=directory \
  --jobs=8 \
  --file=/backup/appdb.dir \
  appdb
```

Các worker dùng synchronized snapshot để thấy cùng một trạng thái. Tăng `--jobs` làm tăng:

- connection;
- concurrent table scan;
- I/O/network/CPU compression;
- lock và pressure lên source.

Benchmark ở peak-like workload. `jobs = số core` không phải công thức đúng cho source đang giới hạn
I/O hoặc connection.

---

## 12. Dump từ standby giảm tải primary nhưng có recovery conflict

`pg_dump` có thể kết nối hot standby vì chủ yếu đọc. Tuy nhiên snapshot dài có thể xung đột WAL replay:

- dump bị cancel khi vượt standby delay;
- replay bị chậm;
- `hot_standby_feedback` có thể giữ dead tuple và gây bloat upstream.

Đừng chuyển backup sang HA candidate rồi kết luận “không tác động production”. Dùng replica chuyên backup
nếu workload lớn và theo dõi replay lag, conflict, disk, network cùng RPO.

---

## 13. Quy tắc version của `pg_dump`

`pg_dump` có thể đọc server cùng hoặc cũ hơn major của chính nó trong phạm vi được hỗ trợ, nhưng từ chối
server mới hơn major của tool. Output được kỳ vọng load vào PostgreSQL mới hơn; restore xuống major cũ
không được bảo đảm.

Thực hành an toàn khi migrate lên PostgreSQL 18:

- dùng `pg_dump` 18 để đọc source cũ được hỗ trợ;
- restore bằng tool 18 vào server 18;
- rehearsal extension/type/collation/SQL syntax;
- không chỉ copy binary `pg_dump` mà quên library/auth environment tương thích.

---

## 14. Selective dump có thể bỏ mất dependency

```bash
pg_dump --format=custom --table='billing.*' appdb > billing.dump
```

Chọn table/schema không tự kéo mọi dependency bên ngoài scope. Có thể thiếu:

- extension/type/function;
- referenced table/foreign key;
- role/owner/grant;
- sequence hoặc data liên quan;
- trigger function;
- row ở bảng khác cần cho business invariant.

Selective dump là data migration contract, không phải full disaster-recovery backup.

---

## 15. Filter pattern và shell quoting là bẫy vận hành

Pattern `-t`, `-n`, exclude option được `pg_dump` diễn giải; shell cũng có thể expand wildcard trước.
Dùng quote và kiểm tra archive TOC:

```bash
pg_restore --list /backup/appdb.dump > /tmp/appdb.toc
```

Với automation, dùng `--strict-names` khi cần fail nếu pattern không match. Một typo tạo dump rỗng nhưng
exit code vẫn như mong đợi ở workflow lỏng lẻo là loại lỗi cần chặn bằng object count/size/invariant.

---

## 16. Large object, sequence và statistics cần được hiểu theo format/scope

Full logical dump thường chứa large object và sequence value trong data section. Selective dump hoặc
option `--schema-only`, `--data-only`, `--no-data` thay đổi contract.

PostgreSQL 18 có thể dump optimizer statistics bằng option phù hợp, nhưng không phải mọi loại statistics
đều được bao phủ. Sau restore vẫn cần đánh giá `ANALYZE`, nhất là khi version, hardware hoặc distribution
thay đổi.

---

## 17. `pg_dumpall --globals-only` bổ sung global objects

```bash
pg_dumpall \
  --host=source.internal \
  --username=backup_admin \
  --globals-only \
  --file=/backup/globals.sql
```

Global dump gồm roles, tablespaces và privilege grant cho configuration parameter. Cân nhắc
`--no-role-passwords` nếu không muốn backup chứa password verifier; đổi lại role restore sẽ chưa đăng
nhập bằng password cho đến khi provision secret mới.

`pg_dumpall` full cluster gọi `pg_dump` từng database; snapshot của các database **không đồng bộ với
nhau**. Nếu business transaction trải nhiều database, phải có consistency strategy riêng.

---

## 18. Restore global objects trước object có owner

Thứ tự thường dùng:

```text
1. Provision package/extension shared libraries.
2. Tạo tablespace directory/mount với owner/permission đúng.
3. Restore roles/tablespaces/global grants.
4. Tạo database hoặc để restore tạo theo strategy.
5. Restore schema/data/post-data.
6. Provision secret và external integration.
7. Analyze, validate, mở traffic.
```

Nếu owner role chưa tồn tại, restore phát sinh lỗi ownership. Dùng `--no-owner` có thể hữu ích cho clone
dev/test nhưng làm thay đổi security/ownership contract, không phải cách che lỗi DR production.

---

## 19. Restore plain SQL bằng `psql` ở chế độ sạch

```bash
createdb --template=template0 appdb_restore

psql \
  --no-psqlrc \
  --set=ON_ERROR_STOP=on \
  --dbname=appdb_restore \
  --file=/backup/appdb.sql
```

- `--no-psqlrc` tránh config cá nhân làm đổi behavior.
- `ON_ERROR_STOP` ngăn script tiếp tục âm thầm sau lỗi.
- `template0` tạo database sạch theo locale/encoding đã chọn.

Một restore chạy hết nhưng đã bỏ qua lỗi giữa script không phải restore thành công.

---

## 20. `pg_restore` cho phép list, filter và parallel restore

```bash
pg_restore \
  --dbname=appdb_restore \
  --jobs=8 \
  --verbose \
  /backup/appdb.dump
```

Có thể xuất/chỉnh TOC list để chọn object và thứ tự, nhưng dependency rất dễ bị phá. Parallel restore
thường load table song song rồi tạo index/constraint; cần budget CPU, I/O, WAL, lock và free disk.

`--single-transaction` tăng atomicity nhưng không tương thích với parallel jobs và có thể tạo transaction
rất lớn. Chọn theo failure/retry strategy.

---

## 21. `--clean`, `--create`, `--no-owner` không phải option vô hại

| Option | Tác động |
|---|---|
| `--clean` | drop object trước restore; có tính phá hủy |
| `--if-exists` | giảm lỗi drop object không tồn tại |
| `--create` | tạo database và reconnect theo archive |
| `--no-owner` | object thuộc restore user, đổi ownership contract |
| `--no-privileges` | không restore GRANT/REVOKE |

Ưu tiên restore vào cluster/database cô lập thay vì `--clean` trực tiếp production. Restore rehearsal cần
dùng cùng option thật để không che lỗi role, grant và tablespace.

---

## 22. Post-restore validation có ba tầng

### Kỹ thuật

- server start, không crash/recovery error;
- extension load, invalid index/constraint, sequence;
- row/object count hợp lý;
- log không còn restore error;
- `ANALYZE`/plan readiness.

### Dữ liệu

- checksum hoặc aggregate trên bảng trọng yếu;
- foreign key/business key invariant;
- max event/commit timestamp và expected recovery cutoff;
- sample record trước/sau target.

### Dịch vụ

- login/auth/TLS;
- read/write smoke test;
- background job, CDC, pooler, cache;
- application version tương thích schema;
- endpoint cutover và rollback.

---

## 23. Physical base backup sao chép toàn cluster

`pg_basebackup` dùng replication protocol và sao chép cả cluster/data directory cùng tablespace. Nó
không backup riêng database/table.

```bash
pg_basebackup \
  --host=primary.internal \
  --username=backup_physical \
  --pgdata=/backup/base/2026-07-31 \
  --format=plain \
  --wal-method=stream \
  --checkpoint=spread \
  --manifest-checksums=SHA256 \
  --progress
```

Role cần `LOGIN REPLICATION`, `pg_hba.conf` cho phép và `max_wal_senders` đủ ít nhất connection backup
cộng connection stream WAL.

---

## 24. `--wal-method=stream` cần thêm connection nhưng giảm retention race

| Method | Behavior |
|---|---|
| `stream` | stream WAL song song, mặc định, dùng connection thứ hai |
| `fetch` | lấy WAL cuối backup; WAL phải còn tới lúc fetch |
| `none` | không kèm WAL; phải bảo đảm archive cung cấp đủ |

Với `stream`, temporary slot thường được dùng nếu không nêu slot. `--no-slot` bỏ guardrail này và tăng
nguy cơ WAL cần cho backup bị recycle. Permanent slot chỉ nên dùng khi backup output sẽ trở thành standby
với slot đó; backup job thường không cần để lại slot vĩnh viễn.

---

## 25. Checkpoint mode đổi thời gian bắt đầu lấy I/O burst

- `--checkpoint=spread`: chờ checkpoint trải đều, ít burst hơn nhưng backup có vẻ đứng lúc đầu.
- `--checkpoint=fast`: bắt checkpoint nhanh, tăng I/O spike.

Backup SLA không được tối ưu bằng `fast` mà không đo tail latency production. Theo dõi
`pg_stat_progress_basebackup`, checkpoint, WAL rate, disk latency và application latency cùng lúc.

`--max-rate` có thể giới hạn transfer, nhưng backup lâu hơn làm chain WAL/retention và RTO trade-off.

---

## 26. Plain và tar base backup có restore workflow khác

Plain format gần data directory và dễ dùng cho verify/restore trực tiếp. Tar tạo file riêng cho base,
WAL và từng tablespace; operator phải unpack đúng vị trí.

Tablespace là bẫy quan trọng:

- plain mặc định giữ absolute path của source;
- backup cùng host có thể đụng path đang dùng;
- dùng `--tablespace-mapping` khi relocate;
- tar restore phải unpack từng tablespace và giữ mapping/symlink đúng.

Không chỉ đo bytes trong `PGDATA`; inventory toàn bộ tablespace trước backup và restore.

---

## 27. Base backup từ standby có lợi và có giới hạn

Có thể giảm read load primary, nhưng:

- primary vẫn phải có `full_page_writes = on`;
- standby phải nhận replication connection;
- backup history file không được tạo trên cluster được backup;
- standby không tự force WAL switch ở primary;
- promote standby trong lúc backup làm backup thất bại;
- incremental backup từ standby có thể thiếu restartpoint mới khi activity thấp.

Source standby phải đủ khỏe và không phải candidate duy nhất. Theo dõi replay/receiver và đừng backup
từ một bản sao đang lag ngoài RPO.

---

## 28. Backup manifest mô tả artifact được server gửi

Mặc định `pg_basebackup` tạo `backup_manifest`, gồm danh sách file, size, thời gian và checksum tùy chọn;
manifest có checksum nội bộ SHA-256.

- CRC32C nhanh, tốt để phát hiện corruption vô tình.
- SHA family tốn CPU hơn nhưng phù hợp kiểm tra chống sửa đổi khi manifest được giữ tin cậy.
- `--no-manifest` bỏ khả năng verify tiêu chuẩn, hiếm khi có lợi production.

Nếu attacker sửa được cả backup và manifest, SHA trong cùng location không tự tạo trust. Có thể lưu
manifest/digest ở control plane hoặc immutable store riêng.

---

## 29. `pg_verifybackup` là bước cần thiết nhưng chưa đủ

```bash
pg_verifybackup \
  --progress \
  /backup/base/2026-07-31
```

Tool kiểm tra manifest, file thiếu/thừa, size/checksum và WAL cần thiết trong phạm vi hỗ trợ. Với tar
format, WAL parsing hiện không được hỗ trợ nên dùng `--no-parse-wal` cho phần đó. Khi WAL cần kiểm tra
nằm ngoài `pg_wal` của backup plain, chỉ rõ archive directory bằng `--wal-directory`.

Tài liệu chính thức nhấn mạnh verify không mô phỏng mọi kiểm tra của server. Vì vậy:

```text
manifest verification ≠ successful startup ≠ correct business data
```

Vẫn phải restore và chạy validation thật.

---

## 30. Restore drill phải dùng môi trường cô lập

Guardrail:

- network policy chặn application/worker kết nối nhầm;
- port/DNS khác production;
- outbound email/payment/webhook bị chặn hoặc stub;
- secret được thay bằng restore-specific credential;
- replication/subscription/job scheduler chưa tự bật;
- `pg_hba.conf` mặc định chỉ cho operator;
- dữ liệu nhạy cảm được kiểm soát như production.

Một bản restore vô tình chạy cron gửi email hoặc consume queue thật là incident, dù database restore đúng.

---

## 31. PostgreSQL 18 incremental backup dựa trên WAL summary

Incremental base backup chỉ gửi toàn bộ non-relation file và các block relation thay đổi kể từ backup
tham chiếu. Server dùng WAL summary trong `pg_wal/summaries` để xác định block nào thay đổi.

```text
full F0 ──► incremental I1 ──► incremental I2
   │              │                    │
   └──── tất cả artifact còn cần để combine ────┘
```

Incremental không phải một data directory có thể start trực tiếp; cần `pg_combinebackup` tạo synthetic
full trước khi recovery.

---

## 32. Bật và giữ WAL summary đủ lâu

```conf
summarize_wal = on
wal_summary_keep_time = '14d'
```

`summarize_wal` mặc định off. Summary phải phủ toàn bộ LSN từ start LSN của backup tham chiếu tới start
LSN backup mới. Nếu đã bị xóa hoặc summarizer không bắt kịp, incremental backup thất bại.

`wal_summary_keep_time` phải lớn hơn khoảng cách tối đa giữa backup phụ thuộc cộng outage/margin. Summary
không thay WAL archive; incremental restore vẫn cần WAL và history file như full physical backup.

---

## 33. Tạo full rồi incremental

Full:

```bash
pg_basebackup \
  --host=primary.internal \
  --pgdata=/backup/full-F0 \
  --format=plain \
  --wal-method=stream \
  --progress
```

Incremental tham chiếu manifest trước:

```bash
pg_basebackup \
  --host=primary.internal \
  --pgdata=/backup/incr-I1 \
  --format=plain \
  --wal-method=stream \
  --incremental=/backup/full-F0/backup_manifest \
  --progress
```

Reference phải từ cùng server/system history phù hợp. Backup catalog cần ghi parent ID/manifest, start/end
LSN, timeline, checksum, WAL coverage và encryption-key version.

---

## 34. Chain dependency làm retention phức tạp hơn

Muốn restore I2 phải còn mọi artifact cung cấp block mà I2 bỏ qua. PostgreSQL core không quản lý backup
dependency/expiration thay operator.

Không xóa F0 chỉ vì “đã quá 7 ngày” nếu I1/I2 còn phụ thuộc. Retention nên xóa nguyên chain từ leaf tới
root hoặc tạo synthetic/full checkpoint mới, verify rồi mới expire chain cũ.

```text
recoverable(I2) = intact(F0) AND intact(I1) AND intact(I2)
               AND continuous_required_WAL
```

Chain dài giảm backup bytes nhưng tăng artifact lookup, combine time và failure surface.

---

## 35. `pg_combinebackup` tạo synthetic full

```bash
pg_combinebackup \
  --output=/restore/synthetic-full \
  /backup/full-F0 \
  /backup/incr-I1 \
  /backup/incr-I2
```

Input phải theo thứ tự cũ nhất tới mới nhất. Tool xác minh quan hệ chain, nhưng không chứng minh mỗi backup
nguyên vẹn; chạy `pg_verifybackup` cho từng artifact và output phù hợp.

`--link`/clone/copy-file-range có thể tăng tốc nhưng thay đổi isolation giữa input/output. Không start
synthetic output dùng hard link với bản backup duy nhất vì write có thể làm hỏng nguồn.

---

## 36. Đổi trạng thái page checksum giữa chain cần full mới

`pg_combinebackup` không tự tính lại page checksum khi ghép output. Nếu chain chứa backup chụp ở các trạng
thái checksum khác nhau, synthetic full có thể có page checksum sai.

Sau khi bật/tắt checksum bằng `pg_checksums`, lựa chọn dễ chứng minh nhất là tạo một full backup mới làm
root chain. Không kéo incremental chain qua thay đổi checksum state chỉ vì tool cho phép một phần workflow.

---

## 37. Incremental chỉ có ROI với cluster lớn và phần lớn block ít đổi

| Workload | Kỳ vọng |
|---|---|
| Cluster nhỏ | full đơn giản hơn |
| Append-heavy nhưng nhiều file cũ ổn định | incremental có thể nhỏ đáng kể |
| Hầu hết block bị rewrite/churn | incremental gần full |
| Chain dài, RTO ngắn | combine có thể thành bottleneck |
| Object storage request/egress đắt | phải đo cả số object và restore path |

Đo backup bytes, wall time, source I/O và **restore + combine time**. Tối ưu backup window nhưng làm RTO
vượt SLA là tối ưu sai phía.

---

## 38. Continuous archiving = base backup + chuỗi WAL liên tục

```text
base backup B
    + WAL từ lúc B bắt đầu
    + WAL liên tục tới target T
    = cluster nhất quán tại T
```

WAL sửa inconsistency của online physical copy và đưa state tiến tới recovery target. Thiếu một segment
cần thiết có thể làm recovery dừng; các segment sau không bù được khoảng trống.

PITR phục hồi toàn cluster, không trực tiếp một database/table. Muốn cứu vài row, restore cluster tạm rồi
export/import có kiểm soát thường an toàn hơn thay production toàn bộ.

---

## 39. Cấu hình WAL archiving

```conf
wal_level = replica
archive_mode = on
archive_command = '/usr/local/bin/archive-wal "%p" "%f"'
```

Trong `archive_command`:

- `%p`: path WAL source tương đối data directory;
- `%f`: tên file archive cần giữ nguyên;
- exit code 0 **chỉ khi** artifact đã được lưu bền và đúng;
- nonzero để PostgreSQL retry.

Production nên dùng script/tool nhỏ, testable và có timeout/log thay vì chuỗi shell phức tạp trong config.

---

## 40. Archive operation phải idempotent và không overwrite khác nội dung

PostgreSQL có thể yêu cầu archive lại file đã thành công trước crash. Contract đúng:

```text
target chưa có      → upload atomically → verify durable → success
target đã có giống  → success
target đã có khác   → fail + page operator
```

Hai cluster dùng chung archive namespace có thể trùng tên WAL nhưng khác nội dung. Namespace theo cluster
system identifier/environment và refusal-to-overwrite là guardrail chống làm hỏng lịch sử.

Không trả 0 ngay sau khi chỉ đẩy vào local queue volatile nếu queue chưa nằm trong durability contract.

---

## 41. Archive hỏng làm `pg_wal` tăng đến khi database dừng

Khi archive command thất bại, PostgreSQL giữ WAL chưa archive và retry. Nếu filesystem `pg_wal` đầy,
server có thể PANIC shutdown để bảo vệ tính đúng.

Alert theo:

- thời gian từ lần archive thành công cuối;
- `failed_count` delta và lỗi cuối;
- số/bytes WAL ready chưa archive;
- WAL generation rate;
- free disk và time-to-full;
- object-store/API latency/error.

Đừng xóa tay WAL trong `pg_wal` để giải phóng chỗ. Sửa archive hoặc tăng storage theo runbook an toàn.

---

## 42. Monitor `pg_stat_archiver`

```sql
SELECT archived_count,
       last_archived_wal,
       last_archived_time,
       failed_count,
       last_failed_wal,
       last_failed_time,
       stats_reset
FROM pg_stat_archiver;
```

Counter cumulative phải đọc theo delta cùng `stats_reset`. Một số lỗi làm archiver process abort/restart
có thể không xuất hiện như failed count mong đợi; luôn kết hợp server log, archive destination probe và
restore/WAL continuity check.

---

## 43. `archive_timeout` giới hạn độ trễ segment chưa đóng, nhưng tốn storage

Archive command thường chỉ chạy khi WAL segment hoàn tất. Hệ ít write có thể giữ transaction trong segment
chưa đóng lâu. `archive_timeout` force switch định kỳ:

```conf
archive_timeout = '60s'
```

Segment bị switch sớm vẫn có kích thước logic đầy đủ trong archive, nên timeout quá ngắn làm phình storage.
RPO rất thấp có thể cần thêm streaming WAL receiver; không ép archive segment mỗi giây một cách mù quáng.

Có thể dùng `pg_switch_wal()` cho một mốc vận hành cụ thể, không gọi liên tục thay monitoring.

---

## 44. Retention phải bảo toàn toàn bộ restore path

Để phục hồi tới T cần:

- một full/synthetic base backup kết thúc trước T;
- toàn bộ incremental parent nếu chưa combine;
- WAL từ lúc backup bắt đầu/được yêu cầu tới T;
- timeline history file;
- manifest/catalog/key/config tương ứng.

```text
retention decision = backup dependency graph + WAL coverage + legal policy
```

Không chạy `pg_archivecleanup` trên archive phục vụ nhiều standby/PITR mà chỉ dựa vào nhu cầu một node.
Xóa WAL nên do backup catalog hiểu tất cả backup và target window quyết định.

---

## 45. Backup configuration và external state riêng

WAL không phục hồi chỉnh sửa thủ công của:

- `postgresql.conf` và include;
- `pg_hba.conf`, `pg_ident.conf`;
- service unit/container spec;
- TLS/key file;
- DNS/load balancer/pooler;
- extension binary và OS package;
- secret manager/IAM policy.

Version-control phần không bí mật, backup secret theo control riêng, và snapshot metadata version cùng mỗi
backup. Tránh restore config primary cũ rồi mở network trước khi đổi identity/endpoint.

---

## 46. `restore_command` là chiều ngược của archive

```conf
restore_command = '/usr/local/bin/restore-wal "%f" "%p"'
```

Contract:

- `%f` là file PostgreSQL yêu cầu, có thể gồm `.history`;
- `%p` là destination path cần ghi atomically;
- trả nonzero khi file không tồn tại để recovery thử nguồn/kết thúc hợp lệ;
- phân biệt “not found” với corruption/auth/network;
- không trả file sai cluster/timeline dù tên giống.

Restore path thường ít được chạy hơn archive path nên dễ bit-rot. Drill định kỳ chính là integration test
cho credential, network, decompression, key và tool version.

---

## 47. `recovery.signal` bật archive recovery

Sau khi restore physical backup vào data directory đích:

```text
$PGDATA/recovery.signal
```

cùng `restore_command` khiến PostgreSQL replay archive. Đừng dùng `standby.signal` nếu mục tiêu là một PITR
độc lập không được phép tự kết nối primary; hai signal diễn tả lifecycle khác nhau.

Trước start:

- owner/permission đúng database OS user;
- tablespace mapping đúng và không trỏ production path;
- `pg_wal`/symlink đúng;
- network/auth cô lập;
- recovery target/timezone được peer review.

---

## 48. Chọn recovery target bằng time, name, LSN hoặc XID

Chỉ được cấu hình tối đa một target chính:

```conf
recovery_target_time = '2026-07-31 14:29:55+07'
```

Hoặc restore point đã tạo trước:

```sql
SELECT pg_create_restore_point('before_billing_release_20260731');
```

```conf
recovery_target_name = 'before_billing_release_20260731'
```

Named restore point tốt cho planned change; timestamp tốt cho incident nếu log/audit clock đáng tin. XID
khó dùng vì transaction bắt đầu theo thứ tự nhưng có thể commit khác thứ tự.

---

## 49. Luôn ghi timezone offset đầy đủ

```conf
recovery_target_time = '2026-07-31 14:29:55.250+07'
```

Không dùng timestamp mơ hồ kiểu `14:30` hoặc abbreviation không được cấu hình. Thu thập:

- database/server/application timezone;
- NTP status và clock skew;
- audit log thời điểm bad transaction bắt đầu/commit;
- transaction ID/LSN nếu có;
- khoảng an toàn trước side effect.

Restore tới “một giây trước lúc lệnh được gõ” có thể vẫn chứa transaction nếu clock/log semantics bị hiểu
sai. Ưu tiên restore cô lập và kiểm tra row cụ thể.

---

## 50. `recovery_target_inclusive` quyết định có nhận transaction tại target

```conf
recovery_target_inclusive = off
```

Với time/LSN/XID target:

- `on` mặc định: dừng sau, gồm transaction đúng target;
- `off`: dừng trước target.

Nếu target là commit gây lỗi và định danh chính xác được nó, thường muốn exclude; nhưng surrounding
transaction vẫn phải xác minh. Cài đặt này không áp dụng theo cùng cách cho named restore point.

---

## 51. `recovery_target_action` mặc định là `pause`

```conf
recovery_target_action = 'pause'
```

| Action | Khi đạt target |
|---|---|
| `pause` | dừng replay để query kiểm tra; mặc định |
| `promote` | kết thúc recovery và nhận hoạt động bình thường |
| `shutdown` | stop server tại target |

`pause` phù hợp drill/forensics vì chưa ngay lập tức tạo timeline writable. Nếu target sai và muốn đi xa hơn,
stop, đổi target rồi tiếp tục theo runbook. Gọi `pg_wal_replay_resume()` khi đã hiểu rằng recovery sẽ kết thúc.

Với `shutdown`, `recovery.signal` còn lại; start tiếp có thể shutdown lại nếu không sửa config/signal.

---

## 52. Recovery target phải sau lúc base backup kết thúc

Không thể dùng một base backup để recover tới thời điểm đang nằm **trong lúc backup đó được chụp**. Recovery
target phải sau end time của backup. Muốn target sớm hơn phải chọn base backup trước đó.

Backup catalog phải lưu start/end time và WAL range để chọn đúng base:

```text
base.end_time <= target_time
WAL coverage liên tục từ base requirement tới target
```

Chọn “backup gần target nhất” mà end time sau target sẽ thất bại về mặt logic.

---

## 53. Timeline giữ các nhánh lịch sử sau PITR

Khi archive recovery kết thúc, PostgreSQL tạo timeline mới. History file mô tả nhánh và cần được archive.
WAL mới không ghi đè lịch sử timeline cũ.

```text
timeline 1 ─────────────X bad change ─────────►
                       └── timeline 2 sau PITR
```

`recovery_target_timeline = 'latest'` là mặc định. Với re-recovery phức tạp, cần chỉ rõ `current` hoặc
timeline ID để không vô tình theo nhánh mới nhất nhưng sai mục tiêu. Giữ history file lâu dài vì nhỏ và
cần để chọn đúng WAL branch.

---

## 54. PITR để cứu một table thường nên restore side-by-side

Thay vì rollback toàn production và mất mọi transaction tốt sau lỗi:

```text
1. Restore cluster cô lập tới trước lỗi.
2. Xác minh table/row cần cứu.
3. Export đúng scope bằng pg_dump/COPY.
4. Reconcile với production hiện tại theo business key/version.
5. Import bằng transaction/idempotency/audit.
```

Đây là data repair, không phải restore đơn giản. Row sau thời điểm lỗi có thể đã được update hợp lệ, nên
không overwrite toàn bảng nếu chưa có conflict rule.

---

## 55. Runbook PITR

1. Mở incident, freeze thao tác xóa/expire backup và thu thập evidence.
2. Xác định target window, timezone, timeline và business scope.
3. Chọn base backup có end time trước target; kiểm tra dependency chain.
4. Xác minh manifest/checksum, WAL continuity, key và free disk.
5. Provision environment cô lập; chặn application/background outbound.
6. Nếu incremental, combine từ full tới incremental cuối thành synthetic full.
7. Restore data directory/tablespace đúng owner/path; giữ source artifact bất biến.
8. Cấu hình `restore_command`, target, inclusive/action và tạo `recovery.signal`.
9. Start, theo dõi log/replay; không bỏ qua WAL missing/corruption.
10. Tại `pause`, kiểm tra record trước/sau target và business invariant.
11. Nếu target sai, stop và thử lại từ copy/snapshot sạch theo timeline plan.
12. Nếu đúng, chọn extract chọn lọc hoặc promote/cutover cluster.
13. Provision config/secret/extension, smoke test, route có kiểm soát.
14. Ghi RPO/RTO thực tế và giữ forensic artifact theo policy.

---

## 56. Không sửa trực tiếp backup artifact khi thử nhiều target

Mỗi recovery làm thay đổi data directory và có thể tạo timeline. Để thử các target khác nhau:

- giữ backup gốc read-only/immutable;
- tạo working copy/clone độc lập;
- ghi rõ target/timeline/result mỗi lần;
- không start trực tiếp directory đang dùng làm nguồn combine;
- không reuse một failed restore mà không hiểu state.

Copy-on-write snapshot có thể tăng tốc lab nhưng phải chứng minh write isolation và durability; hard link
không tạo isolation.

---

## 57. Restore throughput thường quyết định RTO

Đo riêng:

```text
download/egress
decrypt + decompress
combine incremental chain
write + fsync data/tablespace
WAL fetch + replay
post-restore analyze/reindex
application validation + routing
```

Backup compression cao giảm storage/network nhưng tăng CPU restore. Nhiều object nhỏ tăng request latency.
Base backup quá cũ tăng WAL replay. RTO tối ưu bằng end-to-end benchmark với data size và WAL rate thật.

---

## 58. Đo RPO từ latest recoverable point, không từ latest upload timestamp

Cần chứng minh:

- base backup usable;
- chain parent còn đủ;
- WAL từ base tới point mới nhất liên tục;
- WAL cuối đã durable ở failure domain độc lập;
- key/manifest/catalog truy cập được.

```text
latest_recoverable_time
  = min(latest_contiguous_WAL, backup/key/catalog availability)
```

Một file WAL mới nhất tồn tại không chứng minh không có gap ở giữa. Backup manager nên kiểm tra continuity,
không chỉ list object cuối bucket.

---

## 59. Backup catalog là dependency graph vận hành

Metadata tối thiểu:

| Trường | Mục đích |
|---|---|
| cluster system identifier | chống trộn cluster |
| major/minor, platform | chọn đúng binary/tool |
| backup ID/type/parent | dựng chain |
| start/end time, LSN, timeline | chọn recovery target |
| tablespace/config/extension inventory | provision restore |
| manifest/checksum | integrity |
| WAL min/max/continuity | recoverability |
| encryption key version | giải mã |
| retention/legal hold | quyết định expire |
| verify/restore drill result | bằng chứng |

Catalog cũng cần backup/replication riêng; mất catalog có thể biến hàng TB artifact thành tập file khó dùng.

---

## 60. Backup manager như pgBackRest/Barman giảm glue code, không xóa trách nhiệm

Các công cụ chuyên dụng có thể quản lý repository, WAL archive/stream, full/differential/incremental,
retention, compression/encryption, restore và status. Khi chọn công cụ, đánh giá:

- PostgreSQL/platform/object store được hỗ trợ;
- backup/WAL dependency và expire semantics;
- multi-repository/off-site/immutability;
- encryption/key rotation;
- parallelism, bandwidth control và resume;
- verify/check/restore workflow;
- HA/failover/timeline behavior;
- upgrade compatibility và observability;
- khả năng rehearsal không phụ thuộc production secret.

Đừng trộn lệnh native và tool-managed expiration trên cùng repository nếu không có một catalog sở hữu toàn
chain. Tool không thể tự định nghĩa business RPO/RTO hoặc validation invariant.

---

## 61. Managed database vẫn cần hiểu contract provider

Hỏi rõ:

- snapshot là crash-consistent hay application/database-consistent;
- continuous backup granularity và PITR window;
- backup nằm cùng account/region không;
- ai có quyền delete/change retention;
- restore tạo instance mới hay overwrite;
- extension, role, parameter group, network, secret có được phục hồi không;
- restore cross-region/cross-account mất bao lâu;
- export/exit plan khi đổi provider;
- bằng chứng restore drill và SLA thực tế.

“Automated backup enabled” là cấu hình, chưa phải recoverability đã kiểm thử.

---

## 62. Minor upgrade khác major upgrade

```text
18.3 → 18.4  = minor update trong cùng major
17.x → 18.x  = major upgrade
```

Minor release giữ data format và thường không cần dump/restore, nhưng vẫn phải:

- đọc release notes của mọi minor bị bỏ qua;
- cập nhật standby theo thứ tự an toàn cho replication topology;
- kiểm tra extension/package/library;
- restart/rolling procedure theo HA design;
- có backup và rollback binary/config plan;
- smoke/performance test.

Không gọi minor update là “không rủi ro” chỉ vì data directory tương thích.

---

## 63. Bốn chiến lược major upgrade chính

| Chiến lược | Downtime | Disk/độ phức tạp | Điểm mạnh |
|---|---:|---|---|
| Logical dump/restore | dài với data lớn | đơn giản, cần space mới | portable, làm sạch physical layout |
| `pg_upgrade` | ngắn | cùng host/storage hoặc copy | nhanh, giữ toàn cluster |
| Logical blue-green | cutover ngắn | hai cluster + replication | rehearsal/cutover linh hoạt |
| Provider-native | tùy provider | contract riêng | automation tích hợp |

Chọn từ data size, write rate, downtime, rollback window, extension, schema/DDL rate, sequence/large object
và khả năng chạy song song hai version.

---

## 64. `pg_upgrade` tái dùng user data file, không replay mọi row

`pg_upgrade` tạo system catalog mới rồi copy/link/clone/swap user data file theo mode. Nó kiểm tra binary
compatibility mà core biết, nhưng external module binary compatibility vẫn cần operator xác minh.

Ưu điểm: downtime thường ngắn hơn dump/restore. Giới hạn:

- old/new cluster cần binary/config compatible;
- extension shared library cho new major phải sẵn;
- cả cluster nâng cùng lúc;
- physical standby cần upgrade/rebuild procedure;
- rollback phụ thuộc file transfer mode;
- post-upgrade script/statistics/performance vẫn cần.

Luôn chạy binary `pg_upgrade` của **new version**.

---

## 65. `pg_upgrade --check` phải dùng đúng mode dự kiến

```bash
/opt/postgresql/18/bin/pg_upgrade \
  --check \
  --old-bindir=/opt/postgresql/17/bin \
  --new-bindir=/opt/postgresql/18/bin \
  --old-datadir=/data/postgresql/17 \
  --new-datadir=/data/postgresql/18 \
  --clone
```

Nếu production sẽ dùng `--link`, `--clone`, `--copy-file-range` hoặc `--swap`, đưa chính option đó vào
`--check` để chạy mode-specific checks. Check output/manual action là release artifact cần review.

`--check` không benchmark downtime, extension runtime, plan regression hay application compatibility.

---

## 66. Inventory trước major upgrade

```sql
SELECT extname, extversion
FROM pg_extension
ORDER BY extname;

SELECT datname, datcollate, datctype
FROM pg_database
ORDER BY datname;
```

Ngoài ra rà:

- deprecated/removed config và SQL behavior;
- extension binary/control/update path cho target;
- preload library;
- tablespace và `pg_wal` placement;
- data checksum/locale/encoding/architecture;
- replication slot/subscription/publication;
- prepared transaction và long transaction;
- backup/restore của target toolchain;
- disk cho old + new + backup + transient WAL.

---

## 67. So sánh các mode chuyển file của `pg_upgrade`

| Mode | Tốc độ/space | Old cluster sau bước quyết định | Điều kiện/rủi ro |
|---|---|---|---|
| `--copy` mặc định | chậm, tốn space | không bị thay đổi | rollback dễ hiểu nhất |
| `--link` | nhanh, ít space | file có thể shared; start new làm old không an toàn | cùng filesystem |
| `--clone` | nhanh nhờ reflink | old còn độc lập logic | filesystem/OS hỗ trợ |
| `--copy-file-range` | tùy filesystem | thường độc lập theo semantics OS | Linux/FreeBSD hỗ trợ |
| `--swap` PG18 | rất nhanh với nhiều relation | old bị sửa phá hủy khi transfer bắt đầu | cùng filesystem, rollback khó |

Không chọn `--link`/`--swap` chỉ vì downtime nhỏ. Tính thời gian tạo snapshot/backup đáng tin và khả năng
rollback vào change budget.

---

## 68. PostgreSQL 18 `--swap` tối ưu catalog/file-heavy cluster nhưng phá hủy old

`--swap` đổi data directory rồi thay catalog bằng catalog new version. Nó có thể nhanh hơn khi cluster có
rất nhiều relation, nhưng từ lúc file transfer bắt đầu, old cluster không còn an toàn để start.

Tài liệu khuyến nghị `--sync-method=fsync` với `--swap` vì mode tạo nhiều garbage file ở old cluster có thể
làm `syncfs` lâu. Chỉ dùng sau rehearsal cùng filesystem/layout và có external rollback copy/snapshot đã
kiểm chứng.

Fast path không giảm yêu cầu backup; nó làm rollback dependency quan trọng hơn.

---

## 69. Rehearsal major upgrade phải dùng production-like copy

Đo:

- stop/drain time;
- `pg_upgrade --check` và actual runtime;
- file sync time theo mode;
- extension/post-upgrade script;
- startup/recovery;
- statistics warm-up và plan regression;
- application smoke/load;
- rebuild/rejoin standby;
- rollback time.

Schema-only rehearsal bắt compatibility sớm nhưng không đo relation count, data copy, index work, cache
coldness và query plan trên distribution thật. Cần ít nhất một rehearsal từ backup gần production size.

---

## 70. Runbook `pg_upgrade`

1. Chốt target minor mới nhất được phê duyệt; đọc release/migration notes.
2. Inventory extension/config/locale/tablespace/replication và chạy rehearsal.
3. Xác minh backup + WAL archive + restore drill; tạo rollback artifact theo mode.
4. Cài old/new binary và extension target; initdb new cluster với compatible settings.
5. Chạy `pg_upgrade --check` bằng chính transfer mode production; xử lý mọi report.
6. Freeze DDL, drain write/job và ghi cutover checkpoint/evidence.
7. Stop old cluster sạch; fence endpoint để không tự restart.
8. Chạy new `pg_upgrade` với `--jobs` đã benchmark và lưu log.
9. Áp dụng config có chọn lọc, không copy mù old `postgresql.conf`.
10. Chạy generated post-upgrade script/extension update theo output.
11. Start new cluster cô lập; smoke test schema, auth, sequence, extension và business invariant.
12. Analyze/statistics work theo hướng dẫn; theo dõi plan/latency.
13. Cấu hình lại backup/archive/replication và tạo backup baseline new major.
14. Mở traffic theo canary; giữ rollback window.
15. Chỉ xóa old cluster khi exit criteria và restore target mới đã đạt.

---

## 71. Physical standby không tự tiếp tục qua major upgrade

Physical WAL/data format gắn major. Các lựa chọn:

- rebuild standby từ primary new version sau upgrade;
- dùng documented rsync/link workflow của `pg_upgrade` khi topology/condition phù hợp;
- logical blue-green sang cluster new major.

Trong thời gian rebuild, redundancy giảm và primary chịu I/O/network. Budget WAL retention, slot, disk và
thời gian catch-up. Không đóng maintenance chỉ vì primary mới đã nhận traffic khi chưa khôi phục HA/backup.

---

## 72. Post-upgrade statistics và plan cần quan sát riêng

PostgreSQL 18 cải thiện việc giữ optimizer statistics qua `pg_upgrade`, nhưng vẫn cần:

- chạy script mà `pg_upgrade` tạo;
- xử lý missing statistics;
- theo dõi query top total/tail latency;
- so cardinality/plan/cost ở workload thật;
- warm cache có kiểm soát;
- kiểm tra collation/index/extension yêu cầu rebuild;
- không ép plan cũ nếu planner mới chọn tốt hơn.

Performance regression là rollback input. Đặt threshold trước cutover thay vì tranh luận trong incident.

---

## 73. Rollback của `pg_upgrade` phụ thuộc mode và write sau cutover

| Tình huống | Khả năng quay old |
|---|---|
| Chỉ `--check` | old chưa đổi, start lại sau config/endpoint check |
| `--copy`, new chưa nhận write | old thường còn nguyên |
| `--clone`, new chưa nhận write | old thường độc lập, vẫn xác minh filesystem |
| `--link`, new đã start | old file có thể bị ảnh hưởng, không start mù |
| `--swap` đã transfer | old bị phá hủy theo contract |
| New đã nhận write | quay old làm mất/reconcile write mới |

Rollback kỹ thuật không giải quyết dữ liệu phát sinh trên new cluster. Có thể cần freeze write, reverse
logical replication hoặc business reconciliation được thiết kế trước; nếu không, rollback window thực tế
kết thúc ngay khi mở write.

---

## 74. Logical blue-green giảm cutover downtime nhưng tăng migration contract

```text
PostgreSQL 17 source ── logical replication ──► PostgreSQL 18 target
        write endpoint                              shadow/read validation
                └──────────── cutover ─────────────► new write endpoint
```

Ưu điểm:

- target build/rehearse trong lúc source chạy;
- có thể kiểm tra read/performance trước cutover;
- khác major/platform;
- downtime chủ yếu drain + catch-up + route.

Đổi lại phải xử lý DDL, sequence, large object, replica identity, initial copy, conflict và write rollback.

---

## 75. Runbook logical blue-green

1. Inventory table/DDL/sequence/large object/extension và unsupported object.
2. Provision target 18, schema/role/extension bằng migration đã rehearsal.
3. Tạo publication/subscription với security/slot/retention budget.
4. Theo dõi initial copy từng table, apply lag, conflict và source `pg_wal`.
5. Dual-read/shadow query hoặc checksum business invariant.
6. Áp dụng additive DDL subscriber-first trong migration window.
7. Trước cutover, freeze DDL/background write và drain application write.
8. Chờ subscription catch-up tới LSN/transaction mốc; xác minh table state.
9. Đồng bộ sequence và external state; disable subscription theo plan.
10. Chuyển endpoint, reset pool, canary write/read và theo dõi error/latency.
11. Giữ source read-only/fenced trong rollback window.
12. Nếu cần rollback sau new write, dùng reverse path/reconciliation đã thiết kế—không mở write cả hai phía.
13. Tạo physical backup/WAL archive và HA topology cho target trước khi kết thúc change.

---

## 76. DDL và sequence là hai điểm cutover logical dễ quên nhất

Logical replication không tự replicate schema/DDL hay sequence state. Khi source vẫn ghi identity value,
target row nhận value nhưng sequence object target không nhất thiết tiến theo.

Trước mở write target:

```sql
SELECT setval(
  pg_get_serial_sequence('billing.invoice', 'invoice_id'),
  COALESCE(max(invoice_id), 1),
  max(invoice_id) IS NOT NULL
)
FROM billing.invoice;
```

Ví dụ chỉ phù hợp khi max ID là nguồn truth; sequence cache, custom allocator, negative range hoặc multi-writer
cần contract khác. Freeze writer trước khi lấy mốc để tránh race.

---

## 77. Decision matrix backup và upgrade

| Nhu cầu | Lựa chọn khởi đầu |
|---|---|
| Restore toàn cluster nhanh | physical base backup + WAL |
| PITR tới trước lỗi | continuous WAL archive |
| Restore vài object | custom/directory `pg_dump` |
| Cross-major, downtime chấp nhận dài | dump/restore |
| Cluster lớn, downtime ngắn cùng platform | `pg_upgrade` |
| Major upgrade với validation song song | logical blue-green |
| Backup window/storage lớn, nhiều block ổn định | PG18 incremental + chain manager |
| Ransomware/account compromise | immutable/offline cross-account backup + key isolation |
| Managed service | provider PITR + independent export/restore drill theo risk |

Hệ critical thường giữ ít nhất một physical/PITR path và một logical/selective path, nhưng phải drill cả hai.

---

## 78. Failure modes thường gặp

| Failure mode | Hậu quả | Guardrail |
|---|---|---|
| Job backup xanh nhưng chưa restore | artifact unusable không bị phát hiện | restore drill + invariant |
| Chỉ có replica | xóa nhầm lan sang replica | immutable historical backup |
| `pg_dump` thiếu globals | owner/role/tablespace lỗi | `pg_dumpall --globals-only` |
| Dump nhiều database tưởng cùng snapshot | cross-DB inconsistency | app quiesce/contract riêng |
| Archive command trả 0 quá sớm | mất WAL dù metric thành công | durable + verify trước success |
| Hai cluster chung archive namespace | WAL overwrite/corruption | system-ID namespace, no overwrite |
| Archive lag làm đầy `pg_wal` | PANIC/downtime | time-to-full alert, capacity/runbook |
| Xóa parent incremental | chain không restore | dependency-aware retention |
| Verify manifest được coi là đủ | server/data vẫn sai | start + business validation |
| PITR target sai timezone/inclusive | giữ bad transaction hoặc mất good data | offset rõ, pause, side-by-side verify |
| Restore lab gọi external service thật | side effect production | outbound isolation/stub secret |
| `pg_upgrade --link` rồi start old | shared file bị sửa/hỏng | mode-specific rollback runbook |
| `--swap` không có external rollback | old cluster không start được | verified snapshot/full backup |
| Blue-green quên sequence/DDL | duplicate/apply error | freeze, sync, schema contract |
| Upgrade xong chưa rebuild standby/backup | giảm redundancy kéo dài | exit criteria gồm HA + new baseline |

---

## 79. Monitoring và alert tối thiểu

| Nhóm | Tín hiệu |
|---|---|
| Backup | start/end/duration/bytes/type/parent/exit status |
| Integrity | manifest/checksum result, age của verify cuối |
| Restore | age của drill cuối, RPO/RTO đạt được, validation result |
| Archive | last success/failure, queue/backlog, gap, time-to-disk-full |
| Repository | capacity, growth, object error, immutability/replication status |
| Incremental | summarizer lag, summary coverage, chain length/dependency |
| Security | key expiry/access, delete/policy change, unusual download |
| Upgrade | check findings, rehearsal duration, extension readiness |
| Post-cutover | error/latency/plan, sequence/conflict, HA/backup readiness |

Mỗi alert phải chỉ ra backup/cluster ID, owner, impact lên RPO/RTO và runbook. “Backup failed” không đủ nếu
operator không biết còn bao lâu trước khi mất recovery window.

---

## 80. Checklist production

### Policy và security

- [ ] RPO/RTO, retention, legal hold và data classification được phê duyệt.
- [ ] Backup có off-site/independent/immutable copy theo threat model.
- [ ] Encryption key, restore credential và delete privilege được tách hợp lý.
- [ ] Backup catalog/manifest/system identifier được bảo vệ.

### Logical backup

- [ ] Chọn format từ restore workflow; dump global roles/tablespaces riêng.
- [ ] Version tool/source/target nằm trong contract hỗ trợ.
- [ ] Selective dump có dependency/object-count validation.
- [ ] Restore dùng `ON_ERROR_STOP`, đúng owner/grant và post-restore analyze.

### Physical/PITR

- [ ] Base backup gồm mọi tablespace, manifest và WAL cần thiết.
- [ ] Archive idempotent, durable, không overwrite khác nội dung.
- [ ] Theo dõi WAL continuity, backlog, disk và latest recoverable point.
- [ ] Incremental chain/summary/checksum state được catalog quản lý.
- [ ] Restore target timezone/inclusive/action/timeline được peer review.

### Restore drill

- [ ] Environment cô lập network/outbound/job/subscription.
- [ ] Artifact được verify rồi start thật bằng tool/binary đúng version.
- [ ] Technical, data và application invariant đều pass.
- [ ] RPO/RTO thực tế được lưu và alert khi drill quá hạn.

### Upgrade

- [ ] Release notes, extension, config, locale, tablespace và replication đã inventory.
- [ ] Rehearsal production-like và `pg_upgrade --check` đúng mode.
- [ ] Rollback semantics được hiểu trước khi mở write.
- [ ] Post-upgrade script/statistics/plan được theo dõi.
- [ ] HA, archive và backup baseline new major được khôi phục trước khi đóng change.

---

## 81. Câu hỏi phỏng vấn

### Vì sao `pg_dump` không dùng được cho PITR bằng WAL?

Vì nó là logical export SQL/object của một database, không phải file-system state của toàn cluster có thể
được WAL replay.

### Vì sao backup manifest pass vẫn phải restore drill?

Manifest/checksum phát hiện nhiều lỗi file/WAL nhưng không mô phỏng mọi kiểm tra startup, extension,
configuration hay business correctness.

### PITR cần những gì?

Một physical base backup kết thúc trước target, mọi incremental dependency nếu có, chuỗi WAL liên tục tới
target, timeline history, config/key/tool và môi trường restore đúng.

### `archive_timeout` càng thấp càng tốt không?

Không. Nó giảm thời gian segment chưa đóng nhưng mỗi forced segment vẫn tốn archive storage; quá thấp làm
phình storage/request. RPO thấp có thể cần streaming WAL path.

### Incremental backup PostgreSQL 18 có start trực tiếp được không?

Không. Phải dùng `pg_combinebackup` ghép full và các incremental dependency thành synthetic full rồi recovery
với WAL.

### `pg_upgrade --link` đánh đổi gì?

Nhanh và ít disk nhờ hard link, nhưng khi new cluster đã start các file shared có thể làm old cluster không
còn an toàn để start. Rollback cần snapshot/copy khác.

### Dump/restore và logical blue-green khác nhau ở đâu?

Dump/restore đơn giản hơn nhưng downtime theo data load. Blue-green replicate khi source đang chạy nên cutover
ngắn hơn, đổi lại phải quản lý DDL, sequence, slot, conflict và rollback write.

---

## 82. Nguồn và chủ đề tiếp theo

Nguồn chính thức PostgreSQL 18:

- [Backup and Restore](https://www.postgresql.org/docs/18/backup.html)
- [SQL Dump](https://www.postgresql.org/docs/18/backup-dump.html)
- [`pg_dump`](https://www.postgresql.org/docs/18/app-pgdump.html)
- [`pg_dumpall`](https://www.postgresql.org/docs/18/app-pg-dumpall.html)
- [`pg_restore`](https://www.postgresql.org/docs/18/app-pgrestore.html)
- [Continuous Archiving and PITR](https://www.postgresql.org/docs/18/continuous-archiving.html)
- [`pg_basebackup`](https://www.postgresql.org/docs/18/app-pgbasebackup.html)
- [`pg_verifybackup`](https://www.postgresql.org/docs/18/app-pgverifybackup.html)
- [`pg_combinebackup`](https://www.postgresql.org/docs/18/app-pgcombinebackup.html)
- [WAL and Recovery Target Configuration](https://www.postgresql.org/docs/18/runtime-config-wal.html)
- [`pg_upgrade`](https://www.postgresql.org/docs/18/pgupgrade.html)
- [Logical Replication Upgrade](https://www.postgresql.org/docs/18/logical-replication-upgrade.html)
- [PostgreSQL versioning policy](https://www.postgresql.org/support/versioning/)
- [pgBackRest User Guide](https://pgbackrest.org/user-guide.html)
- [Barman documentation](https://docs.pgbarman.org/)

Học tiếp:

1. [Security & Row-Level Security](security_rls.md).
2. [PostgreSQL từ Java/Spring](../integration/jdbc_spring.md).

---

*Cập nhật lần cuối: 2026-07-31.*
