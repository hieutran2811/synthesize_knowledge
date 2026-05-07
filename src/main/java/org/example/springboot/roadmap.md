# Roadmap Tổng Hợp Kiến Thức Spring Boot Deep Dive

## Cấu trúc thư mục
```
springboot/
├── roadmap.md                        ← file này
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
| 1 | Core & Internals – Auto-config SPI, Custom Starter, @ConfigurationProperties, Profiles, ApplicationEvents, Lifecycle, @Async/CompletableFuture, Secrets (Vault/K8s/Jasypt), startup optimization | springboot_core.md | ✅ |
| 2 | Web Layer – REST best practices, ProblemDetail RFC 9457, Business exception hierarchy, WebFlux (Mono/Flux), WebClient, RestClient, JWT/OAuth2 Security, OpenAPI 3, CORS, Rate Limiting | springboot_web.md | ✅ |
| 3 | Data Layer – JPA N+1 & solutions, Projections, Specifications/Querydsl, Spring Cache (multi-level L1+L2), Multiple datasources (read/write split), Flyway/Liquibase, R2DBC reactive | springboot_data.md | ✅ |
| 4 | Messaging – Spring Kafka deep (DLT, retry, Streams), Spring AMQP deep, Application Events, @TransactionalEventListener, Outbox pattern, Saga (Choreography/Orchestration) | springboot_messaging.md | ✅ |
| 5 | Testing – Test slices (@WebMvcTest/@DataJpaTest), MockMvc patterns, Testcontainers (@ServiceConnection), WireMock, Security testing (@WithMockJwtUser), Integration test strategy | springboot_testing.md | ✅ |
| 6 | Production – Actuator custom endpoints, Micrometer+Prometheus, OpenTelemetry tracing, GraalVM native image, Docker layered JARs, K8s probes, Virtual Threads (3.2+), JVM & HikariCP tuning | springboot_production.md | ✅ |
| 7 | Scheduling & Batch – @Scheduled (cron/fixedDelay/fixedRate), Dynamic scheduling, ShedLock distributed lock, Quartz (persistent/cluster-aware), Spring Batch (chunk/parallel/partitioned) | springboot_scheduling.md | ✅ |

---

## Chú thích trạng thái
- ✅ Hoàn thành
- 🔄 Đang làm
- ⬜ Chưa làm

---

## Quick Reference: Spring Boot Versions

| Version | Spring Framework | Java | Key Features |
|---------|-----------------|------|-------------|
| 2.7.x | 5.3 | 8-19 | Last 2.x branch, EOL |
| 3.0.x | 6.0 | 17+ | Jakarta EE 9, AOT, native image |
| 3.1.x | 6.0 | 17+ | Docker Compose integration, Testcontainers baked-in |
| 3.2.x | 6.1 | 17+ | Virtual Threads, RestClient, OTEL auto-config |
| 3.3.x | 6.1 | 17+ | CDS (Class Data Sharing), improved observability |
| 3.4.x | 6.2 | 17+ | Structured logging, enhanced security |

## Dependency Map

```
spring-boot-starter-web
  └── spring-webmvc + Tomcat + Jackson + Validation

spring-boot-starter-webflux
  └── spring-webflux + Reactor Netty + Jackson

spring-boot-starter-data-jpa
  └── Hibernate + Spring Data JPA + HikariCP

spring-boot-starter-security
  └── Spring Security 6 (Jakarta EE)

spring-boot-starter-actuator
  └── Micrometer + actuator endpoints

spring-boot-starter-test
  └── JUnit 5 + Mockito + AssertJ + Testcontainers BOM
```
