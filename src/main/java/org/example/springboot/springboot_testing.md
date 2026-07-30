# Spring Boot Testing – Chiến lược kiểm thử từ Unit đến Production

> Phương pháp: What – How – Why – Components – When – Compare – Trade-offs – Production – Ghi chú
>
> Tra cứu nhanh thuật ngữ tại [Spring Boot Glossary](glossary.md).

---

## What – Spring Boot Testing là gì?

**Testing strategy** *(chiến lược kiểm thử)* là cách phân bổ nhiều loại test để phát hiện lỗi ở đúng ranh giới với chi phí hợp lý. Spring Boot cung cấp test slices, `MockMvc`, `WebTestClient`, Testcontainers và tích hợp Spring Security Test; chúng bổ sung cho JUnit/Mockito chứ không thay thế tư duy chọn phạm vi test.

Một test tốt phải trả lời rõ:

- behavior nào đang được bảo vệ;
- boundary nào là thật, boundary nào được thay bằng mock/stub;
- loại lỗi nào test có thể và không thể phát hiện;
- state được cô lập và dọn dẹp bằng cách nào;
- tốc độ/độ ổn định có phù hợp với tầng CI đang chạy hay không.

> 💡 **Giải thích dễ hiểu:**
> Kiểm thử giống kiểm tra một chiếc xe: unit test kiểm từng chi tiết trên bàn, slice test kiểm riêng hệ thống phanh, integration test cho các cụm thật chạy cùng nhau, còn end-to-end test lái cả xe trên đường. Không một bài kiểm tra nào thay thế được tất cả bài còn lại.

---

## Why – Vì sao không chỉ dùng `@SpringBootTest` cho mọi thứ?

`@SpringBootTest` tăng **fidelity** *(mức độ giống môi trường chạy thật)* nhưng khởi tạo nhiều bean, kết nối và hạ tầng hơn. Nếu mọi test đều load toàn bộ context, suite sẽ chậm, khó xác định lỗi thuộc layer nào và dễ tạo nhiều biến thể context làm mất cache.

Ngược lại, mock mọi dependency khiến test nhanh nhưng có thể bỏ sót mapping, validation, serialization, SQL dialect, security filter hoặc protocol thật. Mục tiêu không phải “mock nhiều nhất” hay “dùng container nhiều nhất”, mà là chọn test nhỏ nhất vẫn chứng minh được rủi ro cần bảo vệ.

---

## Components – Các tầng kiểm thử

```text
          E2E / smoke                 ít, chậm, kiểm hệ thống đã deploy
       Contract / component           kiểm boundary HTTP/message
    Integration + real services       Spring context + container
          Test slices                 một phần auto-configuration
             Unit                     nhiều, nhanh, không Spring
```

| Tầng | Boundary thật | Phát hiện tốt |
|---|---|---|
| Unit test | Một class/hàm | Business branch, algorithm, mapping thuần |
| Slice test | Một phần Spring | MVC binding, JSON, repository query, HTTP client mapping |
| Integration test | Nhiều layer + hạ tầng thật | Wiring, transaction, migration, protocol/driver |
| Contract test | Consumer/provider contract | Request/response/event không tương thích |
| E2E/smoke | Hệ thống đã chạy | Routing, deployment, identity, critical journey |

> 💡 **Giải thích dễ hiểu:**
> Các tầng test giống lưới có mắt từ nhỏ đến lớn. Lưới nhỏ bắt lỗi logic rẻ và nhanh; lưới lớn bắt lỗi nối hệ thống nhưng tốn thời gian. Chỉ dùng một cỡ lưới sẽ để lọt một nhóm lỗi hoặc làm chi phí quá cao.

---

## How – Unit Test không khởi động Spring

**Unit test** *(kiểm thử một đơn vị logic cô lập)* nên gọi object thật trực tiếp, dùng mock cho collaborator có side effect hoặc boundary chậm. Không cần `@SpringBootTest`, `@ExtendWith(SpringExtension.class)` hay Spring context nếu class chỉ có constructor dependency.

```java
@ExtendWith(MockitoExtension.class)
class PriceCalculatorTest {

    @Mock
    private DiscountPolicy discountPolicy;

    @InjectMocks
    private PriceCalculator calculator;

    @Test
    void calculate_vipCustomer_appliesDiscount() {
        given(discountPolicy.percentageFor("VIP")).willReturn(new BigDecimal("0.10"));

        Money result = calculator.calculate(
            new BigDecimal("100.00"), "VIP");

        assertThat(result.amount()).isEqualByComparingTo("90.00");
    }
}
```

Ưu tiên assert output/state/observable interaction quan trọng. Verify mọi lời gọi nội bộ làm test gắn chặt implementation và vỡ khi refactor dù behavior không đổi. Với value object, mapper hoặc domain rule thuần, dùng object thật thường rõ hơn mock.

