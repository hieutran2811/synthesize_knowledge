# Tổng Hợp Kiến Thức MongoDB – Thực Chiến

> Phương pháp: What – How – Why – Components – Compare – Trade-offs – Real-world – Ghi chú

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
| 1 | Data Model & BSON | `fundamentals/data_model.md` | ✅ |
| 2 | CRUD & Aggregation Pipeline | `fundamentals/crud_aggregation.md` | ✅ |
| 3 | Indexing | `fundamentals/indexing.md` | ✅ |
| 4 | Transactions | `fundamentals/transactions.md` | ✅ |

### Performance & Design
| # | Topic | File | Status |
|---|-------|------|--------|
| 5 | Schema Design Patterns | `performance/schema_design.md` | ✅ |

### Operations
| # | Topic | File | Status |
|---|-------|------|--------|
| 6 | Replica Set | `operations/replication.md` | ✅ |
| 7 | Sharding | `operations/sharding.md` | ✅ |
| 8 | Backup & Security | `operations/backup_security.md` | ✅ |

---

## Learning Path

```
Cơ bản:   data_model → crud_aggregation → indexing
Trung cấp: transactions → schema_design → replication
Nâng cao:  sharding → backup_security
```

---

*Cập nhật lần cuối: 2026-05-06*
