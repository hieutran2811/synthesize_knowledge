# RxJS in Angular – Reactive Programming

## Mục lục
1. [Observable vs Promise (What & Why)](#1-observable-vs-promise-what--why)
2. [Subjects](#2-subjects)
3. [Core Operators](#3-core-operators)
4. [Higher-Order Mapping Operators](#4-higher-order-mapping-operators)
5. [Combination Operators](#5-combination-operators)
6. [Error Handling](#6-error-handling)
7. [async pipe & Subscription Management](#7-async-pipe--subscription-management)
8. [Real-world RxJS Patterns](#8-real-world-rxjs-patterns)

---

## 1. Observable vs Promise (What & Why)

### 1.1 Observable là gì?

**Observable** là một luồng dữ liệu bất đồng bộ có thể phát ra 0..N giá trị theo thời gian, có thể bị cancel, có thể được compose.

```
Observable timeline:
  ─────●─────●─────●─────●────X──→
        1     2     3     4   complete

  ─────●─────●─────✕──→
        1     2   error

Promise timeline:
  ──────────────────●──→  (một giá trị, không cancel)
                 resolve
```

### 1.2 Observable vs Promise vs Signal

| | Observable | Promise | Signal |
|--|-----------|---------|--------|
| Values | 0..N over time | Exactly 1 | Current value (sync) |
| Cancellable | ✅ Yes (unsubscribe) | ❌ No | N/A |
| Lazy | ✅ (cold by default) | ❌ (eager, starts immediately) | N/A |
| Operators | Rich (100+) | .then/.catch only | limited (computed/effect) |
| Use case | HTTP, events, streams | Simple async | Reactive state UI |
| Angular integration | HttpClient, Router, Forms | Limited | Template, Change Detection |

### 1.3 Cold vs Hot Observable

```typescript
// Cold Observable: starts fresh for EACH subscriber
const cold$ = new Observable(observer => {
  console.log('Producer started');      // runs per subscription
  observer.next(Math.random());         // each subscriber gets own value
  observer.next(Math.random());
  observer.complete();
});

cold$.subscribe(v => console.log('Sub1:', v));  // Producer started → 0.42, 0.87
cold$.subscribe(v => console.log('Sub2:', v));  // Producer started → 0.13, 0.95

// Hot Observable: shared producer, late subscribers miss values
// (BehaviorSubject, fromEvent, share() operator)

// HttpClient returns COLD — new HTTP request per subscription!
// Pitfall: subscribe twice → 2 HTTP requests
const users$ = this.http.get('/users');
users$.subscribe(u => console.log('List:', u));   // HTTP request 1
users$.subscribe(u => console.log('Count:', u));  // HTTP request 2 (!)

// Fix: shareReplay(1) → makes it hot, replays last value
const users$ = this.http.get('/users').pipe(shareReplay(1));
```

---

## 2. Subjects

```typescript
// Subject: hot, multicast, no initial value
const subject = new Subject<number>();
subject.subscribe(v => console.log('A:', v));
subject.next(1);  // A: 1
subject.subscribe(v => console.log('B:', v));  // B subscribes late
subject.next(2);  // A: 2, B: 2  (B misses the 1)

// BehaviorSubject: hot, multicast, HAS current value
const behavior$ = new BehaviorSubject<number>(0);  // initial value = 0
behavior$.subscribe(v => console.log('A:', v));    // A: 0 (immediate)
behavior$.next(1);                                 // A: 1
behavior$.subscribe(v => console.log('B:', v));    // B: 1 (gets current value)
behavior$.next(2);                                 // A: 2, B: 2

const current = behavior$.getValue();              // synchronous read

// ReplaySubject: buffers N last values for late subscribers
const replay$ = new ReplaySubject<number>(3);      // buffer size 3
replay$.next(1);
replay$.next(2);
replay$.next(3);
replay$.next(4);
replay$.subscribe(v => console.log(v));            // 2, 3, 4 (last 3)

// AsyncSubject: emits only the LAST value when completed
const async$ = new AsyncSubject<number>();
async$.subscribe(v => console.log(v));
async$.next(1);
async$.next(2);
async$.next(3);
async$.complete();  // → 3 (only last value on complete)

// Best practices in Angular services
@Injectable({ providedIn: 'root' })
export class CartService {
  private items$ = new BehaviorSubject<CartItem[]>([]);

  // Expose as Observable (hide Subject internals — encapsulation)
  readonly cart$: Observable<CartItem[]> = this.items$.asObservable();

  addItem(item: CartItem): void {
    this.items$.next([...this.items$.getValue(), item]);
  }

  removeItem(id: number): void {
    this.items$.next(this.items$.getValue().filter(i => i.id !== id));
  }
}
```

---

## 3. Core Operators

### 3.1 Transformation

```typescript
import { map, pluck, mapTo, scan, reduce, pairwise, buffer, bufferTime } from 'rxjs/operators';

// map: transform each value
users$.pipe(
  map(users => users.filter(u => u.active)),  // filter only active users
  map(users => users.map(u => u.name)),        // extract names
)

// scan: running accumulation (like reduce but emits each step)
clicks$.pipe(
  scan((count, _) => count + 1, 0)  // click counter
)

// pairwise: emit pairs [previous, current]
prices$.pipe(
  pairwise(),                              // [prev, curr]
  map(([prev, curr]) => curr - prev)       // price change
)

// buffer: collect values until trigger fires
mouseMoves$.pipe(
  bufferTime(500),                   // collect 500ms worth of moves
  filter(moves => moves.length > 0), // skip empty buffers
)
```

### 3.2 Filtering

```typescript
// filter
values$.pipe(filter(v => v > 0))

// take / takeWhile / takeUntil
stream$.pipe(take(5))                                    // first 5 values
stream$.pipe(takeWhile(v => v < 100))                   // until condition false
stream$.pipe(takeUntil(this.destroy$))                  // until another observable emits

// skip / skipWhile / skipUntil
stream$.pipe(skip(1))                                    // skip first value (useful for BehaviorSubject initial)
stream$.pipe(skipWhile(v => v === null))                // skip nulls at start

// distinct
stream$.pipe(distinct())                                // skip ALL previously seen values
stream$.pipe(distinctUntilChanged())                    // skip consecutive duplicates
stream$.pipe(distinctUntilKeyChanged('id'))             // compare by key

// debounce / throttle
searchInput$.pipe(
  debounceTime(400),           // wait 400ms of silence before emitting
  distinctUntilChanged(),      // skip if same value
)

clicks$.pipe(
  throttleTime(1000),          // max 1 emit per second
)

// first / last / elementAt
stream$.pipe(first())                    // first value then complete
stream$.pipe(first(v => v > 0))         // first value matching predicate
stream$.pipe(last())                     // last value (needs completion)
```

---

## 4. Higher-Order Mapping Operators

**Vấn đề**: khi giá trị emitted là một Observable (Observable<Observable<T>>), cần flatten.

```
Observable<Observable<T>> → Observable<T>

switchMap:    cancel previous inner observable when new outer value arrives
mergeMap:     run all inner observables concurrently
concatMap:    queue inner observables, run one at a time (in order)
exhaustMap:   ignore new outer values while inner is running
```

### 4.1 switchMap – Cancel & Replace

```typescript
// Search typeahead: cancel previous HTTP request when user types again
searchTerm$.pipe(
  debounceTime(400),
  distinctUntilChanged(),
  switchMap(term =>                                // cancel previous request!
    this.api.searchUsers(term).pipe(
      catchError(() => of([]))                     // handle error gracefully
    )
  )
).subscribe(results => this.results = results);

// Route param changes: switch to new user
this.route.paramMap.pipe(
  map(params => +params.get('id')!),
  switchMap(id => this.userService.getById(id))
).subscribe(user => this.user = user);

// When to use switchMap:
// ✓ Search/autocomplete (cancel obsolete requests)
// ✓ Route param changes
// ✓ "Latest value wins" scenarios
```

### 4.2 mergeMap – Concurrent

```typescript
// Process all items concurrently (no ordering guarantee)
userIds$.pipe(
  mergeMap(id => this.userService.getById(id), 5)  // max 5 concurrent
).subscribe(user => this.processUser(user));

// File uploads: all concurrent
selectedFiles$.pipe(
  mergeMap(file => this.uploadService.upload(file))
).subscribe(result => this.onUploaded(result));

// When to use mergeMap:
// ✓ Independent parallel requests
// ✓ Order doesn't matter
// ✓ All results needed
```

### 4.3 concatMap – Sequential (Preserve Order)

```typescript
// Process operations in order (queue)
saveActions$.pipe(
  concatMap(action => this.api.save(action))  // wait for each to complete
).subscribe(result => console.log('Saved:', result));

// Animations: play in sequence
animationTriggers$.pipe(
  concatMap(trigger => this.animate(trigger))  // one at a time
)

// When to use concatMap:
// ✓ Order matters (e.g., save operations)
// ✓ Avoid race conditions
// ✓ Sequential animations
```

### 4.4 exhaustMap – Ignore Until Done

```typescript
// Form submit: ignore button clicks while request is pending
submitClicks$.pipe(
  exhaustMap(() => this.api.createOrder(this.form.value))  // ignore new clicks
).subscribe(order => this.onOrderCreated(order));

// Login button: prevent duplicate requests
loginButton.click$.pipe(
  exhaustMap(() => this.authService.login(credentials))
)

// When to use exhaustMap:
// ✓ Button clicks triggering requests (prevent duplicates)
// ✓ "First wins" scenarios
// ✓ Polling: ignore new poll until current finishes
```

### 4.5 Operator Decision Tree

```
Need to flatten Observable<Observable<T>>?
  ├── Latest value wins / cancel old?  → switchMap
  ├── Parallel, order doesn't matter? → mergeMap
  ├── Sequential, preserve order?     → concatMap
  └── Ignore new while busy?          → exhaustMap
```

---

## 5. Combination Operators

```typescript
// combineLatest: emit when ANY source emits, combining LATEST from all
combineLatest([
  this.userService.currentUser$,
  this.settingsService.theme$,
  this.permissionsService.roles$,
]).pipe(
  map(([user, theme, roles]) => ({ user, theme, roles }))
).subscribe(state => this.updateUI(state));

// Note: combineLatest waits for ALL sources to emit at least once

// forkJoin: wait for ALL to COMPLETE, emit last values (like Promise.all)
forkJoin({
  users: this.userService.getAll(),
  departments: this.deptService.getAll(),
  roles: this.roleService.getAll(),
}).subscribe(({ users, departments, roles }) => {
  this.initializeForm(users, departments, roles);
});

// merge: merge multiple observables into one (interleaved)
merge(
  this.keyboardShortcuts$,
  this.toolbarActions$,
  this.contextMenuActions$,
).subscribe(action => this.handleAction(action));

// zip: emit when ALL sources emit (pairs by index)
zip(
  this.uploadProgress$,
  this.processingProgress$,
).pipe(
  map(([upload, process]) => (upload + process) / 2)  // combined progress
)

// withLatestFrom: combine with latest from second, triggered by first
buttonClicks$.pipe(
  withLatestFrom(this.currentUser$),  // attach current user to each click
  switchMap(([click, user]) => this.api.performAction(user.id))
)

// startWith: prefix observable with initial value
data$.pipe(
  startWith(null),  // emit null immediately (for loading states)
)

// pairwise
prices$.pipe(
  pairwise(),
  map(([prev, curr]) => ({ prev, curr, change: curr - prev }))
)
```

---

## 6. Error Handling

```typescript
// catchError: handle and optionally recover
this.api.getUsers().pipe(
  catchError(error => {
    if (error.status === 404) return of([]);          // return empty array
    if (error.status === 401) {
      this.router.navigate(['/login']);
      return EMPTY;                                    // complete without value
    }
    return throwError(() => new Error('Failed to load users'));  // rethrow
  })
)

// retry: retry N times on error
this.api.getUsers().pipe(
  retry(3),                             // retry 3 times immediately
)

// retryWhen / retry with config (RxJS 7+)
this.api.getUsers().pipe(
  retry({
    count: 3,
    delay: (error, retryCount) => {
      if (error.status === 503) {
        return timer(retryCount * 1000);  // exponential backoff: 1s, 2s, 3s
      }
      return throwError(() => error);    // don't retry 4xx errors
    },
  })
)

// finalize: cleanup regardless of success/error (like finally)
this.api.getUsers().pipe(
  finalize(() => this.isLoading = false)
)

// Full pattern with loading state
this.isLoading = true;
this.api.getUsers().pipe(
  catchError(err => {
    this.error = 'Failed to load users';
    return of([]);
  }),
  finalize(() => this.isLoading = false),
).subscribe(users => this.users = users);
```

---

## 7. async pipe & Subscription Management

### 7.1 async pipe (Preferred)

```typescript
@Component({
  standalone: true,
  imports: [CommonModule, AsyncPipe],
  template: `
    <!-- async pipe: subscribe, unsubscribe, handle null automatically -->
    @if (user$ | async; as user) {
      <div>{{ user.name }}</div>
    }
    
    <!-- Multiple observables -->
    @if ({ user: user$ | async, orders: orders$ | async }; as vm) {
      <user-card [user]="vm.user" />
      <order-list [orders]="vm.orders" />
    }
    
    <!-- Error handling with async -->
    @if (data$ | async; as data) {
      {{ data | json }}
    } @else {
      Loading...
    }
  `,
})
export class UserDashboardComponent {
  user$ = this.userService.currentUser$;
  orders$ = this.orderService.getOrders().pipe(
    catchError(() => of([]))
  );

  // ViewModel pattern — combine multiple streams
  vm$ = combineLatest({
    user: this.userService.currentUser$,
    orders: this.orderService.getOrders().pipe(catchError(() => of([]))),
    isAdmin: this.authService.hasRole('ADMIN'),
  });
}
```

### 7.2 Subscription Management Patterns

```typescript
// Pattern 1: takeUntilDestroyed (Angular 16+ — simplest)
@Component({...})
export class Component1 {
  constructor(private service: DataService) {
    this.service.data$
      .pipe(takeUntilDestroyed())  // no inject needed in constructor
      .subscribe(data => this.data = data);
  }
}

// Pattern 2: destroy$ Subject (classic)
@Component({...})
export class Component2 implements OnDestroy {
  private destroy$ = new Subject<void>();

  ngOnInit(): void {
    this.service.data$
      .pipe(takeUntil(this.destroy$))
      .subscribe(data => this.data = data);
  }

  ngOnDestroy(): void {
    this.destroy$.next();
    this.destroy$.complete();
  }
}

// Pattern 3: Declarative (no subscribe — use async pipe)
@Component({...})
export class Component3 {
  // No subscription needed — async pipe handles everything
  data$ = this.service.data$.pipe(
    map(data => this.transform(data)),
    catchError(() => of(null))
  );
}
```

---

## 8. Real-world RxJS Patterns

### 8.1 Search Typeahead

```typescript
@Component({
  template: `
    <input [formControl]="searchControl" placeholder="Search users..." />
    @for (user of searchResults$ | async; track user.id) {
      <p>{{ user.name }}</p>
    }
  `,
})
export class UserSearchComponent {
  searchControl = new FormControl('');

  searchResults$ = this.searchControl.valueChanges.pipe(
    startWith(''),
    debounceTime(400),
    distinctUntilChanged(),
    filter(term => term!.length >= 2),
    switchMap(term =>
      this.userService.search(term!).pipe(
        catchError(() => of([]))
      )
    ),
    shareReplay(1),
  );
}
```

### 8.2 Polling

```typescript
// Poll every 30s, restart on manual trigger, stop on destroy
@Component({...})
export class LiveDataComponent {
  private refresh$ = new Subject<void>();

  liveData$ = merge(
    this.refresh$.pipe(startWith(null)),  // immediate + manual refresh
    timer(0, 30_000),                     // poll every 30s
  ).pipe(
    switchMap(() => this.api.getLiveData().pipe(
      catchError(() => of(null))
    )),
    filter(data => data !== null),
    takeUntilDestroyed(),
  );

  forceRefresh(): void {
    this.refresh$.next();
  }
}
```

### 8.3 Optimistic UI Update

```typescript
@Injectable({ providedIn: 'root' })
export class TodoService {
  private todos$ = new BehaviorSubject<Todo[]>([]);

  deleteTodo(id: number): Observable<void> {
    const previousState = this.todos$.getValue();

    // Optimistic: update UI immediately
    this.todos$.next(previousState.filter(t => t.id !== id));

    // Then confirm with server
    return this.api.deleteTodo(id).pipe(
      catchError(error => {
        // Revert on error
        this.todos$.next(previousState);
        return throwError(() => error);
      })
    );
  }
}
```

---

## Ghi chú – Topics tiếp theo

- **NgRx Effects** là nơi RxJS operators được dùng nhiều nhất → `angular_state_management.md`
- **Angular Signals** vs RxJS: khi nào dùng cái nào → `angular_state_management.md`
- **Performance**: shareReplay pitfalls (memory leak), async pipe vs manual subscribe → `angular_performance_production.md`
- **Keywords**: from, of, interval, timer, fromEvent, EMPTY, NEVER, iif, defer, generate, race, partition, groupBy, window, throttleTime vs auditTime vs sampleTime, toArray, multicast, publish, share vs shareReplay, connectable, connect
