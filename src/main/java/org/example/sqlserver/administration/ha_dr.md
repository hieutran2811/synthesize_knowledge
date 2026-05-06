# SQL Server High Availability & DR – Deep Dive

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## What – HA/DR là gì?

**HA (High Availability)**: giảm downtime khi failure xảy ra (hardware, software, maintenance). **DR (Disaster Recovery)**: phục hồi sau thảm họa (data center failure, ransomware).

```
Tiers:
  HA:  RTO minutes, RPO seconds-minutes → same datacenter
  DR:  RTO hours,   RPO minutes         → different datacenter/region
```

---

## Components – AlwaysOn Availability Groups (AG)

```
Kiến trúc:

Availability Group "SALES_AG":
  Primary Replica  (Windows Server Failover Cluster node)
      ├── Synchronous Secondary-1 (same datacenter, auto-failover)
      └── Asynchronous Secondary-2 (DR datacenter, manual failover)

AG Listener: "SALES_LISTENER" → virtual IP → routes to current primary
Application → AG Listener → Primary (writes)
Application → Secondary-1 (readonly offload)
```

### AG Setup (WSFC)

```sql
-- Prerequisites:
-- 1. Windows Server Failover Cluster (WSFC) configured
-- 2. SQL Server installed on all nodes
-- 3. Database in FULL recovery model
-- 4. Full backup taken

-- 1. Enable AlwaysOn on each instance (via SQL Server Configuration Manager)
-- hoặc: PowerShell
-- Enable-SqlAlwaysOn -ServerInstance "SQL1" -Force

-- 2. Create AG (trên primary)
CREATE AVAILABILITY GROUP [SALES_AG]
WITH (
    AUTOMATED_BACKUP_PREFERENCE = SECONDARY,  -- backup từ secondary
    FAILURE_CONDITION_LEVEL = 3,              -- 1-5: higher = more aggressive failover
    HEALTH_CHECK_TIMEOUT = 30000,             -- ms before considering unhealthy
    DB_FAILOVER = ON,                         -- failover if DB unhealthy
    REQUIRED_SYNCHRONIZED_SECONDARIES_TO_COMMIT = 0  -- 0 = don't wait for secondaries
)
FOR DATABASE [SalesDB], [InventoryDB]  -- các DB trong AG
REPLICA ON
    'SQL1' WITH (
        ENDPOINT_URL = 'TCP://sql1.corp.local:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,   -- zero data loss
        FAILOVER_MODE = AUTOMATIC,                -- auto failover
        SEEDING_MODE = AUTOMATIC,                 -- auto seed secondary
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY,
                        READ_ONLY_ROUTING_URL = 'TCP://sql1.corp.local:1433')
    ),
    'SQL2' WITH (
        ENDPOINT_URL = 'TCP://sql2.corp.local:5022',
        AVAILABILITY_MODE = SYNCHRONOUS_COMMIT,
        FAILOVER_MODE = AUTOMATIC,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY,
                        READ_ONLY_ROUTING_URL = 'TCP://sql2.corp.local:1433')
    ),
    'SQL3-DR' WITH (
        ENDPOINT_URL = 'TCP://sql3-dr.corp.local:5022',
        AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,  -- small lag ok for DR
        FAILOVER_MODE = MANUAL,                   -- manual failover for DR
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = READ_ONLY)
    );

-- 3. Create AG Listener
ALTER AVAILABILITY GROUP [SALES_AG]
ADD LISTENER 'SALES_LISTENER' (
    WITH IP ((N'192.168.1.100', N'255.255.255.0')),
    PORT = 1433
);

-- 4. Read-only routing list (primary routes read-intent connections to secondary)
ALTER AVAILABILITY GROUP [SALES_AG]
MODIFY REPLICA ON N'SQL1' WITH (
    PRIMARY_ROLE (READ_ONLY_ROUTING_LIST = ('SQL2', 'SQL1'))  -- SQL2 preferred, SQL1 fallback
);

-- Application connection string cho read-only routing:
-- Server=SALES_LISTENER,1433;ApplicationIntent=ReadOnly
-- → routed to SQL2 (read-only secondary)
```

---

## How – AG Monitoring

