# Enterprise & Architectural Patterns

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú
>
> 📖 Tra cứu thuật ngữ: xem [glossary.md](../glossary.md)

## Tổng quan

Enterprise patterns giải quyết vấn đề ở tầng kiến trúc — không chỉ object design. Chúng xử lý: persistence abstraction, domain complexity, distributed consistency, fault tolerance.

> 💡 **Giải thích dễ hiểu — pattern enterprise là cách phối hợp nhiều sổ sách và dịch vụ:**
> Khi hệ thống vượt khỏi một process và một transaction, vấn đề không còn chỉ là class nào gọi class nào. Ta phải quản lý state ở đâu, thay đổi nào commit cùng nhau, event có bị mất không và lỗi của một dịch vụ có kéo sập dịch vụ khác không. Mỗi pattern dưới đây giải một lực cản cụ thể và đồng thời thêm chi phí vận hành riêng.

---

## 1. Repository Pattern

### What
Repository tạo ra một abstraction layer giữa domain layer và data access layer. Domain code làm việc với `Collection<Entity>` interface — không biết gì về SQL, JPA, hay HTTP.

> 💡 **Giải thích dễ hiểu — Repository là “kho domain”, không phải tên mới của mọi DAO:**
> Domain hỏi `findActiveUsers()` hoặc `save(order)` bằng ngôn ngữ nghiệp vụ, giống làm việc với một collection các aggregate. Repository giấu cách lấy/lưu aggregate và thường đặt ranh giới quanh aggregate root. DAO gần database hơn, có thể thao tác table, row hoặc câu CRUD. Một dự án CRUD đơn giản có thể dùng Spring Data repository như data-access abstraction mà không cần dựng thêm domain repository riêng.

### How
```java
// Domain interface — không import gì từ JPA/JDBC
interface UserRepository {
    Optional<User> findById(UserId id);
    List<User> findByEmail(Email email);
    List<User> findActiveUsers();
    void save(User user);
    void delete(UserId id);
}

// Domain model — pure Java, no annotations
class User {
    private final UserId id;
    private Email email;
    private UserStatus status;
    private final Instant createdAt;

    // business methods
    void activate() {
        if (status == UserStatus.BANNED) throw new DomainException("Banned user cannot activate");
        this.status = UserStatus.ACTIVE;
    }
    void ban(String reason) { this.status = UserStatus.BANNED; }
    boolean isActive() { return status == UserStatus.ACTIVE; }
}

// JPA implementation — infrastructure layer
@Repository
class JpaUserRepository implements UserRepository {
    private final EntityManager em;

    @Override
    public Optional<User> findById(UserId id) {
        UserEntity entity = em.find(UserEntity.class, id.value());
        return Optional.ofNullable(entity).map(UserMapper::toDomain);
    }

    @Override
    public List<User> findActiveUsers() {
        return em.createQuery(
                "SELECT u FROM UserEntity u WHERE u.status = 'ACTIVE'", UserEntity.class)
            .getResultList()
            .stream()
            .map(UserMapper::toDomain)
            .toList();
    }

    @Override
    public void save(User user) {
        UserEntity entity = UserMapper.toEntity(user);
        em.merge(entity);
    }
}

// In-memory implementation — dùng cho tests
class InMemoryUserRepository implements UserRepository {
    private final Map<UserId, User> store = new ConcurrentHashMap<>();

    @Override public Optional<User> findById(UserId id) { return Optional.ofNullable(store.get(id)); }
    @Override public void save(User user) { store.put(user.getId(), user); }
    @Override public void delete(UserId id) { store.remove(id); }
    @Override public List<User> findByEmail(Email email) {
        return store.values().stream().filter(u -> u.getEmail().equals(email)).toList();
    }
    @Override public List<User> findActiveUsers() {
        return store.values().stream().filter(User::isActive).toList();
    }
}

// Application service uses interface — không biết implementation
@Service
class UserService {
    private final UserRepository userRepo;  // DI — JPA in prod, InMemory in test

    void activateUser(UserId id) {
        User user = userRepo.findById(id)
            .orElseThrow(() -> new UserNotFoundException(id));
        user.activate();
        userRepo.save(user);
    }
}
```

### Repository vs DAO

