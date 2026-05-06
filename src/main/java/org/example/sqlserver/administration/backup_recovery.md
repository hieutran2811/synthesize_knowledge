# SQL Server Backup & Recovery – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Backup & Recovery là gì?

**Backup** là tạo bản sao data để phục hồi khi có sự cố (hardware failure, data corruption, human error). **Recovery** là quá trình restore database về trạng thái nhất quán từ backups.

```
RTO (Recovery Time Objective):  Thời gian tối đa được phép downtime
RPO (Recovery Point Objective):  Lượng data tối đa có thể mất

RTO = 1h, RPO = 15min → backup mỗi 15min, restore trong 1h
```

---

## Components – Recovery Models

```sql
-- Recovery model quyết định: loại backup available + log truncation behavior

-- SIMPLE: log truncate tự động sau checkpoint
-- Không thể: point-in-time recovery, log backup
-- Dùng: dev/test, databases không yêu cầu PITR
ALTER DATABASE DevDB SET RECOVERY SIMPLE;

-- FULL: log không tự truncate (chỉ sau LOG BACKUP)
-- Có thể: full point-in-time recovery
-- Yêu cầu: phải có LOG BACKUP job
-- Dùng: production databases
ALTER DATABASE ProdDB SET RECOVERY FULL;

-- BULK_LOGGED: minimal logging cho bulk ops (BULK INSERT, CREATE INDEX, SELECT INTO)
-- Không thể: PITR trong khoảng có bulk ops
-- Dùng: ETL windows - switch to BULK_LOGGED → bulk load → switch back to FULL
ALTER DATABASE ProdDB SET RECOVERY BULK_LOGGED;
```

---

## How – Backup Types

### Full Backup

```sql
-- Full backup: snapshot của toàn bộ database
BACKUP DATABASE SalesDB
TO DISK = 'E:\Backup\SalesDB_Full_20260506.bak'
WITH
    COMPRESSION,                    -- giảm 40-70% size, cần CPU
    CHECKSUM,                       -- verify backup integrity
    STATS = 10,                     -- hiển thị progress mỗi 10%
    FORMAT,                         -- overwrites existing media
    NAME = 'SalesDB Full Backup',
    DESCRIPTION = 'Weekly full backup';

-- Backup tới nhiều files (striped) để tăng throughput
BACKUP DATABASE SalesDB
TO
    DISK = 'E:\Backup\SalesDB_Full_1.bak',
    DISK = 'F:\Backup\SalesDB_Full_2.bak',
    DISK = 'G:\Backup\SalesDB_Full_3.bak'
WITH COMPRESSION, CHECKSUM, STATS = 5;

-- Backup tới URL (Azure Blob Storage)
BACKUP DATABASE SalesDB
TO URL = 'https://mystorageaccount.blob.core.windows.net/backups/SalesDB_Full.bak'
WITH CREDENTIAL = 'AzureStorageCredential', COMPRESSION, STATS = 10;
```

### Differential Backup

```sql
-- Differential: chỉ backup pages changed SINCE LAST FULL backup
-- Nhanh hơn full, nhưng cần full backup để restore
BACKUP DATABASE SalesDB
TO DISK = 'E:\Backup\SalesDB_Diff_20260506_1200.bak'
WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, STATS = 10;

-- Backup chain: Full → Diff1 → Diff2 → Diff3
-- Restore: chỉ cần Full + latest Diff (không cần mọi Diff)
```

### Transaction Log Backup

```sql
-- Log backup: backup transaction log (FULL/BULK-LOGGED model only)
-- Truncates inactive portion of log sau khi backup
BACKUP LOG SalesDB
TO DISK = 'E:\Backup\SalesDB_Log_20260506_143000.trn'
WITH COMPRESSION, CHECKSUM, STATS = 10;

-- Frequency: mỗi 5-15 phút cho production → RPO = 5-15 phút

-- Tail-log backup: backup log còn lại trước khi restore
-- Quan trọng: nếu bỏ qua → mất transactions từ last log backup đến failure time
BACKUP LOG SalesDB
TO DISK = 'E:\Backup\SalesDB_TailLog.trn'
WITH NORECOVERY, COMPRESSION, CHECKSUM;
-- NORECOVERY: database ở RESTORING state, sẵn sàng để apply
```

### Copy-Only Backup

```sql
-- Copy-only: không ảnh hưởng backup chain (differential base)
-- Dùng khi: tạo backup ad-hoc mà không muốn break chain
BACKUP DATABASE SalesDB
TO DISK = 'E:\Backup\SalesDB_CopyOnly.bak'
WITH COPY_ONLY, COMPRESSION;
```

