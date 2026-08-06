# SQL Server High Availability & Disaster Recovery

> Mục tiêu phiên bản: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Contained AG là tính năng của 2022; Always On trên Linux dùng Pacemaker thay cho WSFC.
>
> Tra cứu nhanh: [SQL Server Glossary](../glossary.md). Nên đọc trước: [Backup & Recovery](backup_recovery.md), [Architecture](../fundamentals/architecture.md) mục 7. Đọc tiếp: [Security](security.md).

---

## 1. HA và DR trả lời hai câu hỏi khác nhau

| | HA (High Availability) | DR (Disaster Recovery) |
|---|---|---|
| Bảo vệ khỏi | Mất một node, patch, lỗi phần cứng đơn lẻ | Mất cả datacenter/region, ransomware, thảm họa |
| Phạm vi | Trong một site, độ trễ mạng thấp | Site khác, độ trễ cao hơn |
| Mục tiêu | RTO giây, RPO 0 | RTO phút–giờ, RPO giây–phút |
| Cơ chế điển hình | Always On sync, FCI | Always On async, log shipping, backup ở ngoài site |
| Tự động failover | Có | Thường không (quyết định của người) |

Một điều phải nói rõ ngay: **replication đồng bộ không phải backup**. Mọi thứ Always On bảo vệ đều là "mất hạ tầng". Một câu `DELETE` sai được replicate sang secondary trong vài mili giây. Vì vậy [backup_recovery.md](backup_recovery.md) và tài liệu này là hai lớp bảo vệ khác nhau, đều bắt buộc.

Ba câu hỏi cần trả lời **trước** khi chọn công nghệ:

1. RPO và RTO thật là bao nhiêu — do nghiệp vụ quyết định, có con số?
2. Ngân sách cho phép mấy bản sao dữ liệu, và edition nào (Standard vs Enterprise)?
3. Có yêu cầu đọc trên secondary (báo cáo, backup offload) không?

---

## 2. Always On Availability Groups

### 2.1 Kiến trúc

```text
Availability Group "AG_SALES"  (cluster: WSFC trên Windows, Pacemaker trên Linux)

  SQL1 (PRIMARY)        ── synchronous ──► SQL2 (SECONDARY, auto-failover, readable)
   │                                        cùng datacenter, RPO = 0
   └──────────────────── asynchronous ────► SQL3 (SECONDARY, DR site, manual failover)
                                            RPO = giây

  AG Listener "sales-listener" (virtual name + IP)
     ├── ApplicationIntent=ReadWrite  → PRIMARY
     └── ApplicationIntent=ReadOnly   → theo read-only routing list
```

Điểm cần hiểu về cách dữ liệu chảy:

```text
Primary: transaction ghi log record
   → gửi log block sang secondary (log transport)
   → secondary "harden" log (ghi log xuống disk)  → gửi ack về primary
   → SYNCHRONOUS: primary chỉ COMMIT sau khi nhận ack  ⇒ RPO = 0
     ASYNCHRONOUS: primary COMMIT ngay, không chờ      ⇒ RPO > 0
   → secondary redo log vào data file (redo thread) — bước này ĐỘC LẬP với commit
```

Hệ quả rất quan trọng và hay bị hiểu sai: ở chế độ synchronous, **"đồng bộ" nghĩa là log đã bền trên secondary, không phải dữ liệu đã hiện ra trên secondary**. Redo có thể tụt hậu, nên một readable secondary vẫn có thể trả về dữ liệu cũ hơn primary vài giây. Không mất dữ liệu, nhưng không real-time.

### 2.2 Tạo AG