| | Repository | DAO |
|---|---|---|
| Abstraction | Domain concepts | Database operations |
| Return type | Domain objects | DTOs / ResultSet |
| Language | Business terms | CRUD terms |
| Scope | Aggregate root | Any table |
| Layer | Domain | Infrastructure |

```java
// DAO — database-centric
interface UserDao {
    UserDto selectById(long id);
    int insertUser(UserDto dto);
    int updateStatus(long id, String status);
}

// Repository — domain-centric
interface UserRepository {
    Optional<User> findById(UserId id);
    void save(User user);  // insert or update decided internally
    List<User> findActiveUsers();  // domain query, not SQL
}
```

---

## 2. Unit of Work Pattern

### What
Tracks tất cả changes trong một business transaction, batches chúng lại và commit một lần — tránh multiple round trips và đảm bảo consistency.

> 💡 **Giải thích dễ hiểu — Unit of Work là phiếu theo dõi thay đổi trong một ca làm:**
> Trong transaction, nó ghi entity nào mới, bẩn hoặc bị xóa rồi flush theo một đơn vị commit/rollback. Điều quan trọng là **ranh giới nhất quán**, không phải lời hứa mọi SQL chỉ cần một round trip; ORM vẫn có thể phát nhiều statement, dù batching có thể giảm số chuyến mạng. Giữ Unit of Work quá lâu cũng làm persistence context phình và dữ liệu stale.

### How — JPA EntityManager là Unit of Work
```java
// JPA persistence context = Unit of Work implementation
@Service
@Transactional
class OrderService {
    private final EntityManager em;

    void placeOrder(PlaceOrderCommand cmd) {
        // UoW tracks all loaded entities
        Order order = new Order(cmd.userId(), cmd.items());
        em.persist(order);  // registered as "new"

        User user = em.find(User.class, cmd.userId());
        user.incrementOrderCount();  // tracked as "dirty"

        Inventory inventory = em.find(Inventory.class, cmd.productId());
        inventory.reserve(cmd.quantity());  // tracked as "dirty"

        // On transaction commit → UoW flushes all changes:
        // INSERT INTO orders ...
        // UPDATE users SET order_count = ...
        // UPDATE inventory SET reserved = ...
        // All in one transaction
    }
}
```

### Custom Unit of Work (non-JPA)
```java
class UnitOfWork {
    private final Map<Object, Object> newObjects = new LinkedHashMap<>();
    private final Map<Object, Object> dirtyObjects = new LinkedHashMap<>();
    private final Set<Object> deletedObjects = new LinkedHashSet<>();

    void registerNew(Object entity) { newObjects.put(getId(entity), entity); }
    void registerDirty(Object entity) {
        if (!newObjects.containsKey(getId(entity))) {
            dirtyObjects.put(getId(entity), entity);
        }
    }
    void registerDeleted(Object entity) {
        newObjects.remove(getId(entity));
        dirtyObjects.remove(getId(entity));
        deletedObjects.add(entity);
    }

    void commit(DataSource ds) throws SQLException {
        try (Connection conn = ds.getConnection()) {
            conn.setAutoCommit(false);
            try {
                for (Object obj : newObjects.values()) insert(conn, obj);
                for (Object obj : dirtyObjects.values()) update(conn, obj);
                for (Object obj : deletedObjects) delete(conn, obj);
                conn.commit();
            } catch (SQLException e) {
                conn.rollback();
                throw e;
            }
        }
    }
}
```

---

## 3. CQRS (Command Query Responsibility Segregation)

### What
Tách model đọc (Query) và model ghi (Command) thành hai path riêng biệt. Không phải event sourcing — CQRS có thể dùng với traditional DB.

> 💡 **Giải thích dễ hiểu — quầy nhập liệu và quầy tra cứu dùng mẫu khác nhau:**
> Phía ghi cần domain model bảo vệ invariant; phía đọc thường cần DTO phẳng, join và index tối ưu cho màn hình. CQRS chỉ yêu cầu tách trách nhiệm/model, không bắt buộc hai service, hai database hay event sourcing. Nếu cả hai path vẫn dùng chung database và transaction, hệ thống vẫn có thể nhất quán tức thời; eventual consistency xuất hiện khi read model được đồng bộ bất đồng bộ.

