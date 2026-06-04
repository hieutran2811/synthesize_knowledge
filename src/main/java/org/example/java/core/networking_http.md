# Networking & HTTP Client (Deep Dive)

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Real-world – Ghi chú

---

## What – Java Networking là gì?

Java cung cấp nhiều tầng để giao tiếp mạng:
- **`java.net` (Socket/ServerSocket)**: TCP/UDP tầng thấp, blocking.
- **`java.nio` (Channel/Selector)**: non-blocking I/O, scalable (xem [[core/io_nio.md]]).
- **`java.net.http.HttpClient` (Java 11+, JEP 321)**: HTTP client hiện đại, hỗ trợ HTTP/2, WebSocket, async — thay thế `HttpURLConnection` cũ kỹ.
- **Client tầng cao** (Spring): RestTemplate, WebClient, RestClient, OpenFeign.

---

## How – TCP Socket cơ bản

### Mô hình client-server với blocking socket
```java
// SERVER
try (ServerSocket server = new ServerSocket(8080)) {
    while (true) {
        Socket client = server.accept();          // BLOCK tới khi có kết nối
        // mỗi connection 1 thread (thread-per-connection)
        new Thread(() -> handle(client)).start();
    }
}
void handle(Socket s) throws IOException {
    try (var in = new BufferedReader(new InputStreamReader(s.getInputStream()));
         var out = new PrintWriter(s.getOutputStream(), true)) {
        String line = in.readLine();
        out.println("Echo: " + line);
    }
}

// CLIENT
try (Socket socket = new Socket("localhost", 8080)) {
    socket.getOutputStream().write("hello\n".getBytes());
}
```

### Thread-per-connection vs NIO vs Virtual Threads
- **Blocking + thread-per-connection**: đơn giản nhưng tốn ~1MB/thread, không scale tới hàng vạn kết nối (C10k problem).
- **NIO Selector**: 1 thread quản nhiều connection (non-blocking), scale tốt nhưng code phức tạp. Xem [[core/io_nio.md]].
- **Virtual Threads (Java 21)**: viết code blocking đơn giản nhưng scale như NIO — đây là tương lai cho server I/O-bound. Xem [[modern/virtual_threads.md]].

### UDP (DatagramSocket) – không kết nối, không đảm bảo
```java
try (DatagramSocket socket = new DatagramSocket()) {
    byte[] buf = "ping".getBytes();
    socket.send(new DatagramPacket(buf, buf.length, InetAddress.getByName("host"), 9999));
}
```

---

## How – `java.net.http.HttpClient` (Java 11+)

API hiện đại, immutable, builder-based, reuse được (giữ connection pool).

### Tạo client (reuse 1 instance!)
```java
HttpClient client = HttpClient.newBuilder()
    .version(HttpClient.Version.HTTP_2)               // tự fallback HTTP/1.1
    .connectTimeout(Duration.ofSeconds(5))
    .followRedirects(HttpClient.Redirect.NORMAL)
    .executor(Executors.newVirtualThreadPerTaskExecutor()) // Java 21: virtual threads
    .build();
```

### Request đồng bộ (synchronous)
```java
HttpRequest request = HttpRequest.newBuilder()
    .uri(URI.create("https://api.example.com/users"))
    .timeout(Duration.ofSeconds(10))
    .header("Authorization", "Bearer " + token)
    .header("Content-Type", "application/json")
    .POST(HttpRequest.BodyPublishers.ofString("{\"name\":\"An\"}"))
    .build();

HttpResponse<String> resp = client.send(request, HttpResponse.BodyHandlers.ofString());
System.out.println(resp.statusCode());   // 200
System.out.println(resp.body());
```

### Request bất đồng bộ (asynchronous) – CompletableFuture
```java
client.sendAsync(request, HttpResponse.BodyHandlers.ofString())
    .thenApply(HttpResponse::body)
    .thenAccept(System.out::println)
    .exceptionally(ex -> { log.error("fail", ex); return null; });
```
> Liên hệ `CompletableFuture` ở [[core/concurrency.md]] và [[core/concurrency_advanced.md]].

