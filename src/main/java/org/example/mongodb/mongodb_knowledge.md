# Tổng Hợp Kiến Thức MongoDB – Thực Chiến

> Learning path đã được chuẩn hóa theo MongoDB 8.2. Xem [roadmap](roadmap.md) và [glossary](glossary.md) để tra cứu chủ đề/thuật ngữ.

---

## Tổng Quan

**MongoDB** là NoSQL document database, lưu data dưới dạng BSON (Binary JSON). Phù hợp cho dữ liệu semi-structured, schema linh hoạt, scale-out.

```
Client (mongosh / driver)
    ↓ MongoDB Wire Protocol
mongod (primary)
    ├── Query Engine (Aggregation Pipeline)
    ├── Storage Engine (WiredTiger)
    ├── Replication (oplog → secondaries)
    └── Sharding (mongos → config servers → shards)
```

---

## Danh Sách Sub-Topics

### Fundamentals
| # | Topic | File | Status |
|---|-------|------|--------|
| 1 | Data Model & BSON | [fundamentals/data_model.md](fundamentals/data_model.md) | ✅ MongoDB 8.2 |
| 2 | CRUD & Aggregation Pipeline | [fundamentals/crud_aggregation.md](fundamentals/crud_aggregation.md) | ✅ MongoDB 8.2 |
| 3 | Indexing | [fundamentals/indexing.md](fundamentals/indexing.md) | ✅ MongoDB 8.2 |
| 4 | Transactions | [fundamentals/transactions.md](fundamentals/transactions.md) | ✅ MongoDB 8.2 |

### Performance & Design
| # | Topic | File | Status |
|---|-------|------|--------|
| 5 | Schema Design Patterns | [performance/schema_design.md](performance/schema_design.md) | ✅ MongoDB 8.2 |

### Operations
| # | Topic | File | Status |
|---|-------|------|--------|
| 6 | Replica Set | [operations/replication.md](operations/replication.md) | ✅ MongoDB 8.2 |
| 7 | Sharding | [operations/sharding.md](operations/sharding.md) | ✅ MongoDB 8.2 |
| 8 | Backup & Security | [operations/backup_security.md](operations/backup_security.md) | ✅ MongoDB 8.2 |

---

## Learning Path

```
Cơ bản:   data_model → crud_aggregation → indexing
Trung cấp: transactions → schema_design → replication
Nâng cao:  sharding → backup_security
```

---

*Cập nhật lần cuối: 2026-07-29*
