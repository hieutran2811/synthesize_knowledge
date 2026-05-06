# Distributed Transactions – Giao dịch phân tán

## What – Vấn đề của Distributed Transactions?

Trong microservices, một business operation span qua **nhiều services với nhiều databases**. Cần đảm bảo: **tất cả hoàn thành** hoặc **tất cả rollback**.

```
Ví dụ: Đặt hàng
1. Order Service: Tạo order → Orders DB
2. Inventory Service: Trừ tồn kho → Inventory DB
3. Payment Service: Charge thẻ → Payment DB
4. Notification Service: Gửi email

Nếu bước 3 fail sau khi bước 1+2 đã success?
→ Inconsistent state: có order, không có tiền, tồn kho bị trừ
```

---

## Two-Phase Commit (2PC)

### How
Giao thức cổ điển để đảm bảo distributed consistency.

**Phase 1: Prepare (Voting)**
```
Coordinator → "Prepare?"
                ↓
Service A: lock resources → "Ready" ✅
Service B: lock resources → "Ready" ✅
Service C: lock resources → "Ready" ✅
```

**Phase 2: Commit (hoặc Rollback)**
```
If all Ready:
Coordinator → "Commit!"
  Service A → Commit ✅
  Service B → Commit ✅
  Service C → Commit ✅

If any Abort:
Coordinator → "Rollback!"
  Service A → Rollback
  Service B → Rollback
  Service C → Rollback
```

### Vấn đề với 2PC
| Issue | Description |
|-------|-------------|
| **Blocking Protocol** | Resources bị lock trong cả 2 phases → latency tăng |
| **Coordinator SPOF** | Coordinator crash giữa phase 2 → participants bị block mãi |
| **Availability** | Nếu 1 participant down → toàn transaction fail |
| **Scale** | Không phù hợp microservices (cross-DB, cross-team) |

**2PC phù hợp khi:** Same database technology, single organization, không cần high availability (e.g., monolith với distributed DB).

---

## SAGA Pattern

**SAGA** chia transaction lớn thành nhiều **local transactions nhỏ**, mỗi local transaction publish event/message trigger next step. Nếu fail → chạy **compensating transactions** (rollback logic).

```
T1 (Order Service)    → [order.created]
T2 (Inventory Svc)   → [inventory.reserved]
T3 (Payment Svc)     → [payment.processed]
T4 (Notification Svc) → [email.sent]

Nếu T3 fail:
C3 (skip, payment not done)
C2 (Inventory Svc): release reservation
C1 (Order Service): cancel order
```

### SAGA Choreography (Event-based)

Mỗi service lắng nghe events, tự biết làm gì và publish event tiếp theo.

```
OrderSvc           InventorySvc       PaymentSvc          NotifSvc
    │                   │                  │                  │
    │ Create Order       │                  │                  │
    │─────────────────→[order.created]      │                  │
    │                   │                  │                  │
    │              Reserve Stock            │                  │
    │                   │──[inventory.reserved]────────────────→
    │                   │                  │                  │
    │                   │             Charge Card             │
    │                   │                  │──[payment.done]─→│
    │                   │                  │
    ←────────────[order.confirmed]──────────
```

**Compensation flow (if payment fails):**
```
PaymentSvc: charge fail → publish [payment.failed]
InventorySvc: on [payment.failed] → release reservation → publish [inventory.released]
OrderSvc: on [inventory.released] → cancel order
```

### SAGA Orchestration (Orchestrator-based)

```java
@Saga
public class OrderSaga {
    private String orderId;
    
    @StartSaga
    @SagaEventHandler(associationProperty = "orderId")
    public void on(OrderCreatedEvent event) {
        this.orderId = event.getOrderId();
        
        // Send command to Inventory
        commandGateway.send(new ReserveInventoryCommand(
            event.getOrderId(), event.getItems()
        ));
    }
    
    @SagaEventHandler(associationProperty = "orderId")
    public void on(InventoryReservedEvent event) {
        // Inventory OK → charge payment
        commandGateway.send(new ProcessPaymentCommand(
            event.getOrderId(), event.getAmount()
        ));
    }
    
    @SagaEventHandler(associationProperty = "orderId")
    public void on(PaymentProcessedEvent event) {
        // All done → confirm order
        commandGateway.send(new ConfirmOrderCommand(orderId));
        SagaLifecycle.end();
    }
    
    // Compensation
    @SagaEventHandler(associationProperty = "orderId")
    public void on(PaymentFailedEvent event) {
        // Rollback: release inventory
        commandGateway.send(new ReleaseInventoryCommand(orderId));
    }
    
    @SagaEventHandler(associationProperty = "orderId")
    public void on(InventoryReleasedEvent event) {
        // Rollback complete: cancel order
        commandGateway.send(new CancelOrderCommand(orderId));
        SagaLifecycle.end();
    }
}
```

---

## Idempotency – Xử lý duplicate messages

Trong distributed systems, messages có thể được delivered **nhiều lần** (at-least-once delivery). Consumer phải idempotent.

### Why duplicate messages xảy ra?
```
Producer → send msg → Kafka (stored)
           → crash trước khi nhận ack
Producer → retry → send msg again → Kafka (duplicate)
```

### Idempotency Key

