---
title: "SQL Server Backup & Recovery"
topic: sqlserver
level: mixed
review_status: needs_review
content_updated: 2026-07-30
last_verified: null
version_scope: "SQL Server 2022 (16"
source_count: 2
---
# SQL Server Backup & Recovery

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Backup/restore tới S3-compatible object storage là tính năng của 2022 trở lên.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Architecture](../fundamentals/architecture.md) mục 7 (transaction log). Đọc tiếp: [HA & DR](ha_dr.md).

---

## 1. Backup không phải mục tiêu — restore mới là mục tiêu

Câu hỏi đúng không phải "chúng ta có backup không?" mà là **"lần cuối chúng ta restore thành công là khi nào, và mất bao lâu?"**. Rất nhiều tổ chức có job backup xanh suốt 3 năm rồi phát hiện không restore được: certificate TDE bị mất, backup chain đứt, hoặc đơn giản là chưa ai từng thử.

Hai con số định nghĩa toàn bộ thiết kế:

```text
RPO (Recovery Point Objective) : được phép mất tối đa bao nhiêu dữ liệu (tính theo thời gian)
RTO (Recovery Time Objective)  : được phép mất tối đa bao lâu để trở lại hoạt động

Ví dụ: RPO 15 phút, RTO 1 giờ
  → log backup mỗi 15 phút
  → và toàn bộ chuỗi restore phải hoàn tất trong 60 phút — phải ĐO, không giả định
```

RPO quyết định **tần suất backup**; RTO quyết định **chiến lược restore** (và nhiều khi buộc phải dùng Always On thay vì chỉ backup — xem [ha_dr.md](ha_dr.md)).

Điều cần nói thêm: backup **không** phải giải pháp cho ransomware nếu backup nằm trên cùng hệ thống file mà kẻ tấn công chạm được. Yêu cầu tối thiểu là một bản sao ở nơi khác và **không thể ghi đè** (immutable/WORM).

---

## 2. Recovery model quyết định những gì có thể làm

```sql
SELECT name, recovery_model_desc, log_reuse_wait_desc,
       is_read_committed_snapshot_on, is_accelerated_database_recovery_on
FROM sys.databases WHERE database_id > 4;

ALTER DATABASE SalesDB SET RECOVERY FULL;
```

| Model | Log backup | PITR | Bulk operation ghi log | Dùng cho |
|---|---|---|---|---|
| **SIMPLE** | Không được | Không | Tối thiểu | Dev/test, DW nạp lại được từ nguồn |
| **FULL** | Bắt buộc | Có | Đầy đủ | Mặc định cho production |
| **BULK_LOGGED** | Có | Không, cho khoảng chứa bulk | Tối thiểu | Cửa sổ ETL/index rebuild lớn |

Cạm bẫy quan trọng nhất trong toàn bộ chủ đề backup: **đặt FULL mà không có job `BACKUP LOG`**. Log sẽ tăng đến khi hết đĩa, và khi đó database dừng nhận write. Kiểm tra định kỳ:

```sql
-- Database ở FULL/BULK_LOGGED mà chưa có log backup trong 1 giờ
SELECT d.name, d.recovery_model_desc, d.log_reuse_wait_desc,
       MAX(b.backup_finish_date) AS LastLogBackup,
       DATEDIFF(MINUTE, MAX(b.backup_finish_date), SYSDATETIME()) AS MinutesAgo
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b
       ON b.database_name = d.name AND b.type = 'L'
WHERE d.recovery_model_desc <> 'SIMPLE' AND d.database_id > 4
GROUP BY d.name, d.recovery_model_desc, d.log_reuse_wait_desc
HAVING MAX(b.backup_finish_date) IS NULL
    OR DATEDIFF(MINUTE, MAX(b.backup_finish_date), SYSDATETIME()) > 60;
```

### 2.1 BULK_LOGGED dùng đúng cách

