---
title: "Angular Signals & Zoneless – Reactivity Model & Change Detection"
topic: angular
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Angular Signals & Zoneless – Reactivity Model & Change Detection

> Thuật ngữ: [Glossary](glossary.md).

> Bổ trợ cho [angular_state_management.md](angular_state_management.md) (Signals cho quản lý state) và [angular_components_advanced.md](angular_components_advanced.md) (Change Detection Default/OnPush). File này đi sâu vào **mô hình reactivity**, **signal-based components**, và **zoneless**.

## Mục lục
1. [Vấn đề: Zone.js & Change Detection truyền thống (What & Why)](#1-zonejs--change-detection-truyền-thống)
2. [Signals hoạt động thế nào? (How – reactive graph)](#2-signals-hoạt-động-thế-nào)
3. [effect() chuyên sâu](#3-effect-chuyên-sâu)
4. [Signal-based Components (input/model/output/queries)](#4-signal-based-components)
5. [linkedSignal & resource() (Angular 19)](#5-linkedsignal--resource)
6. [Zoneless Change Detection](#6-zoneless-change-detection)
7. [So sánh & Trade-offs](#7-so-sánh--trade-offs)

---

## 1. Zone.js & Change Detection truyền thống

### What – Zone.js là gì?
Angular (trước zoneless) dùng **Zone.js** để "monkey-patch" mọi API bất đồng bộ của trình duyệt (`setTimeout`, `addEventListener`, `Promise`, `XHR`...). Khi bất kỳ async nào hoàn tất, Zone.js báo Angular → Angular chạy **change detection (CD)** trên **toàn bộ cây component** (từ root xuống) để đồng bộ template với data.

### Why – vấn đề của cách này
- CD chạy **rất thường xuyên** và **quá rộng** (kiểm tra cả component không đổi gì) → lãng phí.
- `OnPush` giảm bớt (chỉ check khi `@Input` đổi reference, event, hoặc `async` pipe emit) nhưng vẫn phụ thuộc Zone.js.
- Zone.js nặng (~100KB), patch async gây khó debug, không hiểu `async/await` native tốt.

```
Sự kiện async → Zone.js notify → Angular tick() → CD từ ROOT xuống toàn cây
                                                   (OnPush: bỏ qua nhánh không "dirty")
```
> Liên hệ Default vs OnPush ở [angular_components_advanced.md](angular_components_advanced.md).

---

## 2. Signals hoạt động thế nào?

### What – Signal là gì?
**Signal** là một giá trị **reactive** có thể đọc (gọi như hàm `count()`) và theo dõi ai đang phụ thuộc vào nó. Khi giá trị đổi, mọi thứ phụ thuộc được thông báo **chính xác** — Angular biết **đúng** component nào cần CD, không cần quét cả cây.

```ts
const count = signal(0);          // WritableSignal<number>
count();                          // đọc → 0 (đồng thời "đăng ký" dependency nếu trong reactive context)
count.set(5);                     // ghi giá trị mới
count.update(c => c + 1);         // ghi dựa trên giá trị cũ → 6

const doubled = computed(() => count() * 2);  // derived, lazy + memoized
```

### How – Reactive Graph (push-pull, glitch-free)
Signals xây một **đồ thị phụ thuộc** (dependency graph):
- **Producer**: `signal`, `computed`.
- **Consumer**: `computed`, `effect`, template.
- Khi đọc producer trong consumer → tạo cạnh phụ thuộc tự động (dynamic dependency tracking).

Cơ chế **push-then-pull**:
1. **Push**: signal `.set()` → đánh dấu các consumer phụ thuộc là "dirty" (không tính lại ngay).
2. **Pull**: khi consumer được đọc (template render / effect chạy) → mới tính lại nếu dirty.

→ `computed` **lazy** (chỉ tính khi được đọc) + **memoized** (cache cho tới khi dependency đổi) + **glitch-free** (không bao giờ thấy giá trị trung gian mâu thuẫn).

```ts
const firstName = signal('An');
const lastName = signal('Le');
const fullName = computed(() => `${firstName()} ${lastName()}`);
// Đổi cả hai trong 1 lần → fullName chỉ tính lại 1 lần khi được đọc (không glitch)
```

> Khác RxJS: signal **luôn có giá trị hiện tại** (synchronous, không cần subscribe), hợp cho **state**; RxJS hợp cho **luồng sự kiện async/thời gian** (xem [angular_rxjs.md](angular_rxjs.md)).

---

## 3. effect() chuyên sâu

`effect()` chạy một side-effect **mỗi khi** signal mà nó đọc thay đổi. Dùng cho logging, sync localStorage, gọi API thủ công, thao tác DOM ngoài template.

```ts
@Component({...})
export class C {
  count = signal(0);
  constructor() {
    effect(() => {
      console.log('count =', this.count());   // tự re-run khi count đổi
    });
  }
}
```

### Các điểm cốt lõi
- **Injection context**: `effect()` phải tạo trong constructor/field initializer (có injector), hoặc truyền `{ injector }`. Tự **cleanup** khi component destroy (gắn `DestroyRef`).
- **Cleanup function**: trả về để dọn dẹp lần chạy trước (vd hủy timer):
  ```ts
  effect((onCleanup) => {
    const id = setInterval(...);
    onCleanup(() => clearInterval(id));
  });
  ```
- **untracked()**: đọc signal **không** tạo dependency (tránh re-run ngoài ý muốn):
  ```ts
  effect(() => { log(this.a()); untracked(() => this.b()); }); // chỉ a() trigger re-run
  ```
- ⚠️ **Không** dùng effect để **cập nhật state** (set signal khác) làm logic phái sinh → dùng `computed`. Effect chỉ cho side-effect "ra ngoài thế giới". Ghi signal trong effect bị chặn mặc định (cần `allowSignalWrites`, và thường là code smell).

---

## 4. Signal-based Components

Angular 17.1+ chuyển input/output/queries sang **signal API** — type-safe, reactive, gọn hơn decorator.

### Signal Inputs (`input()`)
```ts
export class UserCard {
  // thay cho @Input() name: string;
  name = input<string>();                       // InputSignal<string | undefined>
  age = input.required<number>();               // bắt buộc — lỗi compile nếu thiếu
  role = input('guest', { alias: 'userRole' }); // default + alias
  // transform (vd ép kiểu/boolean attribute)
  disabled = input(false, { transform: booleanAttribute });

  // input là signal → dùng trong computed/effect/template
  greeting = computed(() => `Hi ${this.name()}`);
}
```

### Model Inputs (`model()`) – two-way binding gọn
```ts
export class Counter {
  value = model(0);                  // tạo input "value" + output "valueChange"
  inc() { this.value.update(v => v + 1); }   // ghi → tự emit valueChange
}
// Dùng: <app-counter [(value)]="count" />
```

### Outputs (`output()`)
```ts
export class C {
  saved = output<User>();            // thay @Output() saved = new EventEmitter<User>()
  onSave() { this.saved.emit(user); }
}
// outputFromObservable / outputToObservable cho interop RxJS
```

### Signal Queries (`viewChild`/`contentChild`)
```ts
export class C {
  // thay @ViewChild('ref') ref!: ElementRef;
  ref = viewChild<ElementRef>('ref');            // Signal<ElementRef | undefined>
  reqRef = viewChild.required(MyComp);           // bắt buộc
  items = viewChildren(ItemComp);                // Signal<readonly ItemComp[]>
  projected = contentChild(HeaderComp);
}
// Query là signal → dùng trong computed/effect, không cần ngAfterViewInit
```

> So với decorator cũ (`@Input/@Output/@ViewChild`): signal API **reactive ngay**, không cần lifecycle hook để đọc query, hỗ trợ required, transform type-safe. Decorator vẫn dùng được (chưa deprecated).

---

## 5. linkedSignal & resource()

### linkedSignal (Angular 19) – writable signal "phái sinh nhưng ghi đè được"
Giải bài toán: state phụ thuộc nguồn khác **nhưng** người dùng vẫn sửa được, và **reset** khi nguồn đổi.
```ts
const options = signal(['A', 'B', 'C']);
// selected mặc định theo options[0], nhưng user chọn được; options đổi → reset
const selected = linkedSignal(() => options()[0]);
selected.set('B');                 // user override
// options.set([...]) → selected tự reset về phần tử đầu mới
```
> `computed` không ghi được; `linkedSignal` = computed + writable + auto-reset theo source.

### resource() / rxResource – async như signal
Tải dữ liệu async, phơi ra `value()`, `status()`, `error()`, tự **hủy request cũ** khi tham số đổi (như switchMap).
```ts
const userId = signal(1);
const userResource = resource({
  request: () => ({ id: userId() }),                 // đổi → reload, request cũ bị abort
  loader: ({ request, abortSignal }) =>
      fetch(`/api/users/${request.id}`, { signal: abortSignal }).then(r => r.json()),
});
userResource.value();    // dữ liệu | undefined
userResource.status();   // 'idle' | 'loading' | 'resolved' | 'error'

// rxResource: loader trả Observable (dùng HttpClient) — xem angular_http_communication.md
```
> Đây là hướng thay thế dần pattern `BehaviorSubject + switchMap` cho data fetching. Bản chi tiết hơn về state ở [angular_state_management.md](angular_state_management.md).

---

## 6. Zoneless Change Detection

### What – Zoneless là gì?
Angular 18+ cho phép chạy **không cần Zone.js**. CD được kích hoạt bởi **tín hiệu rõ ràng**: signal đổi, `async` pipe emit, event handler, `markForCheck()`, `ChangeDetectorRef`.

```ts
// main.ts – bật zoneless (Angular 18 experimental → 19+ ổn định dần)
bootstrapApplication(App, {
  providers: [provideExperimentalZonelessChangeDetection()]
});
// Đồng thời XÓA "zone.js" khỏi polyfills trong angular.json
```

### Why – lợi ích
- Bỏ ~100KB Zone.js → bundle nhỏ, khởi động nhanh.
- CD **chính xác** (chỉ component "dirty" do signal/event) thay vì quét cả cây → nhanh, ít lãng phí.
- Hiểu `async/await` native, debug stack trace sạch, tương thích tốt hơn với thư viện bên thứ ba.

### How – điều kiện để zoneless hoạt động tốt
- State hiển thị trong template **nên là signal** (hoặc dùng `async` pipe / `markForCheck` thủ công). Mutate object thường mà không báo CD → view **không cập nhật**.
- Component `OnPush` + signals là tổ hợp lý tưởng (zoneless về cơ bản coi mọi component như OnPush).
- Code dựa `setTimeout`/`Promise` để "ép" view cập nhật (anti-pattern cũ) sẽ **không còn chạy** → phải chuyển sang signal.

```
Zoneful:  bất kỳ async → CD toàn cây (OnPush lọc bớt)
Zoneless: signal.set / event / async-pipe / markForCheck → CD đúng component dirty
```

---

## 7. So sánh & Trade-offs

| | Zone.js + Default CD | OnPush + RxJS | Signals + Zoneless |
|--|----------------------|---------------|--------------------|
| Khi nào CD chạy | Mọi async, toàn cây | Khi input đổi/async emit | Khi signal/event đổi, đúng component |
| Bundle | +Zone.js (~100KB) | +Zone.js | **Không Zone.js** |
| Độ chính xác | Thấp (quét rộng) | Trung bình | **Cao** |
| Độ khó | Dễ (tự động) | Trung bình | Cần kỷ luật dùng signal |
| Async data | Promise/RxJS | RxJS | resource()/toSignal |

### Trade-offs
- (+) Signals: đơn giản hơn RxJS cho state, đồng bộ, glitch-free, mở đường zoneless → hiệu năng & bundle.
- (−) Phải đổi tư duy: state là signal; lạm dụng `effect` thay `computed` gây bug; thư viện cũ giả định Zone.js có thể vỡ khi zoneless.
- (−) RxJS vẫn cần cho luồng sự kiện phức tạp (debounce, retry, websocket) → kết hợp `toSignal`/`toObservable`. Xem [angular_rxjs.md](angular_rxjs.md).
- (+) Migration dần được: bật signals trước, zoneless sau khi toàn bộ state đã reactive.

---

## Ghi chú – Topics tiếp theo

- Liên quan: [angular_state_management.md](angular_state_management.md) (signal store, NgRx SignalStore), [angular_components_advanced.md](angular_components_advanced.md) (CD, OnPush), [angular_rxjs.md](angular_rxjs.md) (interop, khi nào RxJS), [angular_http_communication.md](angular_http_communication.md) (rxResource + HttpClient).
- **Keywords**: `WritableSignal`, `Signal<T>`, `computed` equality fn, `effect` `allowSignalWrites`, `untracked`, `signal` `equal`, `toSignal({requireSync})`, `afterRenderEffect`, `afterNextRender`, `PendingTasks` (zoneless SSR), `ɵNG_DEV_MODE`, `provideZonelessChangeDetection`, signal-based forms (đang phát triển).

*Cập nhật lần cuối: 2026-06-04*
