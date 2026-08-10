---
title: "Roadmap Tổng Hợp Kiến Thức Spring Boot Deep Dive"
topic: springboot
level: mixed
review_status: needs_review
content_updated: null
last_verified: null
version_scope: "Spring Boot 3"
source_count: 2
---
# Roadmap Tổng Hợp Kiến Thức Spring Boot Deep Dive

> 📖 Tra cứu thuật ngữ: xem [glossary.md](glossary.md)
>
> Phạm vi chính: Spring Boot 3.5 và 4.1. Các khác biệt lớn giữa hai major version được ghi rõ tại nơi có liên quan.

## Cấu trúc thư mục
```
springboot/
├── roadmap.md                        ← file này
├── glossary.md                       ← thuật ngữ Spring Boot tra cứu nhanh
├── springboot_core.md               ← Auto-config internals, Custom Starter, ConfigurationProperties, Profiles, Events, Lifecycle, @Async, Secrets/Vault
├── springboot_web.md                ← REST API, WebFlux/Reactive, WebClient, Security (JWT/OAuth2), Exception Handling (ProblemDetail), Validation, OpenAPI
├── springboot_data.md               ← JPA deep (N+1, Projections, Specs), Spring Cache, Multi-datasource, Flyway/Liquibase, R2DBC
├── springboot_messaging.md          ← Spring Kafka, Spring AMQP, @EventListener, @TransactionalEventListener, Saga, Outbox
├── springboot_testing.md            ← Test slices, MockMvc, Testcontainers, WireMock, Security testing, Integration tests
├── springboot_production.md         ← Actuator, Micrometer/OTEL, GraalVM native, Docker layered JAR, K8s, Virtual Threads, JVM tuning
└── springboot_scheduling.md         ← @Scheduled, ShedLock, Quartz, Spring Batch (chunk/parallel/partition)
```

> **Prerequisite**: Đã có kiến thức cơ bản tại `java/spring/` (spring_core, spring_boot, spring_aop, spring_mvc_transaction)

---

## Mục lục

| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Core & Internals – Auto-config SPI, Custom Starter, @ConfigurationProperties, Profiles, ApplicationEvents, Lifecycle, @Async/CompletableFuture, Secrets (Vault/K8s/Jasypt), startup optimization | [springboot_core.md](springboot_core.md) | ✅ |
| 2 | Web Layer – REST best practices, ProblemDetail RFC 9457, Business exception hierarchy, WebFlux (Mono/Flux), WebClient, RestClient, JWT/OAuth2 Security, OpenAPI 3, CORS, Rate Limiting | [springboot_web.md](springboot_web.md) | ✅ |
| 3 | Data Layer – JPA N+1 & solutions, Projections, Specifications/Querydsl, Spring Cache (multi-level L1+L2), Multiple datasources (read/write split), Flyway/Liquibase, R2DBC reactive | [springboot_data.md](springboot_data.md) | ✅ |
| 4 | Messaging – Spring Kafka deep (DLT, retry, Streams), Spring AMQP deep, Application Events, @TransactionalEventListener, Outbox pattern, Saga (Choreography/Orchestration) | [springboot_messaging.md](springboot_messaging.md) | ✅ |
| 5 | Testing – Test slices (@WebMvcTest/@DataJpaTest), MockMvc patterns, Testcontainers (@ServiceConnection), WireMock, Security testing (@WithMockJwtUser), Integration test strategy | [springboot_testing.md](springboot_testing.md) | ✅ |
| 6 | Production – Actuator custom endpoints, Micrometer+Prometheus, OpenTelemetry tracing, GraalVM native image, Docker layered JARs, K8s probes, Virtual Threads (3.2+), JVM & HikariCP tuning | [springboot_production.md](springboot_production.md) | ✅ |
| 7 | Scheduling & Batch – @Scheduled (cron/fixedDelay/fixedRate), Dynamic scheduling, ShedLock distributed lock, Quartz (persistent/cluster-aware), Spring Batch (chunk/parallel/partitioned) | [springboot_scheduling.md](springboot_scheduling.md) | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành
- 🔄 Đang làm
- ⬜ Chưa làm

