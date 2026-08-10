---
title: "Roadmap – PostgreSQL Knowledge"
topic: postgresql
level: mixed
review_status: needs_review
content_updated: 2026-07-31
last_verified: null
version_scope: "unspecified"
source_count: 2
---
# Roadmap – PostgreSQL Knowledge

> Thuật ngữ: [Glossary](glossary.md).

> Learning path dành cho backend developer, DBA và SRE, dùng **PostgreSQL 18.x**
> làm phiên bản mục tiêu. Hành vi phụ thuộc extension/cloud provider sẽ được ghi
> rõ trong từng bài.

**Trạng thái chuẩn hóa (2026-07-31): 11/11 chủ đề – hoàn thành lộ trình.**

---

## Cấu trúc

```text
postgresql/
├── roadmap.md
├── postgresql_knowledge.md
├── fundamentals/
│   ├── architecture_storage.md       ← process, memory, page, tuple, WAL, vacuum
│   ├── data_modeling_types.md        ← schema, type, constraint, JSONB, array
│   ├── transactions_mvcc.md          ← isolation, lock, deadlock, SSI
│   ├── indexing_planner.md           ← B-tree/GIN/GiST/BRIN, statistics, EXPLAIN
│   └── advanced_sql.md               ← window, CTE, LATERAL, recursive, upsert
├── performance/
│   ├── tuning_autovacuum.md          ← workload, memory, I/O, vacuum, bloat
│   └── partitioning_large_tables.md  ← pruning, lifecycle, large-table operations
├── operations/
│   ├── replication_ha.md             ← streaming replication, failover, slots
│   ├── backup_pitr_upgrade.md        ← pg_basebackup, WAL archive, PITR, pg_upgrade
│   └── security_rls.md               ← TLS, pg_hba, roles, RLS, audit
└── integration/
    └── jdbc_spring.md                ← pgJDBC, HikariCP, PgBouncer, JPA, retry
```

---

## Danh sách chủ đề

| # | Chủ đề | File | Trạng thái | Mức độ |
|---:|---|---|---|---|
| 1 | Architecture & Storage Engine – process-per-connection, shared memory, relation/page/tuple, MVCC version, TOAST, WAL/checkpoint, vacuum và wraparound | [fundamentals/architecture_storage.md](fundamentals/architecture_storage.md) | ✅ PostgreSQL 18 | Cơ bản |
| 2 | Data Modeling & Types – database/schema, constraint, identity/sequence, timestamp, numeric, UUID, enum/domain, array, range, JSONB và schema evolution | [fundamentals/data_modeling_types.md](fundamentals/data_modeling_types.md) | ✅ PostgreSQL 18 | Cơ bản |
| 3 | Transactions, MVCC & Locking – snapshot, isolation, row/table/advisory lock, deadlock, lost update, write skew, Serializable SSI và retry | [fundamentals/transactions_mvcc.md](fundamentals/transactions_mvcc.md) | ✅ PostgreSQL 18 | Trung cấp |
| 4 | Indexing & Query Planner – B-tree, hash, GIN, GiST, SP-GiST, BRIN, partial/expression/covering index, statistics, EXPLAIN và plan stability | [fundamentals/indexing_planner.md](fundamentals/indexing_planner.md) | ✅ PostgreSQL 18 | Trung cấp |
| 5 | Advanced SQL – window, CTE materialization, recursive query, LATERAL, DISTINCT ON, upsert/MERGE, grouping sets và set-based patterns | [fundamentals/advanced_sql.md](fundamentals/advanced_sql.md) | ✅ PostgreSQL 18 | Trung cấp |
| 6 | Performance & Autovacuum – workload benchmark, connection/memory/I/O, pg_stat_statements, vacuum/analyze, bloat, checkpoint và incident runbook | [performance/tuning_autovacuum.md](performance/tuning_autovacuum.md) | ✅ PostgreSQL 18 | Nâng cao |
| 7 | Partitioning & Large Tables – pruning, local index, attach/detach, lifecycle, bulk load, online migration và khi không nên partition | [performance/partitioning_large_tables.md](performance/partitioning_large_tables.md) | ✅ PostgreSQL 18 | Nâng cao |
| 8 | Replication & HA – physical/logical replication, WAL sender/receiver, slot, synchronous commit, failover, fencing, rewind và split-brain prevention | [operations/replication_ha.md](operations/replication_ha.md) | ✅ PostgreSQL 18 | Nâng cao |
| 9 | Backup, PITR & Upgrade – logical/physical backup, WAL archive, restore drill, RPO/RTO, pgBackRest/Barman, pg_upgrade và blue-green migration | [operations/backup_pitr_upgrade.md](operations/backup_pitr_upgrade.md) | ✅ PostgreSQL 18 | Nâng cao |
| 10 | Security & Row-Level Security – TLS, pg_hba, SCRAM, role/ownership, default privilege, RLS, secret rotation, audit và tenant boundary | [operations/security_rls.md](operations/security_rls.md) | ✅ PostgreSQL 18 | Nâng cao |
| 11 | PostgreSQL từ Java/Spring – pgJDBC, HikariCP, PgBouncer, prepared statement, batch/COPY, transaction, JPA type mapping và retry | [integration/jdbc_spring.md](integration/jdbc_spring.md) | ✅ PostgreSQL 18 | Trung cấp |