```sql
BACKUP LOG SalesDB TO DISK = '/backup/log/pre_etl.trn';   -- chốt điểm PITR trước
ALTER DATABASE SalesDB SET RECOVERY BULK_LOGGED;

-- ... bulk insert / index rebuild lớn ...

ALTER DATABASE SalesDB SET RECOVERY FULL;
BACKUP LOG SalesDB TO DISK = '/backup/log/post_etl.trn';  -- chốt lại ngay
```

Trong khoảng BULK_LOGGED, log backup vẫn chạy được nhưng **PITR tới một thời điểm bên trong khoảng đó là không thể** — chỉ restore được tới đầu hoặc cuối khoảng. Vì vậy hai lệnh `BACKUP LOG` bọc hai đầu là bắt buộc, không phải tùy chọn.

---

## 3. Các loại backup

### 3.1 Full

```sql
BACKUP DATABASE SalesDB
TO DISK = '/backup/full/SalesDB_20260730.bak'
WITH
    COMPRESSION,            -- giảm 50–70% dung lượng, tốn CPU
    CHECKSUM,               -- xác minh checksum của từng page khi đọc
    STATS = 5,
    INIT,                   -- ghi đè media set này (khác FORMAT: FORMAT xóa cả media header)
    NAME = 'SalesDB full',
    MAXTRANSFERSIZE = 4194304,   -- 4MB: cải thiện throughput trên storage nhanh
    BLOCKSIZE = 65536,
    BUFFERCOUNT = 50;

-- Chia nhiều file để tăng throughput (mỗi file một luồng ghi)
BACKUP DATABASE SalesDB
TO DISK = '/backup1/SalesDB_1.bak',
   DISK = '/backup2/SalesDB_2.bak',
   DISK = '/backup3/SalesDB_3.bak',
   DISK = '/backup4/SalesDB_4.bak'
WITH COMPRESSION, CHECKSUM, STATS = 5;
```

Chia file (striping) là cách đơn giản nhất để cắt thời gian backup của database lớn — nhưng nhớ rằng **mất một file là mất cả bộ**. Ba tham số `MAXTRANSFERSIZE`/`BUFFERCOUNT`/`BLOCKSIZE` là nơi để tune khi backup là điểm nghẽn; mặc định thường đủ cho hệ vừa.

Lưu ý về `MAXTRANSFERSIZE`: nếu database bật TDE, đặt `MAXTRANSFERSIZE > 65536` là điều kiện để backup compression hoạt động cùng TDE (ở các version từ 2016 trở đi).

### 3.2 Differential

```sql
BACKUP DATABASE SalesDB
TO DISK = '/backup/diff/SalesDB_20260730_1200.bak'
WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, STATS = 10;
```

Differential chứa mọi page đã đổi **kể từ full backup gần nhất** (dựa vào Differential Changed Map — xem [architecture.md](../fundamentals/architecture.md) mục 4.1). Vì vậy:

- Restore chỉ cần **full + differential mới nhất**, không cần các differential trung gian.
- Kích thước phình dần theo thời gian kể từ full: đến cuối tuần có thể gần bằng full.
- Một `COPY_ONLY` full **không** reset DCM, nên không làm đứt chuỗi differential — đây chính là mục đích của `COPY_ONLY`.

```sql
-- Backup ad-hoc (ví dụ trước khi deploy) mà không làm hỏng chuỗi diff
BACKUP DATABASE SalesDB TO DISK = '/backup/adhoc/pre_deploy.bak'
WITH COPY_ONLY, COMPRESSION, CHECKSUM;
```

### 3.3 Log

```sql
BACKUP LOG SalesDB
TO DISK = '/backup/log/SalesDB_20260730_143000.trn'
WITH COMPRESSION, CHECKSUM, STATS = 25;
```

Log backup có hai chức năng cùng lúc: cho phép PITR **và** cho phép truncate phần log không còn cần. Đây là lý do không thể "tắt log backup cho nhẹ".

Tần suất = RPO. RPO 15 phút → log backup mỗi 15 phút. Không có lý do kỹ thuật nào ngăn chạy mỗi 5 phút hay mỗi phút nếu RPO đòi hỏi; chi phí là số file phải quản lý.

### 3.4 Tail-log backup — bước bị bỏ quên nhiều nhất

