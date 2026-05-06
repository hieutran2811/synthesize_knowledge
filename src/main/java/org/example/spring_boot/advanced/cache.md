# Spring Cache – Caching chuyên nghiệp

## What – Spring Cache Abstraction

**Spring Cache** là lớp abstraction cho phép thêm caching vào business logic bằng annotation, không quan tâm đến implementation cụ thể (Caffeine, Redis, Hazelcast...).

```java
// Không cần biết cache implementation
@Cacheable("products")
public Product getProduct(Long id) {
    return productRepo.findById(id).orElseThrow(); // chỉ gọi khi cache miss
}
```

---

## Setup

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-cache</artifactId>
</dependency>
<!-- Redis cache provider -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-redis</artifactId>
</dependency>
<!-- Caffeine (local in-process cache) -->
<dependency>
    <groupId>com.github.ben-manes.caffeine</groupId>
    <artifactId>caffeine</artifactId>
</dependency>
```

```java
@SpringBootApplication
@EnableCaching  // Bắt buộc
public class App {}
```

---

## Core Annotations

### @Cacheable – Cache kết quả

```java
@Service
public class ProductService {

    // Basic: cache toàn bộ result với key = id
    @Cacheable("products")
    public Product getProduct(Long id) {
        return productRepo.findById(id).orElseThrow();
    }

    // Custom key: kết hợp nhiều params
    @Cacheable(value = "products", key = "#tenantId + ':' + #id")
    public Product getProductByTenant(Long tenantId, Long id) { ... }

    // SpEL key: method name + params
    @Cacheable(value = "products", key = "#root.methodName + ':' + #filter.hashCode()")
    public List<Product> search(ProductFilter filter) { ... }

    // Conditional: chỉ cache nếu điều kiện thỏa
    @Cacheable(value = "products", condition = "#id > 0")
    public Product getProduct(Long id) { ... }

    // Unless: không cache nếu kết quả thỏa (cache miss không store null)
    @Cacheable(value = "products", unless = "#result == null or #result.deleted")
    public Product getProduct(Long id) { ... }

    // Multiple cache names (check theo thứ tự)
    @Cacheable({"products", "productsV2"})
    public Product getProduct(Long id) { ... }
}
```

### @CachePut – Update cache sau khi ghi

```java
// Luôn execute method VÀ update cache
@CachePut(value = "products", key = "#result.id")
public Product updateProduct(Long id, UpdateProductRequest req) {
    Product product = productRepo.findById(id).orElseThrow();
    product.update(req);
    return productRepo.save(product);
}
```

### @CacheEvict – Xóa cache

```java
// Xóa single entry
@CacheEvict(value = "products", key = "#id")
public void deleteProduct(Long id) {
    productRepo.deleteById(id);
}

// Xóa toàn bộ cache
@CacheEvict(value = "products", allEntries = true)
public void importProducts(List<Product> products) {
    productRepo.saveAll(products);
}

// Evict trước khi execute (beforeInvocation)
@CacheEvict(value = "products", key = "#id", beforeInvocation = true)
public void processProduct(Long id) { ... }
```

### @Caching – Kết hợp nhiều annotations

```java
@Caching(
    put = {
        @CachePut(value = "products", key = "#result.id"),
        @CachePut(value = "products", key = "'slug:' + #result.slug")
    },
    evict = {
        @CacheEvict(value = "productList", allEntries = true)
    }
)
public Product createProduct(CreateProductRequest req) { ... }
```

---

## Cache Configuration

### Caffeine (In-Process – L1 Cache)

```java
@Configuration
@EnableCaching
public class CacheConfig {

    @Bean
    public CacheManager cacheManager() {
        CaffeineCacheManager manager = new CaffeineCacheManager();

        // Default spec
        manager.setCaffeine(Caffeine.newBuilder()
            .maximumSize(10_000)
            .expireAfterWrite(Duration.ofMinutes(10))
            .recordStats()); // metrics

        // Per-cache spec
        manager.setCacheNames(List.of("products", "users", "tenants"));
        return manager;
    }
}

// Hoặc via properties
spring:
  cache:
    caffeine:
      spec: maximumSize=10000,expireAfterWrite=10m
    cache-names: products,users,tenants
```

### Redis (Distributed – L2 Cache)

```java
@Configuration
@EnableCaching
public class RedisCacheConfig {

    @Bean
    public RedisCacheManager cacheManager(RedisConnectionFactory connectionFactory) {
        // Default config
        RedisCacheConfiguration defaultConfig = RedisCacheConfiguration.defaultCacheConfig()
            .entryTtl(Duration.ofMinutes(30))
            .serializeKeysWith(
                RedisSerializationContext.SerializationPair.fromSerializer(new StringRedisSerializer())
            )
            .serializeValuesWith(
                RedisSerializationContext.SerializationPair.fromSerializer(
                    new GenericJackson2JsonRedisSerializer()
                )
            )
            .disableCachingNullValues();

        // Per-cache TTL
        Map<String, RedisCacheConfiguration> cacheConfigs = Map.of(
            "products",      defaultConfig.entryTtl(Duration.ofHours(1)),
            "users",         defaultConfig.entryTtl(Duration.ofMinutes(15)),
            "tenants",       defaultConfig.entryTtl(Duration.ofHours(24)),
            "rate-limits",   defaultConfig.entryTtl(Duration.ofMinutes(1))
        );

        return RedisCacheManager.builder(connectionFactory)
            .cacheDefaults(defaultConfig)
            .withInitialCacheConfigurations(cacheConfigs)
            .transactionAware()  // link với @Transactional
            .build();
    }
}
```

---

## Multi-Level Cache (L1 Caffeine + L2 Redis)

```java
@Configuration
@EnableCaching
public class MultiLevelCacheConfig {

