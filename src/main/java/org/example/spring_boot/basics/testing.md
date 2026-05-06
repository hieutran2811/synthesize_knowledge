# Testing Spring Boot – Kiểm thử chuyên nghiệp

## What – Testing Strategy trong Spring Boot

**Testing Pyramid:**
```
         /\
        /  \
       / E2E \   ← ít, chậm, fragile (Selenium, Cypress)
      /────────\
     /Integration\  ← vừa (Testcontainers, @SpringBootTest)
    /────────────────\
   /    Unit Tests    \  ← nhiều, nhanh, isolated (JUnit 5 + Mockito)
  /────────────────────\
```

**Spring Boot Testing Slices:**
```
@SpringBootTest    – Full application context (tích hợp đầy đủ)
@WebMvcTest        – Controller layer only (MockMvc, no DB)
@DataJpaTest       – JPA layer only (H2 in-memory, no web)
@DataRedisTest     – Redis layer only
@RestClientTest    – RestTemplate/WebClient (MockServer)
@JsonTest          – Jackson serialization/deserialization
```

---

## Dependencies

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-test</artifactId>
    <scope>test</scope>
    <!-- Bao gồm: JUnit 5, Mockito, AssertJ, MockMvc, Hamcrest, JsonPath, Awaitility -->
</dependency>

<!-- Testcontainers -->
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

---

## Unit Testing – JUnit 5 + Mockito

```java
@ExtendWith(MockitoExtension.class)  // Không load Spring context – cực nhanh
class OrderServiceTest {

    @Mock
    private OrderRepository orderRepo;

    @Mock
    private PaymentService paymentService;

    @Mock
    private NotificationService notificationService;

    @InjectMocks
    private OrderService orderService;

    @Captor
    private ArgumentCaptor<Order> orderCaptor;

    @Test
    void createOrder_success_savesOrderAndChargesPayment() {
        // Arrange
        CreateOrderRequest req = new CreateOrderRequest("user-1", List.of(
            new OrderItem("prod-1", 2, BigDecimal.valueOf(10.00))
        ));
        Payment payment = new Payment("pay-1", PaymentStatus.SUCCESS);
        when(paymentService.charge(any(), any())).thenReturn(payment);
        when(orderRepo.save(any())).thenAnswer(inv -> {
            Order o = inv.getArgument(0);
            o.setId(1L);
            return o;
        });

        // Act
        Order result = orderService.createOrder(req);

        // Assert
        assertThat(result.getId()).isEqualTo(1L);
        assertThat(result.getStatus()).isEqualTo(OrderStatus.CONFIRMED);

        // Verify interactions
        verify(orderRepo).save(orderCaptor.capture());
        Order savedOrder = orderCaptor.getValue();
        assertThat(savedOrder.getUserId()).isEqualTo("user-1");
        assertThat(savedOrder.getItems()).hasSize(1);

        verify(paymentService).charge(eq("user-1"), eq(BigDecimal.valueOf(20.00)));
        verify(notificationService).sendOrderConfirmation(any());
    }

    @Test
    void cancelOrder_alreadyShipped_throwsBusinessRuleException() {
        // Arrange
        Order shipped = Order.builder().id(1L).status(OrderStatus.SHIPPED).build();
        when(orderRepo.findById(1L)).thenReturn(Optional.of(shipped));

        // Act & Assert
        assertThatThrownBy(() -> orderService.cancelOrder(1L))
            .isInstanceOf(BusinessRuleException.class)
            .hasMessageContaining("already been shipped");

        verify(orderRepo, never()).save(any());
    }

    @Test
    void getOrder_notFound_throwsResourceNotFoundException() {
        when(orderRepo.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> orderService.getOrder(99L))
            .isInstanceOf(ResourceNotFoundException.class)
            .hasMessageContaining("Order")
            .hasMessageContaining("99");
    }

    @ParameterizedTest
    @CsvSource({
        "100.00, USD, 8.00",
        "200.00, EUR, 20.00",
        "50.00, GBP, 2.50"
    })
    void calculateTax_variousCurrencies(BigDecimal amount, String currency, BigDecimal expectedTax) {
        BigDecimal tax = orderService.calculateTax(amount, currency);
        assertThat(tax).isEqualByComparingTo(expectedTax);
    }
}
```

---

## @WebMvcTest – Controller Layer Test

