# Spring Boot Web Layer

## 1. REST API Best Practices

### 1.1 Response Structure & Global Exception Handler

```java
// Standard API response wrapper
@Getter
@Builder
public class ApiResponse<T> {
    private final boolean success;
    private final T data;
    private final String message;
    private final List<FieldError> errors;
    private final String traceId;
    private final Instant timestamp;

    public static <T> ApiResponse<T> ok(T data) {
        return ApiResponse.<T>builder()
            .success(true).data(data).timestamp(Instant.now()).build();
    }

    public static <T> ApiResponse<T> error(String message, List<FieldError> errors) {
        return ApiResponse.<T>builder()
            .success(false).message(message).errors(errors).timestamp(Instant.now()).build();
    }

    @Getter @Builder
    public static class FieldError {
        private final String field;
        private final Object rejectedValue;
        private final String message;
    }
}

// Global Exception Handler
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    @ResponseStatus(HttpStatus.BAD_REQUEST)
    public ApiResponse<Void> handleValidation(MethodArgumentNotValidException ex,
                                               HttpServletRequest request) {
        List<ApiResponse.FieldError> errors = ex.getBindingResult()
            .getFieldErrors()
            .stream()
            .map(err -> ApiResponse.FieldError.builder()
                .field(err.getField())
                .rejectedValue(err.getRejectedValue())
                .message(err.getDefaultMessage())
                .build())
            .toList();

        log.warn("Validation failed on {}: {}", request.getRequestURI(), errors);
        return ApiResponse.error("Validation failed", errors);
    }

    @ExceptionHandler(EntityNotFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public ApiResponse<Void> handleNotFound(EntityNotFoundException ex) {
        return ApiResponse.error(ex.getMessage(), null);
    }

    @ExceptionHandler(AccessDeniedException.class)
    @ResponseStatus(HttpStatus.FORBIDDEN)
    public ApiResponse<Void> handleAccessDenied(AccessDeniedException ex) {
        return ApiResponse.error("Access denied", null);
    }

    @ExceptionHandler(DuplicateKeyException.class)
    @ResponseStatus(HttpStatus.CONFLICT)
    public ApiResponse<Void> handleDuplicate(DuplicateKeyException ex) {
        return ApiResponse.error("Resource already exists", null);
    }

    @ExceptionHandler(Exception.class)
    @ResponseStatus(HttpStatus.INTERNAL_SERVER_ERROR)
    public ApiResponse<Void> handleAll(Exception ex, HttpServletRequest request) {
        String traceId = MDC.get("traceId");
        log.error("Unhandled exception on {} [traceId={}]", request.getRequestURI(), traceId, ex);
        return ApiResponse.<Void>builder()
            .success(false)
            .message("Internal server error")
            .traceId(traceId)
            .timestamp(Instant.now())
            .build();
    }
}
```

### 1.1b ProblemDetail – RFC 9457 (Spring Boot 3+)

Spring Boot 3 hỗ trợ chuẩn `ProblemDetail` (RFC 9457 / RFC 7807) thay thế cho custom wrapper:

```yaml
spring:
  mvc:
    problemdetails:
      enabled: true   # Spring tự dùng ProblemDetail cho built-in exceptions
```

```java
// ProblemDetail-based exception handler (alternative to ApiResponse<T>)
@RestControllerAdvice
public class ProblemDetailExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ProblemDetail> handleValidation(
            MethodArgumentNotValidException ex, HttpServletRequest request) {

        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST, "Request validation failed"
        );
        problem.setTitle("Validation Error");
        problem.setType(URI.create("https://api.example.com/errors/validation"));
        problem.setInstance(URI.create(request.getRequestURI()));
        problem.setProperty("timestamp", Instant.now());
        problem.setProperty("errors", ex.getBindingResult().getFieldErrors().stream()
            .map(fe -> Map.of("field", fe.getField(), "message", fe.getDefaultMessage()))
            .toList());

        return ResponseEntity.badRequest().body(problem);
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ProblemDetail> handleConstraintViolation(ConstraintViolationException ex) {
        ProblemDetail problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.BAD_REQUEST, "Constraint violation"
        );
        problem.setProperty("errors", ex.getConstraintViolations().stream()
            .map(v -> Map.of("field", v.getPropertyPath().toString(), "message", v.getMessage()))
            .toList());
        return ResponseEntity.badRequest().body(problem);
    }
}
```

