# Roadmap – SQL Server Knowledge

> 📖 Tra cứu nhanh: [SQL Server Glossary](glossary.md)
>
> Phạm vi chính: **SQL Server 2022 (16.x)** và **SQL Server 2025 (17.x)**. Khác biệt giữa hai version line được ghi rõ tại nơi liên quan. Đã chuẩn hóa **14/14 chủ đề**.

## Cấu trúc thư mục

```text
sqlserver/
├── roadmap.md                                   ← file này
├── glossary.md                                  ← thuật ngữ A–Z + mã lỗi thường gặp
├── sqlserver_knowledge.md                       ← tổng quan, learning path, bản đồ chủ đề
├── fundamentals/
│   ├── architecture.md                          ← SQLOS, buffer pool, log, tempdb, page/extent
│   ├── tsql_advanced.md                         ← CTE, window, APPLY, MERGE, JSON, temporal
│   ├── indexing.md                              ← clustered/nonclustered, columnstore, plan, statistics
│   └── transactions.md                          ← isolation, lock, deadlock, RCSI, Optimized Locking
├── performance/
│   ├── query_optimization.md                    ← parameter sniffing, Query Store, IQP, In-Memory OLTP
│   ├── monitoring_troubleshooting.md            ← DMV, XEvents, baseline, runbook, CHECKDB
│   └── partitioning.md                          ← partition function/scheme, sliding window, SWITCH
├── administration/
│   ├── backup_recovery.md                       ← RPO/RTO, backup types, PITR, piecemeal, DR drill
│   ├── ha_dr.md                                 ← Always On AG, FCI, log shipping, failover runbook
│   └── security.md                              ← auth, RBAC, RLS, DDM, TDE, Always Encrypted, audit
├── platform/
│   └── linux_containers.md                      ← Linux, mssql-conf, Docker, Kubernetes, Arc
├── integration/
│   ├── data_movement.md                         ← bulk load, Change Tracking, CDC, Debezium, Outbox
│   └── jdbc_java.md                             ← JDBC, HikariCP, Spring Boot, JPA/Hibernate
└── modern/
    └── sqlserver_2025.md                        ← json gốc, REGEXP_*, vector/AI, CES, OPPO
```

---

## Mục lục

### Fundamentals

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 1 | Architecture & Storage Engine – SQLOS scheduling, buffer pool, WAL & VLF, ADR, tempdb, page/extent, row format, compression, triage wait stats | [fundamentals/architecture.md](fundamentals/architecture.md) | ✅ 2022 / 2025 | Cơ bản |
| 2 | T-SQL Advanced – set-based thinking, CTE & recursive, window function (ROWS vs RANGE, gaps & islands), APPLY, MERGE an toàn, OUTPUT, error handling, dynamic SQL, temporal table, JSON, hàm mới theo version | [fundamentals/tsql_advanced.md](fundamentals/tsql_advanced.md) | ✅ 2022 / 2025 | Trung cấp |
| 3 | Indexing & Execution Plans – thiết kế từ query shape, ESR, clustered key, INCLUDE & Key Lookup, filtered index, columnstore, đọc plan, statistics, bảo trì & kiểm toán index | [fundamentals/indexing.md](fundamentals/indexing.md) | ✅ 2022 / 2025 | Trung cấp |
| 4 | Transactions, Locking & Isolation – ACID, lock mode & escalation, 6 isolation level, RCSI, blocking runbook, lost update & optimistic concurrency, deadlock, Optimized Locking | [fundamentals/transactions.md](fundamentals/transactions.md) | ✅ 2022 / 2025 | Trung cấp |

### Performance

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 5 | Query Optimization – plan cache & recompile, parameter sniffing (6 cách xử lý), Query Store & force plan, Query Store hints, IQP theo version, memory grant & song song hóa, In-Memory OLTP, anti-pattern | [performance/query_optimization.md](performance/query_optimization.md) | ✅ 2022 / 2025 | Nâng cao |
| 6 | Monitoring & Troubleshooting – bản đồ DMV, wait stats theo cửa sổ, Extended Events, baseline vào bảng, điều tra tại thời điểm, CHECKDB & corruption, Prometheus/Grafana, runbook "database chậm" | [performance/monitoring_troubleshooting.md](performance/monitoring_troubleshooting.md) | ✅ 2022 / 2025 | Nâng cao |
| 7 | Partitioning & bảng rất lớn – partition function/scheme, RANGE RIGHT, elimination, aligned index, sliding window & SWITCH, nén theo partition, incremental statistics, các cách không cần partition | [performance/partitioning.md](performance/partitioning.md) | ✅ 2022 / 2025 | Nâng cao |