---

## How – Restore Process

### Full Restore

```sql
-- 1. Tail-log backup (nếu database còn accessible)
BACKUP LOG SalesDB TO DISK = 'E:\Backup\SalesDB_TailLog.trn'
WITH NO_TRUNCATE, NORECOVERY;

-- 2. Restore Full backup
RESTORE DATABASE SalesDB
FROM DISK = 'E:\Backup\SalesDB_Full_20260506.bak'
WITH
    NORECOVERY,           -- keep DB in RESTORING, apply more backups
    MOVE 'SalesDB'      TO 'C:\Data\SalesDB.mdf',
    MOVE 'SalesDB_Log'  TO 'F:\Logs\SalesDB.ldf',
    STATS = 10,
    REPLACE;              -- override existing DB (cẩn thận!)

-- 3. Apply differential (nếu có)
RESTORE DATABASE SalesDB
FROM DISK = 'E:\Backup\SalesDB_Diff_20260506_1200.bak'
WITH NORECOVERY, STATS = 10;

-- 4. Apply log backups (in order)
RESTORE LOG SalesDB FROM DISK = 'E:\Backup\SalesDB_Log_20260506_1300.trn' WITH NORECOVERY;
RESTORE LOG SalesDB FROM DISK = 'E:\Backup\SalesDB_Log_20260506_1315.trn' WITH NORECOVERY;
RESTORE LOG SalesDB FROM DISK = 'E:\Backup\SalesDB_Log_20260506_1330.trn' WITH NORECOVERY;

-- 5. Tail-log
RESTORE LOG SalesDB FROM DISK = 'E:\Backup\SalesDB_TailLog.trn' WITH NORECOVERY;

-- 6. Bring database online
RESTORE DATABASE SalesDB WITH RECOVERY;
-- Sau RECOVERY: DB online, không thể apply thêm backups

-- Xem backup history
SELECT
    bs.database_name,
    bs.backup_start_date,
    bs.backup_finish_date,
    DATEDIFF(MINUTE, bs.backup_start_date, bs.backup_finish_date) AS DurationMin,
    bs.type AS BackupType,  -- D=Full, I=Differential, L=Log
    bs.backup_size / 1024 / 1024 AS SizeMB,
    bs.compressed_backup_size / 1024 / 1024 AS CompressedMB,
    bmf.physical_device_name
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
WHERE bs.database_name = 'SalesDB'
ORDER BY bs.backup_start_date DESC;
```

### Point-in-Time Recovery

```sql
-- Restore đến thời điểm cụ thể (FULL recovery model only)
-- Ví dụ: developer accidentally dropped table lúc 14:30
-- Restore đến 14:29:59

-- 1. Full backup + applicable Diff
RESTORE DATABASE SalesDB
FROM DISK = 'E:\Backup\SalesDB_Full.bak'
WITH NORECOVERY, MOVE ..., REPLACE;

-- 2. Apply log backups đến sát thời điểm muốn
RESTORE LOG SalesDB
FROM DISK = 'E:\Backup\SalesDB_Log_1300.trn'
WITH NORECOVERY;

-- 3. Áp log cuối với STOPAT
RESTORE LOG SalesDB
FROM DISK = 'E:\Backup\SalesDB_Log_1400.trn'
WITH NORECOVERY,
     STOPAT = '2026-05-06 14:29:59';  -- dừng tại đây

RESTORE DATABASE SalesDB WITH RECOVERY;

-- Hoặc dùng STOPBEFOREMARK (LSN/mark based)
RESTORE LOG SalesDB
FROM DISK = '...'
WITH NORECOVERY,
     STOPBEFOREMARK = 'lsn:0x...' AFTER '2026-05-06T14:00:00';
```

### Page-Level Restore

```sql
-- Chỉ restore 1 hoặc vài pages bị corrupt (không cần full DB restore)
-- Database vẫn online trong quá trình restore!

-- Xem damaged pages
SELECT database_id, file_id, page_id, error_type, last_update_date
FROM msdb.dbo.suspect_pages
WHERE error_type = 1;  -- 1=823/824/829 errors

-- Restore specific pages
RESTORE DATABASE SalesDB
PAGE = '1:23456'        -- file:page
FROM DISK = 'E:\Backup\SalesDB_Full.bak'
WITH NORECOVERY;

-- Apply logs
RESTORE LOG SalesDB FROM DISK = 'E:\Backup\...' WITH NORECOVERY;
RESTORE DATABASE SalesDB WITH RECOVERY;
```