```json
// Response format (RFC 9457):
{
  "type": "https://api.example.com/errors/validation",
  "title": "Validation Error",
  "status": 400,
  "detail": "Request validation failed",
  "instance": "/api/users",
  "timestamp": "2024-01-15T10:30:00Z",
  "errors": [
    { "field": "email", "message": "Must be a valid email" },
    { "field": "password", "message": "Must contain at least 1 uppercase letter" }
  ]
}
```

### 1.1c Business Exception Hierarchy

```java
// Base exception — carries HTTP status + error code
public abstract class ApplicationException extends RuntimeException {
    private final String errorCode;
    private final HttpStatus httpStatus;

    protected ApplicationException(String errorCode, String message, HttpStatus status) {
        super(message);
        this.errorCode = errorCode;
        this.httpStatus = status;
    }
}

public class ResourceNotFoundException extends ApplicationException {
    public ResourceNotFoundException(String resource, Object id) {
        super("RESOURCE_NOT_FOUND",
              String.format("%s with id '%s' not found", resource, id),
              HttpStatus.NOT_FOUND);
    }
}

public class DuplicateResourceException extends ApplicationException {
    public DuplicateResourceException(String resource, String field, Object value) {
        super("DUPLICATE_RESOURCE",
              String.format("%s with %s '%s' already exists", resource, field, value),
              HttpStatus.CONFLICT);
    }
}

public class BusinessRuleException extends ApplicationException {
    public BusinessRuleException(String errorCode, String message) {
        super(errorCode, message, HttpStatus.UNPROCESSABLE_ENTITY);
    }
}

// Generic handler — works for all ApplicationException subclasses
@ExceptionHandler(ApplicationException.class)
public ResponseEntity<ApiResponse<Void>> handleApplicationException(ApplicationException ex) {
    return ResponseEntity.status(ex.getHttpStatus())
        .body(ApiResponse.error(ex.getMessage(), null));
}

// Usage in service
public void cancelOrder(Long orderId) {
    Order order = orderRepo.findById(orderId)
        .orElseThrow(() -> new ResourceNotFoundException("Order", orderId));

    if (order.getStatus() == OrderStatus.SHIPPED) {
        throw new BusinessRuleException("ORDER_ALREADY_SHIPPED",
            "Cannot cancel an order that has already been shipped");
    }
}
```

### 1.1d Filter vs Interceptor vs @ControllerAdvice

```
Request lifecycle:
HTTP → [Filter] → DispatcherServlet → [Interceptor.preHandle] 
     → Controller → [Interceptor.postHandle] 
     → [Filter] → Response
              ↓ on exception
     [@ControllerAdvice @ExceptionHandler]
```

| | Filter | Interceptor | @ControllerAdvice |
|--|--------|-------------|-------------------|
| Level | Servlet | Spring MVC | Spring MVC |
| Exception scope | Any (raw response) | Controller exceptions | @Controller exceptions only |
| Access Spring beans | Via @Autowired | Yes | Yes |
| Modify request/response | Yes (both) | Yes (pre/post) | Response body only |
| Runs outside Spring context | Yes | No | No |
| Use for | Auth token parsing, CORS, logging, encoding | Auth check, request context, audit | Error response formatting |

### 1.2 Validation Deep

