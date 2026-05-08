# Roadmap Tổng Hợp Kiến Thức Java

## Cấu trúc thư mục
```
java/
├── roadmap.md                      ← file này
├── java_knowledge.md               ← overview tổng quan
├── oop/                            ← OOP deep dive
│   ├── encapsulation.md
│   ├── inheritance.md
│   ├── polymorphism.md
│   ├── abstraction.md
│   ├── solid.md
│   └── composition.md
├── core/                           ← Java Core API deep dive
│   ├── collections.md
│   ├── generics.md
│   ├── lambda.md
│   ├── streams.md
│   ├── exceptions.md
│   ├── concurrency.md
│   ├── io_nio.md
│   ├── reflection_annotations.md
│   ├── datetime.md
│   ├── strings.md
│   ├── concurrency_advanced.md
│   ├── collections_internals.md
│   └── errors.md
├── patterns/                       ← Design Patterns deep dive
│   ├── creational.md
│   ├── structural.md
│   ├── behavioral.md
│   ├── patterns_modern_java.md
│   ├── patterns_enterprise.md
│   └── antipatterns.md
├── jvm/                            ← JVM Internals deep dive
│   ├── classloader.md
│   ├── jit_compiler.md
│   ├── gc.md
│   ├── java_memory_model.md
│   └── runtime_data_areas.md
├── modern/                         ← Modern Java (16-21) deep dive
│   ├── records.md
│   ├── sealed_classes.md
│   ├── pattern_matching.md
│   ├── virtual_threads.md
│   └── java_modules.md             ← JPMS, module-info.java, jlink
├── spring/                         ← Spring Framework deep dive
│   ├── spring_core.md
│   ├── spring_aop.md
│   ├── spring_boot.md
│   ├── spring_mvc_transaction.md
│   └── spring_security.md          ← JWT, OAuth2, method security
├── core/ (bổ sung)
│   ├── testing.md                  ← JUnit 5, Mockito, Testcontainers
│   ├── reactive.md                 ← Project Reactor, WebFlux, R2DBC
│   └── performance_tuning.md       ← JMH, JFR, async-profiler, HikariCP
└── data/                           ← Data Access deep dive
    ├── jdbc.md
    ├── jpa_hibernate.md
    └── spring_data_jpa.md
```

---

## Mục lục đã hoàn thành ✅

### Nền tảng Java
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 1 | Java Overview – JVM, JRE, JDK, WORA, compile flow | java_knowledge.md | ✅ |
| 2 | Data Types & Variables – primitives, autoboxing, Integer cache | java_knowledge.md | ✅ |
| 3 | Control Flow – if/else, switch expression (Java 14+), loops | java_knowledge.md | ✅ |
| 4 | Arrays & Strings – String Pool, immutability, StringBuilder | java_knowledge.md | ✅ |

### OOP – Hướng Đối Tượng
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 5.1 | Encapsulation – access modifiers, immutable object, Records, defensive copy, Tell Don't Ask | oop/encapsulation.md | ✅ |
| 5.2 | Inheritance – constructor chaining, vtable, dynamic dispatch, equals/hashCode, LSP, Fragile Base Class | oop/inheritance.md | ✅ |
| 5.3 | Polymorphism – overloading rules, overriding rules, sealed class, pattern matching switch (Java 21) | oop/polymorphism.md | ✅ |
| 5.4 | Abstraction – abstract class, interface evolution (Java 7/8/9), diamond problem, marker interface, functional interface | oop/abstraction.md | ✅ |
| 5.5 | SOLID Principles – SRP, OCP, LSP, ISP, DIP | oop/solid.md | ✅ |
| 5.6 | Composition over Inheritance – delegation, mixin, Strategy, DI as composition | oop/composition.md | ✅ |