```java
@WebMvcTest(OrderController.class)
class OrderControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean  // Spring context mock (khác @Mock của Mockito)
    private OrderService orderService;

    @MockBean
    private JwtTokenProvider jwtTokenProvider;

    @Test
    @WithMockUser(username = "user-1", roles = "USER")
    void createOrder_validRequest_returns201() throws Exception {
        CreateOrderRequest req = new CreateOrderRequest(
            List.of(new OrderItemRequest("prod-1", 2))
        );
        OrderResponse response = new OrderResponse(1L, "CONFIRMED", BigDecimal.TEN);
        when(orderService.createOrder(any())).thenReturn(response);

        mockMvc.perform(post("/api/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(req)))
            .andDo(print())
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.id").value(1))
            .andExpect(jsonPath("$.status").value("CONFIRMED"))
            .andExpect(jsonPath("$.total").value(10));

        verify(orderService).createOrder(any(CreateOrderRequest.class));
    }

    @Test
    void createOrder_invalidRequest_returns400WithErrors() throws Exception {
        CreateOrderRequest req = new CreateOrderRequest(null); // null items

        mockMvc.perform(post("/api/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(req))
                .with(csrf()))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.status").value(400))
            .andExpect(jsonPath("$.errors").isArray())
            .andExpect(jsonPath("$.errors[0].field").value("items"));
    }

    @Test
    void getOrder_unauthorized_returns401() throws Exception {
        mockMvc.perform(get("/api/orders/1"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser(roles = "USER")
    void getOrder_notFound_returns404() throws Exception {
        when(orderService.getOrder(99L))
            .thenThrow(new ResourceNotFoundException("Order", 99L));

        mockMvc.perform(get("/api/orders/99"))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.title").value("Resource Not Found"));
    }

    // Test file upload
    @Test
    @WithMockUser
    void uploadFile_validFile_returns200() throws Exception {
        MockMultipartFile file = new MockMultipartFile(
            "file", "test.csv", "text/csv", "col1,col2\nval1,val2".getBytes()
        );

        mockMvc.perform(multipart("/api/upload").file(file))
            .andExpect(status().isOk());
    }
}
```

---

## @DataJpaTest – Repository Layer Test

```java
@DataJpaTest  // Load chỉ JPA layer, H2 in-memory (default)
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE) // Dùng real DB nếu config
class UserRepositoryTest {

    @Autowired
    private UserRepository userRepo;

    @Autowired
    private TestEntityManager entityManager;

    @Test
    void findByEmail_exists_returnsUser() {
        // Arrange
        User user = User.builder()
            .name("Alice")
            .email("alice@example.com")
            .tenantId(1L)
            .build();
        entityManager.persistAndFlush(user);
        entityManager.clear(); // clear L1 cache

        // Act
        Optional<User> found = userRepo.findByEmail("alice@example.com");

        // Assert
        assertThat(found).isPresent();
        assertThat(found.get().getName()).isEqualTo("Alice");
    }

    @Test
    void findByTenantId_withSpecification_returnsFiltered() {
        // Setup test data
        User alice = entityManager.persist(User.builder()
            .name("Alice").email("a@t1.com").tenantId(1L).status(ACTIVE).build());
        User bob = entityManager.persist(User.builder()
            .name("Bob").email("b@t1.com").tenantId(1L).status(INACTIVE).build());
        User charlie = entityManager.persist(User.builder()
            .name("Charlie").email("c@t2.com").tenantId(2L).status(ACTIVE).build());
        entityManager.flush();

        Specification<User> spec = Specification
            .where(UserSpec.hasTenant(1L))
            .and(UserSpec.hasStatus(ACTIVE));

        List<User> result = userRepo.findAll(spec);

        assertThat(result).hasSize(1);
        assertThat(result.get(0).getName()).isEqualTo("Alice");
    }
}
```

---

