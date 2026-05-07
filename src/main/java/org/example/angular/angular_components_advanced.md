# Angular Components Advanced – Lifecycle, Change Detection, DI

## Mục lục
1. [Lifecycle Hooks](#1-lifecycle-hooks)
2. [Change Detection](#2-change-detection)
3. [ViewEncapsulation](#3-viewencapsulation)
4. [Content Projection – ng-content, ng-template, ng-container](#4-content-projection)
5. [Dynamic Components](#5-dynamic-components)
6. [Dependency Injection Deep](#6-dependency-injection-deep)
7. [HTTP Client & Interceptors](#7-http-client--interceptors)

---

## 1. Lifecycle Hooks

### 1.1 Thứ tự thực thi

```
Component Creation:
1. constructor()           ← DI injection, KHÔNG access @Input, DOM chưa tồn tại
2. ngOnChanges()           ← đầu tiên + mỗi khi @Input thay đổi (SimpleChanges)
3. ngOnInit()              ← sau khi @Input lần đầu set, DOM chưa render
4. ngDoCheck()             ← sau mỗi change detection cycle (custom change detection)
5. ngAfterContentInit()    ← sau khi ng-content được projected (một lần)
6. ngAfterContentChecked() ← sau mỗi content check cycle
7. ngAfterViewInit()       ← DOM đã render, @ViewChild available (một lần)
8. ngAfterViewChecked()    ← sau mỗi view check cycle

Component Destruction:
9. ngOnDestroy()           ← trước khi component bị destroy (cleanup!)
```

### 1.2 Ví dụ thực tế

```typescript
@Component({
  selector: 'app-user-profile',
  standalone: true,
  template: `
    <div #profileContainer>
      <h2>{{ user.name }}</h2>
    </div>
  `,
})
export class UserProfileComponent implements OnInit, OnChanges, AfterViewInit, OnDestroy {

  @Input({ required: true }) userId!: number;
  @ViewChild('profileContainer') container!: ElementRef;

  user!: User;
  private destroy$ = new Subject<void>();   // pattern cleanup RxJS subscriptions

  constructor(private userService: UserService) {
    // constructor: DI only, no @Input access yet
  }

  ngOnChanges(changes: SimpleChanges): void {
    // Gọi trước ngOnInit và mỗi khi @Input thay đổi
    if (changes['userId']) {
      const { previousValue, currentValue, firstChange } = changes['userId'];
      console.log(`userId: ${previousValue} → ${currentValue} (firstChange: ${firstChange})`);

      if (!firstChange) {
        // Reload data when userId changes
        this.loadUser(currentValue);
      }
    }
  }

  ngOnInit(): void {
    // Best place for initialization with @Input values
    this.loadUser(this.userId);
  }

  ngAfterViewInit(): void {
    // @ViewChild available here
    this.container.nativeElement.classList.add('ready');
  }

  ngOnDestroy(): void {
    // CRITICAL: cleanup to prevent memory leaks
    this.destroy$.next();
    this.destroy$.complete();
  }

  private loadUser(id: number): void {
    this.userService.getById(id)
      .pipe(takeUntil(this.destroy$))  // auto-unsubscribe on destroy
      .subscribe(user => this.user = user);
  }
}
```

### 1.3 DestroyRef (Angular 16+ — cleaner cleanup)

```typescript
@Component({...})
export class ModernComponent {
  constructor(
    private userService: UserService,
    destroyRef: DestroyRef   // inject directly
  ) {
    // Alternative to ngOnDestroy — cleaner
    const subscription = this.userService.getUser(1)
      .pipe(takeUntilDestroyed(destroyRef))
      .subscribe(user => { ... });
  }
}

// Hoặc dùng takeUntilDestroyed() không cần inject
@Component({...})
export class CleanComponent {
  private destroyRef = inject(DestroyRef);   // inject() function (Angular 14+)

  ngOnInit(): void {
    interval(1000)
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe(i => console.log(i));
  }
}
```

---

## 2. Change Detection

### 2.1 Default Change Detection

```
Zone.js patches: setTimeout, Promise, DOM events, XHR
  → triggers Angular's change detection
  → Angular checks ENTIRE component tree top-down
  → For EACH component: check if template expressions changed → update DOM
  
Cost: O(n) components checked per event
Problem: Large trees → performance issues (1000+ components)
```

### 2.2 OnPush Strategy

```typescript
@Component({
  selector: 'app-user-card',
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,  // ← KEY
  template: `
    <div>{{ user.name }}</div>
    <div>{{ counter }}</div>
  `,
})
export class UserCardComponent {
  @Input() user!: User;
  counter = 0;

  // OnPush component chỉ re-render khi:
  // 1. @Input reference changes (user = newUser, không phải user.name = ...)
  // 2. Component's own DOM event fires
  // 3. async pipe emits new value
  // 4. ChangeDetectorRef.markForCheck() được gọi
}
```

```typescript
// Parent: phải tạo new object khi muốn trigger OnPush child
@Component({...})
export class ParentComponent {
  user: User = { id: 1, name: 'John' };

  // ❌ Sai: mutate → OnPush child không detect
  wrongUpdate(): void {
    this.user.name = 'Jane';  // same reference → no re-render
  }

  // ✅ Đúng: new reference → OnPush child re-renders
  correctUpdate(): void {
    this.user = { ...this.user, name: 'Jane' };
  }

  // ✅ Hoặc dùng immutable patterns (Immer.js)
  correctWithImmer(): void {
    this.user = produce(this.user, draft => {
      draft.name = 'Jane';
    });
  }
}
```

### 2.3 ChangeDetectorRef — Manual Control

```typescript
@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class DataGridComponent implements OnInit {
  rows: Row[] = [];

  constructor(private cdr: ChangeDetectorRef) {}

  ngOnInit(): void {
    // WebSocket data — không qua Zone.js
    this.ws.messages$.subscribe(data => {
      this.rows = data;
      this.cdr.markForCheck();     // mark này + parents → check on next CD cycle
    });
  }

  pauseUpdates(): void {
    this.cdr.detach();     // completely detach from change detection tree
  }

  resumeUpdates(): void {
    this.cdr.reattach();   // reattach + check immediately
  }

  forceCheck(): void {
    this.cdr.detectChanges();  // synchronous check THIS component + children
  }
}
```

### 2.4 Signals (Angular 16+ — Tương lai)

```typescript
import { signal, computed, effect } from '@angular/core';

@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,  // signals work best with OnPush
  template: `
    <p>Count: {{ count() }}</p>
    <p>Double: {{ doubled() }}</p>
    <button (click)="increment()">+</button>
  `,
})
export class CounterComponent {
  count = signal(0);           // WritableSignal<number>
  doubled = computed(() => this.count() * 2);  // ComputedSignal — auto-recomputes

  constructor() {
    effect(() => {
      // Runs when count() changes — like computed but for side effects
      console.log('Count changed to:', this.count());
    });
  }

  increment(): void {
    this.count.update(c => c + 1);  // update based on previous value
    // hoặc: this.count.set(this.count() + 1);
  }
}
```

**Change Detection so sánh:**

| | Default | OnPush | Signals (Zoneless) |
|--|---------|--------|-------------------|
| Trigger | Any async event | @Input change / event / markForCheck | Signal value change |
| Performance | O(component tree) | Much better | Surgical (only affected) |
| Complexity | Low | Medium (need immutable) | Low (natural) |
| Zone.js needed | Yes | Yes | No (future) |
| Angular version | All | All | 16+ (stable in 18+) |

---

## 3. ViewEncapsulation

```typescript
@Component({
  // Default: Emulated — scoped styles via attr selectors (no Shadow DOM)
  encapsulation: ViewEncapsulation.Emulated,
  
  // None — global styles, no scoping (use carefully!)
  encapsulation: ViewEncapsulation.None,
  
  // ShadowDom — real Shadow DOM (browser support required)
  encapsulation: ViewEncapsulation.ShadowDom,

  styles: [`
    h2 { color: blue; }   /* Emulated: becomes h2[_ngcontent-xxx] */
  `],
})
```

```scss
// Override child component styles from parent (Emulated mode)
:host {
  display: block;      /* Component host element styling */
  color: red;
}

:host(.highlighted) {  /* When host has class 'highlighted' */
  background: yellow;
}

// Deep selector (style child component's internal elements)
:host ::ng-deep .mat-button {   // AVOID in new code — use global styles instead
  border-radius: 4px;
}
```

---

## 4. Content Projection

### 4.1 ng-content – Single Slot

```typescript
// card.component.ts
@Component({
  selector: 'app-card',
  standalone: true,
  template: `
    <div class="card">
      <ng-content />    <!-- Project any content here -->
    </div>
  `,
})
export class CardComponent {}

// Usage
<app-card>
  <h2>Title</h2>
  <p>Content here</p>
</app-card>
```

### 4.2 Multi-slot Projection

```typescript
@Component({
  selector: 'app-layout',
  template: `
    <header>
      <ng-content select="[slot=header]" />
    </header>
    <main>
      <ng-content select="[slot=content]" />
    </main>
    <footer>
      <ng-content select="[slot=footer]" />
    </footer>
    <ng-content />     <!-- catch-all -->
  `,
})
export class LayoutComponent {}

// Usage
<app-layout>
  <h1 slot="header">Page Title</h1>
  <app-data-table slot="content" />
  <p slot="footer">Copyright 2024</p>
</app-layout>
```

### 4.3 ng-template & ng-container

```typescript
// ng-template: định nghĩa template không render ngay
// ng-container: logical grouping không tạo DOM element
@Component({
  template: `
    <!-- ng-container: dùng khi cần 2 structural directives -->
    <ng-container *ngFor="let user of users">
      <ng-container *ngIf="user.active">
        <app-user-card [user]="user" />
      </ng-container>
    </ng-container>
    
    <!-- ng-template: reusable template blocks -->
    <ng-container *ngTemplateOutlet="userTemplate; context: { $implicit: selectedUser }" />
    
    <ng-template #userTemplate let-user>
      <div class="user-preview">
        <img [src]="user.avatar" />
        <span>{{ user.name }}</span>
      </div>
    </ng-template>
    
    <!-- ng-template with if/else -->
    <div *ngIf="isLoading; else contentTemplate">
      <spinner />
    </div>
    <ng-template #contentTemplate>
      <p>Content loaded!</p>
    </ng-template>
  `,
})
export class TemplateExampleComponent {
  @Input() contentTemplate!: TemplateRef<any>;   // Accept template from parent
}
```

### 4.4 @ContentChild / @ContentChildren

```typescript
@Component({
  selector: 'app-tabs',
  template: `
    <div class="tab-headers">
      @for (tab of tabs; track tab) {
        <button (click)="activeTab = tab">{{ tab.label }}</button>
      }
    </div>
    <ng-content />
  `,
})
export class TabsComponent implements AfterContentInit {
  @ContentChildren(TabComponent) tabs!: QueryList<TabComponent>;
  activeTab!: TabComponent;

  ngAfterContentInit(): void {
    this.activeTab = this.tabs.first;
    // React to dynamic tabs being added/removed
    this.tabs.changes.subscribe(() => {
      if (!this.tabs.includes(this.activeTab)) {
        this.activeTab = this.tabs.first;
      }
    });
  }
}

// Usage
<app-tabs>
  <app-tab label="Profile"><user-form /></app-tab>
  <app-tab label="Settings"><settings-form /></app-tab>
</app-tabs>
```

---

## 5. Dynamic Components

```typescript
// Dynamic component loading with ViewContainerRef
@Component({
  selector: 'app-dialog-host',
  standalone: true,
  template: `<ng-container #container />`,
})
export class DialogHostComponent {
  @ViewChild('container', { read: ViewContainerRef })
  container!: ViewContainerRef;

  openDialog<T>(component: Type<T>, inputs?: Partial<T>): ComponentRef<T> {
    this.container.clear();
    const ref = this.container.createComponent(component);

    // Set inputs
    if (inputs) {
      Object.entries(inputs).forEach(([key, value]) => {
        ref.setInput(key, value);
      });
    }

    return ref;
  }

  closeDialog(): void {
    this.container.clear();
  }
}

// Dialog Service pattern
@Injectable({ providedIn: 'root' })
export class DialogService {
  private dialogHost!: DialogHostComponent;

  register(host: DialogHostComponent): void {
    this.dialogHost = host;
  }

  open<T>(component: Type<T>, inputs?: Partial<T>): ComponentRef<T> {
    return this.dialogHost.openDialog(component, inputs);
  }

  close(): void {
    this.dialogHost.closeDialog();
  }
}
```

---

## 6. Dependency Injection Deep

### 6.1 Provider Types

```typescript
// 1. Class provider (default)
@Injectable({ providedIn: 'root' })  // singleton across app
export class UserService { }

@Injectable({ providedIn: 'any' })   // new instance per lazy-loaded module

// 2. Value provider
providers: [
  { provide: API_URL, useValue: 'https://api.example.com' },
  { provide: APP_CONFIG, useValue: { theme: 'dark', locale: 'vi' } },
]

// 3. Factory provider
providers: [{
  provide: LoggerService,
  useFactory: (config: AppConfig) => {
    return config.production
      ? new ProductionLoggerService()
      : new DevLoggerService();
  },
  deps: [APP_CONFIG],
}]

// 4. Existing provider (alias)
providers: [
  { provide: NewService, useClass: LegacyService },  // redirect
  { provide: AbstractService, useExisting: ConcreteService },  // alias (same instance)
]
```

### 6.2 InjectionToken (Type-safe DI)

```typescript
// Define token
export const API_URL = new InjectionToken<string>('API_URL', {
  providedIn: 'root',
  factory: () => 'http://localhost:3000',  // default value
});

export interface AppConfig {
  apiUrl: string;
  maxRetries: number;
  theme: 'light' | 'dark';
}
export const APP_CONFIG = new InjectionToken<AppConfig>('APP_CONFIG');

// Provide
providers: [
  { provide: API_URL, useValue: 'https://api.prod.example.com' },
  { provide: APP_CONFIG, useValue: { apiUrl: '...', maxRetries: 3, theme: 'dark' } },
]

// Inject
@Injectable()
export class ApiService {
  constructor(
    @Inject(API_URL) private apiUrl: string,
    @Inject(APP_CONFIG) private config: AppConfig,
  ) {}
}

// inject() function (Angular 14+ — no constructor needed)
@Injectable()
export class ModernService {
  private apiUrl = inject(API_URL);
  private config = inject(APP_CONFIG);
  private http = inject(HttpClient);
}
```

### 6.3 Hierarchical DI

```
Root Injector (providedIn: 'root')
  ├── Singleton, shared across app
  
Module Injector (providers in @NgModule or lazy routes)
  ├── New instance per module
  └── Lazy loaded modules get their own injector

Component Injector (providers in @Component)
  ├── New instance per component
  └── Available to component + its children
  
ElementInjector (viewProviders in @Component)
  └── Available only to component's template, NOT to content children
```

```typescript
// Component-level provider (new instance per component)
@Component({
  selector: 'app-form',
  providers: [FormStateService],  // each app-form gets its own FormStateService
})
export class FormComponent {
  constructor(private formState: FormStateService) {}  // this instance
}

// viewProviders: only template children, NOT projected content
@Component({
  selector: 'app-parent',
  viewProviders: [{ provide: LoggerService, useClass: ParentLogger }],
  template: `
    <app-child />     <!-- gets ParentLogger -->
    <ng-content />    <!-- projected content does NOT get ParentLogger -->
  `,
})
export class ParentComponent {}
```

### 6.4 Optional + Self + SkipSelf

```typescript
@Component({...})
export class MyComponent {
  constructor(
    @Optional() private optionalService: SomeService | null,  // null if not provided
    @Self() private localService: LocalService,               // only from THIS component's injector
    @SkipSelf() private parentService: SharedService,         // skip self, get from parent
    @Host() private hostService: HostService,                 // from host element injector
  ) {}
}
```

---

## 7. HTTP Client & Interceptors

### 7.1 HttpClient Setup (Standalone)

```typescript
// main.ts
bootstrapApplication(AppComponent, {
  providers: [
    provideHttpClient(
      withInterceptors([authInterceptor, loggingInterceptor]),
      withInterceptorsFromDi(),  // support class-based interceptors
    ),
  ],
});
```

### 7.2 HTTP Calls

```typescript
@Injectable({ providedIn: 'root' })
export class UserApiService {
  private readonly apiUrl = inject(API_URL);
  private readonly http = inject(HttpClient);

  getUsers(params: UserSearchParams): Observable<PageResponse<User>> {
    return this.http.get<PageResponse<User>>(`${this.apiUrl}/users`, {
      params: new HttpParams({ fromObject: params as Record<string, string> }),
    });
  }

  getUserById(id: number): Observable<User> {
    return this.http.get<User>(`${this.apiUrl}/users/${id}`);
  }

  createUser(payload: CreateUserRequest): Observable<User> {
    return this.http.post<User>(`${this.apiUrl}/users`, payload);
  }

  updateUser(id: number, payload: UpdateUserRequest): Observable<User> {
    return this.http.patch<User>(`${this.apiUrl}/users/${id}`, payload);
  }

  deleteUser(id: number): Observable<void> {
    return this.http.delete<void>(`${this.apiUrl}/users/${id}`);
  }

  uploadAvatar(userId: number, file: File): Observable<HttpEvent<{ url: string }>> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<{ url: string }>(`${this.apiUrl}/users/${userId}/avatar`, formData, {
      reportProgress: true,
      observe: 'events',   // observe: 'response' | 'events' | 'body'
    });
  }
}
```

### 7.3 Functional Interceptor (Angular 15+ — Recommended)

```typescript
// Auth interceptor: attach JWT token
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const token = authService.getToken();

  if (!token) return next(req);

  const authReq = req.clone({
    headers: req.headers.set('Authorization', `Bearer ${token}`),
  });

  return next(authReq);
};

// Logging interceptor: log requests/responses
export const loggingInterceptor: HttpInterceptorFn = (req, next) => {
  const start = Date.now();
  console.log(`[HTTP] ${req.method} ${req.url}`);

  return next(req).pipe(
    tap({
      next: (event) => {
        if (event instanceof HttpResponse) {
          const duration = Date.now() - start;
          console.log(`[HTTP] ${req.method} ${req.url} ${event.status} (${duration}ms)`);
        }
      },
      error: (err) => console.error(`[HTTP Error] ${req.url}`, err),
    }),
  );
};

// Error interceptor: global error handling + token refresh
export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  return next(req).pipe(
    catchError((error: HttpErrorResponse) => {
      if (error.status === 401) {
        // Try refresh token
        return authService.refreshToken().pipe(
          switchMap(token => {
            const retryReq = req.clone({
              headers: req.headers.set('Authorization', `Bearer ${token}`),
            });
            return next(retryReq);
          }),
          catchError(() => {
            authService.logout();
            router.navigate(['/login']);
            return throwError(() => error);
          }),
        );
      }

      if (error.status === 403) {
        router.navigate(['/forbidden']);
      }

      return throwError(() => error);
    }),
  );
};
```

---

## Ghi chú – Topics tiếp theo

- **Router**: lazy loading, CanActivate, Resolve → `angular_routing_forms.md`
- **Reactive Forms**: FormBuilder, FormArray, custom validators → `angular_routing_forms.md`
- **RxJS operators**: switchMap, combineLatest, error handling → `angular_rxjs.md`
- **NgRx**: Store, Effects, Selectors → `angular_state_management.md`
- **Signals**: signal(), computed(), effect() deep dive → `angular_state_management.md`
- **Keywords**: ComponentRef, ApplicationRef, EnvironmentInjector, Platform, Portals (CDK), createEnvironmentInjector, runInContext, PLATFORM_ID