```
┌─────────────────────────────────────────────────────────┐
│                    API Controller                        │
└───────────┬─────────────────────────┬───────────────────┘
            │ Command                 │ Query
            ▼                         ▼
   ┌─────────────────┐       ┌─────────────────┐
   │  Command Bus    │       │   Query Bus     │
   └────────┬────────┘       └────────┬────────┘
            │                         │
            ▼                         ▼
   ┌─────────────────┐       ┌─────────────────┐
   │ Command Handler │       │  Query Handler  │
   │ (Domain logic)  │       │ (Read-optimized)│
   └────────┬────────┘       └────────┬────────┘
            │                         │
            ▼                         ▼
   ┌─────────────────┐       ┌─────────────────┐
   │   Write Model   │       │   Read Model    │
   │ (Domain objects)│       │ (DTOs/views)    │
   └────────┬────────┘       └────────┬────────┘
            │                         │
            └──────────┬──────────────┘
                       │
              ┌────────▼────────┐
              │    Database     │
              │ (same or diff)  │
              └─────────────────┘
```

### Implementation
```java
// Commands — immutable value objects (sealed + records)
sealed interface Command permits PlaceOrder, CancelOrder, UpdateShippingAddress {}
record PlaceOrder(String userId, List<OrderItem> items) implements Command {}
record CancelOrder(String orderId, String reason) implements Command {}

// Queries
sealed interface Query permits GetOrder, GetUserOrders, GetOrderSummary {}
record GetOrder(String orderId) implements Query {}
record GetUserOrders(String userId, int page, int size) implements Query {}

// Command handler — domain logic
@Service
class OrderCommandHandler {
    private final OrderRepository orderRepo;
    private final EventBus eventBus;

    @Transactional
    void handle(PlaceOrder cmd) {
        Order order = Order.place(cmd.userId(), cmd.items());
        orderRepo.save(order);
        eventBus.publish(new OrderPlaced(order.getId(), cmd.userId()));
    }

    @Transactional
    void handle(CancelOrder cmd) {
        Order order = orderRepo.findById(cmd.orderId()).orElseThrow();
        order.cancel(cmd.reason());
        orderRepo.save(order);
    }
}

// Query handler — optimized for reading (flat DTOs, no domain objects)
@Service
class OrderQueryHandler {
    private final JdbcTemplate jdbc;  // bypass JPA for performance

    OrderDTO handle(GetOrder q) {
        return jdbc.queryForObject(
            """
            SELECT o.id, o.status, o.total_amount, u.email,
                   COUNT(oi.id) as item_count
            FROM orders o
            JOIN users u ON o.user_id = u.id
            JOIN order_items oi ON oi.order_id = o.id
            WHERE o.id = ?
            GROUP BY o.id, o.status, o.total_amount, u.email
            """,
            (rs, _) -> new OrderDTO(
                rs.getString("id"),
                rs.getString("status"),
                rs.getBigDecimal("total_amount"),
                rs.getString("email"),
                rs.getInt("item_count")
            ),
            q.orderId()
        );
    }

    Page<OrderSummaryDTO> handle(GetUserOrders q) {
        // Optimized query with pagination — không load domain objects
        List<OrderSummaryDTO> items = jdbc.query(
            "SELECT id, status, total_amount, created_at FROM orders WHERE user_id = ? LIMIT ? OFFSET ?",
            (rs, _) -> new OrderSummaryDTO(rs.getString("id"), rs.getString("status"),
                rs.getBigDecimal("total_amount"), rs.getTimestamp("created_at").toInstant()),
            q.userId(), q.size(), q.page() * q.size()
        );
        int total = jdbc.queryForObject("SELECT COUNT(*) FROM orders WHERE user_id = ?",
            Integer.class, q.userId());
        return new PageImpl<>(items, PageRequest.of(q.page(), q.size()), total);
    }
}

// Command/Query bus — dispatcher
@Component
class CommandBus {
    private final ApplicationContext ctx;

    @SuppressWarnings("unchecked")
    <C extends Command> void dispatch(C command) {
        // Find handler by convention or registry
        String handlerName = command.getClass().getSimpleName() + "Handler";
        // or use Map<Class<?>, CommandHandler<?>> registry
    }
}
```

### Khi dùng CQRS
- Read/Write load asymmetric (đọc 10x nhiều hơn ghi)
- Read model cần join nhiều table → optimized projection
- Write model complex (domain rules) nhưng read model đơn giản

### Khi KHÔNG dùng CQRS
- CRUD apps đơn giản — over-engineering
- Team nhỏ, deadline gấp
- Read và Write model gần giống nhau

