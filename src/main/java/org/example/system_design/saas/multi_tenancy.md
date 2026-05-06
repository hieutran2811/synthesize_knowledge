# Multi-tenancy – Đa thuê bao trong SaaS

## What – Multi-tenancy là gì?

**Multi-tenancy** là kiến trúc trong đó một phần mềm (SaaS) phục vụ **nhiều tenant (khách hàng)** từ cùng một infrastructure, trong khi **dữ liệu của từng tenant hoàn toàn cô lập** với tenant khác.

```
Single-tenant:          Multi-tenant:
Tenant A → App A         Tenant A ─┐
Tenant B → App B         Tenant B ─┤→ Shared App → Isolated Data
Tenant C → App C         Tenant C ─┘
(expensive, no sharing)  (cost-efficient, isolation required)
```

---

## Các mô hình Multi-tenancy

### 1. Silo Model (Fully Isolated)
Mỗi tenant có **dedicated everything**: app, database, infrastructure.

```
Tenant A: App-A + DB-A (PostgreSQL instance A)
Tenant B: App-B + DB-B (PostgreSQL instance B)
Tenant C: App-C + DB-C (PostgreSQL instance C)
```

**Ưu:**
- Hoàn toàn isolate (data, performance, security)
- Compliance dễ dàng (GDPR: data residency)
- Outage của 1 tenant không ảnh hưởng tenant khác
- Dễ customize per tenant

**Nhược:**
- Chi phí cao (nhiều infra)
- Overhead operations (update N databases)
- Không tận dụng shared resources

**Khi nào:** Enterprise customers, healthcare/finance (strict compliance), custom SLA tiers, single-tenant by contract.

### 2. Pool Model (Fully Shared)
Tất cả tenant dùng chung **database, table**. Dùng `tenant_id` column để phân biệt.

```sql
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL,  -- ← phân biệt tenant
    user_id UUID NOT NULL,
    total_amount DECIMAL(10,2),
    created_at TIMESTAMP
);

CREATE INDEX idx_orders_tenant ON orders(tenant_id, created_at);
```

**Ưu:**
- Chi phí thấp nhất (shared resources)
- Dễ deploy updates (update once for all)
- Hiệu quả resource utilization

**Nhược:**
- **Noisy neighbor problem**: tenant lớn ảnh hưởng tenant khác
- **Data leakage risk**: bug có thể expose data cross-tenant
- **Compliance khó**: data ở cùng table → hard to prove isolation
- **Schema changes**: phải migrate all tenants cùng lúc

**Khi nào:** SMB customers, low-compliance requirements, cost-sensitive.

### 3. Bridge Model (Mixed)
Kết hợp: shared compute nhưng isolated databases.

```
App (shared) ──→ DB-Tenant-A (dedicated)
               ──→ DB-Tenant-B (dedicated)
               ──→ DB-Shared (Pool for small tenants)
```

**Ưu:** Balance giữa cost và isolation.
**Nhược:** Complexity cao (manage nhiều DB).

**Phổ biến nhất trong production SaaS.**

---

## Tenant Isolation Strategies

### Row-Level Security (PostgreSQL)

```sql
-- Enable RLS
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Policy: user chỉ thấy data của tenant mình
CREATE POLICY tenant_isolation ON orders
    USING (tenant_id = current_setting('app.current_tenant')::UUID);

-- Application set context trước query
SET app.current_tenant = '550e8400-e29b-41d4-a716-446655440000';
SELECT * FROM orders;  -- tự động filter theo RLS policy
```

**Áp dụng với Spring Boot:**
```java
@Component
public class TenantAwareDataSource {
    
    @Bean
    public DataSource dataSource() {
        return new TenantRoutingDataSource(); // custom routing
    }
}

// Hibernate filter
@FilterDef(name = "tenantFilter", 
    parameters = @ParamDef(name = "tenantId", type = String.class))
@Filter(name = "tenantFilter", condition = "tenant_id = :tenantId")
@Entity
public class Order {
    @Column(name = "tenant_id")
    private UUID tenantId;
    // ...
}

// In service layer
entityManager.unwrap(Session.class)
    .enableFilter("tenantFilter")
    .setParameter("tenantId", TenantContext.getCurrentTenant());
```

