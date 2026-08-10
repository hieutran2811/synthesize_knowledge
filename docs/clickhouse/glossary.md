---
title: "Glossary ClickHouse"
topic: clickhouse
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Glossary ClickHouse

| Thuật ngữ | Nghĩa tiếng Việt | Giải thích ngắn |
|---|---|---|
| Data part | Phần dữ liệu | Tập file bất biến sinh ra sau mỗi lần insert/merge. |
| Merge | Hợp nhất | Tiến trình nền gộp các data part. |
| MergeTree | Họ storage engine MergeTree | Nhóm engine cốt lõi cho workload phân tích. |
| Mutation | Biến đổi dữ liệu | Thao tác update/delete bất đồng bộ trên part. |
| Primary key | Khóa sắp xếp chính | Biểu thức hỗ trợ pruning, không mang nghĩa unique mặc định. |
| Skip index | Chỉ mục bỏ qua | Metadata giúp loại bỏ granule không phù hợp truy vấn. |