```java
// Custom validator
@Documented
@Constraint(validatedBy = UniqueEmailValidator.class)
@Target({ElementType.FIELD})
@Retention(RetentionPolicy.RUNTIME)
public @interface UniqueEmail {
    String message() default "Email already registered";
    Class<?>[] groups() default {};
    Class<? extends Payload>[] payload() default {};
}

@Component
public class UniqueEmailValidator implements ConstraintValidator<UniqueEmail, String> {
    @Autowired
    private UserRepository userRepository;

    @Override
    public boolean isValid(String email, ConstraintValidatorContext context) {
        if (email == null) return true;
        return !userRepository.existsByEmail(email);
    }
}

// Validation groups (different rules for create vs update)
public interface OnCreate {}
public interface OnUpdate {}

public record UserRequest(
    @NotBlank(groups = OnCreate.class)
    @Null(groups = OnUpdate.class)  // id must be null on create
    Long id,

    @NotBlank @Email @UniqueEmail(groups = OnCreate.class)
    String email,

    @NotBlank(groups = OnCreate.class)
    @Size(min = 8, max = 100)
    String password,

    @NotBlank @Size(min = 2, max = 100)
    String name,

    @Min(0) @Max(150)
    Integer age
) {}

// Controller with validation groups
@RestController
@RequestMapping("/api/users")
public class UserController {

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<UserResponse> create(
        @Validated(OnCreate.class) @RequestBody UserRequest req) {
        return ApiResponse.ok(userService.create(req));
    }

    @PutMapping("/{id}")
    public ApiResponse<UserResponse> update(
        @PathVariable Long id,
        @Validated(OnUpdate.class) @RequestBody UserRequest req) {
        return ApiResponse.ok(userService.update(id, req));
    }
}
```

### 1.3 API Versioning Strategies

```java
// Strategy 1: URI versioning (most common, cacheable)
// GET /api/v1/users  vs  GET /api/v2/users

@RestController
@RequestMapping("/api/v1/users")
public class UserControllerV1 { }

@RestController
@RequestMapping("/api/v2/users")
public class UserControllerV2 { }

// Strategy 2: Header versioning
// GET /api/users  +  Header: X-API-Version: 2
@GetMapping(value = "/users", headers = "X-API-Version=1")
public UserResponseV1 getUsersV1() { }

@GetMapping(value = "/users", headers = "X-API-Version=2")
public UserResponseV2 getUsersV2() { }

// Strategy 3: Content negotiation (Accept header)
// Accept: application/vnd.company.v1+json
@GetMapping(value = "/users", produces = "application/vnd.company.v1+json")
public UserResponseV1 getUsersV1() { }

// Strategy 4: Query param (avoid - poor REST design)
// GET /api/users?version=2
```

---

## 2. WebFlux & Reactive Programming

### 2.1 Reactive Fundamentals

```java
// Mono<T>: 0 or 1 element
// Flux<T>: 0 to N elements

// Non-blocking controller (no thread blocking)
@RestController
@RequestMapping("/reactive/users")
public class ReactiveUserController {

    @Autowired
    private ReactiveUserService userService;

    @GetMapping("/{id}")
    public Mono<UserResponse> getUser(@PathVariable Long id) {
        return userService.findById(id)
            .map(UserResponse::from)
            .switchIfEmpty(Mono.error(new EntityNotFoundException("User " + id + " not found")));
    }

    @GetMapping
    public Flux<UserResponse> listUsers(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return userService.findAll(PageRequest.of(page, size))
            .map(UserResponse::from);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Mono<UserResponse> createUser(@Validated @RequestBody UserRequest req) {
        return userService.create(req)
            .map(UserResponse::from);
    }

    // Server-Sent Events (SSE) - push updates to client
    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<UserEvent>> streamEvents() {
        return userService.subscribeToEvents()
            .map(event -> ServerSentEvent.<UserEvent>builder()
                .id(String.valueOf(event.getId()))
                .event("user-update")
                .data(event)
                .build());
    }
}

// Reactive Service
@Service
public class ReactiveUserService {

    @Autowired
    private ReactiveUserRepository userRepository;  // R2DBC repository

    public Mono<User> findById(Long id) {
        return userRepository.findById(id);
    }

    public Flux<User> findAll(Pageable pageable) {
        return userRepository.findAllBy(pageable);
    }

    // Combining multiple reactive calls (parallel)
    public Mono<UserProfile> getUserProfile(Long userId) {
        Mono<User> userMono = userRepository.findById(userId);
        Mono<List<Order>> ordersMono = orderRepository.findByUserId(userId).collectList();
        Mono<Address> addressMono = addressRepository.findByUserId(userId);

        // zip: wait for all three, then combine
        return Mono.zip(userMono, ordersMono, addressMono)
            .map(tuple -> UserProfile.builder()
                .user(tuple.getT1())
                .orders(tuple.getT2())
                .address(tuple.getT3())
                .build());
    }

    // Error handling
    public Mono<User> findByIdSafe(Long id) {
        return userRepository.findById(id)
            .onErrorResume(DataAccessException.class, ex -> {
                log.error("DB error fetching user {}", id, ex);
                return Mono.empty();
            })
            .timeout(Duration.ofSeconds(5))
            .onErrorMap(TimeoutException.class,
                ex -> new ServiceUnavailableException("User service timeout"));
    }
}
```