---

## How – Test Slices

**Test slice** *(Spring context thu gọn theo một capability)* chỉ bật nhóm auto-configuration và component cần cho một layer. Slice nhanh hơn full context nhưng vẫn kiểm tra framework behavior như binding, converter, repository proxy hoặc JSON module.

| Slice | Nạp chính | Không tự nạp |
|---|---|---|
| `@WebMvcTest` | MVC infrastructure, controller, advice, filter phù hợp | Service/repository thông thường |
| `@WebFluxTest` | WebFlux controller/codec | Reactive service/repository thông thường |
| `@DataJpaTest` | Entity, JPA repository, Hibernate, test transaction | Service/web layer |
| `@DataRedisTest` | Redis data infrastructure/repository | Component tùy chỉnh ngoài slice |
| `@JsonTest` | Jackson/Gson/Jsonb support | Web/service/data layer |
| `@RestClientTest` | JSON + `RestClient.Builder`/`RestTemplateBuilder` + mock server | Full application |
| `@JdbcTest`, `@DataR2dbcTest`, `@JooqTest` | Data technology tương ứng | Layer khác |

Slice không scan mọi `@Configuration` hoặc `@Component`. Nếu subject cần một converter/config/component cụ thể, thêm có chủ đích bằng `@Import` hoặc `@EnableConfigurationProperties`; đừng đổi ngay thành `@SpringBootTest` chỉ vì thiếu một bean.

### Boot 3.5 và Boot 4.1

- Boot 3.5 vẫn có các annotation slice quen thuộc, nhưng `@MockBean`/`@SpyBean` đã deprecated từ 3.4 để loại bỏ ở 4.0.
- Dùng `@MockitoBean`/`@MockitoSpyBean` của Spring Framework cho code mới; các ví dụ bên dưới theo API này.
- Boot 4.x tách thêm các focused `*-test` module theo capability. `spring-boot-starter-test` vẫn kéo general-purpose test support và các module phù hợp; dependency cụ thể phải theo BOM của dòng Boot đang chạy.
- Không copy package/class từ tài liệu Boot 4.1 vào project 3.5 mà chưa kiểm migration guide; semantics cần học là slice boundary, không phải ghi nhớ một import duy nhất.

> 💡 **Giải thích dễ hiểu:**
> Slice test giống bật riêng khu bếp để kiểm món ăn thay vì mở cả nhà hàng. Nếu cần thêm một chiếc máy xay, hãy đưa đúng máy vào khu bếp; mở luôn quầy lễ tân, kho và bãi xe chỉ vì thiếu máy xay sẽ làm bài kiểm tra nặng không cần thiết.

### `@WebMvcTest` – MVC boundary

`@WebMvcTest` dùng `DispatcherServlet` và mock Servlet request/response, nên kiểm được route, binding, validation, Jackson, `@ControllerAdvice` và security filter được cấu hình. Đây là slice/integration test cho web boundary, không phải unit test controller thuần.

```java
@WebMvcTest(OrderController.class)
@Import({ApiExceptionHandler.class, SecurityConfig.class})
class OrderControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockitoBean
    private OrderApplicationService service;

    @MockitoBean
    private JwtDecoder jwtDecoder;

    @Test
    void create_validRequest_returns201AndLocation() throws Exception {
        CreateOrderRequest request = validRequest();
        OrderResponse response = new OrderResponse(42L, "PENDING");
        given(service.create(any())).willReturn(response);

        mockMvc.perform(post("/api/orders")
                .with(jwt().authorities(new SimpleGrantedAuthority("SCOPE_order.write")))
                .with(csrf())
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsBytes(request)))
            .andExpect(status().isCreated())
            .andExpect(header().string(HttpHeaders.LOCATION, "/api/orders/42"))
            .andExpect(jsonPath("$.id").value(42))
            .andExpect(jsonPath("$.status").value("PENDING"));
    }

    @Test
    void create_invalidQuantity_returnsProblemDetail() throws Exception {
        CreateOrderRequest request = requestWithQuantity(0);

        mockMvc.perform(post("/api/orders")
                .with(jwt())
                .with(csrf())
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsBytes(request)))
            .andExpect(status().isBadRequest())
            .andExpect(content().contentTypeCompatibleWith(
                MediaType.APPLICATION_PROBLEM_JSON))
            .andExpect(jsonPath("$.type").exists())
            .andExpect(jsonPath("$.status").value(400))
            .andExpect(jsonPath("$.errors").isArray());

        then(service).shouldHaveNoInteractions();
    }
}
```

Security auto-configuration có thể được đưa vào slice khi Spring Security ở classpath, nhưng custom `SecurityFilterChain`, converter hoặc advice không phải lúc nào cũng được scan theo cách bạn giả định. Import đúng production config cần kiểm tra thay vì vô hiệu hóa filter để test “dễ pass”.

