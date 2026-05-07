# Angular Performance & Production – Deep Dive

## Mục lục
1. [Change Detection Optimization](#1-change-detection-optimization)
2. [@defer – Deferrable Views (Angular 17+)](#2-defer--deferrable-views-angular-17)
3. [Bundle Optimization](#3-bundle-optimization)
4. [Server-Side Rendering (SSR)](#4-server-side-rendering-ssr)
5. [Progressive Web App (PWA)](#5-progressive-web-app-pwa)
6. [Testing](#6-testing)
7. [Production Checklist](#7-production-checklist)

---

## 1. Change Detection Optimization

### 1.1 OnPush + Immutability

```typescript
// Áp dụng OnPush toàn bộ app = best practice
@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class UserListComponent {
  @Input() users: User[] = [];

  // ✅ Create new reference to trigger OnPush
  addUser(user: User): void {
    this.users = [...this.users, user];  // new array reference
  }

  // ❌ Mutation — won't trigger OnPush child re-render
  badAddUser(user: User): void {
    this.users.push(user);  // same reference
  }
}
```

### 1.2 trackBy — ngFor Optimization

```typescript
@Component({
  template: `
    <!-- Without trackBy: entire list re-rendered on any change -->
    <!-- With trackBy: only changed items re-rendered -->
    
    <!-- Old syntax -->
    <div *ngFor="let user of users; trackBy: trackByUserId">{{ user.name }}</div>
    
    <!-- Angular 17+ new syntax (trackBy is required) -->
    @for (user of users; track user.id) {
      <app-user-card [user]="user" />
    }
  `,
})
export class UserListComponent {
  trackByUserId(index: number, user: User): number {
    return user.id;  // stable identity — avoids DOM destroy/recreate
  }
}
```

### 1.3 async pipe vs Manual Subscribe

```typescript
// ✅ async pipe — auto unsubscribe, triggers OnPush, cleaner
@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @for (user of users$ | async; track user.id) {
      {{ user.name }}
    }
  `,
})
export class Component {
  users$ = this.service.users$;
}

// ❌ Manual subscribe — must manage unsubscribe, extra boilerplate
@Component({})
export class Component implements OnInit, OnDestroy {
  users: User[] = [];
  private sub!: Subscription;

  ngOnInit() {
    this.sub = this.service.users$.subscribe(u => this.users = u);
  }

  ngOnDestroy() {
    this.sub.unsubscribe();
  }
}
```

### 1.4 Pure Pipes

```typescript
// Pure pipe (default) — only recalculates when input reference changes
// Impure pipe — recalculates every change detection cycle (expensive!)
@Pipe({ name: 'filterActive', pure: true })
export class FilterActivePipe implements PipeTransform {
  transform(users: User[]): User[] {
    return users.filter(u => u.active);  // only runs when 'users' reference changes
  }
}

// For filtering/sorting — use pipe instead of method call in template
// ❌ Bad: called every change detection cycle
{{ getActiveUsers() }}

// ✅ Good: pure pipe — cached
{{ users | filterActive }}
```

### 1.5 Signals — Zero-overhead Change Detection

```typescript
// Angular 18+ zoneless (experimental)
bootstrapApplication(AppComponent, {
  providers: [
    provideExperimentalZonelessChangeDetection(),
    // Remove zone.js from polyfills in angular.json
  ],
});

// With signals — Angular only updates components that depend on changed signals
@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `{{ userName() }}`,
})
export class NameComponent {
  userName = this.userStore.name;  // signal

  // Only THIS component re-renders when userName changes
  // NOT the entire component tree
}
```

---

## 2. @defer – Deferrable Views (Angular 17+)

```typescript
// Lazy load heavy components based on conditions
@Component({
  template: `
    <!-- Defer until viewport (Intersection Observer) -->
    @defer (on viewport) {
      <heavy-chart [data]="chartData" />
    } @placeholder (minimum 100ms) {
      <div class="chart-skeleton" style="height: 300px"></div>
    } @loading (after 200ms; minimum 500ms) {
      <loading-spinner />
    } @error {
      <error-message />
    }
    
    <!-- Defer on interaction -->
    @defer (on interaction(triggerEl)) {
      <rich-text-editor [(ngModel)]="content" />
    } @placeholder {
      <div #triggerEl class="editor-placeholder" (click)="void">
        Click to edit...
      </div>
    }
    
    <!-- Defer on hover -->
    @defer (on hover(tooltip)) {
      <tooltip-content [message]="tooltipText" />
    } @placeholder {
      <span #tooltip>{{ labelText }}</span>
    }
    
    <!-- Defer when condition is true -->
    @defer (when isAdminMode) {
      <admin-tools />
    }
    
    <!-- Prefetch while deferring (loads JS but doesn't render yet) -->
    @defer (on viewport; prefetch on idle) {
      <low-priority-widget />
    }
    
    <!-- Never defer (eager) — override for specific components -->
    @defer (on immediate) {
      <critical-above-fold-content />
    }
  `,
})
export class PageComponent {
  chartData = signal<ChartData[]>([]);
  isAdminMode = computed(() => this.authStore.role() === 'ADMIN');
}
```

**@defer triggers:**

| Trigger | Description |
|---------|-------------|
| `on idle` | Khi browser rảnh (requestIdleCallback) |
| `on viewport` | Khi element vào viewport (IntersectionObserver) |
| `on interaction(ref)` | Khi user click/keydown ref element |
| `on hover(ref)` | Khi user hover ref element |
| `on immediate` | Ngay lập tức (eager load) |
| `on timer(2000)` | Sau N milliseconds |
| `when condition` | Khi expression là truthy |

---

## 3. Bundle Optimization

### 3.1 Build Configuration

```json
// angular.json
{
  "configurations": {
    "production": {
      "optimization": {
        "scripts": true,
        "styles": { "minify": true, "inlineCritical": true },
        "fonts": true
      },
      "outputHashing": "all",          // cache busting
      "sourceMap": false,
      "namedChunks": false,
      "aot": true,                     // Ahead-of-time compilation
      "buildOptimizer": true,          // tree-shaking + dead code elimination
      "budgets": [
        {
          "type": "initial",
          "maximumWarning": "500kb",
          "maximumError": "1mb"        // fail build if initial bundle > 1MB
        },
        {
          "type": "anyComponentStyle",
          "maximumWarning": "4kb"
        }
      ]
    }
  }
}
```

### 3.2 Bundle Analysis

```bash
# Build with stats
ng build --stats-json

# Analyze with webpack-bundle-analyzer
npx webpack-bundle-analyzer dist/*/stats.json

# Or use source-map-explorer
npm install -g source-map-explorer
ng build --source-map
source-map-explorer dist/*/main*.js
```

### 3.3 Tree Shaking Best Practices

```typescript
// ✅ Named imports — tree-shakeable
import { map, filter, switchMap } from 'rxjs/operators';

// ❌ Namespace import — imports everything
import * as Rx from 'rxjs';

// ✅ Only import what you use from Angular
import { Component, Input, OnInit } from '@angular/core';

// ✅ Standalone components — better tree shaking than NgModules
@Component({ standalone: true, imports: [JsonPipe] })  // only JsonPipe bundled

// ❌ NgModule — entire module bundled even if only 1 component used
@NgModule({ imports: [CommonModule] })  // entire CommonModule included
```

### 3.4 Lazy Loading Strategy

```typescript
// Route-level code splitting (each route = separate chunk)
const routes: Routes = [
  { path: 'users', loadChildren: () => import('./users/routes').then(m => m.routes) },
  { path: 'dashboard', loadComponent: () => import('./dashboard/dashboard.component').then(m => m.DashboardComponent) },
];

// Library lazy loading
// Avoid large third-party libs in initial bundle
// e.g., chart.js, pdf-lib, mapbox — load only when needed

@Component({
  template: `@defer (on viewport) { <chart /> }`,
})
export class ReportComponent {
  // ChartComponent loaded lazily — not in main bundle
}
```

### 3.5 Image Optimization (Angular 15+)

```typescript
// NgOptimizedImage — automatic lazy loading, srcset, size optimization
import { NgOptimizedImage } from '@angular/common';

@Component({
  standalone: true,
  imports: [NgOptimizedImage],
  template: `
    <!-- priority: LCP images — preload, no lazy -->
    <img ngSrc="hero.jpg" width="1200" height="600" priority />
    
    <!-- Regular images: lazy loaded, srcset generated automatically -->
    <img ngSrc="product.jpg" width="400" height="300" />
    
    <!-- Fill mode: takes container size -->
    <div style="position:relative; height:300px">
      <img ngSrc="background.jpg" fill />
    </div>
  `,
})
```

---

## 4. Server-Side Rendering (SSR)

### 4.1 What & Why SSR?

```
Client-Side Rendering (CSR — default):
  Browser → empty HTML → download JS → execute → render DOM
  Problem: First Contentful Paint (FCP) slow, SEO không tốt

Server-Side Rendering (SSR):
  Browser → fully rendered HTML (from server) → hydrate
  Benefit: FCP nhanh, SEO tốt (search crawlers see content)
  Cost: Server load tăng, cold start

Static Site Generation (SSG / Prerendering):
  Build time → pre-render HTML files
  Benefit: CDN cacheable, instant FCP
  Cost: Dynamic content phải hydrate sau
```

### 4.2 Setup (Angular 17+)

```bash
# New project with SSR
ng new my-app --ssr

# Add SSR to existing project
ng add @angular/ssr
```

### 4.3 SSR-aware Code

```typescript
// Avoid browser APIs on server (window, document, localStorage)
@Component({...})
export class BrowserSafeComponent implements OnInit {
  private platformId = inject(PLATFORM_ID);
  private document = inject(DOCUMENT);

  ngOnInit(): void {
    // Only run in browser
    if (isPlatformBrowser(this.platformId)) {
      const token = localStorage.getItem('token');
      window.addEventListener('resize', this.onResize.bind(this));
    }

    // Safe on both server and browser
    const title = this.document.title;
  }
}

// TransferState — pass data from server to client (avoid duplicate HTTP)
@Component({...})
export class UserComponent implements OnInit {
  private transferState = inject(TransferState);
  private http = inject(HttpClient);
  private platformId = inject(PLATFORM_ID);

  user!: User;

  private USER_KEY = makeStateKey<User>('current-user');

  ngOnInit(): void {
    if (this.transferState.hasKey(this.USER_KEY)) {
      // Client: use data transferred from server
      this.user = this.transferState.get(this.USER_KEY, null)!;
      this.transferState.remove(this.USER_KEY);
    } else {
      // Server: fetch data and store in transfer state
      this.http.get<User>('/api/user').subscribe(user => {
        this.user = user;
        if (isPlatformServer(this.platformId)) {
          this.transferState.set(this.USER_KEY, user);
        }
      });
    }
  }
}
```

### 4.4 Prerendering (SSG)

```typescript
// angular.json — prerender routes at build time
{
  "prerender": {
    "routesFile": "routes.txt",  // list of routes to prerender
    "discoverRoutes": true       // auto-discover static routes
  }
}

// routes.txt
/
/about
/products
/products/1
/products/2
```

---

## 5. Progressive Web App (PWA)

```bash
ng add @angular/pwa
```

```typescript
// ngsw-config.json (Service Worker config)
{
  "index": "/index.html",
  "assetGroups": [
    {
      "name": "app",
      "installMode": "prefetch",    // download on install
      "resources": { "files": ["/favicon.ico", "/index.html", "/*.css", "/*.js"] }
    },
    {
      "name": "assets",
      "installMode": "lazy",        // download on first use
      "updateMode": "prefetch",
      "resources": { "files": ["/assets/**"] }
    }
  ],
  "dataGroups": [
    {
      "name": "api-freshness",
      "urls": ["/api/**"],
      "cacheConfig": {
        "maxSize": 100,
        "maxAge": "3d",
        "timeout": "10s",
        "strategy": "freshness"     // network first, cache fallback
      }
    }
  ]
}
```

---

## 6. Testing

### 6.1 Unit Testing with TestBed

```typescript
// Component test
describe('UserCardComponent', () => {
  let component: UserCardComponent;
  let fixture: ComponentFixture<UserCardComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [UserCardComponent],      // standalone component
      providers: [
        provideRouter([]),
        { provide: UserService, useValue: mockUserService },
      ],
    }).compileComponents();

    fixture = TestBed.createComponent(UserCardComponent);
    component = fixture.componentInstance;
    component.user = mockUser;
    fixture.detectChanges();
  });

  it('should display user name', () => {
    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector('h3')!.textContent).toContain('John Doe');
  });

  it('should emit selected event on click', () => {
    const spy = jest.spyOn(component.selected, 'emit');
    fixture.nativeElement.querySelector('button.select').click();
    expect(spy).toHaveBeenCalledWith(mockUser);
  });

  it('should toggle expanded on click', () => {
    expect(component.isExpanded).toBe(false);
    fixture.nativeElement.querySelector('.card').click();
    fixture.detectChanges();
    expect(component.isExpanded).toBe(true);
  });
});
```

### 6.2 Service Testing

```typescript
describe('UserStateService', () => {
  let service: UserStateService;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [
        UserStateService,
        provideHttpClientTesting(),
      ],
    });
    service = TestBed.inject(UserStateService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => httpMock.verify());

  it('should load users successfully', () => {
    const mockUsers: User[] = [{ id: 1, name: 'John' } as User];

    service.loadUsers();

    const req = httpMock.expectOne('/api/users');
    expect(req.request.method).toBe('GET');
    req.flush(mockUsers);

    expect(service.getSnapshot().users).toEqual(mockUsers);
    expect(service.getSnapshot().isLoading).toBe(false);
  });

  it('should handle load error', () => {
    service.loadUsers();

    httpMock.expectOne('/api/users').flush('Error', {
      status: 500, statusText: 'Server Error',
    });

    expect(service.getSnapshot().error).toBeTruthy();
  });
});
```

### 6.3 NgRx Testing with MockStore

```typescript
describe('UserListComponent with NgRx', () => {
  let store: MockStore;
  let fixture: ComponentFixture<UserListComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [UserListComponent],
      providers: [
        provideMockStore({
          initialState: {
            users: { ids: [], entities: {}, isLoading: false, error: null }
          }
        }),
      ],
    }).compileComponents();

    store = TestBed.inject<Store>(Store) as MockStore;
    fixture = TestBed.createComponent(UserListComponent);
    fixture.detectChanges();
  });

  it('should dispatch loadUsers on init', () => {
    const dispatchSpy = jest.spyOn(store, 'dispatch');
    fixture.componentInstance.ngOnInit();
    expect(dispatchSpy).toHaveBeenCalledWith(UserActions.loadUsers());
  });

  it('should display users from store', () => {
    store.overrideSelector(UserSelectors.allUsers, [mockUser]);
    store.refreshState();
    fixture.detectChanges();

    const userCards = fixture.nativeElement.querySelectorAll('app-user-card');
    expect(userCards.length).toBe(1);
  });
});
```

### 6.4 E2E Testing (Cypress)

```typescript
// cypress/e2e/user-management.cy.ts
describe('User Management', () => {
  beforeEach(() => {
    cy.intercept('GET', '/api/users', { fixture: 'users.json' }).as('getUsers');
    cy.visit('/users');
    cy.wait('@getUsers');
  });

  it('should display user list', () => {
    cy.get('[data-cy=user-card]').should('have.length', 3);
    cy.get('[data-cy=user-card]').first().should('contain', 'John Doe');
  });

  it('should create a new user', () => {
    cy.intercept('POST', '/api/users', { statusCode: 201, body: newUser }).as('createUser');

    cy.get('[data-cy=create-user-btn]').click();
    cy.get('[data-cy=name-input]').type('Jane Smith');
    cy.get('[data-cy=email-input]').type('jane@example.com');
    cy.get('[data-cy=submit-btn]').click();

    cy.wait('@createUser').its('request.body').should('include', { name: 'Jane Smith' });
    cy.get('[data-cy=success-toast]').should('be.visible');
  });

  it('should show validation errors', () => {
    cy.get('[data-cy=create-user-btn]').click();
    cy.get('[data-cy=submit-btn]').click();
    cy.get('[data-cy=email-error]').should('contain', 'Email is required');
  });
});
```

---

## 7. Production Checklist

```markdown
## Angular Production Readiness Checklist