### 2.2 Functional Routing (WebFlux)

```java
// Functional endpoints (alternative to @Controller)
@Configuration
public class UserRouter {

    @Bean
    public RouterFunction<ServerResponse> userRoutes(UserHandler handler) {
        return RouterFunctions.route()
            .path("/functional/users", builder -> builder
                .GET("/{id}", handler::getUser)
                .GET("", handler::listUsers)
                .POST("", handler::createUser)
                .PUT("/{id}", handler::updateUser)
                .DELETE("/{id}", handler::deleteUser)
            )
            .filter((request, next) -> {
                // Middleware / filter per router
                log.info("Request: {} {}", request.method(), request.path());
                return next.handle(request);
            })
            .build();
    }
}

@Component
public class UserHandler {

    @Autowired
    private ReactiveUserService userService;

    public Mono<ServerResponse> getUser(ServerRequest request) {
        Long id = Long.parseLong(request.pathVariable("id"));
        return userService.findById(id)
            .map(UserResponse::from)
            .flatMap(user -> ServerResponse.ok()
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(user))
            .switchIfEmpty(ServerResponse.notFound().build());
    }

    public Mono<ServerResponse> createUser(ServerRequest request) {
        return request.bodyToMono(UserRequest.class)
            .flatMap(req -> {
                // Manual validation in functional style
                Errors errors = new BeanPropertyBindingResult(req, "userRequest");
                validator.validate(req, errors);
                if (errors.hasErrors()) {
                    return ServerResponse.badRequest()
                        .bodyValue(ApiResponse.error("Validation failed",
                            mapErrors(errors)));
                }
                return userService.create(req)
                    .map(UserResponse::from)
                    .flatMap(user -> ServerResponse.created(
                        URI.create("/functional/users/" + user.getId()))
                        .bodyValue(user));
            });
    }
}
```

---

## 3. WebClient & RestClient

### 3.1 WebClient (Reactive HTTP Client)

```java
@Configuration
public class WebClientConfig {

    @Bean
    public WebClient orderServiceClient(
            @Value("${services.order.url}") String baseUrl) {
        return WebClient.builder()
            .baseUrl(baseUrl)
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .defaultHeader(HttpHeaders.ACCEPT, MediaType.APPLICATION_JSON_VALUE)
            .codecs(configurer -> configurer.defaultCodecs()
                .maxInMemorySize(10 * 1024 * 1024))  // 10MB
            .filter(ExchangeFilterFunction.ofRequestProcessor(req -> {
                log.debug("Request: {} {}", req.method(), req.url());
                return Mono.just(req);
            }))
            .filter(ExchangeFilterFunction.ofResponseProcessor(res -> {
                log.debug("Response: {}", res.statusCode());
                return Mono.just(res);
            }))
            .build();
    }
}

@Service
public class OrderClient {

    private final WebClient webClient;

    public OrderClient(WebClient orderServiceClient) {
        this.webClient = orderServiceClient;
    }

    public Mono<Order> getOrder(Long id) {
        return webClient.get()
            .uri("/orders/{id}", id)
            .retrieve()
            .onStatus(HttpStatus::is4xxClientError, response -> {
                if (response.statusCode() == HttpStatus.NOT_FOUND) {
                    return Mono.error(new EntityNotFoundException("Order " + id));
                }
                return response.createException();
            })
            .onStatus(HttpStatus::is5xxServerError, response ->
                response.bodyToMono(String.class)
                    .flatMap(body -> Mono.error(
                        new ServiceUnavailableException("Order service error: " + body))))
            .bodyToMono(Order.class)
            .retryWhen(Retry.backoff(3, Duration.ofSeconds(1))
                .filter(ex -> ex instanceof ServiceUnavailableException))
            .timeout(Duration.ofSeconds(5));
    }

    // POST with body
    public Mono<Order> createOrder(CreateOrderRequest request) {
        return webClient.post()
            .uri("/orders")
            .bodyValue(request)
            .retrieve()
            .bodyToMono(Order.class);
    }

    // Exchange for full response access
    public Mono<ResponseEntity<Order>> getOrderWithHeaders(Long id) {
        return webClient.get()
            .uri("/orders/{id}", id)
            .retrieve()
            .toEntity(Order.class);
    }
}
```

