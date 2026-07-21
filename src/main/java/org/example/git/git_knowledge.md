# Tổng Hợp Kiến Thức Git – Quy Trình Dự Án & Quản Lý Version Release

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> Trọng tâm package này: **Git trong quy trình dự án thực tế** và **quản lý version khi release sản phẩm**. Phần deep dive nằm ở `workflow/` và `versioning/`.

---

## 1. Git Overview

### What – Git là gì?
**Git** là hệ thống **quản lý phiên bản phân tán (Distributed Version Control System – DVCS)** mã nguồn mở, do Linus Torvalds tạo ra năm 2005 cho kernel Linux. Git theo dõi mọi thay đổi của mã nguồn theo thời gian, cho phép nhiều người cùng làm việc song song và hợp nhất công việc một cách an toàn.

### How – Đặc điểm
- **Distributed**: Mỗi developer có **full copy** của repo (bao gồm toàn bộ lịch sử), không phụ thuộc server trung tâm để commit/xem lịch sử.
- **Snapshot, không phải diff**: Mỗi commit là một **snapshot** toàn bộ cây thư mục (thực chất reference tới file không đổi + file mới), không lưu delta như SVN.
- **Content-addressable**: Mọi object được định danh bằng **SHA-1/SHA-256 hash** của nội dung → tính toàn vẹn (integrity) tuyệt đối.
- **Cheap branching**: Branch chỉ là một con trỏ (pointer) 40 ký tự tới một commit → tạo/xóa branch tức thời.
- **Offline-first**: Commit, branch, merge, xem log đều làm được offline.
- **Immutable history**: Commit không sửa được; "sửa" thực chất tạo commit mới (rebase/amend thay đổi hash).

### How – Hoạt động (3 khu vực + object model)

```
 Working Directory      Staging Area (Index)        Local Repo (.git)         Remote
 ┌──────────────┐  add   ┌──────────────┐  commit   ┌──────────────┐  push   ┌──────────┐
 │ file đã sửa   │ ─────▶ │  snapshot     │ ────────▶ │  commit tree  │ ──────▶ │  origin   │
 │ (untracked/   │        │  chuẩn bị     │           │  (DAG)        │ ◀────── │           │
 │  modified)    │ ◀───── │              │ ◀──────── │              │  fetch  │           │
 └──────────────┘ checkout└──────────────┘  reset    └──────────────┘         └──────────┘
```

**Git Object Model** (nằm trong `.git/objects/`):
```
commit ──▶ tree ──▶ blob (nội dung file)
   │         └────▶ tree (thư mục con) ──▶ blob
   └─ parent ──▶ commit (trước đó)   ← tạo thành DAG (Directed Acyclic Graph)
```

| Object | Vai trò |
|--------|---------|
| **blob** | Nội dung 1 file (không có tên file) |
| **tree** | Thư mục: ánh xạ tên → blob/tree + mode |
| **commit** | Snapshot: trỏ tới 1 tree gốc + parent(s) + author/committer + message |
| **tag** | Con trỏ có tên tới 1 commit (annotated tag còn có message + signer) |

- **Branch** = file text chứa hash commit (`.git/refs/heads/main`).
- **HEAD** = con trỏ tới branch hiện tại (`.git/HEAD` → `ref: refs/heads/main`).

### Why – Tại sao cần Git?
- **Cộng tác nhóm**: Nhiều dev làm song song trên cùng codebase mà không đè lên nhau.
- **Lịch sử & truy vết**: Ai đổi gì, khi nào, tại sao (`git blame`, `git log`) → điều tra bug, audit.
- **An toàn thử nghiệm**: Tạo branch thử tính năng, hỏng thì bỏ, không ảnh hưởng code chính.
- **Rollback**: Quay lại version ổn định khi release lỗi.
- **Nền tảng CI/CD & DevOps**: Mọi pipeline hiện đại trigger từ Git event (push/PR/tag).

### Components – Thành phần chính
| Thành phần | Vai trò |
|-----------|---------|
| **Working Directory** | Thư mục làm việc thực tế, nơi bạn sửa file |
| **Staging Area (Index)** | Vùng đệm chuẩn bị nội dung cho commit tiếp theo |
| **Local Repository** (`.git`) | Toàn bộ object, ref, config, history trên máy |
| **Remote** (origin) | Repo trên server chia sẻ (GitHub/GitLab/Bitbucket) |
| **Commit** | Snapshot bất biến của toàn bộ project tại một thời điểm |
| **Branch** | Con trỏ di động tới một dòng phát triển |
| **Tag** | Nhãn cố định đánh dấu một version (vd `v1.4.0`) |
| **HEAD** | Con trỏ tới vị trí hiện tại (branch hoặc commit) |
| **Remote-tracking branch** | Bản sao trạng thái remote local biết (`origin/main`) |