---

## Quick Reference: Spring Boot Versions

| Version line | Spring Framework | Java | Ghi chú thực tế |
|--------------|------------------|------|-----------------|
| 3.4.x | 6.2.x | 17+ | Nhánh Boot 3 cũ hơn; kiểm tra support policy trước khi bắt đầu dự án mới. |
| 3.5.x | 6.2.x | 17+ | Điểm xuất phát phù hợp trước khi migrate lên Boot 4; vẫn dùng cấu trúc starter/package của Boot 3. |
| 4.0.x | 7.0.x | 17+ | Jakarta EE 11, Servlet 6.1, Jackson 3 và cấu trúc module/starter mới. |
| 4.1.x | 7.0.8+ | 17–26 | Dòng mới nhất trong tài liệu này; có Spring gRPC, cải thiện observability và bảo vệ HTTP client trước SSRF. |

> ⚠️ Bảng này là ảnh chụp tại **2026-07-27**. Luôn kiểm tra [Spring Boot System Requirements](https://docs.spring.io/spring-boot/system-requirements.html) và support policy trước khi chọn version production.

> 💡 **Giải thích dễ hiểu:**
> Chọn major version giống chọn nền móng cho một tòa nhà. Boot 3 và Boot 4 đều là Spring Boot, nhưng Boot 4 thay nhiều module, starter và dependency nền; không nên chỉ đổi số version rồi kỳ vọng mọi import/config vẫn chạy.

## Dependency Map

### Spring Boot 3.x

```text
spring-boot-starter-web       → Spring MVC + embedded server
spring-boot-starter-webflux   → WebFlux + Reactor Netty
spring-boot-starter-data-jpa  → Spring Data JPA + Hibernate + HikariCP
spring-boot-starter-security  → Spring Security
spring-boot-starter-actuator  → Actuator + Micrometer
spring-boot-starter-test      → JUnit + Mockito + AssertJ
```

### Spring Boot 4.x

```text
spring-boot-starter-webmvc       → Spring MVC server
spring-boot-starter-webclient    → reactive WebClient
spring-boot-starter-restclient   → imperative RestClient/RestTemplate
spring-boot-starter-data-jpa     → Spring Data JPA + Hibernate
spring-boot-starter-flyway       → Flyway integration
spring-boot-starter-liquibase    → Liquibase integration
spring-boot-starter-<tech>-test  → test support theo từng technology
```

Boot 4 được **modularize** *(chia thành module nhỏ hơn)*. Khi migrate, cần đọc [Spring Boot 4.0 Migration Guide](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide) và thay starter/module theo công nghệ đang dùng thay vì phụ thuộc vào transitive dependency tình cờ.

---

<!-- AUTO-GENERATED-DOC-INDEX:START -->

## Tài liệu trong chủ đề

- [📖 Spring Boot Glossary – Bảng thuật ngữ](glossary.md)
- [Spring Boot Core *(phần lõi)* & Internals *(cơ chế bên trong)*](springboot_core.md)
- [Spring Boot Data Layer – Deep Dive](springboot_data.md)
- [Spring Boot Messaging *(nhắn tin bất đồng bộ)* – Deep Dive](springboot_messaging.md)
- [Spring Boot Production – Deep Dive](springboot_production.md)
- [Spring Boot Scheduling & Batch – Deep Dive](springboot_scheduling.md)
- [Spring Boot Testing – Chiến lược kiểm thử từ Unit đến Production](springboot_testing.md)
- [Spring Boot Web Layer – REST, WebFlux, Security và Production](springboot_web.md)

<!-- AUTO-GENERATED-DOC-INDEX:END -->
