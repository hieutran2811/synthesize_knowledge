# Branching Strategies – Chiến Lược Nhánh Trong Dự Án Thực Tế

> Deep dive cho topic 5 của `git_knowledge.md`. Trọng tâm: chọn & vận hành chiến lược nhánh phù hợp với quy trình release của team.

---

## 1. Tổng quan – Vì sao cần chiến lược nhánh?

### What
**Branching strategy** (branching model) là **bộ quy ước** về: những loại nhánh tồn tại, vai trò mỗi nhánh, cách code đi từ nhánh dev → nhánh production, và cách release được cắt ra.

### Why – Không có chiến lược thì sao?
- Nhánh `main` không ổn định → không dám deploy bất cứ lúc nào.
- Không rõ code nào đã lên prod, code nào đang thử nghiệm.
- Merge hỗn loạn, conflict triền miên, release lỗi khó rollback.

### How – 4 mô hình phổ biến (từ nặng → nhẹ)
| Mô hình | Độ phức tạp | Phù hợp | Release cadence |
|---------|-------------|---------|-----------------|
| **Git Flow** | Cao | Sản phẩm có version, nhiều môi trường, release theo lịch | Định kỳ (weeks/months) |
| **GitHub Flow** | Thấp | Web app / SaaS deploy liên tục | Liên tục (khi merge) |
| **GitLab Flow** | Trung bình | Cần môi trường staging/prod rõ ràng | Theo môi trường |
| **Trunk-Based** | Thấp (kỷ luật cao) | Team CI/CD trưởng thành, deploy nhiều lần/ngày | Rất liên tục |

---

## 2. Git Flow (Vincent Driessen, 2010)

### What
Mô hình **hai nhánh dài hạn** + ba loại nhánh tạm, thiết kế cho sản phẩm phát hành theo version.

### Components – Các nhánh
| Nhánh | Loại | Vai trò |
|-------|------|---------|
| `main` (`master`) | Dài hạn | Chỉ chứa code **đã release**, mỗi commit ~ 1 tag version |
| `develop` | Dài hạn | Tích hợp mọi tính năng cho lần release tiếp theo |
| `feature/*` | Tạm | Phát triển tính năng, nhánh ra từ `develop`, merge lại `develop` |
| `release/*` | Tạm | Ổn định hóa trước phát hành (fix bug, bump version), từ `develop` |
| `hotfix/*` | Tạm | Vá lỗi khẩn production, nhánh ra từ `main` |

### How – Luồng hoạt động
```
feature/x ──┐
feature/y ──┼──▶ develop ──▶ release/1.5.0 ──▶ main (tag v1.5.0)
            │                     │                 │
            └──◀── merge back ────┴─────────────────┤
                                                    │
                        hotfix/1.5.1 ──▶ main (tag v1.5.1)
                                          └──▶ develop (merge ngược)
```
1. Dev tạo `feature/*` từ `develop`, xong merge về `develop`.
2. Đến kỳ release: cắt `release/1.5.0` từ `develop` → chỉ fix bug + bump version.
3. Release xong: merge `release/1.5.0` vào `main` (tag `v1.5.0`) **và** merge ngược về `develop`.
4. Lỗi prod: `hotfix/1.5.1` từ `main` → vá → merge vào `main` (tag) **và** `develop`.

### When
- Sản phẩm cài đặt tại khách (desktop, mobile app, on-premise) có **nhiều version song song**.
- Team có QA riêng, release theo sprint/lịch, cần giai đoạn "code freeze".

### Trade-offs
- (+) Rõ ràng, tách biệt dev/release/hotfix, hỗ trợ nhiều version cùng lúc.
- (+) `main` luôn = production, dễ audit.
- (−) **Nặng, nhiều bước merge** → không hợp deploy liên tục.
- (−) `develop` và feature branch sống lâu → conflict lớn, "merge hell".
- (−) Nhiều team hiện đại cho là **overkill** với web/SaaS.

---

## 3. GitHub Flow

### What
Mô hình **cực đơn giản, một nhánh dài hạn** (`main`) + feature branch ngắn, deploy ngay khi merge.

### How
```
main ─────●──────────●──────────●───────▶ (luôn deployable)
           \        / \        /
   feature/a●──────●   feature/b●──────●
            PR + CI + review        PR + CI + review
```
1. `main` **luôn deployable**.
2. Tạo branch mô tả rõ (`feature/add-search`).
3. Commit, push, mở **Pull Request** sớm để thảo luận.
4. CI chạy + review; merge vào `main` khi xanh.
5. **Deploy `main` ngay** (thường tự động).

### When
- Web app / SaaS / microservice deploy **liên tục**.
- Team dùng feature flag để ẩn tính năng chưa xong thay vì giữ nhánh dài.

### Trade-offs
- (+) Đơn giản, nhanh, ít merge, khuyến khích PR nhỏ.
- (+) Hợp CI/CD, continuous deployment.
- (−) Không có khái niệm "version phát hành" rõ → cần bổ sung tag riêng.
- (−) Khó hỗ trợ nhiều version production song song.
- (−) Yêu cầu test tự động tốt + feature flag để `main` luôn ổn định.

---

## 4. GitLab Flow