### When – Khi nào dùng?
- **Luôn luôn** cho mọi dự án phần mềm (kể cả solo) – nên `git init` ngay từ đầu.
- Quản lý infra-as-code, tài liệu, cấu hình, notebook – bất cứ thứ gì dạng text.
- Không phù hợp làm kho chính cho **file nhị phân lớn** (video, dataset GB) → dùng Git LFS hoặc artifact repo (Nexus/Artifactory/S3).

### Compare – Git vs SVN vs Mercurial
| | Git | SVN (Subversion) | Mercurial |
|--|-----|------------------|-----------|
| Mô hình | Phân tán (DVCS) | Tập trung (CVCS) | Phân tán |
| Lịch sử offline | Có (full) | Không (cần server) | Có |
| Branching | Rất rẻ, phổ biến | Nặng, ít dùng | Rẻ |
| Tốc độ | Nhanh | Chậm hơn với repo lớn | Nhanh |
| Đường cong học | Dốc (nhiều khái niệm) | Thoải | Thoải hơn Git |
| Phổ biến | Thống trị (~90%+) | Legacy, doanh nghiệp cũ | Ít dần |

### Trade-offs
- (+) Phân tán, nhanh, branching rẻ, ecosystem khổng lồ (GitHub/GitLab, CI/CD).
- (+) Toàn vẹn dữ liệu qua hashing, khó mất lịch sử.
- (−) Đường cong học dốc: rebase, reset, reflog, detached HEAD dễ gây hoảng loạn.
- (−) Kém với binary lớn & monorepo cực lớn (cần Git LFS, sparse-checkout, partial clone).
- (−) Lịch sử viết lại (force push) nguy hiểm nếu làm trên shared branch.

### Real-world Usage
- **Feature branch → Pull Request → Review → CI → Merge → Deploy**: quy trình chuẩn của hầu hết team.
- **Tag `v1.2.3` → CI build artifact → push registry → deploy**: nền tảng release.
- **Hotfix branch** từ tag production để vá lỗi khẩn cấp.
- **`git bisect`** tìm commit gây bug qua binary search trên lịch sử.

### Ghi chú – Chủ đề tiếp theo
> Git Internals (object model, packfile) · Branching strategies · Merge vs Rebase · Semantic Versioning · Release management

---

## 2. Git Internals – Cơ chế lưu trữ

### What
Cách Git thực sự lưu dữ liệu bên trong thư mục `.git/`.

### How – Hoạt động
```
.git/
├── HEAD               ← ref: refs/heads/main
├── config             ← config repo (remote, user...)
├── index              ← staging area (binary)
├── objects/           ← toàn bộ blob/tree/commit/tag (nén zlib)
│   ├── ab/cd1234...   ← object theo 2 ký tự đầu của hash
│   └── pack/          ← packfile (nhiều object nén delta lại)
└── refs/
    ├── heads/         ← local branches
    ├── tags/          ← tags
    └── remotes/       ← remote-tracking branches
```

- Mỗi object: `<type> <size>\0<content>` → nén zlib → hash SHA-1 → lưu theo hash.
- **Packfile**: gom nhiều object, dùng **delta compression** để tiết kiệm (chạy khi `git gc` / push/fetch).
- **Loose object** → chạy `git gc` gói lại thành pack.

### Why
Hiểu internals giúp bạn không sợ Git: mọi thao tác đều là di chuyển con trỏ + tạo object. `reflog` ghi lại mọi lần HEAD thay đổi → gần như luôn khôi phục được commit "mất".

### Ghi chú
> `git cat-file -p <hash>`, `git reflog`, `git fsck`, packfile, garbage collection

---

## 3. Cấu hình & Khởi tạo (Config)

