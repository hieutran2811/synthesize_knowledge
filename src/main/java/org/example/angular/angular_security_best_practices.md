# Angular Security & Best Practices

## Mục lục
1. [XSS & DomSanitizer](#1-xss--domsanitizer)
2. [CSRF Protection](#2-csrf-protection)
3. [Authentication – JWT + Refresh Token Flow](#3-authentication--jwt--refresh-token-flow)
4. [Route Guards & Authorization](#4-route-guards--authorization)
5. [Content Security Policy (CSP)](#5-content-security-policy-csp)
6. [Angular Security Checklist](#6-angular-security-checklist)

---

## 1. XSS & DomSanitizer

### 1.1 Angular tự động escape

```typescript
// Angular escapes interpolation và property binding tự động
@Component({
  template: `
    <!-- ✅ An toàn: Angular escapes HTML -->
    <p>{{ userInput }}</p>
    <p [textContent]="userInput"></p>
    
    <!-- ✅ An toàn: Angular xử lý attribute binding -->
    <a [href]="userUrl">Link</a>      <!-- sanitizes javascript: URLs -->
    <img [src]="imageUrl" />           <!-- sanitizes data: URLs -->
  `,
})
export class SafeComponent {
  userInput = '<script>alert("xss")</script>';
  // → rendered as literal text, not executed
}
```

### 1.2 DomSanitizer — Khi cần render HTML động

```typescript
import { DomSanitizer, SafeHtml, SafeUrl, SafeStyle, SafeResourceUrl } from '@angular/platform-browser';

@Component({
  template: `
    <!-- innerHTML binding — NGUY HIỂM nếu không sanitize -->
    <div [innerHTML]="trustedHtml"></div>
    
    <!-- Safe URL for <a href> -->
    <a [href]="trustedUrl">External Link</a>
    
    <!-- Safe ResourceUrl for iframe/script src -->
    <iframe [src]="trustedResourceUrl"></iframe>
    
    <!-- Safe Style -->
    <div [style]="trustedStyle"></div>
  `,
})
export class RichContentComponent {
  private sanitizer = inject(DomSanitizer);

  // ✅ Sanitize HTML — removes dangerous tags/attributes
  trustedHtml: SafeHtml = this.sanitizer.sanitize(
    SecurityContext.HTML,
    '<p>Safe <b>content</b> <script>evil()</script></p>'
  )!;
  // → '<p>Safe <b>content</b></p>'  (script removed)

  // ✅ bypassSecurityTrust — ONLY when you fully trust the content source
  trustedDynamicHtml: SafeHtml;
  trustedUrl: SafeUrl;
  trustedResourceUrl: SafeResourceUrl;

  loadTrustedContent(htmlFromTrustedCmsSystem: string): void {
    // Only bypass if content is from YOUR controlled backend, never from user input
    this.trustedDynamicHtml = this.sanitizer.bypassSecurityTrustHtml(htmlFromTrustedCmsSystem);
    this.trustedUrl = this.sanitizer.bypassSecurityTrustUrl('https://trusted-partner.com');
    this.trustedResourceUrl = this.sanitizer.bypassSecurityTrustResourceUrl('https://maps.trusted.com/embed');
  }
}

// ❌ NEVER do this with user input
this.trustedHtml = this.sanitizer.bypassSecurityTrustHtml(userTypedContent);  // XSS!
```

### 1.3 Renderer2 — Thay vì trực tiếp thao tác DOM

```typescript
// ❌ Nguy hiểm: trực tiếp thao tác DOM
@Component({...})
export class BadComponent {
  constructor(private el: ElementRef) {}

  highlight(): void {
    this.el.nativeElement.innerHTML = '<b>Highlighted!</b>';  // XSS risk!
  }
}

// ✅ An toàn: dùng Renderer2
@Component({...})
export class SafeComponent {
  constructor(
    private el: ElementRef,
    private renderer: Renderer2,
  ) {}

  highlight(): void {
    const b = this.renderer.createElement('b');
    const text = this.renderer.createText('Highlighted!');
    this.renderer.appendChild(b, text);
    this.renderer.appendChild(this.el.nativeElement, b);
  }

  setClass(className: string): void {
    this.renderer.addClass(this.el.nativeElement, className);
  }

  setAttribute(name: string, value: string): void {
    this.renderer.setAttribute(this.el.nativeElement, name, value);
  }
}
```

---

## 2. CSRF Protection

```typescript
// Angular HttpClient tự động đọc XSRF-TOKEN cookie
// và gửi X-XSRF-TOKEN header cho non-GET requests

// main.ts
bootstrapApplication(AppComponent, {
  providers: [
    provideHttpClient(
      withXsrfConfiguration({
        cookieName: 'XSRF-TOKEN',    // cookie name server sets
        headerName: 'X-XSRF-TOKEN', // header name Angular sends
      }),
    ),
  ],
});

// Server (Node/Express) phải set cookie:
// res.cookie('XSRF-TOKEN', csrfToken, { httpOnly: false, sameSite: 'strict' });
// 'httpOnly: false' — Angular JavaScript PHẢI đọc được cookie

// Server validates X-XSRF-TOKEN header on mutations (POST/PUT/DELETE)
// If cookie != header → 403 Forbidden
```

---

## 3. Authentication – JWT + Refresh Token Flow

### 3.1 Auth Service

```typescript
// services/auth.service.ts
@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly ACCESS_TOKEN_KEY = 'access_token';
  // ⚠️ localStorage: vulnerable to XSS — prefer HttpOnly cookie for refresh token
  // Access token in memory or sessionStorage is safer

  private currentUser$ = new BehaviorSubject<User | null>(null);
  readonly user$ = this.currentUser$.asObservable();
  readonly isAuthenticated$ = this.user$.pipe(map(u => u !== null));

  private http = inject(HttpClient);
  private router = inject(Router);

  login(credentials: LoginRequest): Observable<void> {
    return this.http.post<AuthResponse>('/api/auth/login', credentials).pipe(
      tap(response => {
        this.storeToken(response.accessToken);
        this.currentUser$.next(response.user);
      }),
      map(() => void 0),
    );
  }

  logout(): void {
    this.http.post('/api/auth/logout', {}).subscribe();  // invalidate server session
    this.clearToken();
    this.currentUser$.next(null);
    this.router.navigate(['/login']);
  }

  refreshToken(): Observable<string> {
    return this.http.post<{ accessToken: string }>('/api/auth/refresh', {}, {
      withCredentials: true,  // sends HttpOnly refresh token cookie
    }).pipe(
      tap(({ accessToken }) => this.storeToken(accessToken)),
      map(({ accessToken }) => accessToken),
    );
  }

  getToken(): string | null {
    return sessionStorage.getItem(this.ACCESS_TOKEN_KEY);
  }

  isTokenExpired(): boolean {
    const token = this.getToken();
    if (!token) return true;
    const payload = JSON.parse(atob(token.split('.')[1]));
    return Date.now() >= payload.exp * 1000;
  }

  hasRole(role: string): boolean {
    return this.currentUser$.getValue()?.roles?.includes(role) ?? false;
  }

  private storeToken(token: string): void {
    sessionStorage.setItem(this.ACCESS_TOKEN_KEY, token);
  }

  private clearToken(): void {
    sessionStorage.removeItem(this.ACCESS_TOKEN_KEY);
  }
}
```

### 3.2 Auth Interceptor with Token Refresh

```typescript
// interceptors/auth.interceptor.ts
let isRefreshing = false;
let refreshTokenSubject = new BehaviorSubject<string | null>(null);

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const authService = inject(AuthService);

  // Skip auth for public endpoints
  if (req.url.includes('/api/auth/')) return next(req);

  const token = authService.getToken();
  const authReq = token ? addToken(req, token) : req;

  return next(authReq).pipe(
    catchError((error: HttpErrorResponse) => {
      if (error.status !== 401) return throwError(() => error);

      if (isRefreshing) {
        // Wait for current refresh to complete
        return refreshTokenSubject.pipe(
          filter(token => token !== null),
          take(1),
          switchMap(token => next(addToken(req, token!))),
        );
      }

      isRefreshing = true;
      refreshTokenSubject.next(null);

      return authService.refreshToken().pipe(
        switchMap(newToken => {
          isRefreshing = false;
          refreshTokenSubject.next(newToken);
          return next(addToken(req, newToken));
        }),
        catchError(refreshError => {
          isRefreshing = false;
          authService.logout();
          return throwError(() => refreshError);
        }),
      );
    }),
  );
};

function addToken(req: HttpRequest<unknown>, token: string): HttpRequest<unknown> {
  return req.clone({
    headers: req.headers.set('Authorization', `Bearer ${token}`),
  });
}
```

---

## 4. Route Guards & Authorization

```typescript
// guards/auth.guard.ts
export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (authService.getToken() && !authService.isTokenExpired()) {
    return true;
  }

  return router.createUrlTree(['/login'], {
    queryParams: { returnUrl: state.url },
  });
};

// guards/role.guard.ts
export const roleGuard = (...requiredRoles: string[]): CanActivateFn =>
  (route, state) => {
    const authService = inject(AuthService);
    const router = inject(Router);

    const hasRole = requiredRoles.some(role => authService.hasRole(role));
    if (hasRole) return true;

    return router.createUrlTree(['/forbidden']);
  };

// guards/unsaved-changes.guard.ts
export const unsavedChangesGuard: CanDeactivateFn<{ hasUnsavedChanges(): boolean }> =
  (component) => {
    if (!component.hasUnsavedChanges()) return true;
    return confirm('You have unsaved changes. Leave anyway?');
  };

// Route config
const routes: Routes = [
  {
    path: 'dashboard',
    canActivate: [authGuard],
    loadComponent: () => import('./dashboard.component').then(m => m.DashboardComponent),
  },
  {
    path: 'admin',
    canActivate: [authGuard, roleGuard('ADMIN', 'SUPER_ADMIN')],
    canActivateChild: [authGuard],
    children: [
      { path: 'users', component: AdminUsersComponent },
      { path: 'settings', component: AdminSettingsComponent },
    ],
  },
  {
    path: 'edit/:id',
    canDeactivate: [unsavedChangesGuard],
    component: EditComponent,
  },
];
```

---

## 5. Content Security Policy (CSP)

```typescript
// Angular meta service để set CSP meta tag (fallback — prefer HTTP header)
@Injectable({ providedIn: 'root' })
export class CspService {
  private meta = inject(Meta);

  setCsp(): void {
    this.meta.addTag({
      'http-equiv': 'Content-Security-Policy',
      content: [
        "default-src 'self'",
        "script-src 'self'",                         // no inline scripts
        "style-src 'self' 'unsafe-inline'",          // Angular needs inline styles
        "img-src 'self' data: https:",               // allow https images
        "font-src 'self' https://fonts.gstatic.com",
        "connect-src 'self' https://api.example.com",
        "frame-src 'none'",                          // no iframes
        "object-src 'none'",                         // no plugins
        "base-uri 'self'",
      ].join('; '),
    });
  }
}
```

```nginx
# Preferred: set CSP via server header (nginx)
add_header Content-Security-Policy "
  default-src 'self';
  script-src 'self' 'nonce-{NONCE}';
  style-src 'self' 'unsafe-inline';
  img-src 'self' data: https:;
  connect-src 'self' https://api.example.com;
  frame-ancestors 'none';
  base-uri 'self';
" always;

add_header X-Frame-Options "DENY" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
```

---

## 6. Angular Security Checklist

### 6.1 Input Handling

```typescript
// ✅ Never trust user input — sanitize before rendering HTML
// ✅ Use Angular template binding (not innerHTML directly)
// ✅ Validate on both client AND server
// ✅ Use Reactive Forms with validators
// ❌ Never eval() or new Function() with user data
// ❌ Never use document.write()
```

### 6.2 Token & Session Security

```typescript
// ✅ Best: HttpOnly cookies for refresh tokens (not accessible to JS → XSS-safe)
// ✅ Access tokens in memory (not localStorage)
// ✅ Short-lived access tokens (15min), long-lived refresh tokens
// ✅ Rotate refresh tokens on each use
// ✅ Invalidate tokens on logout (server-side blacklist)
// ❌ Avoid localStorage for sensitive tokens if XSS is a risk
// ❌ Never log tokens

// Token storage comparison:
// localStorage:   persistent, accessible to JS → XSS risk
// sessionStorage: session-only, accessible to JS → XSS risk
// Memory (variable): lost on refresh, safe from XSS
// HttpOnly cookie: server-controlled, safe from XSS, CSRF risk (mitigate with SameSite)
```

### 6.3 HTTP Security

```typescript
// ✅ Always use HTTPS (no mixed content)
// ✅ HSTS header on server
// ✅ Angular HttpClient withXsrfConfiguration() for CSRF
// ✅ SameSite=Strict|Lax on cookies
// ✅ withCredentials: true only for trusted same-origin APIs
// ❌ Never log full request/response with tokens in interceptor
```

### 6.4 Dependency Security

```bash
# Audit dependencies regularly
npm audit
ng update --check

# Fix vulnerabilities
npm audit fix
ng update @angular/core @angular/cli

# Check for outdated packages
npm outdated
```

---

## Summary: Trade-offs

| Security Measure | Protection | Cost |
|-----------------|-----------|------|
| Angular template binding | XSS via interpolation | Free (default) |
| DomSanitizer.sanitize() | XSS via innerHTML | Strips dangerous HTML |
| bypassSecurityTrust*() | None (bypass!) | Use only for trusted content |
| Renderer2 | DOM manipulation XSS | Slightly more verbose |
| HttpOnly cookies | Token theft via XSS | CSRF must be mitigated |
| XSRF token | CSRF | Double-submit cookie pattern |
| CSP headers | XSS script execution | Can break inline scripts |
| Route guards | Unauthorized navigation | Must also validate on server |
| JWT short expiry + refresh | Token theft window | More HTTP calls |

---

## Ghi chú – Keywords tiếp theo

- **Angular CDK**: DragDrop, Overlay, Portal, VirtualScroll, Clipboard, A11y (Accessibility)
- **Angular Material**: Component library, theming (tokens), MDC-based components
- **Micro-frontends**: Module Federation (Webpack), Angular Elements (Custom Elements)
- **Advanced Patterns**: NX monorepo, Feature Flags, Dynamic remote config, i18n (@angular/localize)
- **Keywords**: SecurityContext, SafeValue, TrustedTypes API, Sanitizer, HttpClientXsrfModule, withNoHttpTransferCache, withFetch (HttpClient), APP_ID (SSR), TransferHttpCacheModule, DOCUMENT injection token, ɵɵsanitizeHtml (internal), Angular DevTools Profiler