### Administration

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 8 | Backup & Recovery – RPO/RTO, recovery model, full/diff/log/tail-log/filegroup, backup ra S3 & Azure, encryption & certificate, chuỗi restore, PITR, page & piecemeal restore, verify, DR drill | [administration/backup_recovery.md](administration/backup_recovery.md) | ✅ 2022 / 2025 | Nâng cao |
| 9 | High Availability & DR – Always On AG (sync/async, readable secondary, contained AG, distributed AG), FCI, log shipping với restore delay, failover runbook, bảo trì không downtime | [administration/ha_dr.md](administration/ha_dr.md) | ✅ 2022 / 2025 | Nâng cao |
| 10 | Security – authentication & orphaned user, RBAC & ownership chaining, TLS, Row-Level Security, Dynamic Data Masking, TDE & EKM, Always Encrypted, Ledger table, Audit, cứng hóa bề mặt tấn công | [administration/security.md](administration/security.md) | ✅ 2022 / 2025 | Nâng cao |

### Platform

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 11 | SQL Server trên Linux, Docker & Kubernetes – SQLPAL, mssql-conf, cứng hóa OS, Docker & compose & Testcontainers, StatefulSet, HA trong K8s, backup bằng CronJob, NetworkPolicy, Azure Arc | [platform/linux_containers.md](platform/linux_containers.md) | ✅ 2022 / 2025 | Trung cấp |

### Integration

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 12 | Data Movement, CDC & Integration – minimal logging & bulk load, Change Tracking vs CDC, Debezium → Kafka, Change Event Streaming, Outbox pattern, linked server & data virtualization, replication | [integration/data_movement.md](integration/data_movement.md) | ✅ 2022 / 2025 | Nâng cao |
| 13 | SQL Server từ Java – connection string & driver 12.x, kiểu dữ liệu & implicit conversion, PreparedStatement & TVP, fetch size, HikariCP, transaction & retry, JPA/Hibernate (SEQUENCE, N+1), Always Encrypted, quan sát hai phía | [integration/jdbc_java.md](integration/jdbc_java.md) | ✅ Boot 3.5 / 4.1 | Trung cấp |

### Modern

| # | Chủ đề | File | Trạng thái | Level |
|---|---|---|---|---|
| 14 | SQL Server 2025 – Optimized Locking (TID + LAQ), kiểu `json` gốc & JSON index, họ `REGEXP_*`, `vector`/DiskANN/`AI_GENERATE_EMBEDDINGS`, Change Event Streaming, Fabric mirroring, OPPO, tempdb resource governance, quy trình nâng cấp | [modern/sqlserver_2025.md](modern/sqlserver_2025.md) | ✅ 2025 (17.x) | Nâng cao |

---

## Learning path

```text
Cơ bản
  architecture → tsql_advanced → indexing

Trung cấp (làm việc thực tế)
  transactions → jdbc_java → linux_containers

Nâng cao (vận hành production)
  query_optimization → monitoring_troubleshooting → backup_recovery → security

Chuyên sâu / theo nhu cầu
  partitioning        (bảng rất lớn, vòng đời dữ liệu)
  ha_dr               (yêu cầu RPO/RTO chặt)
  data_movement       (tích hợp, event-driven)
  sqlserver_2025      (đánh giá nâng cấp)
```

### Lối đi theo vai

| Vai | Thứ tự đề xuất |
|---|---|
| **Java backend developer** | tsql_advanced → indexing → transactions → jdbc_java → query_optimization |
| **DevOps / SRE** | architecture → linux_containers → monitoring_troubleshooting → backup_recovery → ha_dr |
| **DBA** | toàn bộ, theo learning path trên |
| **Data engineer** | architecture → indexing → partitioning → data_movement → sqlserver_2025 |

---

## Key concepts → file