```sql
-- Trường hợp database còn truy cập được: chụp phần log chưa backup
BACKUP LOG SalesDB TO DISK = '/backup/log/SalesDB_tail.trn'
WITH NORECOVERY, CHECKSUM;
-- NORECOVERY: sau lệnh này database ở trạng thái RESTORING, sẵn sàng nhận restore

-- Trường hợp data file đã hỏng nhưng log file còn: vẫn cứu được phần cuối
BACKUP LOG SalesDB TO DISK = '/backup/log/SalesDB_tail.trn'
WITH NO_TRUNCATE, CONTINUE_AFTER_ERROR, CHECKSUM;
```

Bỏ qua tail-log = mất toàn bộ giao dịch từ log backup gần nhất tới thời điểm sự cố. Nếu log backup chạy mỗi 15 phút, đó là tối đa 15 phút dữ liệu bị mất **một cách không cần thiết**.

### 3.5 File / filegroup backup

```sql
BACKUP DATABASE SalesDB FILEGROUP = 'FG_Data'
TO DISK = '/backup/fg/SalesDB_FGData.bak' WITH COMPRESSION, CHECKSUM;

-- Filegroup read-only chỉ cần backup một lần
BACKUP DATABASE SalesDB FILEGROUP = 'FG_Archive'
TO DISK = '/backup/fg/SalesDB_FGArchive.bak' WITH COMPRESSION, CHECKSUM;
```

Đây là nền tảng của **piecemeal restore** (mục 5.4): với database nhiều TB đã partition theo vòng đời ([partitioning.md](../performance/partitioning.md)), có thể đưa filegroup nóng online trong ít phút rồi restore phần archive sau.

### 3.6 Backup tới object storage

```sql
-- Azure Blob Storage (SAS credential)
CREATE CREDENTIAL [https://acct.blob.core.windows.net/backups]
    WITH IDENTITY = 'SHARED ACCESS SIGNATURE', SECRET = 'sv=2022-11-02&ss=b&...';

BACKUP DATABASE SalesDB
TO URL = 'https://acct.blob.core.windows.net/backups/SalesDB_full.bak'
WITH COMPRESSION, CHECKSUM, STATS = 5;

-- S3-compatible object storage (SQL Server 2022+) — dùng được với MinIO, Ceph, AWS S3
CREATE CREDENTIAL [s3://minio.corp.local:9000/mssql-backup]
    WITH IDENTITY = 'S3 Access Key', SECRET = '<access_key>:<secret_key>';

BACKUP DATABASE SalesDB
TO URL = 's3://minio.corp.local:9000/mssql-backup/SalesDB_full.bak'
WITH COMPRESSION, CHECKSUM, STATS = 5, MAXTRANSFERSIZE = 20971520, BACKUP_OPTIONS = '{"s3": {"multipart_size": 20}}';
```

Backup tới S3-compatible là bổ sung đáng chú ý của 2022: nó cho phép dùng chính hạ tầng object storage của on-prem (MinIO/Ceph) làm đích backup, kèm khả năng bật object lock/versioning ở phía storage để có **immutability** chống ransomware — điều rất khó làm với file share thông thường.

---

## 4. Backup encryption và TDE

### 4.1 Backup encryption

```sql
USE master;
CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<strong>';
CREATE CERTIFICATE BackupCert WITH SUBJECT = 'Backup encryption';

-- BẮT BUỘC: backup certificate ra ngoài, giữ ở nơi khác
BACKUP CERTIFICATE BackupCert TO FILE = '/secure/BackupCert.cer'
WITH PRIVATE KEY (FILE = '/secure/BackupCert.pvk', ENCRYPTION BY PASSWORD = '<strong2>');

BACKUP DATABASE SalesDB TO DISK = '/backup/full/SalesDB_enc.bak'
WITH COMPRESSION, CHECKSUM,
     ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = BackupCert);
```

### 4.2 Điểm chết người: certificate và restore

Nếu database bật TDE, **backup cũng được mã hóa**, và không có certificate thì file backup là vô dụng. Đây là nguyên nhân thật của nhiều thất bại DR.

