# Release Management – Quy Trình Phát Hành, Hotfix & Rollback

> Deep dive cho topic 9 của `git_knowledge.md`. Trọng tâm: biến version (SemVer + tag) thành sản phẩm triển khai được, xử lý sự cố release, tự động hóa bằng CI/CD.

---

## 1. Release là gì & vòng đời

### What
**Release** là quá trình đóng gói một trạng thái code (một commit, đánh dấu bằng **tag version**) thành **artifact triển khai được** (JAR, Docker image, binary...), phát hành ra môi trường (staging → production) một cách **có kiểm soát và truy vết được**.

### How – Vòng đời một release
```
Code freeze / cắt release
      ▼
Version bump (SemVer) + CHANGELOG
      ▼
Tag vX.Y.Z (annotated, signed)
      ▼
CI build artifact bất biến (immutable) từ tag
      ▼
Deploy staging → smoke test / QA / UAT
      ▼
Deploy production (rolling / blue-green / canary)
      ▼
Monitor (metrics, logs, error rate)
      ▼
✅ OK → đóng release   |   ❌ Lỗi → Rollback / Hotfix
```

### Why
- Mọi thứ trên prod phải truy được về **một commit + một version** (audit, compliance).
- Artifact **bất biến**: build một lần từ tag, deploy nhiều môi trường → tránh "khác nhau giữa staging và prod".
- Kiểm soát rủi ro: phát hiện lỗi ở staging trước khi tới user.

### Components
| Thành phần | Vai trò |
|-----------|---------|
| Tag version | Neo bất biến điểm phát hành |
| Artifact repository | Nexus/Artifactory/ECR/GHCR lưu bản build |
| Release notes | Tổng hợp thay đổi (từ CHANGELOG) |
| Deployment strategy | Rolling / blue-green / canary |
| Environments | dev → staging → production |
| Rollback plan | Kế hoạch quay lui khi lỗi |

### Ghi chú
> Immutable artifact, environment promotion, release notes, deployment strategy

---

## 2. Cắt release theo từng chiến lược nhánh

### How – Gắn với branching model (xem `../workflow/branching_strategies.md`)

**Git Flow** – có nhánh release riêng:
```bash
git switch -c release/1.5.0 develop   # cắt từ develop, code freeze
# chỉ fix bug + bump version trên nhánh này
git switch main && git merge --no-ff release/1.5.0
git tag -a v1.5.0 -m "Release 1.5.0"
git switch develop && git merge --no-ff release/1.5.0   # merge ngược
git branch -d release/1.5.0
```

**GitHub Flow / Trunk-Based** – release = tag trên `main`:
```bash
git switch main && git pull
git tag -a v1.5.0 -m "Release 1.5.0"
git push origin v1.5.0        # tag này trigger pipeline release
```

**GitLab Flow** – promote qua nhánh môi trường hoặc tag trên nhánh stable.