### BodyPublishers (gửi) & BodyHandlers (nhận)
| BodyPublishers (request body) | BodyHandlers (response body) |
|-------------------------------|------------------------------|
| `ofString(s)` | `ofString()` |
| `ofByteArray(b)` | `ofByteArray()` |
| `ofFile(path)` | `ofFile(path)` (tải file) |
| `ofInputStream(...)` | `ofInputStream()` (stream lớn) |
| `noBody()` | `ofLines()` (Stream<String>) |

### WebSocket (Java 11+)
```java
WebSocket ws = client.newWebSocketBuilder()
    .buildAsync(URI.create("wss://echo.example.com"), new WebSocket.Listener() {
        @Override public CompletionStage<?> onText(WebSocket ws, CharSequence data, boolean last) {
            System.out.println("Received: " + data);
            return null;
        }
    }).join();
ws.sendText("hello", true);
```

---

## How – `HttpURLConnection` (legacy, nên tránh)

```java
// ❌ API cũ kỹ, khó dùng, không HTTP/2, blocking, dễ leak connection
HttpURLConnection conn = (HttpURLConnection) new URL("https://...").openConnection();
conn.setRequestMethod("GET");
```
> Chỉ gặp trong code cũ hoặc môi trường < Java 11. Code mới → dùng `HttpClient`.

---

## Compare – Các HTTP client tầng cao (Java/Spring)

| Client | Kiểu | Trạng thái | HTTP/2 | Khi dùng |
|--------|------|-----------|--------|----------|
| **`java.net.http.HttpClient`** | sync + async | JDK 11+ chuẩn | Có | Không phụ thuộc Spring; lib/CLI |
| **RestTemplate** | sync, blocking | **Maintenance** (không thêm tính năng) | Hạn chế | Code Spring cũ; tránh cho dự án mới |
| **WebClient** | reactive, non-blocking | Khuyến nghị (reactive) | Có | WebFlux, gọi song song nhiều API, streaming |
| **RestClient** (Spring 6.1+) | sync, fluent | **Khuyến nghị (sync)** | Có (qua HttpClient) | Thay RestTemplate trong app blocking |
| **OpenFeign** | declarative (interface) | Spring Cloud | Có | Microservices, nhiều service call |

### RestClient (Spring 6.1 / Boot 3.2+) – thay thế RestTemplate hiện đại
```java
RestClient restClient = RestClient.create();
User user = restClient.get()
    .uri("https://api.example.com/users/{id}", 42)
    .header("Authorization", "Bearer " + token)
    .retrieve()
    .body(User.class);
```

### WebClient (reactive, non-blocking)
```java
WebClient webClient = WebClient.builder().baseUrl("https://api.example.com").build();
Mono<User> userMono = webClient.get().uri("/users/{id}", 42)
    .retrieve().bodyToMono(User.class);
// Gọi song song nhiều API rồi gộp:
Mono.zip(call1, call2, call3).map(tuple -> combine(...));
```
> Liên hệ [[core/reactive.md]] (Mono/Flux, backpressure, Schedulers).

### OpenFeign (declarative – chỉ khai interface)
```java
@FeignClient(name = "user-service")
public interface UserClient {
    @GetMapping("/users/{id}") User getUser(@PathVariable Long id);
}
// Inject và gọi như method bình thường → Feign tự tạo HTTP call
```
> Liên hệ [[spring/spring_cloud.md]] (Feign + LoadBalancer + Resilience4j).

---

## When – Chọn client nào?

| Tình huống | Lựa chọn |
|-----------|----------|
| Library/CLI, không Spring | `java.net.http.HttpClient` |
| App Spring blocking (MVC) mới | **RestClient** |
| App Spring blocking cũ | RestTemplate (đang có) → di dời dần sang RestClient |
| WebFlux / cần non-blocking / gọi song song nhiều | **WebClient** |
| Microservices nhiều service-to-service call | **OpenFeign** |
| Cần WebSocket | `HttpClient.newWebSocketBuilder` hoặc WebClient |

