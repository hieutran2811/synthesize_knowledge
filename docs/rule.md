---
title: "Quy chuẩn biên soạn và kiểm chứng"
topic: governance
level: mixed
review_status: verified
content_updated: 2026-08-10
last_verified: 2026-08-10
version_scope: "Không phụ thuộc phiên bản"
source_count: 0
---

# Quy chuẩn biên soạn và kiểm chứng

## Mục tiêu

Mỗi tài liệu phải giúp người đọc hiểu đúng cơ chế, biết khi nào áp dụng, nhận ra trade-off và có đường dẫn để kiểm chứng các chi tiết phụ thuộc phiên bản.

## Khung nội dung

Chọn các câu hỏi phù hợp với chủ đề, không buộc mọi file phải có cùng số mục:

- **What:** khái niệm là gì và ranh giới của nó ở đâu?
- **Why:** vấn đề nào khiến khái niệm này cần thiết?
- **How:** cơ chế, luồng dữ liệu hoặc vòng đời hoạt động thế nào?
- **Components:** thành phần nào tham gia và trách nhiệm của chúng?
- **When:** khi nào nên hoặc không nên dùng?
- **Compare:** khác lựa chọn thay thế ở điểm nào?
- **Trade-offs:** đánh đổi về correctness, latency, cost, complexity và operability?
- **Production:** failure mode, quan sát, bảo mật, rollback và runbook tối thiểu?

## Giải thích dễ hiểu

- Giữ thuật ngữ tiếng Anh thường dùng trong công việc và chú thích tiếng Việt ở lần xuất hiện đầu tiên khi cần.
- Với cơ chế khó, thêm diễn giải đời thường hoặc ví von nhưng không thay thế mô tả kỹ thuật chính xác.
- Tách câu chứa quá nhiều khái niệm; ưu tiên sơ đồ luồng và ví dụ nhỏ có mục đích rõ ràng.
- Không lạm dụng callout hoặc ví von ở phần người đọc có thể hiểu trực tiếp.

## Glossary và điều hướng

- Mỗi chủ đề có đúng một `glossary.md` cấp cao nhất.
- Mỗi file trong chủ đề liên kết tới glossary gần đầu tài liệu.
- Mỗi chủ đề có `roadmap.md` chứa learning path và mục lục có thể bấm được.
- Nội dung trùng phạm vi phải chọn một tài liệu canonical và liên kết về tài liệu đó.

## Nguồn và phiên bản

- Ưu tiên tiêu chuẩn, RFC, tài liệu dự án hoặc tài liệu nhà cung cấp chính thức.
- Khẳng định về version, default, giới hạn, deprecation hoặc hành vi production phải có nguồn.
- `content_updated` chỉ cho biết file được cập nhật.
- Chỉ điền `last_verified` và đặt `review_status: verified` sau khi đã đối chiếu nguồn cho các khẳng định quan trọng.
- Nếu chưa đủ bằng chứng, giữ `review_status: needs_review`; không suy diễn trạng thái từ Git hoặc ngày sửa file.

## Definition of Done

Definition of Done chi tiết và quy trình đóng góp nằm tại [Hướng dẫn đóng góp](contributing.md). Mọi thay đổi phải vượt qua `scripts/Test-Docs.ps1 -Strict` và build website ở chế độ strict.
