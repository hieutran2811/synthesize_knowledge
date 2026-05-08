# Spring Security – Authentication & Authorization

## Mục lục
1. [Architecture – Security Filter Chain](#1-architecture--security-filter-chain)
2. [Authentication – Xác Thực](#2-authentication--xác-thực)
3. [JWT Authentication – Stateless API](#3-jwt-authentication--stateless-api)
4. [Authorization – Phân Quyền](#4-authorization--phân-quyền)
5. [Method Security](#5-method-security)
6. [OAuth2 / OIDC](#6-oauth2--oidc)
7. [CSRF, CORS & Security Headers](#7-csrf-cors--security-headers)
8. [Password Encoding & Crypto](#8-password-encoding--crypto)

---

## 1. Architecture – Security Filter Chain

### 1.1 How Spring Security Works

```
HTTP Request
    │
    ▼
DelegatingFilterProxy (Servlet Filter)
    │
    ▼
FilterChainProxy
    │
    ├── SecurityContextPersistenceFilter   ← load/save SecurityContext
    ├── UsernamePasswordAuthenticationFilter ← process /login
    ├── BasicAuthenticationFilter          ← Basic auth header
    ├── BearerTokenAuthenticationFilter    ← JWT Bearer token
    ├── SecurityContextHolderFilter
    ├── ExceptionTranslationFilter         ← convert auth exceptions to HTTP responses
    └── AuthorizationFilter                ← access control (was FilterSecurityInterceptor)
    │
    ▼
DispatcherServlet → Controller

SecurityContextHolder (ThreadLocal)
    └── SecurityContext
            └── Authentication
                    ├── Principal (UserDetails)
                    ├── Credentials (password, cleared after auth)
                    └── Authorities (roles/permissions)
```

### 1.2 SecurityFilterChain Configuration (Spring Security 6)

```java
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            // ── Session Management ───────────────────────────────────────
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS)  // JWT → no session
            )

            // ── CSRF (disable for stateless APIs) ────────────────────────
            .csrf(csrf -> csrf.disable())

            // ── CORS ─────────────────────────────────────────────────────
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))

            // ── Authorization Rules ───────────────────────────────────────
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/auth/**").permitAll()
                .requestMatchers("/actuator/health").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/products/**").permitAll()
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .requestMatchers("/api/orders/**").hasAnyRole("USER", "ADMIN")
                .anyRequest().authenticated()
            )

            // ── JWT Filter (add before UsernamePasswordAuthenticationFilter)
            .addFilterBefore(jwtAuthenticationFilter(), UsernamePasswordAuthenticationFilter.class)

            // ── Exception Handling ────────────────────────────────────────
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint(unauthorizedHandler())     // 401
                .accessDeniedHandler(accessDeniedHandler())          // 403
            )

            .build();
    }

    @Bean
    public AuthenticationManager authenticationManager(
            AuthenticationConfiguration config) throws Exception {
        return config.getAuthenticationManager();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12);  // cost factor 12
    }
}
```

---

## 2. Authentication – Xác Thực

### 2.1 UserDetailsService

```java
// Spring Security calls loadUserByUsername() to get UserDetails
@Service
@RequiredArgsConstructor
public class CustomUserDetailsService implements UserDetailsService {

    private final UserRepository userRepository;

    @Override
    public UserDetails loadUserByUsername(String email) throws UsernameNotFoundException {
        return userRepository.findByEmail(email)
            .map(this::toUserDetails)
            .orElseThrow(() -> new UsernameNotFoundException("User not found: " + email));
    }

    private UserDetails toUserDetails(User user) {
        var authorities = user.getRoles().stream()
            .map(role -> new SimpleGrantedAuthority("ROLE_" + role.name()))
            .collect(Collectors.toList());

        return new org.springframework.security.core.userdetails.User(
            user.getEmail(),
            user.getPasswordHash(),
            user.isEnabled(),           // enabled
            true,                       // accountNonExpired
            !user.isPasswordExpired(),  // credentialsNonExpired
            !user.isLocked(),           // accountNonLocked
            authorities
        );
    }
}

// Or implement UserDetails on your entity (simpler but tight coupling):
@Entity
public class User implements UserDetails {
    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return roles.stream()
            .map(r -> new SimpleGrantedAuthority("ROLE_" + r.name()))
            .toList();
    }

    @Override public String getPassword() { return passwordHash; }
    @Override public String getUsername() { return email; }
    @Override public boolean isAccountNonExpired() { return true; }
    @Override public boolean isAccountNonLocked() { return !locked; }
    @Override public boolean isCredentialsNonExpired() { return true; }
    @Override public boolean isEnabled() { return enabled; }
}
```

### 2.2 Login Endpoint (Form / JSON)

```java
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthenticationManager authenticationManager;
    private final JwtTokenService jwtTokenService;
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        // Delegates to UserDetailsService.loadUserByUsername + PasswordEncoder.matches
        var authToken = new UsernamePasswordAuthenticationToken(
            request.email(), request.password());

        Authentication auth;
        try {
            auth = authenticationManager.authenticate(authToken);
        } catch (BadCredentialsException e) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new AuthResponse(null, null, "Invalid credentials"));
        }

        var userDetails = (UserDetails) auth.getPrincipal();
        var accessToken  = jwtTokenService.generateAccessToken(userDetails);
        var refreshToken = jwtTokenService.generateRefreshToken(userDetails);

        return ResponseEntity.ok(new AuthResponse(accessToken, refreshToken, null));
    }

    @PostMapping("/register")
    public ResponseEntity<UserResponse> register(@Valid @RequestBody RegisterRequest request) {
        if (userRepository.existsByEmail(request.email())) {
            throw new DuplicateEmailException(request.email());
        }

        var user = User.builder()
            .email(request.email())
            .passwordHash(passwordEncoder.encode(request.password()))
            .roles(Set.of(Role.USER))
            .enabled(true)
            .build();

        var saved = userRepository.save(user);
        return ResponseEntity.status(HttpStatus.CREATED).body(UserResponse.from(saved));
    }

    @PostMapping("/refresh")
    public ResponseEntity<AuthResponse> refresh(@RequestBody RefreshRequest request) {
        var username = jwtTokenService.extractUsername(request.refreshToken());
        var userDetails = userDetailsService.loadUserByUsername(username);

        if (!jwtTokenService.isValid(request.refreshToken(), userDetails)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        var newAccessToken = jwtTokenService.generateAccessToken(userDetails);
        return ResponseEntity.ok(new AuthResponse(newAccessToken, request.refreshToken(), null));
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@RequestHeader("Authorization") String authHeader) {
        var token = authHeader.substring(7);
        jwtTokenService.blacklistToken(token);  // store in Redis with TTL = token expiry
        return ResponseEntity.noContent().build();
    }
}
```

---

## 3. JWT Authentication – Stateless API

### 3.1 JWT Token Service

```java
@Service
public class JwtTokenService {

    @Value("${app.jwt.secret}")
    private String jwtSecret;

    @Value("${app.jwt.access-token-expiry:900}")    // 15 minutes
    private long accessTokenExpirySeconds;

    @Value("${app.jwt.refresh-token-expiry:2592000}") // 30 days
    private long refreshTokenExpirySeconds;

    private SecretKey secretKey() {
        return Keys.hmacShaKeyFor(Decoders.BASE64.decode(jwtSecret));
    }

    public String generateAccessToken(UserDetails userDetails) {
        return generateToken(
            Map.of(
                "type", "access",
                "roles", userDetails.getAuthorities().stream()
                    .map(GrantedAuthority::getAuthority)
                    .toList()
            ),
            userDetails.getUsername(),
            accessTokenExpirySeconds
        );
    }

    public String generateRefreshToken(UserDetails userDetails) {
        return generateToken(
            Map.of("type", "refresh"),
            userDetails.getUsername(),
            refreshTokenExpirySeconds
        );
    }

    private String generateToken(Map<String, Object> extraClaims, String subject, long expirySeconds) {
        return Jwts.builder()
            .claims(extraClaims)
            .subject(subject)
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + expirySeconds * 1000))
            .signWith(secretKey())
            .compact();
    }

    public String extractUsername(String token) {
        return extractClaim(token, Claims::getSubject);
    }

    public boolean isValid(String token, UserDetails userDetails) {
        var username = extractUsername(token);
        return username.equals(userDetails.getUsername())
            && !isExpired(token)
            && !isBlacklisted(token);
    }

    private boolean isExpired(String token) {
        return extractClaim(token, Claims::getExpiration).before(new Date());
    }

    private boolean isBlacklisted(String token) {
        return redisTemplate.hasKey("blacklist:" + token);
    }

    public void blacklistToken(String token) {
        var expiry = extractClaim(token, Claims::getExpiration);
        var ttl = Duration.between(Instant.now(), expiry.toInstant());
        if (ttl.isPositive()) {
            redisTemplate.opsForValue().set("blacklist:" + token, "1", ttl);
        }
    }

    private <T> T extractClaim(String token, Function<Claims, T> resolver) {
        return resolver.apply(parseClaims(token));
    }

    private Claims parseClaims(String token) {
        return Jwts.parser()
            .verifyWith(secretKey())
            .build()
            .parseSignedClaims(token)
            .getPayload();
    }
}
```

### 3.2 JWT Authentication Filter

```java
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenService jwtTokenService;
    private final UserDetailsService userDetailsService;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        var authHeader = request.getHeader(HttpHeaders.AUTHORIZATION);

        if (authHeader == null || !authHeader.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        var token = authHeader.substring(7);

        try {
            var username = jwtTokenService.extractUsername(token);

            if (username != null && SecurityContextHolder.getContext().getAuthentication() == null) {
                var userDetails = userDetailsService.loadUserByUsername(username);

                if (jwtTokenService.isValid(token, userDetails)) {
                    var authToken = new UsernamePasswordAuthenticationToken(
                        userDetails,
                        null,
                        userDetails.getAuthorities()
                    );
                    authToken.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                    SecurityContextHolder.getContext().setAuthentication(authToken);
                }
            }
        } catch (JwtException e) {
            // Invalid token: just don't set authentication — downstream will get 401
            log.debug("JWT validation failed: {}", e.getMessage());
        }

        filterChain.doFilter(request, response);
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        // Skip for public endpoints
        return request.getServletPath().startsWith("/api/auth/");
    }
}
```

---

## 4. Authorization – Phân Quyền

### 4.1 URL-based Authorization

```java
// SecurityConfig.authorizeHttpRequests():
.authorizeHttpRequests(auth -> auth
    // Public
    .requestMatchers("/api/auth/**", "/api/public/**").permitAll()
    .requestMatchers(HttpMethod.GET, "/api/products", "/api/products/*").permitAll()

    // Role-based
    .requestMatchers("/api/admin/**").hasRole("ADMIN")
    .requestMatchers("/api/reports/**").hasAnyRole("ADMIN", "ANALYST")

    // Authority-based (granular permissions)
    .requestMatchers(HttpMethod.DELETE, "/api/orders/*").hasAuthority("ORDER_DELETE")
    .requestMatchers(HttpMethod.POST, "/api/orders").hasAuthority("ORDER_CREATE")

    // IP restriction
    .requestMatchers("/actuator/**").hasIpAddress("10.0.0.0/8")

    // Catch-all
    .anyRequest().authenticated()
)
```

### 4.2 SpEL Expressions

```java
// Custom SpEL expressions in URL rules or @PreAuthorize:
.requestMatchers("/api/orders/{id}").access(
    new WebExpressionAuthorizationManager(
        "hasRole('ADMIN') or (hasRole('USER') and #id == authentication.principal.userId)"
    )
)

// In controller annotations:
@PreAuthorize("hasRole('ADMIN') or #userId == authentication.principal.id")
public UserResponse getUser(@PathVariable Long userId) { ... }

// Custom security beans available in SpEL:
@Bean
public OrderSecurity orderSecurity() {
    return new OrderSecurity();
}

// In @PreAuthorize:
@PreAuthorize("@orderSecurity.isOwner(authentication, #orderId)")
public OrderResponse getOrder(@PathVariable Long orderId) { ... }

@Component("orderSecurity")
public class OrderSecurity {
    public boolean isOwner(Authentication auth, Long orderId) {
        var userId = ((UserDetails) auth.getPrincipal()).getUserId();
        return orderRepository.existsByIdAndCustomerId(orderId, userId);
    }
}
```

---

## 5. Method Security

```java
@Configuration
@EnableMethodSecurity(
    prePostEnabled = true,   // @PreAuthorize, @PostAuthorize (default: true)
    securedEnabled = true,   // @Secured
    jsr250Enabled = true     // @RolesAllowed
)
public class MethodSecurityConfig { }

// ── @PreAuthorize (most common) ───────────────────────────────────────────
@Service
public class OrderService {

    @PreAuthorize("isAuthenticated()")
    public List<Order> findMyOrders(Principal principal) { ... }

    @PreAuthorize("hasRole('ADMIN') or #customerId == authentication.principal.id")
    public List<Order> findByCustomer(Long customerId) { ... }

    @PreAuthorize("hasAuthority('ORDER_CREATE')")
    public Order create(CreateOrderRequest request) { ... }

    // ── @PostAuthorize: check AFTER method runs (access return value) ───
    @PostAuthorize("returnObject.customerId == authentication.principal.id or hasRole('ADMIN')")
    public Order findById(Long id) {
        return orderRepository.findById(id).orElseThrow();
    }

    // ── @PreFilter: filter input collection ──────────────────────────────
    @PreFilter("filterObject.customerId == authentication.principal.id")
    public void bulkCancel(List<Order> orders) {
        orders.forEach(o -> o.cancel());  // only processes user's own orders
    }

    // ── @PostFilter: filter returned collection ───────────────────────────
    @PostFilter("filterObject.customerId == authentication.principal.id or hasRole('ADMIN')")
    public List<Order> findAll() {
        return orderRepository.findAll();  // filtered down to user's own
    }
}

// ── @Secured: role check only, no SpEL ───────────────────────────────────
@Secured({"ROLE_ADMIN", "ROLE_MANAGER"})
public void deleteOrder(Long id) { ... }

// ── @RolesAllowed (JSR-250 standard) ─────────────────────────────────────
@RolesAllowed("ADMIN")
public void promoteUser(Long userId) { ... }
```

### 5.1 Getting Current User

```java
// Method 1: SecurityContextHolder (anywhere)
Authentication auth = SecurityContextHolder.getContext().getAuthentication();
UserDetails userDetails = (UserDetails) auth.getPrincipal();

// Method 2: @AuthenticationPrincipal (in controller)
@GetMapping("/me")
public UserResponse getCurrentUser(@AuthenticationPrincipal CustomUserDetails userDetails) {
    return UserResponse.from(userDetails.getUser());
}

// Method 3: Principal injection
@GetMapping("/me")
public UserResponse getCurrentUser(Principal principal) {
    return userService.findByEmail(principal.getName());
}

// Custom @AuthenticationPrincipal meta-annotation:
@Target(ElementType.PARAMETER)
@Retention(RetentionPolicy.RUNTIME)
@AuthenticationPrincipal
public @interface CurrentUser { }

@GetMapping("/profile")
public ProfileResponse getProfile(@CurrentUser CustomUserDetails user) { ... }
```

---

## 6. OAuth2 / OIDC

### 6.1 Resource Server (Validate JWT from Auth Server)

```java
// This service validates JWT tokens issued by Keycloak / Auth0 / Okta
@Configuration
public class ResourceServerConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .oauth2ResourceServer(oauth2 -> oauth2
                .jwt(jwt -> jwt
                    .jwtAuthenticationConverter(jwtAuthenticationConverter())
                )
            )
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/public/**").permitAll()
                .anyRequest().authenticated()
            )
            .build();
    }

    @Bean
    public JwtAuthenticationConverter jwtAuthenticationConverter() {
        var converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwt -> {
            // Extract roles from Keycloak-style JWT claim
            var realmAccess = (Map<String, Object>) jwt.getClaims().get("realm_access");
            if (realmAccess == null) return List.of();
            var roles = (List<String>) realmAccess.get("roles");
            return roles.stream()
                .map(role -> new SimpleGrantedAuthority("ROLE_" + role.toUpperCase()))
                .collect(Collectors.toList());
        });
        return converter;
    }
}

# application.yml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://keycloak.example.com/realms/myapp
          # jwk-set-uri: https://keycloak.example.com/realms/myapp/protocol/openid-connect/certs
```

### 6.2 OAuth2 Client (Login with Google / GitHub)

```yaml
# application.yml
spring:
  security:
    oauth2:
      client:
        registration:
          google:
            client-id: ${GOOGLE_CLIENT_ID}
            client-secret: ${GOOGLE_CLIENT_SECRET}
            scope: openid,profile,email
          github:
            client-id: ${GITHUB_CLIENT_ID}
            client-secret: ${GITHUB_CLIENT_SECRET}
            scope: read:user,user:email
```

```java
@Configuration
public class OAuth2SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        return http
            .oauth2Login(oauth2 -> oauth2
                .loginPage("/login")
                .defaultSuccessUrl("/dashboard", true)
                .failureUrl("/login?error=true")
                .userInfoEndpoint(userInfo -> userInfo
                    .userService(customOAuth2UserService())  // process user info
                )
            )
            .build();
    }
}

@Service
public class CustomOAuth2UserService extends DefaultOAuth2UserService {

    @Override
    public OAuth2User loadUser(OAuth2UserRequest userRequest) throws OAuth2AuthenticationException {
        var oAuth2User = super.loadUser(userRequest);
        var registrationId = userRequest.getClientRegistration().getRegistrationId(); // "google"/"github"

        // Extract email based on provider
        String email = switch (registrationId) {
            case "google" -> oAuth2User.getAttribute("email");
            case "github" -> fetchGithubEmail(oAuth2User);
            default -> throw new OAuth2AuthenticationException("Unknown provider");
        };

        // Upsert user in our DB
        var user = userRepository.findByEmail(email)
            .orElseGet(() -> createNewUser(email, oAuth2User, registrationId));

        return new CustomOAuth2User(user, oAuth2User.getAttributes());
    }
}
```

---

## 7. CSRF, CORS & Security Headers

### 7.1 CSRF Configuration

```java
// Session-based apps: CSRF protection needed
.csrf(csrf -> csrf
    .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
    // Cookie: XSRF-TOKEN (readable by JS)
    // Header: X-XSRF-TOKEN (Angular/Axios send automatically)
    .ignoringRequestMatchers("/api/webhooks/**")  // exempt webhooks
)

// Stateless JWT API: disable CSRF (no session to exploit)
.csrf(csrf -> csrf.disable())
```

### 7.2 CORS Configuration

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    var config = new CorsConfiguration();
    config.setAllowedOriginPatterns(List.of(
        "https://*.example.com",
        "http://localhost:*"      // dev only
    ));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
    config.setAllowedHeaders(List.of("*"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);  // preflight cache for 1 hour

    var source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
}

// Alternative: @CrossOrigin on controller
@CrossOrigin(origins = "https://app.example.com", methods = {GET, POST})
@RestController
public class ProductController { ... }
```

### 7.3 Security Headers

```java
.headers(headers -> headers
    .frameOptions(frame -> frame.deny())                       // X-Frame-Options: DENY
    .contentTypeOptions(Customizer.withDefaults())             // X-Content-Type-Options: nosniff
    .httpStrictTransportSecurity(hsts -> hsts
        .maxAgeInSeconds(31536000)
        .includeSubDomains(true)
        .preload(true)                                         // HSTS preload
    )
    .referrerPolicy(ref -> ref
        .policy(ReferrerPolicyHeaderWriter.ReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN)
    )
    .permissionsPolicy(perms -> perms
        .policy("camera=(), microphone=(), geolocation=()")
    )
    .contentSecurityPolicy(csp -> csp
        .policyDirectives("default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'")
    )
)
```

---

## 8. Password Encoding & Crypto

### 8.1 PasswordEncoder

```java
// BCrypt (default recommended):
@Bean
public PasswordEncoder passwordEncoder() {
    return new BCryptPasswordEncoder(12);  // work factor 12 (2^12 iterations)
    // Higher factor → slower but more secure
    // Recommend: 10-12 for interactive login, don't go below 10
}

// Argon2 (modern, memory-hard — even better than BCrypt):
@Bean
public PasswordEncoder argon2Encoder() {
    return new Argon2PasswordEncoder(
        16,   // saltLength
        32,   // hashLength
        1,    // parallelism
        65536, // memory (64MB)
        3     // iterations
    );
}

// DelegatingPasswordEncoder: handles multiple encoders (migration)
@Bean
public PasswordEncoder delegatingEncoder() {
    var encoders = Map.of(
        "bcrypt", new BCryptPasswordEncoder(12),
        "argon2", new Argon2PasswordEncoder(16, 32, 1, 65536, 3),
        "noop",   NoOpPasswordEncoder.getInstance()  // legacy migration only!
    );
    return new DelegatingPasswordEncoder("bcrypt", encoders);
    // Stored as: {bcrypt}$2a$12$...
    //            {argon2}$argon2id$...
    //            {noop}plaintext
}

// Usage:
String hash = passwordEncoder.encode("rawPassword");
boolean matches = passwordEncoder.matches("rawPassword", hash);  // true
```

### 8.2 Audit Logging

```java
@Component
@Slf4j
public class SecurityAuditListener {

    @EventListener
    public void onAuthenticationSuccess(AuthenticationSuccessEvent event) {
        var username = event.getAuthentication().getName();
        log.info("LOGIN_SUCCESS user={} ip={}", username, getIpAddress(event));
    }

    @EventListener
    public void onAuthenticationFailure(AbstractAuthenticationFailureEvent event) {
        var username = event.getAuthentication().getName();
        var reason = event.getException().getClass().getSimpleName();
        log.warn("LOGIN_FAILURE user={} reason={}", username, reason);
        // Alert if repeated failures
    }

    @EventListener
    public void onAccessDenied(AuthorizationDeniedEvent event) {
        var auth = event.getAuthentication().get();
        log.warn("ACCESS_DENIED user={} resource={}", auth.getName(), event.getAuthorizationDecision());
    }
}
```

---

## Trade-offs & Ghi chú

| Mechanism | Stateless | Scalable | Revocable | Complexity |
|-----------|-----------|----------|-----------|-----------|
| Session (HttpSession) | ❌ | Needs sticky/Redis | ✅ instant | Low |
| JWT (access only) | ✅ | ✅ | ❌ (until expiry) | Medium |
| JWT + refresh + blacklist | ✅ | ✅ | ✅ (via blacklist) | High |
| OAuth2 opaque tokens | ✅ | ✅ | ✅ (introspect) | High |
| OAuth2 JWT | ✅ | ✅ | Partial | Medium |

- **Keywords**: SecurityContextHolder, FilterChainProxy, OncePerRequestFilter, AuthenticationManager, AuthenticationProvider, UserDetailsService, GrantedAuthority, JwtAuthenticationConverter, CookieCsrfTokenRepository, DelegatingPasswordEncoder, BCryptPasswordEncoder, Argon2, @PreAuthorize SpEL, @PostFilter, @AuthenticationPrincipal, OAuth2ResourceServer, JWK Set URI, PKCE, OIDC UserInfo endpoint, Spring Security ACL (domain object security)
