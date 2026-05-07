# Angular State Management – BehaviorSubject, NgRx, Signals

## Mục lục
1. [Vấn đề State Management là gì? (What & Why)](#1-vấn-đề-state-management-là-gì-what--why)
2. [Pattern 1 – Service + BehaviorSubject](#2-pattern-1--service--behaviorsubject)
3. [Pattern 2 – NgRx (Full Redux Pattern)](#3-pattern-2--ngrx-full-redux-pattern)
4. [Pattern 3 – Angular Signals (Angular 16+)](#4-pattern-3--angular-signals-angular-16)
5. [So sánh & Khi nào dùng cái nào?](#5-so-sánh--khi-nào-dùng-cái-nào)

---

## 1. Vấn đề State Management là gì? (What & Why)

```
Vấn đề khi app lớn:
  ├── State phân tán: mỗi component tự giữ state riêng
  ├── Props drilling: truyền data qua nhiều tầng component
  ├── State sync: 2 components cùng cần 1 data, không đồng bộ
  ├── Time-travel debug: không biết state thay đổi lúc nào
  └── Predictability: state mutation khó trace

Giải pháp:
  Single Source of Truth → tập trung state vào 1 chỗ
  Unidirectional data flow → dễ predict, test, debug
```

```
Unidirectional Data Flow (Redux pattern):

  Component   →   Action   →   Reducer   →   State (Store)
      ↑                                           ↓
      └────────────── Selector ←──────────────────┘
                                  (derived data)
  Side effects (HTTP, localStorage):
  Action → Effect → API call → Success/Failure Action → Reducer → State
```

---

## 2. Pattern 1 – Service + BehaviorSubject

### 2.1 Khi nào dùng?
- App vừa và nhỏ (< 10 feature modules)
- Không cần time-travel debug
- Team ít kinh nghiệm NgRx
- State đơn giản, ít cross-feature dependency

### 2.2 Implementation

```typescript
// models/user.model.ts
export interface User {
  id: number;
  name: string;
  email: string;
  role: 'ADMIN' | 'USER';
}

export interface UserState {
  users: User[];
  selectedUser: User | null;
  isLoading: boolean;
  error: string | null;
}

// services/user-state.service.ts
@Injectable({ providedIn: 'root' })
export class UserStateService {
  // Private state — only service can modify
  private state$ = new BehaviorSubject<UserState>({
    users: [],
    selectedUser: null,
    isLoading: false,
    error: null,
  });

  // Public read-only selectors
  readonly users$ = this.state$.pipe(
    map(s => s.users),
    distinctUntilChanged()  // only emit when users array reference changes
  );

  readonly selectedUser$ = this.state$.pipe(
    map(s => s.selectedUser),
    distinctUntilChanged()
  );

  readonly isLoading$ = this.state$.pipe(map(s => s.isLoading));
  readonly error$ = this.state$.pipe(map(s => s.error));

  // Derived selectors
  readonly activeUsers$ = this.users$.pipe(
    map(users => users.filter(u => u.role !== 'INACTIVE'))
  );

  readonly adminCount$ = this.users$.pipe(
    map(users => users.filter(u => u.role === 'ADMIN').length)
  );

  constructor(private api: UserApiService) {}

  // Actions (state mutations)
  loadUsers(): void {
    this.patchState({ isLoading: true, error: null });

    this.api.getAll().subscribe({
      next: users => this.patchState({ users, isLoading: false }),
      error: err => this.patchState({ isLoading: false, error: err.message }),
    });
  }

  selectUser(userId: number): void {
    const user = this.state$.getValue().users.find(u => u.id === userId) ?? null;
    this.patchState({ selectedUser: user });
  }

  createUser(payload: CreateUserRequest): Observable<User> {
    return this.api.create(payload).pipe(
      tap(newUser => {
        const current = this.state$.getValue();
        this.patchState({ users: [...current.users, newUser] });
      })
    );
  }

  updateUser(id: number, payload: Partial<User>): Observable<User> {
    return this.api.update(id, payload).pipe(
      tap(updated => {
        const current = this.state$.getValue();
        this.patchState({
          users: current.users.map(u => u.id === id ? updated : u),
          selectedUser: current.selectedUser?.id === id ? updated : current.selectedUser,
        });
      })
    );
  }

  deleteUser(id: number): Observable<void> {
    const previous = this.state$.getValue();
    // Optimistic update
    this.patchState({ users: previous.users.filter(u => u.id !== id) });

    return this.api.delete(id).pipe(
      catchError(err => {
        this.patchState(previous);  // revert
        return throwError(() => err);
      })
    );
  }

  // Helper: partial state update
  private patchState(partial: Partial<UserState>): void {
    this.state$.next({ ...this.state$.getValue(), ...partial });
  }

  // Snapshot access (use sparingly)
  getSnapshot(): UserState {
    return this.state$.getValue();
  }
}

// Component usage
@Component({
  standalone: true,
  imports: [CommonModule, AsyncPipe],
  template: `
    @if (isLoading$ | async) { <spinner /> }
    
    @if (error$ | async; as error) {
      <p class="error">{{ error }}</p>
    }
    
    @for (user of users$ | async; track user.id) {
      <app-user-card [user]="user" (select)="onSelect(user.id)" />
    }
  `,
})
export class UserListComponent implements OnInit {
  users$ = this.userState.users$;
  isLoading$ = this.userState.isLoading$;
  error$ = this.userState.error$;

  constructor(private userState: UserStateService) {}

  ngOnInit(): void {
    this.userState.loadUsers();
  }

  onSelect(id: number): void {
    this.userState.selectUser(id);
  }
}
```

---

## 3. Pattern 2 – NgRx (Full Redux Pattern)

### 3.1 Setup

```bash
ng add @ngrx/store @ngrx/effects @ngrx/entity @ngrx/router-store
ng add @ngrx/store-devtools
```

### 3.2 Actions

```typescript
// store/user/user.actions.ts
import { createAction, props } from '@ngrx/store';
import { User, CreateUserRequest } from './user.model';

export const UserActions = {
  // Load
  loadUsers: createAction('[User List] Load Users'),
  loadUsersSuccess: createAction('[User API] Load Users Success', props<{ users: User[] }>()),
  loadUsersFailure: createAction('[User API] Load Users Failure', props<{ error: string }>()),

  // Select
  selectUser: createAction('[User List] Select User', props<{ userId: number }>()),

  // Create
  createUser: createAction('[User Form] Create User', props<{ payload: CreateUserRequest }>()),
  createUserSuccess: createAction('[User API] Create User Success', props<{ user: User }>()),
  createUserFailure: createAction('[User API] Create User Failure', props<{ error: string }>()),

  // Update
  updateUser: createAction('[User Form] Update User', props<{ id: number; changes: Partial<User> }>()),
  updateUserSuccess: createAction('[User API] Update User Success', props<{ user: User }>()),

  // Delete
  deleteUser: createAction('[User List] Delete User', props<{ id: number }>()),
  deleteUserSuccess: createAction('[User API] Delete User Success', props<{ id: number }>()),
};
```

### 3.3 Reducer (with @ngrx/entity)

```typescript
// store/user/user.reducer.ts
import { createEntityAdapter, EntityAdapter, EntityState } from '@ngrx/entity';
import { createReducer, on } from '@ngrx/store';

export interface UserState extends EntityState<User> {
  selectedUserId: number | null;
  isLoading: boolean;
  error: string | null;
}

export const adapter: EntityAdapter<User> = createEntityAdapter<User>({
  selectId: user => user.id,
  sortComparer: (a, b) => a.name.localeCompare(b.name),
});

const initialState: UserState = adapter.getInitialState({
  selectedUserId: null,
  isLoading: false,
  error: null,
});

export const userReducer = createReducer(
  initialState,

  on(UserActions.loadUsers, state => ({
    ...state, isLoading: true, error: null,
  })),

  on(UserActions.loadUsersSuccess, (state, { users }) =>
    adapter.setAll(users, { ...state, isLoading: false })
  ),

  on(UserActions.loadUsersFailure, (state, { error }) => ({
    ...state, isLoading: false, error,
  })),

  on(UserActions.selectUser, (state, { userId }) => ({
    ...state, selectedUserId: userId,
  })),

  on(UserActions.createUserSuccess, (state, { user }) =>
    adapter.addOne(user, state)
  ),

  on(UserActions.updateUserSuccess, (state, { user }) =>
    adapter.updateOne({ id: user.id, changes: user }, state)
  ),

  on(UserActions.deleteUserSuccess, (state, { id }) =>
    adapter.removeOne(id, state)
  ),
);
```

### 3.4 Selectors

```typescript
// store/user/user.selectors.ts
import { createSelector, createFeatureSelector } from '@ngrx/store';

const selectUserState = createFeatureSelector<UserState>('users');

// Entity adapter selectors
const { selectAll, selectEntities, selectIds, selectTotal } = adapter.getSelectors();

export const UserSelectors = {
  // Raw entity selectors (from adapter)
  allUsers: createSelector(selectUserState, selectAll),
  userEntities: createSelector(selectUserState, selectEntities),
  total: createSelector(selectUserState, selectTotal),

  // UI state
  isLoading: createSelector(selectUserState, s => s.isLoading),
  error: createSelector(selectUserState, s => s.error),
  selectedUserId: createSelector(selectUserState, s => s.selectedUserId),

  // Derived selectors
  selectedUser: createSelector(
    createSelector(selectUserState, selectEntities),
    createSelector(selectUserState, s => s.selectedUserId),
    (entities, selectedId) => selectedId ? entities[selectedId] ?? null : null,
  ),

  adminUsers: createSelector(
    createSelector(selectUserState, selectAll),
    users => users.filter(u => u.role === 'ADMIN'),
  ),

  userById: (id: number) => createSelector(
    createSelector(selectUserState, selectEntities),
    entities => entities[id] ?? null,
  ),

  // Combined ViewModel selector
  viewModel: createSelector(
    createSelector(selectUserState, selectAll),
    createSelector(selectUserState, s => s.isLoading),
    createSelector(selectUserState, s => s.error),
    (users, isLoading, error) => ({ users, isLoading, error }),
  ),
};
```

### 3.5 Effects

```typescript
// store/user/user.effects.ts
@Injectable()
export class UserEffects {

  loadUsers$ = createEffect(() =>
    this.actions$.pipe(
      ofType(UserActions.loadUsers),
      switchMap(() =>
        this.api.getAll().pipe(
          map(users => UserActions.loadUsersSuccess({ users })),
          catchError(err => of(UserActions.loadUsersFailure({ error: err.message }))),
        )
      ),
    )
  );

  createUser$ = createEffect(() =>
    this.actions$.pipe(
      ofType(UserActions.createUser),
      exhaustMap(({ payload }) =>
        this.api.create(payload).pipe(
          map(user => UserActions.createUserSuccess({ user })),
          catchError(err => of(UserActions.createUserFailure({ error: err.message }))),
        )
      ),
    )
  );

  // Non-dispatching effect (side effect only)
  notifyOnCreateSuccess$ = createEffect(() =>
    this.actions$.pipe(
      ofType(UserActions.createUserSuccess),
      tap(({ user }) => this.toastService.success(`User ${user.name} created!`)),
    ),
    { dispatch: false }
  );

  // Navigate after delete
  navigateAfterDelete$ = createEffect(() =>
    this.actions$.pipe(
      ofType(UserActions.deleteUserSuccess),
      tap(() => this.router.navigate(['/users'])),
    ),
    { dispatch: false }
  );

  constructor(
    private actions$: Actions,
    private api: UserApiService,
    private toastService: ToastService,
    private router: Router,
  ) {}
}
```

### 3.6 Store Registration & Component

```typescript
// app.config.ts
export const appConfig: ApplicationConfig = {
  providers: [
    provideStore({ users: userReducer }),
    provideEffects([UserEffects]),
    provideStoreDevtools({ maxAge: 25, logOnly: false }),
    provideRouterStore(),
  ],
};

// Feature module registration
// users.routes.ts
{
  path: 'users',
  providers: [provideState('users', userReducer), provideEffects([UserEffects])],
  loadComponent: () => import('./user-list.component').then(m => m.UserListComponent),
}

// Component
@Component({
  standalone: true,
  imports: [CommonModule, AsyncPipe],
})
export class UserListComponent implements OnInit {
  private store = inject(Store);

  vm$ = this.store.select(UserSelectors.viewModel);
  selectedUser$ = this.store.select(UserSelectors.selectedUser);

  ngOnInit(): void {
    this.store.dispatch(UserActions.loadUsers());
  }

  selectUser(userId: number): void {
    this.store.dispatch(UserActions.selectUser({ userId }));
  }

  deleteUser(id: number): void {
    this.store.dispatch(UserActions.deleteUser({ id }));
  }
}
```

---

## 4. Pattern 3 – Angular Signals (Angular 16+)

### 4.1 Core API

```typescript
import { signal, computed, effect, untracked } from '@angular/core';

// WritableSignal<T>
const count = signal(0);
const name = signal('John');

// Read
console.log(count());  // 0 — signals are functions, call to read

// Write
count.set(5);                    // replace value
count.update(c => c + 1);       // update based on previous
name.mutate(n => n.toUpperCase()); // mutate object/array in place (Angular 16)

// ComputedSignal — automatically updates when dependencies change
const doubled = computed(() => count() * 2);      // lazy, memoized
const fullName = computed(() => `${firstName()} ${lastName()}`);

// effect — side effects when signals change
effect(() => {
  // Runs when ANY signal read inside this function changes
  console.log('Count is now:', count());
  console.log('Doubled:', doubled());
  // Note: avoid writing signals inside effects (can cause infinite loops)
});

// untracked — read signal without tracking as dependency
effect(() => {
  const currentCount = count();  // tracked
  const label = untracked(() => labelSignal());  // NOT tracked
  console.log(`${label}: ${currentCount}`);
});
```

### 4.2 Signal-based Service (State Store)

```typescript
@Injectable({ providedIn: 'root' })
export class UserSignalService {
  // Private writable signals
  private _users = signal<User[]>([]);
  private _selectedId = signal<number | null>(null);
  private _isLoading = signal(false);
  private _error = signal<string | null>(null);

  // Public readonly (computed signals as selectors)
  readonly users = this._users.asReadonly();
  readonly isLoading = this._isLoading.asReadonly();
  readonly error = this._error.asReadonly();

  readonly selectedUser = computed(() => {
    const id = this._selectedId();
    return this._users().find(u => u.id === id) ?? null;
  });

  readonly activeUsers = computed(() =>
    this._users().filter(u => u.role !== 'INACTIVE')
  );

  readonly adminCount = computed(() =>
    this._users().filter(u => u.role === 'ADMIN').length
  );

  private api = inject(UserApiService);

  loadUsers(): void {
    this._isLoading.set(true);
    this._error.set(null);

    this.api.getAll().subscribe({
      next: users => {
        this._users.set(users);
        this._isLoading.set(false);
      },
      error: err => {
        this._error.set(err.message);
        this._isLoading.set(false);
      },
    });
  }

  selectUser(id: number): void {
    this._selectedId.set(id);
  }

  addUser(user: User): void {
    this._users.update(users => [...users, user]);
  }

  updateUser(id: number, changes: Partial<User>): void {
    this._users.update(users =>
      users.map(u => u.id === id ? { ...u, ...changes } : u)
    );
  }

  deleteUser(id: number): void {
    this._users.update(users => users.filter(u => u.id !== id));
  }
}

// Component — no async pipe needed!
@Component({
  changeDetection: ChangeDetectionStrategy.OnPush,  // signals work with OnPush
  template: `
    @if (state.isLoading()) {
      <spinner />
    }
    
    @if (state.error(); as error) {
      <p class="error">{{ error }}</p>
    }
    
    @for (user of state.users(); track user.id) {
      <app-user-card [user]="user" />
    }
    
    <p>Admins: {{ state.adminCount() }}</p>
  `,
})
export class UserListComponent implements OnInit {
  protected state = inject(UserSignalService);

  ngOnInit(): void {
    this.state.loadUsers();
  }
}
```

### 4.3 Signals + RxJS Interop (Angular 16+)

```typescript
import { toSignal, toObservable } from '@angular/core/rxjs-interop';

@Component({...})
export class SearchComponent {
  searchControl = new FormControl('');

  // Observable → Signal
  searchResults = toSignal(
    this.searchControl.valueChanges.pipe(
      debounceTime(400),
      distinctUntilChanged(),
      switchMap(term => this.api.search(term ?? '')),
    ),
    { initialValue: [] }  // required: signal must have initial value
  );

  // Signal → Observable
  private count = signal(0);
  count$ = toObservable(this.count);
}
```

### 4.4 linkedSignal & resource (Angular 19+)

```typescript
import { linkedSignal, resource } from '@angular/core';

// linkedSignal: writable signal that resets when source changes
const selectedPage = signal(1);
const pageSize = linkedSignal(() => {
  selectedPage();    // when page changes, reset pageSize
  return 20;         // to default value
});

// resource: async data loading with signals
const userId = signal(1);
const userResource = resource({
  request: () => ({ id: userId() }),
  loader: ({ request, abortSignal }) =>
    fetch(`/api/users/${request.id}`, { signal: abortSignal })
      .then(r => r.json()),
});

// Template
@if (userResource.isLoading()) { <spinner /> }
@if (userResource.value(); as user) { {{ user.name }} }
@if (userResource.error(); as err) { Error: {{ err }} }
```

---

## 5. So sánh & Khi nào dùng cái nào?

| | BehaviorSubject Service | NgRx | Signals |
|--|------------------------|------|---------|
| Boilerplate | Low | Very High | Low |
| Learning curve | Low | High | Medium |
| DevTools | Limited | Excellent (Redux DevTools) | Angular DevTools |
| Time-travel debug | ❌ | ✅ | ❌ (planned) |
| Testability | Good | Excellent (pure functions) | Good |
| Async handling | Manual (subscribe) | Effects (reactive) | resource() / toSignal() |
| Performance | Good | Good | Excellent (surgical updates) |
| Best app size | Small–Medium | Large Enterprise | Medium–Large |
| Zone.js needed | Yes | Yes | No (zoneless) |

**Decision Guide:**
```
App size < 5 features, team new to reactive?     → BehaviorSubject service
App has complex cross-feature state + team?      → NgRx
App is Angular 16+, want simpler DX?             → Signals + NgRx for complex
New project, Angular 18+, future-proof?          → Signals (zoneless ready)
```

---

## Ghi chú – Topics tiếp theo

- **Performance**: signals + OnPush = minimal re-renders → `angular_performance_production.md`
- **Testing NgRx**: MockStore, provideMockActions → `angular_performance_production.md`
- **Keywords**: createFeatureSelector, createActionGroup, on() type inference, EntityState, Dictionary, Update<T>, provideState, provideEffects, ActionCreator, TypedAction, MemoizedSelector, MemoizedSelectorWithProps, toSignal options (requireSync, manualCleanup), Signal<T>, WritableSignal<T>