---

## How – Production concerns (BẮT BUỘC nhớ)

### Timeout – luôn đặt cả connect & read
```java
HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build(); // connect timeout
HttpRequest.newBuilder().timeout(Duration.ofSeconds(10)).build();      // request (read) timeout
```
> Không đặt timeout = thread treo vĩnh viễn khi server không phản hồi → cạn thread pool → sập cả app. **Lỗi production kinh điển.**

### Connection pooling & reuse
- `HttpClient` quản connection pool nội bộ — **tạo 1 instance, reuse**. Tạo mới mỗi request = không tái dùng connection, tốn handshake TLS.
- RestTemplate/RestClient/WebClient nên cấu hình connection pool qua underlying (Apache HttpClient / Reactor Netty).

### Resilience: retry, circuit breaker, timeout
Bọc lời gọi mạng bằng Resilience4j (retry với backoff, circuit breaker khi downstream chết, bulkhead giới hạn concurrency). Xem [[spring/spring_cloud.md]] và pattern Circuit Breaker ở [[patterns/patterns_enterprise.md]].

### TLS/HTTPS
HttpClient hỗ trợ `SSLContext` tùy chỉnh (mTLS, custom truststore). Liên hệ [[security/crypto/pki_tls.md]] nếu có.

---

## Trade-offs

- (+) `HttpClient` JDK: không phụ thuộc ngoài, HTTP/2, async, WebSocket, kết hợp virtual threads tốt.
- (−) `HttpClient` thiếu tiện ích tầng cao (interceptor, retry, serialization tự động) → phải tự code hoặc dùng client Spring.
- (+) WebClient mạnh cho non-blocking/song song nhưng học reactive khó (xem [[core/reactive.md]]).
- (−) RestTemplate đơn giản nhưng blocking & maintenance-mode.
- Với **Virtual Threads (Java 21)**, ranh giới "blocking vs non-blocking để scale" mờ đi → code blocking đơn giản (RestClient/HttpClient sync) chạy trên virtual thread scale tốt mà dễ đọc hơn reactive.

---

## Real-world Usage

```java
// Bean HttpClient dùng chung, virtual-thread executor, timeout đầy đủ
@Bean
HttpClient httpClient() {
    return HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(5))
        .executor(Executors.newVirtualThreadPerTaskExecutor())
        .build();
}

// Gọi API ngoài có timeout + xử lý status
HttpResponse<String> r = httpClient.send(req, BodyHandlers.ofString());
if (r.statusCode() >= 400) throw new ExternalApiException(r.statusCode(), r.body());
```
- Microservice gọi nhau: OpenFeign + LoadBalancer + Resilience4j (retry/circuit breaker). Xem [[spring/spring_cloud.md]].
- Gọi nhiều API độc lập rồi gộp: WebClient + `Mono.zip`, hoặc virtual threads + structured concurrency (`StructuredTaskScope`) — xem [[modern/virtual_threads.md]].

---

## Ghi chú – Chủ đề tiếp theo

> Liên quan: [[core/io_nio.md]] (NIO Selector, non-blocking), [[modern/virtual_threads.md]] (blocking I/O scalable), [[core/reactive.md]] (WebClient/Mono/Flux), [[core/concurrency.md]] (CompletableFuture cho sendAsync), [[spring/spring_cloud.md]] (Feign, LoadBalancer, Resilience4j).
>
> Keyword cho topic kế: **Spring Cloud / Microservices** – Service Discovery (Eureka), Spring Cloud Gateway, Config Server, OpenFeign, Resilience4j (CircuitBreaker/Retry/RateLimiter/Bulkhead).

*Cập nhật lần cuối: 2026-06-04*