```sql
-- Danh sách certificate và ngày backup certificate gần nhất — nên kiểm tra hàng tháng
SELECT c.name, c.subject, c.expiry_date,
       c.pvt_key_last_backup_date,
       CASE WHEN c.pvt_key_last_backup_date IS NULL THEN 'CHƯA BACKUP - RỦI RO'
            ELSE 'OK' END AS Status
FROM sys.certificates c;

-- Database nào đang mã hóa và bằng cái gì
SELECT DB_NAME(dek.database_id) AS DbName, dek.encryption_state_desc,
       dek.key_algorithm, dek.key_length, dek.encryptor_type, dek.percent_complete
FROM sys.dm_database_encryption_keys dek;
```

Checklist quản lý khóa:

```text
□ Certificate/asymmetric key đã backup ra file, kèm private key
□ File certificate + mật khẩu private key lưu ở NƠI KHÁC với backup database
□ Mật khẩu private key có trong hệ quản lý bí mật (Vault/Key Vault), không trong wiki
□ Có quy trình kiểm tra restore trên server MỚI (chưa có cert) mỗi quý
□ Ngày hết hạn certificate được theo dõi
□ Khi rotate cert: giữ cert cũ đủ lâu để restore mọi backup còn trong retention
```

Điểm cuối rất dễ sai: rotate certificate rồi xóa cert cũ, nhưng backup 6 tháng trước vẫn được mã hóa bằng cert cũ.

---

## 5. Restore

### 5.1 Chuỗi restore đầy đủ

```sql
-- Bước 0: tail-log nếu instance còn sống
BACKUP LOG SalesDB TO DISK = '/backup/log/tail.trn' WITH NORECOVERY, CHECKSUM;

-- Bước 1: full
RESTORE DATABASE SalesDB
FROM DISK = '/backup/full/SalesDB_20260730.bak'
WITH NORECOVERY, REPLACE, STATS = 5,
     MOVE 'SalesDB_Data' TO '/var/opt/mssql/data/SalesDB.mdf',
     MOVE 'SalesDB_Log'  TO '/var/opt/mssql/log/SalesDB.ldf';

-- Bước 2: differential mới nhất (bỏ qua các diff trung gian)
RESTORE DATABASE SalesDB
FROM DISK = '/backup/diff/SalesDB_20260730_1200.bak' WITH NORECOVERY, STATS = 10;

-- Bước 3: các log backup theo đúng thứ tự
RESTORE LOG SalesDB FROM DISK = '/backup/log/SalesDB_20260730_1215.trn' WITH NORECOVERY;
RESTORE LOG SalesDB FROM DISK = '/backup/log/SalesDB_20260730_1230.trn' WITH NORECOVERY;
RESTORE LOG SalesDB FROM DISK = '/backup/log/tail.trn'                  WITH NORECOVERY;

-- Bước 4: mở database
RESTORE DATABASE SalesDB WITH RECOVERY;
```

`NORECOVERY` giữ database ở trạng thái `RESTORING` để còn apply tiếp; `RECOVERY` hoàn tất và **không thể apply thêm** sau đó. Sai bước này là lỗi phải làm lại từ đầu — nên trong tình huống thật, hãy sinh script trước rồi mới chạy.

```sql
-- Sinh chuỗi restore từ lịch sử backup: an toàn hơn viết tay lúc sự cố
SELECT
    ROW_NUMBER() OVER (ORDER BY bs.backup_finish_date) AS Seq,
    bs.type,      -- D = full, I = diff, L = log
    bs.backup_finish_date,
    CASE bs.type
        WHEN 'D' THEN 'RESTORE DATABASE [' + bs.database_name + '] FROM DISK = N'''
                      + bmf.physical_device_name + ''' WITH NORECOVERY, REPLACE, STATS=5;'
        WHEN 'I' THEN 'RESTORE DATABASE [' + bs.database_name + '] FROM DISK = N'''
                      + bmf.physical_device_name + ''' WITH NORECOVERY, STATS=10;'
        WHEN 'L' THEN 'RESTORE LOG ['      + bs.database_name + '] FROM DISK = N'''
                      + bmf.physical_device_name + ''' WITH NORECOVERY;'
    END AS RestoreCmd
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name = 'SalesDB'
  AND bs.backup_finish_date >= (
        SELECT MAX(backup_finish_date) FROM msdb.dbo.backupset
        WHERE database_name = 'SalesDB' AND type = 'D')
ORDER BY bs.backup_finish_date;
```

