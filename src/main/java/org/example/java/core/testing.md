# Java Testing – JUnit 5, Mockito, Integration Testing

## Mục lục
1. [JUnit 5 – Testing Framework](#1-junit-5--testing-framework)
2. [Mockito – Mocking Framework](#2-mockito--mocking-framework)
3. [AssertJ – Fluent Assertions](#3-assertj--fluent-assertions)
4. [Test Doubles – Mock vs Stub vs Spy vs Fake](#4-test-doubles--mock-vs-stub-vs-spy-vs-fake)
5. [Spring Test Slices](#5-spring-test-slices)
6. [Testcontainers – Integration Testing](#6-testcontainers--integration-testing)
7. [Test Strategy & Best Practices](#7-test-strategy--best-practices)

---

## 1. JUnit 5 – Testing Framework

### 1.1 Architecture

```
JUnit 5 = JUnit Platform + JUnit Jupiter + JUnit Vintage

JUnit Platform:  launcher, TestEngine SPI (pluggable: Spock, Cucumber)
JUnit Jupiter:   new @Test API (Java 8+), annotations, extensions
JUnit Vintage:   backward compatibility runner for JUnit 3/4

<!-- pom.xml -->
<dependency>
  <groupId>org.junit.jupiter</groupId>
  <artifactId>junit-jupiter</artifactId>       <!-- all-in-one: Jupiter API + Engine -->
  <scope>test</scope>
</dependency>
<!-- Maven Surefire >= 2.22.0 auto-discovers JUnit 5 tests -->
```

### 1.2 Core Annotations

```java
import org.junit.jupiter.api.*;

class OrderServiceTest {

    // ── Lifecycle ────────────────────────────────────────────────────────
    @BeforeAll     // once per class, must be static (unless @TestInstance(PER_CLASS))
    static void setupDatabase() { ... }

    @AfterAll
    static void teardownDatabase() { ... }

    @BeforeEach    // before every test method
    void setUp() { ... }

    @AfterEach
    void tearDown() { ... }

    // ── Test Methods ──────────────────────────────────────────────────────
    @Test
    @DisplayName("Should create order with valid items")
    void createOrder_withValidItems_succeeds() {
        // Arrange – Act – Assert
        var items = List.of(new OrderItem("SKU-001", 2, BigDecimal.valueOf(29.99)));
        var order = orderService.create(new CreateOrderRequest(customerId, items));

        assertNotNull(order.id());
        assertEquals(OrderStatus.PENDING, order.status());
    }

    @Test
    @Disabled("Known bug JIRA-123, fix by 2024-Q2")
    void createOrder_withExpiredVoucher_throwsException() { }

    // ── Assertions ────────────────────────────────────────────────────────
    @Test
    void assertions_showcase() {
        // Basic
        assertEquals(expected, actual, "message on failure");
        assertNotEquals(unexpected, actual);
        assertTrue(condition, "should be true");
        assertFalse(condition);
        assertNull(value);
        assertNotNull(value);

        // Exception assertion
        var ex = assertThrows(IllegalArgumentException.class,
            () -> orderService.create(null));
        assertEquals("Request must not be null", ex.getMessage());

        // No exception
        assertDoesNotThrow(() -> orderService.findById(validId));

        // Grouped (all run even if some fail):
        assertAll("order properties",
            () -> assertNotNull(order.id()),
            () -> assertEquals(customerId, order.customerId()),
            () -> assertEquals(OrderStatus.PENDING, order.status())
        );

        // Timeout
        assertTimeout(Duration.ofSeconds(2),
            () -> orderService.processLargeOrder(bigOrder));
    }
}
```

### 1.3 Parameterized Tests

```java
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.*;

class PriceCalculatorTest {

    // ── @ValueSource ──────────────────────────────────────────────────────
    @ParameterizedTest
    @ValueSource(ints = {1, 2, 5, 10, 100})
    void calculateDiscount_withPositiveQuantity_returnsDiscount(int quantity) {
        assertTrue(calculator.calculateDiscount(quantity) >= 0);
    }

    // ── @CsvSource ────────────────────────────────────────────────────────
    @ParameterizedTest(name = "qty={0}, price={1} → total={2}")
    @CsvSource({
        "1,  10.00, 10.00",
        "2,  10.00, 20.00",
        "10, 10.00, 90.00",   // 10% bulk discount
    })
    void calculateTotal(int qty, BigDecimal unitPrice, BigDecimal expected) {
        assertEquals(expected, calculator.total(qty, unitPrice));
    }

    // ── @CsvFileSource ────────────────────────────────────────────────────
    @ParameterizedTest
    @CsvFileSource(resources = "/test-data/price-cases.csv", numLinesToSkip = 1)
    void calculateTotalFromFile(int qty, BigDecimal price, BigDecimal expected) {
        assertEquals(expected, calculator.total(qty, price));
    }

    // ── @MethodSource ─────────────────────────────────────────────────────
    @ParameterizedTest
    @MethodSource("invalidOrderRequests")
    void createOrder_withInvalidRequest_throwsValidationException(CreateOrderRequest request, String expectedMsg) {
        var ex = assertThrows(ValidationException.class, () -> service.create(request));
        assertThat(ex.getMessage()).contains(expectedMsg);
    }

    private static Stream<Arguments> invalidOrderRequests() {
        return Stream.of(
            Arguments.of(new CreateOrderRequest(null, List.of()),   "customerId"),
            Arguments.of(new CreateOrderRequest(1L, List.of()),     "items"),
            Arguments.of(new CreateOrderRequest(-1L, List.of(item())), "customerId must be positive")
        );
    }

    // ── @EnumSource ───────────────────────────────────────────────────────
    @ParameterizedTest
    @EnumSource(value = OrderStatus.class, names = {"CANCELLED", "REFUNDED"})
    void cannotModify_cancelledOrRefundedOrder(OrderStatus status) {
        var order = new Order(status);
        assertThrows(IllegalStateException.class, () -> service.addItem(order, item()));
    }

    // ── @NullAndEmptySource ───────────────────────────────────────────────
    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"  ", "\t", "\n"})
    void validate_blankProductName_throwsException(String name) {
        assertThrows(IllegalArgumentException.class, () -> validator.validateName(name));
    }
}
```

### 1.4 Extensions & Custom Annotations

```java
// ── Extension API ─────────────────────────────────────────────────────────
public class TimingExtension implements BeforeEachCallback, AfterEachCallback {
    private static final ExtensionContext.Namespace NS =
        ExtensionContext.Namespace.create(TimingExtension.class);

    @Override
    public void beforeEach(ExtensionContext ctx) {
        ctx.getStore(NS).put("startTime", System.currentTimeMillis());
    }

    @Override
    public void afterEach(ExtensionContext ctx) {
        long elapsed = System.currentTimeMillis() - ctx.getStore(NS).get("startTime", long.class);
        System.out.printf("[%s] took %dms%n", ctx.getDisplayName(), elapsed);
    }
}

// ── Custom annotation ─────────────────────────────────────────────────────
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@Test
@Tag("slow")
@Timeout(value = 30, unit = TimeUnit.SECONDS)
public @interface SlowTest { }

// ── Use ───────────────────────────────────────────────────────────────────
@ExtendWith(TimingExtension.class)
class IntegrationTest {
    @SlowTest
    void processLargeDataset() { ... }
}

// ── Test Instance Lifecycle ───────────────────────────────────────────────
@TestInstance(TestInstance.Lifecycle.PER_CLASS)  // one instance per class (not per method)
class ExpensiveSetupTest {
    private final List<String> sharedData = new ArrayList<>();

    @BeforeAll  // no need for static when PER_CLASS
    void setupOnce() {
        sharedData.addAll(loadExpensiveData());
    }

    @Test
    void test1() { /* uses sharedData */ }
}

// ── Nested Tests for describe/it style ───────────────────────────────────
class OrderServiceTest {
    @Nested
    @DisplayName("when order is pending")
    class WhenPending {
        @Test void canBeCancelled() { ... }
        @Test void canBeConfirmed() { ... }

        @Nested
        @DisplayName("and payment fails")
        class AndPaymentFails {
            @Test void orderIsRevertedToPending() { ... }
        }
    }

    @Nested
    @DisplayName("when order is shipped")
    class WhenShipped {
        @Test void cannotBeCancelled() { ... }
    }
}
```

---

## 2. Mockito – Mocking Framework

### 2.1 Setup & Basic Mocking

```java
// 3 ways to set up mocks:
// 1. Annotation-based (preferred)
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock
    private OrderRepository orderRepository;

    @Mock
    private PaymentService paymentService;

    @InjectMocks                // creates OrderService, injects mocks via constructor/setter/field
    private OrderService orderService;

    // 2. Programmatic
    OrderRepository repo = Mockito.mock(OrderRepository.class);

    // 3. Static factory with lambda (Java 8+)
    OrderRepository repo = mock(OrderRepository.class, invocation -> {
        throw new RuntimeException("Unexpected call: " + invocation.getMethod().getName());
    });
}
```

### 2.2 Stubbing – When / Then

```java
@Test
void findOrder_existingId_returnsOrder() {
    // Arrange: stub the mock
    var orderId = 42L;
    var expectedOrder = new Order(orderId, OrderStatus.PENDING);

    when(orderRepository.findById(orderId))
        .thenReturn(Optional.of(expectedOrder));

    // Act
    var result = orderService.findOrder(orderId);

    // Assert
    assertEquals(expectedOrder, result);
}

// ── Multiple stubs ────────────────────────────────────────────────────────
when(orderRepository.findById(anyLong()))
    .thenReturn(Optional.of(order))          // first call
    .thenReturn(Optional.empty())            // second call
    .thenThrow(new DataAccessException("DB down")); // third call

// ── thenAnswer: dynamic response ─────────────────────────────────────────
when(orderRepository.save(any(Order.class)))
    .thenAnswer(invocation -> {
        Order o = invocation.getArgument(0);
        return o.withId(ThreadLocalRandom.current().nextLong(1, 1000));
    });

// ── Exception stubbing ────────────────────────────────────────────────────
when(paymentService.charge(anyLong(), any()))
    .thenThrow(new PaymentException("Card declined"));

// ── void method stubbing ──────────────────────────────────────────────────
doThrow(new EmailException("SMTP down"))
    .when(emailService).sendOrderConfirmation(any());

doNothing().when(emailService).sendOrderConfirmation(any());  // explicitly do nothing

doAnswer(invocation -> {
    Order o = invocation.getArgument(0);
    log.info("Email sent for order {}", o.id());
    return null;
}).when(emailService).sendOrderConfirmation(any());

// ── Argument Matchers ─────────────────────────────────────────────────────
when(repo.findByCustomerIdAndStatus(
    eq(100L),                           // exact value
    eq(OrderStatus.PENDING)
)).thenReturn(List.of(order));

when(repo.searchByQuery(
    argThat(query -> query.keywords().contains("laptop")),  // custom matcher
    any(Pageable.class)
)).thenReturn(page);
```

### 2.3 Verification

```java
@Test
void createOrder_validRequest_savesAndPublishesEvent() {
    // Act
    orderService.create(request);

    // Verify interaction count
    verify(orderRepository, times(1)).save(any(Order.class));
    verify(eventPublisher, once()).publish(any(OrderCreatedEvent.class));  // once() = times(1)
    verify(emailService, never()).sendCancellationEmail(any());

    // Verify argument content
    verify(orderRepository).save(argThat(order ->
        order.status() == OrderStatus.PENDING &&
        order.customerId() == request.customerId()
    ));

    // Ordered verification (interactions must happen in this order)
    var inOrder = inOrder(orderRepository, eventPublisher);
    inOrder.verify(orderRepository).save(any());
    inOrder.verify(eventPublisher).publish(any());

    // No other interactions
    verifyNoMoreInteractions(orderRepository);
    verifyNoInteractions(smsService);  // zero interactions total
}
```

### 2.4 ArgumentCaptor – Capture & Inspect

```java
@Test
void createOrder_capturesPublishedEvent() {
    orderService.create(request);

    // Capture what was passed to eventPublisher
    var eventCaptor = ArgumentCaptor.forClass(OrderCreatedEvent.class);
    verify(eventPublisher).publish(eventCaptor.capture());

    var capturedEvent = eventCaptor.getValue();
    assertEquals(request.customerId(), capturedEvent.customerId());
    assertNotNull(capturedEvent.orderId());
    assertTrue(capturedEvent.timestamp().isBefore(Instant.now()));
}

// Capture multiple invocations
verify(emailService, times(3)).send(emailCaptor.capture());
List<Email> emails = emailCaptor.getAllValues();
assertEquals(3, emails.size());
```

### 2.5 Spy – Partial Mocking

```java
// Spy: wraps REAL object, intercept only specific methods
@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Spy
    private List<OrderItem> items = new ArrayList<>();  // real ArrayList

    @Spy
    @InjectMocks
    private OrderService orderService;  // real service, some methods mocked

    @Test
    void test() {
        // Real methods work normally
        items.add(new OrderItem(...));
        assertEquals(1, items.size());  // real size()

        // Stub specific methods of spy
        doReturn(BigDecimal.TEN).when(orderService).calculateDiscount(any());
        // Don't use when(spy.method()) for spies — calls real method!
        // Always use doReturn().when() with spies
    }
}

// Programmatic spy:
List<String> spyList = spy(new ArrayList<>());
spyList.add("hello");                       // real method
doReturn(100).when(spyList).size();         // stubbed
```

### 2.6 MockedStatic & MockedConstruction (Mockito 3.4+)

```java
// Mock static methods
try (MockedStatic<UUID> mockedUUID = mockStatic(UUID.class)) {
    var fixedUUID = UUID.fromString("550e8400-e29b-41d4-a716-446655440000");
    mockedUUID.when(UUID::randomUUID).thenReturn(fixedUUID);

    var result = orderService.createOrderWithId();
    assertEquals(fixedUUID.toString(), result.id());
}

// Mock constructor (new ClassName())
try (MockedConstruction<PaymentGateway> mocked = mockConstruction(PaymentGateway.class,
    (mock, context) -> {
        when(mock.charge(anyLong())).thenReturn(PaymentResult.SUCCESS);
    })) {
    orderService.processPayment(order);  // internally creates new PaymentGateway()
    // The constructed mock received the charge() call
}
```

---

## 3. AssertJ – Fluent Assertions

```java
import static org.assertj.core.api.Assertions.*;

// ── Basic ─────────────────────────────────────────────────────────────────
assertThat(actual)
    .isNotNull()
    .isEqualTo(expected)
    .isInstanceOf(OrderService.class)
    .isNotSameAs(anotherObject);

// ── String ────────────────────────────────────────────────────────────────
assertThat(errorMessage)
    .isNotBlank()
    .startsWith("Error:")
    .contains("customerId")
    .matches("Error: .+ is invalid")
    .hasSize(20)
    .doesNotContain("password");

// ── Numbers ───────────────────────────────────────────────────────────────
assertThat(price)
    .isPositive()
    .isGreaterThan(BigDecimal.ZERO)
    .isLessThanOrEqualTo(new BigDecimal("999.99"))
    .isCloseTo(new BigDecimal("10.00"), within(new BigDecimal("0.01")));

// ── Collections ───────────────────────────────────────────────────────────
assertThat(orders)
    .isNotEmpty()
    .hasSize(3)
    .containsExactly(order1, order2, order3)             // exact order
    .containsExactlyInAnyOrder(order3, order1, order2)   // any order
    .contains(order1, order2)                             // at least these
    .doesNotContain(cancelledOrder)
    .allSatisfy(o -> assertThat(o.status()).isNotNull())
    .anySatisfy(o -> assertThat(o.total()).isGreaterThan(BigDecimal.valueOf(100)))
    .filteredOn(o -> o.status() == PENDING).hasSize(2)
    .extracting(Order::customerId).containsOnly(42L);

// ── Exceptions ────────────────────────────────────────────────────────────
assertThatThrownBy(() -> service.create(null))
    .isInstanceOf(IllegalArgumentException.class)
    .hasMessageContaining("null")
    .hasCauseInstanceOf(NullPointerException.class);

assertThatExceptionOfType(ValidationException.class)
    .isThrownBy(() -> validator.validate(badRequest))
    .withMessage("Validation failed")
    .satisfies(ex -> assertThat(ex.getErrors()).hasSize(2));

// No exception
assertThatCode(() -> service.create(validRequest))
    .doesNotThrowAnyException();

// ── Objects ───────────────────────────────────────────────────────────────
assertThat(order)
    .hasFieldOrPropertyWithValue("status", PENDING)
    .satisfies(o -> {
        assertThat(o.id()).isNotNull();
        assertThat(o.createdAt()).isBeforeOrEqualTo(Instant.now());
    });

// ── SoftAssertions (collect all failures) ────────────────────────────────
SoftAssertions.assertSoftly(softly -> {
    softly.assertThat(order.id()).isNotNull();
    softly.assertThat(order.status()).isEqualTo(PENDING);
    softly.assertThat(order.total()).isPositive();
    // All 3 checked, all failures reported
});
```

---

## 4. Test Doubles – Mock vs Stub vs Spy vs Fake

```
Test Double taxonomy (Martin Fowler):

Dummy:   passed but never used (null, empty object)
         → fill required parameters

Stub:    returns canned responses, no verification
         → control indirect inputs to unit under test

Mock:    pre-programmed with expectations, verified after
         → verify indirect outputs (what methods were called)

Spy:     real object with selective override + optional verification
         → partial mocking, legacy code

Fake:    working implementation with shortcuts (in-memory DB)
         → faster integration tests

When to use what:
  Unit tests: Mock/Stub (control all dependencies)
  Integration tests: Fake (in-memory repo, embedded DB)
  Component tests: Spy (test real service, mock external)
```

```java
// Dummy
service.createOrder(request, null /* auditContext — unused */);

// Stub (via Mockito when-thenReturn)
when(repo.findById(1L)).thenReturn(Optional.of(expectedOrder));

// Fake: in-memory repository implementation
class InMemoryOrderRepository implements OrderRepository {
    private final Map<Long, Order> store = new ConcurrentHashMap<>();
    private final AtomicLong idSeq = new AtomicLong(1);

    @Override
    public Order save(Order order) {
        var id = order.id() != null ? order.id() : idSeq.getAndIncrement();
        var saved = order.withId(id);
        store.put(id, saved);
        return saved;
    }

    @Override
    public Optional<Order> findById(Long id) {
        return Optional.ofNullable(store.get(id));
    }
}
// Use in test:
var repo = new InMemoryOrderRepository();
var service = new OrderService(repo, eventPublisher);
```

---

## 5. Spring Test Slices

### 5.1 @WebMvcTest – Controller Layer Only

```java
@WebMvcTest(OrderController.class)  // loads only web layer, no service/repo beans
class OrderControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean   // replaces real bean in context with Mockito mock
    private OrderService orderService;

    @Autowired
    private ObjectMapper objectMapper;

    @Test
    void createOrder_validRequest_returns201() throws Exception {
        var request = new CreateOrderRequest(1L, List.of(item()));
        var response = new OrderResponse(42L, PENDING, BigDecimal.TEN);

        when(orderService.create(any())).thenReturn(response);

        mockMvc.perform(
            post("/api/orders")
                .contentType(APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(request))
                .header("Authorization", "Bearer test-token")
            )
            .andExpect(status().isCreated())
            .andExpect(header().string("Location", "/api/orders/42"))
            .andExpect(jsonPath("$.id").value(42))
            .andExpect(jsonPath("$.status").value("PENDING"))
            .andExpect(content().contentType(APPLICATION_JSON));
    }

    @Test
    void createOrder_invalidRequest_returns400() throws Exception {
        var badRequest = new CreateOrderRequest(null, List.of()); // missing customerId

        mockMvc.perform(
            post("/api/orders")
                .contentType(APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(badRequest))
            )
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.errors").isArray());
    }

    @Test
    void getOrder_notFound_returns404() throws Exception {
        when(orderService.findOrder(999L))
            .thenThrow(new OrderNotFoundException(999L));

        mockMvc.perform(get("/api/orders/999"))
            .andExpect(status().isNotFound())
            .andExpect(jsonPath("$.message").value("Order 999 not found"));
    }
}
```

### 5.2 @DataJpaTest – Repository Layer Only

```java
@DataJpaTest                         // loads only JPA, embedded H2 by default
@AutoConfigureTestDatabase(replace = Replace.NONE)  // use real DB (Testcontainers)
@Import(JpaAuditingConfig.class)     // import only what's needed
class OrderRepositoryTest {

    @Autowired
    private TestEntityManager em;

    @Autowired
    private OrderRepository orderRepository;

    @Test
    @Transactional
    void findByCustomerIdAndStatus_returnsMatchingOrders() {
        // Arrange: persist test data
        var customer1 = em.persist(new Customer(null, "Alice"));
        var order1 = em.persist(new Order(null, customer1.id(), PENDING, BigDecimal.TEN));
        var order2 = em.persist(new Order(null, customer1.id(), SHIPPED, BigDecimal.valueOf(50)));
        em.flush();

        // Act
        var pendingOrders = orderRepository.findByCustomerIdAndStatus(customer1.id(), PENDING);

        // Assert
        assertThat(pendingOrders).hasSize(1);
        assertThat(pendingOrders.get(0).id()).isEqualTo(order1.id());
    }

    @Test
    void findTopRevenueCustomers_returnsCorrectProjection() {
        // ... setup ...
        var results = orderRepository.findTopRevenueCustomers(Pageable.ofSize(5));
        assertThat(results).hasSize(5)
            .extracting(RevenueProjection::totalRevenue)
            .isSortedAccordingTo(Comparator.reverseOrder());
    }
}
```

### 5.3 @SpringBootTest – Full Integration

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")
class OrderApiIntegrationTest {

    @Autowired
    private TestRestTemplate restTemplate;

    @Autowired
    private OrderRepository orderRepository;

    @LocalServerPort
    private int port;

    @BeforeEach
    void setUp() {
        orderRepository.deleteAll();
    }

    @Test
    void fullOrderFlow_createConfirmShip_success() {
        // Create
        var createRequest = new CreateOrderRequest(1L, List.of(item("SKU-001", 2)));
        var createResponse = restTemplate.postForEntity(
            "/api/orders", createRequest, OrderResponse.class);
        assertEquals(HttpStatus.CREATED, createResponse.getStatusCode());
        var orderId = createResponse.getBody().id();

        // Confirm
        var confirmResponse = restTemplate.postForEntity(
            "/api/orders/{id}/confirm", null, OrderResponse.class, orderId);
        assertEquals(HttpStatus.OK, confirmResponse.getStatusCode());
        assertEquals(CONFIRMED, confirmResponse.getBody().status());

        // Verify in DB
        var dbOrder = orderRepository.findById(orderId).orElseThrow();
        assertEquals(CONFIRMED, dbOrder.status());
    }
}
```

---

## 6. Testcontainers – Integration Testing

### 6.1 Database Integration

```java
@SpringBootTest
@Testcontainers
class OrderRepositoryIntegrationTest {

    @Container
    static final PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:15-alpine")
            .withDatabaseName("testdb")
            .withUsername("test")
            .withPassword("test");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired
    private OrderRepository orderRepository;

    @Test
    void save_andRetrieve_order() {
        var order = new Order(null, 1L, PENDING, BigDecimal.TEN);
        var saved = orderRepository.save(order);
        var found = orderRepository.findById(saved.id());

        assertThat(found).isPresent()
            .get()
            .satisfies(o -> {
                assertThat(o.customerId()).isEqualTo(1L);
                assertThat(o.status()).isEqualTo(PENDING);
            });
    }
}

// Spring Boot 3.1+ @ServiceConnection (auto-configures datasource):
@SpringBootTest
@Testcontainers
class ModernTestcontainersTest {

    @Container
    @ServiceConnection
    static final PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:15");

    // No @DynamicPropertySource needed — @ServiceConnection handles it!
}
```

### 6.2 Multi-container Tests

```java
@SpringBootTest
@Testcontainers
class FullStackIntegrationTest {

    @Container
    @ServiceConnection
    static final PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15");

    @Container
    @ServiceConnection
    static final RedisContainer redis = new RedisContainer("redis:7-alpine");

    @Container
    static final KafkaContainer kafka =
        new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.4.0"));

    @DynamicPropertySource
    static void kafkaProps(DynamicPropertyRegistry reg) {
        reg.add("spring.kafka.bootstrap-servers", kafka::getBootstrapServers);
    }

    // Tests use real Postgres + Redis + Kafka
}
```

### 6.3 Reusable Base Test Class

```java
@SpringBootTest(webEnvironment = RANDOM_PORT)
@ActiveProfiles("integration-test")
@Testcontainers
abstract class AbstractIntegrationTest {

    @Container
    @ServiceConnection
    static final PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:15-alpine");

    @Container
    @ServiceConnection
    static final RedisContainer redis = new RedisContainer("redis:7-alpine");

    // Container is started ONCE (static) and shared across all subclass tests
    // JUnit5 lifecycle: @Container on static field = once per class hierarchy
}

// Concrete test:
class OrderServiceIntegrationTest extends AbstractIntegrationTest {
    @Autowired OrderService orderService;

    @Test
    void test() { /* uses real Postgres + Redis */ }
}
```

---

## 7. Test Strategy & Best Practices

### 7.1 Test Pyramid

```
                     ┌────────────┐
                     │   E2E/UI   │  few, slow, flaky
                     │   (Selenium│  but high confidence
                     └─────┬──────┘
               ┌───────────┴──────────┐
               │  Integration Tests   │  some, medium speed
               │  (@SpringBootTest    │  real DB/broker
               │   Testcontainers)    │
               └──────────┬───────────┘
          ┌────────────────┴───────────────┐
          │         Unit Tests             │  many, fast, isolated
          │  (@ExtendWith(Mockito), JUnit)  │  all dependencies mocked
          └────────────────────────────────┘

Rule of thumb: 70% unit / 20% integration / 10% E2E
```

### 7.2 Test Naming & Structure

```java
// Naming: method_condition_expectation
// or: should_doX_when_conditionY

@Test
void createOrder_withNullRequest_throwsIllegalArgument() { }

@Test
void getOrderTotal_withBulkDiscount_appliesCorrectPercentage() { }

// Given-When-Then (BDD style) inside each test:
@Test
void applyVoucher_validCode_deductsFromTotal() {
    // Given
    var order = orderWithTotal(BigDecimal.valueOf(100));
    var voucher = new Voucher("SAVE10", DiscountType.PERCENT, BigDecimal.TEN);

    // When
    var discountedOrder = orderService.applyVoucher(order, voucher);

    // Then
    assertThat(discountedOrder.total()).isEqualByComparingTo("90.00");
}
```

### 7.3 Common Anti-patterns

```java
// ❌ Anti-pattern 1: Testing implementation, not behavior
verify(userMapper, times(1)).toEntity(any());  // testing HOW, not WHAT

// ✅ Test the outcome:
assertThat(savedUser.email()).isEqualTo(request.email());

// ❌ Anti-pattern 2: Over-mocking (mock everything including simple objects)
when(mockUser.getEmail()).thenReturn("test@example.com");  // just create real User

// ✅ Use real objects for simple value objects:
var user = new User(1L, "test@example.com");

// ❌ Anti-pattern 3: Non-deterministic tests
var timestamp = System.currentTimeMillis();  // flaky! depends on system time

// ✅ Use fixed clock:
var clock = Clock.fixed(Instant.parse("2024-01-01T00:00:00Z"), UTC);
var service = new OrderService(repo, clock);

// ❌ Anti-pattern 4: Large test with too many assertions (hard to debug)
// ✅ One test = one behavior. Multiple fine-grained tests

// ❌ Anti-pattern 5: Test database state leaking between tests
// ✅ @Transactional on test or @BeforeEach cleanup

// ❌ Anti-pattern 6: Asserting on toString() or hashCode()
// ✅ Assert on actual domain fields

// ❌ Anti-pattern 7: Mocking third-party types you don't own
when(mockHttpResponse.getStatusCode()).thenReturn(200);  // mock HttpResponse
// ✅ Use WireMock or wrap third-party in your own interface
```

### 7.4 Test Coverage & Mutation Testing

```xml
<!-- JaCoCo: line/branch coverage -->
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <executions>
    <execution>
      <goals><goal>prepare-agent</goal></goals>
    </execution>
    <execution>
      <id>report</id>
      <phase>test</phase>
      <goals><goal>report</goal></goals>
    </execution>
    <execution>
      <id>check</id>
      <goals><goal>check</goal></goals>
      <configuration>
        <rules>
          <rule>
            <element>PACKAGE</element>
            <limits>
              <limit><counter>LINE</counter><value>COVEREDRATIO</value><minimum>0.80</minimum></limit>
              <limit><counter>BRANCH</counter><value>COVEREDRATIO</value><minimum>0.75</minimum></limit>
            </limits>
          </rule>
        </rules>
      </configuration>
    </execution>
  </executions>
</plugin>

<!-- PITest: mutation testing (better than coverage) -->
<plugin>
  <groupId>org.pitest</groupId>
  <artifactId>pitest-maven</artifactId>
  <configuration>
    <mutationThreshold>75</mutationThreshold>
    <targetClasses><param>com.example.order.*</param></targetClasses>
  </configuration>
</plugin>
```

---

## Ghi chú – Keywords tiếp theo

- **Testing Patterns**: Test Data Builder, Object Mother, Test Fixtures, BDD (Cucumber/Given-When-Then)
- **Keywords**: JUnit 5 Extension API, Mockito strict stubbing, ArgumentCaptor, @Captor, InOrder verification, MockedStatic, MockedConstruction, AssertJ SoftAssertions, @WebMvcTest MockMvc, @DataJpaTest TestEntityManager, @DataRedisTest, @JsonTest, Testcontainers @ServiceConnection, WireMock (HTTP stubbing), ArchUnit (architecture tests), Mutation testing (PITest), JaCoCo coverage
