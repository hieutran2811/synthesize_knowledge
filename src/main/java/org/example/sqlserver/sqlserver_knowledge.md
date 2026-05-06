# Tổng Hợp Kiến Thức SQL Server – Thực Chiến

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

---

## Tổng Quan

**SQL Server** là RDBMS của Microsoft, chạy trên Windows và Linux (2017+). Được dùng rộng rãi trong enterprise, đặc biệt hệ sinh thái .NET/Java.

```
Client (SSMS / app)
    ↓ TDS protocol
SQL Server Engine
    ├── Query Processor (Parser → Optimizer → Executor)
    ├── Storage Engine (Buffer Pool → Data Files / Log Files)
    ├── Lock Manager
    └── Transaction Manager
```

---

## Danh Sách Sub-Topics

### Fundamentals
| # | Topic | File | Status |
|---|-------|------|--------|
| 1 | Architecture & Storage Engine | `fundamentals/architecture.md` | ✅ |
| 2 | T-SQL Advanced | `fundamentals/tsql_advanced.md` | ✅ |
| 3 | Indexing & Execution Plans | `fundamentals/indexing.md` | ✅ |
| 4 | Transactions, Locking & Isolation | `fundamentals/transactions.md` | ✅ |

### Performance
| # | Topic | File | Status |
|---|-------|------|--------|
| 5 | Query Optimization | `performance/query_optimization.md` | ✅ |

### Administration
| # | Topic | File | Status |
|---|-------|------|--------|
| 6 | Backup & Recovery | `administration/backup_recovery.md` | ✅ |
| 7 | High Availability & DR | `administration/ha_dr.md` | ✅ |
| 8 | Security | `administration/security.md` | ✅ |

---

## Learning Path

```
Cơ bản:   architecture → tsql_advanced → indexing
Trung cấp: transactions → query_optimization → security
Nâng cao:  backup_recovery → ha_dr
```

---

*Cập nhật lần cuối: 2026-05-06*
