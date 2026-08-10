---
title: "Angular HTTP Communication – HttpClient Deep Dive"
topic: angular
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Angular HTTP Communication – HttpClient Deep Dive

> Thuật ngữ: [Glossary](glossary.md).

> Bổ trợ cho [angular_security_best_practices.md](angular_security_best_practices.md) (auth/refresh token interceptor) và [angular_rxjs.md](angular_rxjs.md) (operators). File này đi sâu vào HttpClient, functional interceptors, retry, caching, upload/download, TransferState.

## Mục lục
1. [Setup: provideHttpClient (What & How)](#1-setup-providehttpclient)
2. [Request cơ bản & typed response](#2-request-cơ-bản--typed-response)
3. [HttpParams, Headers, observe & responseType](#3-httpparams-headers-observe--responsetype)
4. [Error handling & Retry](#4-error-handling--retry)
5. [Functional Interceptors (Angular 15+)](#5-functional-interceptors)
6. [HttpContext – truyền metadata cho interceptor](#6-httpcontext)
7. [Caching](#7-caching)
8. [Upload & Download với progress](#8-upload--download)
9. [Cancellation](#9-cancellation)
10. [SSR & TransferState](#10-ssr--transferstate)
11. [So sánh & Trade-offs](#11-so-sánh--trade-offs)

---

## 1. Setup: provideHttpClient

### What – HttpClient là gì?
`HttpClient` (`@angular/common/http`) là service gọi HTTP, trả về **Observable** (cold → phải subscribe mới chạy, mỗi subscribe = 1 request). Tích hợp interceptor, typed response, testing.

### How – cấu hình hiện đại (standalone, Angular 15+)
```ts
// app.config.ts
export const appConfig: ApplicationConfig = {
  providers: [
    provideHttpClient(
      withFetch(),                        // dùng Fetch API thay XHR (tốt cho SSR, streaming)
      withInterceptors([authInterceptor, errorInterceptor, loggingInterceptor]),
    ),
  ],
};
```
> `HttpClientModule` (NgModule) đã **deprecated** (Angular 18) → dùng `provideHttpClient`. `withFetch()` khuyến nghị cho app mới + SSR.

---

## 2. Request cơ bản & typed response

```ts
@Injectable({ providedIn: 'root' })
export class UserApi {
  private http = inject(HttpClient);                    // inject() thay constructor

  getUsers(): Observable<User[]> {
    return this.http.get<User[]>('/api/users');         // typed
  }
  create(u: CreateUser): Observable<User> {
    return this.http.post<User>('/api/users', u);
  }
  update(id: number, u: Partial<User>) {
    return this.http.patch<User>(`/api/users/${id}`, u);
  }
  remove(id: number) { return this.http.delete<void>(`/api/users/${id}`); }
}
```
> ⚠️ `get<User[]>()` chỉ là **type assertion lúc compile**, KHÔNG validate runtime. Dữ liệu sai schema vẫn lọt → cần validate (zod) nếu API không tin cậy.

Dùng trong component (ưu tiên `async` pipe hoặc `toSignal`, tránh subscribe thủ công gây leak):
```ts
users$ = inject(UserApi).getUsers();              // template: *ngFor="let u of users$ | async"
users = toSignal(inject(UserApi).getUsers(), { initialValue: [] }); // signal (xem signals_zoneless)
```

---

## 3. HttpParams, Headers, observe & responseType

```ts
// Query params (immutable — mỗi set trả instance mới)
const params = new HttpParams().set('page', 1).set('size', 20).append('tag', 'a');
this.http.get<Page<User>>('/api/users', { params });   // ?page=1&size=20&tag=a

// Hoặc object literal (Angular 15+)
this.http.get('/api/users', { params: { page: 1, q: 'an' } });

// observe: lấy full response (status, headers) thay vì chỉ body
this.http.get<User>('/api/u/1', { observe: 'response' })  // HttpResponse<User>
    .subscribe(res => { res.status; res.headers.get('X-Total'); res.body; });

// responseType cho non-JSON
this.http.get('/file.csv', { responseType: 'text' });
this.http.get('/img.png', { responseType: 'blob' });
```

---

## 4. Error handling & Retry

```ts
this.http.get<User[]>('/api/users').pipe(
  retry({ count: 3, delay: (err, n) => timer(n * 1000) }),   // retry exponential backoff
  catchError((err: HttpErrorResponse) => {
    if (err.status === 0)        return throwError(() => new Error('Network/CORS'));
    if (err.status === 404)      return of([]);              // fallback rỗng
    if (err.status >= 500)       return throwError(() => err);
    return throwError(() => err);
  }),
);
```
- `HttpErrorResponse`: `status` (0 = network/CORS/abort), `error` (body lỗi), `message`, `url`.
- `retry({ delay })` chỉ nên cho lỗi tạm thời (5xx, network), KHÔNG retry 4xx (client sai).
- Xử lý lỗi tập trung → đặt trong **error interceptor** (mục 5). Liên hệ operators ở [angular_rxjs.md](angular_rxjs.md).

---

## 5. Functional Interceptors

Angular 15+ dùng **function** interceptor (`HttpInterceptorFn`) thay class — gọn, dễ test, dùng `inject()`.

```ts
// auth.interceptor.ts — gắn token
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const token = inject(AuthService).token();
  if (!token || req.context.get(SKIP_AUTH)) return next(req);
  const authed = req.clone({ setHeaders: { Authorization: `Bearer ${token}` } });
  return next(authed);
};

// error.interceptor.ts — xử lý lỗi tập trung + refresh token (401)
export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  return next(req).pipe(
    catchError((err: HttpErrorResponse) => {
      if (err.status === 401) return auth.refresh().pipe(switchMap(() => next(req))); // retry sau refresh
      inject(ToastService).error(err.message);
      return throwError(() => err);
    }),
  );
};

// loading.interceptor.ts — bật/tắt spinner toàn cục
export const loadingInterceptor: HttpInterceptorFn = (req, next) => {
  const loading = inject(LoadingService);
  loading.start();
  return next(req).pipe(finalize(() => loading.stop()));
};
```
> Interceptor chạy theo **thứ tự khai báo** cho request, **ngược lại** cho response. Chi tiết auth + refresh token race condition (queue request khi đang refresh): [angular_security_best_practices.md](angular_security_best_practices.md).
> Class interceptor cũ (`HttpInterceptor` + `HTTP_INTERCEPTORS`) vẫn dùng được qua `withInterceptorsFromDi()`.

---

## 6. HttpContext

`HttpContext` truyền **metadata** từ nơi gọi tới interceptor (vd: bỏ auth, bật cache) mà không đụng header.
```ts
export const SKIP_AUTH = new HttpContextToken(() => false);
export const CACHEABLE = new HttpContextToken(() => false);

// Gọi: đánh dấu request này bỏ auth + cho cache
this.http.get('/api/public', { context: new HttpContext().set(SKIP_AUTH, true).set(CACHEABLE, true) });

// Interceptor đọc: req.context.get(SKIP_AUTH)
```

---

## 7. Caching

### Cache trong stream (chia sẻ 1 response cho nhiều subscriber)
```ts
private config$ = this.http.get<Config>('/api/config').pipe(
  shareReplay({ bufferSize: 1, refCount: false }),   // gọi 1 lần, cache, mọi subscriber dùng chung
);
```

### Cache interceptor (theo URL, có TTL)
```ts
export const cacheInterceptor: HttpInterceptorFn = (req, next) => {
  if (req.method !== 'GET' || !req.context.get(CACHEABLE)) return next(req);
  const cache = inject(HttpCacheService);
  const hit = cache.get(req.urlWithParams);
  if (hit) return of(hit);                                  // trả từ cache, không gọi mạng
  return next(req).pipe(tap(res => { if (res instanceof HttpResponse) cache.set(req.urlWithParams, res); }));
};
```
> Cân nhắc invalidation (xóa cache khi POST/PUT/DELETE) và TTL. `resource()`/`rxResource` (signals) cũng là hướng quản lý fetch hiện đại — xem [angular_signals_zoneless.md](angular_signals_zoneless.md).

---

## 8. Upload & Download

### Upload file + theo dõi progress
```ts
upload(file: File) {
  const form = new FormData();
  form.append('file', file, file.name);
  const req = new HttpRequest('POST', '/api/upload', form, { reportProgress: true });
  return this.http.request(req).pipe(
    map(event => {
      if (event.type === HttpEventType.UploadProgress)
        return { progress: Math.round(100 * event.loaded / (event.total ?? 1)) };
      if (event.type === HttpEventType.Response) return { done: true, body: event.body };
      return { progress: 0 };
    }),
  );
}
```

### Download blob
```ts
this.http.get('/api/report', { responseType: 'blob', observe: 'response' }).subscribe(res => {
  const url = URL.createObjectURL(res.body!);
  const a = document.createElement('a'); a.href = url; a.download = 'report.pdf'; a.click();
  URL.revokeObjectURL(url);
});
```

---

## 9. Cancellation

HttpClient Observable **tự hủy request** khi unsubscribe. Kết hợp `switchMap` để hủy request cũ (search-as-you-type):
```ts
this.searchControl.valueChanges.pipe(
  debounceTime(300), distinctUntilChanged(),
  switchMap(q => this.http.get<Result[]>('/api/search', { params: { q } })), // hủy request cũ
).subscribe(...);
```
> `switchMap` = hủy cũ; `mergeMap` = song song; `concatMap` = tuần tự; `exhaustMap` = bỏ qua khi đang chạy. Chi tiết: [angular_rxjs.md](angular_rxjs.md).

---

## 10. SSR & TransferState

Với Server-Side Rendering, nếu không xử lý → server fetch API, render HTML, rồi **client fetch lại y hệt** (double fetch, nháy màn hình). **TransferState** giải quyết: server nhúng kết quả vào HTML, client dùng lại.

```ts
// Bật tự động cache HTTP transfer khi hydration
bootstrapApplication(App, {
  providers: [
    provideClientHydration(withHttpTransferCacheOptions({ includePostRequests: false })),
    provideHttpClient(withFetch()),     // withFetch bắt buộc để transfer cache hoạt động tốt
  ],
});
```
> Server GET requests được cache và chuyển sang client tự động → client không gọi lại. Liên hệ SSR/hydration ở [angular_performance_production.md](angular_performance_production.md).

---

## 11. So sánh & Trade-offs

| | HttpClient (Observable) | fetch() thuần | axios |
|--|-------------------------|---------------|-------|
| Tích hợp Angular | Native (interceptor, DI, testing) | Không | Không |
| Cancel | Tự động (unsubscribe) | AbortController thủ công | CancelToken |
| Retry/operators | RxJS sẵn | Tự code | Hạn chế |
| Testing | HttpTestingController | Mock thủ công | Mock thủ công |
| Typed | Có (assertion) | Tự cast | Tự cast |

### Trade-offs
- (+) Interceptor tập trung (auth, error, loading, cache), cancel tự động, test dễ, hợp RxJS.
- (−) Observable cold dễ gây bug "quên subscribe" hoặc subscribe nhiều lần → request lặp; ưu tiên `async` pipe/`toSignal`.
- (−) Typed chỉ compile-time; cần validate runtime nếu API không kiểm soát.
- ⚠️ **Memory leak**: subscribe thủ công không unsubscribe → dùng `async` pipe, `takeUntilDestroyed()`, hoặc `toSignal`.

---

## Ghi chú – Topics tiếp theo

- Liên quan: [angular_security_best_practices.md](angular_security_best_practices.md) (auth/refresh, XSRF, withXsrfConfiguration), [angular_rxjs.md](angular_rxjs.md) (switchMap/retry/shareReplay), [angular_signals_zoneless.md](angular_signals_zoneless.md) (rxResource/toSignal), [angular_performance_production.md](angular_performance_production.md) (SSR hydration), [angular_testing.md](angular_testing.md) (HttpTestingController).
- **Keywords**: `withInterceptorsFromDi`, `withXsrfConfiguration`, `withRequestsMadeViaParent`, `HttpResponse`/`HttpHeaderResponse`, `HttpEventType`, `HttpStatusCode` enum, `provideHttpClientTesting`, `HttpParams` `fromObject`, `withJsonpSupport`, RFC `withNoXsrfProtection`.

*Cập nhật lần cuối: 2026-06-04*
