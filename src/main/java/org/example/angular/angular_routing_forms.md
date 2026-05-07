# Angular Routing & Forms – Deep Dive

## Mục lục
1. [Angular Router](#1-angular-router)
2. [Lazy Loading & Code Splitting](#2-lazy-loading--code-splitting)
3. [Route Guards](#3-route-guards)
4. [Route Resolvers & Data Prefetching](#4-route-resolvers--data-prefetching)
5. [Template-driven Forms](#5-template-driven-forms)
6. [Reactive Forms Deep](#6-reactive-forms-deep)
7. [Custom Validators](#7-custom-validators)
8. [ControlValueAccessor – Custom Form Controls](#8-controlvalueaccessor--custom-form-controls)

---

## 1. Angular Router

### 1.1 Route Configuration

```typescript
// app.routes.ts
export const routes: Routes = [
  // Redirect
  { path: '', redirectTo: '/home', pathMatch: 'full' },

  // Static routes
  { path: 'home', component: HomeComponent },
  { path: 'about', component: AboutComponent },

  // Route with params
  { path: 'users/:id', component: UserDetailComponent },
  { path: 'users/:id/orders/:orderId', component: OrderDetailComponent },

  // Child routes (nested)
  {
    path: 'admin',
    component: AdminLayoutComponent,
    children: [
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
      { path: 'dashboard', component: DashboardComponent },
      { path: 'users', component: AdminUsersComponent },
    ],
  },

  // Lazy loading (discussed below)
  {
    path: 'products',
    loadChildren: () => import('./features/products/products.routes')
      .then(m => m.PRODUCT_ROUTES),
  },

  // Named outlet (secondary router-outlet)
  { path: 'chat', component: ChatComponent, outlet: 'sidebar' },

  // Wildcard
  { path: '**', component: NotFoundComponent },
];
```

### 1.2 Router Navigation

```typescript
@Component({
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  template: `
    <!-- RouterLink directive -->
    <a routerLink="/home">Home</a>
    <a [routerLink]="['/users', userId]">User Profile</a>
    <a [routerLink]="['/users', userId]"
       [queryParams]="{ tab: 'orders', page: 1 }"
       fragment="top"
       routerLinkActive="active"           <!-- add class when route is active -->
       [routerLinkActiveOptions]="{ exact: true }">
      Profile
    </a>
    
    <router-outlet />                       <!-- primary outlet -->
    <router-outlet name="sidebar" />        <!-- named outlet -->
  `,
})
export class AppComponent {
  constructor(
    private router: Router,
    private route: ActivatedRoute,
  ) {}

  navigate(): void {
    // Programmatic navigation
    this.router.navigate(['/users', 42]);
    this.router.navigate(['/users', 42], { queryParams: { tab: 'orders' } });
    this.router.navigate(['../sibling'], { relativeTo: this.route });
    
    // Navigate and detect if successful
    this.router.navigateByUrl('/users/42?tab=orders#section1');
  }

  readParams(): void {
    // Snapshot (one-time read)
    const id = this.route.snapshot.paramMap.get('id');
    const tab = this.route.snapshot.queryParamMap.get('tab');
    const data = this.route.snapshot.data['user'];  // resolver data

    // Observable (react to param changes — same component, different params)
    this.route.paramMap.subscribe(params => {
      const userId = params.get('id');
      this.loadUser(+userId!);
    });

    // Combine params and queryParams
    combineLatest([this.route.paramMap, this.route.queryParamMap])
      .subscribe(([params, queryParams]) => {
        const id = params.get('id');
        const page = queryParams.get('page') ?? '1';
        this.loadUser(+id!, +page);
      });
  }
}
```

### 1.3 Router Events

```typescript
@Injectable({ providedIn: 'root' })
export class NavigationService {
  isLoading = false;

  constructor(private router: Router) {
    this.router.events.pipe(
      filter(event =>
        event instanceof NavigationStart ||
        event instanceof NavigationEnd ||
        event instanceof NavigationCancel ||
        event instanceof NavigationError
      ),
    ).subscribe(event => {
      if (event instanceof NavigationStart) this.isLoading = true;
      if (event instanceof NavigationEnd ||
          event instanceof NavigationCancel ||
          event instanceof NavigationError) {
        this.isLoading = false;
      }
    });
  }
}
```

---

## 2. Lazy Loading & Code Splitting

### 2.1 Route-level Lazy Loading

```typescript
// products.routes.ts (standalone routes file)
export const PRODUCT_ROUTES: Routes = [
  { path: '', component: ProductListComponent },
  { path: ':id', component: ProductDetailComponent },
  { path: ':id/edit', component: ProductEditComponent },
];

// app.routes.ts
const routes: Routes = [
  {
    path: 'products',
    loadChildren: () => import('./features/products/products.routes')
      .then(m => m.PRODUCT_ROUTES),
  },
  // Lazy load single component (Angular 14+)
  {
    path: 'dashboard',
    loadComponent: () => import('./features/dashboard/dashboard.component')
      .then(m => m.DashboardComponent),
  },
];
```

### 2.2 Preloading Strategies

```typescript
bootstrapApplication(AppComponent, {
  providers: [
    provideRouter(
      routes,
      // Option 1: Preload nothing (default)
      withNoPreloading(),
      
      // Option 2: Preload ALL lazy modules after initial load
      withPreloading(PreloadAllModules),
      
      // Option 3: Custom preloading strategy
      withPreloading(SelectivePreloadingStrategy),
    ),
  ],
});

// Custom: only preload routes with data.preload = true
@Injectable({ providedIn: 'root' })
export class SelectivePreloadingStrategy implements PreloadingStrategy {
  preload(route: Route, load: () => Observable<any>): Observable<any> {
    return route.data?.['preload'] ? load() : EMPTY;
  }
}

// Mark routes for preloading
{
  path: 'dashboard',
  data: { preload: true },
  loadChildren: () => import('./dashboard/dashboard.routes').then(m => m.routes),
}
```

---

## 3. Route Guards

### 3.1 Functional Guards (Angular 15+ — Recommended)

```typescript
// canActivate: prevent access if not authenticated
export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  if (authService.isAuthenticated()) return true;

  return router.createUrlTree(['/login'], {
    queryParams: { returnUrl: state.url },
  });
};

// canActivate with role check
export const roleGuard = (requiredRole: string): CanActivateFn => {
  return (route, state) => {
    const authService = inject(AuthService);
    const router = inject(Router);

    if (authService.hasRole(requiredRole)) return true;

    return router.createUrlTree(['/forbidden']);
  };
};

// Async guard (check from API)
export const subscriptionGuard: CanActivateFn = (route, state) => {
  const subscriptionService = inject(SubscriptionService);
  const router = inject(Router);

  return subscriptionService.checkAccess(route.data['feature']).pipe(
    map(hasAccess => hasAccess ? true : router.createUrlTree(['/upgrade'])),
    catchError(() => of(router.createUrlTree(['/error']))),
  );
};

// canDeactivate: prevent leaving dirty forms
export const unsavedChangesGuard: CanDeactivateFn<HasUnsavedChanges> = (component) => {
  if (!component.hasUnsavedChanges()) return true;

  return confirm('You have unsaved changes. Are you sure you want to leave?');
};

// Interface for components
export interface HasUnsavedChanges {
  hasUnsavedChanges(): boolean;
}
```

### 3.2 Apply Guards in Routes

```typescript
const routes: Routes = [
  {
    path: 'dashboard',
    component: DashboardComponent,
    canActivate: [authGuard],
  },
  {
    path: 'admin',
    component: AdminComponent,
    canActivate: [authGuard, roleGuard('ADMIN')],
    canActivateChild: [authGuard],
    children: [
      { path: 'users', component: AdminUsersComponent },
    ],
  },
  {
    path: 'edit/:id',
    component: EditComponent,
    canDeactivate: [unsavedChangesGuard],
  },
  {
    path: 'premium',
    canMatch: [authGuard],   // canMatch: prevent route from matching (Angular 14+)
    loadChildren: () => import('./premium/routes').then(m => m.routes),
  },
];
```

---

## 4. Route Resolvers & Data Prefetching

```typescript
// user.resolver.ts — prefetch data before route activates
export const userResolver: ResolveFn<User> = (route, state) => {
  const userService = inject(UserApiService);
  const router = inject(Router);

  const id = route.paramMap.get('id');
  if (!id) return router.createUrlTree(['/not-found']);

  return userService.getById(+id).pipe(
    catchError(() => {
      router.navigate(['/not-found']);
      return EMPTY;  // cancel navigation
    }),
  );
};

// Route config
{
  path: 'users/:id',
  component: UserDetailComponent,
  resolve: { user: userResolver },          // key 'user' → available in route.data
  title: userTitleResolver,                 // dynamic page title (Angular 14+)
}

// Title resolver
export const userTitleResolver: ResolveFn<string> = (route) => {
  return inject(UserApiService).getById(+route.paramMap.get('id')!)
    .pipe(map(user => `${user.name} - My App`));
};

// Component reads resolved data
@Component({...})
export class UserDetailComponent implements OnInit {
  user!: User;

  constructor(private route: ActivatedRoute) {}

  ngOnInit(): void {
    this.user = this.route.snapshot.data['user'];
    // Or observable for param changes:
    this.route.data.subscribe(data => this.user = data['user']);
  }
}
```

---

## 5. Template-driven Forms

```typescript
@Component({
  standalone: true,
  imports: [FormsModule, CommonModule],
  template: `
    <form #loginForm="ngForm" (ngSubmit)="onSubmit(loginForm)">
      
      <div>
        <label for="email">Email</label>
        <input id="email"
               type="email"
               name="email"
               [(ngModel)]="model.email"
               required
               email
               #emailField="ngModel" />
        
        @if (emailField.invalid && emailField.touched) {
          @if (emailField.errors?.['required']) {
            <span class="error">Email is required</span>
          }
          @if (emailField.errors?.['email']) {
            <span class="error">Invalid email format</span>
          }
        }
      </div>
      
      <div>
        <input name="password"
               type="password"
               [(ngModel)]="model.password"
               required
               minlength="8"
               #pwField="ngModel" />
               
        @if (pwField.invalid && pwField.touched) {
          <span class="error">Password must be at least 8 characters</span>
        }
      </div>
      
      <button type="submit" [disabled]="loginForm.invalid || isLoading">
        {{ isLoading ? 'Logging in...' : 'Login' }}
      </button>
    </form>
  `,
})
export class LoginFormComponent {
  model = { email: '', password: '' };
  isLoading = false;

  onSubmit(form: NgForm): void {
    if (form.invalid) return;
    this.isLoading = true;
    // submit...
  }
}
```

---

## 6. Reactive Forms Deep

### 6.1 FormBuilder & FormGroup

```typescript
@Component({
  standalone: true,
  imports: [ReactiveFormsModule, CommonModule],
})
export class UserRegistrationComponent implements OnInit {
  
  form!: FormGroup;
  
  constructor(private fb: FormBuilder) {}

  ngOnInit(): void {
    this.form = this.fb.group({
      // [initial value, validators, async validators]
      firstName: ['', [Validators.required, Validators.minLength(2), Validators.maxLength(50)]],
      lastName:  ['', Validators.required],
      email:     ['', [Validators.required, Validators.email], [this.uniqueEmailValidator]],
      password:  ['', [
        Validators.required,
        Validators.minLength(8),
        Validators.pattern(/^(?=.*[A-Z])(?=.*[0-9]).*$/),
      ]],
      confirmPassword: ['', Validators.required],
      
      address: this.fb.group({
        street: ['', Validators.required],
        city:   ['', Validators.required],
        zip:    ['', [Validators.required, Validators.pattern(/^\d{5}$/)]],
      }),
      
      roles: this.fb.array([]),        // FormArray

      // Typed: FormControl<string> (Angular 14+)
      phone: new FormControl<string>('', { nonNullable: true }),
    }, {
      validators: [passwordMatchValidator],  // cross-field validator
    });
    
    // Listen to value changes
    this.form.get('email')!.valueChanges
      .pipe(debounceTime(400), distinctUntilChanged())
      .subscribe(email => console.log('Email changed:', email));
    
    // Disable/enable fields conditionally
    this.form.get('address')!.statusChanges.subscribe(status => {
      const zip = this.form.get('address.zip');
      if (status === 'VALID') zip?.enable();
      else zip?.disable();
    });
  }

  // FormArray helpers
  get roles(): FormArray {
    return this.form.get('roles') as FormArray;
  }

  addRole(): void {
    this.roles.push(this.fb.control('', Validators.required));
  }

  removeRole(index: number): void {
    this.roles.removeAt(index);
  }

  onSubmit(): void {
    if (this.form.invalid) {
      this.form.markAllAsTouched();  // show all errors
      return;
    }
    console.log(this.form.getRawValue());  // getRawValue() includes disabled controls
  }

  resetForm(): void {
    this.form.reset({ firstName: '', lastName: '' });  // partial reset with values
  }

  // Patch vs setValue
  loadExistingUser(user: User): void {
    this.form.patchValue(user);   // patch: only provided fields (safe for partial)
    // this.form.setValue(user);  // setValue: ALL fields required (error if missing)
  }
}
```

### 6.2 Typed Forms (Angular 14+)

```typescript
// Fully type-safe form
interface RegistrationForm {
  email: FormControl<string>;
  password: FormControl<string>;
  profile: FormGroup<{
    name: FormControl<string>;
    age: FormControl<number | null>;
  }>;
}

const form = new FormGroup<RegistrationForm>({
  email: new FormControl('', { nonNullable: true, validators: [Validators.required] }),
  password: new FormControl('', { nonNullable: true }),
  profile: new FormGroup({
    name: new FormControl('', { nonNullable: true }),
    age: new FormControl<number | null>(null),
  }),
});

// TypeScript knows the type of each control
const email: string = form.value.email!;         // string
const age: number | null | undefined = form.value.profile?.age;  // typed
```

---

## 7. Custom Validators

### 7.1 Synchronous Validators

```typescript
// Standalone validator function
export function passwordStrengthValidator(control: AbstractControl): ValidationErrors | null {
  const value = control.value as string;
  if (!value) return null;

  const hasUpperCase = /[A-Z]/.test(value);
  const hasLowerCase = /[a-z]/.test(value);
  const hasNumeric = /[0-9]/.test(value);
  const hasSpecial = /[!@#$%^&*]/.test(value);

  const strength = [hasUpperCase, hasLowerCase, hasNumeric, hasSpecial].filter(Boolean).length;

  if (strength < 3) {
    return {
      passwordStrength: {
        actual: strength,
        required: 3,
        message: 'Password must contain uppercase, lowercase, number, and special character'
      }
    };
  }
  return null;
}

// Cross-field validator (at group level)
export const passwordMatchValidator: ValidatorFn = (group: AbstractControl): ValidationErrors | null => {
  const password = group.get('password')?.value;
  const confirm = group.get('confirmPassword')?.value;
  return password === confirm ? null : { passwordMismatch: true };
};

// Usage
this.fb.group({
  password: ['', passwordStrengthValidator],
  confirmPassword: [''],
}, { validators: passwordMatchValidator });
```

### 7.2 Async Validators

```typescript
// Check email uniqueness via API
export function uniqueEmailValidator(userService: UserApiService): AsyncValidatorFn {
  return (control: AbstractControl): Observable<ValidationErrors | null> => {
    if (!control.value) return of(null);

    return timer(400).pipe(  // debounce
      switchMap(() => userService.checkEmailExists(control.value)),
      map(exists => exists ? { emailTaken: true } : null),
      catchError(() => of(null)),  // don't block form on API error
    );
  };
}

// In component
this.fb.group({
  email: [
    '',
    [Validators.required, Validators.email],      // sync validators
    [uniqueEmailValidator(this.userService)],      // async validators
  ],
});

// Template: show pending state
@if (form.get('email')!.pending) {
  <span>Checking availability...</span>
}
@if (form.get('email')!.errors?.['emailTaken']) {
  <span class="error">Email is already taken</span>
}
```

---

## 8. ControlValueAccessor – Custom Form Controls

```typescript
// Custom rating input: <app-rating [(ngModel)]="rating" />
//                   or: <app-rating formControlName="rating" />
@Component({
  selector: 'app-rating',
  standalone: true,
  template: `
    <div class="stars">
      @for (star of stars; track star) {
        <span
          [class.filled]="star <= value"
          (click)="onRate(star)"
          (mouseenter)="hovered = star"
          (mouseleave)="hovered = 0">
          ★
        </span>
      }
    </div>
  `,
  providers: [{
    provide: NG_VALUE_ACCESSOR,
    useExisting: forwardRef(() => RatingComponent),
    multi: true,
  }],
})
export class RatingComponent implements ControlValueAccessor {
  stars = [1, 2, 3, 4, 5];
  value = 0;
  hovered = 0;
  disabled = false;

  // Called by Angular when model changes from outside
  writeValue(value: number): void {
    this.value = value || 0;
  }

  // Register callback for when internal value changes
  registerOnChange(fn: (value: number) => void): void {
    this.onChange = fn;
  }

  // Register callback for when control is touched
  registerOnTouched(fn: () => void): void {
    this.onTouched = fn;
  }

  // Called by Angular when form control is disabled
  setDisabledState(disabled: boolean): void {
    this.disabled = disabled;
  }

  onRate(star: number): void {
    if (this.disabled) return;
    this.value = star;
    this.onChange(star);
    this.onTouched();
  }

  private onChange: (value: number) => void = () => {};
  private onTouched: () => void = () => {};
}

// Usage
<app-rating formControlName="rating" />
<app-rating [(ngModel)]="productRating" [disabled]="isReadonly" />
```

---

## Ghi chú – Topics tiếp theo

- **RxJS operators** dùng trong guards/resolvers: switchMap, catchError, takeUntil → `angular_rxjs.md`
- **State management**: form state across routes → `angular_state_management.md`
- **Performance**: lazy loading + preloading chiến lược → `angular_performance_production.md`
- **Keywords**: RouterStateSnapshot, ActivatedRouteSnapshot, UrlTree, PRIMARY_OUTLET, ChildActivationEnd, RouteReuseStrategy, ScrollPositionRestoration, ParamMap, Data, CanLoad (deprecated → canMatch), NavigationExtras, FormRecord, NonNullableFormBuilder