```sql
-- Điều kiện: cluster đã sẵn, AlwaysOn đã bật trên từng instance,
-- database ở FULL recovery model và đã có full backup

CREATE AVAILABILITY GROUP [AG_SALES]
WITH (
    AUTOMATED_BACKUP_PREFERENCE = SECONDARY,
    FAILURE_CONDITION_LEVEL     = 3,      -- 1..5, càng cao càng dễ failover
    HEALTH_CHECK_TIMEOUT        = 30000,
    DB_FAILOVER                 = ON,     -- failover khi một database mất khả năng, không chỉ khi instance chết
    DTC_SUPPORT                 = NONE,
    REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 1,
    CLUSTER_TYPE                = WSFC    -- EXTERNAL cho Pacemaker/Linux, NONE cho read-scale AG
)
FOR DATABASE [SalesDB], [InventoryDB]
REPLICA ON
    N'SQL1' WITH (
        ENDPOINT_URL         = N'TCP://sql1.corp.local:5022',
        AVAILABILITY_MODE    = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE        = AUTOMATIC,
        SEEDING_MODE         = AUTOMATIC,
        BACKUP_PRIORITY      = 30,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY,
                        READ_ONLY_ROUTING_URL = N'TCP://sql1.corp.local:1433'),
        PRIMARY_ROLE   (ALLOW_CONNECTIONS = READ_WRITE,
                        READ_ONLY_ROUTING_LIST = (N'SQL2', N'SQL3'))
    ),
    N'SQL2' WITH (
        ENDPOINT_URL         = N'TCP://sql2.corp.local:5022',
        AVAILABILITY_MODE    = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE        = AUTOMATIC,
        SEEDING_MODE         = AUTOMATIC,
        BACKUP_PRIORITY      = 50,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY,
                        READ_ONLY_ROUTING_URL = N'TCP://sql2.corp.local:1433'),
        PRIMARY_ROLE   (ALLOW_CONNECTIONS = READ_WRITE,
                        READ_ONLY_ROUTING_LIST = (N'SQL1', N'SQL3'))
    ),
    N'SQL3' WITH (
        ENDPOINT_URL         = N'TCP://sql3-dr.corp.local:5022',
        AVAILABILITY_MODE    = ASYNCHRONOUS_COMMIT,
        FAILOVER_MODE        = MANUAL,
        SEEDING_MODE         = AUTOMATIC,
        BACKUP_PRIORITY      = 10,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY,
                        READ_ONLY_ROUTING_URL = N'TCP://sql3-dr.corp.local:1433')
    );

-- Listener
ALTER AVAILABILITY GROUP [AG_SALES]
ADD LISTENER N'sales-listener' (
    WITH IP ((N'10.10.1.50', N'255.255.255.0')), PORT = 1433
);

-- Trên từng secondary
ALTER AVAILABILITY GROUP [AG_SALES] JOIN WITH (CLUSTER_TYPE = WSFC);
ALTER AVAILABILITY GROUP [AG_SALES] GRANT CREATE ANY DATABASE;   -- cho automatic seeding
```

Ba tham số đáng dừng lại:

| Tham số | Ý nghĩa thực tế |
|---|---|
| `REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT` | Số secondary sync phải ack trước khi commit. `1` bảo vệ tốt hơn `0`, nhưng nếu secondary đó chết thì **primary dừng nhận write** cho đến khi có secondary sync khác. Đây là đánh đổi availability vs durability rất thật. |
| `SEEDING_MODE = AUTOMATIC` | Engine tự stream database sang secondary, không cần backup/restore thủ công. Rất tiện, nhưng dùng băng thông và không nén (mặc định tùy version) — cân nhắc với database nhiều TB qua WAN. |
| `DB_FAILOVER = ON` | Failover khi một database trong AG mất khả năng (ví dụ hết chỗ, file offline), không chỉ khi cả instance chết. Nên bật. |

### 2.3 Giám sát AG

```sql
-- Trạng thái tổng quan
SELECT
    ag.name                                AS AgName,
    ar.replica_server_name,
    ars.role_desc, ars.operational_state_desc,
    ars.connected_state_desc, ars.synchronization_health_desc,
    ar.availability_mode_desc, ar.failover_mode_desc,
    drs.database_name, drs.synchronization_state_desc,
    drs.is_commit_participant,
    drs.log_send_queue_size / 1024.0        AS LogSendQueueMB,   -- chưa gửi → ảnh hưởng RPO
    drs.log_send_rate / 1024.0              AS LogSendRateMBps,
    drs.redo_queue_size / 1024.0            AS RedoQueueMB,      -- chưa apply → ảnh hưởng RTO & độ mới khi đọc
    drs.redo_rate / 1024.0                  AS RedoRateMBps,
    drs.last_commit_time,
    drs.secondary_lag_seconds                                     -- 2016+
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar                 ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars  ON ar.replica_id = ars.replica_id
JOIN sys.dm_hadr_database_replica_states drs      ON ar.replica_id = drs.replica_id
ORDER BY ag.name, ars.role_desc DESC, ar.replica_server_name;
```

