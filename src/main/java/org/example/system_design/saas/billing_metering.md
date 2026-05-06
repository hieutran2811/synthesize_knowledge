# Billing & Metering – Hệ thống thanh toán SaaS

## What – Billing trong SaaS là gì?

**Billing & Metering** trong SaaS là hệ thống đo đếm việc sử dụng của tenant (metering) và tính phí dựa trên mức sử dụng đó (billing). Đây là core business logic của SaaS.

---

## Pricing Models

### 1. Flat Rate (Fixed Price)
Mỗi tier có giá cố định, không quan tâm dùng bao nhiêu.
```
Free: $0/month
Pro: $29/month
Business: $99/month
Enterprise: Custom
```

**Ưu:** Predictable revenue, simple billing logic
**Nhược:** Không phù hợp high-usage customers (either overpay or underpay)

### 2. Usage-Based (Pay-as-you-go)
Tính phí theo actual usage.
```
API calls: $0.0001 per call
Storage: $0.023 per GB
Bandwidth: $0.01 per GB
Compute: $0.004 per CPU-hour
```
**Ví dụ:** AWS, Twilio, Stripe (% per transaction), Datadog

### 3. Per-Seat (Per-User)
Tính phí theo số user.
```
$15/user/month
Team of 10 → $150/month
```
**Ví dụ:** Slack, GitHub, HubSpot

### 4. Tiered (Volume Discount)
Giá giảm khi dùng nhiều hơn.
```
0-1000 API calls: $0.0010 each
1001-10000:       $0.0008 each
10001-100000:     $0.0005 each
100001+:          $0.0002 each
```

### 5. Hybrid (Platform Fee + Usage)
```
Platform: $99/month base fee
+ $0.001 per API call above 100,000 included calls
```

---

## Metering Architecture

### High-Level Flow
```
User Action (API call, file upload, email sent)
     ↓
Instrumentation Layer (intercept + emit usage event)
     ↓
Kafka / Message Queue (buffer, reliable delivery)
     ↓
Metering Service (aggregate, store)
     ↓
Usage Store (Redis for real-time + DB for permanent)
     ↓
Billing Service (calculate charges at billing cycle)
     ↓
Payment Gateway (Stripe)
     ↓
Invoice + Notification
```

### Usage Event Schema
```json
{
  "eventId": "evt-uuid",
  "tenantId": "tenant-abc",
  "userId": "user-123",
  "feature": "api_call",
  "subFeature": "orders_create",
  "quantity": 1,
  "metadata": {
    "endpoint": "POST /api/orders",
    "responseStatus": 201,
    "processingTimeMs": 45
  },
  "timestamp": "2024-01-15T10:30:00Z",
  "idempotencyKey": "req-xyz-789"  // deduplicate
}
```

### Metering Service (Java)
```java
@Service
public class MeteringService {
    
    @Autowired
    private KafkaTemplate<String, UsageEvent> kafkaTemplate;
    
    @Autowired
    private RedisTemplate<String, Long> redis;
    
    // Emit event (fire-and-forget từ API servers)
    public void recordUsage(String tenantId, String feature, long quantity) {
        UsageEvent event = UsageEvent.builder()
            .eventId(UUID.randomUUID().toString())
            .tenantId(tenantId)
            .feature(feature)
            .quantity(quantity)
            .timestamp(Instant.now())
            .idempotencyKey(generateIdempotencyKey())
            .build();
        
        kafkaTemplate.send("usage-events", tenantId, event);
    }
    
    // Real-time counter (for rate limiting + current usage display)
    public void incrementRealTimeCounter(String tenantId, String feature) {
        String key = String.format("usage:%s:%s:%s", 
            tenantId, feature, YearMonth.now());
        redis.opsForValue().increment(key);
        redis.expire(key, 60, TimeUnit.DAYS);
    }
    
    public long getCurrentUsage(String tenantId, String feature) {
        String key = String.format("usage:%s:%s:%s", 
            tenantId, feature, YearMonth.now());
        Long usage = redis.opsForValue().get(key);
        return usage != null ? usage : 0L;
    }
}
```

### Kafka Consumer (Aggregation)
```java
@Component
public class UsageAggregator {
    
    @KafkaListener(topics = "usage-events", 
                   groupId = "metering-service",
                   containerFactory = "batchKafkaListenerContainerFactory")
    public void consumeBatch(List<ConsumerRecord<String, UsageEvent>> records) {
        // Group by tenant + feature + period (hourly buckets)
        Map<AggregationKey, Long> aggregated = records.stream()
            .collect(Collectors.groupingBy(
                r -> new AggregationKey(r.value().getTenantId(), 
                                        r.value().getFeature(),
                                        truncateToHour(r.value().getTimestamp())),
                Collectors.summingLong(r -> r.value().getQuantity())
            ));
        
        // Upsert aggregations to DB
        aggregated.forEach((key, total) -> 
            usageAggregationRepo.upsert(key, total)
        );
    }
}
```

