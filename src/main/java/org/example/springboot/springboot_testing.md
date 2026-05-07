# Spring Boot Testing – Deep Dive

## Mục lục
1. [Test Slices](#1-test-slices)
2. [MockMvc Patterns](#2-mockmvc-patterns)
3. [Testcontainers](#3-testcontainers)
4. [WireMock – HTTP Mocking](#4-wiremock--http-mocking)
5. [Security Testing](#5-security-testing)
6. [Integration Test Strategy](#6-integration-test-strategy)

---

## 1. Test Slices

### 1.1 @WebMvcTest — Controller Layer Only

```java
// Loads: Controllers, @ControllerAdvice, @JsonComponent, Filter, WebMvcConfigurer
// Does NOT load: @Service, @Repository, @Component, full Spring context
@WebMvcTest(UserController.class)
class UserControllerTest {

    @Autowired
    private MockMvc mockMvc;
    
    @MockBean  // registers mock in Spring context
    private UserService userService;
    
    @Autowired
    private ObjectMapper objectMapper;
    
    @Test
    void createUser_validInput_returns201() throws Exception {
        CreateUserRequest req = new CreateUserRequest("John", "john@example.com", "password123");
        UserResponse response = new UserResponse(1L, "John", "john@example.com");
        
        given(userService.create(any())).willReturn(response);
        
        mockMvc.perform(post("/api/v1/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(req)))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.id").value(1L))
            .andExpect(jsonPath("$.data.name").value("John"))
            .andExpect(header().string("Location", containsString("/api/v1/users/1")));
    }
    
    @Test
    void createUser_blankName_returns400() throws Exception {
        CreateUserRequest req = new CreateUserRequest("", "john@example.com", "password123");
        
        mockMvc.perform(post("/api/v1/users")
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(req)))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.errors[0].field").value("name"))
            .andExpect(jsonPath("$.errors[0].message").exists());
    }
    
    @Test
    void getUser_notFound_returns404() throws Exception {
        given(userService.findById(99L))
            .willThrow(new EntityNotFoundException("User 99 not found"));
        
        mockMvc.perform(get("/api/v1/users/99"))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.message").value("User 99 not found"));
    }
}
```

### 1.2 @DataJpaTest — JPA Layer Only

```java
// Loads: @Entity, @Repository, embedded H2 (or Testcontainers with @AutoConfigureTestDatabase)
// Rolls back each test by default
// Does NOT load: @Service, @Component, web layer
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE) // use real DB
@Testcontainers
class UserRepositoryTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");
    
    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }
    
    @Autowired
    private UserRepository userRepository;
    
    @Autowired
    private TestEntityManager entityManager;
    
    @Test
    void findByEmail_existingUser_returnsUser() {
        User user = entityManager.persistAndFlush(
            User.builder().firstName("John").email("john@test.com").active(true).build()
        );
        entityManager.clear(); // clear 1st-level cache
        
        Optional<User> found = userRepository.findByEmail("john@test.com");
        
        assertThat(found).isPresent();
        assertThat(found.get().getFirstName()).isEqualTo("John");
    }
    
    @Test
    void findActiveUsers_returnsOnlyActive() {
        entityManager.persist(User.builder().email("a@test.com").active(true).build());
        entityManager.persist(User.builder().email("b@test.com").active(false).build());
        entityManager.flush();
        
        List<User> active = userRepository.findByActiveTrue();
        
        assertThat(active).hasSize(1);
        assertThat(active.get(0).getEmail()).isEqualTo("a@test.com");
    }
    
    @Test
    void specification_findsCorrectUsers() {
        entityManager.persist(User.builder().firstName("Alice").email("alice@test.com")
            .department("IT").active(true).build());
        entityManager.persist(User.builder().firstName("Bob").email("bob@test.com")
            .department("HR").active(true).build());
        entityManager.flush();
        
        Specification<User> spec = UserSpecs.inDepartment("IT").and(UserSpecs.isActive());
        List<User> result = userRepository.findAll(spec);
        
        assertThat(result).hasSize(1);
        assertThat(result.get(0).getFirstName()).isEqualTo("Alice");
    }
}
```

### 1.3 @DataRedisTest

```java
@DataRedisTest
@Testcontainers
class RedisSessionRepositoryTest {

    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
        .withExposedPorts(6379);
    
    @DynamicPropertySource
    static void props(DynamicPropertyRegistry registry) {
        registry.add("spring.data.redis.host", redis::getHost);
        registry.add("spring.data.redis.port", () -> redis.getMappedPort(6379));
    }
    
    @Autowired
    private StringRedisTemplate redisTemplate;
    
    @Autowired
    private SessionRepository sessionRepository; // component under test
    
    @Test
    void createAndRetrieveSession() {
        String sessionId = sessionRepository.create("user:123", Duration.ofHours(1));
        
        Optional<Session> session = sessionRepository.findById(sessionId);
        
        assertThat(session).isPresent();
        assertThat(session.get().getUserId()).isEqualTo("user:123");
    }
}
```

### 1.4 @JsonTest

```java
// Tests JSON serialization/deserialization only
@JsonTest
class UserResponseTest {

    @Autowired
    private JacksonTester<UserResponse> json;
    
    @Test
    void serialize_includesAllFields() throws Exception {
        UserResponse response = new UserResponse(1L, "John", "john@test.com",
            LocalDateTime.of(2024, 1, 1, 0, 0));
        
        JsonContent<UserResponse> content = json.write(response);
        
        assertThat(content).hasJsonPathNumberValue("$.id", 1L);
        assertThat(content).hasJsonPathStringValue("$.name", "John");
        assertThat(content).hasJsonPathStringValue("$.email", "john@test.com");
        assertThat(content).hasJsonPathStringValue("$.createdAt", "2024-01-01T00:00:00");
        assertThat(content).doesNotHaveJsonPath("$.password"); // sensitive field hidden
    }
    
    @Test
    void deserialize_handlesAllFormats() throws Exception {
        String jsonStr = """
            {"id": 1, "name": "John", "email": "john@test.com"}
            """;
        
        UserResponse response = json.parseObject(jsonStr);
        
        assertThat(response.getId()).isEqualTo(1L);
    }
}
```

### 1.5 Other Slices

```java
@DataMongoTest    // MongoDB repositories
@DataR2dbcTest    // R2DBC repositories (reactive)
@RestClientTest   // @HttpExchange clients / RestClient
@WebFluxTest      // WebFlux controllers
@JdbcTest         // JdbcTemplate / Spring JDBC
@JooqTest         // jOOQ DSLContext

// @RestClientTest example
@RestClientTest(WeatherClient.class)
class WeatherClientTest {
    
    @Autowired
    private WeatherClient weatherClient;
    
    @Autowired
    private MockRestServiceServer server;  // auto-configured
    
    @Test
    void getWeather_returnsCorrectData() {
        server.expect(requestTo("https://api.weather.com/current?city=Hanoi"))
            .andRespond(withSuccess(
                """
                {"city":"Hanoi","temp":30,"unit":"C"}
                """, MediaType.APPLICATION_JSON));
        
        WeatherDto weather = weatherClient.getWeather("Hanoi");
        
        assertThat(weather.getTemp()).isEqualTo(30);
        server.verify();
    }
}
```

---

## 2. MockMvc Patterns

### 2.1 MockMvc Setup Options

```java
// Option 1: Standalone (fastest, no Spring context)
@ExtendWith(MockitoExtension.class)
class UserControllerUnitTest {
    
    @InjectMocks
    private UserController userController;
    
    @Mock
    private UserService userService;
    
    private MockMvc mockMvc;
    
    @BeforeEach
    void setup() {
        mockMvc = MockMvcBuilders
            .standaloneSetup(userController)
            .setControllerAdvice(new GlobalExceptionHandler())
            .addFilter(new CharacterEncodingFilter("UTF-8", true))
            .build();
    }
}

// Option 2: @WebMvcTest (controller layer with Spring context)
@WebMvcTest(UserController.class)
class UserControllerWebTest {
    @Autowired
    private MockMvc mockMvc; // auto-configured
}

// Option 3: Full integration test
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.MOCK)
@AutoConfigureMockMvc
class UserControllerIntegrationTest {
    @Autowired
    private MockMvc mockMvc;
}
```

### 2.2 Request Builders

```java
// GET with params
mockMvc.perform(get("/api/users")
    .param("page", "0")
    .param("size", "10")
    .param("sort", "createdAt,desc")
    .header("Authorization", "Bearer " + token)
    .accept(MediaType.APPLICATION_JSON));

// POST with JSON body
mockMvc.perform(post("/api/users")
    .contentType(MediaType.APPLICATION_JSON)
    .content(objectMapper.writeValueAsString(request))
    .with(csrf())); // for forms with CSRF

// Multipart file upload
mockMvc.perform(multipart("/api/files")
    .file(new MockMultipartFile("file", "test.csv",
        MediaType.TEXT_PLAIN_VALUE, "col1,col2\nval1,val2".getBytes()))
    .param("description", "test file"));

// DELETE
mockMvc.perform(delete("/api/users/{id}", 1L)
    .header("Authorization", "Bearer " + token));
```

### 2.3 Result Matchers

```java
mockMvc.perform(get("/api/users/1"))
    // Status
    .andExpect(status().isOk())
    
    // Headers
    .andExpect(header().string("Content-Type", startsWith("application/json")))
    .andExpect(header().exists("X-Request-Id"))
    
    // JSON path matchers
    .andExpect(jsonPath("$.data.id").value(1L))
    .andExpect(jsonPath("$.data.name").value("John"))
    .andExpect(jsonPath("$.data.items").isArray())
    .andExpect(jsonPath("$.data.items").value(hasSize(3)))
    .andExpect(jsonPath("$.data.items[0].name").value("Item 1"))
    .andExpect(jsonPath("$.data.active").value(true))
    .andExpect(jsonPath("$.data.createdAt").exists())
    .andExpect(jsonPath("$.data.password").doesNotExist())
    
    // Full body
    .andExpect(content().json("""
        {"data": {"id": 1, "name": "John"}}
        """))
    
    // Logging (useful for debugging)
    .andDo(print());
```

### 2.4 MockMvc Result Handlers & Custom Matchers

```java
// Result handler — print for debug
.andDo(print())
.andDo(document("user-create")) // Spring REST Docs

// Capture result for further assertions
MvcResult result = mockMvc.perform(post("/api/users")
    .contentType(MediaType.APPLICATION_JSON)
    .content(objectMapper.writeValueAsString(req)))
    .andExpect(status().isCreated())
    .andReturn();

String location = result.getResponse().getHeader("Location");
String responseBody = result.getResponse().getContentAsString();
UserResponse response = objectMapper.readValue(responseBody,
    new TypeReference<ApiResponse<UserResponse>>() {}).getData();
```

### 2.5 Parameterized Tests

```java
@ParameterizedTest
@MethodSource("invalidRequests")
void createUser_invalidInput_returns400(CreateUserRequest req, String expectedField) 
        throws Exception {
    mockMvc.perform(post("/api/users")
            .contentType(MediaType.APPLICATION_JSON)
            .content(objectMapper.writeValueAsString(req)))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.errors[?(@.field == '" + expectedField + "')]").exists());
}

static Stream<Arguments> invalidRequests() {
    return Stream.of(
        Arguments.of(new CreateUserRequest("", "j@test.com", "pass123"), "name"),
        Arguments.of(new CreateUserRequest("John", "invalid-email", "pass123"), "email"),
        Arguments.of(new CreateUserRequest("John", "j@test.com", "short"), "password")
    );
}
```

---

## 3. Testcontainers

### 3.1 Setup (Spring Boot 3.1+)

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-testcontainers</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>junit-jupiter</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>postgresql</artifactId>
    <scope>test</scope>
</dependency>
<dependency>
    <groupId>org.testcontainers</groupId>
    <artifactId>kafka</artifactId>
    <scope>test</scope>
</dependency>
```

### 3.2 Spring Boot 3.1 @ServiceConnection

```java
// Automatic property wiring — no @DynamicPropertySource needed!
@SpringBootTest
@Testcontainers
class IntegrationTest {

    @Container
    @ServiceConnection  // Spring Boot 3.1+ — auto-configures spring.datasource.*
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");
    
    @Container
    @ServiceConnection
    static RedisContainer redis = new RedisContainer("redis:7-alpine");
    
    @Container
    @ServiceConnection
    static KafkaContainer kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.5.0"));
    
    // Tests use the containers automatically
}
```

### 3.3 Shared Container (Singleton Pattern — faster tests)

```java
// AbstractIntegrationTest.java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@Testcontainers
public abstract class AbstractIntegrationTest {

    // static = shared across all test classes (singleton)
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine")
        .withDatabaseName("testdb")
        .withUsername("test")
        .withPassword("test")
        .withInitScript("init-test.sql");
    
    @Container
    static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
        .withExposedPorts(6379);
    
    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.5.0"))
        .withEnv("KAFKA_AUTO_CREATE_TOPICS_ENABLE", "true");
    
    @DynamicPropertySource
    static void registerProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
        registry.add("spring.data.redis.host", redis::getHost);
        registry.add("spring.data.redis.port", () -> redis.getMappedPort(6379));
        registry.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
    }
}

// All integration tests extend this
class OrderServiceIntegrationTest extends AbstractIntegrationTest {
    @Autowired
    private OrderService orderService;
    
    @Test
    void placeOrder_savesAndPublishesEvent() { ... }
}
```

### 3.4 Testcontainers for Kafka

```java
@SpringBootTest
@Testcontainers
@EmbeddedKafka(partitions = 1, topics = {"orders", "payments"})  // Alternative: embedded Kafka
class KafkaIntegrationTest {

    @Autowired
    private OrderEventPublisher publisher;
    
    @Autowired
    private KafkaListenerEndpointRegistry kafkaListenerRegistry;
    
    // Or use real Kafka with Testcontainers
    @Container
    @ServiceConnection
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.5.0"));
    
    @Test
    @Timeout(30) // fail if consumer doesn't receive within 30s
    void publishOrderEvent_consumerReceivesIt() throws Exception {
        CountDownLatch latch = new CountDownLatch(1);
        List<OrderCreatedEvent> received = new CopyOnWriteArrayList<>();
        
        // Register a test consumer
        kafkaTemplate.setConsumerRebalanceListener(...);
        
        publisher.sendOrderCreated(new OrderCreatedEvent(1L, 42L, new BigDecimal("100.00")));
        
        assertThat(latch.await(10, TimeUnit.SECONDS)).isTrue();
        assertThat(received).hasSize(1);
    }
}
```

### 3.5 Database Cleanup Between Tests

```java
@SpringBootTest
@Testcontainers
@Transactional  // rollback each test — simplest approach
class TransactionalIntegrationTest { ... }

// Or: use @Sql to reset state
@Test
@Sql(scripts = "/test-data/users.sql")
@Sql(scripts = "/test-data/cleanup.sql", executionPhase = Sql.ExecutionPhase.AFTER_TEST_METHOD)
void testWithSetupAndCleanup() { ... }

// Or: programmatic cleanup
@BeforeEach
void cleanDb(@Autowired UserRepository userRepo, @Autowired OrderRepository orderRepo) {
    orderRepo.deleteAll();
    userRepo.deleteAll();
}
```

---

## 4. WireMock – HTTP Mocking

### 4.1 Setup

```xml
<dependency>
    <groupId>org.springframework.cloud</groupId>
    <artifactId>spring-cloud-contract-wiremock</artifactId>
    <scope>test</scope>
</dependency>
```

### 4.2 Basic Usage

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureWireMock(port = 0)  // random port
class PaymentClientTest {

    @Value("${wiremock.server.port}")
    private int wireMockPort;
    
    @Autowired
    private PaymentClient paymentClient;  // @FeignClient or WebClient-based
    
    @BeforeEach
    void setup() {
        // Override URL to point to WireMock
    }
    
    @Test
    void chargeCard_success_returnsPaymentId() {
        // Stubbing
        stubFor(post(urlEqualTo("/api/payments/charge"))
            .withHeader("Content-Type", equalTo("application/json"))
            .withRequestBody(matchingJsonPath("$.amount", equalTo("100.00")))
            .willReturn(aResponse()
                .withStatus(200)
                .withHeader("Content-Type", "application/json")
                .withBody("""
                    {"paymentId": "pay_123", "status": "SUCCESS"}
                    """)));
        
        PaymentResult result = paymentClient.charge(new ChargeRequest("card_token", new BigDecimal("100.00")));
        
        assertThat(result.getPaymentId()).isEqualTo("pay_123");
        
        // Verify the request was made
        verify(postRequestedFor(urlEqualTo("/api/payments/charge"))
            .withHeader("Authorization", matching("Bearer .+")));
    }
    
    @Test
    void chargeCard_serviceUnavailable_throwsException() {
        stubFor(post(urlEqualTo("/api/payments/charge"))
            .willReturn(serviceUnavailable()
                .withFixedDelay(100)));
        
        assertThatThrownBy(() -> paymentClient.charge(new ChargeRequest("token", BigDecimal.TEN)))
            .isInstanceOf(PaymentServiceException.class);
    }
    
    @Test
    void chargeCard_networkTimeout_retriesAndFails() {
        // Simulate network delay beyond client timeout
        stubFor(post(urlEqualTo("/api/payments/charge"))
            .willReturn(aResponse()
                .withFixedDelay(5000)  // 5 second delay
                .withStatus(200)));
        
        assertThatThrownBy(() -> paymentClient.charge(...))
            .isInstanceOf(PaymentTimeoutException.class);
    }
}
```

### 4.3 WireMock with Scenarios (State Machine)

```java
@Test
void retryLogic_succeedsOnSecondAttempt() {
    // First call fails
    stubFor(post(urlEqualTo("/api/payments/charge"))
        .inScenario("Retry Test")
        .whenScenarioStateIs(Scenario.STARTED)
        .willReturn(serverError())
        .willSetStateTo("First attempt failed"));
    
    // Second call succeeds
    stubFor(post(urlEqualTo("/api/payments/charge"))
        .inScenario("Retry Test")
        .whenScenarioStateIs("First attempt failed")
        .willReturn(aResponse().withStatus(200)
            .withBody("{\"paymentId\": \"pay_456\"}")));
    
    PaymentResult result = paymentClient.chargeWithRetry(request);
    assertThat(result.getPaymentId()).isEqualTo("pay_456");
    verify(2, postRequestedFor(urlEqualTo("/api/payments/charge")));
}
```

### 4.4 WireMock from File Stubs

```
test/resources/
└── __files/
    └── responses/
        ├── payment_success.json
        └── payment_failure.json
└── mappings/
    └── payment_charge.json
```

```json
// mappings/payment_charge.json
{
  "request": {
    "method": "POST",
    "url": "/api/payments/charge"
  },
  "response": {
    "status": 200,
    "bodyFileName": "responses/payment_success.json",
    "headers": {
      "Content-Type": "application/json"
    }
  }
}
```

---

## 5. Security Testing

### 5.1 @WithMockUser

```java
@WebMvcTest(UserController.class)
@Import(SecurityConfig.class)
class UserControllerSecurityTest {

    @Autowired
    private MockMvc mockMvc;
    
    @MockBean
    private UserService userService;
    
    @Test
    @WithMockUser(roles = "USER")
    void getProfile_authenticated_returns200() throws Exception {
        given(userService.findById(1L)).willReturn(mockUser());
        
        mockMvc.perform(get("/api/users/me"))
            .andExpect(status().isOk());
    }
    
    @Test
    @WithMockUser(roles = "ADMIN")
    void deleteUser_admin_returns204() throws Exception {
        mockMvc.perform(delete("/api/users/1"))
            .andExpect(status().isNoContent());
    }
    
    @Test
    void getProfile_unauthenticated_returns401() throws Exception {
        mockMvc.perform(get("/api/users/me"))
            .andExpect(status().isUnauthorized());
    }
    
    @Test
    @WithMockUser(roles = "USER")
    void deleteUser_insufficientRole_returns403() throws Exception {
        mockMvc.perform(delete("/api/users/1"))
            .andExpect(status().isForbidden());
    }
}
```

### 5.2 JWT Token Testing

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
class JwtSecurityIntegrationTest {

    @Autowired
    private MockMvc mockMvc;
    
    @Autowired
    private JwtTokenProvider jwtProvider;
    
    private String generateToken(String username, String... roles) {
        return jwtProvider.generateToken(UserDetails.builder()
            .username(username)
            .authorities(Arrays.stream(roles)
                .map(SimpleGrantedAuthority::new)
                .collect(Collectors.toList()))
            .build());
    }
    
    @Test
    void accessProtectedResource_validJwt_returns200() throws Exception {
        String token = generateToken("john", "ROLE_USER");
        
        mockMvc.perform(get("/api/users/me")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isOk());
    }
    
    @Test
    void accessProtectedResource_expiredJwt_returns401() throws Exception {
        // Generate expired token
        String token = Jwts.builder()
            .subject("john")
            .issuedAt(new Date(System.currentTimeMillis() - 7200_000))
            .expiration(new Date(System.currentTimeMillis() - 3600_000))
            .signWith(Keys.hmacShaKeyFor(secret.getBytes()))
            .compact();
        
        mockMvc.perform(get("/api/users/me")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isUnauthorized())
            .andExpect(jsonPath("$.error").value("Token expired"));
    }
    
    @Test
    void accessAdminEndpoint_userRole_returns403() throws Exception {
        String token = generateToken("john", "ROLE_USER");
        
        mockMvc.perform(get("/api/admin/users")
                .header("Authorization", "Bearer " + token))
            .andExpect(status().isForbidden());
    }
}
```

### 5.3 Custom @WithMockJwtUser

```java
// Custom security context factory
@Retention(RetentionPolicy.RUNTIME)
@WithSecurityContext(factory = WithMockJwtUserSecurityContextFactory.class)
public @interface WithMockJwtUser {
    String username() default "testUser";
    String[] roles() default {"ROLE_USER"};
    long userId() default 1L;
}

public class WithMockJwtUserSecurityContextFactory
        implements WithSecurityContextFactory<WithMockJwtUser> {
    
    @Override
    public SecurityContext createSecurityContext(WithMockJwtUser annotation) {
        SecurityContext context = SecurityContextHolder.createEmptyContext();
        
        List<GrantedAuthority> authorities = Arrays.stream(annotation.roles())
            .map(SimpleGrantedAuthority::new)
            .collect(Collectors.toList());
        
        // Custom JWT principal
        JwtUser principal = new JwtUser(annotation.userId(), annotation.username(), authorities);
        UsernamePasswordAuthenticationToken auth =
            new UsernamePasswordAuthenticationToken(principal, null, authorities);
        
        context.setAuthentication(auth);
        return context;
    }
}

// Usage
@Test
@WithMockJwtUser(userId = 42L, username = "alice", roles = {"ROLE_ADMIN"})
void adminAction_withJwtUser_succeeds() throws Exception {
    mockMvc.perform(delete("/api/users/1"))
        .andExpect(status().isNoContent());
}
```

---

## 6. Integration Test Strategy

### 6.1 Test Pyramid

```
         /\
        /  \
       / E2E\        ← Few, slow, expensive (Playwright/Selenium)
      /------\
     /        \
    / Integration\   ← Some, medium speed (@SpringBootTest + Testcontainers)
   /------------\
  /              \
 /   Unit Tests   \  ← Many, fast, isolated (JUnit + Mockito)
/------------------\
```

### 6.2 Integration Test Base

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Transactional
public abstract class BaseIntegrationTest {

    @Container
    @ServiceConnection
    static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");
    
    @Container
    @ServiceConnection
    static final GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
        .withExposedPorts(6379);
    
    @Autowired
    protected MockMvc mockMvc;
    
    @Autowired
    protected ObjectMapper objectMapper;
    
    // Utility helpers
    protected String toJson(Object obj) {
        try {
            return objectMapper.writeValueAsString(obj);
        } catch (JsonProcessingException e) {
            throw new RuntimeException(e);
        }
    }
    
    protected <T> T fromJson(String json, Class<T> type) {
        try {
            return objectMapper.readValue(json, type);
        } catch (JsonProcessingException e) {
            throw new RuntimeException(e);
        }
    }
    
    protected String bearerToken(String username, String... roles) {
        // generate test JWT
        return "Bearer " + jwtProvider.generateToken(username, List.of(roles));
    }
}
```

### 6.3 Full Order Flow Integration Test

```java
class OrderFlowIntegrationTest extends BaseIntegrationTest {

    @Autowired
    private UserRepository userRepository;
    @Autowired
    private OrderRepository orderRepository;
    
    @Test
    void fullOrderFlow_happyPath() throws Exception {
        // Arrange: create a user
        User user = userRepository.save(User.builder()
            .email("customer@test.com").password("hash").active(true).build());
        String token = bearerToken(user.getEmail(), "ROLE_USER");
        
        // Act: place an order
        CreateOrderRequest req = new CreateOrderRequest(
            List.of(new OrderItemRequest(1L, 2, new BigDecimal("50.00")))
        );
        
        MvcResult result = mockMvc.perform(post("/api/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content(toJson(req))
                .header("Authorization", token))
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.data.status").value("PENDING"))
            .andReturn();
        
        Long orderId = fromJson(result.getResponse().getContentAsString(),
            ApiResponse.class).getData().getId();
        
        // Assert: order exists in DB
        Optional<Order> savedOrder = orderRepository.findById(orderId);
        assertThat(savedOrder).isPresent();
        assertThat(savedOrder.get().getTotal()).isEqualByComparingTo("100.00");
        
        // Assert: can retrieve it
        mockMvc.perform(get("/api/orders/{id}", orderId)
                .header("Authorization", token))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.data.id").value(orderId));
    }
}
```

### 6.4 application-test.yml

```yaml
# src/test/resources/application-test.yml
spring:
  jpa:
    show-sql: true
    properties:
      hibernate:
        format_sql: true
  flyway:
    clean-disabled: false  # allow flyway clean in tests
    
logging:
  level:
    org.springframework.web: DEBUG
    org.hibernate.SQL: DEBUG

# Override external service URLs for WireMock
payment:
  service:
    url: http://localhost:${wiremock.server.port}
```

### 6.5 Test Performance Tips

```java
// 1. Reuse Spring context with @DirtiesContext sparingly
// 2. Use @TestConfiguration to override beans without full reload
@TestConfiguration
static class TestConfig {
    @Bean
    @Primary
    public EmailService mockEmailService() {
        return Mockito.mock(EmailService.class);
    }
}

// 3. Profile-based test config
@SpringBootTest(properties = {
    "feature.notifications.enabled=false",
    "async.processing.enabled=false"
})

// 4. Parallel test execution
// src/test/resources/junit-platform.properties
// junit.jupiter.execution.parallel.enabled=true
// junit.jupiter.execution.parallel.config.strategy=dynamic

// 5. Reuse containers with static fields (already covered above)
// Static containers = one Docker container for all tests in the class hierarchy
```

---

## Summary: Testing Cheatsheet

| Annotation | Loads | Use For |
|------------|-------|---------|
| `@WebMvcTest` | Controllers + Security | Controller unit tests |
| `@DataJpaTest` | JPA + Hibernate | Repository tests |
| `@DataRedisTest` | Redis repositories | Redis component tests |
| `@JsonTest` | Jackson | Serialization tests |
| `@RestClientTest` | HTTP clients | REST client tests |
| `@SpringBootTest` | Full context | Integration tests |
| `@MockBean` | N/A | Mock Spring bean in context |
| `@SpyBean` | N/A | Spy (partial mock) on Spring bean |
| `@WithMockUser` | N/A | Fake authenticated user |
| `@Transactional` on test | N/A | Auto-rollback after each test |
| `@Sql` | N/A | Execute SQL before/after test |
| `@DirtiesContext` | N/A | Force context reload (expensive!) |