### Java Core API
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 6 | Collections Framework – ArrayList/LinkedList internals, HashMap (bucket, treeify), ConcurrentHashMap, Fail-fast/Fail-safe | core/collections.md | ✅ |
| 7 | Generics – type params, bounded wildcards, PECS, type erasure, heap pollution, @SafeVarargs | core/generics.md | ✅ |
| 8 | Lambda & Functional Interface – 4 method reference types, closure, effectively final, composing, currying | core/lambda.md | ✅ |
| 9 | Stream API – lazy eval, intermediate/terminal ops, Collectors (groupingBy, teeing), Optional, parallel stream | core/streams.md | ✅ |
| 10 | Exception Handling – hierarchy, checked/unchecked, try-with-resources, suppressed, chaining, anti-patterns | core/exceptions.md | ✅ |
| 11 | Concurrency & Multithreading – thread lifecycle, synchronized, volatile, atomic, ReentrantLock, CompletableFuture, utilities | core/concurrency.md | ✅ |
| 12 | I/O & NIO – byte/char streams, ByteBuffer state machine, NIO Selector, NIO.2 Path/Files, WatchService, memory-mapped | core/io_nio.md | ✅ |
| 13 | Reflection & Annotations – Class/Field/Method API, @Retention/@Target, AnnotationProcessor, Dynamic Proxy, MethodHandle | core/reflection_annotations.md | ✅ |
| 14 | Date/Time API – Instant/LocalDate/ZonedDateTime/Duration/Period, DateTimeFormatter, Clock, DST pitfalls | core/datetime.md | ✅ |
| 15 | String Deep Dive – String Pool, immutability, Compact Strings, StringBuilder, regex (Pattern/Matcher), text blocks, Charset | core/strings.md | ✅ |
| 16 | Concurrency Advanced – Fork/Join (work-stealing), ThreadLocal internals (memory leak), Lock-free/CAS/ABA, Phaser/Exchanger, CompletableFuture advanced, Flow API | core/concurrency_advanced.md | ✅ |
| 17 | Collections Internals – PriorityQueue (binary heap/sift-up/sift-down), ArrayDeque (circular buffer), EnumSet/EnumMap, WeakHashMap, IdentityHashMap, Spliterator, immutable collections (Java 9+) | core/collections_internals.md | ✅ |
| 18 | Java Error – Error hierarchy, OOM (heap/metaspace/GC overhead/native thread), StackOverflow, LinkageError, AssertionError, ExceptionInInitializerError, chẩn đoán JVM, tuning production | core/errors.md | ✅ |

### Design Patterns (GoF)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 13.1 | Creational – Singleton (5 variants), Builder, Factory Method, Abstract Factory, Prototype | patterns/creational.md | ✅ |
| 13.2 | Structural – Adapter, Bridge, Composite, Decorator, Facade, Flyweight, Proxy (JDK/CGLIB/AOP) | patterns/structural.md | ✅ |
| 13.3 | Behavioral – Strategy, Observer, Template Method, Command, Chain of Responsibility, State, Visitor, Mediator, Iterator | patterns/behavioral.md | ✅ |
| 13.4 | Modern Java Patterns – GoF với Lambda/Records/Sealed Classes, Result monad, Event Sourcing với sealed events | patterns/patterns_modern_java.md | ✅ |
| 13.5 | Enterprise Patterns – Repository, Unit of Work, CQRS, Event Sourcing, Saga, Outbox, Circuit Breaker, Bulkhead | patterns/patterns_enterprise.md | ✅ |
| 13.6 | Anti-patterns – God Object, Anemic Domain, Primitive Obsession, Service Locator, Singleton overuse, Exception swallowing, N+1 | patterns/antipatterns.md | ✅ |

### JVM Internals
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 14 | Java Memory Model & GC – overview | java_knowledge.md | ✅ |
| 14.1 | ClassLoader – hierarchy, parent delegation, custom ClassLoader, class loading phases, isolation | jvm/classloader.md | ✅ |
| 14.2 | JIT Compiler – tiered compilation, inlining, escape analysis, devirtualization, OSR, GraalVM, profiling | jvm/jit_compiler.md | ✅ |
| 14.3 | Garbage Collection – heap layout (Eden/Survivor/Old), GC algorithms, Serial/Parallel/G1/ZGC, reference types, memory leaks | jvm/gc.md | ✅ |
| 14.4 | Java Memory Model (JMM) – happens-before, volatile semantics, synchronized, safe publication, DCL, VarHandle | jvm/java_memory_model.md | ✅ |
| 14.5 | JVM Runtime Data Areas – Metaspace, heap, stack frames, bytecode instructions, invokedynamic, stack trace reading | jvm/runtime_data_areas.md | ✅ |

### Modern Java (16–21)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 17.1 | Records (Java 16) – value objects, compact canonical constructor, limitations, deconstruction pattern | modern/records.md | ✅ |
| 17.2 | Sealed Classes (Java 17) – ADT/sum types, permits, exhaustive switch, Result<T> monad | modern/sealed_classes.md | ✅ |
| 17.3 | Pattern Matching – instanceof (Java 16), switch patterns (Java 21), guarded, deconstruction, unnamed `_` | modern/pattern_matching.md | ✅ |
| 17.4 | Virtual Threads (Java 21) – Project Loom, mount/unmount, StructuredTaskScope, pinning, ScopedValue | modern/virtual_threads.md | ✅ |
| 17.5 | Java Modules (JPMS) – module-info.java (requires/exports/opens/uses/provides), module types, ServiceLoader SPI, jlink custom JRE, migration từ classpath | modern/java_modules.md | ✅ |