---

## How – Backup Verification

```sql
-- RESTORE VERIFYONLY: check backup là valid (không restore)
RESTORE VERIFYONLY
FROM DISK = 'E:\Backup\SalesDB_Full.bak'
WITH CHECKSUM;

-- DBCC CHECKDB: check database integrity
DBCC CHECKDB('SalesDB') WITH NO_INFOMSGS, ALL_ERRORMSGS;

-- DBCC CHECKDB sau restore để verify
-- Thêm vào maintenance schedule: weekly DBCC CHECKDB

-- Automated backup verification job
-- Ola Hallengren: DatabaseIntegrityCheck

-- Restore test (monthly/quarterly):
-- Restore backup tới test server → run DBCC CHECKDB → verify data
```

---

## How – Backup Schedule (Production Standard)

```
Strategy: Full weekly + Diff daily + Log every 15min

Sunday 11PM:  Full backup (~2h for 1TB)
Mon-Sat 11PM: Differential backup (~30min)
Every 15min:  Log backup (~1-5min)

RPO = 15 minutes (max data loss)
RTO = Full restore + apply Diff + apply ~X logs

Retention:
  Full: 4 weeks
  Diff: 1 week
  Log:  2 weeks (enough for PITR)

Storage:
  Primary: NAS/SAN (fast restore)
  Secondary: Azure Blob / S3 (offsite DR)
  Immutable: Veeam/Azure Backup (ransomware protection)
```

```sql
-- SQL Agent Job: Ola Hallengren (industry standard)
EXEC dbo.DatabaseBackup
    @Databases = 'USER_DATABASES',
    @BackupType = 'FULL',
    @Directory = 'E:\Backup',
    @BackupSoftware = NULL,
    @CleanupTime = 168,          -- xóa backup cũ hơn 168h (7 days)
    @Compress = 'Y',
    @Checksum = 'Y',
    @Verify = 'Y',
    @LogToTable = 'Y';

EXEC dbo.DatabaseBackup
    @Databases = 'USER_DATABASES',
    @BackupType = 'LOG',
    @Directory = 'E:\Backup\Logs',
    @CleanupTime = 336,           -- giữ 2 tuần logs
    @Compress = 'Y',
    @Checksum = 'Y';
```

---

## Compare – Backup Strategies

| Strategy | RTO | RPO | Storage | Complexity |
|----------|-----|-----|---------|------------|
| Full only (weekly) | Hours | Days | Low | Simple |
| Full + Log | Hours | Minutes | Medium | Medium |
| Full + Diff + Log | 30-60min | Minutes | Medium | Medium |
| AlwaysOn AG + Backup | Minutes | Seconds | High | Complex |
| Continuous Log Shipping | Minutes | Seconds | Medium | Medium |

---

## Trade-offs

```
Full backup frequency:
✅ Faster restore (fewer logs to apply)
❌ Longer backup window, more storage

Differential backup:
✅ Smaller than full, fewer logs to apply than log-only
❌ Grows throughout week → by day 6, similar size to full
❌ Only 1 Diff needed per restore (latest one)

Log backup frequency:
High frequency (5min): RPO = 5min, more files to manage
Low frequency (1h):    RPO = 1h, simpler management
→ Balance RPO requirement vs operational complexity

Compression:
✅ 50-70% smaller, faster network transfer
❌ CPU overhead during backup (use MAXTRANSFERSIZE and BLOCKSIZE tuning)
→ Enable by default: sp_configure 'backup compression default', 1
```

---

## Real-world – DR Testing Checklist

```
Monthly DR Test:
□ Restore latest full backup to DR server
□ Apply latest diff + logs
□ Run DBCC CHECKDB
□ Validate: row counts, spot-check data
□ Measure actual RTO (record it)
□ Document any issues

Quarterly Full DR Drill:
□ Simulate primary failure
□ Promote DR server
□ Update connection strings
□ Verify all applications connect
□ Fail back to primary

Monitoring:
□ Alert when backup has not run in > 25h (full) / 1h (log)
□ Monitor backup file sizes (sudden change = anomaly)
□ Check msdb.dbo.suspect_pages weekly
□ CHECKDB results: alert on any errors
```

---

## Ghi chú – Chủ đề tiếp theo
> `administration/ha_dr.md`: AlwaysOn Availability Groups, Log Shipping, Database Mirroring (deprecated), Replication

---

*Cập nhật lần cuối: 2026-05-06*
