# Team Collaboration – Pull Request, Code Review & Hợp Nhất Trong Nhóm

> Deep dive cho topic 6-7 của `git_knowledge.md`. Trọng tâm: quy trình cộng tác qua PR/MR, merge vs rebase thực chiến, giải conflict, bảo vệ nhánh.

---

## 1. Pull Request / Merge Request (PR/MR)

### What
**PR (GitHub/Bitbucket) = MR (GitLab)** là đề xuất hợp nhất code từ nhánh nguồn vào nhánh đích, kèm nơi để **review, thảo luận, chạy CI** trước khi merge.

### How – Vòng đời PR
```
1. Tạo feature branch từ main       → git switch -c feature/JIRA-123
2. Commit + push                     → git push -u origin feature/JIRA-123
3. Mở PR (draft nếu chưa xong)       → base: main ← compare: feature/JIRA-123
4. CI chạy tự động (build/test/lint) → phải xanh
5. Reviewer comment → tác giả sửa    → push thêm commit
6. Approve (đủ số lượng yêu cầu)
7. Merge (merge commit / squash / rebase)
8. Xóa nhánh nguồn
```

### Why
- **Cổng chất lượng**: không code nào vào `main` mà chưa qua review + CI.
- **Chia sẻ tri thức**: reviewer học code, phát hiện lỗi sớm, giữ chuẩn chung.
- **Truy vết**: PR gắn với issue/ticket → lịch sử "tại sao thay đổi".

### Components – PR tốt gồm
| Thành phần | Ghi chú |
|-----------|---------|
| Title rõ | Theo Conventional Commits: `feat: add VNPay payment` |
| Description | Vấn đề gì, giải pháp gì, cách test, link issue |
| Nhỏ & tập trung | < 400 dòng thay đổi → review kỹ hơn nhiều |
| CI xanh | Build/test/lint pass |
| Reviewer + CODEOWNERS | Người có ngữ cảnh review |
| Screenshots/demo | Với thay đổi UI |

### Real-world – PR nhỏ
> "Một PR nên làm **một việc**." PR khổng lồ 3000 dòng → reviewer bấm Approve cho xong (rubber-stamp) → lỗi lọt. Tách nhỏ, review sâu.

---

## 2. Ba kiểu Merge PR (rất quan trọng cho lịch sử)

### How – Hoạt động
```
Trước:  main A─B          feature C─D (2 commit)

1) Merge commit (--no-ff):
   main A─B──────M     ← M có 2 parent, giữ nguyên C,D
              \  /
   feature     C─D

2) Squash merge:
   main A─B─S          ← S = gộp C+D thành 1 commit sạch trên main

3) Rebase merge:
   main A─B─C'─D'      ← C,D replay tuyến tính, không merge commit
```

### Compare
| Kiểu | Lịch sử `main` | Khi nào dùng |
|------|----------------|--------------|
| **Merge commit** | Có merge commit, thấy nhóm PR | Muốn giữ ngữ cảnh nhánh, Git Flow |
| **Squash** | 1 commit / PR, rất sạch | Feature branch nhiều commit "wip", muốn `main` gọn (phổ biến nhất cho web) |
| **Rebase** | Tuyến tính, không merge commit | Muốn lịch sử phẳng nhưng giữ từng commit |

### Trade-offs
- **Squash**: (+) `main` sạch, mỗi PR = 1 dòng log, dễ revert nguyên PR. (−) mất lịch sử commit chi tiết bên trong PR.
- **Merge commit**: (+) giữ đủ ngữ cảnh. (−) log rối nếu nhiều nhánh nhỏ.
- **Rebase merge**: (+) phẳng + giữ commit. (−) mất dấu "đây là 1 PR".

---

## 3. Merge vs Rebase – thực chiến

### How – Cập nhật feature branch với main mới

**Cách 1 – Merge main vào feature** (an toàn, giữ lịch sử thật):
```bash
git switch feature/x
git fetch origin
git merge origin/main        # tạo merge commit trong feature
```

**Cách 2 – Rebase feature lên main** (phẳng, dọn trước khi tạo PR):
```bash
git switch feature/x
git fetch origin
git rebase origin/main       # replay commit của feature lên đầu main
# nếu đã push trước đó:
git push --force-with-lease  # bắt buộc, nhưng dùng bản an toàn
```

### Interactive Rebase – dọn lịch sử trước khi PR
```bash
git rebase -i HEAD~4
```
```
pick   a1b2c3 feat: add payment service
squash d4e5f6 fix typo            ← gộp vào commit trên
squash 7g8h9i wip                 ← gộp tiếp
reword j0k1l2 add tests           ← sửa message
# lệnh: pick / reword / edit / squash / fixup / drop / reorder
```
→ Biến 4 commit lộn xộn thành 1-2 commit sạch, ý nghĩa.

### Quy tắc vàng
> **Không rebase / force-push nhánh mà người khác đang cùng làm.** Rebase viết lại hash → đồng đội bị lệch lịch sử. Chỉ rebase nhánh **của riêng bạn, chưa chia sẻ** (hoặc đã thống nhất).

