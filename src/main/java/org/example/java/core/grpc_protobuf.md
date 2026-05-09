# gRPC & Protobuf – Java

> Phương pháp: What – How (đặc điểm) – How (hoạt động) – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## 1. Protocol Buffers (Protobuf)

### What – Protobuf là gì?
**Protocol Buffers** là binary serialization format của Google. Nhỏ hơn JSON ~3-10x, nhanh hơn ~5-10x parse, schema-first, và language-agnostic.

### How – .proto file syntax

```proto
// order.proto
syntax = "proto3";

package com.example.order;
option java_package = "com.example.grpc.order";
option java_outer_classname = "OrderProto";
option java_multiple_files = true;

import "google/protobuf/timestamp.proto";
import "google/protobuf/wrappers.proto";

// Enum
enum OrderStatus {
  ORDER_STATUS_UNSPECIFIED = 0;   // default, must be 0 in proto3
  ORDER_STATUS_PENDING = 1;
  ORDER_STATUS_CONFIRMED = 2;
  ORDER_STATUS_SHIPPED = 3;
  ORDER_STATUS_DELIVERED = 4;
  ORDER_STATUS_CANCELLED = 5;
}

// Message
message OrderItem {
  string product_id = 1;         // field number (1-15 = 1 byte encoding)
  int32 quantity = 2;
  double unit_price = 3;
}

message Order {
  string id = 1;
  string user_id = 2;
  repeated OrderItem items = 3;  // repeated = list
  OrderStatus status = 4;
  google.protobuf.Timestamp created_at = 5;
  google.protobuf.StringValue coupon_code = 6;  // optional wrapper
  map<string, string> metadata = 7;             // map type

  // Oneof: only one field set at a time
  oneof payment {
    CreditCardPayment credit_card = 8;
    BankTransferPayment bank_transfer = 9;
  }
}

// Service definition
service OrderService {
  // Unary RPC
  rpc GetOrder(GetOrderRequest) returns (GetOrderResponse);
  rpc CreateOrder(CreateOrderRequest) returns (CreateOrderResponse);

  // Server streaming
  rpc StreamOrderUpdates(StreamOrderRequest) returns (stream OrderUpdate);

  // Client streaming
  rpc BatchCreateOrders(stream CreateOrderRequest) returns (BatchCreateResponse);

  // Bidirectional streaming
  rpc OrderChat(stream ChatMessage) returns (stream ChatMessage);
}

message GetOrderRequest { string order_id = 1; }
message GetOrderResponse { Order order = 1; }
message CreateOrderRequest { string user_id = 1; repeated OrderItem items = 2; }
message CreateOrderResponse { Order order = 1; }
message StreamOrderRequest { string order_id = 1; }
message OrderUpdate { string order_id = 1; OrderStatus status = 2; }
message BatchCreateResponse { repeated Order orders = 1; int32 success_count = 2; }
message ChatMessage { string sender = 1; string content = 2; }
```

### How – Code Generation

```xml
<!-- pom.xml -->
<dependencies>
    <dependency>
        <groupId>net.devh</groupId>
        <artifactId>grpc-spring-boot-starter</artifactId>
        <version>3.1.0.RELEASE</version>
    </dependency>
    <dependency>
        <groupId>io.grpc</groupId>
        <artifactId>grpc-protobuf</artifactId>
        <version>1.59.0</version>
    </dependency>
    <dependency>
        <groupId>io.grpc</groupId>
        <artifactId>grpc-stub</artifactId>
        <version>1.59.0</version>
    </dependency>
    <dependency>
        <groupId>com.google.protobuf</groupId>
        <artifactId>protobuf-java</artifactId>
        <version>3.25.1</version>
    </dependency>
</dependencies>

<build>
    <extensions>
        <extension>
            <groupId>kr.motd.maven</groupId>
            <artifactId>os-maven-plugin</artifactId>
        </extension>
    </extensions>
    <plugins>
        <plugin>
            <groupId>org.xolstice.maven.plugins</groupId>
            <artifactId>protobuf-maven-plugin</artifactId>
            <configuration>
                <protocArtifact>com.google.protobuf:protoc:3.25.1:exe:${os.detected.classifier}</protocArtifact>
                <pluginId>grpc-java</pluginId>
                <pluginArtifact>io.grpc:protoc-gen-grpc-java:1.59.0:exe:${os.detected.classifier}</pluginArtifact>
            </configuration>
            <executions>
                <execution>
                    <goals>
                        <goal>compile</goal>
                        <goal>compile-custom</goal>
                    </goals>
                </execution>
            </executions>
        </plugin>
    </plugins>
</build>
```

