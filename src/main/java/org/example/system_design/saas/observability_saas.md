# SaaS Observability – Giám sát hệ thống SaaS đa thuê bao

## What – SaaS Observability là gì?

**SaaS Observability** là khả năng hiểu **trạng thái nội tại** của hệ thống từ các tín hiệu bên ngoài (metrics, logs, traces), với context đặc thù của SaaS: **per-tenant visibility, cost attribution, và business metrics**.

```
3 Pillars of Observability:
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   Metrics   │  │    Logs     │  │   Traces    │
│  (What's    │  │  (What      │  │  (Where     │
│ happening?) │  │ happened?)  │  │   is slow?) │
└─────────────┘  └─────────────┘  └─────────────┘
        │                │                │
        └────────────────┴────────────────┘
                         │
              SaaS Context: + Tenant ID
                           + Plan Tier
                           + Feature used
                           + Cost attribution
```

---

## Tenant-Aware Metrics

### Custom Metrics với Tenant Dimension

```java
@Component
public class TenantMetrics {
    
    private final MeterRegistry registry;
    
    // Counter: API calls per tenant per endpoint
    public void recordApiCall(String tenantId, String endpoint, 
                              int statusCode, long durationMs) {
        registry.counter("api.requests.total",
            "tenant_id", tenantId,
            "endpoint", endpoint,
            "status_code", String.valueOf(statusCode),
            "plan", planService.getPlan(tenantId).getTier().name()
        ).increment();
        
        registry.timer("api.request.duration",
            "tenant_id", tenantId,
            "endpoint", endpoint
        ).record(durationMs, TimeUnit.MILLISECONDS);
    }
    
    // Gauge: active tenants
    public void registerTenantGauge() {
        Gauge.builder("tenants.active", tenantService, 
                      ts -> ts.countActiveTenants())
            .register(registry);
    }
    
    // Business metric: orders per tenant
    public void recordOrderCreated(String tenantId, BigDecimal amount) {
        registry.counter("business.orders.total",
            "tenant_id", tenantId
        ).increment();
        
        registry.summary("business.order.amount",
            "tenant_id", tenantId
        ).record(amount.doubleValue());
    }
}
```

### Prometheus Queries cho SaaS

```promql
# Error rate per tenant (alert nếu > 1%)
sum(rate(api_requests_total{status_code=~"5.."}[5m])) by (tenant_id)
/ sum(rate(api_requests_total[5m])) by (tenant_id) > 0.01

# Top 10 tenants by request volume
topk(10, sum(rate(api_requests_total[1h])) by (tenant_id))

# P99 latency per tenant
histogram_quantile(0.99, 
  sum(rate(api_request_duration_seconds_bucket[5m])) by (le, tenant_id)
)

# Tenants approaching rate limit (> 80% of limit)
(rate_limit_current_count / rate_limit_max_count) > 0.8

# Active tenant count trend
count(count by (tenant_id)(api_requests_total{status_code="200"}))
```

---

## Tenant-Aware Logging

### Structured Logging với Tenant Context

```java
@Component
public class TenantAwareLoggingFilter extends OncePerRequestFilter {
    
    @Override
    protected void doFilterInternal(...) throws ... {
        String tenantId = TenantContext.getCurrentTenant();
        String traceId = MDC.get("traceId");
        
        // Enrich MDC with tenant context
        MDC.put("tenant_id", tenantId);
        MDC.put("tenant_plan", planService.getPlan(tenantId).getTier().name());
        
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove("tenant_id");
            MDC.remove("tenant_plan");
        }
    }
}

// All log statements auto-include tenant_id via MDC
log.info("Order created: orderId={}, amount={}", orderId, amount);
// Output (JSON):
// {"timestamp":"...","level":"INFO","message":"Order created: orderId=123, amount=59.99",
//  "tenant_id":"tenant-abc","tenant_plan":"PRO","trace_id":"abc123"}
```

