---
title: "Backlog bảo trì nội dung"
topic: governance
level: mixed
review_status: verified
content_updated: 2026-08-10
last_verified: 2026-08-10
version_scope: "Baseline repository ngày 2026-08-10"
source_count: 0
---

# Backlog bảo trì nội dung

Backlog này theo dõi chất lượng và khả năng duy trì, không dùng số lượng file mới làm thước đo tiến độ.

## P0 — Nền tảng repository

- [x] Chuyển nội dung khỏi cây Java sang `docs/`.
- [x] Tạo README, hướng dẫn đóng góp và quy chuẩn biên soạn.
- [x] Bổ sung glossary cho 19/19 chủ đề.
- [x] Thêm metadata và liên kết glossary cho tài liệu hiện có.
- [x] Thêm kiểm tra cấu trúc, link, metadata và code fence.
- [x] Dựng MkDocs và workflow build/deploy.
- [ ] Chủ sở hữu chọn giấy phép công bố; đây là quyết định pháp lý, không tự động suy đoán.

## P1 — Kiểm chứng nội dung

Mỗi batch chỉ chuyển `review_status` sang `verified` sau khi đối chiếu nguồn chính thức và ghi `last_verified`.

1. **Git và WebSocket:** bổ sung nguồn, phạm vi phiên bản và ngày kiểm chứng.
2. **Angular và Linux:** rà các file cũ thiếu nguồn hoặc freshness metadata.
3. **Java:** ưu tiên JVM, concurrency, serialization, networking và Spring integration.
4. **SQL Server và System Design:** thêm nguồn cho các khẳng định về version/default và tách fact khỏi heuristic.
5. **Security, PostgreSQL, Observability:** kiểm tra lại URL, version scope và runbook có tác động production cao.

Quality gate in cảnh báo chính xác danh sách file nhạy cảm theo phiên bản nhưng chưa có external source.

## P1 — Chia nhỏ tài liệu lớn

Baseline hiện có 71 tài liệu trên 1.000 dòng. Không tách máy móc theo số dòng; chỉ tách khi file có nhiều mục tiêu đọc hoặc nhiều lifecycle độc lập.

Ưu tiên:

1. `security/security_knowledge.md` — tách overview/index khỏi nội dung deep dive.
2. Các file observability trên 1.500 dòng — tách fundamentals, operations và runbook.
3. Các chương PostgreSQL — giữ chapter map và tách phần hands-on/runbook khi cần.
4. `docker/docker_knowledge.md`, `linux/linux_knowledge.md` và các overview lớn — chuyển thành landing page ngắn liên kết tới deep dive.

Mỗi lần tách phải giữ redirect/link từ vị trí cũ và chạy kiểm tra liên kết.

## P1 — Loại bỏ trùng phạm vi

- [x] Quy định `springboot/` là canonical cho Spring Boot application/production.
- [ ] Rà từng phần trùng giữa `java/spring/` và `springboot/`; thay nội dung trùng bằng summary và link canonical.
- [ ] Lập dependency map cho Docker → Kubernetes → Observability → Security.
- [ ] Chọn canonical page cho các pattern lặp lại như outbox, retry, circuit breaker và rate limiting.

## P2 — Trải nghiệm học tập

- [ ] Thêm `prerequisites`, `learning_outcomes` và `estimated_time` sau khi schema thí điểm ổn định.
- [ ] Chọn 20 tài liệu nền tảng để thêm bài thực hành có thể chạy lại.
- [ ] Thêm câu hỏi tự kiểm tra và tiêu chí hoàn thành cho năm learning path theo vai trò.
- [ ] Tạo lịch kiểm chứng theo volatility: hàng quý cho framework/cloud/security; nửa năm cho nền tảng ổn định.
- [ ] Phát hành `v1.0` khi các cảnh báo P0 bằng 0 và batch nội dung nền tảng đã được xác minh.

