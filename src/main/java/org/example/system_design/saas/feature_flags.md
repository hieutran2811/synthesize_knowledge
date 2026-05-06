# Feature Flags – Quản lý tính năng trong SaaS

## What – Feature Flags là gì?

**Feature Flags** (Feature Toggles) là kỹ thuật cho phép **bật/tắt tính năng** mà không cần deploy code mới. Flag là điều kiện runtime kiểm soát code path.

```java
// Code vẫn tồn tại trong codebase, chỉ khác ở runtime
if (featureFlags.isEnabled("new-checkout-flow", tenantId)) {
    return newCheckoutService.process(order);
} else {
    return legacyCheckoutService.process(order);
}
```

---

## Tại sao cần Feature Flags trong SaaS?

| Vấn đề | Giải pháp với Feature Flag |
|--------|--------------------------|
| Deploy mới gây bug production | Kill switch: tắt ngay không cần rollback |
| Test feature trên production traffic | Canary release: bật cho 1% users |
| Khách hàng trả phí cao muốn feature mới | Tier-based rollout |
| A/B test giữa 2 implementation | Split traffic 50/50 |
| Feature chưa hoàn thiện | Commit to main, ẩn sau flag |

---

## Các loại Feature Flags

### 1. Release Toggles (Trunk-Based Development)
Feature đang develop, merge vào main nhưng ẩn sau flag.

```java
@GetMapping("/orders")
public List<Order> getOrders() {
    if (flags.isEnabled("enhanced-order-filtering")) {
        return orderService.getOrdersWithAdvancedFilter();  // New code
    }
    return orderService.getOrders();  // Stable code
}
```

**Lifecycle:** Ngắn (vài ngày → vài tuần). Xóa flag sau khi rollout hoàn tất.

### 2. Experiment Toggles (A/B Testing)
Chia users vào control vs experiment group.

```java
Variant variant = flags.getVariant("checkout-button-color", userId);
String buttonColor = switch (variant.getName()) {
    case "red"    -> "#FF0000";
    case "green"  -> "#00FF00";
    default       -> "#0000FF";  // control
};
```

Track conversion rates per variant → chọn winner → bật cho tất cả.

### 3. Ops Toggles (Kill Switches)
Emergency switch để tắt expensive/buggy features.

```java
public List<Recommendation> getRecommendations(String userId) {
    if (!flags.isEnabled("ml-recommendations")) {
        // Fallback to simple rule-based (lighter)
        return getTopProductsByCategory(userId);
    }
    return mlRecommendationService.get(userId);  // Expensive ML model
}
```

**Use case:** ML model quá tải → tắt ngay không cần deploy.

### 4. Permission Toggles (Tier-based Access)
Kiểm soát access theo plan/subscription.

```java
public void exportToCsv(ExportRequest request) {
    if (!flags.isEnabled("csv-export", tenantId)) {
        throw new FeatureNotAvailableException(
            "CSV Export is available on Pro and Enterprise plans. " +
            "Upgrade at example.com/pricing"
        );
    }
    // Process export
}
```

---

## Architecture của Feature Flag System

### Simple (Không nên dùng)
```java
// ❌ Hardcoded → deploy để thay đổi
private static final boolean NEW_FEATURE = true;
```

### Database-backed (Cơ bản)
```sql
CREATE TABLE feature_flags (
    id UUID PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    enabled BOOLEAN DEFAULT FALSE,
    rollout_percentage INT DEFAULT 0,
    tenant_ids TEXT[],  -- whitelist tenants
    metadata JSONB,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);
```

```java
@Service
public class DatabaseFeatureFlagService implements FeatureFlagService {
    
    @Cacheable(value = "feature-flags", key = "#name + ':' + #tenantId")
    public boolean isEnabled(String name, String tenantId) {
        FeatureFlag flag = flagRepo.findByName(name)
            .orElse(FeatureFlag.defaultOff());
        
        if (!flag.isEnabled()) return false;
        
        // Tenant whitelist check
        if (!flag.getTenantIds().isEmpty() && 
            !flag.getTenantIds().contains(tenantId)) {
            return false;
        }
        
        // Percentage rollout
        if (flag.getRolloutPercentage() < 100) {
            return hashToBucket(name + ":" + tenantId) < flag.getRolloutPercentage();
        }
        
        return true;
    }
    
    // Consistent hashing: same entity always gets same result
    private int hashToBucket(String key) {
        int hash = Math.abs(MurmurHash3.hash32(key.getBytes()));
        return hash % 100;  // 0-99 bucket
    }
}
```