### Spring Framework
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 15.1 | Spring Core – IoC Container, Bean lifecycle (8 steps), DI types, scopes, @Conditional, @Profile, events | spring/spring_core.md | ✅ |
| 15.2 | Spring AOP – proxy-based (JDK/CGLIB), 5 advice types, pointcut expressions, self-invocation problem | spring/spring_aop.md | ✅ |
| 15.3 | Spring Boot – auto-configuration, @ConditionalOn*, starters, @ConfigurationProperties, profiles, Actuator | spring/spring_boot.md | ✅ |
| 15.4 | Spring MVC – DispatcherServlet lifecycle, request binding, ResponseEntity, @ControllerAdvice | spring/spring_mvc_transaction.md | ✅ |
| 15.5 | Spring Transaction – 7 propagation types, 4 isolation levels, rollback rules, @TransactionalEventListener, pitfalls | spring/spring_mvc_transaction.md | ✅ |
| 15.6 | Spring Security – SecurityFilterChain (lambda DSL), JWT (JJWT, OncePerRequestFilter), OAuth2 (Resource Server, Client), method security (@PreAuthorize SpEL), CSRF/CORS, password encoding | spring/spring_security.md | ✅ |

### Data Access
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 16.1 | JDBC – Connection, PreparedStatement (SQL injection), ResultSet, batch ops, HikariCP pool, JdbcTemplate | data/jdbc.md | ✅ |
| 16.2 | JPA & Hibernate – Entity lifecycle, persistence context, N+1 fix (JOIN FETCH/@BatchSize/@EntityGraph), JPQL/Criteria/Native, locking | data/jpa_hibernate.md | ✅ |
| 16.3 | Spring Data JPA – Repository hierarchy, query derivation, @Query, Specification, Pageable, Auditing, projections | data/spring_data_jpa.md | ✅ |

### Advanced Topics (bổ sung)
| STT | Chủ đề | File | Trạng thái |
|-----|--------|------|-----------|
| 18.1 | Spring Security – Authentication (JWT/Session), Authorization (@PreAuthorize, method security), CSRF, CORS | spring/spring_security.md | ✅ |
| 18.2 | Testing – JUnit 5 (@ParameterizedTest/@TestFactory, Extension API), Mockito (mock/spy/ArgumentCaptor/MockedStatic), AssertJ, @WebMvcTest/@DataJpaTest, Testcontainers | core/testing.md | ✅ |
| 18.3 | Reactive Programming – Project Reactor (Mono/Flux, cold/hot, backpressure), operators (flatMap/switchMap/zip), Schedulers, WebFlux, R2DBC, StepVerifier | core/reactive.md | ✅ |
| 18.4 | Java Modules (JPMS) – module-info.java, requires/exports/opens, migration from classpath | modern/java_modules.md | ✅ |
| 18.5 | Performance Tuning & Profiling – JVM flags (ZGC/G1, container-aware), JFR, async-profiler, JMH microbenchmarking, HikariCP, Foreign Memory API | core/performance_tuning.md | ✅ |

---

## Chủ đề tiếp theo ⬜

### Có thể bổ sung thêm
| STT | Chủ đề | Ghi chú | Trạng thái |
|-----|--------|---------|-----------|
| 19.1 | Logging – SLF4J/Logback, structured logging (JSON), MDC, async appender, log aggregation | ELK/Loki integration | ⬜ |
| 19.2 | Observability – Micrometer, Prometheus, distributed tracing (OpenTelemetry, Zipkin/Jaeger) | Spring Boot Actuator integration | ⬜ |
| 19.3 | Messaging – Spring Kafka, Spring AMQP (RabbitMQ), transactional outbox pattern | Event-driven architecture | ⬜ |
| 19.4 | gRPC & Protobuf – code generation, streaming (unary/server/client/bidi), deadline/retry | Service-to-service communication | ⬜ |
| 19.5 | GraalVM Native Image – AOT compilation, reflection config, native hints, build size | Alternative to jlink for small images | ⬜ |

## Chú thích trạng thái
- ✅ Hoàn thành – đã có file deep dive
- 🔄 Đang làm
- ⬜ Chưa làm