### `@DataJpaTest` – repository với database thật

Mặc định `@DataJpaTest` scan entity/repository, dùng embedded database nếu có và rollback test transaction. H2 không tái hiện đầy đủ PostgreSQL/MySQL về type, index, locking, JSON, SQL syntax; query phụ thuộc dialect nên chạy với container đúng engine.

```java
@DataJpaTest
@Testcontainers
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class OrderRepositoryTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:16.6-alpine");

    @Autowired
    private OrderRepository repository;

    @Autowired
    private TestEntityManager entityManager;

    @Test
    void findPendingByCustomer_returnsOnlyMatchingRows() {
        entityManager.persist(order(7L, OrderStatus.PENDING));
        entityManager.persist(order(7L, OrderStatus.SHIPPED));
        entityManager.persist(order(8L, OrderStatus.PENDING));
        entityManager.flush();
        entityManager.clear(); // buộc query database, không đọc L1 cache

        List<Order> result = repository.findByCustomerIdAndStatus(
            7L, OrderStatus.PENDING);

        assertThat(result).singleElement()
            .extracting(Order::getCustomerId)
            .isEqualTo(7L);
    }
}
```

`flush()` làm lỗi constraint/SQL xuất hiện trong test; `clear()` tránh persistence context che query hoặc lazy-loading issue. Ngoài happy path, test unique constraint, optimistic locking, custom query, pagination và migration tương thích engine thật.

### `@DataRedisTest` và component ngoài slice

```java
@DataRedisTest
@Import(SessionStore.class)
@Testcontainers
class SessionStoreTest {

    @Container
    @ServiceConnection(name = "redis")
    static GenericContainer<?> redis =
        new GenericContainer<>("redis:7.4-alpine").withExposedPorts(6379);

    @Autowired
    private SessionStore sessionStore;

    @Test
    void save_setsValueAndExpiry() {
        sessionStore.save("s-1", "user-42", Duration.ofMinutes(30));

        assertThat(sessionStore.find("s-1")).contains("user-42");
        assertThat(sessionStore.ttl("s-1")).isPositive();
    }
}
```

`@Import(SessionStore.class)` là cần thiết nếu `SessionStore` là component tùy chỉnh không thuộc whitelist của slice. Với `GenericContainer`, `name="redis"` giúp Boot chọn đúng `ConnectionDetails` factory.

### `@JsonTest` – serialization contract

```java
@JsonTest
class OrderResponseJsonTest {

    @Autowired
    private JacksonTester<OrderResponse> json;

    @Test
    void serialize_usesPublicContractAndHidesInternalField() throws Exception {
        OrderResponse response = responseWithSecret();

        JsonContent<OrderResponse> content = json.write(response);

        assertThat(content).hasJsonPathNumberValue("$.id", 42);
        assertThat(content).hasJsonPathStringValue("$.createdAt",
            "2026-07-27T09:00:00Z");
        assertThat(content).doesNotHaveJsonPath("$.internalCost");
    }
}
```

Test JSON nên bảo vệ field name, enum/time format, null policy và dữ liệu nhạy cảm; không cần assert whitespace hoặc toàn bộ JSON nếu điều đó làm test dễ vỡ vô ích.

### `@RestClientTest` – outbound client mapping

```java
@RestClientTest(WeatherClient.class)
class WeatherClientTest {

    @Autowired
    private WeatherClient client;

    @Autowired
    private MockRestServiceServer server;

    @Test
    void current_success_mapsResponse() {
        server.expect(requestTo("https://weather.example/current?city=Hanoi"))
            .andExpect(method(HttpMethod.GET))
            .andRespond(withSuccess(
                """{"city":"Hanoi","temperature":30}""",
                MediaType.APPLICATION_JSON));

        Weather weather = client.current("Hanoi");

        assertThat(weather.temperature()).isEqualTo(30);
        server.verify();
    }
}
```

Test này chứng minh request construction và response/error mapping của `RestClient`; nó không kiểm DNS, TLS, connection pool hay provider thật. Boot 4.1 có focused support cho WebClient test; với Boot 3.5, chọn công cụ được dòng đó hỗ trợ hoặc dùng mock HTTP server/WireMock.

---

## How – `MockMvc`, `WebTestClient` và Live Server

### Ba mức setup MVC

| Setup | Có gì thật | Khi dùng |
|---|---|---|
| Gọi controller method trực tiếp | Chỉ object Java | Unit test branch trong controller rất mỏng |
| `standaloneSetup` | `MockMvc` + controller/advice tự cung cấp | Test cấu hình nhỏ, chấp nhận không giống full MVC config |
| `@WebMvcTest` | MVC slice của Spring Boot | Test HTTP boundary một controller/nhóm controller |
| `@SpringBootTest(MOCK)` + `@AutoConfigureMockMvc` | Full application context, không mở port | Wiring nhiều layer nhưng không cần network thật |
| `@SpringBootTest(RANDOM_PORT)` | Server thật trên port ngẫu nhiên | Filter/container/network behavior và E2E trong process |