---

## 4. Event Sourcing

### What
Thay vì lưu current state, lưu **sequence of events** dẫn đến state đó. State = fold over events.

> 💡 **Giải thích dễ hiểu — lưu sổ giao dịch thay vì chỉ lưu số dư:**
> Số dư 750 không kể được nó hình thành thế nào; chuỗi Opened, Deposited, Withdrawn thì có thể replay để dựng lại state và audit lịch sử. Đổi lại, event đã lưu trở thành dữ liệu lâu dài: schema event cần versioning/upcasting, handler replay phải deterministic và side effect không được chạy lại tùy tiện.

```
Traditional:     DB stores: { balance: 750 }
Event Sourcing:  DB stores:
                   [AccountOpened(1000), Deposited(500), Withdrawn(750)]
                 State = 1000 + 500 - 750 = 750  ← computed
```

### Implementation
```java
// Event store interface
interface EventStore {
    void append(String aggregateId, long expectedVersion, List<DomainEvent> events);
    List<DomainEvent> load(String aggregateId);
    List<DomainEvent> loadFrom(String aggregateId, long fromVersion);
}

// Aggregate base class
abstract class AggregateRoot {
    private final List<DomainEvent> uncommittedEvents = new ArrayList<>();
    private long version = 0;

    protected void apply(DomainEvent event) {
        handleEvent(event);  // update in-memory state
        uncommittedEvents.add(event);
        version++;
    }

    protected abstract void handleEvent(DomainEvent event);

    // Reconstruction from event history
    void replayEvents(List<DomainEvent> events) {
        events.forEach(e -> {
            handleEvent(e);
            version++;
        });
    }

    List<DomainEvent> getUncommittedEvents() { return Collections.unmodifiableList(uncommittedEvents); }
    void markEventsCommitted() { uncommittedEvents.clear(); }
    long getVersion() { return version; }
}

// Bank account aggregate
class BankAccount extends AggregateRoot {
    private String accountId;
    private BigDecimal balance;
    private boolean closed;

    // Reconstruction constructor
    static BankAccount reconstitute(List<DomainEvent> events) {
        BankAccount acc = new BankAccount();
        acc.replayEvents(events);
        return acc;
    }

    // Business commands — produce events
    void open(String id, BigDecimal initialBalance) {
        if (initialBalance.compareTo(BigDecimal.ZERO) < 0)
            throw new DomainException("Initial balance cannot be negative");
        apply(new AccountOpened(id, initialBalance, Instant.now()));
    }

    void deposit(BigDecimal amount) {
        if (closed) throw new DomainException("Account is closed");
        if (amount.compareTo(BigDecimal.ZERO) <= 0) throw new DomainException("Amount must be positive");
        apply(new MoneyDeposited(accountId, amount, Instant.now()));
    }

    void withdraw(BigDecimal amount) {
        if (closed) throw new DomainException("Account is closed");
        if (balance.compareTo(amount) < 0) throw new DomainException("Insufficient funds");
        apply(new MoneyWithdrawn(accountId, amount, Instant.now()));
    }

    // Event handlers — update state only (no business logic)
    @Override
    protected void handleEvent(DomainEvent event) {
        switch (event) {
            case AccountOpened e  -> { accountId = e.accountId(); balance = e.initialBalance(); closed = false; }
            case MoneyDeposited e -> balance = balance.add(e.amount());
            case MoneyWithdrawn e -> balance = balance.subtract(e.amount());
            case AccountClosed e  -> closed = true;
            default -> throw new IllegalArgumentException("Unknown event: " + event.getClass());
        }
    }
}

// Repository với event store
@Repository
class BankAccountRepository {
    private final EventStore eventStore;

    BankAccount load(String id) {
        List<DomainEvent> events = eventStore.load(id);
        if (events.isEmpty()) throw new EntityNotFoundException(id);
        return BankAccount.reconstitute(events);
    }

    void save(BankAccount account) {
        List<DomainEvent> events = account.getUncommittedEvents();
        if (events.isEmpty()) return;
        eventStore.append(account.getId(), account.getVersion() - events.size(), events);
        account.markEventsCommitted();
    }
}
```

