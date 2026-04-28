# Anti-patterns trong Java

## Tại sao học anti-patterns?

Anti-patterns là những giải pháp thoạt nhìn có vẻ hợp lý nhưng thực tế gây ra vấn đề: khó maintain, performance kém, bugs tiềm ẩn, hoặc security vulnerabilities. Nhận biết chúng giúp code review và refactoring hiệu quả hơn.

---

## 1. God Object (God Class)

### What
Một class biết quá nhiều, làm quá nhiều — vi phạm SRP nghiêm trọng.

### Dấu hiệu
```java
// ❌ God Object — 500+ lines, 30+ methods
class OrderManager {
    // User management
    User createUser(String email, String password) { ... }
    void sendWelcomeEmail(User u) { ... }

    // Order processing
    Order createOrder(User u, List<Item> items) { ... }
    BigDecimal calculateTotal(Order o) { ... }
    void applyDiscount(Order o, String code) { ... }

    // Payment
    boolean processPayment(Order o, CreditCard card) { ... }
    void refund(String orderId) { ... }
    void generateInvoice(Order o) { ... }

    // Inventory
    boolean checkStock(String productId, int qty) { ... }
    void reserveStock(String productId, int qty) { ... }
    void releaseStock(String productId, int qty) { ... }

    // Shipping
    void arrangeShipping(Order o, Address addr) { ... }
    String generateTrackingCode() { ... }
    void notifyShipped(Order o) { ... }

    // Reporting
    List<Order> getOrdersByDateRange(LocalDate from, LocalDate to) { ... }
    Map<String, BigDecimal> getRevenueByCategory() { ... }
    // ... 20 more methods
}
```

### Refactor
```java
// ✅ Separate services — SRP
@Service class UserService { User create(String email, String password); }
@Service class EmailService { void sendWelcome(User u); }
@Service class OrderService { Order create(User u, List<Item> items); }
@Service class PricingService { BigDecimal calculateTotal(Order o); void applyDiscount(Order o, String code); }
@Service class PaymentService { Payment process(Order o, PaymentMethod m); void refund(String paymentId); }
@Service class InventoryService { boolean checkAndReserve(String productId, int qty); }
@Service class ShippingService { Shipment arrange(Order o, Address addr); }
@Service class ReportingService { List<Order> byDateRange(LocalDate from, LocalDate to); }
```

---

## 2. Anemic Domain Model

### What
Domain objects chỉ có getters/setters — không có behavior. Business logic nằm hết ở Service layer.

### Dấu hiệu
```java
// ❌ Anemic — chỉ là data container
@Entity
class Order {
    private String id;
    private String status;  // "PENDING", "PAID", "CANCELLED"
    private BigDecimal total;
    private List<OrderItem> items;

    // Just getters and setters — no behavior
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    // ...
}

// Business logic bị "leak" vào service
@Service
class OrderService {
    void pay(String orderId, String paymentId) {
        Order order = repo.findById(orderId).orElseThrow();

        // ❌ Domain logic in service layer
        if (!"PENDING".equals(order.getStatus())) {
            throw new IllegalStateException("Can only pay pending orders");
        }
        if (order.getTotal().compareTo(BigDecimal.ZERO) <= 0) {
            throw new IllegalStateException("Order total must be positive");
        }
        order.setStatus("PAID");
        order.setPaymentId(paymentId);
        order.setPaidAt(Instant.now());
        repo.save(order);
    }

    void cancel(String orderId) {
        Order order = repo.findById(orderId).orElseThrow();
        // Same logic duplicated across services!
        if ("CANCELLED".equals(order.getStatus()) || "SHIPPED".equals(order.getStatus())) {
            throw new IllegalStateException("Cannot cancel");
        }
        order.setStatus("CANCELLED");
        repo.save(order);
    }
}
```