### 5.2 Point-in-time recovery

```sql
-- Ai đó DROP TABLE lúc 14:32. Restore về 14:31:30.
RESTORE DATABASE SalesDB_Recover
FROM DISK = '/backup/full/SalesDB_20260730.bak'
WITH NORECOVERY, MOVE 'SalesDB_Data' TO '/var/opt/mssql/data/SalesDB_Recover.mdf',
                 MOVE 'SalesDB_Log'  TO '/var/opt/mssql/log/SalesDB_Recover.ldf';

RESTORE DATABASE SalesDB_Recover
FROM DISK = '/backup/diff/SalesDB_20260730_1200.bak' WITH NORECOVERY;

RESTORE LOG SalesDB_Recover FROM DISK = '/backup/log/SalesDB_1415.trn' WITH NORECOVERY;
RESTORE LOG SalesDB_Recover FROM DISK = '/backup/log/SalesDB_1430.trn' WITH NORECOVERY;
RESTORE LOG SalesDB_Recover FROM DISK = '/backup/log/SalesDB_1445.trn'
WITH NORECOVERY, STOPAT = '2026-07-30T14:31:30';

RESTORE DATABASE SalesDB_Recover WITH RECOVERY;
```

Chi tiết quan trọng về quy trình: **restore ra một database mới, không ghi đè database production**. Sau đó lấy bảng bị xóa và chuyển sang. Cách này giữ nguyên các giao dịch sau 14:32 mà nghiệp vụ vẫn cần — trong khi restore đè production sẽ mất chúng.

Khi cần chính xác đến từng transaction, dùng LSN thay vì thời gian:

```sql
RESTORE LOG SalesDB_Recover FROM DISK = '/backup/log/SalesDB_1445.trn'
WITH NORECOVERY, STOPBEFOREMARK = 'lsn:0x0000002a:000004b8:0001';
```

### 5.3 Page-level restore

```sql
SELECT DB_NAME(database_id) AS DbName, file_id, page_id, event_type, error_count, last_update_date
FROM msdb.dbo.suspect_pages;

-- Database vẫn ONLINE trong lúc restore page (Enterprise; Standard yêu cầu offline)
RESTORE DATABASE SalesDB PAGE = '1:23456, 1:23457'
FROM DISK = '/backup/full/SalesDB_20260730.bak' WITH NORECOVERY;

RESTORE LOG SalesDB FROM DISK = '/backup/log/SalesDB_1430.trn' WITH NORECOVERY;
BACKUP LOG SalesDB TO DISK = '/backup/log/tail_for_page.trn';
RESTORE LOG SalesDB FROM DISK = '/backup/log/tail_for_page.trn' WITH RECOVERY;
```

Đây là công cụ đúng cho corruption cục bộ vài page — nhanh hơn restore cả database hàng TB rất nhiều.

### 5.4 Piecemeal restore

```sql
-- Chỉ đưa filegroup PRIMARY + FG_Data online trước
RESTORE DATABASE SalesDB FILEGROUP = 'PRIMARY', FILEGROUP = 'FG_Data'
FROM DISK = '/backup/full/SalesDB_20260730.bak'
WITH PARTIAL, NORECOVERY;

RESTORE LOG SalesDB FROM DISK = '/backup/log/SalesDB_1430.trn' WITH NORECOVERY;
RESTORE DATABASE SalesDB WITH RECOVERY;
-- → Database online. Truy vấn chạm FG_Archive sẽ lỗi cho tới khi restore tiếp.

-- Restore phần còn lại sau, không cần downtime nữa
RESTORE DATABASE SalesDB FILEGROUP = 'FG_Archive'
FROM DISK = '/backup/fg/SalesDB_FGArchive.bak' WITH RECOVERY;
```