---

## 2. gRPC Server Implementation

### How – Unary & Streaming Server

```java
@GrpcService
public class OrderGrpcService extends OrderServiceGrpc.OrderServiceImplBase {

    // Unary RPC
    @Override
    public void getOrder(GetOrderRequest request,
                         StreamObserver<GetOrderResponse> responseObserver) {
        try {
            Order order = orderService.findById(request.getOrderId());
            if (order == null) {
                responseObserver.onError(
                    Status.NOT_FOUND
                        .withDescription("Order not found: " + request.getOrderId())
                        .asRuntimeException()
                );
                return;
            }
            GetOrderResponse response = GetOrderResponse.newBuilder()
                .setOrder(toProto(order))
                .build();
            responseObserver.onNext(response);
            responseObserver.onCompleted();
        } catch (Exception e) {
            responseObserver.onError(
                Status.INTERNAL.withDescription(e.getMessage()).withCause(e).asRuntimeException()
            );
        }
    }

    // Server streaming: push updates to client
    @Override
    public void streamOrderUpdates(StreamOrderRequest request,
                                   StreamObserver<OrderUpdate> responseObserver) {
        String orderId = request.getOrderId();
        // Subscribe to order status changes
        orderEventBus.subscribe(orderId, event -> {
            if (!responseObserver.isReady()) return;  // backpressure check
            try {
                responseObserver.onNext(OrderUpdate.newBuilder()
                    .setOrderId(orderId)
                    .setStatus(toProtoStatus(event.getStatus()))
                    .build());
                if (event.isTerminal()) {
                    responseObserver.onCompleted();
                }
            } catch (StatusRuntimeException e) {
                // Client disconnected
                orderEventBus.unsubscribe(orderId);
            }
        });
    }

    // Client streaming: receive batch, return single response
    @Override
    public StreamObserver<CreateOrderRequest> batchCreateOrders(
            StreamObserver<BatchCreateResponse> responseObserver) {
        List<Order> createdOrders = new ArrayList<>();

        return new StreamObserver<>() {
            @Override
            public void onNext(CreateOrderRequest request) {
                Order order = orderService.createOrder(request);
                createdOrders.add(order);
            }

            @Override
            public void onError(Throwable t) {
                log.error("Client stream error", t);
                createdOrders.clear();
            }

            @Override
            public void onCompleted() {
                responseObserver.onNext(BatchCreateResponse.newBuilder()
                    .addAllOrders(createdOrders.stream().map(OrderGrpcService::toProto).toList())
                    .setSuccessCount(createdOrders.size())
                    .build());
                responseObserver.onCompleted();
            }
        };
    }
}
```

### How – Spring Boot gRPC Config

```yaml
# application.yaml
grpc:
  server:
    port: 9090
    security:
      enabled: true
      certificateChain: classpath:certs/server.crt
      privateKey: classpath:certs/server.key
  client:
    order-service:
      address: discovery:///order-service  # hoặc static: static://host:9090
      negotiation-type: TLS
```

---

## 3. gRPC Client

### How – Stub Types