### LaunchDarkly SDK (Production-grade)

```java
// Config
LDConfig config = new LDConfig.Builder()
    .events(Components.sendEvents().flushInterval(5, TimeUnit.SECONDS))
    .build();
LDClient ldClient = new LDClient("sdk-key", config);

// Evaluation with context
LDContext context = LDContext.builder(tenantId)
    .set("plan", "pro")
    .set("country", "US")
    .set("created_at", tenantCreatedAt)
    .build();

boolean isEnabled = ldClient.boolVariation("new-checkout", context, false);

// Multi-variate flag
String variant = ldClient.stringVariation("checkout-layout", context, "default");

// Track metrics for experiments
ldClient.track("purchase_completed", context, LDValue.of(orderAmount));
```

---

## Percentage Rollout (Canary Release)

**Rollout chiến lược:**
```
Day 1:  1%  → Internal users + beta testers → Monitor errors
Day 2:  5%  → Small cohort → Monitor performance
Day 3:  20% → Broader rollout → Monitor business metrics
Day 5:  50% → Half traffic → Confidence check
Day 7: 100% → Full rollout
```

**Consistent bucketing:**
```java
// Đảm bảo user X luôn vào cùng bucket
// 30% rollout: users với bucket 0-29 → enabled
// bucket = hash(featureName + userId) % 100

public boolean isUserInRollout(String feature, String userId, int rolloutPercent) {
    String key = feature + ":" + userId;
    byte[] hash = MessageDigest.getInstance("MD5").digest(key.getBytes());
    int bucket = Math.abs(ByteBuffer.wrap(hash).getInt()) % 100;
    return bucket < rolloutPercent;
}
```

---

## Feature Flags trong Multi-tenant SaaS

### Tier-based Feature Gates
```java
public enum PlanFeature {
    CSV_EXPORT(Set.of(Plan.PRO, Plan.ENTERPRISE)),
    API_ACCESS(Set.of(Plan.PRO, Plan.ENTERPRISE)),
    SSO_INTEGRATION(Set.of(Plan.ENTERPRISE)),
    AUDIT_LOGS(Set.of(Plan.ENTERPRISE)),
    CUSTOM_DOMAIN(Set.of(Plan.PRO, Plan.ENTERPRISE)),
    ADVANCED_ANALYTICS(Set.of(Plan.ENTERPRISE));
    
    private final Set<Plan> allowedPlans;
    
    public boolean isAllowedFor(Plan plan) {
        return allowedPlans.contains(plan);
    }
}

@Service
public class PlanFeatureGate {
    public void require(PlanFeature feature) {
        Tenant tenant = TenantContext.getTenant();
        if (!feature.isAllowedFor(tenant.getPlan())) {
            throw new FeatureGateException(
                feature.name(), tenant.getPlan(),
                "Upgrade to " + feature.getRequiredPlans() + " to access this feature"
            );
        }
    }
}

// Usage
@PostMapping("/export/csv")
public void exportCsv() {
    featureGate.require(PlanFeature.CSV_EXPORT);
    // ... export logic
}
```

### Beta Features cho Selected Tenants
```java
// Bật feature cho specific tenants (opt-in beta)
public boolean isBetaEnabled(String feature, String tenantId) {
    return betaRepo.isEnrolled(tenantId, feature)
        && flagService.isEnabled(feature);
}

// API cho tenants self-enroll vào beta
@PostMapping("/beta/enroll")
public void enrollBeta(@RequestBody BetaEnrollRequest req) {
    betaService.enroll(TenantContext.getTenantId(), req.getFeature());
}
```

---

## A/B Testing với Feature Flags