Piecemeal restore là cách hiệu quả nhất để cắt RTO của database rất lớn, và là lý do vận hành mạnh nhất để thiết kế nhiều filegroup.

### 5.5 Ước lượng và theo dõi RTO

```sql
-- Tiến độ restore đang chạy
SELECT session_id, command, percent_complete,
       estimated_completion_time / 60000.0 AS EstMinLeft,
       total_elapsed_time / 60000.0        AS ElapsedMin
FROM sys.dm_exec_requests
WHERE command IN ('RESTORE DATABASE','RESTORE LOG','BACKUP DATABASE','BACKUP LOG');

-- Thời gian backup/restore lịch sử → cơ sở để ước lượng RTO thật
SELECT bs.database_name, bs.type,
       AVG(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date)) AS AvgSec,
       MAX(DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date)) AS MaxSec,
       AVG(bs.backup_size / 1048576.0)            AS AvgSizeMB,
       AVG(bs.compressed_backup_size / 1048576.0) AS AvgCompressedMB
FROM msdb.dbo.backupset bs
WHERE bs.backup_start_date > DATEADD(DAY, -30, SYSDATETIME())
GROUP BY bs.database_name, bs.type;
```

Restore thường **chậm hơn** backup (phải zero-out file nếu không có Instant File Initialization, phải redo log). RTO công bố phải dựa trên **thời gian restore đo được**, không phải thời gian backup.

---

## 6. Xác minh backup

```sql
-- Kiểm tra file backup đọc được và checksum đúng (không restore)
RESTORE VERIFYONLY FROM DISK = '/backup/full/SalesDB_20260730.bak' WITH CHECKSUM;

-- Xem nội dung: có những gì trong media set
RESTORE HEADERONLY  FROM DISK = '/backup/full/SalesDB_20260730.bak';
RESTORE FILELISTONLY FROM DISK = '/backup/full/SalesDB_20260730.bak';
RESTORE LABELONLY   FROM DISK = '/backup/full/SalesDB_20260730.bak';
```

Cần hiểu giới hạn: `VERIFYONLY` kiểm tra **cấu trúc và checksum của file backup**, không kiểm tra tính toàn vẹn logic của dữ liệu bên trong. Chuỗi xác minh đầy đủ là:

```text
1. BACKUP ... WITH CHECKSUM      → phát hiện page hỏng ngay lúc backup
2. RESTORE VERIFYONLY WITH CHECKSUM → file backup không bị hỏng trên đường lưu trữ
3. RESTORE thật ra server test    → chuỗi backup thực sự dùng được
4. DBCC CHECKDB trên bản restore  → dữ liệu bên trong toàn vẹn
5. Kiểm tra nghiệp vụ (row count, spot-check) → dữ liệu đúng như mong đợi
```

Chỉ bước 3–5 mới trả lời được câu hỏi ở mục 1. Và bước 3–4 chạy trên server test còn cho lợi ích kép: giảm tải CHECKDB khỏi production.

---

## 7. Lịch backup production

```text
Cấu hình tham chiếu cho RPO 15 phút / RTO 1 giờ:

  Chủ nhật 23:00   : FULL      (nén, checksum, striped nếu lớn)
  Thứ 2–7  23:00   : DIFF
  Mỗi 15 phút      : LOG
  Trước mỗi deploy : COPY_ONLY FULL

Retention:
  FULL : 4 tuần tại chỗ + 12 tháng ở object storage (immutable)
  DIFF : 1 tuần
  LOG  : 2 tuần (phải đủ để PITR về bất kỳ điểm trong 2 tuần)

Lưu trữ 3-2-1:
  3 bản sao, 2 loại phương tiện, 1 bản ở ngoài site
  + 1 bản immutable (object lock) chống ransomware
```

### 7.1 Ola Hallengren – chuẩn thực tế

