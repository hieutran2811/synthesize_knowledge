---
title: "Micro-Frontends, i18n, Feature Flags & Deployment – Deep Dive"
topic: angular
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 1
---
# Micro-Frontends, i18n, Feature Flags & Deployment – Deep Dive

> Thuật ngữ: [Glossary](glossary.md).

> Bổ trợ cho [angular_cli_nx_monorepo.md](angular_cli_nx_monorepo.md) (monorepo, builders) và [angular_performance_production.md](angular_performance_production.md) (SSR, bundle). Các pattern kiến trúc & vận hành cho app Angular lớn (hợp hướng DevOps).

## Mục lục
1. [Micro-frontends (What & Why)](#1-micro-frontends)
2. [Module Federation (Webpack)](#2-module-federation)
3. [Native Federation (esbuild)](#3-native-federation)
4. [Angular Elements (Custom Elements)](#4-angular-elements)
5. [Internationalization (i18n)](#5-internationalization-i18n)
6. [Runtime Config & Feature Flags](#6-runtime-config--feature-flags)
7. [Deployment & CI/CD](#7-deployment--cicd)
8. [So sánh & Trade-offs](#8-so-sánh--trade-offs)

---

## 1. Micro-frontends

### What & Why
**Micro-frontend (MFE)**: chia UI lớn thành nhiều app độc lập, mỗi team **phát triển & deploy riêng**, ghép lại lúc runtime. Áp dụng tư duy microservices cho frontend.

**Khi nào cần:** nhiều team lớn, cần **deploy độc lập**, codebase khổng lồ, công nghệ khác nhau (Angular + React cùng tồn tại trong quá trình migrate).

**Khi KHÔNG cần:** app nhỏ/vừa, 1-2 team → MFE thêm phức tạp không đáng (lazy-loaded routes/Nx libs là đủ). Đây là quyết định kiến trúc, **đừng dùng vì hype**.

```
┌──────────── Shell (host) ────────────┐
│ Shell load remote lúc runtime:        │
│   /orders  → orders-mfe (team A)      │  ← build & deploy độc lập
│   /billing → billing-mfe (team B)     │
└───────────────────────────────────────┘
```

---

## 2. Module Federation

Cơ chế của **Webpack 5**: app (host) load **module từ app khác (remote)** lúc runtime, **chia sẻ dependency** (Angular core load 1 lần).

```ts
// remote (orders-mfe) webpack.config — expose module
exposes: { './Routes': './src/app/orders/orders.routes.ts' }

// host (shell) — load remote động
{ path: 'orders',
  loadChildren: () => loadRemoteModule({
    type: 'module', remoteEntry: 'http://orders.cdn/remoteEntry.js', exposedModule: './Routes',
  }).then(m => m.ORDERS_ROUTES) }

// shared deps: @angular/core, rxjs... singleton để không load trùng + tránh xung đột version
shared: { '@angular/core': { singleton: true, strictVersion: true } }
```
> Dùng `@angular-architects/module-federation`. **Dynamic federation**: danh sách remote nạp từ config runtime (thêm MFE không cần rebuild shell).
> ⚠️ Module Federation gắn với **webpack** — Angular 17+ mặc định **esbuild** → dùng **Native Federation** (mục 3).

---

## 3. Native Federation

`@angular-architects/native-federation`: chuẩn federation **không phụ thuộc bundler**, hoạt động với **esbuild/Vite** (builder mới của Angular), dùng **Import Maps** + ESM.

```ts
// API tương tự Module Federation nhưng chạy trên application builder (esbuild)
loadRemoteModule('orders-mfe', './Routes')
```
> Đây là hướng đi được khuyến nghị cho MFE Angular hiện đại (vì Angular đã rời webpack). Concept giống Module Federation (host/remote/shared) nhưng tương thích esbuild. Liên hệ builders [angular_cli_nx_monorepo.md](angular_cli_nx_monorepo.md).

---

## 4. Angular Elements (Custom Elements)

Đóng gói component Angular thành **Web Component** (Custom Element) chuẩn → nhúng vào **bất kỳ** trang nào (React, Vue, plain HTML, CMS).

```ts
import { createCustomElement } from '@angular/elements';

@Component({ selector: 'rating-widget', template: `...` })
export class RatingWidget { value = input(0); }

// Đăng ký thành custom element
const el = createCustomElement(RatingWidget, { injector });
customElements.define('rating-widget', el);
// Dùng ở bất kỳ đâu: <rating-widget value="4"></rating-widget>
```
- Input → attribute/property; Output → CustomEvent.
- Dùng cho: widget nhúng (rating, chat), micro-frontend kiểu "component-level", tích hợp dần Angular vào app cũ.
- (−) Mỗi element kéo theo Angular runtime (bundle); nhiều element rời rạc → cân nhắc gộp.

---

## 5. Internationalization (i18n)

### Hai hướng: compile-time (built-in) vs runtime (thư viện)

#### A. `@angular/localize` – built-in, compile-time
```html
<h1 i18n="@@homeTitle">Trang chủ</h1>
<p i18n="meaning|description@@greeting">Xin chào</p>
```
```bash
ng extract-i18n                      # xuất messages.xlf để dịch
ng build --localize                  # build RIÊNG mỗi locale (vi/en/...) → /vi, /en
```
- `$localize` cho chuỗi trong code: `` $localize`:@@key:Xin chào` ``.
- **Compile-time**: mỗi ngôn ngữ = 1 build/bundle riêng → **tối ưu** (không tốn runtime, tree-shake chuỗi thừa) nhưng **đổi ngôn ngữ phải reload** sang bundle khác (thường route theo locale).

#### B. `transloco` / `ngx-translate` – runtime
```ts
// JSON per language: en.json, vi.json — load runtime, đổi ngôn ngữ không reload
{{ 'home.title' | transloco }}
this.translocoService.setActiveLang('vi');   // đổi tức thì
```
- **Runtime**: 1 bundle, đổi ngôn ngữ tức thì, load JSON lazy → linh hoạt cho app nhiều ngôn ngữ, user tự đổi.

### So sánh i18n

| | @angular/localize (compile) | transloco/ngx-translate (runtime) |
|--|------------------------------|-----------------------------------|
| Build | 1 build/locale | 1 build, JSON load runtime |
| Đổi ngôn ngữ | Reload bundle khác | Tức thì, không reload |
| Hiệu năng runtime | Tốt nhất | Có overhead (pipe/lookup) |
| Pluralization/ICU | Mạnh (ICU) | Có (tùy lib) |
| Khi dùng | SEO/locale theo domain/route | App đa ngôn ngữ user tự đổi |

> Ngoài text: format ngày/số/tiền tệ qua `DatePipe`/`CurrencyPipe` + `LOCALE_ID`, `registerLocaleData`.

---

## 6. Runtime Config & Feature Flags

### Vấn đề: "build once, deploy anywhere"
`environment.prod.ts` được nhúng **lúc build** → mỗi môi trường (dev/staging/prod) phải **build lại**. Đi ngược nguyên tắc Docker "build 1 image, chạy mọi env" (liên hệ [angular_cli_nx_monorepo.md](angular_cli_nx_monorepo.md) phần environments).

### Giải pháp: nạp config runtime lúc khởi động
```ts
// Nạp /assets/config.json (mount khác nhau mỗi env) trước khi app chạy
export function provideRuntimeConfig() {
  return provideAppInitializer(() => {            // Angular 19 (thay APP_INITIALIZER)
    const http = inject(HttpClient), cfg = inject(AppConfig);
    return firstValueFrom(http.get<Config>('/assets/config.json').pipe(tap(c => cfg.set(c))));
  });
}
```
> Cùng 1 image Docker; mỗi env mount `config.json` riêng (ConfigMap K8s / volume). API URL, feature flags không cần rebuild.

### Feature Flags
```ts
// Bật/tắt tính năng runtime — A/B test, canary, kill-switch
@if (flags.isEnabled('new-checkout')) { <app-new-checkout /> } @else { <app-old-checkout /> }
```
- Tự build (config.json) hoặc dịch vụ: **Unleash, LaunchDarkly, Flagsmith**.
- Kết hợp với SSR/route guards. Tách "deploy" khỏi "release" (deploy code tắt flag, bật dần).

---

## 7. Deployment & CI/CD

### Build & đóng gói (Docker multi-stage)
```dockerfile
# Stage 1: build
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build           # ng build → dist/

# Stage 2: serve tĩnh bằng nginx (nhẹ)
FROM nginx:alpine
COPY --from=build /app/dist/my-app/browser /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
```
- **SPA fallback**: nginx `try_files $uri $uri/ /index.html;` (để route Angular hoạt động khi refresh).
- **`--base-href`**: khi deploy dưới subpath (`/app/`): `ng build --base-href=/app/`.
- **Cache header**: `index.html` no-cache; asset có hash → cache vĩnh viễn (immutable).
- SSR: chạy Node server (`dist/server`) thay vì nginx tĩnh — xem [angular_performance_production.md](angular_performance_production.md).
> Liên hệ Docker multi-stage + nginx + CI/CD ở các file Docker của dự án (docker/production/cicd_integration.md).

### CI pipeline (điển hình)
```bash
npm ci → ng lint → ng test --watch=false --browsers=ChromeHeadless → ng build --configuration=production
# Monorepo Nx: nx affected -t lint test build (chỉ phần thay đổi) + remote cache
```

---

## 8. So sánh & Trade-offs

### Micro-frontend vs Monolith SPA vs Modular Monolith (Nx)
| | Monolith SPA | Modular Monolith (Nx libs) | Micro-frontend |
|--|--------------|----------------------------|----------------|
| Deploy độc lập | Không | Không (1 deploy) | **Có** |
| Độ phức tạp | Thấp | Trung bình | **Cao** |
| Chia sẻ code | Trực tiếp | Trực tiếp (libs) | Qua shared deps (khó hơn) |
| Phù hợp | Đa số app | App lớn 1 tổ chức | Nhiều team, deploy độc lập |

### Trade-offs
- (+) MFE: team tự chủ, deploy độc lập, scale tổ chức, migrate dần công nghệ.
- (−) MFE: phức tạp vận hành (version shared deps, routing, state chung, bundle trùng), debug khó → **chỉ dùng khi thật sự cần**; phần lớn app dùng Nx modular monolith là đủ.
- (+) Runtime config + feature flags: 1 image mọi env, tách deploy/release, A/B test an toàn.
- i18n: compile-time tối ưu nhưng cứng; runtime linh hoạt nhưng tốn overhead → chọn theo nhu cầu đổi ngôn ngữ.

---

## Ghi chú – Topics tiếp theo

- Liên quan: [angular_cli_nx_monorepo.md](angular_cli_nx_monorepo.md) (monorepo, builders, environments), [angular_performance_production.md](angular_performance_production.md) (SSR, bundle, PWA), [angular_http_communication.md](angular_http_communication.md) (load config runtime), [angular_security_best_practices.md](angular_security_best_practices.md) (CSP cho MFE/elements).
- **Keywords**: `loadRemoteModule`, `remoteEntry.js`, Import Maps, `shareScope`, `provideAppInitializer`/`APP_INITIALIZER`, `LOCALE_ID`, `registerLocaleData`, `$localize`, ICU expressions, `xliffmerge`, `DOCUMENT`/`PLATFORM_ID`, `withViewTransitions`, base-href/deploy-url, Web Components polyfill, single-spa (alternative MFE framework).

*Cập nhật lần cuối: 2026-06-04*
