---
title: "Roadmap – MongoDB Knowledge"
topic: mongodb
level: mixed
review_status: needs_review
content_updated: 2026-07-29
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Roadmap – MongoDB Knowledge

> 📖 Tra cứu nhanh: [MongoDB Glossary](glossary.md)
>
> Learning path đã hoàn tất chuẩn hóa 8 chủ đề theo phiên bản mục tiêu MongoDB 8.2.

| # | Topic | File | Status | Level |
|---|-------|------|--------|-------|
| 1 | Data Model & BSON | [fundamentals/data_model.md](fundamentals/data_model.md) | ✅ MongoDB 8.2 | Cơ bản |
| 2 | CRUD & Aggregation Pipeline | [fundamentals/crud_aggregation.md](fundamentals/crud_aggregation.md) | ✅ MongoDB 8.2 | Cơ bản |
| 3 | Indexing | [fundamentals/indexing.md](fundamentals/indexing.md) | ✅ MongoDB 8.2 | Trung cấp |
| 4 | Transactions | [fundamentals/transactions.md](fundamentals/transactions.md) | ✅ MongoDB 8.2 | Trung cấp |
| 5 | Schema Design Patterns | [performance/schema_design.md](performance/schema_design.md) | ✅ MongoDB 8.2 | Trung cấp |
| 6 | Replica Set | [operations/replication.md](operations/replication.md) | ✅ MongoDB 8.2 | Nâng cao |
| 7 | Sharding | [operations/sharding.md](operations/sharding.md) | ✅ MongoDB 8.2 | Nâng cao |
| 8 | Backup & Security | [operations/backup_security.md](operations/backup_security.md) | ✅ MongoDB 8.2 | Nâng cao |

## Key Concepts

| Concept | File |
|---------|------|
| Document model, BSON types, ObjectId, Embed vs Reference | [data_model.md](fundamentals/data_model.md) |
| CRUD operators, Aggregation Pipeline stages, Window functions | [crud_aggregation.md](fundamentals/crud_aggregation.md) |
| Single/Compound/Multikey/Text/Geo/Wildcard indexes, ESR Rule | [indexing.md](fundamentals/indexing.md) |
| Multi-document transactions, Write/Read concerns, Retry logic | [transactions.md](fundamentals/transactions.md) |
| Bucket, Outlier, Computed, Subset, Extended Reference, Polymorphic, Tree, Schema Versioning, Archive | [schema_design.md](performance/schema_design.md) |
| Replica set topology, Oplog, Election/Term, Majority commit, Lag, Rollback, Failover runbook | [replication.md](operations/replication.md) |
| Shard key analyzer, routing, ranges, balancer, zones, resharding, sharding runbook | [sharding.md](operations/sharding.md) |
| RPO/RTO, PITR, restore drill, RBAC, TLS/x.509, encryption, auditing, incident runbook | [backup_security.md](operations/backup_security.md) |

## Chú thích trạng thái

- ✅ Hoàn thành – đã refactor theo phiên bản mục tiêu
- 🟡 Đã có nội dung nhưng cần rà soát/version hóa
- 🔄 Đang làm
- ⬜ Chưa làm

*Cập nhật lần cuối: 2026-07-29*

---

<!-- AUTO-GENERATED-DOC-INDEX:START -->

## Tài liệu trong chủ đề

- [MongoDB CRUD & Aggregation Pipeline](fundamentals/crud_aggregation.md)
- [MongoDB Data Model & BSON](fundamentals/data_model.md)
- [MongoDB Indexing – thiết kế từ query pattern](fundamentals/indexing.md)
- [MongoDB Transactions – correctness trước, transaction sau](fundamentals/transactions.md)
- [MongoDB Glossary](glossary.md)
- [Tổng Hợp Kiến Thức MongoDB – Thực Chiến](mongodb_knowledge.md)
- [MongoDB Backup & Security – Recovery và phòng thủ nhiều lớp](operations/backup_security.md)
- [MongoDB Replica Set – High Availability và vận hành production](operations/replication.md)
- [MongoDB Sharding – Chọn shard key và vận hành production](operations/sharding.md)
- [MongoDB Schema Design Patterns – Thiết kế theo access pattern](performance/schema_design.md)

<!-- AUTO-GENERATED-DOC-INDEX:END -->