```java
@Transactional
public void processPayment(PaymentCommand cmd) {
    String idempotencyKey = cmd.getIdempotencyKey(); // UUID từ producer
    
    // Check if already processed
    if (processedPaymentRepo.existsByKey(idempotencyKey)) {
        log.info("Payment {} already processed, skipping", idempotencyKey);
        return; // Idempotent: same result, no duplicate charge
    }
    
    // Process payment
    Payment payment = stripeService.charge(cmd.getAmount(), cmd.getCardToken());
    
    // Record as processed (same transaction)
    processedPaymentRepo.save(new ProcessedPayment(idempotencyKey, payment.getId()));
}
```

### Idempotency trong Kafka (Exactly-once)

```java
// Producer: enable idempotence
props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
props.put(ProducerConfig.ACKS_CONFIG, "all");

// Consumer: transactional processing
@KafkaListener(topics = "orders")
@Transactional("kafkaTransactionManager")
public void processOrder(OrderEvent event) {
    // DB update + Kafka ack trong cùng 1 transaction
    orderRepo.save(mapToOrder(event));
    // If this fails → Kafka offset NOT committed → retry
}
```

---

## Outbox Pattern (Anti-dual-write)

Đã mô tả trong `event_driven_architecture.md`. Tóm tắt:

```
@Transactional
public void createOrder(OrderRequest req) {
    Order order = orderRepo.save(new Order(req)); // DB write
    outboxRepo.save(new OutboxEvent("order.created", order)); // Same TX
}
// Outbox publisher (async): reads outbox → publishes to Kafka
```

---

## Try-Confirm/Cancel (TCC)

Variant của 2PC nhưng không blocking:

**Try phase:** Reserve resources (soft lock, không commit)
**Confirm phase:** Commit all reserved resources
**Cancel phase:** Release all reserved resources

```
Try:
  Order Service: create order (status=PENDING)
  Inventory: reserve stock (status=RESERVED)
  Payment: hold funds (status=HELD)

Confirm (if all Try succeeded):
  Order Service: confirm order (status=CONFIRMED)
  Inventory: deduct stock (status=DEDUCTED)
  Payment: capture charge (status=CAPTURED)

Cancel (if any Try failed):
  Order Service: cancel order
  Inventory: release reservation
  Payment: release hold
```

**Dùng khi:** Cần performance tốt hơn 2PC, nhưng cần eventually consistent (hotel booking, ticket reservation).

---

## Comparison

| | 2PC | SAGA | TCC |
|--|-----|------|-----|
| **Consistency** | Strong | Eventual | Eventual |
| **Availability** | Low | High | High |
| **Performance** | Slow | Fast | Medium |
| **Complexity** | Medium | High | High |
| **Lock duration** | Long | None (compensate) | Short (Try) |
| **Rollback** | Automatic | Manual (compensation) | Cancel phase |
| **Best for** | Same DB, monolith | Microservices | High-performance |

---

## Distributed Transaction Anti-patterns

### 1. Distributed Monolith
```
❌ Service A → BEGIN DISTRIBUTED TX
             → Call Service B (HTTP trong TX)
             → Call Service C (HTTP trong TX)
             → COMMIT
```
Tạo tight coupling, distributed locking nightmare.

### 2. Cross-service Queries trong Transaction
```
❌ OrderService.createOrder():
   inventoryService.checkStock(itemId); // HTTP call IN transaction
   paymentService.checkBalance(userId); // HTTP call IN transaction
   orderRepo.save(order);               // DB write
```

**Fix:** Validate trước transaction, hoặc dùng eventual consistency.

### 3. Long-running Transactions
Transaction giữ lock quá lâu → block khác → deadlock risk.

**Fix:** SAGA, break into small local transactions.

---

## Real-world Production

### Stripe (Payment Idempotency)
```
POST /v1/charges
Idempotency-Key: {client_generated_uuid}
→ Same key = same result (không charge 2 lần)
→ Stripe store results per idempotency key 24h
```

### Axon Framework (Java SAGA)
```java
@Saga
public class PaymentSaga {
    @Autowired
    private transient CommandGateway commandGateway;
    
    @StartSaga
    @SagaEventHandler(associationProperty = "paymentId")
    public void on(PaymentInitiatedEvent event) {
        commandGateway.send(new AuthorizeCardCommand(event.getCardToken()));
    }
}
```

### Uber (Cadence/Temporal Workflow)
- **Temporal:** Durable workflow engine cho distributed transactions
- Workflows persist state, auto-retry, handle failures
- Alternative to SAGA manual implementation

```java
// Temporal Workflow
@WorkflowInterface
public interface OrderWorkflow {
    @WorkflowMethod
    void processOrder(OrderRequest request);
}

public class OrderWorkflowImpl implements OrderWorkflow {
    private final InventoryActivity inventory = newActivityStub(InventoryActivity.class);
    private final PaymentActivity payment = newActivityStub(PaymentActivity.class);
    
    @Override
    public void processOrder(OrderRequest request) {
        inventory.reserve(request.getItems());  // auto-retry on failure
        try {
            payment.charge(request.getAmount());
        } catch (Exception e) {
            inventory.release(request.getItems()); // compensation
            throw e;
        }
    }
}
```

---

## Ghi chú

**Sub-topic tiếp theo:**
- `api_design.md` – REST, gRPC, API versioning strategies
- `saas/multi_tenancy.md` – Multi-tenant transactions và isolation
- **Keywords:** Compensating transaction, Pivot transaction, Semantic lock, Countermeasures (SAGA), Business transaction, Long-running process (LRP), Temporal (Cadence), Exactly-once semantics, Optimistic locking, Pessimistic locking, Distributed lock (Redis Redlock)
