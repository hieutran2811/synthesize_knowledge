---
title: "Hướng dẫn đóng góp"
topic: governance
level: mixed
review_status: verified
content_updated: 2026-08-10
last_verified: 2026-08-10
version_scope: "Không phụ thuộc phiên bản"
source_count: 0
---

# Hướng dẫn đóng góp

## Luồng làm việc

1. Chọn một mục trong [backlog bảo trì](MAINTENANCE_BACKLOG.md).
2. Chỉ sửa một phạm vi kiến thức rõ ràng trong mỗi pull request.
3. Đối chiếu nguồn chính thức cho chi tiết phụ thuộc phiên bản.
4. Chạy script đồng bộ và validation.
5. Dùng Conventional Commits mô tả đúng mục đích thay đổi.

## Lệnh kiểm tra

```powershell
pwsh -File scripts/Sync-Docs.ps1
pwsh -File scripts/Test-Docs.ps1 -Strict
```

Xem [quy chuẩn biên soạn](rule.md) để biết yêu cầu metadata, nguồn, glossary và Definition of Done.

