# Đóng góp nội dung

## Quy trình

1. Chọn một issue hoặc mục trong `docs/MAINTENANCE_BACKLOG.md`.
2. Chỉ sửa một phạm vi kiến thức rõ ràng trong mỗi pull request.
3. Ưu tiên tài liệu chính thức, tiêu chuẩn, RFC và tài liệu nhà cung cấp gốc.
4. Chạy `scripts/Sync-Docs.ps1`, sau đó `scripts/Test-Docs.ps1 -Strict`.
5. Dùng Conventional Commits, ví dụ `docs(kafka): clarify consumer rebalance trade-offs`.

## Definition of Done

Một tài liệu được coi là hoàn thành khi:

- có metadata hợp lệ và một H1 duy nhất;
- nêu phạm vi phiên bản hoặc ghi rõ nội dung không phụ thuộc phiên bản;
- giải thích What, Why, How, When và trade-off ở mức phù hợp;
- có ví dụ hoặc tình huống production khi chủ đề cần;
- liên kết tới glossary của chủ đề;
- các khẳng định nhạy cảm theo phiên bản có nguồn chính thức;
- có `content_updated` và chỉ đặt `last_verified` sau khi thực sự đối chiếu nguồn;
- mọi liên kết và quality gate đều vượt qua.

## Trạng thái rà soát

- `needs_review`: chưa được kiểm chứng theo quy trình hiện tại.
- `in_review`: đang được đối chiếu nguồn và ví dụ.
- `verified`: đã đối chiếu các khẳng định quan trọng với nguồn được liệt kê vào ngày `last_verified`.
- `deprecated`: chỉ giữ để hỗ trợ migration hoặc lịch sử.

Không tự động đổi `needs_review` thành `verified` chỉ vì đã sửa format, thêm metadata hoặc chạy link checker.

## Quy tắc phạm vi

- `docs/springboot/` là nguồn canonical cho Spring Boot application và production practice.
- `docs/java/spring/` tập trung vào Spring Framework và tích hợp trong hệ sinh thái Java; nội dung Spring Boot trùng lặp phải trỏ về tài liệu canonical.
- Không mở chủ đề mới khi vẫn còn lỗi P0/P1 trong backlog cùng lĩnh vực.

