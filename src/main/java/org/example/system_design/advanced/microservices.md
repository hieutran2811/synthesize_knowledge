# Microservices Architecture – Kiến trúc Microservices

## What – Microservices là gì?

**Microservices** là kiến trúc phần mềm chia application thành các **service nhỏ, độc lập**, mỗi service:
- Chạy trong process riêng
- Giao tiếp qua lightweight protocol (HTTP/REST, gRPC, Message Queue)
- Được deploy, scale, và develop độc lập
- Có database riêng (Database per Service)

```
Monolith:                    Microservices:
┌─────────────────────┐      ┌──────┐ ┌──────┐ ┌──────┐
│ UI + API + Auth     │      │ Auth │ │Order │ │ Pay  │
│ + Orders + Payment  │ →→→  │ Svc  │ │ Svc  │ │ Svc  │
│ + Notification      │      └──────┘ └──────┘ └──────┘
│ + [shared DB]       │      ┌──────┐ ┌──────┐
└─────────────────────┘      │Notif │ │ User │
                             │ Svc  │ │ Svc  │
                             └──────┘ └──────┘
```

---

## Decomposition Patterns

### 1. Decompose by Business Capability
Chia theo **khả năng nghiệp vụ** của tổ chức.

```
Business Capabilities:
├── Customer Management → Customer Service
├── Order Management → Order Service
├── Inventory Management → Inventory Service
├── Payment Processing → Payment Service
└── Notification → Notification Service
```

**Nguồn gốc từ** Domain-Driven Design (DDD) – Bounded Context.

### 2. Decompose by Subdomain (DDD)

```
Domain: E-commerce
├── Core Subdomain (competitive advantage):
│   ├── Order Processing
│   └── Recommendation Engine
├── Supporting Subdomain:
│   ├── Notification
│   └── Reporting
└── Generic Subdomain (buy, don't build):
    ├── Authentication (Auth0, Keycloak)
    └── Payment (Stripe, Braintree)
```

### 3. Strangler Fig Pattern (Migration từ Monolith)

```
Phase 1: Route mới features → Microservice
         Old features vẫn ở Monolith
         
Phase 2: Migrate feature A → Service A (Extract)

Phase 3: Monolith shrinks, Microservices grow

Phase N: Monolith = empty → decommission
```

**Façade (API Gateway):** Route requests đến monolith hoặc new services transparently.

---

## Inter-Service Communication

### Synchronous (Request-Response)

#### REST (HTTP/JSON)
```
Order Service → GET /api/users/{id} → User Service
             ← { id: 1, name: "Alice" }
```
- Simple, widely supported
- Tight coupling – nếu User Service down → Order Service bị ảnh hưởng

#### gRPC (HTTP/2 + Protobuf)
```protobuf
service UserService {
  rpc GetUser(GetUserRequest) returns (User);
  rpc StreamUsers(Empty) returns (stream User);
}
```
- 5-10x faster serialization so với JSON
- Strongly typed (protobuf schema)
- Bidirectional streaming
- **Dùng cho:** Internal service-to-service, high-throughput, mobile apps

#### GraphQL
- Client kiểm soát data shape (không over/under-fetch)
- Federation để combine nhiều service thành 1 graph
- **Dùng cho:** BFF (Backend for Frontend), mobile với variable bandwidth

### Asynchronous (Event-driven)

```
Order Service → [Kafka: order.created] → Inventory Service (reserve stock)
                                       → Notification Service (send email)
                                       → Analytics Service (update metrics)
```

**Ưu:** Loose coupling, resilience, fan-out dễ
**Nhược:** Eventual consistency, harder debugging, need message broker

---

## API Gateway

Single entry point cho tất cả clients.

```
Mobile App ──┐
Web App ─────┤→ API Gateway → Auth Service
Partner API ─┘               → Order Service
                             → User Service
                             → Product Service
```

**Chức năng API Gateway:**
| Feature | Description |
|---------|-------------|
| **Routing** | Route /api/orders → Order Service |
| **Authentication** | Validate JWT/API key trước khi forward |
| **Rate Limiting** | Throttle per client/tenant |
| **Load Balancing** | Balance between service instances |
| **SSL Termination** | Decrypt HTTPS, forward HTTP |
| **Request/Response Transform** | Aggregate, translate format |
| **Circuit Breaking** | Stop forwarding if service is down |
| **Logging/Tracing** | Centralized access logs, trace headers |

**Popular API Gateways:**
- AWS API Gateway / ALB
- Kong (open source + enterprise)
- Nginx + Lua
- Traefik (Kubernetes native)
- Spring Cloud Gateway (Java)

### BFF (Backend for Frontend) Pattern
Mỗi client type có API Gateway riêng tối ưu cho client đó:

```
Mobile App → Mobile BFF → (compose: User + Orders + Recommendations)
Web App    → Web BFF    → (full data, pagination)
Partner    → Partner BFF → (limited, versioned API)
```

---

## Service Discovery

Microservices cần biết address của nhau → Service Discovery.

### Client-side Discovery
Client tự query Service Registry rồi load balance:

