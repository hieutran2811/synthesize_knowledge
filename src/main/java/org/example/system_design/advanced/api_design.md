# API Design – Thiết kế API chuyên nghiệp

## What – API Design là gì?

**API Design** là quá trình thiết kế **giao diện lập trình** cho phép các hệ thống communicate với nhau. API tốt là API dễ học, khó dùng sai, dễ evolve, và consistent.

---

## REST API Best Practices

### Resource Naming
```
✅ Danh từ số nhiều, lowercase, hyphen:
GET  /api/v1/orders
GET  /api/v1/orders/{id}
POST /api/v1/orders
PUT  /api/v1/orders/{id}
DELETE /api/v1/orders/{id}

✅ Nested resources:
GET  /api/v1/orders/{orderId}/items
POST /api/v1/orders/{orderId}/items

❌ Sai:
GET  /api/v1/getOrders
POST /api/v1/createOrder
GET  /api/v1/order (không plural)
```

### HTTP Methods + Idempotency

| Method | Idempotent | Safe | Use |
|--------|-----------|------|-----|
| GET | ✅ | ✅ | Read |
| HEAD | ✅ | ✅ | Check existence/metadata |
| PUT | ✅ | ❌ | Full replace |
| PATCH | ❌ | ❌ | Partial update |
| DELETE | ✅ | ❌ | Delete |
| POST | ❌ | ❌ | Create, non-idempotent actions |

**PUT vs PATCH:**
```json
// PUT (full replace): phải gửi toàn bộ object
PUT /users/123
{"name": "Alice", "email": "new@email.com", "age": 30}

// PATCH (partial update): chỉ gửi fields cần update
PATCH /users/123
{"email": "new@email.com"}
```

### HTTP Status Codes

```
2xx Success:
200 OK            – GET, PUT success
201 Created       – POST success (return new resource)
204 No Content    – DELETE success, PUT with no body
202 Accepted      – Async processing started

3xx Redirect:
301 Moved Permanently – Old URL → New URL
304 Not Modified     – Conditional GET, use cached version

4xx Client Error:
400 Bad Request      – Invalid input, validation error
401 Unauthorized     – Not authenticated
403 Forbidden        – Authenticated but not authorized
404 Not Found        – Resource doesn't exist
409 Conflict         – Resource conflict (duplicate, wrong version)
422 Unprocessable    – Validation error (semantic)
429 Too Many Requests – Rate limited

5xx Server Error:
500 Internal Server Error – Unexpected server error
502 Bad Gateway          – Upstream service error
503 Service Unavailable  – Temporarily down
504 Gateway Timeout      – Upstream timeout
```

### Error Response Format
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "timestamp": "2024-01-15T10:30:00Z",
    "traceId": "abc123",
    "details": [
      {
        "field": "email",
        "code": "INVALID_FORMAT",
        "message": "Email must be a valid email address"
      },
      {
        "field": "age",
        "code": "OUT_OF_RANGE",
        "message": "Age must be between 0 and 150"
      }
    ]
  }
}
```

### Pagination

**Offset-based (đơn giản, phổ biến):**
```
GET /orders?page=2&size=20&sort=createdAt,desc

Response:
{
  "data": [...],
  "pagination": {
    "page": 2,
    "size": 20,
    "total": 1250,
    "totalPages": 63
  }
}
```

**Cursor-based (cho real-time data, infinite scroll):**
```
GET /orders?limit=20&after=eyJpZCI6MTIzfQ==  // base64 cursor