### Event Store — JDBC implementation
```java
@Repository
class JdbcEventStore implements EventStore {
    private final JdbcTemplate jdbc;
    private final ObjectMapper mapper;

    @Override
    @Transactional
    public void append(String aggregateId, long expectedVersion, List<DomainEvent> events) {
        // Optimistic locking — check current version
        Long currentVersion = jdbc.queryForObject(
            "SELECT MAX(version) FROM domain_events WHERE aggregate_id = ?",
            Long.class, aggregateId);

        if (currentVersion == null) currentVersion = -1L;
        if (!currentVersion.equals(expectedVersion)) {
            throw new OptimisticLockingException(
                "Expected version " + expectedVersion + " but got " + currentVersion);
        }

        long version = expectedVersion + 1;
        for (DomainEvent event : events) {
            jdbc.update(
                "INSERT INTO domain_events (aggregate_id, version, event_type, payload, occurred_at) VALUES (?,?,?,?::jsonb,?)",
                aggregateId, version++,
                event.getClass().getSimpleName(),
                serialize(event),
                event.occurredAt()
            );
        }
    }
}
```

### Snapshot Pattern (performance)

> 💡 **Giải thích dễ hiểu — snapshot là điểm lưu nhanh, event log vẫn là sự thật:**
> Thay vì phát lại 100.000 event từ đầu, aggregate bắt đầu từ ảnh chụp ở version 99.000 rồi replay phần còn lại. Snapshot có thể xóa và tạo lại vì source of truth vẫn là event log. Cần gắn version để không ghép snapshot với sai đoạn lịch sử.
```java
// Rebuild state từ 1000 events = slow → snapshot every N events
class SnapshotStore {
    void save(String aggregateId, long version, Object state);
    Optional<Snapshot> loadLatest(String aggregateId);
}

BankAccount load(String id) {
    Optional<Snapshot> snapshot = snapshotStore.loadLatest(id);
    if (snapshot.isPresent()) {
        BankAccount acc = deserialize(snapshot.get().state());
        List<DomainEvent> remaining = eventStore.loadFrom(id, snapshot.get().version() + 1);
        acc.replayEvents(remaining);
        return acc;
    }
    return BankAccount.reconstitute(eventStore.load(id));
}
```

---

## 5. Saga Pattern (Distributed Transactions)

### What
Quản lý distributed transactions qua chuỗi local transactions, mỗi step có compensating transaction khi fail.

> 💡 **Giải thích dễ hiểu — Saga là chuỗi hành động có cách bù, không phải rollback xuyên dịch vụ:**
> Sau khi Payment đã commit, database của Order không thể quay ngược transaction đó. Saga chạy một hành động nghiệp vụ khác như refund hoặc release stock để **bù** hậu quả. Compensation cũng có thể thất bại, đến muộn hoặc chạy lặp, nên từng step cần idempotency, retry, trạng thái bền vững và khả năng can thiệp thủ công.

```
┌──────────┐  ✅ Order    ┌──────────┐  ✅ Payment  ┌──────────┐  ✅ Stock    ┌──────────┐
│ Order    │──────────────▶│ Payment  │──────────────▶│ Inventory│──────────────▶│ Shipping │
│ Service  │              │ Service  │               │ Service  │               │ Service  │
└──────────┘              └──────────┘               └──────────┘               └──────────┘
                                                           ❌ FAIL
                                ◀──────────────────────────────────────────────────
                          Cancel Payment (compensating transaction)
◀──────────────────────────
Cancel Order (compensating transaction)
```

