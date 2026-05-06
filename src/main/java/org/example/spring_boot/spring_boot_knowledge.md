# Spring Boot – Tổng hợp Kiến thức

## What – Spring Boot là gì?

**Spring Boot** là opinionated framework xây dựng trên Spring Framework, giải quyết bài toán cấu hình phức tạp bằng **Auto-configuration + Convention over Configuration**.

> File này là overview. Kiến thức nền tảng (IoC/DI, AOP, Auto-config, MVC, Transaction) đã có tại `java/spring/`. File này tập trung vào các chủ đề còn lại: Security, Data Access nâng cao, Testing, WebFlux, Messaging, Cache, Scheduling, Async, và Production patterns.

---

## Ecosystem Map

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Spring Boot Application                        │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐ │
│  │ Security │  │  Data    │  │Messaging │  │   Observability      │ │
│  │ JWT/OAuth│  │ JPA/R2DBC│  │Kafka/AMQ │  │ Micrometer/OTel      │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────────────┘ │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────────────┐ │
│  │  Cache   │  │ WebFlux  │  │  Batch   │  │   Production         │ │
│  │ Redis/   │  │ Reactor  │  │Spring    │  │ Config/Secrets/Perf  │ │
│  │ Caffeine │  │ R2DBC    │  │Batch     │  │ GraalVM/Virtual Thr  │ │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────────────┘ │
│                                                                      │
│  Foundation (java/spring/): IoC/DI, AOP, MVC, Transaction           │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Roadmap

### Basics (Cơ bản)
1. `basics/security.md` – Spring Security: Auth, JWT, OAuth2/OIDC, Method Security
2. `basics/data_access.md` – Spring Data JPA nâng cao, Specifications, QueryDSL, projections
3. `basics/validation_exception.md` – Bean Validation, @ControllerAdvice, Problem Details RFC 9457
4. `basics/testing.md` – @SpringBootTest, @WebMvcTest, @DataJpaTest, Testcontainers, WireMock

### Advanced (Nâng cao)
5. `advanced/reactive_webflux.md` – WebFlux, Project Reactor, R2DBC, SSE, backpressure
6. `advanced/messaging.md` – Spring Kafka, RabbitMQ/AMQP, outbox pattern, dead-letter
7. `advanced/cache.md` – @Cacheable/@CacheEvict, Redis, multi-level (Caffeine + Redis)
8. `advanced/scheduling_batch.md` – @Scheduled, Quartz, Spring Batch (chunk-oriented)
9. `advanced/async_concurrency.md` – @Async, CompletableFuture, Virtual Threads (Java 21)

### Production (Thực chiến)
10. `production/observability.md` – Micrometer, OpenTelemetry, custom metrics, tracing
11. `production/configuration_secrets.md` – Config Server, Vault, K8s ConfigMap/Secret
12. `production/performance_tuning.md` – HikariCP, thread pools, JVM tuning, GraalVM native
13. `production/production_patterns.md` – 12-Factor, Graceful shutdown, health checks, layered JAR

---

## Tham chiếu chéo

| Topic | File trong project |
|-------|-------------------|
| IoC, DI, Bean lifecycle | `java/spring/spring_core.md` |
| AOP, @Transactional internals | `java/spring/spring_aop.md` |
| Auto-configuration, Actuator | `java/spring/spring_boot.md` |
| MVC, Transaction | `java/spring/spring_mvc_transaction.md` |
| JPA, Hibernate | `java/data/jpa_hibernate.md` |
| Redis patterns | `redis/` |
| Kafka | `kafka/` |
| System Design cho SaaS | `system_design/` |
