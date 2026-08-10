# Synthesize Knowledge

Kho tri thức kỹ thuật bằng tiếng Việt, tập trung vào mental model, trade-off và cách vận hành production. Nội dung bao phủ backend, dữ liệu, hạ tầng, observability, security và system design.

## Bắt đầu

- Đọc [trang chủ tài liệu](docs/index.md) để chọn learning path hoặc chủ đề.
- Mỗi chủ đề có `roadmap.md` để điều hướng và `glossary.md` để tra cứu thuật ngữ.
- Quy chuẩn nội dung nằm tại [docs/rule.md](docs/rule.md).
- Cách đóng góp và Definition of Done nằm tại [CONTRIBUTING.md](CONTRIBUTING.md).

## Chạy kiểm tra

```powershell
pwsh -File scripts/Test-Docs.ps1 -Strict
```

Đồng bộ metadata, liên kết glossary và mục lục tự sinh:

```powershell
pwsh -File scripts/Sync-Docs.ps1
```

## Chạy website cục bộ

Yêu cầu Python 3.11+:

```bash
python -m venv .venv
python -m pip install -r requirements-docs.txt
mkdocs serve
```

Website production được build bằng `mkdocs build --strict`; CI kiểm tra cấu trúc tài liệu trước khi build.

Workflow chỉ deploy GitHub Pages khi repository variable `ENABLE_PAGES_DEPLOY` được đặt thành `true`. Hãy chọn giấy phép trước khi bật biến này.

## Trạng thái chất lượng

Repository dùng metadata `review_status` để phân biệt nội dung đã xuất bản với nội dung đã được kiểm chứng. Việc một file tồn tại hoặc có ngày cập nhật không đồng nghĩa mọi khẳng định trong file đã được fact-check.

## Giấy phép

Chưa chọn giấy phép công bố. Không nên tái phân phối repository ra ngoài cho đến khi chủ sở hữu chọn giấy phép phù hợp, ví dụ CC BY 4.0 cho nội dung hoặc một giấy phép riêng.