### Compare – Release branch vs Tag-only
| | Release branch (Git Flow) | Tag-only (trunk/GitHub Flow) |
|--|---------------------------|------------------------------|
| Giai đoạn ổn định hóa | Có (fix trên release/*) | Không (main luôn deployable) |
| Nhiều version support | Dễ | Khó hơn |
| Tốc độ | Chậm hơn | Nhanh |
| Phù hợp | Release định kỳ | Continuous delivery |

### Ghi chú
> Code freeze, release branch, merge-back, tag-triggered pipeline

---

## 3. Deployment strategies (triển khai an toàn)

### How – Các chiến lược
| Chiến lược | Cách làm | Ưu | Nhược |
|-----------|----------|----|-------|
| **Recreate** | Tắt bản cũ, bật bản mới | Đơn giản | Downtime |
| **Rolling** | Thay dần từng instance | Không downtime | Hai version chạy song song một lúc |
| **Blue-Green** | Bật full môi trường mới (green) → switch traffic | Rollback tức thì (switch lại blue) | Tốn gấp đôi tài nguyên |
| **Canary** | Cho 5% traffic vào bản mới → tăng dần | Giảm rủi ro, phát hiện lỗi sớm | Cần routing + monitoring tinh vi |

```
Blue-Green:            Canary:
[Blue v1.4]◀─100%      [v1.4]◀─95%
[Green v1.5] 0%   →    [v1.5]◀─5%  → 25% → 50% → 100%
     switch traffic         tăng dần khi metric ổn
```

### Why
Tách **deploy** (đưa code lên) khỏi **release** (cho user thấy) → có thể deploy bản mới nhưng bật dần bằng **feature flag**, giảm rủi ro.

### Real-world
- Kubernetes: rolling update mặc định; blue-green/canary qua Argo Rollouts / Flagger / Istio.
- Feature flags (LaunchDarkly, Unleash) tách release logic khỏi deploy.

### Ghi chú
> Rolling, blue-green, canary, feature flag, deploy ≠ release, Argo Rollouts

---

## 4. Hotfix – Vá lỗi khẩn cấp production

### What
**Hotfix** là sửa lỗi nghiêm trọng đang xảy ra trên production, **không đi qua chu kỳ release bình thường**.

### How – Quy trình (Git Flow style)
```bash
# 1. Nhánh hotfix TỪ TAG production đang lỗi (không phải từ develop!)
git switch -c hotfix/1.5.1 v1.5.0

# 2. Sửa lỗi tối thiểu + test
git commit -m "fix: vá crash khi thanh toán null amount"

# 3. Bump PATCH + tag
git switch main && git merge --no-ff hotfix/1.5.1
git tag -a v1.5.1 -m "Hotfix 1.5.1"
git push origin main v1.5.1

# 4. Merge NGƯỢC vào develop/main-dev để không mất fix ở version sau
git switch develop && git merge --no-ff hotfix/1.5.1
```

**Trunk-Based / GitHub Flow**: fix vào `main` → cherry-pick sang nhánh release đang chạy prod (upstream-first, xem GitLab Flow).

### Why – Điểm mấu chốt
- Nhánh hotfix từ **đúng commit đang chạy prod** (tag) → không kéo theo tính năng chưa release.
- **Bắt buộc merge ngược** → tránh lỗi tái xuất ở version tiếp theo (regression).

### Real-world – Cherry-pick port fix
```bash
# Fix đã có trên main, cần đưa xuống nhánh release 1.4 đang support
git switch release/1.4
git cherry-pick <hash-fix>
git tag -a v1.4.5 -m "backport fix"
```

### Ghi chú
> Hotfix branch từ tag, merge-back bắt buộc, cherry-pick backport, upstream-first

---

## 5. Rollback – Quay lui khi release lỗi

### What
Đưa production về trạng thái ổn định trước đó khi bản mới gây sự cố.

### How – Các cấp độ rollback
| Cấp | Cách | Khi nào |
|-----|------|---------|
| **Deploy rollback** | Deploy lại artifact của tag trước (`v1.4.0`) | Nhanh nhất, ưu tiên — không đụng git history |
| **Traffic switch** | Blue-green: chuyển traffic về blue | Tức thì, nếu dùng blue-green |
| **`git revert`** | Tạo commit đảo ngược thay đổi lỗi | Cần loại bỏ code lỗi khỏi lịch sử về sau |
| **DB rollback** | Migration down / restore backup | ⚠️ Cẩn trọng nhất — dữ liệu |

```bash
# Revert an toàn (KHÔNG viết lại lịch sử — hợp nhánh chung)
git revert <hash-commit-loi>
git revert <hash1>..<hash2>        # revert một dải
# Revert nguyên một PR đã squash → chỉ 1 commit để revert (lợi ích của squash)
```

### Compare – `revert` vs `reset`
| | `git revert` | `git reset --hard` |
|--|--------------|--------------------|
| Lịch sử | Giữ, thêm commit đảo ngược | Xóa commit |
| An toàn nhánh chung | ✅ | ❌ (force push) |
| Dùng cho | Production/shared | Nhánh cá nhân chưa push |

### Why – Ưu tiên redeploy tag cũ hơn revert code
Redeploy artifact `v1.4.0` là **nhanh và chắc chắn** (đúng bản đã chạy tốt). `git revert` để dọn code lỗi khỏi lịch sử cho các release sau, làm **sau** khi đã ổn định prod.

### Real-world – Điểm nghẽn: Database
- Backward-compatible migration (expand/contract): deploy code mới vẫn đọc được schema cũ → rollback code không vỡ DB.
- Tránh migration phá hủy (drop column) cùng release thêm tính năng dùng nó → tách 2 release.

### Ghi chú
> Redeploy tag cũ, `git revert`, blue-green switch, DB migration expand/contract, rollback plan

---

## 6. CI/CD Release Automation (tự động hóa)

### How – Pipeline release điển hình (GitHub Actions, trigger theo tag)
```yaml
# .github/workflows/release.yml
on:
  push:
    tags: ['v*.*.*']          # chỉ chạy khi push tag version

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }          # cần full history cho changelog
      - name: Build artifact
        run: mvn -B package                # build từ đúng commit của tag
      - name: Build & push Docker image
        run: |
          docker build -t ghcr.io/org/app:${GITHUB_REF_NAME} .
          docker push ghcr.io/org/app:${GITHUB_REF_NAME}
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          generate_release_notes: true     # tự sinh release notes từ PR/commit
      - name: Deploy staging
        run: ./deploy.sh staging ${GITHUB_REF_NAME}
```

### How – Kết hợp auto-versioning (semantic-release)
```
Merge PR vào main
   ▼
semantic-release chạy trên main:
  - đọc Conventional Commits → tính version → tạo tag vX.Y.Z + CHANGELOG + GitHub Release
   ▼
Tag mới push → kích hoạt release.yml (build + deploy)
```
→ Toàn bộ từ merge đến deploy **không có bước thủ công đánh version**.

### Components – Pipeline release nên có
- Build artifact **bất biến**, gắn version = tag.
- Push vào artifact registry (immutable, không ghi đè tag đã publish).
- Nhúng version vào app (`git describe` / build arg) để `/version` endpoint truy vết.
- Deploy tự động staging + approval gate thủ công cho production.
- Smoke test sau deploy, tự rollback nếu health check fail.

### Why
Giảm lỗi con người, release nhất quán, lặp lại được, nhanh (deploy nhiều lần/ngày an toàn) — nền tảng của DevOps/DORA metrics (deployment frequency, lead time, MTTR, change failure rate).

### Ghi chú
> tag-triggered pipeline, immutable artifact, approval gate, smoke test, auto-rollback, semantic-release, DORA metrics

---

## 7. Real-world – Checklist release production (tổng hợp)

```
TRƯỚC RELEASE
□ Tất cả PR đã merge, CI xanh trên main
□ Version bump đúng SemVer (feat→minor, fix→patch, breaking→major)
□ CHANGELOG.md cập nhật
□ Tag annotated vX.Y.Z đã tạo & push (--tags)
□ Artifact build từ đúng tag, đẩy registry
□ DB migration backward-compatible, đã test rollback
□ Release notes gửi stakeholder

KHI DEPLOY
□ Deploy staging → smoke test + QA/UAT pass
□ Approval gate cho production
□ Deploy prod (rolling/canary), theo dõi error rate + latency
□ Verify tính năng chính + health check

SAU RELEASE
□ Monitor 15-60 phút (metrics, logs, alerts)
□ Rollback plan sẵn sàng (redeploy tag trước / blue-green switch)
□ Đóng release, thông báo team
□ (Nếu lỗi) Hotfix từ tag → vá → merge ngược → tag mới
```

### Bẫy thường gặp
- Build lại artifact khác nhau cho staging và prod → "chạy ở staging mà hỏng prod". Dùng **cùng một artifact**.
- Deploy khi chưa có rollback plan / DB migration không revert được.
- Quên merge ngược hotfix → lỗi tái xuất version sau.
- Release "Big Bang" cuối tuần → khó xử lý khi lỗi. Ưu tiên **nhỏ, thường xuyên, giờ hành chính**.
- Không nhúng version vào app → không biết prod đang chạy build nào.

---

## Ghi chú – Liên hệ
> Nền tảng version: `semantic_versioning.md` · Chiến lược nhánh cắt release: `../workflow/branching_strategies.md` · CI/CD chi tiết: package `docker/production/cicd_integration.md`, `kubernetes/`