```sql
-- FULL hàng tuần
EXEC dbo.DatabaseBackup
    @Databases = 'USER_DATABASES', @Directory = '/backup', @BackupType = 'FULL',
    @Compress = 'Y', @Checksum = 'Y', @Verify = 'Y',
    @CleanupTime = 672,               -- giữ 28 ngày
    @NumberOfFiles = 4,               -- striping
    @LogToTable = 'Y';

-- DIFF hàng ngày
EXEC dbo.DatabaseBackup
    @Databases = 'USER_DATABASES', @Directory = '/backup', @BackupType = 'DIFF',
    @Compress = 'Y', @Checksum = 'Y', @CleanupTime = 168, @LogToTable = 'Y';

-- LOG mỗi 15 phút
EXEC dbo.DatabaseBackup
    @Databases = 'USER_DATABASES', @Directory = '/backup', @BackupType = 'LOG',
    @Compress = 'Y', @Checksum = 'Y', @CleanupTime = 336, @LogToTable = 'Y';

-- CHECKDB hàng tuần
EXEC dbo.DatabaseIntegrityCheck
    @Databases = 'USER_DATABASES', @CheckCommands = 'CHECKDB',
    @LogToTable = 'Y', @TimeLimit = 7200;
```

Hai điểm cấu hình quan trọng: `@CleanupTime` phải **dài hơn** khoảng bạn cần PITR (nếu log chỉ giữ 3 ngày thì PITR chỉ được 3 ngày, bất kể full giữ bao lâu), và `@LogToTable = 'Y'` để có lịch sử job trong `dbo.CommandLog` phục vụ điều tra.

### 7.2 Alert cần có

| Alert | Ngưỡng | Vì sao |
|---|---|---|
| Full backup trễ | > 25 giờ (với lịch hàng ngày) | Backup không chạy nghĩa là RPO đã vỡ mà không ai biết |
| Log backup trễ | > 2× khoảng lịch | Vừa vỡ RPO vừa nguy cơ log đầy |
| Kích thước backup thay đổi đột ngột | ±30% so với trung bình 7 ngày | Có thể là dữ liệu bị xóa hàng loạt, hoặc backup không đầy đủ |
| `RESTORE VERIFYONLY` thất bại | Bất kỳ | Backup đã hỏng |
| `msdb.dbo.suspect_pages` có dòng mới | Bất kỳ | Corruption đang xảy ra |
| CHECKDB báo lỗi | Bất kỳ | Ưu tiên cao nhất |
| Certificate chưa backup | `pvt_key_last_backup_date IS NULL` | Backup mã hóa không restore được |
| Đĩa backup còn < 20% | – | Backup sắp thất bại |

---

## 8. DR drill – phần không thể bỏ

```text
Hàng tháng (tự động hóa được):
□ Restore full + diff + log mới nhất sang server test
□ DBCC CHECKDB trên bản restore
□ Kiểm tra row count các bảng chính so với production
□ ĐO thời gian restore thực tế, ghi lại
□ So sánh thời gian đo được với RTO đã công bố

Hàng quý (có người tham gia):
□ Giả lập mất primary hoàn toàn
□ Restore lên hạ tầng DR từ bản backup ở ngoài site
□ Restore trên server CHƯA CÓ certificate TDE (kiểm tra quy trình khóa)
□ Đổi connection string, xác nhận ứng dụng kết nối được
□ Kiểm tra nghiệp vụ đầu-cuối
□ Fail back
□ Cập nhật runbook theo những gì thực tế đã vấp

Hàng năm:
□ Diễn tập ransomware: restore từ bản immutable, giả định mọi bản online đã bị mã hóa
□ Rà soát lại RPO/RTO với bên nghiệp vụ (yêu cầu có thể đã đổi)
```

Script tự động hóa DR drill hàng tháng (khung):

```sql
-- Trên server test: restore bản mới nhất rồi CHECKDB, ghi kết quả vào bảng
DECLARE @start DATETIME2 = SYSDATETIME();
-- ... sinh và chạy chuỗi RESTORE như mục 5.1 ...
DBCC CHECKDB('SalesDB_DrillTest') WITH NO_INFOMSGS, ALL_ERRORMSGS;

INSERT INTO Ops.DrDrillLog (DrillDate, DatabaseName, RestoreSeconds, CheckDbResult)
VALUES (@start, 'SalesDB', DATEDIFF(SECOND, @start, SYSDATETIME()), 'OK');
```