`MockMvc` chạy đầy đủ Spring MVC request handling bằng mock Servlet API nhưng **không mở server socket**. Vì vậy nó kiểm MVC tốt, nhưng không chứng minh TLS, HTTP/2, reverse proxy hoặc container-specific networking.

```java
mockMvc.perform(get("/api/orders/{id}", 42)
        .with(jwt().authorities(new SimpleGrantedAuthority("SCOPE_order.read")))
        .accept(MediaType.APPLICATION_JSON))
    .andExpect(status().isOk())
    .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
    .andExpect(header().exists("X-Trace-Id"))
    .andExpect(jsonPath("$.id").value(42))
    .andExpect(jsonPath("$.internalCost").doesNotExist());
```

`andDo(print())` hữu ích khi debug, nhưng không nên in mọi response/token/PII trong CI log. Có thể chỉ print khi test fail hoặc dùng output có redaction.

### Async MVC

Controller trả `Callable`, `DeferredResult` hoặc reactive type trong MVC có thể cần assert hai pha:

```java
MvcResult result = mockMvc.perform(get("/api/reports/42"))
    .andExpect(request().asyncStarted())
    .andReturn();

mockMvc.perform(asyncDispatch(result))
    .andExpect(status().isOk())
    .andExpect(jsonPath("$.id").value(42));
```

### WebFlux với `WebTestClient`

```java
@WebFluxTest(UserController.class)
class UserControllerWebFluxTest {

    @Autowired
    private WebTestClient webTestClient;

    @MockitoBean
    private ReactiveUserService service;

    @Test
    void get_existingUser_returnsBody() {
        given(service.findById(7L)).willReturn(Mono.just(new User(7L, "Alice")));

        webTestClient.get().uri("/users/7")
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.id").isEqualTo(7)
            .jsonPath("$.name").isEqualTo("Alice");
    }
}
```

`WebTestClient` có thể bind vào WebFlux application context hoặc gọi live server. Với service-level Reactor pipeline, dùng `StepVerifier` để kiểm value, completion, error và virtual time. Không gọi `.block()` chỉ để biến mọi reactive test thành imperative nếu mục tiêu là kiểm non-blocking behavior.

> 💡 **Giải thích dễ hiểu:**
> `MockMvc` giống diễn tập đầy đủ ở quầy lễ tân nhưng chưa mở cửa ra đường; live-server test cho khách thật đi qua cổng mạng. Diễn tập trong nhà nhanh và ổn định, còn đi qua cổng thật mới phát hiện cấu hình cổng, nhưng tốn chi phí hơn.

---

## How – Testcontainers và `@ServiceConnection`

**Testcontainers** *(chạy dependency thật trong container tạm cho test)* tăng parity với production database, Redis, Kafka hoặc broker khác. Spring Boot 3.1+ hỗ trợ `@ServiceConnection` để tạo `ConnectionDetails` tự động; connection detail có ưu tiên hơn property kết nối thông thường.

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-testcontainers</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>postgresql</artifactId>
    <scope>test</scope>
</dependency>
```

```java
@SpringBootTest
@Testcontainers
class OrderIntegrationTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:16.6-alpine");

    @Test
    void placeOrder_commitsOrderAndOutboxEvent() {
        // test application service với database thật
    }
}
```

`@ServiceConnection` giảm boilerplate và chọn config theo container type/image. Nếu technology chưa có factory, dùng fallback:

```java
@DynamicPropertySource
static void registerProperties(DynamicPropertyRegistry registry) {
    registry.add("thirdparty.base-url", thirdParty::getEndpoint);
}
```

Không khai báo đồng thời `@ServiceConnection` và các property trùng nhau nếu không có lý do; precedence khác nhau làm test khó đọc.

### Container dùng chung và lifecycle

Static `@Container` thường dùng chung cho các method trong **một test class**. Chia sẻ container qua nhiều class cần gắn lifecycle với context/suite cẩn thận; base class + static container có thể bị stop trong khi Spring cached context vẫn giữ connection cũ.

Cách Spring-managed theo context:

```java
@TestConfiguration(proxyBeanMethods = false)
class ContainersConfiguration {

    @Bean
    @ServiceConnection
    PostgreSQLContainer<?> postgresContainer() {
        return new PostgreSQLContainer<>("postgres:16.6-alpine");
    }
}

