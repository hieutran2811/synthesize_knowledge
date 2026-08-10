---
title: "Glossary PostgreSQL"
topic: postgresql
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Glossary PostgreSQL

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|---|---|---|
| Autovacuum | Dọn dẹp tự động | Worker thu hồi tuple chết và cập nhật statistics. |
| MVCC | Điều khiển đồng thời đa phiên bản | Cho phép transaction đọc snapshot phù hợp mà ít chặn writer. |
| Planner | Bộ lập kế hoạch | Chọn execution plan dựa trên cost và statistics. |
| Replication slot | Khe sao chép | Giữ WAL cần thiết cho consumer replication. |
| VACUUM | Dọn tuple chết | Bảo trì storage, visibility map và transaction ID. |
| WAL | Nhật ký ghi trước | Log thay đổi dùng cho durability, recovery và replication. |