### Schema-per-Tenant (PostgreSQL)

```sql
-- Mỗi tenant có schema riêng
CREATE SCHEMA tenant_abc123;
CREATE TABLE tenant_abc123.orders (...);

-- Dynamic search_path
SET search_path = tenant_abc123;
SELECT * FROM orders; -- → tenant_abc123.orders
```

**Dùng Flyway multi-tenant migration:**
```java
@Component
public class TenantMigrationService {
    public void migrateNewTenant(String tenantId) {
        DataSource ds = createTenantDataSource(tenantId);
        Flyway flyway = Flyway.configure()
            .dataSource(ds)
            .schemas("tenant_" + tenantId)
            .locations("classpath:db/tenant-migrations")
            .load();
        flyway.migrate();
    }
}
```

---

## Tenant Routing

### Request Context Propagation

**Subdomain-based (phổ biến):**
```
tenant-a.app.com → extract "tenant-a" → TenantContext
tenant-b.app.com → extract "tenant-b" → TenantContext
```

**Path-based:**
```
app.com/tenant-a/api/orders → extract from path
```

**Header-based (B2B):**
```
X-Tenant-ID: tenant-abc123
```

**Spring Boot Tenant Filter:**
```java
@Component
@Order(1)
public class TenantFilter extends OncePerRequestFilter {
    
    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws IOException, ServletException {
        try {
            String tenantId = extractTenantId(request);
            validateTenant(tenantId); // Check tenant exists and is active
            TenantContext.setCurrentTenant(tenantId);
            chain.doFilter(request, response);
        } finally {
            TenantContext.clear(); // IMPORTANT: clear thread local
        }
    }
    
    private String extractTenantId(HttpServletRequest request) {
        // From subdomain
        String host = request.getServerName(); // tenant-a.app.com
        return host.split("\\.")[0];
        
        // Or from JWT claim
        // return jwtDecoder.decode(token).getClaim("tenant_id");
    }
}

// Thread-local context
public class TenantContext {
    private static final ThreadLocal<String> CURRENT_TENANT = new ThreadLocal<>();
    
    public static void setCurrentTenant(String tenantId) {
        CURRENT_TENANT.set(tenantId);
    }
    
    public static String getCurrentTenant() {
        return CURRENT_TENANT.get();
    }
    
    public static void clear() {
        CURRENT_TENANT.remove();
    }
}
```

---

## Tenant-Aware Caching

**Vấn đề:** Cache key phải include tenant_id để tránh cross-tenant data.

```java
// ❌ Sai: cache key không có tenant
@Cacheable("products")
public List<Product> getProducts(ProductFilter filter) { ... }

// ✅ Đúng: tenant-scoped cache keys
@Cacheable(value = "products", key = "#root.method.name + ':' + T(com.example.TenantContext).getCurrentTenant() + ':' + #filter.hashCode()")
public List<Product> getProducts(ProductFilter filter) { ... }

// Hoặc custom KeyGenerator
@Bean
public KeyGenerator tenantKeyGenerator() {
    return (target, method, params) -> {
        String tenantId = TenantContext.getCurrentTenant();
        return tenantId + ":" + method.getName() + ":" + Arrays.hashCode(params);
    };
}
```

**Cache isolation với namespace:**
```java
// Redis key pattern: {tenantId}:products:{filterId}
// tenant-a:products:active
// tenant-b:products:active
// → cô lập hoàn toàn
```

---

## Tenant Tiers (Pricing Tiers)