### Refactor — Rich Domain Model
```java
// ✅ Rich domain model — behavior in entity
@Entity
class Order {
    private String id;
    private OrderStatus status;  // enum, not String
    private BigDecimal total;

    // Business rules LIVE in the domain object
    void pay(String paymentId) {
        if (status != OrderStatus.PENDING)
            throw new IllegalStateException("Can only pay PENDING orders, current: " + status);
        this.status = OrderStatus.PAID;
        this.paymentId = paymentId;
        this.paidAt = Instant.now();
    }

    void cancel(String reason) {
        if (status == OrderStatus.SHIPPED || status == OrderStatus.DELIVERED)
            throw new IllegalStateException("Cannot cancel " + status + " order");
        if (status == OrderStatus.CANCELLED)
            throw new IllegalStateException("Already cancelled");
        this.status = OrderStatus.CANCELLED;
        this.cancelReason = reason;
    }

    boolean isPaid() { return status == OrderStatus.PAID; }
    boolean canBeCancelled() { return status == OrderStatus.PENDING || status == OrderStatus.PAID; }
}

// Service chỉ orchestrate — không chứa business logic
@Service
class OrderService {
    void pay(String orderId, String paymentId) {
        Order order = repo.findById(orderId).orElseThrow();
        order.pay(paymentId);  // business logic in domain
        repo.save(order);
    }
}
```

---

## 3. Primitive Obsession

### What
Dùng primitives (String, int, long) cho các domain concepts có ý nghĩa riêng.

### Dấu hiệu
```java
// ❌ Primitive Obsession
class User {
    String email;          // any string?
    String phoneNumber;    // format validated where?
    String countryCode;    // ISO 3166? which format?
    int age;               // negative? 200?
    String currency;       // USD? EUR? validated?
}

void transfer(String fromAccountId, String toAccountId, BigDecimal amount, String currency) {
    // Which string is which? Easy to swap by accident
    bankService.transfer(toAccountId, fromAccountId, amount, currency); // BUG — swapped!
}
```

### Refactor — Value Objects
```java
// ✅ Value Objects — records (Java 16+)
record Email(String value) {
    Email {
        Objects.requireNonNull(value);
        if (!value.matches("^[\\w.+-]+@[\\w-]+\\.[\\w.]+$"))
            throw new IllegalArgumentException("Invalid email: " + value);
        value = value.toLowerCase().strip();  // normalize
    }
    @Override public String toString() { return value; }
}

record PhoneNumber(String countryCode, String number) {
    PhoneNumber {
        if (!countryCode.matches("\\+\\d{1,3}")) throw new IllegalArgumentException("Invalid country code");
        if (!number.matches("\\d{7,15}")) throw new IllegalArgumentException("Invalid phone number");
    }
    String toE164() { return countryCode + number; }
}

record Money(BigDecimal amount, Currency currency) {
    Money {
        Objects.requireNonNull(amount);
        Objects.requireNonNull(currency);
        if (amount.scale() > currency.getDefaultFractionDigits())
            throw new IllegalArgumentException("Too many decimal places for " + currency);
    }
    Money add(Money other) {
        if (!currency.equals(other.currency)) throw new IllegalArgumentException("Currency mismatch");
        return new Money(amount.add(other.amount), currency);
    }
    boolean isNegative() { return amount.compareTo(BigDecimal.ZERO) < 0; }
}

record AccountId(String value) {
    AccountId {
        if (!value.matches("ACC-[A-Z0-9]{8}")) throw new IllegalArgumentException("Invalid account ID");
    }
}

// Now method signature is self-documenting and type-safe
void transfer(AccountId from, AccountId to, Money amount) {
    // transfer(to, from, amount) — compiler catches swap!
}
```

---

## 4. Service Locator

### What
Dùng global registry để "pull" dependencies thay vì nhận qua constructor (DI).

### Dấu hiệu
```java
// ❌ Service Locator — hidden dependencies
class OrderService {
    void placeOrder(PlaceOrderCmd cmd) {
        // Dependencies hidden, not declared in constructor
        UserRepository userRepo = ServiceLocator.get(UserRepository.class);
        InventoryService inventory = ServiceLocator.get(InventoryService.class);
        PaymentGateway payment = ServiceLocator.get(PaymentGateway.class);

        // Hard to test — must configure ServiceLocator in tests
        // Hard to see what this class needs at a glance
        // Runtime error if service not registered (not compile-time)
    }
}
```

### Refactor — Constructor Injection
```java
// ✅ Explicit Dependencies via Constructor Injection
@Service
class OrderService {
    private final UserRepository userRepo;
    private final InventoryService inventory;
    private final PaymentGateway payment;

    // Dependencies visible, testable, immutable
    OrderService(UserRepository userRepo, InventoryService inventory, PaymentGateway payment) {
        this.userRepo = Objects.requireNonNull(userRepo);
        this.inventory = Objects.requireNonNull(inventory);
        this.payment = Objects.requireNonNull(payment);
    }

    // In tests — just pass mocks
}

// Test
@Test
void placeOrder_deductsInventory() {
    UserRepository mockRepo = mock(UserRepository.class);
    InventoryService mockInventory = mock(InventoryService.class);
    PaymentGateway mockPayment = mock(PaymentGateway.class);

    OrderService service = new OrderService(mockRepo, mockInventory, mockPayment);
    // test...
}
```