### 3.2 RestClient (Spring Boot 3.2+ - Synchronous)

```java
// RestClient = modern RestTemplate replacement (fluent, synchronous)
@Configuration
public class RestClientConfig {

    @Bean
    public RestClient productServiceClient(
            @Value("${services.product.url}") String baseUrl) {
        return RestClient.builder()
            .baseUrl(baseUrl)
            .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
            .requestInterceptor((request, body, execution) -> {
                // Add auth token
                request.getHeaders().add("Authorization", "Bearer " + tokenProvider.getToken());
                return execution.execute(request, body);
            })
            .build();
    }
}

@Service
public class ProductClient {

    private final RestClient restClient;

    public ProductResponse getProduct(Long id) {
        return restClient.get()
            .uri("/products/{id}", id)
            .retrieve()
            .onStatus(HttpStatusCode::is4xxClientError, (request, response) -> {
                throw new EntityNotFoundException("Product " + id + " not found");
            })
            .body(ProductResponse.class);
    }

    public List<ProductResponse> searchProducts(String query) {
        return restClient.get()
            .uri(uriBuilder -> uriBuilder
                .path("/products")
                .queryParam("q", query)
                .build())
            .retrieve()
            .body(new ParameterizedTypeReference<List<ProductResponse>>() {});
    }
}
```

---

## 4. Spring Security

### 4.1 JWT Authentication

```java
// Security Config
@Configuration
@EnableWebSecurity
@EnableMethodSecurity  // enables @PreAuthorize, @PostAuthorize, @Secured
public class SecurityConfig {

    @Autowired
    private JwtAuthenticationFilter jwtFilter;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(sm ->
                sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/auth/**", "/actuator/health").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/products/**").permitAll()
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated())
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint(jwtAuthEntryPoint())
                .accessDeniedHandler(jwtAccessDeniedHandler()))
            .build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);
    }
}

// JWT Filter
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider tokenProvider;
    private final UserDetailsService userDetailsService;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String token = extractToken(request);

        if (token != null && tokenProvider.validateToken(token)) {
            String username = tokenProvider.getUsernameFromToken(token);
            UserDetails userDetails = userDetailsService.loadUserByUsername(username);

            UsernamePasswordAuthenticationToken auth =
                new UsernamePasswordAuthenticationToken(
                    userDetails, null, userDetails.getAuthorities());
            auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));

            SecurityContextHolder.getContext().setAuthentication(auth);
        }

        chain.doFilter(request, response);
    }

    private String extractToken(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
    }
}

// JWT Token Provider
@Component
public class JwtTokenProvider {

    @Value("${app.jwt.secret}")
    private String jwtSecret;

    @Value("${app.jwt.expiration-ms}")
    private long jwtExpirationMs;

    private SecretKey key;

    @PostConstruct
    public void init() {
        key = Keys.hmacShaKeyFor(Decoders.BASE64.decode(jwtSecret));
    }

    public String generateToken(Authentication authentication) {
        UserDetails user = (UserDetails) authentication.getPrincipal();
        return Jwts.builder()
            .subject(user.getUsername())
            .claim("roles", user.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority).toList())
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + jwtExpirationMs))
            .signWith(key)
            .compact();
    }

    public String getUsernameFromToken(String token) {
        return Jwts.parser().verifyWith(key).build()
            .parseSignedClaims(token).getPayload().getSubject();
    }

    public boolean validateToken(String token) {
        try {
            Jwts.parser().verifyWith(key).build().parseSignedClaims(token);
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            log.error("Invalid JWT: {}", e.getMessage());
            return false;
        }
    }
}
```