### What
Trung gian giữa Git Flow và GitHub Flow: thêm **nhánh môi trường** (environment branches) hoặc **nhánh release** vào mô hình đơn giản.

### How – Hai biến thể
**a) Environment branches** (deploy theo môi trường):
```
feature/* ──▶ main ──▶ pre-production ──▶ production
             (merge)     (deploy staging)   (deploy prod)
```
Code **chỉ chảy một chiều** (downstream): `main` → staging → production. Muốn lên prod thì merge từ staging.

**b) Release branches** (sản phẩm có version):
```
main ──▶ 1-5-stable ──(cherry-pick fix)──▶ tag v1.5.x
     ──▶ 2-0-stable ──▶ tag v2.0.x
```
Fix vá vào `main` trước rồi **cherry-pick** xuống nhánh stable (upstream-first) → tránh quên fix ở version mới.

### When
- Cần môi trường staging/pre-prod rõ ràng trước khi lên prod.
- Vừa deploy liên tục vừa cần hỗ trợ vài version cũ.

### Trade-offs
- (+) Linh hoạt, rõ ràng hơn GitHub Flow, nhẹ hơn Git Flow.
- (+) Nguyên tắc **upstream-first** tránh regression.
- (−) Nhiều nhánh môi trường → cần kỷ luật merge một chiều.

---

## 5. Trunk-Based Development (TBD)

### What
Mọi dev commit trực tiếp (qua PR ngắn) vào **một nhánh chính duy nhất** (`trunk`/`main`), nhánh feature sống **< 1-2 ngày**. Chuẩn mực của các team DevOps trưởng thành (theo báo cáo DORA).

### How
```
main ●─●─●─●─●─●─●─●─●─▶  (commit nhỏ, thường xuyên, luôn xanh)
      \_/ \_/ \_/
      branch sống vài giờ → merge ngay
```
- Feature lớn ẩn sau **feature flag**, merge code chưa hoàn thiện nhưng tắt cờ.
- Release cắt bằng **tag** trên `main` hoặc nhánh `release/*` chỉ để hotfix, không phát triển.

### When
- Team có **test tự động mạnh + CI nhanh + feature flag**.
- Muốn đạt continuous integration/deployment thực sự, giảm merge conflict.

### Trade-offs
- (+) Ít conflict nhất, tích hợp liên tục, feedback nhanh, DORA metric cao.
- (+) Không "merge hell", `main` luôn nguồn chân lý.
- (−) Đòi hỏi kỷ luật cao, test coverage tốt, hạ tầng feature flag.
- (−) Commit chưa xong lên `main` (dù tắt cờ) khiến người mới bỡ ngỡ.

---

## 6. Compare – Bảng so sánh tổng hợp

| Tiêu chí | Git Flow | GitHub Flow | GitLab Flow | Trunk-Based |
|----------|----------|-------------|-------------|-------------|
| Số nhánh dài hạn | 2 (`main`+`develop`) | 1 | 1 + môi trường | 1 |
| Tuổi thọ feature branch | Dài | Ngắn | Ngắn | Rất ngắn (<2 ngày) |
| Release | Theo lịch, nhánh release | Liên tục | Theo môi trường/version | Tag trên trunk |
| Nhiều version song song | ✅ Tốt | ❌ Kém | ✅ Được | ⚠️ Qua release branch |
| Yêu cầu feature flag | Không | Nên có | Tùy | **Bắt buộc** |
| Độ phức tạp | Cao | Thấp | Trung bình | Thấp (kỷ luật cao) |
| Hợp CI/CD liên tục | ❌ | ✅ | ✅ | ✅✅ |

---

## 7. Real-world – Chọn chiến lược nào?

### Cây quyết định
```
Sản phẩm cài tại khách / nhiều version cần support cùng lúc?
   └─ Có → Git Flow (hoặc GitLab Flow release branches)

Web/SaaS deploy nhiều lần mỗi ngày, có CI/CD + test mạnh?
   ├─ Cần môi trường staging rõ ràng → GitLab Flow (environment)
   ├─ Team trưởng thành, muốn tối ưu tốc độ → Trunk-Based + feature flags
   └─ Đơn giản, deploy khi merge → GitHub Flow
```

### Gợi ý theo bối cảnh (đúc kết)
- **Startup / team nhỏ / web app**: GitHub Flow — bắt đầu đơn giản, thêm tag version khi cần.
- **Sản phẩm doanh nghiệp on-premise, release theo quý**: Git Flow.
- **Có staging + prod, một sản phẩm SaaS**: GitLab Flow (environment branches).
- **Team lớn, muốn CI/CD tối đa**: Trunk-Based Development + feature flags.

### Bẫy thường gặp
- Áp Git Flow cho web SaaS → merge chậm, phức tạp không cần thiết.
- Trunk-Based mà **không có test tự động** → `main` liên tục hỏng.
- Feature branch sống hàng tuần → conflict khổng lồ (bất kể mô hình nào, giữ nhánh **ngắn**).
- Không bảo vệ nhánh chính → push thẳng gây sự cố (xem `team_collaboration.md`).

---

## Ghi chú – Chủ đề tiếp theo
> Pull/Merge Request, code review, merge vs rebase chi tiết, giải conflict, protected branches → `team_collaboration.md`
> Cách chiến lược nhánh gắn với version & tag → `../versioning/release_management.md`