Hai hàng đợi, hai ý nghĩa khác nhau — đây là điều cần nhớ khi đọc dashboard:

| Chỉ số | Đo cái gì | Ảnh hưởng |
|---|---|---|
| `log_send_queue_size` | Log đã sinh ở primary nhưng chưa gửi/chưa ack ở secondary | **RPO**: mất bao nhiêu nếu primary chết ngay lúc này |
| `redo_queue_size` | Log đã bền ở secondary nhưng chưa apply vào data file | **RTO** (phải redo hết trước khi lên primary) và độ mới của readable secondary |

```sql
-- Ước lượng RPO và thời gian catch-up
SELECT ar.replica_server_name, drs.database_name,
       drs.log_send_queue_size / NULLIF(drs.log_send_rate, 0) AS EstSecToSend,
       drs.redo_queue_size     / NULLIF(drs.redo_rate, 0)     AS EstSecToRedo,
       DATEDIFF(SECOND, drs.last_commit_time,
                (SELECT MAX(last_commit_time) FROM sys.dm_hadr_database_replica_states
                 WHERE is_primary_replica = 1 AND database_name = drs.database_name)) AS BehindPrimarySec
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
WHERE drs.is_primary_replica = 0;
```

`HADR_SYNC_COMMIT` là wait cần theo dõi ở primary: nó cho biết bao nhiêu thời gian commit đang bị dành cho việc chờ secondary. Tăng đột biến nghĩa là mạng hoặc log disk của secondary có vấn đề — và nó ảnh hưởng trực tiếp tới độ trễ ghi của ứng dụng.

### 2.4 Readable secondary – lợi ích và ba cái bẫy

```sql
-- Ứng dụng chỉ đọc: connection string thêm ApplicationIntent
-- jdbc:sqlserver://sales-listener:1433;databaseName=SalesDB;applicationIntent=ReadOnly
```

| Bẫy | Chi tiết | Xử lý |
|---|---|---|
| **Mọi query trên secondary chạy dưới snapshot isolation** | Engine tự chuyển; hint isolation bị bỏ qua | Chấp nhận; và biết rằng nó dùng version store trong **tempdb của secondary** |
| **Dữ liệu tụt hậu theo redo queue** | Không phải real-time, dù là sync replica | Đặt SLA về độ mới; giám sát `secondary_lag_seconds` |
| **Redo có thể bị block bởi query đang đọc** | Query dài trên secondary giữ schema stability lock, chặn redo của một DDL | Giới hạn thời gian query trên secondary |

Bẫy thứ ba là nguyên nhân thật của sự cố "secondary tụt hậu hàng giờ": một report chạy 2 tiếng trên secondary, primary có một `ALTER TABLE`, redo thread đứng chờ, và cả AG tụt hậu.

Statistics trên readable secondary cũng là điểm cần biết: secondary là read-only nên không tạo được statistics mới — engine lưu chúng dưới dạng **temporary statistics trong tempdb**, và chúng mất khi failover hoặc restart. Query trên secondary do đó có thể có plan khác primary.

### 2.5 Failover

```sql
-- Failover có kế hoạch, không mất dữ liệu (chạy TRÊN secondary sẽ thành primary)
ALTER AVAILABILITY GROUP [AG_SALES] FAILOVER;

-- Failover cưỡng chế sang async secondary: CÓ THỂ MẤT DỮ LIỆU
ALTER AVAILABILITY GROUP [AG_SALES] FORCE_FAILOVER_ALLOW_DATA_LOSS;
```