```
Free Tier:
  - Shared resources (Pool model)
  - Rate limit: 100 req/min
  - Storage: 1GB
  - No SLA guarantee

Pro Tier:
  - Shared DB, dedicated schema
  - Rate limit: 1000 req/min
  - Storage: 100GB
  - 99.9% SLA

Enterprise Tier:
  - Dedicated DB instance (Silo model)
  - Unlimited rate (or custom)
  - Custom storage
  - 99.99% SLA, dedicated support
```

**Implementation:**
```java
public class TenantPlanEnforcer {
    public void checkRateLimit(String tenantId) {
        TenantPlan plan = tenantService.getPlan(tenantId);
        int limit = switch (plan.getTier()) {
            case FREE -> 100;
            case PRO -> 1000;
            case ENTERPRISE -> Integer.MAX_VALUE;
        };
        rateLimiter.check(tenantId, limit);
    }
}
```

---

## Tenant Onboarding & Offboarding

### Onboarding Flow
```
1. Signup → create Tenant record
2. Provision resources:
   - Create schema (if schema-per-tenant)
   - Run DB migrations
   - Setup Kafka topics for tenant
   - Configure tenant-specific settings
3. Create initial admin user
4. Send welcome email
5. Mark tenant as ACTIVE
```

```java
@Transactional
public Tenant onboardTenant(OnboardingRequest request) {
    Tenant tenant = tenantRepo.save(Tenant.create(request));
    
    // Provision in background
    tenantProvisioningService.provision(tenant.getId());
    
    // Send onboarding email (async)
    eventPublisher.publish(new TenantCreatedEvent(tenant.getId()));
    
    return tenant;
}
```

### Offboarding / Data Deletion (GDPR)
```java
public void deleteTenantData(String tenantId) {
    // 1. Soft delete (mark as DELETED)
    tenantRepo.markDeleted(tenantId);
    
    // 2. Stop accepting requests
    // (TenantFilter now returns 403 for this tenant)
    
    // 3. Schedule hard delete after cooling period (30 days)
    scheduler.schedule(() -> hardDeleteTenant(tenantId), 30, DAYS);
}

public void hardDeleteTenant(String tenantId) {
    // Delete DB schema or truncate tables
    // Delete files in S3
    // Remove from search indexes
    // Anonymize audit logs
    // Archive billing records (legal requirement)
}
```

---

## Trade-offs

| Model | Isolation | Cost | Complexity | Scale |
|-------|-----------|------|------------|-------|
| Silo | Maximum | High | Low per tenant | Limited |
| Pool | Minimum | Low | Medium (RLS) | Excellent |
| Bridge | Medium | Medium | High | Good |

| Concern | Silo | Pool |
|---------|------|------|
| Noisy neighbor | No | Yes |
| Deployment | N deployments | 1 deployment |
| Schema migration | Per tenant | All at once |
| GDPR compliance | Easy | Complex |
| New tenant speed | Slow (provision) | Fast |

---

## Real-world Production

### Salesforce (Multi-tenant Pioneer)
- Pool model: tất cả customers cùng Oracle DB
- "Metadata-driven": tenant config lưu trong metadata tables
- Custom isolation layer (không dùng DB-native isolation)
- Xử lý 150,000+ customers trên shared infra

### Shopify
- Shop-level sharding (Bridge model)
- Mỗi shop là 1 tenant, sharded by shop_id
- Vitess cho MySQL sharding
- Redis namespace per shop

### GitHub (Enterprises)
- Silo cho Enterprise (dedicated instances)
- Pool cho free/pro users

---

## Ghi chú

**Sub-topic tiếp theo:**
- `billing_metering.md` – Usage metering per tenant, Stripe integration
- `rate_limiting.md` – Tenant-aware rate limiting
- **Keywords:** Tenant isolation, Row-Level Security (RLS), Cross-tenant data leak, Noisy neighbor mitigation, Tenant provisioning automation, Data residency, GDPR right to erasure, Soft delete, Tenant context propagation, Virtual Private Database (Oracle VPD), Database connection per tenant, Connection pool per tenant