---

## Billing Cycle & Invoice Generation

### Monthly Billing Flow
```
Day 1 of month:
1. Lock usage data for previous month
2. Calculate charges per tenant
3. Apply discounts, credits
4. Generate invoice
5. Charge payment method (Stripe)
6. Send invoice email
7. Handle failures (retry, dunning)
```

### Charge Calculation
```java
@Service
public class BillingCalculationService {
    
    public Invoice calculateInvoice(String tenantId, YearMonth billingPeriod) {
        TenantPlan plan = planService.getPlan(tenantId);
        UsageSummary usage = usageRepo.getSummary(tenantId, billingPeriod);
        
        List<LineItem> lineItems = new ArrayList<>();
        
        // Base platform fee
        lineItems.add(LineItem.of("Platform Fee", plan.getBaseFee()));
        
        // Usage-based charges
        for (Feature feature : plan.getMeteredFeatures()) {
            long usedQuantity = usage.getQuantity(feature.getName());
            long includedQuantity = feature.getIncludedQuantity();
            long billableQuantity = Math.max(0, usedQuantity - includedQuantity);
            
            if (billableQuantity > 0) {
                BigDecimal charge = feature.calculateTieredPrice(billableQuantity);
                lineItems.add(LineItem.of(
                    feature.getDisplayName() + " (" + billableQuantity + " units)",
                    charge
                ));
            }
        }
        
        // Apply credits
        BigDecimal credits = creditService.getAvailableCredits(tenantId);
        if (credits.compareTo(BigDecimal.ZERO) > 0) {
            lineItems.add(LineItem.credit("Credits Applied", credits.negate()));
        }
        
        BigDecimal subtotal = lineItems.stream()
            .map(LineItem::getAmount)
            .reduce(BigDecimal.ZERO, BigDecimal::add);
        
        BigDecimal tax = taxService.calculateTax(tenantId, subtotal);
        
        return Invoice.builder()
            .tenantId(tenantId)
            .period(billingPeriod)
            .lineItems(lineItems)
            .subtotal(subtotal)
            .tax(tax)
            .total(subtotal.add(tax))
            .build();
    }
}
```

---

## Stripe Integration

### Setup Subscription
```java
@Service
public class StripeService {
    
    public String createCustomer(Tenant tenant) {
        CustomerCreateParams params = CustomerCreateParams.builder()
            .setEmail(tenant.getBillingEmail())
            .setName(tenant.getOrganizationName())
            .putMetadata("tenantId", tenant.getId())
            .build();
        
        Customer customer = Customer.create(params);
        tenantRepo.updateStripeCustomerId(tenant.getId(), customer.getId());
        return customer.getId();
    }
    
    public Subscription createSubscription(String customerId, String priceId) {
        SubscriptionCreateParams params = SubscriptionCreateParams.builder()
            .setCustomer(customerId)
            .addItem(SubscriptionCreateParams.Item.builder()
                .setPrice(priceId)
                .build())
            .setPaymentBehavior(ALLOW_INCOMPLETE) // For 3D Secure
            .build();
        
        return Subscription.create(params);
    }
    
    // Usage-based: report metered usage to Stripe
    public void reportUsage(String subscriptionItemId, long quantity) {
        UsageRecordCreateParams params = UsageRecordCreateParams.builder()
            .setQuantity(quantity)
            .setTimestamp(Instant.now().getEpochSecond())
            .setAction(UsageRecordCreateParams.Action.INCREMENT)
            .build();
        
        SubscriptionItem item = SubscriptionItem.retrieve(subscriptionItemId);
        item.usageRecords().create(params);
    }
}
```

### Stripe Webhooks (Handle Billing Events)
```java
@RestController
@RequestMapping("/webhooks/stripe")
public class StripeWebhookController {
    
    @PostMapping
    public ResponseEntity<Void> handleWebhook(
            @RequestBody String payload,
            @RequestHeader("Stripe-Signature") String sigHeader) {
        
        // Verify webhook signature
        Event event = Webhook.constructEvent(payload, sigHeader, webhookSecret);
        
        switch (event.getType()) {
            case "invoice.payment_succeeded" -> {
                Invoice invoice = (Invoice) event.getDataObjectDeserializer().getObject().get();
                activateTenantSubscription(invoice.getCustomer());
            }
            case "invoice.payment_failed" -> {
                startDunningProcess(event);
            }
            case "customer.subscription.deleted" -> {
                deactivateTenant(event);
            }
        }
        
        return ResponseEntity.ok().build();
    }
}
```

---

## Dunning Management (Xử lý payment failure)

**Dunning** = quy trình retry thu phí khi payment fail.