@SpringBootTest
@Import(ContainersConfiguration.class)
class CheckoutIntegrationTest { }
```

Spring Boot quản lý start/stop container bean theo application context. Có thể dùng `@ImportTestcontainers` cho container declaration class. Dù chọn cách nào, pin image version/digest, không dùng `latest`, và xác định rõ state reset giữa test.

> 💡 **Giải thích dễ hiểu:**
> Testcontainers giống thuê một căn bếp thật cho buổi thử món rồi trả lại. `@ServiceConnection` tự đưa đúng địa chỉ bếp cho đầu bếp. Nếu bếp đã bị trả nhưng Spring vẫn cache địa chỉ cũ, lớp test sau sẽ chạy tới một căn bếp không còn tồn tại.

### Cleanup database

| Cách | Khi phù hợp | Cạm bẫy |
|---|---|---|
| Test transaction rollback | Slice/MOCK test cùng thread/transaction | Không đại diện commit; không rollback live server thread |
| `@Sql` setup/cleanup | Dataset SQL rõ và nhỏ | Script phải giữ đúng FK/order |
| Truncate/schema-per-test | Integration cần commit thật | Tốn setup; cần tool an toàn |
| Container-per-test/class | Isolation mạnh | Chậm hơn |
| Repository `deleteAll()` | Dataset nhỏ, đơn giản | Chậm, callback/FK/order có thể gây nhiễu |

Không bật Flyway clean hoặc lệnh phá dữ liệu bằng profile có thể trỏ nhầm môi trường. Test database phải có credential/hostname tách biệt và guardrail rõ.

---

## How – WireMock cho HTTP Boundary

**WireMock** *(HTTP stub server có thể lập trình response)* phù hợp kiểm outbound client, timeout, retry, error mapping và request shape mà không phụ thuộc provider thật. Spring Cloud Contract cung cấp `@AutoConfigureWireMock`.

```java
@SpringBootTest(
    properties = "clients.payment.base-url=http://localhost:${wiremock.server.port}")
@AutoConfigureWireMock(port = 0)
class PaymentClientTest {

    @Autowired
    private PaymentClient client;

    @Test
    void charge_success_sendsIdempotencyKeyAndMapsBody() {
        stubFor(post(urlEqualTo("/payments"))
            .withHeader("Idempotency-Key", matching(".+"))
            .withRequestBody(matchingJsonPath("$.amount", equalTo("100.00")))
            .willReturn(okJson("""
                {"paymentId":"pay-123","status":"AUTHORIZED"}
                """)));

        PaymentResult result = client.charge(request("100.00"));

        assertThat(result.paymentId()).isEqualTo("pay-123");
        verify(1, postRequestedFor(urlEqualTo("/payments")));
    }

    @Test
    void charge_slowProvider_timesOut() {
        stubFor(post(urlEqualTo("/payments"))
            .willReturn(aResponse().withFixedDelay(5_000).withStatus(200)));

        assertThatThrownBy(() -> client.charge(request("100.00")))
            .isInstanceOf(PaymentTimeoutException.class);
    }
}
```

`port=0` tránh xung đột port và công bố `wiremock.server.port`. WireMock context có thể được cache; mặc định listener reset theo test class, và property `wiremock.reset-mappings-after-each-test=true` hữu ích khi từng method phải cách ly scenario/mapping.

Stateful scenario có thể test retry “lần đầu 500, lần sau 200”, nhưng phải verify số request và giới hạn retry để phát hiện retry storm. WireMock không chứng minh DNS, TLS certificate, provider rate limit hoặc contract provider thực sự; bổ sung contract test/sandbox smoke khi rủi ro cần.

> 💡 **Giải thích dễ hiểu:**
> WireMock giống diễn viên đóng vai đối tác: có thể cố ý trả lời chậm, báo lỗi rồi thành công để đội mình luyện phản ứng. Diễn viên giúp diễn tập ổn định, nhưng không chứng minh đối tác thật ngoài đời sẽ nói đúng kịch bản.

---

## How – Spring Security Test

Spring Security Test cung cấp annotation, request post-processor và matcher cho authentication/authorization, CSRF, OAuth2/JWT.

### User/role và CSRF

```java
@WebMvcTest(AdminController.class)
@Import(SecurityConfig.class)
class AdminSecurityTest {

    @Autowired
    private MockMvc mockMvc;

    @MockitoBean
    private AdminService service;

    @MockitoBean
    private JwtDecoder jwtDecoder;

