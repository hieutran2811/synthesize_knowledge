# Angular Fundamentals – Nền Tảng

## Mục lục
1. [Angular là gì? (What)](#1-angular-là-gì-what)
2. [Tại sao dùng Angular? (Why)](#2-tại-sao-dùng-angular-why)
3. [Kiến trúc Angular (How)](#3-kiến-trúc-angular-how)
4. [Components](#4-components)
5. [Templates & Data Binding](#5-templates--data-binding)
6. [Built-in Directives](#6-built-in-directives)
7. [Pipes](#7-pipes)
8. [NgModule vs Standalone Components](#8-ngmodule-vs-standalone-components)

---

## 1. Angular là gì? (What)

**Angular** là một **platform và framework** để xây dựng Single Page Applications (SPA) sử dụng TypeScript, được phát triển và duy trì bởi Google.

### Đặc điểm cốt lõi:
- **Opinionated full framework**: tích hợp sẵn Router, Forms, HttpClient, Animation, Testing
- **TypeScript-first**: type safety, IDE support, refactoring tốt hơn
- **Ivy compiler**: ahead-of-time (AOT) compilation → bundle nhỏ, runtime nhanh
- **Dependency Injection**: hierarchical DI system built-in, không cần thư viện ngoài
- **Two-way data binding**: đồng bộ Model ↔ View tự động
- **Component-based**: UI được chia thành các component tái sử dụng

---

## 2. Tại sao dùng Angular? (Why)

```
Problem: Frontend app phức tạp → khó maintain, scale, test

Angular giải quyết:
✓ Structure rõ ràng: component/service/module/guard tách biệt
✓ TypeScript: bắt lỗi compile-time, tự document code
✓ DI system: loose coupling, testable, reusable services
✓ AOT compilation: template lỗi bắt lúc build, không phải runtime
✓ Schematics: CLI generate code theo convention nhất quán
✓ Ecosystem đầy đủ: không cần chọn router/state/form library riêng
```

### So sánh với React và Vue:

| | Angular | React | Vue |
|--|---------|-------|-----|
| Type | Framework đầy đủ | UI Library | Progressive Framework |
| Language | TypeScript (bắt buộc) | JS/TS | JS/TS |
| Learning curve | Cao (DI, RxJS, decorators) | Trung bình | Thấp |
| State management | NgRx / Signals built-in | Redux/Zustand (tách biệt) | Pinia/Vuex |
| Forms | Template-driven + Reactive | Formik/React Hook Form | VeeValidate |
| Bundle size | ~50KB+ (initial) | ~40KB+ | ~30KB+ |
| Best for | Enterprise apps lớn | Flexible, ecosystem rộng | Apps vừa, học nhanh |
| Backed by | Google | Meta | Community |

---

## 3. Kiến trúc Angular (How)

### 3.1 Compilation Pipeline

```
TypeScript + HTML Templates
        ↓  
Angular Compiler (Ivy) — AOT mode (build time)
        ↓
Optimized JavaScript (tree-shaken, type-checked)
        ↓
Browser / Node.js (SSR)

Build tools:
  Angular 16-: webpack
  Angular 17+: esbuild (default) → 10x faster builds
```

### 3.2 Module System

```
NgModule (truyền thống):
  AppModule
    imports: [BrowserModule, RouterModule, HttpClientModule]
    declarations: [AppComponent, HeaderComponent]
    providers: [UserService]
    bootstrap: [AppComponent]

Standalone (Angular 14+ stable):
  @Component({ standalone: true, imports: [...] })
  → không cần NgModule, import trực tiếp vào component
```

### 3.3 Runtime Architecture

```
┌─────────────────────────────────────────────────┐
│              Angular Runtime                      │
│                                                  │
│  Zone.js (Change Detection trigger)              │
│    ├── setTimeout/setInterval wrap               │
│    ├── Promise wrap                              │
│    └── Event listener wrap                       │
│                                                  │
│  Change Detector (per component)                 │
│    ├── Default: check all on any event          │
│    └── OnPush: check only when Input changes    │
│                                                  │
│  Renderer (DOM manipulation)                     │
│    ├── Browser: DOM renderer                    │
│    └── Server: platform-server renderer         │
└─────────────────────────────────────────────────┘
```

---

## 4. Components

### 4.1 Anatomy of a Component

```typescript
// user-card.component.ts
import { Component, Input, Output, EventEmitter, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { User } from './user.model';

@Component({
  selector: 'app-user-card',      // Dùng: <app-user-card>
  templateUrl: './user-card.component.html',
  styleUrls: ['./user-card.component.scss'],
  standalone: true,               // Angular 14+ standalone
  imports: [CommonModule],        // import các module cần dùng trong template
})
export class UserCardComponent implements OnInit {
  
  // Input: nhận data từ parent
  @Input({ required: true }) user!: User;     // required: Angular 16+
  @Input() showActions = false;

  // Output: emit event lên parent
  @Output() selected = new EventEmitter<User>();
  @Output() deleted = new EventEmitter<number>();

  isExpanded = false;  // local state

  ngOnInit(): void {
    console.log('Component initialized with user:', this.user);
  }

  toggleExpand(): void {
    this.isExpanded = !this.isExpanded;
  }

  onSelect(): void {
    this.selected.emit(this.user);
  }

  onDelete(): void {
    this.deleted.emit(this.user.id);
  }
}
```

```html
<!-- user-card.component.html -->
<div class="card" [class.expanded]="isExpanded" (click)="toggleExpand()">
  <img [src]="user.avatar" [alt]="user.name" />
  <h3>{{ user.name }}</h3>
  <p>{{ user.email }}</p>
  
  @if (isExpanded) {
    <div class="details">
      <p>Department: {{ user.department }}</p>
      <p>Joined: {{ user.createdAt | date:'mediumDate' }}</p>
    </div>
  }
  
  @if (showActions) {
    <div class="actions">
      <button (click)="onSelect(); $event.stopPropagation()">Select</button>
      <button (click)="onDelete(); $event.stopPropagation()">Delete</button>
    </div>
  }
</div>
```

### 4.2 Component Interaction

```typescript
// Parent component
@Component({
  selector: 'app-user-list',
  standalone: true,
  imports: [UserCardComponent, CommonModule],
  template: `
    <app-user-card
      *ngFor="let user of users; trackBy: trackByUserId"
      [user]="user"
      [showActions]="true"
      (selected)="onUserSelected($event)"
      (deleted)="onUserDeleted($event)"
    />
  `
})
export class UserListComponent {
  users: User[] = [];

  trackByUserId(index: number, user: User): number {
    return user.id;  // ngFor optimization — avoids full re-render
  }

  onUserSelected(user: User): void {
    console.log('Selected:', user);
  }

  onUserDeleted(userId: number): void {
    this.users = this.users.filter(u => u.id !== userId);
  }
}
```

---

## 5. Templates & Data Binding

### 5.1 Bốn loại Data Binding

```html
<!-- 1. Interpolation {{ }} — Component → DOM (one-way) -->
<h1>Hello, {{ user.name }}!</h1>
<p>Score: {{ score * 10 + bonus }}</p>

<!-- 2. Property Binding [property] — Component → DOM (one-way) -->
<input [value]="username" />
<button [disabled]="isLoading">Submit</button>
<img [src]="imageUrl" [alt]="imageAlt" />
<app-child [data]="parentData" />  <!-- @Input binding -->

<!-- 3. Event Binding (event) — DOM → Component (one-way) -->
<button (click)="onSave()">Save</button>
<input (keyup)="onKeyUp($event)" (blur)="onBlur()" />
<form (ngSubmit)="onSubmit()">...</form>
<app-child (dataChange)="handleChange($event)" />  <!-- @Output binding -->

<!-- 4. Two-way Binding [(ngModel)] — Component ↔ DOM -->
<input [(ngModel)]="searchTerm" />
<!-- Equivalent to: -->
<input [ngModel]="searchTerm" (ngModelChange)="searchTerm = $event" />
```

### 5.2 Template Reference Variables

```html
<!-- #ref tạo reference đến DOM element hoặc component instance -->
<input #searchInput type="text" placeholder="Search..." />
<button (click)="search(searchInput.value)">Search</button>

<!-- Reference đến component instance -->
<app-date-picker #datePicker />
<button (click)="datePicker.open()">Open picker</button>

<!-- @ViewChild trong class -->
```

```typescript
@Component({...})
export class MyComponent implements AfterViewInit {
  @ViewChild('searchInput') searchInputRef!: ElementRef<HTMLInputElement>;
  @ViewChild(DatePickerComponent) datePicker!: DatePickerComponent;

  ngAfterViewInit(): void {
    this.searchInputRef.nativeElement.focus();
  }
}
```

### 5.3 New Control Flow (Angular 17+)

```html
<!-- Angular 17+ built-in control flow (replaces *ngIf, *ngFor, ngSwitch) -->

<!-- @if / @else if / @else -->
@if (user.role === 'ADMIN') {
  <admin-panel />
} @else if (user.role === 'MANAGER') {
  <manager-panel />
} @else {
  <user-panel />
}

<!-- @for với track (bắt buộc, replaces ngFor+trackBy) -->
@for (user of users; track user.id) {
  <app-user-card [user]="user" />
} @empty {
  <p>No users found</p>
}

<!-- @switch -->
@switch (status) {
  @case ('ACTIVE') { <span class="badge green">Active</span> }
  @case ('INACTIVE') { <span class="badge red">Inactive</span> }
  @default { <span class="badge gray">Unknown</span> }
}

<!-- @defer (Angular 17+ — lazy loading blocks) -->
@defer (on viewport) {
  <heavy-chart-component [data]="chartData" />
} @placeholder {
  <div class="skeleton" />
} @loading (minimum 200ms) {
  <spinner />
} @error {
  <p>Failed to load chart</p>
}
```

---

## 6. Built-in Directives

### 6.1 Structural Directives (thay đổi DOM structure)

```html
<!-- *ngIf (Angular < 17, hoặc dùng song song) -->
<div *ngIf="isLoggedIn; else loginTemplate">
  Welcome, {{ user.name }}!
</div>
<ng-template #loginTemplate>
  <app-login />
</ng-template>

<!-- *ngIf với async pipe -->
<div *ngIf="user$ | async as user">
  {{ user.name }}
</div>

<!-- *ngFor -->
<li *ngFor="let item of items; let i = index; let isFirst = first; let isLast = last; trackBy: trackById">
  {{ i + 1 }}. {{ item.name }}
  <span *ngIf="isFirst">(First)</span>
  <span *ngIf="isLast">(Last)</span>
</li>

<!-- *ngSwitch -->
<div [ngSwitch]="status">
  <p *ngSwitchCase="'PENDING'">Pending...</p>
  <p *ngSwitchCase="'DONE'">Done!</p>
  <p *ngSwitchDefault>Unknown</p>
</div>
```

### 6.2 Attribute Directives (thay đổi appearance/behavior)

```html
<!-- ngClass -->
<div [ngClass]="{ 'active': isActive, 'disabled': isDisabled, 'highlight': score > 90 }">...</div>
<div [ngClass]="[baseClass, conditionalClass]">...</div>

<!-- ngStyle -->
<div [ngStyle]="{ 'color': textColor, 'font-size.px': fontSize }">...</div>

<!-- ngModel (two-way binding) — requires FormsModule -->
<input [(ngModel)]="name" />

<!-- Custom Attribute Directive -->
```

```typescript
@Directive({
  selector: '[appHighlight]',
  standalone: true,
})
export class HighlightDirective {
  @Input() appHighlight = 'yellow';   // Directive input

  constructor(private el: ElementRef, private renderer: Renderer2) {}

  @HostListener('mouseenter') onMouseEnter(): void {
    this.renderer.setStyle(this.el.nativeElement, 'background-color', this.appHighlight);
  }

  @HostListener('mouseleave') onMouseLeave(): void {
    this.renderer.removeStyle(this.el.nativeElement, 'background-color');
  }
}

// Usage: <p appHighlight="lightblue">Hover me!</p>
```

---

## 7. Pipes

### 7.1 Built-in Pipes

```html
<!-- String -->
{{ 'hello world' | uppercase }}         <!-- HELLO WORLD -->
{{ 'HELLO WORLD' | lowercase }}         <!-- hello world -->
{{ 'hello world' | titlecase }}         <!-- Hello World -->
{{ longText | slice:0:100 }}           <!-- first 100 chars -->

<!-- Number -->
{{ 12345.6789 | number:'1.2-3' }}      <!-- 12,345.679 (min 1 integer, 2-3 decimals) -->
{{ 0.75 | percent:'1.0-0' }}           <!-- 75% -->
{{ 1500.5 | currency:'VND':'symbol':'1.0-0' }}  <!-- ₫1,501 -->

<!-- Date -->
{{ today | date }}                      <!-- Jan 1, 2024 -->
{{ today | date:'dd/MM/yyyy' }}        <!-- 01/01/2024 -->
{{ today | date:'dd/MM/yyyy HH:mm' }}  <!-- 01/01/2024 09:30 -->
{{ today | date:'relative' }}          <!-- 2 hours ago (Angular 17+) -->

<!-- Object/Array -->
{{ user | json }}                       <!-- {"id":1,"name":"John"} -->
{{ [3,1,2] | slice:0:2 }}             <!-- [3, 1] -->

<!-- Async (subscribe + unsubscribe automatically) -->
{{ user$ | async }}
<div *ngIf="users$ | async as users">{{ users.length }} users</div>

<!-- KeyValue -->
<div *ngFor="let item of obj | keyvalue">
  {{ item.key }}: {{ item.value }}
</div>
```

### 7.2 Custom Pipe

```typescript
// Truncate pipe: {{ text | truncate:50:'...' }}
@Pipe({
  name: 'truncate',
  standalone: true,
  pure: true,  // default: true — only recalculate when input changes (performant)
})
export class TruncatePipe implements PipeTransform {
  transform(value: string, limit = 100, ellipsis = '...'): string {
    if (!value || value.length <= limit) return value;
    return value.substring(0, limit) + ellipsis;
  }
}

// Impure pipe: recalculates on every change detection cycle
// Use only when pipe reads external mutable state
@Pipe({ name: 'filterBy', pure: false })
export class FilterByPipe implements PipeTransform {
  transform(items: any[], filterFn: (item: any) => boolean): any[] {
    return items.filter(filterFn);
  }
}
```

---

## 8. NgModule vs Standalone Components

### 8.1 NgModule (Truyền thống)

```typescript
// app.module.ts
@NgModule({
  declarations: [
    AppComponent,
    UserListComponent,
    UserCardComponent,
    HighlightDirective,
    TruncatePipe,
  ],
  imports: [
    BrowserModule,
    HttpClientModule,
    RouterModule.forRoot(routes),
    ReactiveFormsModule,
  ],
  providers: [
    UserService,
    { provide: HTTP_INTERCEPTORS, useClass: AuthInterceptor, multi: true },
  ],
  bootstrap: [AppComponent],
})
export class AppModule {}
```

### 8.2 Standalone Components (Angular 14+ — Recommended)

```typescript
// main.ts — bootstrapApplication (no NgModule)
import { bootstrapApplication } from '@angular/platform-browser';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { routes } from './app/app.routes';

bootstrapApplication(AppComponent, {
  providers: [
    provideRouter(routes, withPreloading(PreloadAllModules)),
    provideHttpClient(withInterceptors([authInterceptor])),
    provideAnimations(),
  ],
});

// app.component.ts — standalone
@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, CommonModule],
  template: `<router-outlet />`,
})
export class AppComponent {}

// Feature component — imports only what it needs
@Component({
  selector: 'app-user-list',
  standalone: true,
  imports: [
    CommonModule,       // ngIf, ngFor, async pipe
    UserCardComponent,  // another standalone component
    TruncatePipe,       // standalone pipe
    ReactiveFormsModule,
  ],
  template: `...`,
})
export class UserListComponent {}
```

### 8.3 So sánh NgModule vs Standalone

| | NgModule | Standalone |
|--|---------|-----------|
| Boilerplate | Nhiều (declare, import, export) | Ít hơn |
| Lazy loading | Route level | Route level (cleaner) |
| Tree-shaking | Module-based | Component-based (tốt hơn) |
| Reusability | Export từ module | Import trực tiếp |
| Testing | TestBed dễ setup | Cần import ít hơn |
| Migration | Có sẵn | Dần thay thế NgModule |
| Angular 17+ | Không còn generate NgModule mặc định | Default |

---

## Ghi chú – Topics tiếp theo

- **Component lifecycle**: ngOnInit, ngOnChanges, ngOnDestroy → `angular_components_advanced.md`
- **Change Detection**: Default vs OnPush, ChangeDetectorRef → `angular_components_advanced.md`
- **Dependency Injection**: providers, InjectionToken, hierarchical DI → `angular_components_advanced.md`
- **Router**: lazy loading, guards, resolvers → `angular_routing_forms.md`
- **Reactive Forms**: FormBuilder, FormArray, async validators → `angular_routing_forms.md`
- **RxJS**: switchMap, combineLatest, error handling → `angular_rxjs.md`
- **NgRx / Signals**: state management patterns → `angular_state_management.md`
- **Performance**: OnPush, @defer, SSR → `angular_performance_production.md`
- **Keywords**: ViewContainerRef, TemplateRef, ElementRef, Renderer2, HostBinding, HostListener, ContentChild, ViewChild, QueryList, forwardRef, inject() function