`FORCE_FAILOVER_ALLOW_DATA_LOSS` là quyết định nghiệp vụ, không phải quyết định kỹ thuật. Trước khi chạy, phải trả lời được: mất bao nhiêu dữ liệu (xem `log_send_queue_size` và `last_commit_time`), và ai chấp nhận việc đó. Sau khi chạy, AG cũ có thể cần reseed hoặc xử lý phân nhánh dữ liệu.

Quy trình chuyển đổi có kế hoạch giữa hai datacenter:

```text
1. Đổi DR replica từ ASYNCHRONOUS sang SYNCHRONOUS_COMMIT
2. Chờ synchronization_state_desc = 'SYNCHRONIZED' và redo_queue ≈ 0
3. ALTER AVAILABILITY GROUP ... FAILOVER (từ node đích)
4. Đổi replica cũ về ASYNCHRONOUS nếu cần
5. Xác nhận ứng dụng kết nối qua listener và hoạt động
```

```sql
ALTER AVAILABILITY GROUP [AG_SALES]
MODIFY REPLICA ON N'SQL3' WITH (AVAILABILITY_MODE = SYNCHRONOUS_COMMIT);
```

### 2.6 Những gì AG **không** replicate

Đây là danh sách gây sự cố sau failover nhiều nhất, vì AG chỉ replicate nội dung database người dùng:

| Không được replicate | Cách xử lý |
|---|---|
| Login ở mức instance (`master`) | Script hóa login + SID, đồng bộ sang mọi replica; hoặc dùng **contained AG** (2022+) |
| SQL Agent job | Script hóa và deploy lên mọi node; job phải tự kiểm tra mình có đang ở primary |
| Linked server, credential, server-level config | Script hóa, quản lý bằng IaC |
| Certificate/khóa trong `master` (TDE) | Tạo cùng certificate trên mọi replica |
| Nội dung `msdb` (lịch sử backup, job) | Chấp nhận, hoặc tập trung hóa monitoring |
| Server-level audit, trigger, alert | Deploy lên mọi node |

Mẫu để job chỉ chạy trên primary:

```sql
IF sys.fn_hadr_backup_is_preferred_replica('SalesDB') = 0
BEGIN
    PRINT 'Không phải replica ưu tiên, bỏ qua.';
    RETURN;
END
-- ... công việc backup ...
```

```sql
-- Hoặc kiểm tra vai trò trực tiếp
IF EXISTS (
    SELECT 1 FROM sys.dm_hadr_availability_replica_states rs
    JOIN sys.availability_databases_cluster adc ON adc.group_id = rs.group_id
    WHERE adc.database_name = 'SalesDB' AND rs.is_local = 1 AND rs.role_desc = 'PRIMARY'
)
BEGIN
    -- công việc chỉ chạy ở primary
END
```

### 2.7 Contained Availability Group (SQL Server 2022+)

Contained AG giải quyết đúng vấn đề ở mục 2.6: AG có **`master` và `msdb` riêng ở phạm vi AG**, nên login, job, và metadata đi cùng AG khi failover.

```sql
CREATE AVAILABILITY GROUP [AG_SALES_CONTAINED]
WITH (CLUSTER_TYPE = WSFC, CONTAINED)      -- từ khóa CONTAINED
FOR DATABASE [SalesDB]
REPLICA ON ...;
```

Đây là cải tiến vận hành đáng kể cho môi trường nhiều AG trên cùng instance, vì trước đây login/job phải đồng bộ thủ công và là nguồn lỗi thường xuyên sau failover. Cần đọc kỹ giới hạn trước khi chuyển AG hiện có sang mô hình này.

### 2.8 Distributed AG và read-scale AG

