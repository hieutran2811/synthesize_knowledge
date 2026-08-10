---
title: "Semantic Versioning, Conventional Commits & Changelog"
topic: git
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Semantic Versioning, Conventional Commits & Changelog

> Thuật ngữ: [Glossary](../glossary.md).

> Deep dive cho topic 8-9 của `git_knowledge.md`. Trọng tâm: đánh số version có ý nghĩa, chuẩn commit để tự động hóa, sinh changelog cho release.

---

## 1. Semantic Versioning (SemVer 2.0.0)

### What
**SemVer** là quy ước đánh số version theo dạng `MAJOR.MINOR.PATCH` (vd `2.4.1`), trong đó **mỗi số mang ý nghĩa** về mức độ thay đổi tương thích.

### How – Quy tắc tăng số
```
        MAJOR . MINOR . PATCH
          │       │       │
          │       │       └─ Sửa lỗi, tương thích ngược (bug fix)
          │       └───────── Tính năng mới, TƯƠNG THÍCH ngược
          └───────────────── Thay đổi PHÁ VỠ tương thích (breaking change)
```
| Tình huống | Tăng | Ví dụ |
|-----------|------|-------|
| Sửa bug, không đổi API | PATCH | `1.4.2 → 1.4.3` |
| Thêm API/tính năng mới, code cũ vẫn chạy | MINOR (reset PATCH) | `1.4.3 → 1.5.0` |
| Đổi/xóa API, code cũ hỏng | MAJOR (reset MINOR+PATCH) | `1.5.0 → 2.0.0` |

### Components – Version đầy đủ
```
1.0.0-alpha.1+build.2026
│ │ │  └─────┘ └────────┘
│ │ │  pre-release  build metadata (không tính khi so sánh)
MAJOR MINOR PATCH
```
- **Pre-release**: `-alpha`, `-beta`, `-rc.1` → version chưa ổn định, ưu tiên thấp hơn bản chính thức (`1.0.0-rc.1` < `1.0.0`).
- **Build metadata**: `+...` → bị bỏ qua khi so sánh thứ tự.
- **`0.y.z`**: giai đoạn phát triển ban đầu, **API có thể đổi bất cứ lúc nào**.
- **`1.0.0`**: đánh dấu API ổn định công khai lần đầu.

### Why
- **Người dùng/thư viện phụ thuộc** biết ngay nâng cấp có rủi ro không: PATCH/MINOR an toàn, MAJOR cần đọc kỹ.
- Nền tảng cho **dependency range** (`^1.4.0` = nhận mọi `1.x.y`, không nhận `2.0.0`).
- Giao tiếp rõ ràng giữa team backend/frontend/mobile về breaking change.

### Compare – SemVer vs cách khác
| Kiểu | Ví dụ | Ưu | Nhược |
|------|-------|----|-------|
| **SemVer** | `2.4.1` | Mang ý nghĩa tương thích | Cần kỷ luật xác định breaking |
| **CalVer** | `2026.07.0` | Biết ngày phát hành, hợp app/SaaS | Không nói gì về tương thích |
| **Sequential** | `build-1423` | Đơn giản | Vô nghĩa với người dùng |

### Trade-offs
- (+) Chuẩn công nghiệp, tooling hỗ trợ khắp nơi (npm, Maven, pip, cargo).
- (−) Quyết định "cái này có phải breaking không?" đôi khi mơ hồ.
- (−) Với app cuối (không phải library), tương thích API ít ý nghĩa → nhiều team dùng CalVer.

### Real-world – Dependency range (npm/Maven)
```
^1.4.2  → >=1.4.2 <2.0.0   (nhận minor+patch mới, phổ biến nhất)
~1.4.2  → >=1.4.2 <1.5.0   (chỉ patch)
1.4.2   → khóa cứng đúng version
```

### Ghi chú
> Pre-release, CalVer, dependency range, `0.x` unstable, lockfile

---

## 2. Conventional Commits

### What
Chuẩn **format message commit** để máy đọc được, từ đó **tự suy ra version bump** và **sinh changelog**.

### How – Cú pháp
```
<type>(<scope>)<!>: <mô tả ngắn>

<body: giải thích chi tiết, tùy chọn>

<footer: BREAKING CHANGE:, Closes #123>
```
Ví dụ:
```
feat(payment): thêm cổng thanh toán VNPay
fix(auth): sửa lỗi token hết hạn không refresh
docs(readme): cập nhật hướng dẫn cài đặt
feat(api)!: đổi response format sang JSON:API   ← ! = breaking
```

### Components – Các `type` chuẩn
| Type | Ý nghĩa | Ảnh hưởng version |
|------|---------|-------------------|
| `feat` | Tính năng mới | → **MINOR** |
| `fix` | Sửa lỗi | → **PATCH** |
| `docs` | Tài liệu | Không |
| `style` | Format, không đổi logic | Không |
| `refactor` | Tái cấu trúc, không đổi hành vi | Không |
| `perf` | Cải thiện hiệu năng | → PATCH |
| `test` | Thêm/sửa test | Không |
| `build` / `ci` | Build system / CI | Không |
| `chore` | Việc lặt vặt (deps, config) | Không |
| `BREAKING CHANGE:` (footer) hoặc `!` | Phá vỡ tương thích | → **MAJOR** |

### How – Ánh xạ commit → SemVer (tự động)
```
fix: ...                    → bump PATCH   (1.4.2 → 1.4.3)
feat: ...                   → bump MINOR   (1.4.3 → 1.5.0)
feat!: ... / BREAKING CHANGE→ bump MAJOR   (1.5.0 → 2.0.0)
```