    @Bean
    @Primary
    public CacheManager multiLevelCacheManager(
            CaffeineCacheManager caffeineCacheManager,
            RedisCacheManager redisCacheManager) {

        return new MultiLevelCacheManager(caffeineCacheManager, redisCacheManager);
    }
}

public class MultiLevelCacheManager implements CacheManager {

    private final CacheManager l1Manager;  // Caffeine
    private final CacheManager l2Manager;  // Redis

    @Override
    public Cache getCache(String name) {
        Cache l1 = l1Manager.getCache(name);
        Cache l2 = l2Manager.getCache(name);
        return new MultiLevelCache(l1, l2);
    }
}

public class MultiLevelCache implements Cache {

    private final Cache l1;  // Caffeine (fast, local)
    private final Cache l2;  // Redis (shared, persistent)

    @Override
    public ValueWrapper get(Object key) {
        // Check L1 first
        ValueWrapper l1Value = l1.get(key);
        if (l1Value != null) return l1Value;

        // L1 miss → check L2
        ValueWrapper l2Value = l2.get(key);
        if (l2Value != null) {
            l1.put(key, l2Value.get()); // backfill L1
            return l2Value;
        }

        return null; // cache miss
    }

    @Override
    public void put(Object key, Object value) {
        l1.put(key, value);
        l2.put(key, value);
    }

    @Override
    public void evict(Object key) {
        l1.evict(key);
        l2.evict(key);
        // Cần broadcast eviction tới các L1 caches khác (Pub/Sub)
    }
}
```

### L1 Invalidation Broadcast (Cache Coherence)

```java
// Khi evict L1 trên node này, cần notify tất cả nodes khác
@Component
public class CacheInvalidationService {

    @Autowired
    private RedisTemplate<String, String> redis;

    public void broadcastEviction(String cacheName, Object key) {
        redis.convertAndSend("cache-invalidation",
            cacheName + ":" + key.toString());
    }
}

@Component
public class CacheInvalidationListener {

    @Autowired
    private CaffeineCacheManager l1Manager;

    @RedisListener(channel = "cache-invalidation")
    public void onMessage(String message) {
        String[] parts = message.split(":", 2);
        String cacheName = parts[0];
        String key = parts[1];
        Cache l1Cache = l1Manager.getCache(cacheName);
        if (l1Cache != null) {
            l1Cache.evict(key);  // Invalidate L1 trên node này
        }
    }
}
```

---

## Tenant-Aware Caching

```java
@Bean
public KeyGenerator tenantKeyGenerator() {
    return (target, method, params) -> {
        String tenantId = TenantContext.getCurrentTenant();
        return tenantId + ":" + method.getName() + ":" + Arrays.deepHashCode(params);
    };
}

@Cacheable(value = "products", keyGenerator = "tenantKeyGenerator")
public List<Product> getProducts(ProductFilter filter) { ... }

// Key pattern: "tenant-abc:getProducts:12345"
// Evict all cache for tenant on tenant offboarding:
@CacheEvict(value = "products", allEntries = true)
public void evictTenantCache(String tenantId) { }
```

---

## Cache Metrics

```yaml
management:
  endpoints:
    web:
      exposure:
        include: caches,metrics
  metrics:
    cache:
      instrument:
        enabled: true
```

```java
// Caffeine stats
CaffeineCacheManager mgr = ...;
CaffeineCache cache = (CaffeineCache) mgr.getCache("products");
CacheStats stats = cache.getNativeCache().stats();
log.info("Hit rate: {}, Miss count: {}, Load time: {}",
    stats.hitRate(), stats.missCount(), stats.totalLoadTime());

// Micrometer tự expose: cache.gets, cache.puts, cache.evictions, cache.hits
// Prometheus: cache_gets_total{name="products",result="hit"}
```

---

## Trade-offs

| L1 Cache (Caffeine) | L2 Cache (Redis) |
|---------------------|-----------------|
| < 1ms latency | 1-2ms network |
| Local only (per node) | Shared across nodes |
| No serialization needed | Serialization overhead |
| Lost on restart | Persists across restarts |
| Simple, no infrastructure | Requires Redis cluster |

| TTL Short | TTL Long |
|-----------|----------|
| Fresh data | Stale risk |
| More cache misses | Fewer misses, better perf |
| Lower infra cost (small cache) | Higher memory cost |

---

## Real-world Production

### Cache Key Design
```java
// ❌ Sai: toàn bộ object là key (chậm, fragile)
@Cacheable(value = "products", key = "#filter")

// ✅ Đúng: stable, lightweight key
@Cacheable(value = "products", key = "'tenant:' + #tenantId + ':status:' + #status + ':page:' + #page")
```

### Cache Warming (Preload)
```java
@EventListener(ApplicationReadyEvent.class)
public void warmCache() {
    log.info("Warming cache...");
    List<String> topTenants = tenantRepo.findTopByUsage(100);
    topTenants.parallelStream().forEach(tenantId ->
        productService.getProducts(tenantId, null) // triggers @Cacheable
    );
    log.info("Cache warmed for {} tenants", topTenants.size());
}
```

---

## Ghi chú

**Sub-topic tiếp theo:**
- `advanced/scheduling_batch.md` – @Scheduled, Quartz, Spring Batch
- `production/observability.md` – Cache hit rate monitoring
- **Keywords:** @CacheConfig (class-level default cache name), CompositeCacheManager, CacheResolver, KeyGenerator, Spring Cache + Reactive (ReactiveCache), Redis Cluster cache, Caffeine refreshAfterWrite, Cache stampede protection, Cache-aside vs Spring Cache (@Cacheable = cache-aside), NearCache (Hazelcast)