    @Test
    void delete_anonymous_returns401() throws Exception {
        mockMvc.perform(delete("/api/admin/users/7").with(csrf()))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser(roles = "USER")
    void delete_userRole_returns403() throws Exception {
        mockMvc.perform(delete("/api/admin/users/7").with(csrf()))
            .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser(roles = "ADMIN")
    void delete_admin_returns204() throws Exception {
        mockMvc.perform(delete("/api/admin/users/7").with(csrf()))
            .andExpect(status().isNoContent());
    }

    @Test
    @WithMockUser(roles = "ADMIN")
    void delete_invalidCsrf_returns403() throws Exception {
        mockMvc.perform(delete("/api/admin/users/7")
                .with(csrf().useInvalidToken()))
            .andExpect(status().isForbidden());
    }
}
```

Chỉ thêm `csrf()` nếu production security bật CSRF cho request đó. Test không nên “rắc csrf cho pass” mà không hiểu session/cookie hay bearer-token architecture.

### JWT Resource Server

```java
@Test
void readOrder_scopePresent_returns200() throws Exception {
    mockMvc.perform(get("/api/orders/42")
            .with(jwt()
                .jwt(jwt -> jwt
                    .subject("alice")
                    .claim("tenant", "acme"))
                .authorities(new SimpleGrantedAuthority("SCOPE_order.read"))))
        .andExpect(status().isOk());
}

@Test
void readOrder_scopeMissing_returns403() throws Exception {
    mockMvc.perform(get("/api/orders/42").with(jwt()))
        .andExpect(status().isForbidden());
}
```

`jwt()` tạo `JwtAuthenticationToken` giả và **không yêu cầu JWT hợp lệ**, vì vậy nó kiểm authorization/controller behavior, không kiểm signature, issuer, audience, expiry hoặc `JwtDecoder`.

Muốn kiểm claim-to-authority converter/filter chain, mock `JwtDecoder.decode("token")` trả `Jwt` mong muốn rồi gửi `Authorization: Bearer token`. Muốn kiểm crypto/issuer/JWK rotation, dùng test riêng với key/test authorization server hoặc signed fixture đúng cấu hình production.

Nếu tự dựng `MockMvc` bằng `standaloneSetup`, phải `.apply(springSecurity())` hoặc thêm `FilterChainProxy`; `@WebMvcTest`/Boot auto-configuration thường làm phần wiring này. Luôn có negative tests: anonymous `401`, authenticated thiếu quyền `403`, tenant/ownership, invalid token và CORS/CSRF nếu áp dụng.

> 💡 **Giải thích dễ hiểu:**
> `jwt()` giống đưa cho bảo vệ một thẻ test đã được hệ thống công nhận để kiểm cửa nào được mở. Nó không mang thẻ qua máy soi chữ ký. Vì vậy cần một nhóm test kiểm quyền cửa và một nhóm khác kiểm máy soi thẻ thật.

---

## How – Integration Test Strategy

### Chọn `webEnvironment`

| Mode | Server | Client phù hợp | Transaction behavior |
|---|---|---|---|
| `MOCK` | Không mở port | `MockMvc`/bound client | Test và handler thường cùng test-managed context |
| `RANDOM_PORT` | Server thật, port ngẫu nhiên | `RestTestClient`, `WebTestClient` hoặc client phù hợp Boot version | Client/server khác thread và transaction |
| `DEFINED_PORT` | Server thật, port cố định | HTTP client | Dễ xung đột port, hiếm cần trong CI |
| `NONE` | Không web environment | Gọi bean trực tiếp | Dành cho non-web integration |

Điểm rất quan trọng: `@Transactional` trên test `RANDOM_PORT` chỉ rollback transaction của test thread. Request HTTP chạy ở server thread, nên transaction do ứng dụng commit **không tự rollback**. Phải cleanup rõ hoặc cấp database/schema riêng.

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureRestTestClient
@Import(ContainersConfiguration.class)
class OrderFlowIntegrationTest {

    @Autowired
    private RestTestClient client; // Boot 4.x; chọn live client tương ứng ở Boot 3.5

    @Autowired
    private OrderRepository orders;

    @AfterEach
    void cleanDatabase() {
        orders.deleteAllInBatch();
    }

    @Test
    void createThenReadOrder() {
        String location = client.post().uri("/api/orders")
            .body(validRequest())
            .exchange()
            .expectStatus().isCreated()
            .returnResult()
            .getResponseHeaders().getLocation().toString();

        client.get().uri(location)
            .exchange()
            .expectStatus().isOk()
            .expectBody()
            .jsonPath("$.status").isEqualTo("PENDING");
    }
}
```

`RestTestClient` là API hiện hành trong Boot 4.x. Ở Boot 3.5, dùng `TestRestTemplate` hoặc `WebTestClient` theo dependency/application stack; đừng đưa import Boot 4 vào branch 3.5.

### Context cache và test performance

Spring TestContext cache `ApplicationContext` theo cấu hình. Các tổ hợp property/profile/import/mock khác nhau tạo cache key khác nhau. Giữ annotation/property nhất quán giữa test class giúp reuse context.

- Tránh `@DirtiesContext` trừ khi test thực sự làm context không thể tái sử dụng.
- Đặt tên field `@MockitoBean` nhất quán; qualifier/name khác có thể làm phát sinh context khác.
- Không tạo một base class khổng lồ khiến mọi test nạp Kafka, Redis và PostgreSQL dù không dùng.
- Theo dõi context cache hit/miss và thời gian container/context startup trước khi “tối ưu” bằng singleton toàn cục.

### Parallel execution

Chỉ bật parallel khi test không dùng shared mutable database, broker, filesystem, WireMock scenario, `@DirtiesContext` hoặc mock/context có thể va chạm. Random port không tự đảm bảo data isolation. Tách namespace/schema/topic/key theo test hoặc giữ nhóm stateful chạy tuần tự.

### Async và eventual consistency

Không dùng `Thread.sleep()` với thời gian tùy ý. Dùng polling có deadline như Awaitility, `StepVerifier`, latch hoặc consumer probe; assert cả timeout để test fail hữu hạn.

```java
await().atMost(Duration.ofSeconds(10))
    .pollInterval(Duration.ofMillis(100))
    .untilAsserted(() ->
        assertThat(outboxRepository.findPublished(orderId)).isPresent());
```

> 💡 **Giải thích dễ hiểu:**
> Context cache giống giữ lại một căn phòng đã setup cho lớp sau. Mỗi test đổi một kiểu bàn ghế sẽ buộc dựng phòng mới. Parallel test giống cho nhiều đội dùng chung phòng cùng lúc: chỉ nhanh nếu họ không sửa hoặc giành cùng đồ vật.

---

## When – Dùng loại test nào?

| Rủi ro cần chứng minh | Test nhỏ nhất phù hợp |
|---|---|
| Domain calculation/branch | Unit test, object thật |
| Route, validation, ProblemDetail, JSON | `@WebMvcTest`/`@WebFluxTest` |
| Custom JPA query/constraint/dialect | `@DataJpaTest` + DB Testcontainer |
| Redis TTL/serialization | `@DataRedisTest` + Redis container |
| `RestClient` request/response mapping | `@RestClientTest` |
| Timeout/retry/error của HTTP dependency | WireMock/mock HTTP server |
| Security route/method authorization | Security Test với user/jwt/csrf |
| JWT signature/issuer/audience | Integration với `JwtDecoder`/key thật |
| Full transaction + migration + event | `@SpringBootTest` + containers |
| Consumer/provider compatibility | Contract test/stub artifact |
| Deployment/routing/identity thật | E2E hoặc smoke sau deploy |

Không nâng test lên full context chỉ để tăng cảm giác an toàn. Mỗi test phải có failure mode mục tiêu; cùng behavior có thể được bảo vệ ở nhiều tầng chỉ khi mỗi tầng bắt một loại lỗi khác nhau.

---

## Compare – Những lựa chọn dễ nhầm

### Mock, fake, stub server và container

| Double/hạ tầng | Đặc điểm | Bắt được | Không bắt được |
|---|---|---|---|
| Mockito mock | Behavior lập trình trong process | Branch và interaction | Serialization/protocol thật |
| Fake | Implementation đơn giản có state | Workflow nhanh | Khác production implementation |
| WireMock | HTTP server giả | Request/response, delay, retry | Provider implementation/TLS thực |
| Testcontainer | Service thật trong container | Driver/protocol/dialect/migration | Managed-cloud behavior đầy đủ |

### H2 và PostgreSQL Testcontainer

| | H2 embedded | PostgreSQL container |
|---|---|---|
| Tốc độ startup | Nhanh | Chậm hơn |
| Dialect/type/index/locking | Có khác biệt | Gần production PostgreSQL |
| Phù hợp | Query rất đơn giản, prototype | Repository/migration production-critical |

### MockMvc và live HTTP

| | `MockMvc` | `RANDOM_PORT` |
|---|---|---|
| Server socket | Không | Có |
| MVC mapping/validation | Có | Có |
| Network/container/TLS | Không | Một phần hoặc có tùy setup |
| Tốc độ | Nhanh hơn | Chậm hơn |
| Test transaction rollback | Có thể cùng transaction | Server transaction tách biệt |

### Embedded Kafka và Kafka Testcontainer

Embedded broker thường khởi động nhanh hơn và tiện cho Spring Kafka test. Kafka container gần runtime/distribution thực hơn. Chọn **một** cho mục tiêu test; không gắn `@EmbeddedKafka` và Kafka container vào cùng class rồi không biết client đang nối broker nào.

---

## Trade-offs

- Unit test nhanh và định vị lỗi tốt, nhưng không phát hiện wiring/protocol.
- Slice test cân bằng tốc độ/fidelity, nhưng import quá nhiều bean sẽ biến nó thành full context trá hình.
- Testcontainers tăng production parity, đổi lại cần Docker, image pull, CPU/RAM và cleanup tốt.
- WireMock tạo failure scenario dễ, nhưng stub drift khỏi provider có thể cho cảm giác an toàn giả.
- Security request post-processor làm test authorization đơn giản, nhưng có thể bypass token validation thực.
- Rollback làm test data sạch nhanh, nhưng che lỗi chỉ xuất hiện lúc commit hoặc ở transaction khác.
- Parallel execution giảm wall-clock time, nhưng tăng flaky test nếu có shared mutable state.
- E2E bắt lỗi deployment, nhưng chậm và khó chẩn đoán; không nên là nơi duy nhất kiểm business rule.

---

## Production – Chiến lược CI/CD và chất lượng test

### Pipeline gợi ý

```text
Pull request:
  compile/static analysis → unit → slices → selected integration/contract

Main branch:
  full integration + Testcontainers → package/image → security scan

Pre-production:
  migration test → E2E critical journey → resilience/load test có chọn lọc

Post-deploy:
  smoke/readiness → synthetic critical path → progressive rollout gates
```

### Checklist production-grade

- Pin Testcontainers/WireMock stub/image version; dùng BOM, không dùng floating `latest`.
- CI bắt buộc integration test phải có Docker/runtime; không silently skip rồi báo xanh.
- Test migration từ schema gần production, không chỉ database rỗng.
- Mỗi test tự sở hữu data/key/topic hoặc cleanup xác định; không phụ thuộc thứ tự.
- Time/UUID/random được kiểm soát bằng `Clock`, seed hoặc matcher đúng mức.
- Không gọi service Internet/shared staging không ổn định từ unit/integration suite.
- Capture container log, application log, request/response đã redaction khi fail.
- Không che flaky test bằng retry vô hạn; tìm shared state, race, timeout hoặc resource starvation.
- Coverage là tín hiệu, không phải mục tiêu; mutation/branch/critical-path quality quan trọng hơn một phần trăm đơn lẻ.
- Security negative tests, contract breaking-change check và migration rollback/forward path nằm trong pipeline.
- Theo dõi test duration, context cache miss và flaky rate để suite không xuống cấp âm thầm.

> 💡 **Giải thích dễ hiểu:**
> Test suite production giống hệ thống kiểm soát chất lượng của nhà máy: kiểm nhanh ngay trên dây chuyền, kiểm chuyên sâu theo lô, rồi chạy thử sản phẩm hoàn chỉnh. Nếu một máy kiểm thường xuyên báo sai mà chỉ bấm “chạy lại”, sớm muộn hàng lỗi thật cũng lọt qua.

---

## Nguồn chính thức

- [Spring Boot – Testing](https://docs.spring.io/spring-boot/reference/testing/index.html)
- [Spring Boot – Testing Spring Boot Applications và Test Slices](https://docs.spring.io/spring-boot/reference/testing/spring-boot-applications.html)
- [Spring Boot – Testcontainers và Service Connections](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html)
- [Spring Boot 3.5 – `@MockBean` deprecation](https://docs.spring.io/spring-boot/3.5/api/java/org/springframework/boot/test/mock/mockito/MockBean.html)
- [Spring Framework – `@MockitoBean` và `@MockitoSpyBean`](https://docs.spring.io/spring-framework/reference/testing/annotations/integration-spring/annotation-mockitobean.html)
- [Spring Framework – MockMvc](https://docs.spring.io/spring-framework/reference/testing/mockmvc.html)
- [Spring Framework – Test-managed Transactions](https://docs.spring.io/spring-framework/reference/testing/testcontext-framework/tx.html)
- [Spring Security – MockMvc Test Integration](https://docs.spring.io/spring-security/reference/servlet/test/mockmvc/)
- [Spring Security – OAuth2/JWT Testing](https://docs.spring.io/spring-security/reference/servlet/test/mockmvc/oauth2.html)
- [Spring Cloud Contract – WireMock](https://docs.spring.io/spring-cloud-contract/docs/current/reference/htmlsingle/)

---

## Ghi chú – Chủ đề tiếp theo

- REST/ProblemDetail/Security boundary: [Spring Boot Web](springboot_web.md).
- JPA, transaction, migration, Redis: [Spring Boot Data](springboot_data.md).
- Kafka/event integration test: [Spring Boot Messaging](springboot_messaging.md).
- Observability, Actuator và deployment: [Spring Boot Production](springboot_production.md).

> Keywords: test pyramid, test slice, `@WebMvcTest`, `@WebFluxTest`, `@DataJpaTest`, `@DataRedisTest`, `@JsonTest`, `@RestClientTest`, `@MockitoBean`, `MockMvc`, `WebTestClient`, `RestTestClient`, Testcontainers, `@ServiceConnection`, `ConnectionDetails`, `@DynamicPropertySource`, WireMock, `@AutoConfigureWireMock`, Spring Security Test, `@WithMockUser`, `jwt()`, `csrf()`, TestContext cache, `@DirtiesContext`, test-managed transaction, contract test, smoke test, flaky test.

---

*Cập nhật lần cuối: 2026-07-27*
