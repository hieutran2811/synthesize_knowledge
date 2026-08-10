---
title: "Angular CLI, Build Tooling & Nx Monorepo – Deep Dive"
topic: angular
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Angular CLI, Build Tooling & Nx Monorepo – Deep Dive

> Thuật ngữ: [Glossary](glossary.md).

> Bổ trợ cho [angular_performance_production.md](angular_performance_production.md) (esbuild, bundle optimization). File này đi sâu CLI/builders/schematics và kiến trúc Nx monorepo (góc DevOps).

## Mục lục
1. [Angular CLI & Workspace (What & How)](#1-angular-cli--workspace)
2. [Schematics – code generation](#2-schematics)
3. [Builders & Build pipeline (esbuild/Vite)](#3-builders--build-pipeline)
4. [Build configurations, budgets, environments](#4-build-configurations-budgets-environments)
5. [ng update & migrations](#5-ng-update--migrations)
6. [Angular Libraries (ng-packagr)](#6-angular-libraries)
7. [Nx Monorepo](#7-nx-monorepo)
8. [So sánh & Trade-offs](#8-so-sánh--trade-offs)

---

## 1. Angular CLI & Workspace

### What – CLI là gì?
`@angular/cli` (`ng`) là công cụ tạo, build, test, serve, nâng cấp project — chuẩn hóa toàn bộ tooling. Cấu hình tập trung ở **`angular.json`** (workspace).

```bash
ng new my-app --standalone --routing --style=scss
ng serve              # dev server (HMR, watch)
ng build              # production build vào dist/
ng test               # unit test
ng lint               # ESLint
ng add @angular/material   # cài + cấu hình tự động (schematic)
ng generate component user # sinh code
```

### Workspace – một hoặc nhiều project
```jsonc
// angular.json (rút gọn)
{
  "projects": {
    "my-app":     { "projectType": "application", "architect": { "build": {...}, "serve": {...} } },
    "ui-lib":     { "projectType": "library",     "architect": { "build": { "builder": "@angular-devkit/build-angular:ng-packagr" } } }
  }
}
```
> Một workspace có thể chứa **nhiều application + library** (monorepo nhẹ của CLI). Nx mở rộng mạnh hơn (mục 7).

---

## 2. Schematics

**Schematics** = bộ sinh/biến đổi code theo convention (cái chạy sau `ng generate`/`ng add`/`ng update`).

```bash
ng generate component features/user --change-detection=OnPush --inline-template
ng generate service core/auth
ng generate @angular/material:navigation my-nav   # schematic của package
```
- `ng add <pkg>`: cài package **và** chạy schematic cấu hình (vd thêm provider, import).
- Viết schematic riêng để chuẩn hóa cấu trúc team (Tree API, Rule). Liên hệ generator của Nx (mục 7).

---

## 3. Builders & Build pipeline

**Builder** = thực thi một "architect target" (build/serve/test). Angular 17+ mặc định **application builder** dùng **esbuild + Vite**.

| Builder | Dùng cho | Engine |
|---------|---------|--------|
| `@angular-devkit/build-angular:application` | App (A17+ default) | **esbuild** (build) + **Vite** (dev server) |
| `:browser-esbuild` | Migrate từ webpack | esbuild |
| `:browser` (legacy) | App cũ | webpack |
| `:ng-packagr` | Library | ng-packagr |

```
esbuild: bundle/transpile cực nhanh (Go) → build & cold-start dev nhanh hơn webpack nhiều
Vite:    dev server dùng native ESM + HMR tức thì
```
> Lợi ích esbuild: build production nhanh hơn 2-4x, dev server khởi động nhanh, hỗ trợ SSR tích hợp. Liên hệ bundle optimization ở [angular_performance_production.md](angular_performance_production.md).

---

## 4. Build configurations, budgets, environments

```jsonc
"configurations": {
  "production": {
    "optimization": true, "outputHashing": "all", "sourceMap": false,
    "budgets": [
      { "type": "initial", "maximumWarning": "500kb", "maximumError": "1mb" },
      { "type": "anyComponentStyle", "maximumWarning": "4kb" }
    ],
    "fileReplacements": [{ "replace": "src/environments/environment.ts", "with": "src/environments/environment.prod.ts" }]
  },
  "development": { "optimization": false, "sourceMap": true }
}
```
```bash
ng build --configuration=production
```
- **Budgets**: cảnh báo/lỗi khi bundle vượt ngưỡng → giữ size kiểm soát trong CI.
- **fileReplacements / environments**: đổi config theo môi trường (API URL...). Hiện đại hơn: inject config runtime (đỡ rebuild mỗi env — quan trọng cho Docker "build once, run anywhere"). Liên hệ [angular_microfrontends_i18n.md](angular_microfrontends_i18n.md) (dynamic config).
- `outputHashing`: cache busting cho CDN.

---

## 5. ng update & migrations

```bash
ng update                       # liệt kê package có thể update
ng update @angular/core @angular/cli   # update + chạy migration schematics tự động
```
> `ng update` chạy **migration** tự sửa breaking change (vd chuyển sang standalone, đổi API) → nâng version mượt. Luôn update **từng major một**, đọc changelog. Liên hệ Quick Reference versions ở [roadmap.md](roadmap.md).

---

## 6. Angular Libraries

```bash
ng generate library ui-kit
ng build ui-kit                 # ng-packagr → Angular Package Format (APF)
npm publish dist/ui-kit
```
- **ng-packagr** đóng gói theo APF (esm, types, partial-Ivy để tương thích nhiều version).
- **Secondary entry points**: `ui-kit/button`, `ui-kit/forms` → tree-shaking tốt.
- Library nội bộ dùng chung giữa apps → đây là cầu nối sang **monorepo**.

---

## 7. Nx Monorepo

### What & Why
**Nx** là build system cho monorepo (nhiều app + lib trong 1 repo). Giải bài toán scale: chia sẻ code, **chỉ build/test thứ bị ảnh hưởng**, cache để CI nhanh, ép ranh giới kiến trúc.

### Cấu trúc & Project Graph
```
apps/
  web/            (Angular app)
  admin/          (Angular app)
libs/
  shared/ui/             (component dùng chung — type: ui)
  orders/feature-list/   (feature — type: feature)
  orders/data-access/    (HTTP/state — type: data-access)
  shared/util-formatting/(hàm thuần — type: util)
```
Nx dựng **project graph** (đồ thị phụ thuộc giữa app/lib) → biết gì phụ thuộc gì.

### Module Boundaries (ép kiến trúc bằng lint)
Gắn **tag** cho từng lib, cấu hình rule `@nx/enforce-module-boundaries` để cấm import sai tầng:
```jsonc
// vd: feature có thể dùng data-access & ui & util; nhưng util KHÔNG được dùng feature
{ "sourceTag": "type:util", "onlyDependOnLibsWithTags": ["type:util"] },
{ "sourceTag": "scope:orders", "onlyDependOnLibsWithTags": ["scope:orders", "scope:shared"] }
```
> Ép ranh giới ngay khi lint/CI → tránh "big ball of mud", giữ kiến trúc tầng (feature → data-access/ui → util). Tư tưởng tương tự `api` vs `implementation` ở Gradle (ranh giới module ở tầng build).

### Affected – chỉ làm việc cần thiết
```bash
nx affected -t build test lint --base=origin/main   # chỉ build/test project bị ảnh hưởng bởi diff
nx graph                                            # xem project graph trực quan
```
> CI chỉ chạy phần thay đổi tác động → tiết kiệm thời gian khổng lồ trên monorepo lớn.

### Computation Caching
```
Nx hash input (source + deps + config) → nếu trùng cache → trả output tức thì (không chạy lại)
- Local cache: máy dev
- Remote cache (Nx Cloud): chia sẻ cache giữa CI runners & cả team → "ai đó đã build, bạn không phải build lại"
- Distributed Task Execution (DTE): chia task ra nhiều CI agent song song
```

### Generators & Executors
- **Generator** (≈ schematic): `nx g @nx/angular:component`, `nx g @nx/angular:library`.
- **Executor** (≈ builder): `nx build web`, `nx test orders-data-access`.
- Plugin: `@nx/angular`, `@nx/jest`, `@nx/playwright`, `@nx/esbuild`.

---

## 8. So sánh & Trade-offs

### Monorepo (Nx) vs Polyrepo
| | Monorepo (Nx) | Polyrepo (nhiều repo) |
|--|---------------|------------------------|
| Chia sẻ code | Trực tiếp qua libs | npm publish/version |
| Refactor xuyên project | 1 commit | Nhiều PR, version bump |
| Build/CI | Affected + cache (nhanh) | Mỗi repo riêng |
| Ranh giới | Lint enforce | Tự nhiên (repo tách) |
| Độ phức tạp setup | Cao hơn | Thấp |

### Angular CLI workspace vs Nx
- CLI workspace: đủ cho 1-2 app + vài lib, ít cấu hình.
- Nx: nhiều app/lib, cần affected + caching + boundaries + plugin (Storybook, Playwright, backend Node trong cùng repo).

### Trade-offs
- (+) Nx: scale tốt, CI nhanh (affected + cache), ép kiến trúc, chia sẻ code dễ, đa công nghệ (FE+BE 1 repo).
- (−) Nx: học curve, setup phức tạp, Nx Cloud cache remote có thể tốn phí, monorepo lớn cần kỷ luật.
- (+) esbuild/Vite: build & dev nhanh hơn webpack rõ rệt.
- (−) Một số webpack plugin/loader chưa tương thích esbuild builder (cần custom).

---

## Ghi chú – Topics tiếp theo

- Liên quan: [angular_performance_production.md](angular_performance_production.md) (esbuild, bundle, budgets), [angular_microfrontends_i18n.md](angular_microfrontends_i18n.md) (Module Federation trong monorepo, dynamic config), [angular_testing.md](angular_testing.md) (Nx test executors), roadmap versions [roadmap.md](roadmap.md).
- **Keywords**: `angular.json` architect, `project.json` (Nx), `nx.json` `targetDefaults`/`namedInputs`, `nx release` (versioning libs), `@nx/enforce-module-boundaries`, `nx affected:graph`, `inputs`/`outputs` cache, Nx Cloud DTE, `ng-packagr` APF, `browserslist`, `assets`/`styles` config, `ng deploy`, Bazel (alternative).

*Cập nhật lần cuối: 2026-06-04*