### Logback JSON config
```xml
<encoder class="net.logstash.logback.encoder.LogstashEncoder">
    <includeMdcKeyName>tenant_id</includeMdcKeyName>
    <includeMdcKeyName>tenant_plan</includeMdcKeyName>
    <includeMdcKeyName>user_id</includeMdcKeyName>
    <includeMdcKeyName>trace_id</includeMdcKeyName>
    <includeMdcKeyName>request_id</includeMdcKeyName>
</encoder>
```

### Log Separation per Tenant (Compliance)
```
Tenant A logs → Elasticsearch index: logs-tenant-a-2024.01
Tenant B logs → Elasticsearch index: logs-tenant-b-2024.01

# Ensure no cross-tenant log access via RBAC
# GDPR: tenant can request their logs, we can delete just their index
```

---

## Distributed Tracing với Tenant Context

```java
@Configuration
public class TracingConfig {
    
    @Bean
    public Tracer tracer(OpenTelemetry openTelemetry) {
        return openTelemetry.getTracer("order-service");
    }
}

@Service
public class OrderService {
    
    @Autowired
    private Tracer tracer;
    
    public Order createOrder(CreateOrderRequest request) {
        Span span = tracer.spanBuilder("createOrder")
            .setAttribute("tenant.id", TenantContext.getCurrentTenant())
            .setAttribute("tenant.plan", getCurrentPlan())
            .setAttribute("order.items_count", request.getItems().size())
            .startSpan();
        
        try (Scope scope = span.makeCurrent()) {
            // Business logic
            Order order = orderRepo.save(new Order(request));
            
            span.setAttribute("order.id", order.getId());
            span.setAttribute("order.amount", order.getTotalAmount().doubleValue());
            
            return order;
        } catch (Exception e) {
            span.recordException(e);
            span.setStatus(StatusCode.ERROR, e.getMessage());
            throw e;
        } finally {
            span.end();
        }
    }
}
```

### Trace-based alerting
```
Alert: P99 latency > 2s for ANY tenant
→ Investigate trace: which service is slow?
→ Filter by tenant_id → identify hot tenant
→ Might be noisy neighbor or tenant-specific issue
```

---

## Cost Attribution per Tenant

### Infrastructure Cost Allocation

```java
@Scheduled(cron = "0 0 * * * ?") // Hourly
public void attributeCosts() {
    Instant hour = Instant.now().truncatedTo(ChronoUnit.HOURS);
    
    // Get CPU/memory usage per tenant pod
    Map<String, ResourceUsage> resourceByTenant = 
        kubernetesMetricsClient.getPodMetricsByTenant(hour);
    
    for (Map.Entry<String, ResourceUsage> entry : resourceByTenant.entrySet()) {
        String tenantId = entry.getKey();
        ResourceUsage usage = entry.getValue();
        
        // Calculate cost
        double computeCost = usage.getCpuCoreHours() * CPU_PRICE_PER_CORE_HOUR;
        double memoryCost = usage.getMemoryGBHours() * MEMORY_PRICE_PER_GB_HOUR;
        double storageCost = usage.getStorageGBHours() * STORAGE_PRICE_PER_GB_HOUR;
        
        TenantCost cost = TenantCost.builder()
            .tenantId(tenantId)
            .period(hour)
            .computeCost(computeCost)
            .memoryCost(memoryCost)
            .storageCost(storageCost)
            .totalCost(computeCost + memoryCost + storageCost)
            .build();
        
        costRepo.save(cost);
    }
}
```

### Cost Analysis Dashboard
```sql
-- Cost per tenant per month
SELECT 
    tenant_id,
    DATE_TRUNC('month', period) as month,
    SUM(compute_cost) as compute_cost,
    SUM(memory_cost) as memory_cost,
    SUM(storage_cost) as storage_cost,
    SUM(total_cost) as total_infra_cost
FROM tenant_costs
GROUP BY tenant_id, month
ORDER BY total_infra_cost DESC;

-- Gross margin per tenant
SELECT 
    t.id as tenant_id,
    t.plan as plan_tier,
    SUM(i.amount) as revenue,
    SUM(tc.total_cost) as infra_cost,
    (SUM(i.amount) - SUM(tc.total_cost)) / SUM(i.amount) * 100 as gross_margin_pct
FROM tenants t
JOIN invoices i ON t.id = i.tenant_id
JOIN tenant_costs tc ON t.id = tc.tenant_id 
    AND DATE_TRUNC('month', i.billing_date) = DATE_TRUNC('month', tc.period)
GROUP BY t.id, t.plan
HAVING gross_margin_pct < 30  -- Identify loss-making tenants
ORDER BY gross_margin_pct;
```

