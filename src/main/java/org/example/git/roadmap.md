# Roadmap Tổng Hợp Kiến Thức Git

> Trọng tâm package: **Git trong quy trình dự án thực tế** và **quản lý version khi release sản phẩm**.

## Cấu trúc thư mục
```
git/
├── roadmap.md                       ← file này
├── git_knowledge.md                 ← overview tổng quan (12 topics)
├── workflow/                        ← quy trình làm việc nhóm trong dự án thực tế
│   ├── branching_strategies.md      ← Git Flow, GitHub Flow, GitLab Flow, Trunk-Based
│   └── team_collaboration.md        ← PR/MR, code review, merge vs rebase, conflict, protected branch
└── versioning/                      ← quản lý phiên bản & phát hành
    ├── semantic_versioning.md       ← SemVer, Conventional Commits, tag, CHANGELOG
    └── release_management.md        ← release process, deploy strategy, hotfix, rollback, CI/CD
```

---

## Mục lục đã hoàn thành ✅

### Overview – Nền tảng (git_knowledge.md)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Git Overview – DVCS, snapshot, object model (blob/tree/commit/tag), 3 khu vực, branch/HEAD | git_knowledge.md | ✅ |
| 2 | Git Internals – `.git/`, object storage, packfile, delta compression, gc | git_knowledge.md | ✅ |
| 3 | Config & Init – `git config`, `.gitignore`, `.gitattributes`, Git LFS | git_knowledge.md | ✅ |
| 4 | Everyday Workflow – add/commit/diff/log, undo cheat sheet (reset/revert/stash/reflog) | git_knowledge.md | ✅ |
| 5 | Branching – tạo/xóa/switch nhánh, naming convention | git_knowledge.md | ✅ |
| 6 | Merge vs Rebase – DAG, golden rule, squash | git_knowledge.md | ✅ |
| 7 | Remote & Cộng tác – fetch vs pull, `--force-with-lease` | git_knowledge.md | ✅ |
| 8 | Tag & Version – annotated vs lightweight, đẩy tag | git_knowledge.md | ✅ |
| 9 | Quản lý phiên bản & Release – chuỗi giá trị release, components | git_knowledge.md | ✅ |
| 10 | Bảo mật & Toàn vẹn – signed commit, gitleaks, filter-repo, protected branch, CODEOWNERS | git_knowledge.md | ✅ |
| 11 | Debugging with Git – blame, bisect, pickaxe, reflog, cherry-pick | git_knowledge.md | ✅ |
| 12 | Git Hooks & Automation – pre-commit/commit-msg/pre-push, Husky, commitlint | git_knowledge.md | ✅ |

### Workflow Deep Dive – Quy trình dự án thực tế
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 13.1 | Branching Strategies – Git Flow, GitHub Flow, GitLab Flow, Trunk-Based, cây quyết định chọn mô hình | workflow/branching_strategies.md | ✅ |
| 13.2 | Team Collaboration – PR/MR lifecycle, 3 kiểu merge, merge vs rebase thực chiến, interactive rebase, conflict, protected branches, CODEOWNERS | workflow/team_collaboration.md | ✅ |

### Versioning Deep Dive – Quản lý version & release
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 14.1 | Semantic Versioning – SemVer 2.0, Conventional Commits → auto version, git tag thực hành, CHANGELOG, auto-changelog tools | versioning/semantic_versioning.md | ✅ |
| 14.2 | Release Management – vòng đời release, cắt release theo branching model, deploy strategies (rolling/blue-green/canary), hotfix, rollback, CI/CD automation, checklist production | versioning/release_management.md | ✅ |

---

## Chủ đề mở rộng tương lai (⬜ chưa làm)
| STT | Chủ đề gợi ý | Ghi chú |
|-----|--------------|---------|
| 15.1 | Monorepo với Git – sparse-checkout, partial clone, submodule vs subtree, Nx/Turborepo | Repo lớn |
| 15.2 | Git LFS & binary lớn – workflow asset game/ML | Binary |
| 15.3 | Advanced recovery – `git worktree`, `git rerere`, `filter-repo` sâu | Vận hành |
| 15.4 | GitOps – ArgoCD/Flux, Git là source of truth cho infra | Liên kết `kubernetes/` |

---

## Liên hệ package khác
- CI/CD chi tiết: `docker/production/cicd_integration.md`
- Triển khai K8s/GitOps: `kubernetes/`
- Bảo mật supply chain: `security/`, `docker/security/`

## Chú thích trạng thái
- ✅ Hoàn thành – đã có nội dung
- 🔄 Đang làm
- ⬜ Chưa làm