```
Day 0:  Payment fails → Send email "Payment failed"
Day 3:  Retry charge → Fail → Send reminder
Day 7:  Retry charge → Fail → Send warning "Account at risk"
Day 14: Retry charge → Fail → Downgrade to Free tier
Day 30: Final notice → Account suspension → Data retention 30 days
```

```java
@Scheduled(cron = "0 9 * * * ?") // 9 AM every day
public void processDunning() {
    List<Tenant> failedPayments = tenantRepo.findWithFailedPayments();
    
    for (Tenant tenant : failedPayments) {
        int daysSinceFail = tenant.getDaysSincePaymentFailed();
        
        switch (daysSinceFail) {
            case 3, 7 -> retryAndNotify(tenant);
            case 14 -> downgradeToFree(tenant);
            case 30 -> suspendAccount(tenant);
        }
    }
}
```

---

## Usage Limits & Enforcement

### Soft Limits vs Hard Limits
```
Soft Limit: Warn at 80%, 100% usage → allow continue + upsell
Hard Limit: Block at 100% + clear error message

Rate Limit: Real-time enforcement (see rate_limiting.md)
Quota Limit: Monthly enforcement (storage, seats)
```

```java
@Aspect
@Component
public class UsageLimitAspect {
    
    @Around("@annotation(CheckUsageLimit)")
    public Object enforceLimit(ProceedingJoinPoint pjp, CheckUsageLimit limit) throws Throwable {
        String tenantId = TenantContext.getCurrentTenant();
        String feature = limit.feature();
        
        long currentUsage = meteringService.getCurrentUsage(tenantId, feature);
        long maxUsage = planService.getLimit(tenantId, feature);
        
        if (currentUsage >= maxUsage) {
            throw new UsageLimitExceededException(
                feature, currentUsage, maxUsage,
                "Upgrade your plan to continue using " + feature
            );
        }
        
        // Warning at 80%
        if (currentUsage >= maxUsage * 0.8) {
            notificationService.sendUsageWarning(tenantId, feature, currentUsage, maxUsage);
        }
        
        Object result = pjp.proceed();
        meteringService.recordUsage(tenantId, feature, 1);
        return result;
    }
}
```

---

## Revenue Analytics

```sql
-- Monthly Recurring Revenue (MRR)
SELECT 
    DATE_TRUNC('month', billing_date) as month,
    SUM(amount) as mrr,
    COUNT(DISTINCT tenant_id) as paying_customers
FROM invoices
WHERE status = 'PAID'
GROUP BY 1
ORDER BY 1;

-- Churn Rate
SELECT 
    month,
    churned_customers / total_customers * 100 as churn_rate
FROM (
    SELECT 
        DATE_TRUNC('month', cancelled_at) as month,
        COUNT(*) as churned_customers,
        (SELECT COUNT(*) FROM tenants WHERE created_at < month AND status = 'ACTIVE') as total_customers
    FROM tenants
    WHERE status = 'CANCELLED'
    GROUP BY 1
) monthly_churn;

-- Customer Lifetime Value (CLV)
SELECT 
    tenant_id,
    SUM(amount) as total_revenue,
    DATEDIFF('day', MIN(billing_date), COALESCE(MAX(cancelled_at), NOW())) as lifetime_days
FROM invoices
GROUP BY tenant_id;
```

---

## Trade-offs

| Billing Model | Revenue Predictability | Customer Satisfaction | Complexity |
|--------------|----------------------|---------------------|------------|
| Flat Rate | High | Medium (over/underpay) | Low |
| Usage-Based | Low | High (pay what you use) | High |
| Per-Seat | High | Medium | Low |
| Hybrid | Medium | High | Medium |

---

## Real-world Production

### Datadog (Usage-Based)
- Meter: hosts, containers, custom metrics, logs ingested
- Real-time usage dashboard per customer
- Anomaly detection to alert on unexpected usage spikes

### Stripe Atlas (Metered Billing)
- Stripe uses its own metered billing for API calls
- Usage records API → aggregate → invoice monthly

### Snowflake (Credits system)
- Compute measured in "credits" (abstract from infrastructure)
- Virtual warehouse sizes = different credit/hour rates
- Pre-purchase credits for discount (commit spend)

---

## Ghi chú

**Sub-topic tiếp theo:**
- `rate_limiting.md` – Real-time usage enforcement và rate limiting
- `feature_flags.md` – Feature gates per pricing tier
- **Keywords:** MRR (Monthly Recurring Revenue), ARR (Annual Recurring Revenue), Churn rate, LTV (Lifetime Value), CAC (Customer Acquisition Cost), Usage-based billing, Metered subscription, Stripe Billing, Dunning, Credit system, Revenue recognition (ASC 606), Proration, Upgrade/downgrade billing