---

## Learning path

```text
architecture_storage
        │
        ├──► data_modeling_types ──► advanced_sql
        │
        ├──► transactions_mvcc
        │           │
        │           └──► jdbc_spring
        │
        └──► indexing_planner ──► tuning_autovacuum
                                      │
                         ┌────────────┼────────────┐
                         ▼            ▼            ▼
                    partitioning  replication  backup/security
```

| Vai | Thứ tự đề xuất |
|---|---|
| Java backend | architecture → data modeling → transactions → indexing → JDBC |
| DBA/SRE | architecture → tuning → replication → backup → security |
| Data engineer | architecture → data modeling → advanced SQL → partitioning → logical replication |
| Chuẩn bị phỏng vấn | architecture → transactions → indexing → tuning |

---

## Nguyên tắc xuyên suốt

1. MVCC giảm reader/writer blocking nhưng tạo row version phải được vacuum.
2. Commit bền nhờ WAL; checkpoint không phải backup.
3. Index và planner phải được thiết kế từ query shape cùng phân bố dữ liệu.
4. Connection, `work_mem` và transaction đều là tài nguyên nhân theo concurrency.
5. Replica không thay backup; failover phải có fencing và restore phải được drill.
6. PostgreSQL mặc định an toàn khá tốt; không tắt `fsync`, `full_page_writes` hoặc
   autovacuum để lấy benchmark đẹp.
7. Tách owner `NOLOGIN`, migration identity và runtime role; application không sở hữu table,
   không có `BYPASSRLS` và không nhận privilege qua `PUBLIC` ngoài chủ đích.
8. RLS là một lớp authorization, không thay TLS, object privilege, tenant-aware constraint
   hay kiểm soát connection-pool context.
9. Pool size là admission budget của toàn fleet, không phải knob tăng throughput vô hạn;
   retry phải bao ngoài một transaction mới và operation phải idempotent.
10. Java type, transaction proxy, PgBouncer mode và replica routing đều là contract phải
    integration test với PostgreSQL thật, không suy luận từ H2 hoặc annotation.

---

## Nguồn phiên bản

- [PostgreSQL 18 documentation](https://www.postgresql.org/docs/18/)
- [Supported versions](https://www.postgresql.org/support/versioning/)

---

*Cập nhật lần cuối: 2026-07-31.*

---

<!-- AUTO-GENERATED-DOC-INDEX:START -->

## Tài liệu trong chủ đề

- [PostgreSQL Advanced SQL](fundamentals/advanced_sql.md)
- [PostgreSQL Architecture & Storage Engine](fundamentals/architecture_storage.md)
- [PostgreSQL Data Modeling & Types](fundamentals/data_modeling_types.md)
- [PostgreSQL Indexing & Query Planner](fundamentals/indexing_planner.md)
- [PostgreSQL Transactions, MVCC & Locking](fundamentals/transactions_mvcc.md)
- [Glossary PostgreSQL](glossary.md)
- [PostgreSQL từ Java và Spring](integration/jdbc_spring.md)
- [PostgreSQL Backup, PITR & Upgrade](operations/backup_pitr_upgrade.md)
- [PostgreSQL Replication & High Availability](operations/replication_ha.md)
- [PostgreSQL Security & Row-Level Security](operations/security_rls.md)
- [PostgreSQL Partitioning & Large Tables](performance/partitioning_large_tables.md)
- [PostgreSQL Performance & Autovacuum](performance/tuning_autovacuum.md)
- [PostgreSQL – Tổng hợp kiến thức](postgresql_knowledge.md)

<!-- AUTO-GENERATED-DOC-INDEX:END -->