### Choreography Saga (event-driven, decentralized)
```java
// Order Service — step 1
@Service
class OrderService {
    @Transactional
    public void placeOrder(PlaceOrderCmd cmd) {
        Order order = Order.create(cmd);
        orderRepo.save(order);
        eventBus.publish(new OrderCreated(order.getId(), cmd.userId(), cmd.items(), order.totalAmount()));
    }

    // Compensating transaction
    @EventListener
    @Transactional
    public void on(PaymentFailed event) {
        Order order = orderRepo.findByPaymentId(event.paymentId()).orElseThrow();
        order.cancel("Payment failed: " + event.reason());
        orderRepo.save(order);
        log.info("Order {} cancelled due to payment failure", order.getId());
    }
}

// Payment Service — step 2, listens to OrderCreated
@Service
class PaymentService {
    @EventListener
    @Transactional
    public void on(OrderCreated event) {
        try {
            Payment payment = paymentGateway.charge(event.userId(), event.amount());
            eventBus.publish(new PaymentSucceeded(event.orderId(), payment.getId()));
        } catch (PaymentException e) {
            eventBus.publish(new PaymentFailed(event.orderId(), e.getMessage()));
        }
    }

    // Compensating transaction
    @EventListener
    @Transactional
    public void on(StockReservationFailed event) {
        paymentGateway.refund(event.paymentId());
        eventBus.publish(new PaymentRefunded(event.orderId()));
    }
}

// Inventory Service — step 3
@Service
class InventoryService {
    @EventListener
    @Transactional
    public void on(PaymentSucceeded event) {
        try {
            inventory.reserve(event.orderId(), event.items());
            eventBus.publish(new StockReserved(event.orderId(), event.paymentId()));
        } catch (InsufficientStockException e) {
            eventBus.publish(new StockReservationFailed(event.orderId(), event.paymentId(), e.getMessage()));
        }
    }
}
```

### Orchestration Saga (centralized coordinator)
```java
@Service
class OrderSagaOrchestrator {
    enum Step { ORDER_CREATED, PAYMENT_PROCESSED, STOCK_RESERVED, SHIPPING_ARRANGED, COMPLETED, FAILED }

    @Transactional
    public void execute(PlaceOrderCmd cmd) {
        SagaState saga = sagaRepo.create(cmd.orderId());

        try {
            // Step 1
            orderService.create(cmd);
            saga.advance(Step.ORDER_CREATED);

            // Step 2
            Payment payment = paymentService.charge(cmd.userId(), cmd.totalAmount());
            saga.advance(Step.PAYMENT_PROCESSED, payment.getId());

            // Step 3
            inventory.reserve(cmd.orderId(), cmd.items());
            saga.advance(Step.STOCK_RESERVED);

            // Step 4
            shipping.arrange(cmd.orderId(), cmd.address());
            saga.advance(Step.COMPLETED);

        } catch (PaymentException e) {
            compensate(saga, Step.PAYMENT_PROCESSED, cmd);
        } catch (InsufficientStockException e) {
            compensate(saga, Step.STOCK_RESERVED, cmd);
        }
    }

    private void compensate(SagaState saga, Step failedAt, PlaceOrderCmd cmd) {
        saga.markFailed(failedAt);
        // Run compensating transactions in reverse order
        switch (failedAt) {
            case STOCK_RESERVED   -> paymentService.refund(saga.getPaymentId());
            case PAYMENT_PROCESSED -> {}  // nothing to undo
            default -> log.error("Unexpected failure at {}", failedAt);
        }
        orderService.cancel(cmd.orderId(), "Saga failed at " + failedAt);
    }
}
```

---

## 6. Outbox Pattern (Reliable Event Publishing)

### Problem
```java
@Transactional
void placeOrder(PlaceOrderCmd cmd) {
    orderRepo.save(order);         // DB commit ✅
    eventBus.publish(orderPlaced); // Kafka publish ❌ (crash between these two!)
    // → Order saved but event NOT published → inconsistency
}
```

### Solution: Write event to DB in same transaction (Outbox table)

> 💡 **Giải thích dễ hiểu — ghi đơn hàng và “phiếu gửi thư” vào cùng két:**
> Transaction bảo đảm hoặc cả order lẫn outbox row cùng tồn tại, hoặc cả hai cùng rollback; crash không còn làm mất ý định phát event. Relay có thể publish thành công rồi crash trước `markPublished`, nên cùng event có thể được gửi lại. Outbox cung cấp **at-least-once**, không phải exactly-once end-to-end: event cần ID ổn định và consumer phải idempotent/deduplicate.
```java
@Transactional
void placeOrder(PlaceOrderCmd cmd) {
    Order order = Order.create(cmd);
    orderRepo.save(order);  // writes to orders table

    // Write event to outbox in SAME transaction
    OutboxEvent outboxEvent = OutboxEvent.of(
        "OrderPlaced",
        new OrderPlaced(order.getId(), cmd.userId()),
        "orders"
    );
    outboxRepo.save(outboxEvent);  // same DB transaction → atomic!
}

// Separate process: poll outbox and publish to Kafka
@Scheduled(fixedDelay = 1000)
@Transactional
void processOutbox() {
    List<OutboxEvent> pending = outboxRepo.findPending(100);
    for (OutboxEvent event : pending) {
        try {
            kafkaTemplate.send(event.topic(), event.payload()).get(5, SECONDS);
            outboxRepo.markPublished(event.id());
        } catch (Exception e) {
            outboxRepo.incrementRetryCount(event.id());
            log.error("Failed to publish event {}", event.id(), e);
        }
    }
}
```

