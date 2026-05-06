# Event-Driven Architecture – Kiến trúc Hướng sự kiện

## What – Event-Driven Architecture là gì?

**Event-Driven Architecture (EDA)** là kiểu kiến trúc mà các component giao tiếp bằng cách **publish và consume events** thay vì gọi trực tiếp nhau. Event là thông điệp mô tả **điều đã xảy ra** trong hệ thống.

```
Traditional (Request-Response):
Order Service ──── HTTP POST ────→ Inventory Service
              ←─── Response ───── (tight coupling)

Event-Driven:
Order Service → [order.created event] → Kafka
                                       ↓
                                 Inventory Service (consumes)
                                 Notification Service (consumes)
                                 Analytics Service (consumes)
                                 (loose coupling)
```

---

## Tại sao cần EDA?

| Problem (Request-Response) | Solution (EDA) |
|---------------------------|----------------|
| Tight coupling | Producer/consumer độc lập |
| Cascade failures | Consumer lỗi không ảnh hưởng producer |
| Hard to scale independently | Scale consumer riêng |
| Synchronous blocking | Async, non-blocking |
| Hard to add new subscribers | Just add new consumer |

---

## Core Concepts

### Event
```json
{
  "eventId": "evt-550e8400-e29b",
  "eventType": "order.created",
  "aggregateId": "order-123",
  "aggregateType": "Order",
  "occurredAt": "2024-01-15T10:30:00Z",
  "version": 1,
  "payload": {
    "orderId": "order-123",
    "userId": "user-456",
    "items": [{"productId": "prod-1", "quantity": 2}],
    "totalAmount": 59.99
  },
  "metadata": {
    "correlationId": "req-abc",
    "causationId": "cmd-xyz",
    "traceId": "trace-123"
  }
}
```

**Event Types:**
- **Domain Event:** Điều gì đó xảy ra trong domain business (`OrderPlaced`, `PaymentFailed`)
- **Integration Event:** Communicate qua service boundaries
- **System Event:** Infrastructure events (`SystemStarted`, `HealthCheckFailed`)

### Event Broker (Message Broker)
Trung gian lưu trữ và forward events:

| Broker | Throughput | Retention | Ordering | Replay |
|--------|-----------|-----------|---------|--------|
| Kafka | 1M+ msg/s | Days-forever | Per partition | Yes ✅ |
| RabbitMQ | ~50K msg/s | Until consumed | Queue order | No |
| AWS SQS | High | Up to 14 days | Best-effort | Limited |
| AWS SNS | Very high | No storage | No | No |
| Pulsar | 1M+ msg/s | Tiered | Per partition | Yes ✅ |

---

## Choreography vs Orchestration

### Choreography (Distributed Decision)
Mỗi service lắng nghe events và tự quyết định làm gì.

```
Order Service → [order.created]
                      ↓
              ┌───────┴────────┐
              ↓                ↓
     Inventory Service    Payment Service
   [inventory.reserved]  [payment.processed]
              ↓                ↓
      Notification Svc   Order Service
    [email.send]          update status
```

**Ưu:**
- Không có central controller → không SPOF
- Services hoàn toàn độc lập
- Dễ thêm service mới (just subscribe to event)

**Nhược:**
- Khó track toàn bộ flow (distributed logic)
- Debugging phức tạp
- Event storms (events trigger events trigger events)

### Orchestration (Central Coordinator)
Một Orchestrator điều phối toàn bộ flow.

```
                ┌─────────────────┐
                │    Saga           │
                │   Orchestrator   │
                └────────┬─────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
   Inventory Svc   Payment Svc    Notif Svc
   reserve()       charge()       sendEmail()
```

**Ưu:**
- Flow rõ ràng, dễ debug
- Dễ implement compensation (rollback)
- Central visibility

**Nhược:**
- Orchestrator là central component (risk SPOF)
- Coupling qua Orchestrator

**Khi nào dùng gì:**
- Choreography: Ít steps, simple flow, independent services
- Orchestration: Complex flow, nhiều compensation logic, cần audit trail

---

## Event Sourcing