```java
// 3 loại stub:
// BlockingStub   – synchronous (đơn giản nhất, block thread)
// FutureStub     – returns ListenableFuture (non-blocking)
// AsyncStub (Stub) – full async với StreamObserver

@GrpcClient("order-service")
private OrderServiceGrpc.OrderServiceBlockingStub blockingStub;

@GrpcClient("order-service")
private OrderServiceGrpc.OrderServiceFutureStub futureStub;

@GrpcClient("order-service")
private OrderServiceGrpc.OrderServiceStub asyncStub;

// Blocking (đơn giản)
public Order getOrder(String orderId) {
    GetOrderRequest request = GetOrderRequest.newBuilder()
        .setOrderId(orderId)
        .build();
    GetOrderResponse response = blockingStub
        .withDeadlineAfter(5, TimeUnit.SECONDS)  // timeout!
        .getOrder(request);
    return fromProto(response.getOrder());
}

// Async với CompletableFuture
public CompletableFuture<Order> getOrderAsync(String orderId) {
    GetOrderRequest req = GetOrderRequest.newBuilder().setOrderId(orderId).build();
    ListenableFuture<GetOrderResponse> future = futureStub
        .withDeadlineAfter(5, TimeUnit.SECONDS)
        .getOrder(req);
    return CompletableFutureConverter.toCompletableFuture(future)
        .thenApply(response -> fromProto(response.getOrder()));
}

// Client streaming consumer
public void consumeOrderUpdates(String orderId, Consumer<OrderStatus> onUpdate) {
    asyncStub.streamOrderUpdates(
        StreamOrderRequest.newBuilder().setOrderId(orderId).build(),
        new StreamObserver<>() {
            @Override
            public void onNext(OrderUpdate update) {
                onUpdate.accept(fromProtoStatus(update.getStatus()));
            }
            @Override
            public void onError(Throwable t) {
                log.error("Stream error for orderId={}", orderId, t);
            }
            @Override
            public void onCompleted() {
                log.info("Stream completed for orderId={}", orderId);
            }
        }
    );
}
```

---

## 4. Interceptors – Cross-cutting Concerns

### How – Server Interceptor

```java
@Component
public class AuthServerInterceptor implements ServerInterceptor {
    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call,
            Metadata headers,
            ServerCallHandler<ReqT, RespT> next) {

        // Extract JWT from metadata
        String token = headers.get(Metadata.Key.of("authorization", Metadata.ASCII_STRING_MARSHALLER));
        if (token == null || !jwtValidator.isValid(token.replace("Bearer ", ""))) {
            call.close(Status.UNAUTHENTICATED.withDescription("Invalid token"), new Metadata());
            return new ServerCall.Listener<>() {};  // no-op listener
        }

        // Store user context (accessible trong service method)
        Context context = Context.current().withValue(USER_CONTEXT_KEY, extractUser(token));
        return Contexts.interceptCall(context, call, headers, next);
    }
}

// Logging interceptor
@Component
@GrpcGlobalServerInterceptor
public class LoggingServerInterceptor implements ServerInterceptor {
    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call, Metadata headers, ServerCallHandler<ReqT, RespT> next) {
        long startTime = System.currentTimeMillis();
        String methodName = call.getMethodDescriptor().getFullMethodName();

        return new ForwardingServerCallListener.SimpleForwardingServerCallListener<>(
            next.startCall(new ForwardingServerCall.SimpleForwardingServerCall<>(call) {
                @Override
                public void close(Status status, Metadata trailers) {
                    long duration = System.currentTimeMillis() - startTime;
                    log.info("gRPC {} {} {}ms", methodName, status.getCode(), duration);
                    super.close(status, trailers);
                }
            }, headers)) {};
    }
}
```

---

## 5. Deadline, Retry & Resilience

### How – Deadline Propagation