### What – How
```bash
# Định danh (bắt buộc trước khi commit)
git config --global user.name  "Nguyen Van A"
git config --global user.email "a@company.com"

# Chất lượng cuộc sống
git config --global init.defaultBranch main       # nhánh mặc định là main
git config --global pull.rebase true               # pull = fetch + rebase (lịch sử phẳng)
git config --global core.autocrlf input            # chuẩn hóa line-ending (Windows: true)
git config --global rerere.enabled true            # nhớ cách giải conflict đã làm
git config --global fetch.prune true               # tự xóa remote branch đã bị xóa
```
- **Thứ tự ưu tiên config**: `local` (repo) > `global` (user) > `system`.
- **`.gitignore`**: liệt kê file/thư mục không track (build output, `node_modules/`, `.env`, `target/`).
- **`.gitattributes`**: quy tắc per-file (line-ending, diff cho binary, Git LFS, `export-ignore`).

### Why
Config đúng ngay từ đầu tránh commit rác (file build, secret), tránh war line-ending giữa Windows/Linux, và tự động hóa các thao tác lặp lại.

### Ghi chú
> `.gitignore`, `.gitattributes`, Git LFS, `pull.rebase`, `rerere`

---

## 4. Vòng đời cơ bản (Everyday Workflow)

### How – Lệnh hằng ngày
```bash
git status                     # trạng thái working dir + staging
git add <file> / git add -p    # stage (-p: chọn từng hunk)
git commit -m "feat: ..."      # tạo snapshot
git log --oneline --graph --all  # xem lịch sử dạng đồ thị
git diff / git diff --staged   # xem thay đổi (chưa stage / đã stage)
git restore <file>             # bỏ thay đổi working dir (Git 2.23+)
git restore --staged <file>    # bỏ stage (unstage)
```

### Real-world – Undo cheat sheet (rất hay dùng)
| Tình huống | Lệnh |
|-----------|------|
| Bỏ sửa file chưa stage | `git restore <file>` |
| Unstage file đã add | `git restore --staged <file>` |
| Sửa message commit vừa rồi | `git commit --amend` |
| Thêm file quên vào commit trước | `git add x && git commit --amend --no-edit` |
| Hủy commit cuối, **giữ** thay đổi | `git reset --soft HEAD~1` |
| Hủy commit cuối, **bỏ** thay đổi | `git reset --hard HEAD~1` ⚠️ |
| Đảo ngược 1 commit đã push (an toàn) | `git revert <hash>` |
| Khôi phục commit "mất" | `git reflog` → `git reset --hard <hash>` |
| Cất tạm việc dang dở | `git stash` → `git stash pop` |

### Ghi chú
> `reset --soft/--mixed/--hard`, `revert`, `stash`, `reflog`, `restore` vs `checkout`

---

## 5. Branching – Nhánh (khái niệm cốt lõi cho quy trình)

### What
Branch là một **dòng phát triển độc lập** – con trỏ di động tới commit. `main`/`master` là nhánh mặc định.

### How
```bash
git branch feature/login          # tạo nhánh
git switch feature/login          # chuyển sang (Git 2.23+, thay cho checkout)
git switch -c feature/login       # tạo + chuyển
git branch -d feature/login       # xóa (đã merge)
git branch -D feature/login       # xóa cưỡng bức
git push -u origin feature/login  # đẩy lên & set upstream
```

### Why
Cô lập công việc: mỗi tính năng/bugfix có nhánh riêng → `main` luôn ổn định, review dễ, rollback gọn.

### Compare – Naming convention (quan ước đặt tên nhánh)
```
feature/JIRA-123-user-login     ← tính năng mới
bugfix/JIRA-456-null-pointer    ← sửa lỗi trong quá trình dev
hotfix/1.4.1-payment-crash      ← vá khẩn production
release/1.5.0                   ← chuẩn bị release
chore/upgrade-spring-boot-3     ← việc phụ trợ (deps, config)
```

### Ghi chú
> **→ Chi tiết chiến lược nhánh (Git Flow, GitHub Flow, GitLab Flow, Trunk-based): `workflow/branching_strategies.md`**

---

## 6. Merge vs Rebase (hợp nhất công việc)

### What
Hai cách tích hợp thay đổi từ nhánh này sang nhánh khác.

### How – Hoạt động
```
Merge (giữ lịch sử thật, tạo merge commit):
  main    A───B───────M
                 \   /
  feature         C─D

Rebase (viết lại, lịch sử phẳng, C-D thành C'-D'):
  main    A───B───C'───D'
```