### What
Thay vì lưu **current state**, lưu **lịch sử tất cả events** đã xảy ra. Current state = replay all events.

```
Traditional (State-based):
Table: orders
| id  | status  | total |
| 123 | SHIPPED | 59.99 | ← chỉ thấy state cuối

Event Sourcing:
Event Store:
| seq | orderId | eventType         | data                    |
|  1  | 123     | OrderCreated      | {items: [...], amt: 59} |
|  2  | 123     | PaymentProcessed  | {txId: "tx-456"}        |
|  3  | 123     | OrderShipped      | {trackingNo: "TN123"}   |

Current state = replay events 1+2+3
```

### Aggregate Reconstruction
```java
public class Order {
    private String id;
    private OrderStatus status;
    private List<OrderItem> items;
    
    // Apply events to rebuild state
    public static Order reconstruct(List<DomainEvent> events) {
        Order order = new Order();
        events.forEach(order::apply);
        return order;
    }
    
    private void apply(DomainEvent event) {
        switch (event) {
            case OrderCreated e -> {
                this.id = e.getOrderId();
                this.items = e.getItems();
                this.status = CREATED;
            }
            case PaymentProcessed e -> this.status = PAID;
            case OrderShipped e -> this.status = SHIPPED;
        }
    }
}
```

### Snapshot Pattern
Sau N events, lưu snapshot để không replay từ đầu:

```
Events: 1..100 → Snapshot (state tại event 100)
New events: 101, 102, 103
Reconstruct: Load snapshot + apply events 101-103
```

### Pros & Cons Event Sourcing

**Pros:**
- Audit log đầy đủ (compliance, debugging)
- Temporal queries: "What was state at 2 weeks ago?"
- Replay events để rebuild state, fix bugs
- Decoupled read/write models

**Cons:**
- Querying current state phức tạp (cần CQRS)
- Event schema migration khó
- Storage tăng theo thời gian
- Eventual consistency
- Learning curve cao

---

## CQRS (Command Query Responsibility Segregation)

### What
Tách **Command (write)** và **Query (read)** thành hai model riêng biệt.

```
┌──────────────────────────────────────────────────────┐
│                    Application                        │
│                                                      │
│  Commands            Write Model          Read Model │
│  ─────────          ─────────────        ─────────── │
│  CreateOrder →       Event Store    →    Read DB     │
│  CancelOrder →       (source of         (projections)│
│  UpdateUser →         truth)            ─────────── │
│                                          Queries     │
│                                         ──────────   │
│                                          GetOrders → │
│                                          GetUser  → │
└──────────────────────────────────────────────────────┘
```

### Why CQRS?

1. **Scale independently:** Read replicas cho query side, scale write separately
2. **Optimized schemas:** Write model = normalized; Read model = denormalized/optimized
3. **Different databases:** Write to PostgreSQL, Read from Elasticsearch
4. **Security:** Separate read/write permissions clearly

### Implementation

```java
// Command Side
public class CreateOrderCommand {
    private String userId;
    private List<OrderItem> items;
}

@CommandHandler
public class OrderCommandHandler {
    public OrderId handle(CreateOrderCommand cmd) {
        Order order = Order.create(cmd.getUserId(), cmd.getItems());
        eventStore.save(order.getUncommittedEvents());
        return order.getId();
    }
}

// Query Side (separate model)
@QueryHandler
public class OrderQueryHandler {
    private final OrderReadRepository readRepo; // Optimized read DB
    
    public OrderSummaryDTO handle(GetOrderQuery query) {
        return readRepo.findSummaryById(query.getOrderId());
    }
}

// Projection (sync Read DB from events)
@EventHandler
public class OrderProjection {
    @Subscribe
    public void on(OrderCreatedEvent event) {
        OrderView view = new OrderView(event.getOrderId(), "CREATED", ...);
        readRepo.save(view);  // Update read model
    }
    
    @Subscribe
    public void on(OrderShippedEvent event) {
        readRepo.updateStatus(event.getOrderId(), "SHIPPED");
    }
}
```

### CQRS + Event Sourcing (Full Stack)