## @SpringBootTest + Testcontainers – Integration Test

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
@ActiveProfiles("integration-test")
class OrderIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test");

    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7")
        .withExposedPorts(6379);

    @DynamicPropertySource  // Override application properties với container ports
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.data.redis.host", redis::getHost);
        registry.add("spring.data.redis.port", () -> redis.getMappedPort(6379));
    }

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private OrderRepository orderRepo;

    @Test
    void createAndGetOrder_fullFlow() {
        // Login để lấy token
        LoginRequest login = new LoginRequest("admin@test.com", "password");
        TokenResponse tokens = restTemplate.postForObject("/api/auth/login", login, TokenResponse.class);

        // Create order
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth(tokens.accessToken());
        CreateOrderRequest req = new CreateOrderRequest(List.of(new OrderItemRequest("prod-1", 2)));

        ResponseEntity<OrderResponse> createResp = restTemplate.exchange(
            "/api/orders", HttpMethod.POST,
            new HttpEntity<>(req, headers), OrderResponse.class
        );
        assertThat(createResp.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        Long orderId = createResp.getBody().id();

        // Verify in DB
        Order order = orderRepo.findById(orderId).orElseThrow();
        assertThat(order.getStatus()).isEqualTo(OrderStatus.CONFIRMED);

        // Get order via API
        ResponseEntity<OrderResponse> getResp = restTemplate.exchange(
            "/api/orders/" + orderId, HttpMethod.GET,
            new HttpEntity<>(headers), OrderResponse.class
        );
        assertThat(getResp.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(getResp.getBody().id()).isEqualTo(orderId);
    }

    @Test
    void createOrder_rollbackOnPaymentFailure() {
        // ... test that DB is consistent after payment failure
        long orderCountBefore = orderRepo.count();
        // ... trigger failure scenario
        long orderCountAfter = orderRepo.count();
        assertThat(orderCountAfter).isEqualTo(orderCountBefore); // no partial order
    }
}
```

---

## WireMock – Mock External Services

```java
@SpringBootTest
@WireMockTest(httpPort = 8089)
class PaymentServiceTest {

    @Autowired
    private PaymentService paymentService;

    @Test
    void chargeCard_stripeSuccess_returnsPayment(WireMockRuntimeInfo wm) {
        stubFor(post(urlEqualTo("/v1/charges"))
            .withHeader("Authorization", containing("Bearer sk_"))
            .willReturn(aResponse()
                .withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBodyFile("stripe-charge-success.json"))); // src/test/resources/__files/

        Payment result = paymentService.charge("card_123", BigDecimal.TEN);

        assertThat(result.getStatus()).isEqualTo(PaymentStatus.SUCCESS);
        verify(postRequestedFor(urlEqualTo("/v1/charges")));
    }

    @Test
    void chargeCard_stripeTimeout_throwsException() {
        stubFor(post(urlEqualTo("/v1/charges"))
            .willReturn(aResponse()
                .withFixedDelay(5000)  // 5 second delay
                .withStatus(200)));

        assertThatThrownBy(() -> paymentService.charge("card_123", BigDecimal.TEN))
            .isInstanceOf(PaymentTimeoutException.class);
    }
}
```

---

## Test Containers Spring Boot 3.1+ (Simplified)

```java
// Khai báo trong test application.properties / @TestConfiguration
@TestConfiguration(proxyBeanMethods = false)
class TestcontainersConfig {

    @Bean
    @ServiceConnection  // tự động wire properties!
    PostgreSQLContainer<?> postgresContainer() {
        return new PostgreSQLContainer<>("postgres:16");
    }

    @Bean
    @ServiceConnection
    RedisContainer redisContainer() {
        return new RedisContainer("redis:7");
    }
}

// Test class chỉ cần import config
@SpringBootTest
@Import(TestcontainersConfig.class)
class MyTest {}
```

---

## Tips & Best Practices

```java
// 1. @TestPropertySource – override specific properties
@TestPropertySource(properties = {
    "app.payment.enabled=false",
    "app.email.mock=true"
})

// 2. @Sql – setup test data
@Test
@Sql("/test-data/orders.sql")
@Sql(value = "/test-data/cleanup.sql", executionPhase = AFTER_TEST_METHOD)
void testWithData() { ... }

// 3. @Transactional trên test – auto rollback sau mỗi test
@DataJpaTest  // mặc định đã @Transactional
@Transactional  // hoặc thêm explicit

// 4. Slices không conflict nhau
// @WebMvcTest load controller + security + advice, NOT service beans
// @DataJpaTest load repository + JPA, NOT controller beans

// 5. Shared container (performance)
@SpringBootTest
@Testcontainers
class BaseIntegrationTest {
    @Container
    static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>("postgres:16")
        .withReuse(true);  // reuse container across test runs (speed up)
}
```

---

## Trade-offs

| Test Type | Speed | Coverage | Confidence |
|-----------|-------|----------|------------|
| Unit | Fastest (ms) | Low (isolated) | Low (mocked deps) |
| @WebMvcTest | Fast (s) | Controller layer | Medium |
| @DataJpaTest | Fast (s) | Repository layer | Medium |
| @SpringBootTest + Testcontainers | Slow (10-30s startup) | Full | Highest |

---

## Ghi chú

**Sub-topic tiếp theo:**
- `advanced/reactive_webflux.md` – Testing reactive endpoints với WebTestClient
- `advanced/messaging.md` – Testing Kafka consumers/producers
- **Keywords:** @MockBean vs @Mock, TestRestTemplate vs WebTestClient, @AutoConfigureMockMvc, @SpyBean, Awaitility (async assertions), EmbeddedKafka, @EmbeddedKafka, Consumer-driven contract testing (Pact), ArchUnit (architecture tests), Mutation testing (PIT), JaCoCo coverage, SonarQube quality gates