### 4.2 Method Security

```java
@Service
public class OrderService {

    // Role-based
    @PreAuthorize("hasRole('ADMIN')")
    public void deleteAll() { }

    // Permission-based
    @PreAuthorize("hasAuthority('order:write')")
    public Order createOrder(CreateOrderRequest req) { }

    // SpEL with current user
    @PreAuthorize("hasRole('ADMIN') or #userId == authentication.principal.id")
    public List<Order> getUserOrders(Long userId) { }

    // Post-authorize: check return value
    @PostAuthorize("returnObject.userId == authentication.principal.id or hasRole('ADMIN')")
    public Order getOrder(Long id) { }

    // Pre/Post filtering on collections
    @PreFilter("filterObject.status != 'CANCELLED'")
    public void processOrders(List<Order> orders) { }

    @PostFilter("filterObject.userId == authentication.principal.id")
    public List<Order> getAllOrders() { }
}
```

### 4.3 OAuth2 Resource Server (Spring Boot 3)

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://auth-server.example.com
          jwk-set-uri: https://auth-server.example.com/.well-known/jwks.json
```

```java
@Configuration
@EnableWebSecurity
public class OAuth2ResourceServerConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        return http
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/public/**").permitAll()
                .anyRequest().authenticated())
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter())))
            .build();
    }

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter() {
        JwtGrantedAuthoritiesConverter grantedAuthoritiesConverter =
            new JwtGrantedAuthoritiesConverter();
        grantedAuthoritiesConverter.setAuthoritiesClaimName("roles");
        grantedAuthoritiesConverter.setAuthorityPrefix("ROLE_");

        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(grantedAuthoritiesConverter);
        return converter;
    }
}
```

---

## 5. OpenAPI 3 Documentation

```xml
<!-- pom.xml -->
<dependency>
    <groupId>org.springdoc</groupId>
    <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
    <version>2.3.0</version>
</dependency>
```

```java
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI openAPI() {
        return new OpenAPI()
            .info(new Info()
                .title("Order Service API")
                .description("Order management service")
                .version("v2.0")
                .contact(new Contact().name("Team Backend").email("backend@company.com")))
            .addSecurityItem(new SecurityRequirement().addList("bearerAuth"))
            .components(new Components()
                .addSecuritySchemes("bearerAuth", new SecurityScheme()
                    .name("bearerAuth")
                    .type(SecurityScheme.Type.HTTP)
                    .scheme("bearer")
                    .bearerFormat("JWT")));
    }
}

// Controller documentation
@RestController
@RequestMapping("/api/orders")
@Tag(name = "Orders", description = "Order management endpoints")
public class OrderController {

    @Operation(summary = "Get order by ID",
        description = "Returns a single order. Requires VIEWER or ADMIN role.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Order found",
            content = @Content(schema = @Schema(implementation = OrderResponse.class))),
        @ApiResponse(responseCode = "404", description = "Order not found",
            content = @Content(schema = @Schema(implementation = ApiResponse.class))),
        @ApiResponse(responseCode = "401", description = "Unauthorized")
    })
    @GetMapping("/{id}")
    public ApiResponse<OrderResponse> getOrder(
        @Parameter(description = "Order ID", required = true, example = "42")
        @PathVariable Long id) {
        return ApiResponse.ok(orderService.findById(id));
    }
}
```

```yaml
# application.yml
springdoc:
  api-docs:
    path: /api-docs
  swagger-ui:
    path: /swagger-ui.html
    operationsSorter: method
    tagsSorter: alpha
  show-actuator: false
  default-produces-media-type: application/json
```

---

## 6. CORS Configuration

```java
@Configuration
public class CorsConfig implements WebMvcConfigurer {

    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/api/**")
            .allowedOriginPatterns("https://*.example.com", "http://localhost:*")
            .allowedMethods("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS")
            .allowedHeaders("*")
            .allowCredentials(true)
            .maxAge(3600);
    }
}

// Or per endpoint
@CrossOrigin(origins = "https://frontend.example.com", maxAge = 3600)
@RestController
public class ProductController { }

// With Spring Security (must configure security too)
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOriginPatterns(List.of("https://*.example.com"));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
    config.setAllowedHeaders(List.of("*"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/**", config);
    return source;
}

// Add to SecurityFilterChain:
// .cors(cors -> cors.configurationSource(corsConfigurationSource()))
```

---

## 7. Rate Limiting with Bucket4j

```xml
<dependency>
    <groupId>com.bucket4j</groupId>
    <artifactId>bucket4j-core</artifactId>
    <version>8.7.0</version>
</dependency>
<dependency>
    <groupId>com.bucket4j</groupId>
    <artifactId>bucket4j-redis</artifactId>
    <version>8.7.0</version>
</dependency>
```

```java
@Component
public class RateLimitingFilter extends OncePerRequestFilter {

    private final Map<String, Bucket> buckets = new ConcurrentHashMap<>();

    // 100 requests per minute per IP
    private Bucket getBucket(String key) {
        return buckets.computeIfAbsent(key, k -> Bucket.builder()
            .addLimit(Bandwidth.classic(100, Refill.greedy(100, Duration.ofMinutes(1))))
            .build());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws IOException, ServletException {
        String clientIp = getClientIp(request);
        Bucket bucket = getBucket(clientIp);

        ConsumptionProbe probe = bucket.tryConsumeAndReturnRemaining(1);

        if (probe.isConsumed()) {
            response.setHeader("X-Rate-Limit-Remaining",
                String.valueOf(probe.getRemainingTokens()));
            chain.doFilter(request, response);
        } else {
            long waitSeconds = probe.getNanosToWaitForRefill() / 1_000_000_000;
            response.setHeader("X-Rate-Limit-Retry-After-Seconds", String.valueOf(waitSeconds));
            response.sendError(HttpStatus.TOO_MANY_REQUESTS.value(),
                "Rate limit exceeded. Retry after " + waitSeconds + "s");
        }
    }
}

// Custom annotation for method-level rate limiting
@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
public @interface RateLimit {
    int requests() default 100;
    int duration() default 60;  // seconds
    String key() default "ip";  // "ip" | "user" | custom SpEL
}

@RateLimit(requests = 5, duration = 60, key = "user")  // 5 per minute per user
@PostMapping("/send-otp")
public ResponseEntity<?> sendOtp(@RequestBody SendOtpRequest req) { ... }
```

---

## 8. HTTP Compression & HTTP/2

```yaml
# application.yml
server:
  compression:
    enabled: true
    mime-types: application/json,application/xml,text/html,text/plain
    min-response-size: 1024   # compress responses > 1KB
  http2:
    enabled: true             # requires HTTPS in production
  ssl:
    key-store: classpath:keystore.p12
    key-store-password: ${SSL_KEYSTORE_PASSWORD}
    key-store-type: PKCS12
```

---

## Ghi chú – Topics tiếp theo

- **JPA N+1**: EntityGraph, JOIN FETCH, Projections → `springboot_data.md`
- **Spring Cache**: @Cacheable, Redis, multi-level cache → `springboot_data.md`
- **Spring Kafka**: @KafkaListener, consumer groups → `springboot_messaging.md`
- **@TransactionalEventListener**: reliable events → `springboot_messaging.md`
- **@WebMvcTest**: testing controllers in isolation → `springboot_testing.md`
- **Actuator**: custom health, metrics → `springboot_production.md`