```java
@Service
public class ABTestService {
    
    public <T> T runExperiment(String experimentName, 
                               String userId,
                               Supplier<T> controlFn,
                               Supplier<T> treatmentFn) {
        Variant variant = flags.getVariant(experimentName, userId);
        
        long startTime = System.currentTimeMillis();
        T result;
        boolean isControl = "control".equals(variant.getName());
        
        try {
            result = isControl ? controlFn.get() : treatmentFn.get();
            
            // Track metrics
            analytics.track(ExperimentEvent.builder()
                .experiment(experimentName)
                .variant(variant.getName())
                .userId(userId)
                .durationMs(System.currentTimeMillis() - startTime)
                .success(true)
                .build());
                
        } catch (Exception e) {
            analytics.track(ExperimentEvent.error(experimentName, variant.getName()));
            throw e;
        }
        
        return result;
    }
}

// Usage
public Order processCheckout(Cart cart, String userId) {
    return abTestService.runExperiment(
        "one-click-checkout",
        userId,
        () -> legacyCheckout.process(cart),   // control
        () -> oneClickCheckout.process(cart)  // treatment
    );
}
```

---

## Technical Considerations

### Performance: Caching Flag Evaluations

```java
// Cache flag evaluations để không query DB mỗi request
@Cacheable(value = "flags", key = "#name + ':' + #tenantId", 
           unless = "#result == null")
@CacheEvict(value = "flags", key = "#name + ':' + #tenantId")

// Or: local in-process cache (sub-millisecond)
Cache<String, Boolean> localFlagCache = Caffeine.newBuilder()
    .maximumSize(10_000)
    .expireAfterWrite(30, SECONDS)  // Accept 30s staleness
    .build();

// LaunchDarkly SDK: built-in streaming (SSE) for instant flag updates
// No polling needed → instant propagation
```

### Flag Lifecycle Management

```
1. Create flag (disabled)
2. Enable for internal users
3. Rollout: 1% → 5% → 20% → 100%
4. Monitor: error rates, performance, business metrics
5. Full rollout → remove flag from code
6. Archive flag (keep for audit history)
```

**Technical debt:** Stale flags cần cleanup. "Flag debt" = khó maintain.

```java
// Annotate temporary flags với expiry date
@FeatureFlag(name = "new-checkout", 
             expiresAt = "2024-03-01",
             owner = "checkout-team")
public boolean isNewCheckoutEnabled(String tenantId) {
    return flagService.isEnabled("new-checkout", tenantId);
}

// CI check: fail build if flag past expiry date
```

---

## Trade-offs

| Approach | Pros | Cons |
|----------|------|------|
| Hardcoded constants | Simple | Requires deploy |
| DB-backed flags | Flexible, no external dep | DB latency, cache needed |
| LaunchDarkly/Unleash | Full-featured, SDK | Cost, external dependency |
| Config server (Consul) | No extra service | Less feature-rich |

| Flag Type | Lifetime | Who Controls |
|-----------|---------|-------------|
| Release toggle | Days-weeks | Engineering |
| Experiment toggle | Weeks-months | Product/Data |
| Ops toggle | Permanent | Ops/SRE |
| Permission toggle | Permanent | Product/Business |

---

## Real-world Production

### Facebook Gatekeeper
- Phát triển "Gatekeeper" nội bộ
- Rollout theo: user_id, location, device, age, …
- Hàng nghìn experiments chạy đồng thời

### Google (Feature Flags via Abacus/Plx)
- Mọi feature đều qua flag trước khi GA
- Statistical significance testing trước khi ship

### Netflix (Archaius)
- Dynamic configuration properties
- Real-time update không cần restart JVM

---

## Ghi chú

**Sub-topic tiếp theo:**
- `observability_saas.md` – Tracking experiment metrics, tenant-level monitoring
- **Keywords:** Feature toggle, Kill switch, Canary release, Blue-Green deployment, Dark launch (run new code but don't show to users), Shadow mode (run both, compare results), Trunk-Based Development (TBD), Continuous Delivery, Gradual rollout, Targeting rules, Segment-based rollout, LaunchDarkly, Unleash (open source), Flagsmith, Split.io, Statistical significance, p-value, Minimum Detectable Effect (MDE)