| | Merge | Rebase |
|--|-------|--------|
| Lịch sử | Giữ nguyên, có merge commit | Phẳng, tuyến tính |
| An toàn shared branch | ✅ An toàn | ❌ Không rebase nhánh đã push chung |
| Truy vết ngữ cảnh | Rõ (thấy nhánh gộp khi nào) | Mất ngữ cảnh nhánh |
| Conflict | Giải 1 lần | Có thể giải nhiều lần (từng commit) |

**Quy tắc vàng (Golden Rule of Rebase):** *Không bao giờ rebase commit đã được đẩy lên nhánh chia sẻ mà người khác đang dùng.*

### When
- **Rebase** để cập nhật feature branch với `main` mới nhất → gọn trước khi tạo PR.
- **Merge** (thường `--no-ff`) để đưa feature vào `main`/`develop` → giữ dấu vết nhóm commit.
- **Squash merge** khi muốn mỗi PR = 1 commit sạch trên `main`.

### Ghi chú
> **→ Chi tiết + interactive rebase, cherry-pick, conflict, code review: `workflow/team_collaboration.md`**

---

## 7. Remote & Cộng tác

### How
```bash
git remote -v                      # xem remote
git clone <url>                    # sao chép repo
git fetch origin                   # tải cập nhật (KHÔNG merge)
git pull                           # fetch + merge/rebase vào nhánh hiện tại
git push                           # đẩy commit local lên remote
git push --force-with-lease        # force push AN TOÀN (không đè việc người khác)
```

### Compare – `fetch` vs `pull`
- `fetch`: chỉ tải object + cập nhật `origin/*`, không đụng nhánh local → **an toàn, kiểm soát được**.
- `pull` = `fetch` + `merge` (hoặc `rebase`) → tiện nhưng dễ tạo merge commit ngoài ý muốn.

### Trade-offs – `--force` vs `--force-with-lease`
- `--force`: đè thẳng, có thể xóa commit người khác vừa push → **nguy hiểm**.
- `--force-with-lease`: chỉ đè nếu remote đúng như bạn biết → **luôn ưu tiên cái này**.

### Ghi chú
> `origin`, `upstream` (fork), `push -u`, `--force-with-lease`, protected branches

---

## 8. Tag & Version (nền tảng quản lý release)

### What
**Tag** đánh dấu cố định một commit là một version phát hành (vd `v2.3.1`).

### How
```bash
# Annotated tag (KHUYÊN DÙNG cho release – có message, author, ngày)
git tag -a v1.4.0 -m "Release 1.4.0: thêm thanh toán VNPay"
git push origin v1.4.0             # đẩy 1 tag
git push origin --tags             # đẩy tất cả tag

git tag                            # liệt kê
git tag -a v1.4.1 <hash>           # tag một commit cũ
git checkout v1.4.0                # xem code tại version đó (detached HEAD)
```

### Compare – Lightweight vs Annotated tag
| | Lightweight | Annotated |
|--|-------------|-----------|
| Bản chất | Con trỏ đơn thuần | Object đầy đủ (author, date, message, GPG sign) |
| Dùng cho | Đánh dấu tạm cá nhân | **Release chính thức** |

### Why
Tag = điểm neo bất biến để: build artifact, tạo GitHub Release, rollback, và truy "version này gồm những commit nào".

### Ghi chú
> **→ Chi tiết SemVer, changelog, tag trong CI/CD: `versioning/semantic_versioning.md`**

---

## 9. Quản lý phiên bản & Release (trọng tâm)

### What
Quy trình biến code trên nhánh thành **sản phẩm có version rõ ràng, có thể triển khai và truy vết**.

### How – Chuỗi giá trị release điển hình
```
Commit (Conventional) → Version bump (SemVer) → Tag vX.Y.Z → CHANGELOG
        → CI build artifact → GitHub/GitLab Release → Deploy (staging→prod)
        → (nếu lỗi) Hotfix / Rollback về tag trước
```

### Components
| Thành phần | Vai trò |
|-----------|---------|
| **SemVer** (`MAJOR.MINOR.PATCH`) | Quy tắc đánh số version có ý nghĩa |
| **Conventional Commits** | Chuẩn message → tự sinh version + changelog |
| **CHANGELOG.md** | Nhật ký thay đổi cho người dùng/dev |
| **Git tag** | Neo version vào commit cụ thể |
| **Release branch / trunk** | Chiến lược ổn định hóa trước phát hành |
| **CI/CD** | Tự động build, test, tag, deploy |
| **Rollback / Hotfix** | Phục hồi khi release lỗi |