---

## SLO Monitoring per Tenant

### Tenant-specific SLOs
```java
@Component
public class TenantSLOMonitor {
    
    // Error budget tracking
    public ErrorBudget getErrorBudget(String tenantId, Duration period) {
        TenantSLO slo = sloRepo.findByTenantId(tenantId);
        double targetAvailability = slo.getAvailabilityTarget(); // e.g., 0.999 (99.9%)
        
        TimeRange range = TimeRange.ofDuration(period);
        long totalRequests = metricsRepo.getTotalRequests(tenantId, range);
        long successfulRequests = metricsRepo.getSuccessfulRequests(tenantId, range);
        
        double actualAvailability = (double) successfulRequests / totalRequests;
        double errorBudgetTotal = 1.0 - targetAvailability;
        double errorBudgetUsed = 1.0 - actualAvailability;
        double errorBudgetRemaining = errorBudgetTotal - errorBudgetUsed;
        
        return ErrorBudget.builder()
            .tenantId(tenantId)
            .targetAvailability(targetAvailability)
            .actualAvailability(actualAvailability)
            .errorBudgetTotal(errorBudgetTotal)
            .errorBudgetUsed(errorBudgetUsed)
            .errorBudgetRemainingPct(errorBudgetRemaining / errorBudgetTotal * 100)
            .build();
    }
}
```

### Alerting Rules (Prometheus Alertmanager)
```yaml
groups:
- name: saas-tenant-alerts
  rules:
  # Alert khi tenant error rate cao
  - alert: TenantHighErrorRate
    expr: |
      (sum(rate(api_requests_total{status_code=~"5.."}[5m])) by (tenant_id))
      / (sum(rate(api_requests_total[5m])) by (tenant_id))
      > 0.05
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "High error rate for tenant {{ $labels.tenant_id }}"
      description: "Error rate {{ $value | humanizePercentage }} for {{ $labels.tenant_id }}"
  
  # Alert khi enterprise tenant có vấn đề
  - alert: EnterpriseLatencyHigh
    expr: |
      histogram_quantile(0.99, 
        rate(api_request_duration_seconds_bucket{plan="ENTERPRISE"}[5m])
      ) > 2
    for: 5m
    labels:
      severity: critical
    annotations:
      summary: "Enterprise tenant P99 > 2s"
```

---

## Tenant Health Dashboard

### Grafana Dashboard Structure
```
SaaS Operations Dashboard
├── Overview Row
│   ├── Total Active Tenants
│   ├── Total Requests/s
│   ├── Overall Error Rate
│   └── P99 Latency
│
├── Per-Tenant Row (dropdown: select tenant)
│   ├── Request Rate (tenant)
│   ├── Error Rate (tenant)
│   ├── Latency P50/P95/P99 (tenant)
│   └── Feature Usage (tenant)
│
├── Noisy Neighbor Detection
│   ├── Top CPU consumers by tenant
│   ├── Top Memory consumers by tenant
│   └── Top DB connection users by tenant
│
└── Business Metrics Row
    ├── New Tenant Signups (24h)
    ├── Churned Tenants (30d)
    ├── Revenue by Plan Tier
    └── Gross Margin Trend
```

---

## Noisy Neighbor Detection & Mitigation