### Performance
- [ ] OnPush applied to all components
- [ ] trackBy on all *ngFor/@for
- [ ] async pipe (not manual subscribe) throughout
- [ ] Heavy components deferred with @defer
- [ ] Images use NgOptimizedImage with priority on LCP
- [ ] Lazy loading for all feature routes
- [ ] Bundle budget set in angular.json
- [ ] Bundle analyzed (no unexpected large deps)
- [ ] Tree-shaking verified (no namespace imports)

### Build
- [ ] AOT compilation enabled (default production)
- [ ] source maps disabled in production
- [ ] esbuild (Angular 17+ default) — verify in angular.json
- [ ] outputHashing: 'all' for cache busting
- [ ] Critical CSS inlined (optimization.styles.inlineCritical)
- [ ] Environment files configured (environment.prod.ts)

### Security (see angular_security_best_practices.md)
- [ ] No direct DOM manipulation (use Renderer2 or Angular binding)
- [ ] DomSanitizer used for dynamic HTML/URL/Style
- [ ] CSP headers set on server
- [ ] HTTP interceptor adds auth tokens
- [ ] HttpOnly cookies for sensitive tokens (not localStorage)
- [ ] Route guards protect all authenticated routes

### SSR (if applicable)
- [ ] No direct window/document access (use isPlatformBrowser)
- [ ] TransferState for HTTP deduplication
- [ ] Meta tags + Open Graph in SSR pages

### Testing
- [ ] Unit tests for all services and complex components
- [ ] Integration tests for critical user flows
- [ ] E2E tests for happy paths
- [ ] Coverage > 80% for business logic

### Observability
- [ ] Error tracking (Sentry, Datadog)
- [ ] Analytics events on key interactions
- [ ] Performance monitoring (Core Web Vitals — LCP, FID, CLS)
- [ ] Angular error handler override (ErrorHandler)
```

---

## Ghi chú – Topics tiếp theo

- **Security**: XSS, CSRF, Auth interceptor → `angular_security_best_practices.md`
- **Keywords**: APP_INITIALIZER, APP_BOOTSTRAP_LISTENER, ApplicationInitStatus, NgZone.runOutsideAngular(), ChangeDetectorRef.detach/reattach, NgZone.onMicrotaskEmpty, Profiler API (Angular DevTools), ApplicationRef.tick(), TransferState, makeStateKey, PLATFORM_ID, isPlatformBrowser/Server, prerender discoverRoutes, provideServiceWorker, SwUpdate, ServiceWorkerModule, withDebugTracing (router), enableDebugTools
