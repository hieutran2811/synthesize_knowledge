# Roadmap Tổng Hợp Kiến Thức Angular – Cơ Bản đến Nâng Cao

## Cấu trúc thư mục
```
angular/
├── roadmap.md                          ← file này
├── angular_fundamentals.md            ← Architecture, Components, Templates, Data Binding, Directives, Pipes, Standalone
├── angular_components_advanced.md     ← Lifecycle hooks, Change Detection, ViewEncapsulation, Content Projection, Dynamic Components, DI
├── angular_routing_forms.md           ← Router (lazy load, guards, resolvers), Template-driven, Reactive Forms, ControlValueAccessor
├── angular_rxjs.md                    ← RxJS: Observables, Subjects, Operators (switchMap/mergeMap/...), Error handling, async pipe
├── angular_state_management.md        ← BehaviorSubject pattern, NgRx (Store/Actions/Reducers/Effects/Selectors), Signals (Angular 16+)
├── angular_performance_production.md  ← OnPush + Signals, @defer, SSR (Angular Universal), Bundle optimization, PWA, Testing
├── angular_security_best_practices.md ← XSS (DomSanitizer), CSRF, Auth guards, HTTP Interceptor (token), CSP, HTTPS
│
│   ── Bổ sung 2026-06 (lấp gap chuyên gia) ──
├── angular_signals_zoneless.md        ← Reactive graph, signal-based components (input/model/output/queries), effect, linkedSignal/resource, zoneless CD
├── angular_http_communication.md      ← HttpClient, provideHttpClient/withFetch, functional interceptors, retry, caching, upload/download, HttpContext, TransferState
├── angular_testing.md                 ← TestBed/ComponentFixture, HttpTestingController, CDK Harness, marble testing, fakeAsync, signals, Playwright/Cypress
├── angular_material_cdk_a11y.md       ← CDK (Overlay/Portal/VirtualScroll/DragDrop/A11y), Material + theming M3 tokens, accessibility (WCAG/ARIA)
├── angular_animations.md              ← @angular/animations (trigger/state/transition/keyframes/stagger), route/page transitions, View Transitions API
├── angular_cli_nx_monorepo.md         ← CLI/builders (esbuild/Vite)/schematics, budgets, ng update, libraries (ng-packagr), Nx monorepo (affected/cache/boundaries)
└── angular_microfrontends_i18n.md     ← Module Federation/Native Federation, Angular Elements, i18n (localize vs transloco), runtime config/feature flags, Docker/CI-CD
```

> **Prerequisite**: Biết TypeScript, HTML/CSS cơ bản, hiểu JavaScript ES6+

---

## Mục lục

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Fundamentals – Architecture (platform/compiler/runtime), Components, Templates, Data Binding (4 loại), Built-in Directives, Pipes, NgModule vs Standalone Components | angular_fundamentals.md | ✅ |
| 2 | Components Advanced – Lifecycle hooks (8 hooks), Change Detection (Default vs OnPush), ViewEncapsulation, ng-content/ng-template/ng-container, Dynamic components, DI hierarchical | angular_components_advanced.md | ✅ |
| 3 | Routing & Forms – Router config, lazy loading, route guards (CanActivate/CanDeactivate/Resolve), Reactive Forms (FormGroup/FormArray), Custom validators, ControlValueAccessor | angular_routing_forms.md | ✅ |
| 4 | RxJS in Angular – Observable vs Promise, Subjects, Core operators (map/filter/switchMap/mergeMap/concatMap/exhaustMap/combineLatest/forkJoin), Error handling, async pipe | angular_rxjs.md | ✅ |
| 5 | State Management – BehaviorSubject service pattern, NgRx full stack (Store/Actions/Reducers/Effects/Selectors/Entity), Angular Signals (Angular 16+), comparison | angular_state_management.md | ✅ |
| 6 | Performance & Production – OnPush+Signals, trackBy, @defer (Angular 17+), SSR (Angular Universal/SSR), preloading, esbuild, bundle analysis, PWA, Testing (TestBed/Cypress) | angular_performance_production.md | ✅ |
| 7 | Security & Best Practices – XSS/DomSanitizer, CSRF, Auth + Refresh Token interceptor, Route guards, CSP headers, HTTPS, Angular audit checklist | angular_security_best_practices.md | ✅ |