### When
- Rebase: dọn nhánh cá nhân, đồng bộ với `main`, giữ lịch sử phẳng.
- Merge: tích hợp vào nhánh chung, nhánh có nhiều người.

---

## 4. Giải quyết Conflict (xung đột)

### What
Conflict xảy ra khi hai nhánh sửa **cùng vùng** một file, Git không tự quyết được giữ bản nào.

### How – Quy trình giải
```bash
git merge origin/main            # (hoặc rebase) → báo CONFLICT
git status                       # xem file nào conflict
```
File conflict trông như:
```
<<<<<<< HEAD (nhánh hiện tại)
int timeout = 30;
=======
int timeout = 60;
>>>>>>> origin/main (nhánh đưa vào)
```
```bash
# Sửa tay: chọn/gộp code, xóa marker <<< === >>>
git add <file>                   # đánh dấu đã giải
git merge --continue             # (hoặc git rebase --continue)
# muốn hủy giữa chừng:
git merge --abort                # (hoặc git rebase --abort)
```

### Real-world – Giảm đau conflict
- **Nhánh ngắn + sync `main` thường xuyên** → conflict nhỏ, dễ giải.
- `git config rerere.enabled true` → Git **nhớ** cách bạn giải conflict giống nhau, tự áp dụng lại.
- Dùng merge tool: `git mergetool` (VS Code, Beyond Compare, KDiff3).
- Conflict trong file generated (lock file) → thường regenerate thay vì sửa tay.

### Trade-offs
- Rebase: conflict có thể xuất hiện **từng commit** (giải nhiều lần) nhưng kết quả phẳng.
- Merge: giải conflict **một lần** nhưng có merge commit.

---

## 5. Protected Branches & Quy tắc merge

### What
Cấu hình trên GitHub/GitLab bảo vệ nhánh quan trọng (`main`, `release/*`) khỏi thay đổi trực tiếp/nguy hiểm.

### Components – Rule nên bật
| Rule | Tác dụng |
|------|----------|
| Require PR before merge | Cấm push thẳng vào `main` |
| Require N approvals | Bắt buộc ≥1-2 người approve |
| Require status checks | CI phải xanh mới merge được |
| Require branches up to date | Phải rebase/merge `main` mới nhất trước merge |
| Require conversation resolution | Mọi comment phải được giải quyết |
| Require signed commits | Commit phải ký GPG/SSH |
| Restrict force push / deletion | Cấm force-push, cấm xóa nhánh |
| Require linear history | Chỉ cho squash/rebase (không merge commit) |

### CODEOWNERS
```
# .github/CODEOWNERS
/src/payment/**   @team-payment @alice
/infra/**         @devops-team
*.sql             @dba-team
```
→ PR đụng file nào **tự gán** owner tương ứng làm reviewer bắt buộc.

### Why
Ngăn sự cố do push nhầm, ép chuẩn review + CI, đảm bảo người có chuyên môn duyệt vùng code họ phụ trách.

---

## 6. Commit hygiene – Chất lượng commit

### How – Commit tốt
- **Atomic**: một commit làm một việc logic (không trộn refactor + feature + fix).
- **Message rõ** theo Conventional Commits (chi tiết ở `../versioning/semantic_versioning.md`):
  ```
  feat(auth): thêm đăng nhập bằng Google OAuth

  - Tích hợp Google OAuth2 client
  - Thêm bảng oauth_account

  Closes #123
  ```
- **Không commit rác**: file build, secret, code comment-out.
- **Chạy được**: mỗi commit nên build/test pass (quan trọng cho `git bisect`).

### Why
Lịch sử sạch giúp review nhanh, `git blame`/`bisect` hiệu quả, revert chính xác, auto-changelog đúng.

---

## 7. Real-world – Quy trình cộng tác mẫu (chuẩn công nghiệp)

```
┌─ Dev A ─────────────────────────────────────────────┐
│ git switch -c feature/JIRA-42-search                 │
│ ...code...  (pre-commit hook: lint+test+quét secret) │
│ git push -u origin feature/JIRA-42-search            │
│ → Mở PR (title Conventional, mô tả, link ticket)     │
└──────────────────────┬───────────────────────────────┘
                       ▼
      CI: build + unit/integration test + lint + SAST
                       ▼
      Reviewer (CODEOWNERS) review → comment → sửa
                       ▼
      Approve ≥1  +  CI xanh  +  branch up-to-date
                       ▼
      Squash merge vào main  →  xóa nhánh
                       ▼
      main deploy staging (tự động) → verify → tag release
```

### Bẫy thường gặp
- PR quá lớn → review hời hợt.
- Force-push nhánh chung → đồng đội mất commit.
- Merge `main` chưa cập nhật → CI xanh giả, hỏng sau merge (bật "require up to date").
- Nhánh sống hàng tuần → conflict khổng lồ.
- Commit gộp nhiều việc → khó revert đúng phần lỗi.

---

## Ghi chú – Chủ đề tiếp theo
> Đánh số version cho commit đã merge (SemVer), Conventional Commits → auto changelog → `../versioning/semantic_versioning.md`
> Cắt release, hotfix, rollback từ nhánh chính → `../versioning/release_management.md`
