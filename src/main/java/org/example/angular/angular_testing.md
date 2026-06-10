# Angular Testing – Deep Dive (Unit, HTTP, Harness, Marble, E2E)

> Bổ trợ cho [angular_performance_production.md](angular_performance_production.md) (đã chạm TestBed/Cypress). File này đi sâu: TestBed, ComponentFixture, spies, HttpTestingController, CDK Harness, marble testing, async, signals, E2E.

## Mục lục
1. [Testing pyramid & công cụ (What & Why)](#1-testing-pyramid--công-cụ)
2. [TestBed & ComponentFixture](#2-testbed--componentfixture)
3. [Service & Spies/Mocks](#3-service--spiesmocks)
4. [HttpTestingController](#4-httptestingcontroller)
5. [Async: fakeAsync/tick & waitForAsync](#5-async-fakeasynctick--waitforasync)
6. [CDK Component Harnesses](#6-cdk-component-harnesses)
7. [Marble Testing (RxJS)](#7-marble-testing)
8. [Testing Signals & Zoneless](#8-testing-signals--zoneless)
9. [E2E: Playwright & Cypress](#9-e2e-playwright--cypress)
10. [Best Practices & Trade-offs](#10-best-practices--trade-offs)

---

## 1. Testing pyramid & công cụ

```
        ▲  E2E (ít, chậm, thật)        Playwright / Cypress
        │  Integration (component + DOM)  TestBed + Harness
        │  Unit (nhiều, nhanh)          Jasmine/Jest – service, pipe, pure logic
```

| Công cụ | Vai trò | Ghi chú |
|---------|---------|---------|
| **Jasmine** | Test framework (describe/it/expect) | Mặc định Angular |
| **Karma** | Test runner (chạy trong browser) | **Deprecated** → Angular chuyển sang Web Test Runner / Vitest |
| **Jest** | Runner + framework (jsdom, nhanh) | Phổ biến, snapshot, không cần browser |
| **Vitest** | Runner mới (Angular 20+ hỗ trợ) | Nhanh, ESM, thay Karma |
| **TestBed** | Tạo môi trường Angular (DI, CD) | Của `@angular/core/testing` |
| **Playwright / Cypress** | E2E thật trên browser | Playwright đang được ưu tiên |

---

## 2. TestBed & ComponentFixture

`TestBed` dựng một Angular module thu nhỏ để test component/service trong môi trường DI thật.

```ts
describe('CounterComponent', () => {
  let fixture: ComponentFixture<CounterComponent>;
  let component: CounterComponent;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [CounterComponent],                 // standalone → import trực tiếp
      providers: [{ provide: UserService, useValue: mockUserService }],
    }).compileComponents();

    fixture = TestBed.createComponent(CounterComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();                       // trigger CD + ngOnInit
  });

  it('tăng count khi click', () => {
    const btn = fixture.nativeElement.querySelector('button.inc') as HTMLButtonElement;
    btn.click();
    fixture.detectChanges();
    expect(fixture.nativeElement.querySelector('.count').textContent).toContain('1');
  });

  it('dùng DebugElement + By.css', () => {
    const el = fixture.debugElement.query(By.css('.count'));
    expect(el.nativeElement.textContent).toContain('0');
  });
});
```
- `fixture.detectChanges()`: chạy change detection (cần gọi thủ công sau khi đổi state).
- `nativeElement` (DOM thật) vs `debugElement` (wrapper Angular, query bằng `By.css`/`By.directive`).
- Set input: `fixture.componentRef.setInput('name', 'An')` (cho signal input/`@Input`).

---

## 3. Service & Spies/Mocks

```ts
// Mock dependency bằng spy object
const apiSpy = jasmine.createSpyObj<UserApi>('UserApi', ['getUsers']);
apiSpy.getUsers.and.returnValue(of([{ id: 1, name: 'An' }]));   // trả Observable giả

TestBed.configureTestingModule({ providers: [{ provide: UserApi, useValue: apiSpy }] });

it('load users', () => {
  const svc = TestBed.inject(UserFacade);
  svc.load();
  expect(apiSpy.getUsers).toHaveBeenCalledTimes(1);
});

// spyOn method có sẵn
spyOn(console, 'error');
// Jest: jest.fn(), jest.spyOn(obj, 'method').mockReturnValue(...)
```
> Service thuần (không DOM) → test trực tiếp, **không cần TestBed** (nhanh hơn): `new MyService(mockDep)`.

---

## 4. HttpTestingController

Test service gọi HTTP **không cần backend thật** — chặn request, kiểm tra, trả response giả.

```ts
describe('UserApi', () => {
  let api: UserApi;
  let httpMock: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [UserApi, provideHttpClient(), provideHttpClientTesting()],  // Angular 15+
    });
    api = TestBed.inject(UserApi);
    httpMock = TestBed.inject(HttpTestingController);
  });
  afterEach(() => httpMock.verify());        // đảm bảo không còn request thừa

  it('GET /api/users', () => {
    let result: User[] | undefined;
    api.getUsers().subscribe(r => result = r);

    const req = httpMock.expectOne('/api/users');   // có đúng 1 request
    expect(req.request.method).toBe('GET');
    req.flush([{ id: 1, name: 'An' }]);             // trả response giả

    expect(result).toEqual([{ id: 1, name: 'An' }]);
  });

  it('xử lý lỗi 500', () => {
    let err: HttpErrorResponse | undefined;
    api.getUsers().subscribe({ error: e => err = e });
    httpMock.expectOne('/api/users').flush('fail', { status: 500, statusText: 'Server Error' });
    expect(err?.status).toBe(500);
  });
});
```
> `expectOne`/`match` (theo predicate), `flush` (trả body), `error` (trả lỗi mạng), `verify` (không có request chưa xử lý). Liên hệ [angular_http_communication.md](angular_http_communication.md).

---

## 5. Async: fakeAsync/tick & waitForAsync

```ts
// fakeAsync: kiểm soát thời gian ảo, tick() đẩy timer (setTimeout, debounceTime)
it('debounce search', fakeAsync(() => {
  component.search('an');
  tick(300);                          // đẩy 300ms → debounceTime hoàn tất
  expect(component.results().length).toBeGreaterThan(0);
  flush();                            // xả mọi timer còn lại
}));

// waitForAsync: chờ Promise/microtask hoàn tất
it('async init', waitForAsync(() => {
  fixture.whenStable().then(() => expect(component.ready).toBeTrue());
}));
```
- `fakeAsync` + `tick(ms)`/`flush()`: test timer/debounce **đồng bộ, xác định** (không chờ thật).
- `flushMicrotasks()`: xả Promise.
- ⚠️ Lỗi "1 timer(s) still in the queue" → còn timer chưa tick → dùng `flush()`.

---

## 6. CDK Component Harnesses

**Harness** là API test trừu tượng cho component (đặc biệt Angular Material): test **hành vi** thay vì cấu trúc DOM → test không vỡ khi DOM nội bộ Material đổi.

```ts
import { HarnessLoader } from '@angular/cdk/testing';
import { TestbedHarnessEnvironment } from '@angular/cdk/testing/testbed';
import { MatButtonHarness } from '@angular/material/button/testing';

it('click nút submit qua harness', async () => {
  const loader: HarnessLoader = TestbedHarnessEnvironment.loader(fixture);
  const button = await loader.getHarness(MatButtonHarness.with({ text: 'Submit' }));
  await button.click();
  expect(component.submitted()).toBeTrue();
});
```
> Tự viết harness bằng `ComponentHarness` cho component riêng. Liên hệ [angular_material_cdk_a11y.md](angular_material_cdk_a11y.md).

---

## 7. Marble Testing

Test logic RxJS phức tạp bằng "marble diagram" — biểu diễn thời gian dạng chuỗi ký tự.

```ts
import { TestScheduler } from 'rxjs/testing';

it('map x2', () => {
  const scheduler = new TestScheduler((actual, expected) => expect(actual).toEqual(expected));
  scheduler.run(({ cold, expectObservable }) => {
    const source$ = cold('-a-b-c|', { a: 1, b: 2, c: 3 });
    const result$ = source$.pipe(map(x => x * 2));
    expectObservable(result$).toBe('-a-b-c|', { a: 2, b: 4, c: 6 });
  });
});
```
- `-` = 1 frame thời gian; chữ = giá trị emit; `|` = complete; `#` = error; `()` = đồng thời.
- `cold` (mỗi subscribe phát lại từ đầu) vs `hot` (đang phát). Hữu ích test `debounceTime`, `switchMap`, retry.

---

## 8. Testing Signals & Zoneless

```ts
it('computed phái sinh đúng', () => {
  const count = signal(2);
  const doubled = computed(() => count() * 2);
  expect(doubled()).toBe(4);
  count.set(5);
  expect(doubled()).toBe(10);            // đọc signal đồng bộ → test thẳng, không cần CD
});

// effect cần injection context + flush
it('effect chạy', () => {
  TestBed.runInInjectionContext(() => {
    const log: number[] = [];
    const s = signal(0);
    effect(() => log.push(s()));
    TestBed.flushEffects();              // (hoặc tick) để effect chạy
    s.set(1); TestBed.flushEffects();
    expect(log).toEqual([0, 1]);
  });
});
```
> Signal đồng bộ → test rất dễ (đọc giá trị trực tiếp). Component zoneless: gọi `fixture.detectChanges()` vẫn hoạt động. Liên hệ [angular_signals_zoneless.md](angular_signals_zoneless.md).

---

## 9. E2E: Playwright & Cypress

```ts
// Playwright (đang được Angular ưu tiên, nhanh, đa browser, auto-wait)
import { test, expect } from '@playwright/test';
test('login flow', async ({ page }) => {
  await page.goto('/login');
  await page.getByLabel('Email').fill('a@b.com');
  await page.getByRole('button', { name: 'Login' }).click();
  await expect(page).toHaveURL('/dashboard');
  await expect(page.getByText('Welcome')).toBeVisible();
});
```
```ts
// Cypress (DX tốt, time-travel debugging)
it('login', () => {
  cy.visit('/login');
  cy.get('[data-testid=email]').type('a@b.com');
  cy.contains('button', 'Login').click();
  cy.url().should('include', '/dashboard');
});
```

| | Playwright | Cypress |
|--|-----------|---------|
| Browser | Chromium/Firefox/WebKit | Chromium chính (Firefox/WebKit hạn chế) |
| Kiến trúc | Ngoài browser (nhanh, parallel) | Trong browser (debug trực quan) |
| Auto-wait | Mạnh | Có |
| Angular default mới | **Ưu tiên** | Vẫn phổ biến |

---

## 10. Best Practices & Trade-offs

- Dùng **`data-testid`** thay class/text để query (ổn định khi UI đổi).
- Test **hành vi** (output, DOM hiển thị), không test chi tiết nội bộ → dùng Harness cho Material.
- Service thuần → test không TestBed; component/DI → TestBed.
- `httpMock.verify()` + `afterEach` để bắt request thừa.
- Tránh `detectChanges()` thừa; với signals/zoneless test đồng bộ dễ hơn.
- E2E ít nhưng phủ critical flow; unit nhiều cho logic.

### Trade-offs
- (+) TestBed mô phỏng môi trường thật (DI, CD), HttpTestingController test HTTP không backend, Harness chống brittle, marble test RxJS chính xác.
- (−) TestBed chậm hơn unit thuần; Karma deprecated (cần migrate Jest/Vitest); E2E chậm, flaky nếu không auto-wait.
- (−) Over-mocking → test "xanh" nhưng không phản ánh thật; cân bằng theo pyramid.

---

## Ghi chú – Topics tiếp theo

- Liên quan: [angular_performance_production.md](angular_performance_production.md) (testing tổng quan, coverage), [angular_http_communication.md](angular_http_communication.md) (mock HTTP), [angular_signals_zoneless.md](angular_signals_zoneless.md) (test signals), [angular_material_cdk_a11y.md](angular_material_cdk_a11y.md) (Harness), [angular_rxjs.md](angular_rxjs.md) (marble).
- **Keywords**: `compileComponents`, `fixture.whenStable`, `ComponentFixtureAutoDetect`, `NO_ERRORS_SCHEMA`, `overrideComponent`, `TestBed.overrideProvider`, `MockProvider` (ng-mocks), `provideRouter` (test routing), `RouterTestingHarness`, `jest-preset-angular`, `@analogjs/vitest-angular`, `cy.intercept`, Playwright `route()`.

*Cập nhật lần cuối: 2026-06-04*