### Why
- Khách hàng/đội vận hành biết **cái gì thay đổi** và **có breaking change không**.
- Truy vết: "prod đang chạy version nào? gồm commit nào? deploy khi nào?"
- Tự động hóa: version + changelog + deploy sinh ra từ commit, giảm lỗi thủ công.

### Ghi chú
> **→ Chi tiết quy trình release, hotfix, rollback, CI/CD automation: `versioning/release_management.md`**

---

## 10. Bảo mật & Toàn vẹn trong dự án thực tế

### How – Real-world
- **Signed commits/tags (GPG/SSH)**: chứng minh danh tính tác giả → yêu cầu ở nhiều team enterprise.
  ```bash
  git config --global commit.gpgsign true
  git tag -s v1.4.0 -m "signed release"
  ```
- **Không commit secret**: dùng `.gitignore` cho `.env`, quét bằng `gitleaks`/`trufflehog` trong CI, dùng **pre-commit hook**.
- **Xóa secret đã lỡ commit**: `git filter-repo` (thay cho `filter-branch`) hoặc BFG Repo-Cleaner → **và phải rotate secret ngay** (lịch sử có thể đã bị clone).
- **Protected branches**: cấm push thẳng vào `main`, bắt buộc PR + review + CI xanh.
- **CODEOWNERS**: tự gán reviewer theo đường dẫn file.

### Ghi chú
> `gitleaks`, `git filter-repo`, BFG, signed commits, branch protection, CODEOWNERS, `pre-commit` hooks

---

## 11. Công cụ điều tra & khôi phục (Debugging with Git)

### How
| Lệnh | Dùng để |
|------|---------|
| `git blame <file>` | Dòng này ai sửa, commit nào, khi nào |
| `git log -S"chuỗi"` | Tìm commit thêm/xóa một chuỗi code (pickaxe) |
| `git bisect` | Binary search tìm commit gây bug |
| `git reflog` | Lịch sử di chuyển HEAD → cứu commit "mất" |
| `git cherry-pick <hash>` | Lấy 1 commit cụ thể sang nhánh khác (vd port hotfix) |
| `git show <hash>` | Xem chi tiết 1 commit |

### Real-world – `git bisect`
```bash
git bisect start
git bisect bad                 # commit hiện tại có bug
git bisect good v1.3.0         # version này còn tốt
# Git tự checkout commit giữa → bạn test → good/bad → lặp lại
git bisect reset               # kết thúc
```
Tìm commit lỗi trong ~log₂(N) bước thay vì dò tuyến tính.

### Ghi chú
> `blame`, `bisect`, pickaxe `-S`/`-G`, `reflog`, `cherry-pick`

---

## 12. Git Hooks & Tự động hóa

### What
Script chạy tự động tại các thời điểm trong vòng đời Git (`.git/hooks/` hoặc quản lý bằng **Husky**/**pre-commit**).

### How – Hook hay dùng
| Hook | Thời điểm | Dùng cho |
|------|-----------|----------|
| `pre-commit` | Trước khi commit | Lint, format, quét secret, chạy unit test nhanh |
| `commit-msg` | Sau khi nhập message | Kiểm tra format Conventional Commits |
| `pre-push` | Trước khi push | Chạy test suite, chặn push nhánh cấm |
| `post-merge` | Sau merge | Cài lại dependency (vd `npm install`) |

### Why
Ép chuẩn chất lượng **trước** khi code vào repo → giảm CI đỏ, giữ lịch sử sạch, chặn secret sớm.

### Real-world
- **Husky + lint-staged** (JS/TS): chỉ lint file staged.
- **pre-commit framework** (Python & đa ngôn ngữ): quản lý hook khai báo trong `.pre-commit-config.yaml`.
- **commitlint**: enforce Conventional Commits.

### Ghi chú
> Husky, lint-staged, pre-commit framework, commitlint, server-side hooks

---

## Tổng kết mối liên hệ

```
Nền tảng Git (1-4)  →  Nhánh & hợp nhất (5-7)  →  Version & Release (8-9)
      │                        │                          │
   Internals              branching_strategies      semantic_versioning
   Config/Undo            team_collaboration        release_management
      │                        │                          │
      └─────── Bảo mật, Debug, Hooks (10-12) xuyên suốt mọi giai đoạn ──────┘
```

Đọc tiếp theo thứ tự: `workflow/branching_strategies.md` → `workflow/team_collaboration.md` → `versioning/semantic_versioning.md` → `versioning/release_management.md`.