```sql
-- Read-scale AG: không cần cluster, không auto-failover — chỉ để nhân bản đọc
CREATE AVAILABILITY GROUP [AG_ReadScale]
WITH (CLUSTER_TYPE = NONE)
FOR DATABASE [SalesDB]
REPLICA ON ... ;   -- FAILOVER_MODE phải là MANUAL

-- Distributed AG: nối hai AG (thường ở hai region, hoặc Windows ↔ Linux)
CREATE AVAILABILITY GROUP [DAG_SALES]
WITH (DISTRIBUTED)
AVAILABILITY GROUP ON
    'AG_SALES_HN' WITH (LISTENER_URL = 'TCP://hn-listener:5022',
                        AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                        SEEDING_MODE = AUTOMATIC),
    'AG_SALES_SG' WITH (LISTENER_URL = 'TCP://sg-listener:5022',
                        AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, FAILOVER_MODE = MANUAL,
                        SEEDING_MODE = AUTOMATIC);
```

Distributed AG là công cụ chuẩn cho hai bài toán: **DR đa region** (mỗi region có HA riêng, nối với nhau) và **migration giữa OS/version** (AG cũ trên Windows 2019, AG mới trên Linux/SQL 2025, cắt chuyển khi sẵn sàng).

---

## 3. Failover Cluster Instance (FCI)

```text
Node A ─┐
         ├── shared storage (SAN / Azure shared disk / S2D)
Node B ─┘
Một SQL Server instance, di chuyển giữa các node. Dữ liệu chỉ có một bản.
```

```sql
SELECT NodeName, status_description, is_current_owner FROM sys.dm_os_cluster_nodes;
SELECT cluster_name, quorum_type_desc, quorum_state_desc FROM sys.dm_hadr_cluster;
```

| Đặc điểm | Ý nghĩa |
|---|---|
| Bảo vệ ở mức instance | Toàn bộ instance chuyển node: login, job, msdb đi theo — không có vấn đề ở mục 2.6 |
| Không nhân bản dữ liệu | Shared storage là single point of failure cho dữ liệu |
| Không có readable secondary | Không offload đọc được |
| Ứng dụng không cần đổi gì | Kết nối theo virtual network name |
| RTO | 30–90 giây (thời gian instance khởi động và recovery database) |

FCI thường được kết hợp với AG: FCI cho HA trong site (dùng chung storage), AG async sang site khác cho DR. Khi đó FCI là một "replica" trong AG.

---

## 4. Log Shipping

```sql
-- Primary
EXEC master.dbo.sp_add_log_shipping_primary_database
    @database = N'SalesDB',
    @backup_directory = N'\\fileserver\logship\SalesDB',
    @backup_share     = N'\\fileserver\logship\SalesDB',
    @backup_job_name  = N'LSBackup_SalesDB',
    @backup_retention_period = 4320,          -- phút (3 ngày)
    @backup_threshold = 60,                   -- alert nếu không có backup trong 60 phút
    @threshold_alert_enabled = 1;

-- Secondary
EXEC master.dbo.sp_add_log_shipping_secondary_database
    @secondary_database = N'SalesDB',
    @primary_server = N'SQL-PRIMARY', @primary_database = N'SalesDB',
    @restore_delay = 60,        -- TRỄ 60 phút: lá chắn chống lỗi logic/ransomware
    @restore_mode = 1,          -- 0 = NORECOVERY, 1 = STANDBY (đọc được giữa các lần restore)
    @restore_all = 1, @disconnect_users = 1;

-- Trạng thái
SELECT primary_server, primary_database, secondary_database,
       last_restored_file, last_restored_date,
       DATEDIFF(MINUTE, last_restored_date, GETDATE()) AS MinutesBehind
FROM msdb.dbo.log_shipping_secondary_databases;
```

Log shipping là công nghệ cũ nhưng vẫn có hai chỗ đứng không thay thế được:

1. **`@restore_delay`** — secondary cố tình tụt hậu 1 giờ. Khi ai đó `DROP TABLE` hoặc ransomware bắt đầu mã hóa, bạn có một bản dữ liệu "trước sự cố" đang sống, không phải chờ restore. Always On **không** làm được điều này.
2. **Cross-version / cross-edition** — restore log lên version cao hơn được, hữu ích cho migration.

Nhược điểm: không auto-failover, RPO bằng tần suất log backup, và chuyển đổi phải làm tay.

---

## 5. Các cơ chế nhân bản khác