```java
@Component
@Scheduled(fixedRate = 60_000) // Every minute
public class NoisyNeighborDetector {
    
    public void detect() {
        List<TenantResourceUsage> usage = metricsCollector.getTopConsumers(10);
        
        for (TenantResourceUsage top : usage) {
            double normalUsage = metricsRepo.getAverageUsage(top.getTenantId(), 7, DAYS);
            
            if (top.getCurrentUsage() > normalUsage * 3) {
                log.warn("Noisy neighbor detected: tenant={}, usage={}x normal",
                    top.getTenantId(), top.getCurrentUsage() / normalUsage);
                
                // Automated mitigation
                if (top.getTenantId().isOnFreePlan()) {
                    // Throttle free tenant
                    rateLimiter.setDynamicLimit(top.getTenantId(), 
                        top.getTenantId().getPlanLimit() * 0.5);
                    notifyTenant(top.getTenantId(), "THROTTLED_DUE_TO_HIGH_USAGE");
                } else {
                    // Alert SRE team for paid tenants
                    alertService.page("SRE", "Noisy neighbor: " + top.getTenantId());
                }
            }
        }
    }
}
```

---

## Audit Trail (Compliance)

```java
@Aspect
@Component
public class AuditLogAspect {
    
    @AfterReturning(
        pointcut = "@annotation(AuditLog)",
        returning = "result"
    )
    public void logAudit(JoinPoint jp, Object result) {
        AuditLog annotation = getAnnotation(jp);
        
        AuditEntry entry = AuditEntry.builder()
            .tenantId(TenantContext.getCurrentTenant())
            .userId(SecurityContext.getCurrentUserId())
            .action(annotation.action())
            .resource(annotation.resource())
            .resourceId(extractResourceId(result))
            .ipAddress(RequestContext.getClientIP())
            .userAgent(RequestContext.getUserAgent())
            .timestamp(Instant.now())
            .requestId(MDC.get("request_id"))
            .traceId(MDC.get("trace_id"))
            .build();
        
        auditLogRepo.save(entry);
        
        // Also publish to audit stream (Kafka → long-term storage)
        kafkaTemplate.send("audit-logs", entry.getTenantId(), entry);
    }
}

// Usage
@AuditLog(action = "UPDATE", resource = "USER")
public User updateUser(String userId, UpdateUserRequest request) { ... }
```

---

## Trade-offs

| Approach | Benefit | Cost |
|----------|---------|------|
| Per-tenant metrics | Granular visibility | More Prometheus time series, memory |
| Centralized logs (all tenants) | Simple operations | GDPR, cross-tenant access risk |
| Separated log indices | GDPR compliant | Elasticsearch index overhead |
| Full distributed tracing | Complete visibility | ~5-10% overhead, storage |
| Cost attribution | Know unprofitable tenants | Complexity, tooling needed |

---

## Real-world Production

### Datadog (SaaS Observability Platform)
- Per-customer (tenant) metrics dashboards
- Multi-tenant by design: workspace isolation
- Alert on customer-specific anomalies

### Stripe (Observability)
- Merchant-level (tenant) error rate monitoring
- Automatic incident detection per merchant
- Internal dashboard: "Merchant Health Score"

### Snowflake
- Warehouse-level (tenant-like) metrics
- Credit usage real-time tracking
- Query performance per virtual warehouse

---

## Ghi chú

**Topic này hoàn thành toàn bộ System Design cho SaaS.**

**Tổng kết toàn bộ roadmap:**
- `fundamentals/scalability.md` ✅
- `fundamentals/availability_reliability.md` ✅
- `fundamentals/load_balancing.md` ✅
- `fundamentals/caching.md` ✅
- `fundamentals/databases_design.md` ✅
- `advanced/microservices.md` ✅
- `advanced/event_driven_architecture.md` ✅
- `advanced/distributed_transactions.md` ✅
- `advanced/api_design.md` ✅
- `saas/multi_tenancy.md` ✅
- `saas/billing_metering.md` ✅
- `saas/rate_limiting.md` ✅
- `saas/feature_flags.md` ✅
- `saas/observability_saas.md` ✅

**Keywords:**
Three pillars of observability (Metrics, Logs, Traces), OpenTelemetry (OTel), Prometheus + Grafana, ELK Stack, Jaeger/Zipkin, Error budget, SLO burn rate, MTTD (Mean Time to Detect), MTTR (Mean Time to Recover), Tenant health score, Gross margin per tenant, Unit economics, Noisy neighbor isolation, GDPR audit trail