```sql
-- Dashboard status
SELECT
    ag.name AS AG_Name,
    ar.replica_server_name,
    ars.role_desc,
    ars.availability_mode_desc,
    ars.failover_mode_desc,
    ars.synchronization_health_desc,
    drs.synchronization_state_desc,
    drs.is_commit_participant,
    drs.log_send_queue_size / 1024 AS LogSendQueueMB,  -- unsent log
    drs.redo_queue_size / 1024 AS RedoQueueMB,          -- unapplied log
    drs.last_hardened_lsn
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
JOIN sys.dm_hadr_database_replica_states drs ON ar.replica_id = drs.replica_id
ORDER BY ag.name, ar.replica_server_name;

-- AG health (listener)
SELECT * FROM sys.availability_group_listeners;
SELECT * FROM sys.availability_group_listener_ip_addresses;

-- Replication lag (seconds behind primary)
SELECT
    ars.role_desc,
    ar.replica_server_name,
    drs.database_name,
    drs.redo_queue_size / 1024.0 AS RedoQueueMB,
    drs.redo_rate AS RedoRateKBps,
    CASE WHEN drs.redo_rate > 0
         THEN drs.redo_queue_size / drs.redo_rate
         ELSE NULL END AS EstimatedCatchupSeconds
FROM sys.dm_hadr_database_replica_states drs
JOIN sys.availability_replicas ar ON drs.replica_id = ar.replica_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id
WHERE ars.role_desc = 'SECONDARY';

-- Manual failover (planned: synchronous, zero data loss)
ALTER AVAILABILITY GROUP [SALES_AG] FAILOVER;  -- run on target secondary!

-- Forced failover (DR: async secondary, possible data loss)
ALTER AVAILABILITY GROUP [SALES_AG] FORCE_FAILOVER_ALLOW_DATA_LOSS;
-- CẢNH BÁO: chỉ dùng khi primary unreachable và không thể restore
```

---

## How – Log Shipping

```sql
-- Log Shipping: primary → monitor → secondary (simpler than AG, older tech)
-- Dùng khi: không có WSFC, cross-version migration, simple DR

-- Setup via SSMS: Database Properties → Transaction Log Shipping
-- Hoặc T-SQL:

-- Primary server: enable log shipping
EXEC master.dbo.sp_add_log_shipping_primary_database
    @database = N'SalesDB',
    @backup_directory = N'\\fileserver\LogShipping\SalesDB',
    @backup_share = N'\\fileserver\LogShipping\SalesDB',
    @backup_job_name = N'LSBackup_SalesDB',
    @backup_retention_period = 4320,     -- minutes (3 days)
    @monitor_server = N'SQL-MONITOR',
    @threshold_alert_enabled = 1,
    @backup_threshold = 60,              -- alert if no backup in 60 min
    @history_retention_period = 5760,    -- minutes (4 days)
    @backup_job_id = @LS_BackupJobId OUTPUT;

-- Secondary server: configure restore
EXEC master.dbo.sp_add_log_shipping_secondary_database
    @secondary_database = N'SalesDB',
    @primary_server = N'SQL-PRIMARY',
    @primary_database = N'SalesDB',
    @restore_delay = 0,                  -- minutes to delay before restore
    -- hoặc: @restore_delay = 60 → 1h delayed secondary (data corruption protection)
    @restore_all = 1,
    @restore_mode = 0,                   -- 0 = NORECOVERY, 1 = STANDBY
    @disconnect_users = 0,               -- disconnect users khi restore
    @block_size = 512,
    @buffer_count = 10;

-- Xem log shipping status
SELECT
    primary_server, primary_database, secondary_server, secondary_database,
    last_restored_file, last_restored_date,
    DATEDIFF(MINUTE, last_restored_date, GETDATE()) AS MinutesBehind
FROM msdb.dbo.log_shipping_secondary_databases;
```

---

## How – Always On FCI (Failover Cluster Instance)

```sql
-- FCI: shared storage (SAN/Azure Shared Disk), instance failover
-- Khác AG: 1 SQL Server instance, shared storage, no data copy
-- Khi node fail → instance moves to another node → same data

-- Không phải read-only offload (không có secondary)
-- Dùng cho: simple HA, không cần read scaling

-- Xem FCI status
SELECT
    NodeName,
    status_description,
    is_current_owner
FROM sys.dm_os_cluster_nodes;

SELECT
    cluster_name,
    quorum_type_desc,
    quorum_state_desc
FROM sys.dm_hadr_cluster;
```