| Cơ chế | Mục đích chính | Ghi chú |
|---|---|---|
| **Transactional replication** | Nhân bản một phần dữ liệu (subset bảng/cột) tới nhiều subscriber | Không phải HA; dùng cho phân phối dữ liệu — xem [data_movement.md](../integration/data_movement.md) |
| **Merge replication** | Đồng bộ hai chiều, client offline | Phức tạp, cần giải quyết conflict |
| **Database Mirroring** | HA thế hệ trước AG | Deprecated, không dùng cho hệ mới |
| **Azure SQL Managed Instance** | PaaS, HA sẵn có | Business Critical tier có replica đọc được |
| **Auto-failover group (Azure SQL)** | DR đa region cho PaaS | Một endpoint, failover tự động |
| **Azure Arc-enabled SQL Server** | Quản lý instance on-prem từ Azure | Không phải HA, nhưng cho backup/monitoring tập trung |

---

## 6. Compare – chọn công nghệ theo yêu cầu

| | AG sync | AG async | FCI | Log shipping | Chỉ backup |
|---|---|---|---|---|---|
| RPO | 0 | Giây | 0 | Phút (theo tần suất log) | Phút |
| RTO | 10–30 giây (auto) | Phút (manual) | 30–90 giây | 30–60 phút | Giờ |
| Auto failover | Có | Không | Có | Không | – |
| Readable secondary | Có | Có | Không | Có (STANDBY, giữa các restore) | Không |
| Cần shared storage | Không | Không | Có | Không | Không |
| Cross-datacenter | Không nên (độ trễ) | Có | Không | Có | Có |
| Bảo vệ khỏi lỗi logic | Không | Không | Không | **Có** (nếu có restore_delay) | **Có** |
| Số bản dữ liệu | 2+ | 2+ | 1 | 2 | 2+ |
| Edition | Enterprise (Standard: Basic AG, hạn chế) | Enterprise | Standard/Enterprise | Mọi edition | Mọi edition |
| Độ phức tạp vận hành | Cao | Cao | Trung bình | Thấp | Thấp |

Kiến trúc tham chiếu đầy đủ cho hệ thống quan trọng:

```text
Site chính (HN)
  SQL1 (primary) ←sync→ SQL2 (secondary, auto-failover, readable cho báo cáo)
        │
        └─async→ Site DR (SG): SQL3 (manual failover, readable)
        │
        └─log shipping với restore_delay 60 phút → SQL4 (lá chắn lỗi logic)
        │
        └─backup: full/diff/log → NAS tại chỗ + object storage immutable ở ngoài site
```

Bốn lớp này bảo vệ bốn loại sự cố khác nhau: mất node, mất site, lỗi logic/ransomware, và mất tất cả.

---

## 7. Always On trên Linux và trong Kubernetes

Trên Linux, Always On không dùng WSFC mà dùng **Pacemaker + Corosync**, với `CLUSTER_TYPE = EXTERNAL`:

```sql
CREATE AVAILABILITY GROUP [AG_SALES]
WITH (CLUSTER_TYPE = EXTERNAL)
FOR DATABASE [SalesDB]
REPLICA ON
  N'sql1' WITH (ENDPOINT_URL = N'TCP://sql1:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                FAILOVER_MODE = EXTERNAL, SEEDING_MODE = AUTOMATIC),
  N'sql2' WITH (ENDPOINT_URL = N'TCP://sql2:5022', AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
                FAILOVER_MODE = EXTERNAL, SEEDING_MODE = AUTOMATIC);

-- Login mà Pacemaker dùng để điều phối
CREATE LOGIN pacemaker WITH PASSWORD = '<strong>';
ALTER SERVER ROLE [sysadmin] ADD MEMBER pacemaker;   -- hoặc quyền hạn hẹp hơn theo tài liệu
GRANT ALTER, CONTROL, VIEW DEFINITION ON AVAILABILITY GROUP::[AG_SALES] TO pacemaker;
```