```
Order Service → Eureka Registry → [userSvc: 10.0.1.5:8080, 10.0.1.6:8080]
              → Load balance    → 10.0.1.5:8080
```

**Tools:** Netflix Eureka, Consul, etcd

### Server-side Discovery
Client gọi LB, LB query registry:

```
Order Service → AWS ALB → ECS Service Discovery → User Service instance
```

**Kubernetes:** Built-in DNS-based discovery
```
http://user-service.default.svc.cluster.local:8080
         └─────────┘ └──────┘ └──────────────┘
         service     namespace  cluster suffix
```

---

## Service Mesh (Sidecar Pattern)

Inject sidecar proxy vào mỗi service pod, handle cross-cutting concerns:

```
Service A Pod:          Service B Pod:
┌────────────────┐      ┌────────────────┐
│ App Container  │      │ App Container  │
│ (business code)│      │                │
├────────────────┤      ├────────────────┤
│ Envoy (sidecar)│─mTLS→│ Envoy (sidecar)│
└────────────────┘      └────────────────┘
         │                       │
    Control Plane (Istio)
```

**Chức năng Service Mesh:**
- mTLS (mutual TLS): encrypt + authenticate service-to-service
- Observability: Distributed tracing, metrics, logs
- Traffic management: Canary, A/B, circuit breaking
- Retry, timeout, load balancing

**Tools:** Istio, Linkerd, Consul Connect, AWS App Mesh

**Trade-off:** Adds latency (~1ms per hop), operational complexity, learning curve.

---

## Database per Service Pattern

Mỗi service owns its data, không share DB với service khác.

```
❌ Anti-pattern (Shared DB):
Order Service ──┐
User Service ───┤→ [Shared PostgreSQL]
Payment Service─┘
→ Schema changes break other services
→ Cannot scale independently
→ No bounded context

✅ Correct:
Order Service → [Orders DB - PostgreSQL]
User Service → [Users DB - MySQL]
Payment Service → [Payments DB - PostgreSQL]
Analytics Service → [Analytics DB - ClickHouse]
```

**Vấn đề:** Cross-service queries phức tạp hơn.

**Giải pháp:**
1. API Composition: App gọi nhiều services, aggregate kết quả
2. CQRS + Event-sourcing: Maintain materialized view trong Read Service
3. Saga pattern: Cross-service transactions

---

## Distributed Tracing

Track request flow qua nhiều services.

```
Request: [Trace ID: abc123]
User → API GW [Span 1: 5ms]
     → Order Svc [Span 2: 20ms]
       → Inventory Svc [Span 3: 10ms]
       → Payment Svc [Span 4: 50ms]
           → Stripe API [Span 5: 40ms]
     → Response

Total: 85ms, payment is bottleneck
```

**Implementation (Spring Boot + Micrometer):**
```java
@Bean
public Tracer tracer(Tracing tracing) {
    return tracing.tracer();
}

// Auto-inject trace headers via Spring Cloud Sleuth
// X-B3-TraceId: abc123
// X-B3-SpanId: def456
// X-B3-ParentSpanId: ghi789
```

**Tools:** Zipkin, Jaeger, AWS X-Ray, Datadog APM

---

## Trade-offs: Monolith vs Microservices

| | Monolith | Microservices |
|--|---------|---------------|
| **Complexity** | Low | High |
| **Deployment** | Single deploy | CI/CD per service |
| **Scaling** | Whole app scale | Per-service scale |
| **Technology** | Uniform | Polyglot possible |
| **Team size** | Small (< 20) | Large (many teams) |
| **Debugging** | Easy (single process) | Harder (distributed) |
| **Network calls** | In-process (ns) | HTTP/gRPC (ms) |
| **Data consistency** | ACID | Eventual consistency |
| **Start** | Faster | Slower |

### "Microservices-ready" checklist:
- [ ] Có dedicated DevOps/Platform team
- [ ] CI/CD pipeline đã mature
- [ ] Service Discovery, API Gateway setup
- [ ] Distributed tracing
- [ ] Centralized logging
- [ ] Container orchestration (Kubernetes)
- [ ] Team size và ownership rõ ràng

---

## Real-world Production

### Netflix
- 500+ microservices
- Hystrix (circuit breaker), Ribbon (client-side LB), Eureka (service discovery)
- Chuyển dần sang gRPC + Envoy

### Uber
- Started monolith → trip service outages → microservices
- DOSA (Domain-Oriented Microservice Architecture): nhóm microservices vào "domains"

### Amazon
- "Two-pizza team" rule: team nhỏ đủ cho 2 pizza → owns 1-2 microservices

---

## Ghi chú

**Sub-topic tiếp theo:**
- `event_driven_architecture.md` – Event Sourcing, CQRS, Saga pattern
- `distributed_transactions.md` – Xử lý transaction across services
- **Keywords:** Conway's Law (org structure mirrors architecture), Domain-Driven Design (DDD), Aggregate, Anti-corruption layer, Event storming, Bounded context, Polyglot persistence, Service ownership, Team topologies