### Why
- **Tự động hóa hoàn toàn**: tool đọc commit từ tag trước → tính version mới → tạo tag → sinh CHANGELOG → publish. Không quyết định version thủ công.
- Lịch sử `git log` đọc được như tài liệu.
- Bắt buộc dev suy nghĩ "thay đổi này thuộc loại gì, có breaking không".

### Real-world – Enforce
- **commitlint** + **commit-msg hook** (Husky) → chặn commit sai format ngay local.
- **commitizen** (`git cz`) → wizard hỏi type/scope/message.
- CI kiểm tra lại toàn bộ commit trong PR.

### Ghi chú
> commitlint, commitizen, Husky commit-msg hook, scope, `BREAKING CHANGE`

---

## 3. Git Tag cho version (thực hành)

### What – Recap
Tag neo một version vào commit cụ thể; dùng **annotated tag** cho release (xem topic 8 overview).

### How – Quy ước & thao tác
```bash
# Quy ước tên: có tiền tố "v" (phổ biến) hoặc không — nhất quán trong team
git tag -a v1.5.0 -m "Release 1.5.0"
git push origin v1.5.0

# Tìm version hiện tại theo tag gần nhất
git describe --tags            # vd: v1.5.0-3-gabc123 (3 commit sau v1.5.0)

# Liệt kê tag theo thứ tự version
git tag --sort=-v:refname | head

# So sánh 2 version: những gì thay đổi giữa v1.4.0 và v1.5.0
git log v1.4.0..v1.5.0 --oneline
```

### Why – `git describe`
Cho ra chuỗi version chính xác cho **mọi build**, kể cả build giữa hai tag → nhúng vào artifact/`--version` của app để truy vết "prod đang chạy commit nào".

### Trade-offs – Tiền tố `v`
- `v1.5.0`: phổ biến, dễ phân biệt tag version với tag khác (GitHub Releases mặc định).
- `1.5.0`: một số tool (Maven) không thích `v`. → **Chọn một kiểu và giữ nhất quán.**

### Ghi chú
> Annotated vs lightweight tag, `git describe`, signed tag `-s`, tag naming, `v1.4.0..v1.5.0`

---

## 4. CHANGELOG

### What
`CHANGELOG.md` – nhật ký thay đổi giữa các version, **viết cho con người** (user/dev), khác với `git log` (chi tiết kỹ thuật).

### How – Chuẩn "Keep a Changelog"
```markdown
# Changelog

## [Unreleased]

## [1.5.0] - 2026-07-15
### Added
- Cổng thanh toán VNPay (#123)
- Đăng nhập Google OAuth (#130)

### Fixed
- Token hết hạn không tự refresh (#128)

### Changed
- Nâng Spring Boot 3.2 → 3.3

## [1.4.3] - 2026-06-30
### Security
- Vá lỗ hổng SQL injection ở API tìm kiếm (CVE-2026-xxxx)
```
Nhóm chuẩn: **Added / Changed / Deprecated / Removed / Fixed / Security**.

### Why
- Người dùng biết nên nâng cấp không, có gì mới, có breaking gì.
- Đội vận hành/support tra cứu nhanh "version này sửa bug X chưa".
- Bắt buộc cho open-source & sản phẩm bán ra.

### Compare – Thủ công vs Tự động
| | Thủ công | Tự động (từ Conventional Commits) |
|--|----------|-----------------------------------|
| Công sức | Cao, dễ quên | Gần như 0 |
| Chất lượng chữ | Có thể trau chuốt | Phụ thuộc chất lượng commit |
| Nhất quán | Dễ lệch | Luôn nhất quán |

### Real-world – Tool tự sinh
- **standard-version** / **release-please** (Google): đọc Conventional Commits → bump version + sinh CHANGELOG + tạo tag/PR release.
- **semantic-release**: full automation trong CI — quyết định version, changelog, tag, publish npm, tạo GitHub Release, tất cả từ commit.
- **git-cliff** (Rust): sinh changelog linh hoạt, template hóa.

### Ghi chú
> Keep a Changelog, `[Unreleased]`, semantic-release, release-please, git-cliff

---

## 5. Real-world – Luồng version hóa tự động end-to-end

```
Dev commit theo Conventional Commits
        │  (commit-msg hook: commitlint kiểm tra)
        ▼
PR merge vào main (squash, giữ message chuẩn)
        ▼
CI (semantic-release / release-please) chạy trên main:
   1. Đọc commit kể từ tag gần nhất
   2. feat→MINOR, fix→PATCH, BREAKING→MAJOR  ⇒ version mới X.Y.Z
   3. Sinh/CHANGELOG.md
   4. git tag -a vX.Y.Z + push
   5. Tạo GitHub/GitLab Release (kèm changelog)
   6. (tùy) publish artifact: npm/Maven/Docker image tag vX.Y.Z
        ▼
Deploy pipeline trigger từ tag vX.Y.Z  → xem release_management.md
```

### Bẫy thường gặp
- Commit message ẩu → auto-version sai, changelog vô nghĩa → **enforce bằng hook + CI**.
- Quên `--tags` khi push → tag không lên remote → CI release không trigger.
- Trộn lẫn có/không tiền tố `v` → tool parse sai.
- Bump MAJOR mà quên vì không đánh dấu `BREAKING CHANGE` → user vỡ mà không cảnh báo.
- Lightweight tag cho release → mất author/date/message.

---

## Ghi chú – Chủ đề tiếp theo
> Dùng version/tag này để cắt release, deploy, hotfix, rollback trong quy trình thực tế → `release_management.md`