Trong Kubernetes, cách tiếp cận phổ biến là **StatefulSet + PersistentVolume**: dựa vào K8s để tái tạo pod khi node chết, thay vì dựng cluster manager bên trong. RTO khi đó là thời gian pod khởi động + database recovery — thường 30–120 giây, chấp nhận được cho nhiều hệ. Chi tiết ở [linux_containers.md](../platform/linux_containers.md).

---

## 8. Ứng dụng phải làm gì để failover thật sự trong suốt

Failover ở tầng database không tự làm ứng dụng liền mạch. Từ phía Java/JDBC:

```properties
# Kết nối qua listener, không qua tên server cụ thể
jdbc:sqlserver://sales-listener:1433;databaseName=SalesDB;
  encrypt=true;trustServerCertificate=false;
  multiSubnetFailover=true;        # rất quan trọng khi listener có nhiều IP (multi-subnet)
  loginTimeout=15;
  applicationIntent=ReadWrite
```

| Việc cần làm | Vì sao |
|---|---|
| `multiSubnetFailover=true` | Thử song song mọi IP của listener; không có nó, kết nối chờ timeout từng IP |
| Retry ở tầng ứng dụng cho lỗi kết nối tạm | Trong lúc failover, kết nối bị đứt và pool phải xây lại |
| Validate connection khi lấy từ pool | Kết nối "cũ" tới primary đã mất là kết nối chết |
| `loginTimeout` ngắn | Để retry nhanh thay vì treo |
| Transaction phải idempotent hoặc có retry an toàn | Một transaction đang bay lúc failover sẽ bị rollback |
| Tách datasource cho read-only workload | Dùng `applicationIntent=ReadOnly` để tận dụng secondary |

Chi tiết cấu hình HikariCP và mẫu retry: [jdbc_java.md](../integration/jdbc_java.md).

---

## 9. Bảo trì với AG – patch không downtime (gần như)

```text
1. Kiểm tra AG healthy, mọi secondary SYNCHRONIZED, redo_queue ≈ 0
2. Trên secondary A: ALTER DATABASE ... SET HADR SUSPEND (tùy chọn, cho patch dài)
3. Patch secondary A, restart, chờ SYNCHRONIZED lại
4. Failover sang secondary A (đã patch) — downtime = thời gian failover (giây)
5. Patch primary cũ (giờ là secondary), chờ đồng bộ
6. Failover về nếu chính sách yêu cầu primary ở node cụ thể
```

```sql
-- Tạm dừng / tiếp tục đồng bộ cho một database
ALTER DATABASE SalesDB SET HADR SUSPEND;
ALTER DATABASE SalesDB SET HADR RESUME;

-- Kiểm tra đã catch-up chưa trước khi failover
SELECT ar.replica_server_name, drs.database_name, drs.synchronization_state_desc,
       drs.redo_queue_size, drs.log_send_queue_size
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id;
```

Lưu ý khi suspend: log ở primary **không truncate được** trong lúc secondary bị suspend (`log_reuse_wait_desc = 'AVAILABILITY_REPLICA'`). Suspend qua đêm trên hệ ghi nhiều có thể làm log đầy — đây là sự cố hay xảy ra trong cửa sổ bảo trì.

Backup từ secondary:

```sql
-- Trên secondary: full backup phải là COPY_ONLY; log backup thì bình thường
BACKUP DATABASE SalesDB TO DISK = '/backup/full/SalesDB.bak' WITH COPY_ONLY, COMPRESSION, CHECKSUM;
BACKUP LOG      SalesDB TO DISK = '/backup/log/SalesDB.trn'  WITH COMPRESSION, CHECKSUM;
```

Với `AUTOMATED_BACKUP_PREFERENCE = SECONDARY` và `BACKUP_PRIORITY` đã đặt, job dùng `sys.fn_hadr_backup_is_preferred_replica` (mục 2.6) sẽ tự chọn đúng node.

---

## 10. Trade-offs