Response:
{
  "data": [...],
  "pagination": {
    "nextCursor": "eyJpZCI6MTQzfQ==",
    "prevCursor": "eyJpZCI6MTAzfQ==",
    "hasMore": true
  }
}
```

**Cursor-based tốt hơn khi:**
- Data thay đổi thường xuyên (tránh missing/duplicate khi page)
- Không cần COUNT (expensive với large table)
- Real-time feeds (social media, notifications)

### Filtering và Sorting
```
GET /orders?status=ACTIVE&minAmount=100&maxAmount=1000
GET /orders?sort=createdAt,desc&sort=amount,asc
GET /orders?fields=id,status,amount  // Field selection / sparse fieldsets
GET /orders?include=items,user       // Include related resources
```

---

## API Versioning

### URL Versioning (Phổ biến nhất)
```
GET /api/v1/orders
GET /api/v2/orders
```
**Ưu:** Rõ ràng, dễ route, client control version
**Nhược:** URL "noisy", version duplication trong URL

### Header Versioning
```
GET /api/orders
Accept: application/vnd.example.v2+json
```
**Ưu:** Clean URL
**Nhược:** Ít visible, khó test với browser

### Query Param Versioning
```
GET /api/orders?version=2
```
**Ưu:** Dễ test
**Nhược:** Cache keys phức tạp

### Semantic Versioning cho APIs

```
MAJOR: Breaking changes (v1 → v2)
MINOR: New features, backward compatible (v1.1)
PATCH: Bug fixes (v1.0.1)

Breaking changes:
- Remove/rename field
- Change field type
- Change response structure
- Remove endpoint

Non-breaking:
- Add new field (consumers ignore unknown fields)
- Add new endpoint
- Add optional query param
```

---

## gRPC

### What
**gRPC** (Google Remote Procedure Call) dùng Protocol Buffers và HTTP/2.

```protobuf
// order.proto
syntax = "proto3";

service OrderService {
  rpc GetOrder(GetOrderRequest) returns (Order);
  rpc CreateOrder(CreateOrderRequest) returns (Order);
  rpc ListOrders(ListOrdersRequest) returns (stream Order);  // Server streaming
  rpc TrackOrder(stream TrackEvent) returns (stream OrderStatus);  // Bidirectional
}

message Order {
  string id = 1;
  string user_id = 2;
  double total_amount = 3;
  OrderStatus status = 4;
  repeated OrderItem items = 5;
  google.protobuf.Timestamp created_at = 6;
}

enum OrderStatus {
  PENDING = 0;
  CONFIRMED = 1;
  SHIPPED = 2;
}
```

### gRPC vs REST

| | gRPC | REST |
|--|------|------|
| Protocol | HTTP/2 | HTTP/1.1 (usually) |
| Format | Protobuf (binary) | JSON (text) |
| Performance | 5-10x faster | Baseline |
| Type safety | Strong (protobuf schema) | Weak (JSON) |
| Streaming | Yes (bidirectional) | Limited (SSE) |
| Browser support | Limited | Native |
| Code gen | Auto (protobuf compiler) | Manual or OpenAPI |
| Discoverability | Less (need proto file) | Higher (JSON) |

**Dùng gRPC khi:**
- Internal service-to-service (microservices)
- High throughput (real-time, IoT)
- Mobile clients (smaller payload)
- Streaming (live updates, large data transfer)

**Dùng REST khi:**
- Public API (browser clients)
- Partner/external APIs
- Simple CRUD
- Team không quen protobuf

---

## GraphQL

### What
Client query chính xác data cần, không over-fetch hay under-fetch.

```graphql
# Query: lấy chỉ fields cần
query {
  order(id: "123") {
    id
    status
    items {
      productId
      quantity
    }
    user {
      name
      email
    }
  }
}

# Mutation
mutation {
  createOrder(input: {
    userId: "456",
    items: [{productId: "prod-1", quantity: 2}]
  }) {
    id
    status
  }
}

# Subscription (real-time)
subscription {
  orderStatusChanged(orderId: "123") {
    status
    updatedAt
  }
}
```

### N+1 Problem và DataLoader
```
Query: { orders { user { name } } }
Without DataLoader:
  SELECT * FROM orders  → 100 orders
  SELECT * FROM users WHERE id = 1  → 1 query per order
  SELECT * FROM users WHERE id = 2
  ... 100 queries! → N+1 problem