---

## 9. Compare – chiến lược backup

| Chiến lược | RPO | RTO | Dung lượng | Độ phức tạp |
|---|---|---|---|---|
| Chỉ FULL hàng tuần | Tới 7 ngày | Giờ | Thấp | Rất đơn giản |
| FULL + LOG | Phút | Giờ (nhiều log phải apply) | Trung bình | Đơn giản |
| FULL + DIFF + LOG | Phút | 30–60 phút | Trung bình | Trung bình |
| + Piecemeal (filegroup) | Phút | Phút cho phần nóng | Trung bình | Cao |
| Always On AG + backup trên secondary | Giây | Giây–phút (failover) | Cao | Cao |
| Snapshot backup (2022+, có `SUSPEND_FOR_SNAPSHOT_BACKUP`) | Phút | Rất nhanh (snapshot storage) | Theo storage | Cao, phụ thuộc hạ tầng |

**Always On không thay thế backup.** Nó bảo vệ khỏi mất node, không bảo vệ khỏi `DELETE` sai, corruption logic, hay ransomware — vì những thứ đó được replicate sang secondary ngay lập tức. Hai cơ chế giải hai bài toán khác nhau và cần cả hai.

SQL Server 2022 bổ sung snapshot backup thuần T-SQL:

```sql
ALTER DATABASE SalesDB SET SUSPEND_FOR_SNAPSHOT_BACKUP = ON;   -- đóng băng I/O
-- ... hạ tầng storage tạo snapshot ...
BACKUP DATABASE SalesDB TO DISK = '/backup/meta/SalesDB_snap.bkm' WITH METADATA_ONLY;
-- I/O tự động resume sau khi backup metadata hoàn tất
```

Điều này cho phép backup database rất lớn gần như tức thời, với điều kiện storage hỗ trợ snapshot nhất quán.

---

## 10. Trade-offs

| Quyết định | Được | Mất | Cách chọn |
|---|---|---|---|
| `COMPRESSION` | Backup nhanh hơn, ít dung lượng, ít băng thông | CPU cao hơn khi backup | Bật mặc định; tắt nếu CPU là điểm nghẽn |
| `CHECKSUM` | Phát hiện corruption sớm | Chút CPU | Luôn bật |
| Log backup mỗi 5 phút | RPO 5 phút | Nhiều file, nhiều bước restore | Theo yêu cầu nghiệp vụ, không theo cảm giác |
| Nhiều DIFF trong tuần | Restore nhanh hơn log-only | Dung lượng, và DIFF phình dần | Phổ biến: full tuần + diff ngày |
| Striping nhiều file | Backup nhanh hơn nhiều | Mất một file là mất cả bộ | Database lớn, đích ghi song song được |
| Backup encryption | Backup bị lấy cũng không đọc được | Rủi ro mất khóa = mất dữ liệu | Bắt buộc nếu backup ra ngoài site |
| Backup trên secondary AG | Giảm tải primary | Chỉ COPY_ONLY full; log backup thì được bình thường | Có AG thì nên dùng |
| Snapshot backup | Gần như tức thời | Phụ thuộc hạ tầng storage | Database rất lớn, storage hỗ trợ |

---

## 11. Ghi chú – chủ đề tiếp theo

- [ha_dr.md](ha_dr.md): Always On, log shipping, failover — bổ trợ chứ không thay thế backup.
- [security.md](security.md): TDE, quản lý certificate, quyền backup.
- [partitioning.md](../performance/partitioning.md): filegroup read-only và piecemeal restore.
- [monitoring_troubleshooting.md](../performance/monitoring_troubleshooting.md): alert backup, `suspect_pages`, CHECKDB.

Từ khóa mở rộng: `sys.fn_dblog`, `STANDBY` restore (read-only giữa các log restore), `RESTORE ... WITH KEEP_REPLICATION`, mirrored backup media set, `backupset.is_snapshot`, Azure Backup for SQL Server in VM, `sp_delete_backuphistory` (dọn msdb).

---

*Cập nhật lần cuối: 2026-07-30*