```java
// Deadline propagates down the call chain automatically
// client sets 5s → all downstream calls must finish within remaining budget

public Order getOrderWithDetails(String orderId) {
    // Client sets 5s deadline
    // Nếu getOrder lấy 3s, chỉ còn 2s cho getProduct
    Order order = blockingStub
        .withDeadlineAfter(5, TimeUnit.SECONDS)
        .getOrder(GetOrderRequest.newBuilder().setOrderId(orderId).build())
        .getOrder();
    return order;
}
```

### How – Retry Policy (trong service config)

```java
// gRPC retry policy (server phải set retry-able status codes)
@Bean
public ManagedChannel managedChannel() {
    Map<String, Object> retryPolicy = new HashMap<>();
    retryPolicy.put("maxAttempts", 3.0);
    retryPolicy.put("initialBackoff", "0.1s");
    retryPolicy.put("maxBackoff", "1s");
    retryPolicy.put("backoffMultiplier", 2.0);
    retryPolicy.put("retryableStatusCodes", List.of("UNAVAILABLE", "RESOURCE_EXHAUSTED"));

    Map<String, Object> methodConfig = new HashMap<>();
    methodConfig.put("name", List.of(Map.of("service", "com.example.order.OrderService")));
    methodConfig.put("retryPolicy", retryPolicy);
    methodConfig.put("timeout", "5s");

    Map<String, Object> serviceConfig = new HashMap<>();
    serviceConfig.put("methodConfig", List.of(methodConfig));

    return ManagedChannelBuilder.forAddress("order-service", 9090)
        .defaultServiceConfig(serviceConfig)
        .enableRetry()
        .build();
}
```

### How – gRPC Status Codes

```java
// Common Status codes mapping
// OK (0)               – success
// CANCELLED (1)        – cancelled by client
// UNKNOWN (2)          – unknown server error
// INVALID_ARGUMENT (3) – bad request (không retry)
// NOT_FOUND (5)        – resource not found (không retry)
// ALREADY_EXISTS (6)   – duplicate
// PERMISSION_DENIED (7) – authorization failure
// RESOURCE_EXHAUSTED (8) – quota/rate limit (có thể retry với backoff)
// UNAVAILABLE (14)     – service down (retry)
// DEADLINE_EXCEEDED (4) – timeout (có thể retry)

// Map HTTP → gRPC status
// 400 → INVALID_ARGUMENT
// 401 → UNAUTHENTICATED
// 403 → PERMISSION_DENIED
// 404 → NOT_FOUND
// 429 → RESOURCE_EXHAUSTED
// 500 → INTERNAL
// 503 → UNAVAILABLE
```

---

## 6. Compare & Trade-offs

### Compare – gRPC vs REST vs GraphQL

| | gRPC | REST | GraphQL |
|--|------|------|---------|
| Protocol | HTTP/2 + binary | HTTP/1.1 or 2 + JSON | HTTP + JSON |
| Schema | Protobuf (strict) | OpenAPI (optional) | SDL (strict) |
| Performance | Rất cao (binary, multiplexing) | Tốt | Tốt |
| Streaming | Tất cả 4 types | SSE/WebSocket (limited) | Subscriptions |
| Browser support | Cần gRPC-Web proxy | Native | Native |
| Tooling | Good (protoc) | Excellent | Good |
| Khi dùng | Microservice internal, high-throughput | Public API, CRUD | Flexible client queries |

### Trade-offs
- **Binary format**: performance tốt nhưng không debug được bằng curl/Postman trực tiếp; cần grpcurl/BloomRPC
- **Schema evolution**: backward compatible (add fields OK; remove/rename = breaking); cần versioning strategy
- **Streaming**: powerful nhưng complex error handling, load balancing khó hơn (cần L7 proxy)
- **gRPC-Web**: để browser gọi gRPC cần proxy (Envoy, grpc-gateway); thêm complexity

---

### Ghi chú – Chủ đề tiếp theo
> **19.5 GraalVM Native Image**: AOT compilation, reflection config, native hints, build process, Spring Native