---

## 5. Singleton Overuse

### What
Mọi service/util đều là Singleton → global mutable state, hidden coupling, thread-safety issues.

### Dấu hiệu
```java
// ❌ Singleton với mutable state
class UserCache {
    private static UserCache instance;
    private Map<String, User> cache = new HashMap<>();  // NOT thread-safe!

    public static UserCache getInstance() {
        if (instance == null) instance = new UserCache();  // race condition!
        return instance;
    }

    public void put(String id, User user) { cache.put(id, user); }
    public User get(String id) { return cache.get(id); }
}

// ❌ Usage — hidden global state
class OrderService {
    void process(Order o) {
        User user = UserCache.getInstance().get(o.getUserId()); // hidden dependency
    }
}
```

### Problems
- **Thread safety**: HashMap không thread-safe → `ConcurrentModificationException`
- **Test isolation**: Global state leaks between tests
- **Hidden coupling**: Class doesn't declare its dependency
- **Memory leaks**: Never cleared if cached objects hold resources

### Refactor
```java
// ✅ Spring-managed bean (Singleton scope by default, but injectable)
@Service
class UserCacheService {
    private final Cache<String, User> cache = Caffeine.newBuilder()
        .maximumSize(10_000)
        .expireAfterWrite(Duration.ofMinutes(10))
        .build();

    public Optional<User> get(String id) { return Optional.ofNullable(cache.getIfPresent(id)); }
    public void put(String id, User user) { cache.put(id, user); }
    public void evict(String id) { cache.invalidate(id); }
}

// ✅ Explicit dependency
@Service
class OrderService {
    private final UserCacheService userCache;
    OrderService(UserCacheService userCache) { this.userCache = userCache; }
}

// ✅ In tests — inject mock
@Test void process_usesCache() {
    UserCacheService mockCache = mock(UserCacheService.class);
    when(mockCache.get("u1")).thenReturn(Optional.of(testUser));
    new OrderService(mockCache).process(testOrder);
}
```

---

## 6. Magic Numbers & Magic Strings

### Dấu hiệu
```java
// ❌ Magic numbers — what does 86400, 3, "ACTIVE" mean?
if (Duration.between(createdAt, now).getSeconds() > 86400) { ... }
if (retryCount >= 3) { ... }
if ("ACTIVE".equals(user.getStatus())) { ... }
if (user.getRole() == 2) { ... }  // 2 = ADMIN? MANAGER?

// ❌ Magic string query
String query = "SELECT * FROM users WHERE status = 'ACT' AND role_id = 4";
```

### Refactor
```java
// ✅ Named constants
private static final Duration SESSION_EXPIRY = Duration.ofDays(1);
private static final int MAX_RETRY_ATTEMPTS = 3;

// ✅ Enums
enum UserStatus { ACTIVE, INACTIVE, BANNED }
enum UserRole { USER, MANAGER, ADMIN }

if (Duration.between(createdAt, now).compareTo(SESSION_EXPIRY) > 0) { ... }
if (retryCount >= MAX_RETRY_ATTEMPTS) { ... }
if (user.getStatus() == UserStatus.ACTIVE) { ... }  // type-safe, autocomplete
if (user.getRole() == UserRole.ADMIN) { ... }
```

---

## 7. Exception Swallowing

### Dấu hiệu
```java
// ❌ Swallowing — silent failure
try {
    processPayment(order);
} catch (Exception e) {
    // say nothing, do nothing
}

// ❌ Meaningless catch-all
try {
    riskOperation();
} catch (Exception e) {
    return null;  // caller has no idea something went wrong
}

// ❌ Log and ignore
try {
    sendEmail(user);
} catch (EmailException e) {
    log.error("Email failed");  // no stack trace, no rethrow
}
```