### Outbox table schema
```sql
CREATE TABLE outbox_events (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type  VARCHAR(100) NOT NULL,
    topic       VARCHAR(100) NOT NULL,
    payload     JSONB NOT NULL,
    status      VARCHAR(20) DEFAULT 'PENDING',  -- PENDING, PUBLISHED, FAILED
    retry_count INT DEFAULT 0,
    created_at  TIMESTAMP DEFAULT NOW(),
    published_at TIMESTAMP
);
CREATE INDEX idx_outbox_pending ON outbox_events(status, created_at) WHERE status = 'PENDING';
```

### Debezium CDC (production alternative)
```
DB WAL (Write-Ahead Log) → Debezium Connector → Kafka → Consumers
```
Debezium reads DB transaction log → no polling needed, minimal latency.

---

## 7. Circuit Breaker Pattern

### What
Prevent cascading failures: nếu downstream service fail liên tục → stop calling it → fail fast → allow recovery.

> 💡 **Giải thích dễ hiểu — cầu dao ngắt thử tải để hệ thống có thời gian hồi phục:**
> CLOSED cho request đi qua và đo lỗi; OPEN từ chối nhanh để không dồn thêm tải; HALF_OPEN cho một số request thăm dò. Circuit breaker không thay timeout, retry hay bulkhead: retry sai cách còn có thể nhân tải. Implementation thủ công bên dưới chỉ minh họa state machine; production cần xử lý đồng thời, sliding window và metrics cẩn thận như thư viện Resilience4j.

```
CLOSED ──[failures > threshold]──▶ OPEN ──[timeout elapsed]──▶ HALF-OPEN
  ◀──[success]───────────────────────────────────────────────── (test calls)
                                   ◀──[still failing]────────── OPEN again
```

### Manual Implementation
```java
class CircuitBreaker {
    enum State { CLOSED, OPEN, HALF_OPEN }

    private volatile State state = State.CLOSED;
    private final AtomicInteger failureCount = new AtomicInteger(0);
    private volatile Instant openedAt;

    private final int failureThreshold;
    private final Duration resetTimeout;
    private final int successThreshold;
    private final AtomicInteger halfOpenSuccesses = new AtomicInteger(0);

    CircuitBreaker(int failureThreshold, Duration resetTimeout, int successThreshold) {
        this.failureThreshold = failureThreshold;
        this.resetTimeout = resetTimeout;
        this.successThreshold = successThreshold;
    }

    <T> T execute(Supplier<T> action) throws Exception {
        return switch (state) {
            case OPEN -> {
                if (Duration.between(openedAt, Instant.now()).compareTo(resetTimeout) > 0) {
                    state = State.HALF_OPEN;
                    halfOpenSuccesses.set(0);
                    yield execute(action);
                }
                throw new CircuitOpenException("Circuit breaker is OPEN");
            }
            case HALF_OPEN, CLOSED -> {
                try {
                    T result = action.get();
                    onSuccess();
                    yield result;
                } catch (Exception e) {
                    onFailure();
                    throw e;
                }
            }
        };
    }

    private synchronized void onSuccess() {
        if (state == State.HALF_OPEN) {
            if (halfOpenSuccesses.incrementAndGet() >= successThreshold) {
                state = State.CLOSED;
                failureCount.set(0);
                log.info("Circuit breaker CLOSED");
            }
        } else {
            failureCount.set(0);
        }
    }

    private synchronized void onFailure() {
        int failures = failureCount.incrementAndGet();
        if (state == State.HALF_OPEN || failures >= failureThreshold) {
            state = State.OPEN;
            openedAt = Instant.now();
            log.warn("Circuit breaker OPENED after {} failures", failures);
        }
    }
}

// Usage
CircuitBreaker cb = new CircuitBreaker(5, Duration.ofSeconds(30), 2);

try {
    User user = cb.execute(() -> externalUserService.getUser(id));
} catch (CircuitOpenException e) {
    // Fallback — cache, default, or error
    return userCache.get(id).orElse(User.anonymous());
}
```

