---
title: "Angular Material, CDK & Accessibility – Deep Dive"
topic: angular
level: mixed
review_status: needs_review
content_updated: 2026-06-04
last_verified: null
version_scope: "unspecified"
source_count: 0
---
# Angular Material, CDK & Accessibility – Deep Dive

> Thuật ngữ: [Glossary](glossary.md).

> Bổ trợ cho [angular_components_advanced.md](angular_components_advanced.md) (Content Projection, Dynamic Components → nền tảng của Portal/Overlay) và [angular_testing.md](angular_testing.md) (Component Harness).

## Mục lục
1. [Material vs CDK (What & Why)](#1-material-vs-cdk)
2. [CDK – các primitive cốt lõi](#2-cdk--các-primitive-cốt-lõi)
3. [Angular Material – components & standalone](#3-angular-material--components)
4. [Theming với Material 3 (design tokens)](#4-theming-với-material-3)
5. [Accessibility (a11y)](#5-accessibility-a11y)
6. [So sánh & Trade-offs](#6-so-sánh--trade-offs)

---

## 1. Material vs CDK

| | Angular CDK | Angular Material |
|--|-------------|------------------|
| Là gì | **Component Dev Kit** – hành vi/primitive **không style** | Bộ component có sẵn UI theo Material Design |
| Cung cấp | Overlay, Portal, DragDrop, VirtualScroll, A11y, Layout... | Button, Dialog, Table, Datepicker, Autocomplete... |
| Style | Bạn tự style (headless) | Đã style + theme |
| Khi dùng | Xây component riêng/design system của bạn | Cần UI nhanh theo Material |

> **Material được build trên CDK.** Muốn UI riêng (không Material look) nhưng vẫn cần hành vi phức tạp (overlay, focus trap, drag) → dùng **CDK trực tiếp** (headless). Đây là cách xây design system nội bộ.

---

## 2. CDK – các primitive cốt lõi

### Overlay – panel nổi (dropdown, tooltip, popover)
```ts
const overlayRef = inject(Overlay).create({
  positionStrategy: inject(Overlay).position()
    .flexibleConnectedTo(this.triggerEl)            // neo vào element
    .withPositions([{ originX: 'start', originY: 'bottom', overlayX: 'start', overlayY: 'top' }]),
  scrollStrategy: inject(Overlay).scrollStrategies.reposition(),
  hasBackdrop: true,
});
overlayRef.attach(new ComponentPortal(MenuComponent));   // render component vào overlay
overlayRef.backdropClick().subscribe(() => overlayRef.dispose());
```

### Portal – render động component/template ra "nơi khác"
```ts
// ComponentPortal / TemplatePortal — nền của Overlay, Dialog, Stepper
<ng-template cdkPortal>...</ng-template>
<ng-container [cdkPortalOutlet]="myPortal"></ng-container>
```
> Liên hệ Dynamic Components ở [angular_components_advanced.md](angular_components_advanced.md).

### Virtual Scroll – render danh sách lớn hiệu quả
```html
<cdk-virtual-scroll-viewport itemSize="50" class="viewport">
  <div *cdkVirtualFor="let item of items">{{ item.name }}</div>
</cdk-virtual-scroll-viewport>
```
> Chỉ render các item **trong viewport** (recycling DOM) → list 100k phần tử vẫn mượt. Liên hệ performance ([angular_performance_production.md](angular_performance_production.md)).

### Drag & Drop
```html
<div cdkDropList (cdkDropListDropped)="drop($event)">
  <div cdkDrag *ngFor="let task of tasks">{{ task }}</div>
</div>
```
```ts
drop(e: CdkDragDrop<string[]>) { moveItemInArray(this.tasks, e.previousIndex, e.currentIndex); }
```

### Layout – responsive theo breakpoint
```ts
inject(BreakpointObserver).observe([Breakpoints.Handset]).subscribe(r => this.isMobile = r.matches);
```
> Các primitive khác: `cdk-table` (table headless), `cdkStepper`, `cdkMenu`/`cdkListbox` (a11y menu/listbox), `Clipboard`, `cdkTree`.

---

## 3. Angular Material – components

```ts
// Standalone import (Angular 15+) — chỉ import component cần
import { MatButtonModule } from '@angular/material/button';
import { MatDialog } from '@angular/material/dialog';

@Component({ imports: [MatButtonModule], template: `<button mat-raised-button>OK</button>` })
export class C {
  private dialog = inject(MatDialog);
  open() {
    const ref = this.dialog.open(EditDialog, { data: { id: 1 }, width: '400px' });
    ref.afterClosed().subscribe(result => { ... });
  }
}
```
Nhóm component: form (input/select/autocomplete/datepicker/slider), navigation (toolbar/sidenav/menu), layout (card/tabs/expansion/grid-list), data (table + sort + paginator, tree), popups (dialog/snackbar/tooltip/bottom-sheet), buttons/indicators (progress, badge, chips).

> `MatTable` + `MatSort` + `MatPaginator` + `DataSource` là combo phổ biến cho bảng dữ liệu lớn (kết hợp server-side paging).

---

## 4. Theming với Material 3

Angular Material (v17+) dùng **Material 3 (M3)** với **design tokens** (CSS variables) — tách màu/typography/shape khỏi component.

```scss
@use '@angular/material' as mat;

html {
  @include mat.theme((
    color: (
      primary: mat.$violet-palette,      // M3 system palette
      tertiary: mat.$orange-palette,
    ),
    typography: Roboto,
    density: 0,
  ));
}

// Dark mode
.dark {
  @include mat.theme((color: (theme-type: dark, primary: mat.$violet-palette)));
}

// Override token cho 1 component
.my-card { @include mat.card-overrides((elevated-container-color: #fafafa)); }
```
- **System tokens** (`--mat-sys-primary`...) → dùng được cả trong CSS thường, đồng bộ light/dark.
- Density: nén khoảng cách (UI dày đặc như admin table).
- M3 thay API `define-light-theme`/`define-dark-theme` (M2 cũ) bằng `mat.theme()` token-based.

---

## 5. Accessibility (a11y)

### Vì sao quan trọng
A11y giúp người khuyết tật (screen reader, chỉ bàn phím) dùng được app — và là **yêu cầu pháp lý** (WCAG, ADA) ở nhiều nơi. SPA dễ phá a11y vì tự quản DOM/focus.

### Nguyên tắc cốt lõi
- **Semantic HTML** trước ARIA: `<button>`, `<nav>`, `<main>`, `<label>` thay `<div>` click được.
- **ARIA** khi cần: `role`, `aria-label`, `aria-expanded`, `aria-live`, `aria-describedby`.
- **Keyboard**: mọi tương tác phải dùng được bằng phím (Tab/Enter/Esc/Arrow); focus thấy được.
- **Focus management**: mở dialog → focus vào trong + trap; đóng → trả focus về trigger.
- **Color contrast** đủ (WCAG AA 4.5:1).

### CDK a11y module
```ts
// FocusTrap — giữ focus trong dialog/menu
<div cdkTrapFocus cdkTrapFocusAutoCapture> ...dialog... </div>

// LiveAnnouncer — báo screen reader thông điệp động (vd "Đã lưu")
inject(LiveAnnouncer).announce('Đã lưu hồ sơ', 'polite');

// FocusMonitor — biết focus đến từ chuột/bàn phím/chương trình
inject(FocusMonitor).monitor(this.el).subscribe(origin => ...);
```
- `cdkAriaLive`, `A11yModule`, `InteractivityChecker`, `HighContrastModeDetector`.
- Material components đã a11y sẵn (dialog tự trap focus, snackbar tự announce).
- Test a11y: axe-core (`@axe-core/playwright`), Lighthouse, đọc bằng screen reader thật (NVDA/VoiceOver).

---

## 6. So sánh & Trade-offs

| | Angular Material | PrimeNG / Nebular | CDK headless + tự style | Tailwind + headless (Spartan/CDK) |
|--|------------------|-------------------|--------------------------|-----------------------------------|
| Tốc độ ra UI | Nhanh | Nhanh, nhiều component | Chậm (tự style) | Trung bình |
| Tùy biến look | Theme tokens (giới hạn Material) | Theme | **Tự do hoàn toàn** | Tự do |
| A11y | Tốt sẵn | Khác nhau | Bạn tự lo (CDK hỗ trợ) | Tùy |
| Bundle | Trung bình–lớn | Lớn | Nhỏ | Nhỏ–TB |

### Trade-offs
- (+) Material: nhanh, a11y tốt, theme đồng bộ, được Google bảo trì, Harness test tốt.
- (−) Material: "trông giống Google", tùy biến sâu khó, bundle không nhỏ.
- (+) CDK: hành vi phức tạp (overlay/focus/drag/virtual scroll) mà giữ design riêng → nền design system.
- (−) CDK headless: phải tự style + tự lo nhiều chi tiết a11y.
- ⚠️ Đừng "div hóa" mọi thứ rồi vá ARIA — ưu tiên semantic HTML, dùng CDK/Material cho phần khó.

---

## Ghi chú – Topics tiếp theo

- Liên quan: [angular_components_advanced.md](angular_components_advanced.md) (Portal/Dynamic Components/Content Projection), [angular_testing.md](angular_testing.md) (Component Harness test Material), [angular_performance_production.md](angular_performance_production.md) (virtual scroll, bundle), [angular_animations.md](angular_animations.md) (animation cho dialog/menu).
- **Keywords**: `OverlayModule`, `ConnectedPosition`, `CdkScrollable`, `ScrollingModule`, `DragRef`, `MatTableDataSource`, `mat.get-theme-color`, `mat.$theme-overrides`, system variables `--mat-sys-*`, `AriaDescriber`, `cdkMonitorElementFocus`, `ListKeyManager`/`ActiveDescendantKeyManager` (keyboard nav), WCAG 2.2, `role="alert"`.

*Cập nhật lần cuối: 2026-06-04*