### Refactor
```java
// ✅ Handle specifically or rethrow
try {
    processPayment(order);
} catch (InsufficientFundsException e) {
    // Expected — handle gracefully
    notifyUser(order.getUserId(), "Payment failed: insufficient funds");
    order.markFailed("INSUFFICIENT_FUNDS");
} catch (PaymentGatewayException e) {
    // Unexpected — rethrow with context
    throw new OrderProcessingException("Payment gateway error for order " + order.getId(), e);
}

// ✅ Log with full context
try {
    sendEmail(user);
} catch (EmailException e) {
    log.error("Failed to send email to user {} ({}): {}", user.getId(), user.getEmail(), e.getMessage(), e);
    // Decide: rethrow? schedule retry? mark as failed?
    emailRetryQueue.add(new EmailTask(user, EmailType.WELCOME));
}
```

---

## 8. Null Overuse (Null as Sentinel)

### Dấu hiệu
```java
// ❌ null as "not found", "optional", "error", "default"
User findUser(String id) {
    // returns null if not found
    return db.queryForObject("SELECT * FROM users WHERE id = ?", ..., id);
}

// Caller must remember to null-check (and often forgets)
User user = findUser(id);
String name = user.getName(); // NullPointerException!

// ❌ null as boolean flag
String getDiscountCode(Order o) {
    return o.isPremium() ? "PREMIUM20" : null;  // null = no discount?
}
```

### Refactor
```java
// ✅ Optional for "may not exist"
Optional<User> findUser(String id) {
    return Optional.ofNullable(db.queryForObject("...", ..., id));
}

// Caller must explicitly handle both cases
findUser(id)
    .map(User::getName)
    .ifPresentOrElse(
        name -> display(name),
        () -> display("Guest")
    );

// Or throw with clear semantics
User user = findUser(id)
    .orElseThrow(() -> new UserNotFoundException("User not found: " + id));

// ✅ Sealed types for result
sealed interface FindResult<T> permits FindResult.Found, FindResult.NotFound {}
record Found<T>(T value) implements FindResult<T> {}
record NotFound<T>(String reason) implements FindResult<T> {}

FindResult<User> result = userRepo.find(id);
switch (result) {
    case Found(User u) -> display(u);
    case NotFound(String r) -> log.warn("Not found: {}", r);
}
```

---

## 9. Premature Optimization Anti-patterns

### Over-caching
```java
// ❌ Cache everything — cache invalidation is the hard problem
@Cacheable("users")  // cached forever? cleared when?
User findUser(String id) { ... }

@CacheEvict("users") // but what if other things also modify users?
void updateUser(User u) { ... }

// ✅ Cache only hot, read-heavy, stable data
// ✅ Set explicit TTL
// ✅ Measure before caching — profile first
```

### Premature Multi-threading
```java
// ❌ Thread per request — exhausts memory
void handleRequest(Request req) {
    new Thread(() -> process(req)).start();  // unbounded threads!
}

// ✅ Thread pool with bounded queue
ExecutorService pool = new ThreadPoolExecutor(
    4, 16, 60, SECONDS,
    new LinkedBlockingQueue<>(1000),  // bounded
    new ThreadPoolExecutor.CallerRunsPolicy()  // backpressure
);
```

---

## 10. Leaky Abstractions

### Returning Internal Collections (defensive copy missing)
```java
// ❌ Expose internal mutable collection
class Order {
    private List<OrderItem> items = new ArrayList<>();
    public List<OrderItem> getItems() { return items; }  // caller can mutate!
}

Order o = new Order();
o.getItems().clear();  // corrupted order!
o.getItems().add(maliciousItem);
```

### Refactor
```java
class Order {
    private final List<OrderItem> items = new ArrayList<>();

    // Option 1: unmodifiable view
    public List<OrderItem> getItems() { return Collections.unmodifiableList(items); }

    // Option 2: defensive copy
    public List<OrderItem> getItems() { return new ArrayList<>(items); }

    // Option 3: expose only meaningful operations
    public void addItem(OrderItem item) { ... }
    public void removeItem(String itemId) { ... }
    public int itemCount() { return items.size(); }
    public BigDecimal total() { return items.stream().map(OrderItem::price).reduce(BigDecimal.ZERO, BigDecimal::add); }
}
```

---

## 11. String Building Anti-patterns

### String Concatenation in Loop
```java
// ❌ O(n²) — creates new String object every iteration
String result = "";
for (String s : largeList) {
    result += s + ", ";  // new String every time!
}

// ✅ StringBuilder
StringBuilder sb = new StringBuilder(largeList.size() * 20); // capacity hint
for (String s : largeList) {
    sb.append(s).append(", ");
}
String result = sb.toString();

// ✅ Or Stream
String result = String.join(", ", largeList);
// Or
String result = largeList.stream().collect(Collectors.joining(", "));
```

