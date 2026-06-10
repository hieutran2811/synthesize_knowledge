# Angular Animations – @angular/animations Deep Dive

> Bổ trợ cho [angular_material_cdk_a11y.md](angular_material_cdk_a11y.md) (animation cho dialog/menu) và [angular_performance_production.md](angular_performance_production.md) (hiệu năng render).

## Mục lục
1. [Animations là gì & khi nào cần (What & Why)](#1-animations-là-gì--khi-nào-cần)
2. [Setup & building blocks](#2-setup--building-blocks)
3. [State & Transition](#3-state--transition)
4. [:enter / :leave (void)](#4-enter--leave)
5. [Keyframes, group, sequence, stagger](#5-keyframes-group-sequence-stagger)
6. [Route/Page transitions](#6-routepage-transitions)
7. [Callbacks, disable, reusable](#7-callbacks-disable-reusable)
8. [Hiệu năng & So sánh với CSS](#8-hiệu-năng--so-sánh-với-css)

---

## 1. Animations là gì & khi nào cần

`@angular/animations` là **DSL** (domain-specific language) khai báo animation trong TypeScript, build trên **Web Animations API**. Mạnh hơn CSS thuần khi animation **phụ thuộc state component**, cần **enter/leave** (phần tử thêm/xóa khỏi DOM), **orchestration** (nhiều phần tử theo trình tự), hoặc cần **callback** khi animation xong.

> ⚠️ Animation **đơn giản** (hover, fade tĩnh) → dùng **CSS** thuần (nhẹ hơn, không tốn bundle). `@angular/animations` cho trường hợp **động theo state / enter-leave / orchestration**.

---

## 2. Setup & building blocks

```ts
// app.config.ts — Angular 17+ (lazy, tốt cho bundle)
provideAnimationsAsync();          // hoặc provideAnimations() (eager)
```

```ts
import { trigger, state, style, transition, animate, keyframes,
         group, sequence, query, stagger, animateChild, useAnimation, animation } from '@angular/animations';

@Component({
  animations: [ /* các trigger */ ],
  template: `<div [@openClose]="isOpen ? 'open' : 'closed'">...</div>`
})
```

| Hàm | Vai trò |
|-----|---------|
| `trigger(name, [...])` | Gom animation, gắn vào template qua `[@name]` |
| `state(name, style(...))` | Trạng thái cuối + style tương ứng |
| `style({...})` | CSS style snapshot |
| `transition('a => b', [...])` | Chuyển giữa state, định nghĩa animation |
| `animate('300ms ease-in', style(...))` | Thời lượng/easing + style đích |
| `keyframes([...])` | Nhiều bước trung gian |
| `query`/`stagger`/`group`/`sequence` | Orchestration nhiều phần tử |

---

## 3. State & Transition

```ts
trigger('openClose', [
  state('open',   style({ height: '200px', opacity: 1 })),
  state('closed', style({ height: '0px',   opacity: 0 })),
  transition('open => closed', [animate('300ms ease-out')]),
  transition('closed => open', [animate('400ms ease-in')]),
  // hoặc gộp: transition('open <=> closed', [animate('300ms')])
]),
```
Cú pháp transition expression:
- `'open => closed'`, `'closed => open'`, `'open <=> closed'` (cả hai chiều)
- `'* => closed'` (từ bất kỳ → closed), `'* => *'` (mọi chuyển)
- `':enter'`/`':leave'` (= `'void => *'` / `'* => void'`)
- `':increment'`/`':decrement'` (state là số)

---

## 4. :enter / :leave

Animate phần tử khi **thêm/xóa** khỏi DOM (`*ngIf`, `@if`, `*ngFor`). `void` = chưa tồn tại trong DOM.

```ts
trigger('fadeInOut', [
  transition(':enter', [style({ opacity: 0 }), animate('300ms', style({ opacity: 1 }))]),
  transition(':leave', [animate('300ms', style({ opacity: 0 }))]),
]),
```
```html
@if (show) { <div @fadeInOut>Nội dung</div> }
```
> Nhờ Angular giữ phần tử trong DOM cho tới khi `:leave` chạy xong rồi mới xóa.

---

## 5. Keyframes, group, sequence, stagger

```ts
// keyframes — nhiều bước với offset
transition('* => bounce', [
  animate('1s', keyframes([
    style({ transform: 'translateY(0)',     offset: 0 }),
    style({ transform: 'translateY(-30px)', offset: 0.3 }),
    style({ transform: 'translateY(0)',     offset: 1 }),
  ])),
]),

// stagger — animate list lần lượt (hiệu ứng "đổ" từng item)
trigger('listAnim', [
  transition('* => *', [
    query(':enter', [
      style({ opacity: 0, transform: 'translateY(20px)' }),
      stagger(80, animate('300ms ease-out', style({ opacity: 1, transform: 'none' }))),
    ], { optional: true }),
  ]),
]),
```
- `group([...])`: chạy **song song**. `sequence([...])`: chạy **tuần tự**.
- `query(selector, [...])`: chọn phần tử con để animate (`:enter`, `:leave`, `.class`, `@childTrigger`).
- `animateChild()`: cho phép animation của component con chạy trong khi cha đang animate.

---

## 6. Route/Page transitions

```ts
// Trên router-outlet
<div [@routeAnim]="getState(outlet)">
  <router-outlet #outlet="outlet"></router-outlet>
</div>
```
```ts
getState(outlet: RouterOutlet) { return outlet?.activatedRouteData?.['animation']; }

trigger('routeAnim', [
  transition('* <=> *', [
    query(':enter, :leave', style({ position: 'absolute', width: '100%' }), { optional: true }),
    group([
      query(':leave', [animate('300ms', style({ opacity: 0 }))], { optional: true }),
      query(':enter', [style({ opacity: 0 }), animate('300ms', style({ opacity: 1 }))], { optional: true }),
    ]),
  ]),
]),
// route config: data: { animation: 'HomePage' }
```
> Liên hệ Router ở [angular_routing_forms.md](angular_routing_forms.md). Cân nhắc **View Transitions API** (`withViewTransitions()` trong Router, Angular 17+) — cách native, nhẹ hơn cho chuyển trang.

---

## 7. Callbacks, disable, reusable

```ts
// Callback khi bắt đầu/kết thúc
<div [@openClose]="state" (@openClose.start)="onStart($event)" (@openClose.done)="onDone($event)">

// Tắt animation (test, prefers-reduced-motion, hiệu năng)
<div [@.disabled]="disableAnim">...</div>

// Reusable animation
export const fadeIn = animation([
  style({ opacity: 0 }), animate('{{ time }}', style({ opacity: 1 })),
], { params: { time: '300ms' } });
// dùng: transition(':enter', useAnimation(fadeIn, { params: { time: '500ms' } }))
```
> **A11y**: tôn trọng `prefers-reduced-motion` (người dùng tắt hiệu ứng) → bind `[@.disabled]`. Liên hệ a11y ở [angular_material_cdk_a11y.md](angular_material_cdk_a11y.md).

---

## 8. Hiệu năng & So sánh với CSS

### Hiệu năng
- Ưu tiên animate **`transform`** và **`opacity`** → GPU-accelerated, không gây **reflow/repaint** layout.
- Tránh animate `width`/`height`/`top`/`left`/`margin` → trigger layout liên tục (giật, tốn CPU).
- Danh sách lớn + stagger → cân nhắc số lượng (kết hợp virtual scroll). Liên hệ [angular_performance_production.md](angular_performance_production.md).

### So sánh

| | @angular/animations | CSS transition/animation | Web Animations API | View Transitions API |
|--|---------------------|--------------------------|--------------------|----------------------|
| State-driven | **Mạnh** (theo state component) | Hạn chế (class toggle) | Thủ công (JS) | Cho chuyển trang/DOM |
| Enter/leave | **Native** (`:enter/:leave`) | Khó (cần lib) | Thủ công | Tự động |
| Orchestration | Mạnh (query/stagger/group) | Hạn chế | Thủ công | Hạn chế |
| Bundle cost | +`@angular/animations` | 0 | 0 | 0 |
| Đơn giản (hover/fade) | Quá mức | **Lý tưởng** | – | – |

### Trade-offs
- (+) Khai báo gọn, state-driven, enter/leave & orchestration mạnh, callback, test disable được.
- (−) Tốn bundle (`provideAnimationsAsync` giảm thiểu bằng lazy); với animation đơn giản là over-engineering → dùng CSS.
- (−) Lạm dụng animation hại UX + a11y (motion sickness) → tôn trọng `prefers-reduced-motion`.

---

## Ghi chú – Topics tiếp theo

- Liên quan: [angular_material_cdk_a11y.md](angular_material_cdk_a11y.md) (animation component, prefers-reduced-motion), [angular_routing_forms.md](angular_routing_forms.md) (route transitions), [angular_performance_production.md](angular_performance_production.md) (GPU layers, reflow).
- **Keywords**: `AnimationEvent`, `AnimationBuilder`/`AnimationPlayer` (animate bằng code), `withViewTransitions()` (Router), `provideNoopAnimations` (test), `query` flags (`optional`, `limit`), `animateChild`, easing `cubic-bezier`, `NoopAnimationsModule`.

*Cập nhật lần cuối: 2026-06-04*
