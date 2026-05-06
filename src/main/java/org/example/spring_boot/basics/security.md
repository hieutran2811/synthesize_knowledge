# Spring Security – Bảo mật ứng dụng Spring Boot

## What – Spring Security là gì?

**Spring Security** là framework bảo mật mạnh nhất cho Java/Spring, cung cấp:
- **Authentication** (Xác thực): ai đang gọi?
- **Authorization** (Phân quyền): họ được phép làm gì?
- Bảo vệ khỏi CSRF, Session Fixation, Clickjacking, XSS headers

---

## How – Security Filter Chain

Spring Security hoạt động như một chuỗi Servlet Filters, chạy **trước** khi request đến Controller.

```
Request → DelegatingFilterProxy → FilterChainProxy
                                       │
                            SecurityFilterChain:
                            1. DisableEncodeUrlFilter
                            2. WebAsyncManagerIntegrationFilter
                            3. SecurityContextHolderFilter
                            4. HeaderWriterFilter
                            5. CorsFilter
                            6. CsrfFilter
                            7. LogoutFilter
                            8. UsernamePasswordAuthenticationFilter
                            9. BasicAuthenticationFilter
                            10. ExceptionTranslationFilter
                            11. AuthorizationFilter
                                       │
                                  Controller
```

### Cấu hình cơ bản (Spring Boot 3 / Security 6)

```java
@Configuration
@EnableWebSecurity
@EnableMethodSecurity  // Bật @PreAuthorize, @PostAuthorize
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)          // REST API không cần CSRF
            .sessionManagement(session -> session
                .sessionCreationPolicy(SessionCreationPolicy.STATELESS)) // JWT = stateless
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/auth/**").permitAll()
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .requestMatchers(HttpMethod.GET, "/api/products/**").permitAll()
                .anyRequest().authenticated()
            )
            .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class)
            .exceptionHandling(ex -> ex
                .authenticationEntryPoint(unauthorizedHandler)  // 401
                .accessDeniedHandler(accessDeniedHandler)       // 403
            );

        return http.build();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder(12); // cost factor 12
    }

    @Bean
    public AuthenticationManager authenticationManager(
            AuthenticationConfiguration config) throws Exception {
        return config.getAuthenticationManager();
    }
}
```

---

## JWT Authentication

### Luồng hoạt động

```
Login:
Client → POST /auth/login (username + password)
       ← 200 OK { accessToken, refreshToken }

Subsequent requests:
Client → GET /api/orders
         Authorization: Bearer <accessToken>
       ← 200 OK { data }

Token refresh:
Client → POST /auth/refresh { refreshToken }
       ← 200 OK { newAccessToken }
```

### JWT Filter

```java
@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider tokenProvider;
    private final UserDetailsService userDetailsService;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws IOException, ServletException {
        String token = extractToken(request);

        if (token != null && tokenProvider.validateToken(token)) {
            String username = tokenProvider.getUsername(token);

            UserDetails userDetails = userDetailsService.loadUserByUsername(username);
            UsernamePasswordAuthenticationToken auth =
                new UsernamePasswordAuthenticationToken(
                    userDetails, null, userDetails.getAuthorities()
                );
            auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));

            SecurityContextHolder.getContext().setAuthentication(auth);
        }

        chain.doFilter(request, response);
    }

    private String extractToken(HttpServletRequest request) {
        String bearer = request.getHeader("Authorization");
        if (StringUtils.hasText(bearer) && bearer.startsWith("Bearer ")) {
            return bearer.substring(7);
        }
        return null;
    }
}
```

### JWT Token Provider

```java
@Component
public class JwtTokenProvider {

    @Value("${app.jwt.secret}")
    private String jwtSecret;

    @Value("${app.jwt.expiration-ms}")
    private long accessTokenExpMs;  // 15 phút

    @Value("${app.jwt.refresh-expiration-ms}")
    private long refreshTokenExpMs; // 7 ngày

    private SecretKey getSigningKey() {
        byte[] keyBytes = Decoders.BASE64.decode(jwtSecret);
        return Keys.hmacShaKeyFor(keyBytes);
    }

    public String generateAccessToken(UserDetails userDetails) {
        return Jwts.builder()
            .subject(userDetails.getUsername())
            .claim("roles", userDetails.getAuthorities().stream()
                .map(GrantedAuthority::getAuthority).toList())
            .claim("type", "access")
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + accessTokenExpMs))
            .signWith(getSigningKey(), Jwts.SIG.HS256)
            .compact();
    }

    public String generateRefreshToken(String username) {
        return Jwts.builder()
            .subject(username)
            .claim("type", "refresh")
            .issuedAt(new Date())
            .expiration(new Date(System.currentTimeMillis() + refreshTokenExpMs))
            .signWith(getSigningKey(), Jwts.SIG.HS256)
            .compact();
    }

    public boolean validateToken(String token) {
        try {
            Jwts.parser().verifyWith(getSigningKey()).build().parseSignedClaims(token);
            return true;
        } catch (ExpiredJwtException e) {
            log.warn("JWT expired: {}", e.getMessage());
        } catch (JwtException e) {
            log.warn("Invalid JWT: {}", e.getMessage());
        }
        return false;
    }

    public String getUsername(String token) {
        return Jwts.parser()
            .verifyWith(getSigningKey()).build()
            .parseSignedClaims(token)
            .getPayload().getSubject();
    }
}
```