---

## 12. Concurrent Anti-patterns

### Non-atomic Check-then-Act
```java
// ❌ Race condition — check and act are NOT atomic
if (!map.containsKey(key)) {      // Thread A checks → true
    map.put(key, createValue());   // Thread B also checks → true, both put!
}

// ✅ Atomic operation
map.computeIfAbsent(key, k -> createValue());  // atomic in ConcurrentHashMap

// ❌ Non-atomic compound operation
long current = counter.get();
counter.set(current + 1);  // race between get and set!

// ✅ Atomic update
counter.incrementAndGet();
counter.getAndAdd(delta);
counter.updateAndGet(n -> n + delta);
```

### Synchronized on Wrong Object
```java
// ❌ Synchronizing on local/non-shared object
void addItem(Item item) {
    String key = item.getType();
    synchronized (key) {  // String interning may share, but not guaranteed!
        items.add(item);   // different callers may sync on different String instances
    }
}

// ❌ Synchronizing on 'this' when multiple instances exist
class Counter {
    private int count;
    synchronized void increment() { count++; }  // ok if single instance, dangerous if confused
}

// ✅ Explicit lock object or AtomicInteger
class BetterCounter {
    private final AtomicInteger count = new AtomicInteger();
    void increment() { count.incrementAndGet(); }

    // Or if complex logic:
    private final Object lock = new Object();
    void complexOperation() { synchronized (lock) { /* ... */ } }
}
```

---

## 13. JPA Anti-patterns

### LazyInitializationException in wrong context
```java
// ❌ Load entity, close session, access lazy collection
@Transactional
Order findOrder(String id) {
    return orderRepo.findById(id).orElseThrow();
}

// Later, OUTSIDE transaction:
Order order = orderService.findOrder(id);
int count = order.getItems().size();  // LazyInitializationException!

// ✅ Load what you need in the transaction
@Transactional
OrderDTO findOrder(String id) {
    Order order = orderRepo.findByIdWithItems(id);  // JOIN FETCH
    return OrderMapper.toDTO(order);  // convert before leaving transaction
}
```

### N+1 in loop
```java
// ❌ N+1 — 1 query for list + N queries for each item's lazy collection
List<Order> orders = orderRepo.findAll();  // 1 query
for (Order o : orders) {
    int count = o.getItems().size();  // N queries!
}

// ✅ JOIN FETCH
List<Order> orders = em.createQuery(
    "SELECT DISTINCT o FROM Order o JOIN FETCH o.items", Order.class).getResultList();
```

---

## Tổng hợp Anti-patterns

| Anti-pattern | Vấn đề | Refactor |
|-------------|--------|----------|
| God Object | Quá nhiều trách nhiệm | Tách thành services nhỏ |
| Anemic Domain | Logic không ở domain | Đưa behavior vào entities |
| Primitive Obsession | String/int cho domain concepts | Value Objects (Records) |
| Service Locator | Hidden dependencies | Constructor Injection |
| Singleton Overuse | Global mutable state | Spring-managed beans |
| Magic Numbers | Khó đọc, không rõ nghĩa | Constants, Enums |
| Exception Swallowing | Silent failures | Handle or rethrow with context |
| Null Overuse | NullPointerException | Optional, Sealed types |
| Leaky Abstraction | Mutable internal state exposed | Defensive copy, unmodifiable |
| String Concat in Loop | O(n²) performance | StringBuilder, String.join |
| Non-atomic Check-then-Act | Race conditions | computeIfAbsent, AtomicXxx |
| N+1 Query | Performance degradation | JOIN FETCH, @BatchSize |

---

## Ghi chú

**Nhận biết code smell sớm:**
- Method > 20 lines → có thể tách
- Class > 200 lines → có thể tách
- > 3 tham số method → xem xét Parameter Object / Builder
- `null` return → dùng `Optional`
- `instanceof` chain → dùng polymorphism hoặc sealed + switch
- `static` mutable field → global state smell

**Refactoring approach:**
1. Viết test coverage trước khi refactor
2. Refactor nhỏ từng bước, không bigbang rewrite
3. Measure performance trước và sau optimization
4. Code review — anti-patterns thường dễ nhận ra khi có người khác nhìn vào