With DataLoader (batching):
  SELECT * FROM orders
  SELECT * FROM users WHERE id IN (1, 2, ..., 100)  → 1 batch query
```

```java
// Spring Boot GraphQL + DataLoader
@Component
public class UserDataLoader implements BatchLoaderWithContext<Long, User> {
    @Override
    public CompletionStage<List<User>> load(List<Long> userIds, BatchLoaderEnvironment env) {
        return CompletableFuture.supplyAsync(() ->
            userRepo.findAllByIdIn(userIds)
        );
    }
}
```

### GraphQL Federation (Schema stitching cho microservices)
```graphql
# Order Service schema
type Order @key(fields: "id") {
  id: ID!
  status: String!
  userId: ID!
}

# User Service schema
type User @key(fields: "id") {
  id: ID!
  name: String!
  orders: [Order]  # Extends Order from Order Service
}
```

---

## API Security

### Authentication
```
JWT Bearer Token:
Authorization: Bearer eyJhbGciOiJSUzI1NiJ9...

API Key (simple):
X-API-Key: sk_live_abc123

OAuth2 + OpenID Connect:
GET /auth/authorize → user login → code
POST /auth/token → access_token + refresh_token
```

### Rate Limiting Headers
```http
HTTP/1.1 429 Too Many Requests
Retry-After: 60
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1705318200
```

### Input Validation (Spring Boot)
```java
@PostMapping("/orders")
public ResponseEntity<Order> createOrder(
    @Valid @RequestBody CreateOrderRequest request
) { ... }

public class CreateOrderRequest {
    @NotBlank
    @Size(max = 50)
    private String userId;
    
    @NotEmpty
    @Size(min = 1, max = 100)
    private List<@Valid OrderItemRequest> items;
    
    @Positive
    @DecimalMax("10000.00")
    private BigDecimal totalAmount;
}
```

---

## API Documentation

### OpenAPI (Swagger) 3.0
```yaml
openapi: 3.0.0
info:
  title: Order Service API
  version: 2.1.0

paths:
  /orders:
    post:
      summary: Create new order
      tags: [Orders]
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/CreateOrderRequest'
            example:
              userId: "user-123"
              items:
                - productId: "prod-1"
                  quantity: 2
      responses:
        '201':
          description: Order created successfully
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Order'
        '400':
          $ref: '#/components/responses/ValidationError'
        '429':
          $ref: '#/components/responses/RateLimited'
```

---

## Trade-offs

| Technology | Best For | Trade-off |
|-----------|---------|-----------|
| REST | Public APIs, simple CRUD | Over/under-fetch |
| gRPC | Internal services, streaming | Browser support, tooling |
| GraphQL | Complex data, mobile | N+1, caching complexity |
| WebSocket | Real-time, bidirectional | Stateful, harder scale |
| SSE | Server-push, real-time feed | One-way only |

---

## Real-world Production

### Stripe API (REST Excellence)
- Consistent resource naming
- Idempotency keys for all mutations
- Rich error messages với codes
- Webhook với retry và signature verification
- Versioning via header: `Stripe-Version: 2023-10-16`

### GitHub API v4 (GraphQL)
- Reduced API calls từ 10+ → 1
- Typed schema, introspection
- Node global ID system

### Netflix (gRPC + REST hybrid)
- Internal services: gRPC (performance)
- External API: REST + GraphQL

---

## Ghi chú

**Sub-topic tiếp theo:**
- `saas/multi_tenancy.md` – API design cho multi-tenant SaaS
- `saas/rate_limiting.md` – Chi tiết rate limiting implementation
- **Keywords:** HATEOAS (Hypermedia), JSON:API standard, API contract testing (Pact), Consumer-driven contracts, API gateway patterns, Mock servers (WireMock), API mocking, Long polling vs SSE vs WebSocket, API deprecation strategy, Sunset header, API changelog