```
Command → Aggregate → Events (stored in Event Store)
                   → Projections → Read Models (multiple)
                                   - SQL (CRUD queries)
                                   - Elasticsearch (search)
                                   - Cache (hot data)
```

---

## Outbox Pattern (Transactional Outbox)

**Problem:** Làm thế nào đảm bảo cả DB write và event publish đều thành công (hoặc cả hai fail)?

```
❌ Without Outbox:
BEGIN TRANSACTION
  INSERT order → DB ✅
COMMIT
publish order.created → Kafka ❌ (network fail)
→ DB có order, Kafka không có event → inconsistency
```

**Solution: Outbox Table**

```
✅ With Outbox:
BEGIN TRANSACTION
  INSERT order → orders table
  INSERT event → outbox table (same transaction)
COMMIT
                    ↓
          Outbox Processor (polling / CDC)
                    ↓
             Publish to Kafka
                    ↓
          Mark as published in outbox
```

```java
// In OrderService
@Transactional
public Order createOrder(CreateOrderRequest request) {
    Order order = orderRepo.save(new Order(request));
    
    // Same transaction → atomic
    OutboxEvent outboxEvent = new OutboxEvent(
        "order.created",
        objectMapper.writeValueAsString(new OrderCreatedEvent(order))
    );
    outboxRepo.save(outboxEvent);
    
    return order;
}

// Outbox Processor (scheduled or CDC-based)
@Scheduled(fixedDelay = 100)
public void processOutbox() {
    List<OutboxEvent> events = outboxRepo.findUnpublished();
    for (OutboxEvent event : events) {
        kafkaTemplate.send(event.getTopic(), event.getPayload());
        event.markPublished();
        outboxRepo.save(event);
    }
}
```

**CDC-based Outbox (Debezium):** Debezium read PostgreSQL WAL → detect outbox table inserts → publish to Kafka. Không cần polling, near real-time.

---

## Event Versioning & Schema Evolution

Events không thể thay đổi (immutable), nhưng schema cần evolve:

### Strategy 1: Weak Schema (JSON với thêm fields)
```json
// v1
{"orderId": "123", "amount": 50}

// v2 (thêm field, backward compatible)
{"orderId": "123", "amount": 50, "currency": "USD"}
```
Consumer cũ ignore field mới → safe.

### Strategy 2: Versioned Event Types
```
order.created.v1 → Consumer v1
order.created.v2 → Consumer v2 (new fields)
```

### Strategy 3: Upcasting
```java
// Transformer: convert old event to new format on read
public OrderCreatedEventV2 upcast(OrderCreatedEventV1 v1) {
    return new OrderCreatedEventV2(
        v1.getOrderId(), 
        v1.getAmount(),
        "USD"  // default currency for old events
    );
}
```

---

## Trade-offs

| EDA | Trade-off |
|-----|-----------|
| Loose coupling | Eventual consistency |
| High throughput | Debugging complexity |
| Easy fan-out | Message ordering challenges |
| Resilience | Infrastructure overhead (broker) |
| Event Sourcing | Complex read queries (need CQRS) |
| CQRS | Two models to maintain |

---

## Real-world Production

### Uber Eats (Choreography)
- Order placed → events trigger Kitchen prep, Driver matching, Tracking
- Kafka với 1000+ topics

### Axon Framework (Java)
- Framework cho CQRS + Event Sourcing
- Axon Server làm event store + event routing

### LinkedIn (Kafka + CQRS)
- User activity → Kafka → Multiple read models
- Profile views, connection graph, analytics

---

## Ghi chú

**Sub-topic tiếp theo:**
- `distributed_transactions.md` – SAGA pattern chi tiết, 2PC, compensation
- `api_design.md` – Event-driven APIs, async API patterns
- **Keywords:** Domain Event, Integration Event, Event Schema Registry, Avro/Protobuf schema, Dead Letter Queue (DLQ), Event sourcing aggregate, Projection rebuilding, Eventual consistency, Idempotent consumer, At-least-once vs exactly-once delivery, Kafka Streams, Axon Framework