### Resilience4j (production)
```java
@Bean
CircuitBreakerConfig circuitBreakerConfig() {
    return CircuitBreakerConfig.custom()
        .failureRateThreshold(50)                    // 50% fail → OPEN
        .slowCallRateThreshold(100)                  // 100% slow → OPEN
        .slowCallDurationThreshold(Duration.ofSeconds(2))
        .waitDurationInOpenState(Duration.ofSeconds(30))
        .permittedNumberOfCallsInHalfOpenState(3)
        .slidingWindowType(SlidingWindowType.COUNT_BASED)
        .slidingWindowSize(10)
        .build();
}

@Service
class PaymentService {
    private final CircuitBreaker cb;

    BigDecimal charge(String userId, BigDecimal amount) {
        return cb.executeSupplier(() -> externalGateway.charge(userId, amount));
    }
}
```

---

## 8. Bulkhead Pattern

### What
Isolate failures — như bulkhead trong tàu: một khoang bị nước không ảnh hưởng khoang khác.

> 💡 **Giải thích dễ hiểu — chia ngân sách tài nguyên theo khoang:**
> Nếu mọi downstream dùng chung một thread pool/connection pool, Payment treo có thể chiếm sạch tài nguyên khiến Inventory khỏe mạnh cũng đứng. Bulkhead cấp quota riêng bằng pool, semaphore hoặc giới hạn connection. Cách ly tăng khả năng sống sót nhưng quota quá nhỏ làm lãng phí, quá lớn lại mất tác dụng; cần đo saturation và rejection để chỉnh.

```java
// Separate thread pools per downstream service
ExecutorService paymentPool   = Executors.newFixedThreadPool(10);  // max 10 concurrent
ExecutorService inventoryPool = Executors.newFixedThreadPool(5);
ExecutorService emailPool     = Executors.newFixedThreadPool(3);

// Payment failure doesn't exhaust inventory threads
CompletableFuture<Payment> paymentFuture = CompletableFuture
    .supplyAsync(() -> paymentService.charge(amount), paymentPool)
    .orTimeout(5, SECONDS);

CompletableFuture<Void> inventoryFuture = CompletableFuture
    .runAsync(() -> inventory.reserve(items), inventoryPool)
    .orTimeout(3, SECONDS);

// Semaphore-based bulkhead
class SemaphoreBulkhead {
    private final Semaphore semaphore;
    SemaphoreBulkhead(int maxConcurrency) { this.semaphore = new Semaphore(maxConcurrency); }

    <T> T execute(Supplier<T> action) {
        if (!semaphore.tryAcquire()) throw new BulkheadFullException("Bulkhead full");
        try { return action.get(); }
        finally { semaphore.release(); }
    }
}
```

---

## So sánh Enterprise Patterns

| Pattern | Problem | Solution | Consistency |
|---------|---------|----------|-------------|
| Repository | Domain coupled to DB | Abstraction layer | N/A |
| Unit of Work | Multiple round trips | Batch commits | Local ACID |
| CQRS | Read/Write coupling | Separate models | Strong hoặc eventual, tùy cách đồng bộ read model |
| Event Sourcing | State mutation tracking | Event log | Strong (per aggregate) |
| Saga | Distributed transactions | Compensations | Eventual |
| Outbox | Dual write problem | Atomic outbox | At-least-once |
| Circuit Breaker | Cascading failures | Fail fast | N/A |
| Bulkhead | Resource starvation | Isolation pools | N/A |

---

## Ghi chú

**Khi chọn patterns:**
- **CRUD app**: Repository + Unit of Work (JPA) là đủ
- **Complex domain**: CQRS giúp tách read/write logic
- **Audit trail required**: Event Sourcing (nhưng phức tạp — chỉ dùng khi thực sự cần)
- **Microservices**: Saga + Outbox để handle distributed transactions
- **Third-party dependencies**: Circuit Breaker + Bulkhead

**Sai lầm phổ biến:**
- Dùng Event Sourcing cho mọi thứ → over-engineering
- Choreography Saga quá phức tạp → khó debug, dùng Orchestration khi team nhỏ
- Outbox không có idempotent consumer → duplicate events gây bugs

**Tiếp theo:** `patterns/antipatterns.md` — Anti-patterns phổ biến và cách refactor