| Quyết định | Được | Mất | Khi nào |
|---|---|---|---|
| Synchronous commit | RPO = 0 | Mỗi commit chờ round-trip mạng | Cùng site, độ trễ < 1–2ms |
| Asynchronous commit | Không ảnh hưởng độ trễ ghi | RPO > 0, có thể mất dữ liệu khi force failover | Cross-datacenter |
| `REQUIRED_SYNCHRONIZED_...= 1` | Đảm bảo có bản sao bền | Secondary chết → primary dừng nhận write | Khi durability quan trọng hơn availability |
| Auto failover | RTO giây, không cần người | Có thể failover vì lý do tạm thời | HA trong site với sync replica |
| Readable secondary | Offload báo cáo, backup | tempdb secondary chịu tải; dữ liệu tụt hậu; redo có thể bị block | Có báo cáo nặng và chấp nhận độ trễ |
| Automatic seeding | Không cần backup/restore tay | Tốn băng thông, chậm với DB rất lớn qua WAN | DB vừa, mạng tốt |
| Contained AG (2022+) | Login/job đi cùng AG | Mô hình mới, cần đọc kỹ giới hạn | Môi trường nhiều AG |
| Log shipping có `restore_delay` | Lá chắn lỗi logic/ransomware | Không auto failover, tụt hậu có chủ đích | Bổ sung cho AG, không thay thế |
| FCI | Không có vấn đề login/job | Shared storage là SPOF cho dữ liệu | HA đơn giản trong site |

---

## 11. Runbook failover

```text
[Trước - đã chuẩn bị sẵn]
□ Sơ đồ topology, tên listener, IP, port endpoint được ghi tài liệu
□ Login/job/linked server đã script hóa và đồng bộ mọi node (hoặc dùng contained AG)
□ Certificate TDE đã có trên mọi replica
□ Alert: sync health, log send queue, redo queue, secondary lag
□ Runbook đã được diễn tập ít nhất một lần mỗi quý

[Failover có kế hoạch]
□ Kiểm tra AG healthy, mọi sync replica SYNCHRONIZED
□ Kiểm tra redo_queue_size ≈ 0 trên node đích
□ Thông báo cho các bên liên quan, mở cửa sổ
□ ALTER AVAILABILITY GROUP ... FAILOVER (chạy TỪ node đích)
□ Xác nhận role_desc = PRIMARY trên node mới
□ Xác nhận ứng dụng kết nối được qua listener
□ Kiểm tra SQL Agent job đang chạy ở node mới
□ Ghi lại thời gian downtime thực tế

[Failover khẩn cấp - primary mất]
□ Xác nhận primary thật sự mất (không phải mất mạng tạm)
□ Nếu có sync secondary healthy → FAILOVER (không mất dữ liệu)
□ Nếu chỉ còn async secondary:
    - ĐO log_send_queue_size và last_commit_time → lượng dữ liệu sẽ mất
    - Xin quyết định của nghiệp vụ
    - FORCE_FAILOVER_ALLOW_DATA_LOSS
    - Ghi lại chính xác điểm mất dữ liệu để đối soát sau
□ Kiểm tra ứng dụng, job, monitoring
□ Xử lý primary cũ: có thể cần reseed thay vì rejoin

[Sau failover]
□ Root cause của sự cố gốc
□ Đối soát dữ liệu nếu đã force failover
□ Cập nhật runbook theo những gì thực tế đã vấp
```

---

## 12. Ghi chú – chủ đề tiếp theo

- [security.md](security.md): TDE trên nhiều replica, đồng bộ login, audit.
- [backup_recovery.md](backup_recovery.md): backup từ secondary, và vì sao AG không thay thế backup.
- [linux_containers.md](../platform/linux_containers.md): Pacemaker, K8s StatefulSet, Azure Arc.
- [jdbc_java.md](../integration/jdbc_java.md): connection string, retry, read-only routing từ Java.
- [monitoring_troubleshooting.md](../performance/monitoring_troubleshooting.md): alert cho AG.

Từ khóa mở rộng: WSFC quorum (node majority, file share witness, cloud witness), `sys.dm_hadr_cluster_members`, AG với DTC, `sys.availability_read_only_routing_lists`, load-balanced read-only routing (nhóm replica trong ngoặc), Basic AG trên Standard Edition, snapshot backup trên secondary.

---

*Cập nhật lần cuối: 2026-07-30*