---

## How – Stretch Database & Azure SQL Hybrid

```sql
-- SQL 2016+ Stretch Database: archive cold data to Azure SQL
-- Deprecated in SQL 2022 (Microsoft removed)

-- Modern approach: Azure Arc-enabled SQL Server
-- On-premises SQL Server managed via Azure portal

-- Azure SQL Database Managed Instance
-- → Fully managed PaaS, same SQL Server features, built-in HA
-- → Business Critical tier: Always On under the hood (4 nodes)
-- → General Purpose tier: remote storage, 99.99% SLA

-- Geo-replication (Azure SQL Database)
-- → Active Geo-replication: manual failover, readable secondaries
-- → Auto-failover groups: automatic failover, single connection string
-- Connection string: server=myserver.database.windows.net (geo-failover group)
```

---

## Compare – SQL Server HA/DR Options

| Option | RPO | RTO | Complexity | Read Offload | Cost |
|--------|-----|-----|-----------|-------------|------|
| AlwaysOn AG (sync) | 0 (no data loss) | 15-30s | High | Yes | High |
| AlwaysOn AG (async) | Seconds | Minutes | High | Yes | High |
| FCI | 0 | 30-60s | Medium | No | High (SAN) |
| Log Shipping | Minutes | 30-60min | Low | Yes (standby) | Low |
| Database Mirroring | 0 (sync) | 30s | Medium | No (deprecated) | - |
| Azure SQL MI | ~5s | Auto | Low (PaaS) | Yes (BI tier) | Medium |

---

## Trade-offs

```
AlwaysOn AG:
✅ Zero data loss (sync), auto-failover, read offload
✅ Industry standard for enterprise SQL Server
❌ Requires WSFC (Windows only), complex setup
❌ Synchronous mode: slightly higher write latency (wait for secondary)
❌ Enterprise Edition for most features

Log Shipping:
✅ Simple, works cross-version, cross-datacenter
✅ Can have delayed secondary (protection against corruption)
❌ No auto-failover
❌ RPO = log backup frequency (minutes)
❌ Manual switchover required

FCI:
✅ Simple failover (same instance, no app changes needed)
✅ No data copy
❌ Shared storage = single point of failure for storage
❌ No read offload
❌ Expensive SAN/shared storage

Synchronous vs Asynchronous mode:
Synchronous: zero data loss, slight latency overhead (~1-2ms network)
Asynchronous: small data loss (RPO = seconds), no latency overhead
→ Same datacenter: synchronous
→ Cross-datacenter (DR): asynchronous
```

---

## Real-world – AG Maintenance

```sql
-- Patching secondary first (minimize downtime):
-- 1. Pause sync trên secondary
ALTER DATABASE SalesDB SET HADR SUSPEND;

-- 2. Patch secondary, restart
-- 3. Resume sync
ALTER DATABASE SalesDB SET HADR RESUME;

-- 4. Wait for secondary to catch up
-- Kiểm tra: redo_queue_size = 0

-- 5. Failover to patched secondary
-- 6. Patch old primary (now secondary)
-- 7. Failover back

-- Backup from secondary (reduce primary load)
BACKUP DATABASE SalesDB
TO DISK = 'E:\Backup\SalesDB_Full.bak'
WITH COMPRESSION, COPY_ONLY;  -- COPY_ONLY trên secondary không ảnh hưởng chain

-- Monitor: Extended Events cho AG events
CREATE EVENT SESSION [AG_Monitor] ON SERVER
ADD EVENT sqlserver.hadr_ddl_failover_delta_time,
ADD EVENT sqlserver.hadr_server_state_change
ADD TARGET package0.ring_buffer;
ALTER EVENT SESSION [AG_Monitor] ON SERVER STATE = START;
```

---

## Ghi chú – Chủ đề tiếp theo
> `administration/security.md`: Logins, Users, Roles, Schema separation, Row-Level Security, Dynamic Data Masking, TDE, Always Encrypted

---

*Cập nhật lần cuối: 2026-05-06*