### Bổ sung 2026-06 – Lấp gap chuyên gia (4 cụm)

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 8 | Signals & Zoneless – reactive graph (push-pull, glitch-free), effect (cleanup/untracked), signal-based components (input/input.required/model/output, viewChild/contentChild signal queries), linkedSignal, resource()/rxResource (v19), zoneless change detection (provideExperimentalZonelessChangeDetection) | angular_signals_zoneless.md | ✅ |
| 9 | HTTP Communication – provideHttpClient/withFetch, typed request, HttpParams/observe/responseType, error handling + retry backoff, **functional interceptors** (auth/error/loading/cache), HttpContext, caching, upload/download progress, cancellation, SSR TransferState | angular_http_communication.md | ✅ |
| 10 | Testing – TestBed/ComponentFixture/DebugElement, spies/mocks, **HttpTestingController**, fakeAsync/tick & waitForAsync, **CDK Component Harnesses**, **marble testing** (TestScheduler), testing signals/zoneless, E2E Playwright vs Cypress | angular_testing.md | ✅ |
| 11 | Material, CDK & a11y – CDK (Overlay/Portal/VirtualScroll/DragDrop/Layout/A11y FocusTrap/LiveAnnouncer), Material components, **theming Material 3 (design tokens, dark mode)**, accessibility (semantic HTML/ARIA/keyboard/focus, WCAG) | angular_material_cdk_a11y.md | ✅ |
| 12 | Animations – @angular/animations (trigger/state/transition/animate/keyframes/group/sequence/query/stagger), :enter/:leave, route transitions, View Transitions API, callbacks/disable/reusable, GPU performance, vs CSS | angular_animations.md | ✅ |
| 13 | CLI, Build & Nx Monorepo – CLI/workspace, schematics, **builders (esbuild/Vite application builder)**, budgets/environments, ng update migrations, libraries (ng-packagr), **Nx** (project graph, module boundaries/tags, affected, computation caching, generators/executors) | angular_cli_nx_monorepo.md | ✅ |
| 14 | Micro-frontends, i18n & Deploy – **Module Federation / Native Federation**, Angular Elements (Custom Elements), i18n (@angular/localize vs transloco/ngx-translate), runtime config + feature flags (build once), Docker multi-stage + nginx SPA, CI/CD | angular_microfrontends_i18n.md | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành
- 🔄 Đang làm
- ⬜ Chưa làm

---

## Quick Reference: Angular Versions

| Version | Angular CLI | Key Features |
|---------|-------------|-------------|
| Angular 14 | 14.x | Standalone components (preview), typed reactive forms |
| Angular 15 | 15.x | Standalone components stable, directive composition API |
| Angular 16 | 16.x | **Signals** (preview), required inputs, DestroyRef |
| Angular 17 | 17.x | **@defer** blocks, new control flow (@if/@for/@switch), esbuild default |
| Angular 18 | 18.x | Signals stable (signal-based components), zoneless (experimental) |
| Angular 19 | 19.x | Resource API, linked signal, effect improvements |

---

## Angular Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                   Angular Application                    │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │                  Component Tree                  │   │
│  │  AppComponent                                    │   │
│  │    ├── HeaderComponent                          │   │
│  │    ├── RouterOutlet                             │   │
│  │    │     ├── HomeComponent (lazy)               │   │
│  │    │     └── DashboardModule (lazy)             │   │
│  │    └── FooterComponent                          │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  Services (Singleton) ←→ Store (NgRx/Signals)          │
│  HttpClient ←→ Interceptors ←→ Backend API             │
│  Router ←→ Guards ←→ Resolvers                         │
│                                                         │
│  Compiled by: Angular Compiler (Ivy) → optimized JS    │
│  Rendered by: Browser DOM / Server (SSR) / CDK         │
└─────────────────────────────────────────────────────────┘
```

## Dependency Map

```
@angular/core          → Components, Directives, Pipes, DI, Signals
@angular/common        → NgIf, NgFor, AsyncPipe, DatePipe, HttpClient
@angular/router        → RouterModule, Routes, Guards, Resolvers
@angular/forms         → ReactiveFormsModule, FormGroup, Validators
@angular/platform-browser → BrowserModule, DomSanitizer
@angular/animations    → trigger, state, transition, animate
@ngrx/store            → Store, createAction, createReducer, createSelector
@ngrx/effects          → createEffect, Actions, ofType
rxjs                   → Observable, Subject, BehaviorSubject, operators
```