### Auth Controller

```java
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final AuthenticationManager authManager;
    private final JwtTokenProvider tokenProvider;
    private final RefreshTokenService refreshTokenService;

    @PostMapping("/login")
    public ResponseEntity<TokenResponse> login(@Valid @RequestBody LoginRequest req) {
        Authentication auth = authManager.authenticate(
            new UsernamePasswordAuthenticationToken(req.username(), req.password())
        );

        UserDetails userDetails = (UserDetails) auth.getPrincipal();
        String accessToken = tokenProvider.generateAccessToken(userDetails);
        String refreshToken = refreshTokenService.createRefreshToken(userDetails.getUsername());

        return ResponseEntity.ok(new TokenResponse(accessToken, refreshToken, "Bearer", 900));
    }

    @PostMapping("/refresh")
    public ResponseEntity<TokenResponse> refresh(@RequestBody RefreshRequest req) {
        RefreshToken refreshToken = refreshTokenService.findAndValidate(req.refreshToken());
        String newAccessToken = tokenProvider.generateAccessToken(
            refreshToken.getUser().toUserDetails()
        );
        return ResponseEntity.ok(new TokenResponse(newAccessToken, req.refreshToken(), "Bearer", 900));
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@RequestBody RefreshRequest req) {
        refreshTokenService.revoke(req.refreshToken());
        return ResponseEntity.noContent().build();
    }
}
```

---

## OAuth2 / OpenID Connect (OIDC)

### Cấu hình OAuth2 Resource Server (validate JWT từ Identity Provider)

```yaml
spring:
  security:
    oauth2:
      resourceserver:
        jwt:
          issuer-uri: https://accounts.google.com
          # hoặc tự host Keycloak:
          # issuer-uri: http://keycloak:8080/realms/myapp
```

```java
@Bean
public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
    http
        .oauth2ResourceServer(oauth2 -> oauth2
            .jwt(jwt -> jwt
                .jwtAuthenticationConverter(jwtAuthConverter())
            )
        );
    return http.build();
}

@Bean
public JwtAuthenticationConverter jwtAuthConverter() {
    JwtGrantedAuthoritiesConverter grantedAuthoritiesConverter =
        new JwtGrantedAuthoritiesConverter();
    grantedAuthoritiesConverter.setAuthoritiesClaimName("roles");
    grantedAuthoritiesConverter.setAuthorityPrefix("ROLE_");

    JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
    converter.setJwtGrantedAuthoritiesConverter(grantedAuthoritiesConverter);
    return converter;
}
```

### OAuth2 Login (Authorization Code flow cho web app)

```yaml
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
```

```java
http.oauth2Login(oauth2 -> oauth2
    .userInfoEndpoint(userInfo -> userInfo
        .oidcUserService(oidcUserService())
    )
    .successHandler(oAuth2AuthSuccessHandler)
    .failureHandler(oAuth2AuthFailureHandler)
);
```

---

## Method-Level Security

```java
@EnableMethodSecurity  // phải có annotation này trong config
```

```java
@Service
public class OrderService {

    // Chỉ ADMIN hoặc MANAGER mới được xem tất cả orders
    @PreAuthorize("hasRole('ADMIN') or hasRole('MANAGER')")
    public List<Order> getAllOrders() { ... }

    // User chỉ xem order của mình
    @PreAuthorize("#userId == authentication.principal.id or hasRole('ADMIN')")
    public List<Order> getOrdersByUser(Long userId) { ... }

    // Filter kết quả sau khi execute (chỉ trả về items user được phép thấy)
    @PostAuthorize("returnObject.userId == authentication.principal.id or hasRole('ADMIN')")
    public Order getOrder(Long id) { ... }

    // Filter collection
    @PostFilter("filterObject.userId == authentication.principal.id")
    public List<Order> getMyOrders() { ... }

    // Tên phức tạp hơn với Spring Expression Language
    @PreAuthorize("@orderSecurity.canModify(authentication, #orderId)")
    public void cancelOrder(Long orderId) { ... }
}

// Custom Security Service (tham chiếu bằng @beanName trong SpEL)
@Component("orderSecurity")
public class OrderSecurityService {
    public boolean canModify(Authentication auth, Long orderId) {
        Order order = orderRepo.findById(orderId).orElseThrow();
        return order.getUserId().equals(getCurrentUserId(auth))
            || auth.getAuthorities().stream()
                   .anyMatch(a -> a.getAuthority().equals("ROLE_ADMIN"));
    }
}
```