| Khái niệm | File |
|---|---|
| Buffer pool, WAL, VLF, tempdb, ADR, wait stats triage | [architecture.md](fundamentals/architecture.md) |
| CTE, window function, APPLY, MERGE, OUTPUT, temporal table, JSON | [tsql_advanced.md](fundamentals/tsql_advanced.md) |
| ESR, clustered key, INCLUDE, filtered index, columnstore, statistics, execution plan | [indexing.md](fundamentals/indexing.md) |
| Isolation level, RCSI, lock escalation, deadlock, ROWVERSION, Optimized Locking | [transactions.md](fundamentals/transactions.md) |
| Parameter sniffing, Query Store, force plan, IQP, memory grant, MAXDOP | [query_optimization.md](performance/query_optimization.md) |
| DMV, Extended Events, baseline, DBCC CHECKDB, alert, runbook | [monitoring_troubleshooting.md](performance/monitoring_troubleshooting.md) |
| Partition function/scheme, SWITCH, sliding window, incremental statistics | [partitioning.md](performance/partitioning.md) |
| RPO/RTO, recovery model, PITR, tail-log, piecemeal restore, DR drill | [backup_recovery.md](administration/backup_recovery.md) |
| Always On AG, readable secondary, FCI, log shipping, failover | [ha_dr.md](administration/ha_dr.md) |
| RBAC, RLS, DDM, TDE, Always Encrypted, Ledger, Audit, TLS | [security.md](administration/security.md) |
| mssql-conf, Docker, StatefulSet, Testcontainers, Azure Arc | [linux_containers.md](platform/linux_containers.md) |
| Bulk load, Change Tracking, CDC, Debezium, Outbox, data virtualization | [data_movement.md](integration/data_movement.md) |
| JDBC driver, HikariCP, JPA, N+1, SQLServerBulkCopy, retry | [jdbc_java.md](integration/jdbc_java.md) |
| Kiểu `json`, `REGEXP_*`, `vector`, CES, OPPO, nâng compat level | [sqlserver_2025.md](modern/sqlserver_2025.md) |

---

## Quick reference: version & compatibility level

| Version | Build | Compat level | Bổ sung đáng chú ý |
|---|---|---|---|
| SQL Server 2017 | 14.x | 140 | Linux, adaptive join, memory grant feedback (batch mode), Automatic Plan Correction |
| SQL Server 2019 | 15.x | 150 | ADR, batch mode on rowstore, scalar UDF inlining, resumable index create, in-memory tempdb metadata |
| SQL Server 2022 | 16.x | 160 | PSP optimization, CE/DOP feedback, Query Store hints, contained AG, Ledger table, backup ra S3-compatible, snapshot backup bằng T-SQL, `GREATEST`/`DATETRUNC`/`GENERATE_SERIES`/`WINDOW` |
| SQL Server 2025 | 17.x | 170 | Optimized Locking, kiểu `json` + JSON index, `REGEXP_*`, `vector` + DiskANN, external model, Change Event Streaming, Fabric mirroring, OPPO, tempdb resource governance |

> ⚠️ Bảng này là ảnh chụp tại **2026-07-30**. Luôn kiểm tra tài liệu chính thức và support policy trước khi chọn version cho production.

```sql
-- Đang chạy version nào
SELECT SERVERPROPERTY('ProductVersion')  AS Build,
       SERVERPROPERTY('ProductLevel')    AS ProductLevel,
       SERVERPROPERTY('Edition')         AS Edition,
       SERVERPROPERTY('EngineEdition')   AS EngineEdition;

-- Compat level và các thiết lập quan trọng của từng database
SELECT name, compatibility_level, recovery_model_desc,
       is_read_committed_snapshot_on,
       is_accelerated_database_recovery_on,
       is_query_store_on
FROM sys.databases WHERE database_id > 4;
```

---

## Chú thích trạng thái

- ✅ Hoàn thành – đã chuẩn hóa theo phiên bản mục tiêu
- 🟡 Đã có nội dung nhưng cần rà soát/version hóa
- 🔄 Đang làm
- ⬜ Chưa làm

---

## Liên kết sang package khác

| Chủ đề liên quan | Package |
|---|---|
| Spring Boot data layer, testing, messaging | [springboot](../springboot/roadmap.md) |
| Debezium, Kafka Connect, event-driven architecture | [kafka](../kafka/roadmap.md) |
| Dashboard & alert cho metric SQL Server | [prometheus_grafana](../prometheus_grafana/roadmap.md) |
| Container, image, compose | [docker](../docker/roadmap.md) |
| StatefulSet, PV/PVC, NetworkPolicy | [kubernetes](../kubernetes/roadmap.md) |
| Cứng hóa OS, storage, systemd | [linux](../linux/roadmap.md) |
| Threat modeling, OWASP, DevSecOps | [security](../security/roadmap.md) |
| So sánh mô hình document vs quan hệ | [mongodb](../mongodb/roadmap.md) |
| Phân tích theo cột (OLAP) so với columnstore | [clickhouse](../clickhouse/roadmap.md) |

---

*Cập nhật lần cuối: 2026-07-30*