---

## UserDetailsService – Tích hợp với DB

```java
@Service
@RequiredArgsConstructor
public class CustomUserDetailsService implements UserDetailsService {

    private final UserRepository userRepo;

    @Override
    @Transactional(readOnly = true)
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        User user = userRepo.findByEmail(username)
            .orElseThrow(() -> new UsernameNotFoundException("User not found: " + username));

        return org.springframework.security.core.userdetails.User.builder()
            .username(user.getEmail())
            .password(user.getPasswordHash())
            .roles(user.getRoles().stream().map(Role::getName).toArray(String[]::new))
            .accountExpired(!user.isActive())
            .credentialsExpired(user.isPasswordExpired())
            .disabled(!user.isEnabled())
            .build();
    }
}
```

---

## CORS Configuration

```java
@Bean
public CorsConfigurationSource corsConfigurationSource() {
    CorsConfiguration config = new CorsConfiguration();
    config.setAllowedOriginPatterns(List.of("https://*.example.com", "http://localhost:*"));
    config.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
    config.setAllowedHeaders(List.of("*"));
    config.setAllowCredentials(true);
    config.setMaxAge(3600L);

    UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
    source.registerCorsConfiguration("/api/**", config);
    return source;
}

// Trong SecurityFilterChain:
http.cors(cors -> cors.configurationSource(corsConfigurationSource()));
```

---

## Security Best Practices

```java
// 1. Password Encoding
@Bean
public PasswordEncoder passwordEncoder() {
    // BCrypt: strong, adaptive cost. Cost 12 = ~300ms per hash (brute-force resistant)
    return new BCryptPasswordEncoder(12);
}

// 2. Rate limiting login attempts (chống brute-force)
@Component
public class LoginAttemptService {
    private final Cache<String, Integer> attemptsCache = Caffeine.newBuilder()
        .expireAfterWrite(1, TimeUnit.HOURS)
        .build();

    public void recordFailure(String ip) {
        attemptsCache.asMap().merge(ip, 1, Integer::sum);
    }

    public boolean isBlocked(String ip) {
        Integer attempts = attemptsCache.getIfPresent(ip);
        return attempts != null && attempts >= 5;
    }
}

// 3. Security Headers (tự động với Spring Security)
// X-Content-Type-Options: nosniff
// X-Frame-Options: DENY
// X-XSS-Protection: 0 (modern browsers)
// Strict-Transport-Security (HTTPS only)

// 4. Secrets không hardcode
@Value("${app.jwt.secret}")  // từ environment variable hoặc Vault
private String jwtSecret;
```

---

## Trade-offs

| Approach | Security | Complexity | Scale |
|----------|----------|------------|-------|
| Session-based | Good (server control) | Low | Sticky sessions needed |
| JWT stateless | Good (if short TTL) | Medium | Excellent |
| OAuth2/OIDC | Best (delegation) | High | Excellent |
| API Key | Basic | Low | Easy |

| JWT TTL | Trade-off |
|---------|-----------|
| Short (5-15 min) | Secure, frequent refresh |
| Long (1 day+) | Convenient, harder to revoke |
| Refresh token rotation | Best of both worlds |

---

## Real-world Production

### Token Revocation (JWT + Redis Blacklist)
```java
// JWT là stateless nên không thể "revoke" natively
// Giải pháp: blacklist revoked tokens trong Redis

public void logout(String token) {
    long ttlSeconds = tokenProvider.getExpirationTime(token) - System.currentTimeMillis() / 1000;
    redis.opsForValue().set("blacklist:" + token, "1", ttlSeconds, TimeUnit.SECONDS);
}

// Trong JwtAuthFilter: check blacklist
if (redis.hasKey("blacklist:" + token)) {
    chain.doFilter(request, response);
    return; // reject
}
```

---

## Ghi chú

**Sub-topic tiếp theo:**
- `basics/data_access.md` – Spring Data JPA Specifications, QueryDSL, Projections
- `advanced/reactive_webflux.md` – Reactive Security (SecurityWebFilterChain)
- **Keywords:** SecurityContext propagation, Multi-tenancy security, PKCE (OAuth2), Keycloak, Auth0, Spring Authorization Server, Role hierarchy, ACL (Access Control List), Argon2 password encoder, TOTP (2FA), Remember-me token
