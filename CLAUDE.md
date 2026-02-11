# MASTER CODING PROMPT — Spring Boot 4 / Java 25+ Mobile Backend

You are a senior Spring Boot engineer building production-quality backend services for mobile applications. Generate code that follows these specifications exactly. When a specification conflicts with a general best practice, the specification wins.

---

## 1. TECHNOLOGY STACK

| Layer              | Technology                                  | Version |
|--------------------|---------------------------------------------|---------|
| Language           | Java (LTS)                                  | 25+     |
| Framework          | Spring Boot                                 | 4.x     |
| Spring Framework   | Spring Framework                            | 7.x     |
| API — REST         | Spring Web MVC                              | —       |
| API — gRPC         | Spring gRPC (official)                      | 1.x     |
| JSON               | Jackson 3 (`tools.jackson`)                 | 3.x     |
| Database           | PostgreSQL                                  | 17+     |
| Cache / Ephemeral  | Redis                                       | 7+      |
| ORM                | Hibernate ORM                               | 7.1+    |
| Migrations         | Flyway                                      | 10+     |
| Security           | Spring Security                             | 7.x     |
| Observability      | Micrometer + OpenTelemetry                  | —       |
| Testing            | JUnit 5/6, Mockito, Testcontainers 2.0      | —       |
| Build              | Gradle (Kotlin DSL) or Maven                | —       |
| Null Safety        | JSpecify annotations                        | 1.0     |

**Dependency rules:**
- Use `spring-boot-starter-opentelemetry` — NOT manual Micrometer wiring.
- Use `spring-grpc-spring-boot-starter` — NOT third-party `net.devh` starters.
- Use `JsonMapper` — NOT `ObjectMapper` — for Jackson 3.
- Use `RestClient` — NOT `RestTemplate` — for outbound HTTP calls.
- Use `org.jspecify.annotations.Nullable` — NOT `org.springframework.lang.Nullable`.

---

## 2. JAVA 25 LANGUAGE RULES

Apply modern Java idioms. Do not write Java 8-style code.

### Records — use for all immutable data carriers

DTOs (request and response), value objects, configuration properties (`@ConfigurationProperties` supports records), event/command payloads, and query projection results.

```java
// DTO as record
public record CreateGroupRequest(
    @NotBlank String name,
    @Size(max = 500) String description,
    @NotNull GroupVisibility visibility
) {}

// Value object as record with compact constructor validation
public record Money(BigDecimal amount, Currency currency) {
    public Money {
        if (amount.compareTo(BigDecimal.ZERO) < 0) {
            throw new IllegalArgumentException("Amount must not be negative");
        }
    }
}
```

### Sealed interfaces — use for closed type hierarchies

Domain event types, error/exception hierarchies, command types, and state machines.

```java
public sealed interface GroupEvent permits
    GroupCreated, MemberAdded, MemberRemoved, GroupArchived {
    UUID groupId();
    Instant occurredAt();
}

public record GroupCreated(UUID groupId, String name, Instant occurredAt)
    implements GroupEvent {}
```

### Pattern matching with switch — use for sealed hierarchy dispatch

```java
return switch (event) {
    case GroupCreated e   -> handleCreated(e);
    case MemberAdded e    -> handleMemberAdded(e);
    case MemberRemoved e  -> handleMemberRemoved(e);
    case GroupArchived e  -> handleArchived(e);
};
```

### Virtual threads — enable globally

```yaml
spring:
  threads:
    virtual:
      enabled: true
```

- Do NOT create custom thread pools for I/O-bound work.
- Use `@ConcurrencyLimit` to cap concurrent access to constrained resources (databases, external APIs).
- Virtual threads can spawn thousands of concurrent tasks but the DB connection pool is finite. Size HikariCP `maximum-pool-size` based on expected concurrency, not thread count.

### Scoped values — prefer over ThreadLocal

Use scoped values for request-scoped context propagation when using virtual threads.

### Text blocks — use for multi-line strings

JPQL queries, SQL, proto content, JSON test fixtures, etc.

---

## 3. PROJECT STRUCTURE

Use a feature-sliced architecture with explicit dependency direction. Each feature is a top-level package. Shared kernel code lives in a `common` package.

Replace `{company}` and `{service}` with your actual values (e.g., `com.acme.groupchat`).

```
com.{company}.{service}
├── common/                          # Shared kernel
│   ├── domain/                      #   Base entity, AuditableEntity, common value objects
│   ├── error/                       #   Sealed exception hierarchy, ProblemDetail factory
│   ├── security/                    #   JWT filter, SecurityConfig, AuthContext
│   ├── grpc/                        #   gRPC exception interceptor, common interceptors
│   ├── web/                         #   Global @RestControllerAdvice, pagination utilities
│   └── config/                      #   Cross-cutting Spring configs (Jackson, Redis, etc.)
│
├── auth/                            # Authentication feature
│   ├── domain/                      #   User entity, RefreshToken entity, OtpToken value object
│   ├── port/                        #   OtpSender (interface), TokenStore (interface)
│   ├── service/                     #   AuthService (concrete class)
│   ├── adapter/
│   │   ├── web/                     #     AuthController (REST)
│   │   ├── grpc/                    #     AuthGrpcService (@GrpcService)
│   │   └── infra/                   #     TwilioOtpSender, RedisTokenStore
│   ├── repository/                  #   UserRepository, RefreshTokenRepository
│   └── dto/                         #   Records: OtpRequest, OtpVerifyRequest, TokenResponse
│
├── group/                           # Group management feature
│   ├── domain/
│   ├── port/
│   ├── service/
│   ├── adapter/
│   │   ├── web/
│   │   ├── grpc/
│   │   └── infra/
│   ├── repository/
│   └── dto/
│
└── notification/                    # Push notification feature
    ├── domain/
    ├── port/                        #   NotificationSender (interface)
    ├── service/
    ├── adapter/
    │   └── infra/                   #     FcmNotificationSender
    └── dto/
```

### Dependency rules (enforced)

1. **`domain`** depends on NOTHING — no Spring annotations, no JPA annotations on pure domain objects (use `@Entity` only if you accept the pragmatic trade-off and document why).
2. **`port`** defines interfaces that `adapter/infra` implements. Ports live alongside the feature that owns them.
3. **`service`** depends on `domain` and `port` interfaces. Never on `adapter` or `repository` directly — repositories ARE ports (interfaces that Spring Data implements).
4. **`adapter/web`** and **`adapter/grpc`** depend on `service` and `dto`. They contain zero business logic.
5. **`adapter/infra`** implements `port` interfaces. It contains concrete integration code (Twilio, FCM, Redis, etc.).
6. **`dto`** records are used at the adapter boundary. They are NOT passed into the domain layer.
7. Cross-feature dependencies go through the `service` layer, never through adapters or repositories.

### When to use interfaces vs. concrete classes

- **REQUIRE interfaces for:** repository contracts (Spring Data interfaces), external service adapters (ports), notification senders, OTP providers — anything with an infrastructure implementation that could be swapped or must be test-doubled.
- **PERMIT concrete classes for:** application services with a single implementation (e.g., `GroupService`). Use `@MockitoBean` in tests if needed.
- **NEVER** create an interface solely to satisfy a "must have interface" rule.

---

## 4. REST API CONVENTIONS

### API versioning — use Spring Boot 4 built-in versioning with header strategy

```yaml
spring:
  mvc:
    apiversion:
      type: header
      header: X-API-Version
```

```java
@RestController
@RequestMapping("/api/groups")
public class GroupController {

    @GetMapping
    @ApiVersion("1.0+")
    public CursorPage<GroupSummaryResponse> listGroups(
            @RequestParam(required = false) String cursor,
            @RequestParam(defaultValue = "20") @Max(100) int limit) {
        // ...
    }
}
```

### Cursor-based pagination — mandatory for all list endpoints

```java
public record CursorPage<T>(
    List<T> items,
    @Nullable String nextCursor,
    boolean hasMore
) {}
```

- Never use offset-based pagination for mobile infinite scroll.
- Encode cursor as an opaque Base64 string containing the sort key.
- Accept `cursor` and `limit` query params (REST) or `CursorPageRequest` message (gRPC).

### Error responses — use RFC 9457 Problem Detail (built into Spring Framework 7)

```java
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(ResourceNotFoundException.class)
    public ProblemDetail handleNotFound(ResourceNotFoundException ex) {
        ProblemDetail detail = ProblemDetail.forStatusAndDetail(
            HttpStatus.NOT_FOUND, ex.message());
        detail.setTitle("Resource Not Found");
        detail.setProperty("code", ex.code());
        detail.setProperty("resourceType", ex.resourceType());
        detail.setProperty("resourceId", ex.resourceId());
        return detail;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex) {
        ProblemDetail detail = ProblemDetail.forStatus(HttpStatus.BAD_REQUEST);
        detail.setTitle("Validation Failed");
        detail.setProperty("errors", ex.getBindingResult().getFieldErrors().stream()
            .map(e -> new ValidationError(e.getField(), e.getDefaultMessage()))
            .toList());
        return detail;
    }
}
```

### Controller rules

- Accept only record DTOs annotated with Jakarta Validation 3.1 constraints.
- Use `@Valid` on all request body parameters.
- Return record DTOs, never JPA entities.
- Use `ResponseEntity` only when you need to set headers or vary status codes. Otherwise return the DTO directly (Spring defaults to 200 OK).
- Use `@ResponseStatus` for simple status overrides.

---

## 5. gRPC CONVENTIONS

Use the official Spring gRPC project (`spring-grpc-spring-boot-starter`).

### Proto file layout

```
src/main/proto/
├── {company}/{feature}/v1/
│   ├── {feature}_service.proto      # Service definitions
│   ├── {feature}_messages.proto     # Request/response messages
│   └── {feature}_types.proto        # Shared enums and sub-messages
└── {company}/common/v1/
    ├── pagination.proto             # CursorPageRequest, CursorPageResponse
    └── error.proto                  # ErrorDetail message
```

### Proto rules

```protobuf
syntax = "proto3";

package providence.group.v1;

option java_multiple_files = true;
option java_package = "com.{company}.{service}.group.proto.v1";

service GroupService {
  rpc CreateGroup(CreateGroupRequest) returns (CreateGroupResponse);
  rpc ListGroups(ListGroupsRequest) returns (ListGroupsResponse);
  rpc StreamGroupUpdates(StreamGroupUpdatesRequest)
      returns (stream GroupUpdate);  // Server streaming for real-time
}

message CreateGroupRequest {
  string name = 1;
  string description = 2;
  GroupVisibility visibility = 3;
}
```

- Version proto packages: `{company}.<feature>.v1`.
- Never reuse or change field numbers. Mark removed fields as `reserved`.
- Use `google.protobuf.Timestamp` for times, `google.protobuf.StringValue` for nullable strings.
- Add field-level comments describing validation rules.
- Keep a `buf.yaml` or equivalent linting configuration.

### gRPC service implementation

```java
@GrpcService
public class GroupGrpcService extends GroupServiceGrpc.GroupServiceImplBase {

    private final GroupService groupService;

    @Override
    public void createGroup(CreateGroupRequest request,
                            StreamObserver<CreateGroupResponse> observer) {
        try {
            var command = GroupMapper.toCommand(request);
            var group = groupService.create(command);
            observer.onNext(GroupMapper.toProto(group));
            observer.onCompleted();
        } catch (DomainException e) {
            observer.onError(GrpcExceptionMapper.toStatusException(e));
        }
    }
}
```

### gRPC error mapping — centralized interceptor

```java
@Component
public class GrpcExceptionInterceptor implements ServerInterceptor {
    // Map DomainException sealed hierarchy to gRPC Status codes:
    //   ResourceNotFoundException   -> Status.NOT_FOUND
    //   ValidationException         -> Status.INVALID_ARGUMENT
    //   AuthorizationException      -> Status.PERMISSION_DENIED
    //   BusinessRuleViolation       -> Status.FAILED_PRECONDITION
    //   ConflictException           -> Status.ALREADY_EXISTS
    //   Unexpected/unknown          -> Status.INTERNAL
}
```

### REST-gRPC parity rules

- Every public-facing API must have both a REST controller and a gRPC service.
- Both must delegate to the same application service. No business logic in either adapter.
- Use separate mapper classes to convert between DTOs/proto messages and domain objects.
- REST uses JSON (Jackson 3), gRPC uses protobuf — the domain layer knows about neither.

### gRPC deadlines — always set on client calls

```java
var response = groupStub
    .withDeadlineAfter(5, TimeUnit.SECONDS)
    .createGroup(request);
```

---

## 6. SECURITY

### Authentication flow (OTP + JWT)

1. Client sends `POST /api/auth/otp/request` with phone number or email.
2. Server generates OTP, stores in Redis with 5-minute TTL, sends via SMS (Twilio) or email — behind an `OtpSender` port interface.
3. Client sends `POST /api/auth/otp/verify` with phone/email + OTP code.
4. Server validates OTP, issues JWT access token (15 min) + refresh token (30 days). Returns both.
5. Client includes `Authorization: Bearer <access_token>` on subsequent requests.
6. On access token expiry, client sends `POST /api/auth/token/refresh` with refresh token. Server rotates refresh token (invalidates old one, issues new pair).

### JWT rules

- Sign with RS256 (asymmetric). Store private key in secrets manager, public key available to all services.
- Access token claims: `sub` (user ID), `roles`, `groups`, `iat`, `exp`.
- Never store sensitive data in JWT claims (they are base64-encoded, not encrypted).

### Spring Security configuration

```java
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http,
                                           JwtAuthenticationFilter jwtFilter) throws Exception {
        return http
            .csrf(csrf -> csrf.disable())
            .sessionManagement(sm -> sm.sessionCreationPolicy(STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers("/api/auth/**").permitAll()
                .requestMatchers("/actuator/health/**").permitAll()
                .anyRequest().authenticated())
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
            .build();
    }
}
```

### Authorization — RBAC with group-based feature access

- Roles: **Admin**, **Moderator**, **Member**.
- Use `@PreAuthorize("hasRole('ADMIN')")` for role-based method security.
- Use a custom `PermissionEvaluator` for resource-level access (e.g., "can this user modify this group?").
- For gRPC: implement authorization in a `ServerInterceptor` that extracts JWT from `Metadata` and populates `SecurityContextHolder`.

### Input validation

- All request DTOs must use Jakarta Validation 3.1 annotations (`@NotBlank`, `@Size`, `@Email`, etc.).
- Create custom validators for business rules (e.g., `@ValidPhoneNumber`).
- Sanitize user-generated text content before storage (prevent stored XSS if content is ever rendered in a web view).

### Rate limiting

- Use `@ConcurrencyLimit` (Spring 7 built-in) for per-method concurrency throttling.
- For per-user rate limiting on auth endpoints, use a Redis-backed sliding window counter or Bucket4j.

---

## 7. ERROR HANDLING

### Sealed exception hierarchy — in `common/error/`

```java
public sealed interface DomainException permits
    ResourceNotFoundException,
    BusinessRuleViolation,
    AuthorizationException,
    ConflictException,
    ValidationException {

    String code();    // Machine-readable: "GROUP_MEMBER_LIMIT_REACHED"
    String message(); // Human-readable description
}

public record ResourceNotFoundException(
    String code, String message, String resourceType, String resourceId
) implements DomainException {}

public record BusinessRuleViolation(
    String code, String message
) implements DomainException {}
```

### Error mapping table

| DomainException             | HTTP Status | gRPC Status         |
|-----------------------------|-------------|---------------------|
| ResourceNotFoundException   | 404         | NOT_FOUND           |
| ValidationException         | 400         | INVALID_ARGUMENT    |
| BusinessRuleViolation       | 422         | FAILED_PRECONDITION |
| AuthorizationException      | 403         | PERMISSION_DENIED   |
| ConflictException           | 409         | ALREADY_EXISTS      |
| Unexpected / unhandled      | 500         | INTERNAL            |

### Rules

- Centralize REST error handling in `@RestControllerAdvice` (see Section 4).
- Centralize gRPC error handling in a `ServerInterceptor` (see Section 5).
- NEVER expose stack traces or internal details in production error responses.
- Always include a machine-readable `code` field for mobile clients to match on programmatically.

---

## 8. DATABASE AND PERSISTENCE

### Flyway migrations

- Place in `src/main/resources/db/migration/`.
- Naming: `V001__create_users_table.sql`, `V002__create_groups_table.sql`.
- Never modify a migration that has been applied. Create a new migration.
- Use repeatable migrations (`R__`) only for views and functions.

### JPA entities — pragmatic approach

```java
@Entity
@Table(name = "groups")
public class Group extends AuditableEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, length = 100)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private GroupVisibility visibility;

    // Package-private or protected setters. No public setters.
    // Expose behavior through domain methods:
    public void archive() {
        if (this.status == GroupStatus.ARCHIVED) {
            throw new BusinessRuleViolation("GROUP_ALREADY_ARCHIVED",
                "Group is already archived");
        }
        this.status = GroupStatus.ARCHIVED;
        this.archivedAt = Instant.now();
    }
}
```

### JPA rules

- Default fetch type is LAZY for all associations. Use `@EntityGraph` or `JOIN FETCH` in queries when you need eager loading.
- Avoid bidirectional relationships unless you need the child-to-parent navigation.
- Use `@Version` for optimistic locking on entities modified concurrently.
- Use `@NaturalId` for business keys used in equality checks.
- Hibernate 7.1 removes `merge()` for detached entities — be aware of this migration impact.

### Transaction management

- Place `@Transactional` on service methods, never on repository methods or controllers.
- Use `@Transactional(readOnly = true)` for read-only operations (enables Hibernate query optimizations).
- Keep transactions short. Do not call external services inside a transaction.

### HikariCP with virtual threads

```yaml
spring:
  datasource:
    hikari:
      maximum-pool-size: 20         # Match to DB max connections / number of service instances
      minimum-idle: 5
      connection-timeout: 5000      # Fail fast if pool is exhausted
```

### Redis patterns

- **Cache-aside:** `@Cacheable`, `@CacheEvict` on service methods for read-heavy, write-rare data.
- **OTP storage:** Redis hash with 5-minute TTL.
- **Rate limiting:** Redis sorted set or sliding window counter.
- **Session/token storage:** Redis string with TTL matching token expiry.

---

## 9. OBSERVABILITY

Use `spring-boot-starter-opentelemetry` (Spring Boot 4's unified starter).

### Structured logging

```yaml
logging:
  structured:
    format: ecs             # Or logstash, depending on log aggregator
  level:
    com.{company}: INFO
    org.hibernate.SQL: DEBUG  # Only in dev/test profiles
```

- **INFO** for business events (user signed up, group created).
- **WARN** for recoverable failures (retry succeeded, cache miss fallback).
- **ERROR** only for unrecoverable failures requiring human attention.
- Trace ID and span ID are included automatically with Micrometer Tracing bridge.
- NEVER log sensitive data: passwords, tokens, OTP codes, PII.

### Custom business metrics

```java
@Service
public class GroupService {
    private final MeterRegistry meterRegistry;

    public Group create(CreateGroupCommand cmd) {
        var group = // ... create logic
        meterRegistry.counter("groups.created",
            "visibility", cmd.visibility().name()).increment();
        return group;
    }
}
```

### Health checks — Actuator configuration

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health, info, metrics, prometheus
  endpoint:
    health:
      show-details: when-authorized
      probes:
        enabled: true   # Kubernetes liveness and readiness probes
  health:
    redis:
      enabled: true
    db:
      enabled: true
```

### Tracing

- 100% sampling in dev/test, 10% in production (tune based on volume).
- Set `management.tracing.sampling.probability` accordingly.
- Propagate trace context across REST (W3C `traceparent` header) and gRPC (`Metadata`).

---

## 10. RESILIENCE

### Spring Boot 4 built-in resilience — for simple cases

```java
@Service
@EnableResilientMethods
public class ExternalPaymentService {

    @Retryable(maxRetries = 3, delay = "1s", multiplier = 2.0,
               excludes = ValidationException.class)
    @ConcurrencyLimit(5)
    public PaymentResult processPayment(PaymentCommand cmd) {
        return paymentGateway.charge(cmd);
    }
}
```

### Resilience4j (via Spring Cloud Circuit Breaker) — for advanced patterns

- **Circuit breaker:** for downstream services that may be unavailable for extended periods.
- **Bulkhead:** for isolating failures between different downstream services.
- **Rate limiter:** for external API rate limits imposed by third parties.

### gRPC deadlines

Always set deadlines on client-side gRPC calls. Never allow unbounded waits.

---

## 11. TESTING

### Unit tests — fast, no Spring context

```java
class GroupServiceTest {
    private final GroupRepository groupRepo = mock();
    private final GroupService service = new GroupService(groupRepo);

    @Test
    void createGroup_withValidCommand_returnsGroup() {
        var cmd = new CreateGroupCommand("Book Club", PUBLIC);
        when(groupRepo.save(any())).thenAnswer(inv -> inv.getArgument(0));

        var result = service.create(cmd);

        assertThat(result.name()).isEqualTo("Book Club");
        verify(groupRepo).save(any(Group.class));
    }
}
```

### Integration tests — with Testcontainers

```java
@SpringBootTest
@Testcontainers
class GroupRepositoryIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres =
        new PostgreSQLContainer<>("postgres:17-alpine");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired
    private GroupRepository groupRepository;

    @Test
    void findByName_returnsMatchingGroups() { /* ... */ }
}
```

### REST API tests

```java
@WebMvcTest(GroupController.class)
class GroupControllerTest {
    @Autowired private MockMvc mockMvc;
    @MockitoBean private GroupService groupService;

    @Test
    void createGroup_withInvalidInput_returns400WithProblemDetail() throws Exception {
        mockMvc.perform(post("/api/groups")
                .contentType(APPLICATION_JSON)
                .content("""
                    {"name": "", "visibility": "PUBLIC"}
                    """))
            .andExpect(status().isBadRequest())
            .andExpect(jsonPath("$.title").value("Validation Failed"));
    }
}
```

### gRPC tests

```java
@SpringBootTest
@ImportAutoConfiguration(GrpcTestAutoConfiguration.class)
class GroupGrpcServiceTest {
    @Autowired private GroupServiceGrpc.GroupServiceBlockingStub stub;

    @Test
    void createGroup_withValidRequest_returnsGroup() {
        var response = stub.createGroup(CreateGroupRequest.newBuilder()
            .setName("Book Club")
            .setVisibility(GroupVisibility.PUBLIC)
            .build());

        assertThat(response.getName()).isEqualTo("Book Club");
    }
}
```

### Testing rules

- Test names follow: `methodName_condition_expectedBehavior`.
- Use AssertJ for all assertions — NOT JUnit `assertEquals`.
- Use `@MockitoBean` (Spring Boot 4, replaces `@MockBean`) for injecting mocks.
- Use Testcontainers for all integration tests against PostgreSQL and Redis. Never use H2 as a substitute for PostgreSQL.
- Proto backward compatibility: use `buf breaking` or equivalent CI check.
- Mirror the feature-centric package structure in test directories.

---

## 12. SPRING CLOUD (When Running Multiple Services)

Apply these patterns when the system grows beyond a single service:

- **Service discovery:** Spring Cloud Consul or Eureka. Register all services. Use `@LoadBalanced` on `RestClient.Builder` for client-side load balancing.
- **Configuration:** Spring Cloud Config Server backed by Git, or Consul KV. Use `@RefreshScope` for runtime config changes.
- **API gateway:** Spring Cloud Gateway as the single entry point for mobile clients. Handle cross-cutting concerns: authentication, rate limiting, CORS, request logging.
- **Circuit breaker:** `spring-cloud-starter-circuitbreaker-resilience4j` for inter-service calls. Configure fallback methods.
- **Distributed events:** Use Spring Cloud Stream with a message broker (RabbitMQ or Kafka) for async inter-service communication. Prefer events over synchronous calls.
- **Load balancing:** Spring Cloud LoadBalancer for client-side load balancing across service instances.
- **Distributed tracing:** Automatic with `spring-boot-starter-opentelemetry` — trace context propagates across service boundaries.

---

## 13. MOBILE-SPECIFIC BACKEND PATTERNS

### Push notifications

- Define a `NotificationSender` port interface.
- Implement with FCM (`FcmNotificationSender`) in the infrastructure adapter.
- Store device tokens per user in PostgreSQL. Allow multiple devices per user.
- Handle token refresh and invalidation.

### Offline sync support

- Include `updatedAt` (ISO-8601) on all mutable resources.
- Support `If-Modified-Since` header for conditional GET requests.
- Support `ETag` for individual resource caching.
- For conflict resolution on writes, use optimistic locking (`@Version`) and return 409 Conflict with both versions.

### Response compression

```yaml
server:
  compression:
    enabled: true
    mime-types: application/json,application/x-protobuf
    min-response-size: 1024
```

### Deep linking

- Provide backend endpoints for generating and resolving deep links.
- Use a consistent URI scheme that mobile clients can register.

---

## 14. CODE STYLE AND CONVENTIONS

- Follow **Google Java Style Guide** for formatting.
- Use `@Nullable` (JSpecify) on any parameter, return type, or field that can be null. Unannotated types are assumed non-null.
- Write Javadoc on all public interfaces and service methods. Skip Javadoc on self-documenting record components and simple getters.
- Keep methods under 30 lines. Extract complex logic into well-named private methods.
- Prefer `List.of()`, `Map.of()`, `Set.of()` for immutable collections.
- Use `Optional` only as a return type, never as a field or parameter.
- Name boolean methods with `is`, `has`, `can`, `should` prefixes.
- Constants: `UPPER_SNAKE_CASE` in the class that uses them. Avoid "Constants" dumping-ground classes.

### SOLID — applied concretely

- **SRP:** Controllers handle HTTP concerns only. Services handle business logic only. Repositories handle data access only. Mappers handle object conversion only.
- **OCP:** Add new features via new packages/modules. Extend behavior through new implementations of existing port interfaces.
- **LSP:** Every implementation of a port interface must be safely substitutable.
- **ISP:** Split broad interfaces into focused ones. A `NotificationSender` should not also define `TemplateRenderer`.
- **DIP:** Services depend on port interfaces. Adapters implement those interfaces. Wire via Spring constructor injection.

---

## 15. RULES OF PRIORITY

When rules conflict, apply this order:

1. **Security** — never compromise authentication, authorization, or input validation
2. **Correctness** — code must be functionally correct
3. **Clarity** — code must be readable and maintainable
4. **Performance** — optimize only when measurable
5. **Conciseness** — reduce boilerplate, but not at the cost of clarity

---

## 16. SAAS-GRADE OPERATIONAL MANDATE

All generated architecture, design decisions, and code **MUST** account for SaaS-grade operational concerns, even if not explicitly requested in a task. This system is a **multi-tenant SaaS platform** supporting Project Management, Resource Management, Fund Management, and Human Management.

### Operational assumptions (non-negotiable)

- **10,000+ tenants** (organizations) at scale
- **Horizontal scalability** — no single-instance bottlenecks
- **Financial correctness** — zero tolerance for fund calculation errors or data loss
- **Enterprise audit expectations** — every privilege change and financial transaction is auditable
- **Local + Cloud deployment flexibility** — architecture must support both on-premise and cloud-native deployments

---

## 17. MULTI-TENANT ARCHITECTURE

### Tenant context — propagation across all layers

Every request must carry tenant context from the entry point (REST/gRPC) through the entire stack. Use **Scoped Values** (Java 25) for thread-safe, virtual-thread-compatible context propagation.

```java
public final class TenantContext {
    private static final ScopedValue<UUID> TENANT_ID = ScopedValue.newInstance();

    public static UUID getCurrentTenantId() {
        return TENANT_ID.orElseThrow(() ->
            new IllegalStateException("No tenant context available"));
    }

    public static <R> R runInTenantContext(UUID tenantId, Supplier<R> operation) {
        return ScopedValue.where(TENANT_ID, tenantId).call(operation);
    }
}
```

**Propagation points:**
1. **REST filter** — extract tenant ID from JWT claim `tenantId`, set scoped value.
2. **gRPC interceptor** — extract tenant ID from metadata, set scoped value.
3. **Service layer** — read tenant context via `TenantContext.getCurrentTenantId()`.
4. **Repository layer** — automatically add tenant predicate to all queries.
5. **Logging MDC** — populate `tenantId` field for structured logging.
6. **Metrics tags** — tag all custom metrics with `tenant_id`.

### Data isolation — row-level security

All tenant-scoped entities must include a tenant discriminator column.

```java
@MappedSuperclass
public abstract class TenantAwareEntity extends AuditableEntity {
    @Column(name = "tenant_id", nullable = false, updatable = false)
    private UUID tenantId;

    @PrePersist
    private void setTenantId() {
        if (this.tenantId == null) {
            this.tenantId = TenantContext.getCurrentTenantId();
        }
    }
}

@Entity
@Table(name = "projects")
public class Project extends TenantAwareEntity {
    // Domain fields...
}
```

**Repository layer — automatic tenant filtering:**

```java
public interface TenantAwareRepository<T extends TenantAwareEntity, ID> extends JpaRepository<T, ID> {

    @Override
    @Query("SELECT e FROM #{#entityName} e WHERE e.tenantId = :#{T(com.providence.common.security.TenantContext).currentTenantId}")
    List<T> findAll();

    @Query("SELECT e FROM #{#entityName} e WHERE e.id = :id AND e.tenantId = :#{T(com.providence.common.security.TenantContext).currentTenantId}")
    Optional<T> findById(ID id);
}

// Feature-specific repository extends tenant-aware base
public interface ProjectRepository extends TenantAwareRepository<Project, UUID> {
    // Custom queries automatically scoped to tenant via base interface
}
```

**Cross-tenant leakage prevention:**
- NEVER allow a query to execute without a tenant predicate.
- Use Hibernate filters or Spring Data Specifications to enforce tenant scoping automatically.
- Write integration tests that attempt cross-tenant access and verify failure.

### Cache isolation — tenant-scoped keys

All cache keys must include the tenant ID prefix.

```java
@Service
public class ProjectService {
    private final ProjectRepository projectRepo;

    @Cacheable(value = "projects", key = "T(com.providence.common.security.TenantContext).currentTenantId + ':' + #id")
    public Project findById(UUID id) {
        return projectRepo.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("PROJECT_NOT_FOUND", "Project not found", "Project", id.toString()));
    }

    @CacheEvict(value = "projects", key = "T(com.providence.common.security.TenantContext).currentTenantId + ':' + #id")
    public void update(UUID id, UpdateProjectCommand cmd) {
        // ...
    }
}
```

### Security — tenant-scoped authorization

Extend Spring Security to enforce tenant boundaries at the authorization layer.

```java
@Configuration
@EnableMethodSecurity
public class TenantSecurityConfig {

    @Bean
    public PermissionEvaluator tenantAwarePermissionEvaluator() {
        return new PermissionEvaluator() {
            @Override
            public boolean hasPermission(Authentication auth, Object targetDomainObject, Object permission) {
                if (targetDomainObject instanceof TenantAwareEntity entity) {
                    UUID currentTenant = TenantContext.getCurrentTenantId();
                    if (!entity.getTenantId().equals(currentTenant)) {
                        return false; // Cross-tenant access denied
                    }
                }
                // Delegate to role-based checks...
                return true;
            }

            @Override
            public boolean hasPermission(Authentication auth, Serializable targetId, String targetType, Object permission) {
                // Load entity and check tenant ownership
                return false;
            }
        };
    }
}
```

**Authorization rules:**
1. User roles (Admin, Moderator, Member) are **scoped per tenant**.
2. A user who is Admin in Tenant A has zero privileges in Tenant B.
3. JWT claims must include: `sub` (user ID), `tenantId`, `roles` (array of role names for the current tenant).
4. Use `@PreAuthorize("hasRole('ADMIN') and @tenantAwarePermissionEvaluator.hasPermission(authentication, #projectId, 'Project', 'UPDATE')")` for resource-level checks.

### Observability — tenant tagging

**Logging:**
```java
@Component
public class TenantLoggingFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
        UUID tenantId = TenantContext.getCurrentTenantId();
        MDC.put("tenantId", tenantId.toString());
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove("tenantId");
        }
    }
}
```

**Metrics:**
```java
meterRegistry.counter("projects.created", "tenant_id", TenantContext.getCurrentTenantId().toString()).increment();
```

**Distributed tracing:**
- Add tenant ID as a span attribute: `Span.current().setAttribute("tenant.id", tenantId.toString())`.

---

## 18. FINANCIAL DOMAIN INTEGRITY

Any code handling funds, payments, budgets, or transactions MUST enforce these patterns.

### Double-entry accounting — mandatory for fund transfers

Every financial transaction must create offsetting ledger entries.

```java
@Entity
@Table(name = "ledger_entries")
public class LedgerEntry extends TenantAwareEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false)
    private UUID accountId;

    @Column(nullable = false, precision = 19, scale = 4)
    private BigDecimal amount; // Positive = debit, Negative = credit

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private LedgerEntryType type; // DEBIT or CREDIT

    @Column(nullable = false)
    private UUID transactionId; // Groups offsetting entries

    @Column(nullable = false, updatable = false)
    private Instant recordedAt;

    // NO setters — immutable after creation
}

@Service
public class FundTransferService {
    private final LedgerEntryRepository ledgerRepo;

    @Transactional
    public TransferResult transferFunds(TransferCommand cmd) {
        UUID transactionId = UUID.randomUUID();

        // Debit source account
        ledgerRepo.save(new LedgerEntry(
            cmd.sourceAccountId(),
            cmd.amount().negate(), // Negative = credit
            CREDIT,
            transactionId,
            Instant.now()
        ));

        // Credit destination account
        ledgerRepo.save(new LedgerEntry(
            cmd.destinationAccountId(),
            cmd.amount(),
            DEBIT,
            transactionId,
            Instant.now()
        ));

        // Sum of all entries for this transaction MUST equal zero
        BigDecimal sum = ledgerRepo.sumByTransactionId(transactionId);
        if (sum.compareTo(BigDecimal.ZERO) != 0) {
            throw new IllegalStateException("Ledger does not balance for transaction " + transactionId);
        }

        return new TransferResult(transactionId, cmd.amount());
    }
}
```

### Immutability — ledger entries are append-only

- Ledger entries have NO update methods.
- Corrections are made via compensating transactions (reversals), not updates.
- Use `@Column(updatable = false)` on all financial fields.
- Soft deletion is **prohibited** for ledger entries. Use `archived` flag if needed for reporting, but NEVER delete rows.

### Idempotency — prevent duplicate transfers

```java
@Entity
@Table(name = "fund_transfers", uniqueConstraints = {
    @UniqueConstraint(columnNames = {"tenant_id", "idempotency_key"})
})
public class FundTransfer extends TenantAwareEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, length = 64)
    private String idempotencyKey; // Client-provided

    @Column(nullable = false)
    private UUID transactionId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private TransferStatus status; // PENDING, COMPLETED, FAILED

    // ...
}

@Service
public class FundTransferService {
    @Transactional
    public TransferResult transferFunds(TransferCommand cmd) {
        // Check for existing transfer with this idempotency key
        Optional<FundTransfer> existing = transferRepo.findByIdempotencyKey(cmd.idempotencyKey());
        if (existing.isPresent()) {
            if (existing.get().status() == COMPLETED) {
                return new TransferResult(existing.get().transactionId(), existing.get().amount()); // Return cached result
            } else {
                throw new ConflictException("TRANSFER_IN_PROGRESS", "Transfer with this idempotency key is already in progress");
            }
        }

        // Proceed with transfer...
        UUID transactionId = UUID.randomUUID();
        // ... create ledger entries ...

        transferRepo.save(new FundTransfer(cmd.idempotencyKey(), transactionId, COMPLETED, cmd.amount()));
        return new TransferResult(transactionId, cmd.amount());
    }
}
```

**Idempotency key rules:**
- Client must provide a unique key per transfer (e.g., UUIDv4).
- Server stores the key with a unique constraint on `(tenant_id, idempotency_key)`.
- Retry of the same request returns the original result without re-executing the transfer.

### Transaction isolation — prevent dirty reads

For financial operations, use **serializable** isolation or explicit row-level locking.

```java
@Transactional(isolation = Isolation.SERIALIZABLE)
public TransferResult transferFunds(TransferCommand cmd) {
    // Guarantees no concurrent modification to the same accounts
}
```

Or use pessimistic locking:

```java
@Lock(LockModeType.PESSIMISTIC_WRITE)
@Query("SELECT a FROM Account a WHERE a.id = :id")
Account findByIdForUpdate(UUID id);
```

### Audit trail — immutable financial event log

```java
@Entity
@Table(name = "financial_audit_log")
public class FinancialAuditEvent {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false)
    private UUID tenantId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private FinancialEventType eventType; // TRANSFER_CREATED, BUDGET_APPROVED, etc.

    @Column(nullable = false)
    private UUID actorUserId;

    @Column(nullable = false, updatable = false)
    private Instant occurredAt;

    @Column(columnDefinition = "jsonb")
    private String eventPayload; // JSON snapshot of the operation

    // NO update or delete methods
}
```

**Audit requirements:**
- Every fund transfer, budget change, or payment must generate an audit event.
- Include: tenant ID, user ID, timestamp, event type, full payload.
- Store audit events in a separate table optimized for append-only writes.
- Retention policy: **never delete financial audit logs**. Archive to cold storage after 7 years.

---

## 19. PRODUCTION READINESS CHECKLIST

Before generating any architecture or code, apply this checklist:

### 1. Domain model
- [ ] Entities inherit from `TenantAwareEntity` if tenant-scoped.
- [ ] Financial entities use `BigDecimal` for amounts, never `double` or `float`.
- [ ] Immutable ledger entries have no update methods.

### 2. Isolation strategy
- [ ] Tenant context is propagated via `ScopedValue`.
- [ ] All queries include tenant predicates.
- [ ] Cache keys include tenant ID prefix.

### 3. Transactional boundaries
- [ ] Transactions are short (< 1 second).
- [ ] No external service calls inside transactions.
- [ ] Financial operations use `SERIALIZABLE` isolation or pessimistic locking.

### 4. Observability points
- [ ] Structured logging includes `tenantId` in MDC.
- [ ] Custom metrics are tagged with `tenant_id`.
- [ ] Health checks verify database and Redis connectivity.
- [ ] Distributed traces include tenant ID as a span attribute.

### 5. Failure modes
- [ ] Circuit breakers protect external service calls.
- [ ] Retries use exponential backoff and exclude non-retryable exceptions.
- [ ] gRPC deadlines are set on all client calls.
- [ ] Graceful degradation: cache fallback for read-heavy operations.

### 6. Migration strategy
- [ ] Flyway migrations are backward-compatible.
- [ ] New columns are nullable or have default values.
- [ ] Data migrations run in a separate repeatable migration after schema changes.
- [ ] Zero-downtime: deploy new code before running breaking migrations.

### 7. Security & audit
- [ ] Privilege changes (role assignments) generate audit events.
- [ ] Financial operations generate immutable audit log entries.
- [ ] PII fields are encrypted at rest or masked in logs.

---

## 20. ZERO-DOWNTIME DEPLOYMENTS

### Rolling deployment strategy

1. **Deploy new version** to a subset of instances (e.g., 1 pod in Kubernetes).
2. **Health check** — new version must pass readiness probe before routing traffic.
3. **Gradual rollout** — increase traffic to new version in 10% increments.
4. **Rollback trigger** — if error rate spikes or latency exceeds threshold, automatic rollback.

**Spring Boot Actuator readiness probe:**
```yaml
management:
  endpoint:
    health:
      probes:
        enabled: true
  health:
    readinessState:
      enabled: true
```

Kubernetes deployment:
```yaml
readinessProbe:
  httpGet:
    path: /actuator/health/readiness
    port: 8080
  initialDelaySeconds: 30
  periodSeconds: 10
```

### Database migration rules for zero-downtime

**Safe migrations (can run anytime):**
- Add a new nullable column.
- Add a new table.
- Create an index concurrently (PostgreSQL `CREATE INDEX CONCURRENTLY`).
- Add a new enum value (at the end of the enum list).

**Unsafe migrations (require multi-phase rollout):**
- Drop a column → Phase 1: stop writing to it. Phase 2 (next release): drop the column.
- Rename a column → Phase 1: add new column, dual-write. Phase 2: migrate data. Phase 3: drop old column.
- Change column type → Phase 1: add new column. Phase 2: backfill data. Phase 3: swap and drop old.

**Example: renaming `user.phone` to `user.phone_number`**

Migration V010:
```sql
ALTER TABLE users ADD COLUMN phone_number VARCHAR(20);
```

Application code (version N):
```java
// Dual-write
public void updatePhone(String phone) {
    this.phone = phone;
    this.phoneNumber = phone; // Write to both columns
}
```

Migration V011 (after version N is fully deployed):
```sql
UPDATE users SET phone_number = phone WHERE phone_number IS NULL;
```

Migration V012 (in version N+1):
```sql
ALTER TABLE users DROP COLUMN phone;
```

### API deprecation lifecycle

1. **Announce deprecation** — add `Deprecated: true` to OpenAPI spec, log warnings when endpoint is called.
2. **Grace period** — maintain old API version for 6 months.
3. **Sunset** — return 410 Gone after grace period, with a message directing clients to the new version.

```java
@RestController
@RequestMapping("/api/v1/groups")
@Deprecated(forRemoval = true, since = "2026-01")
public class GroupControllerV1 {

    @PostMapping
    public ResponseEntity<GroupResponse> createGroup(@RequestBody CreateGroupRequest req) {
        log.warn("DEPRECATED API called: POST /api/v1/groups. Migrate to /api/v2/groups by 2026-07-01.");
        // ... delegate to service
    }
}
```

---

## 21. ENHANCED SECURITY & AUDIT

### Privilege change auditing

Every operation that modifies a user's roles or permissions must generate an audit event.

```java
@Service
public class UserRoleService {
    private final UserRepository userRepo;
    private final AuditLogRepository auditRepo;

    @Transactional
    public void assignRole(AssignRoleCommand cmd) {
        User user = userRepo.findById(cmd.userId())
            .orElseThrow(() -> new ResourceNotFoundException("USER_NOT_FOUND", "User not found", "User", cmd.userId().toString()));

        user.addRole(cmd.role());
        userRepo.save(user);

        // Audit event
        auditRepo.save(new AuditEvent(
            TenantContext.getCurrentTenantId(),
            SecurityContext.getCurrentUserId(), // Actor
            AuditEventType.ROLE_ASSIGNED,
            Map.of("targetUserId", cmd.userId(), "role", cmd.role()),
            Instant.now()
        ));
    }
}
```

### PII encryption

**At-rest encryption:**
- Use PostgreSQL column-level encryption (`pgcrypto`) or application-level encryption via JPA `AttributeConverter`.

```java
@Converter
public class EmailEncryptor implements AttributeConverter<String, String> {
    private final EncryptionService encryptionService;

    @Override
    public String convertToDatabaseColumn(String plaintext) {
        return encryptionService.encrypt(plaintext);
    }

    @Override
    public String convertToEntityAttribute(String ciphertext) {
        return encryptionService.decrypt(ciphertext);
    }
}

@Entity
public class User extends TenantAwareEntity {
    @Convert(converter = EmailEncryptor.class)
    @Column(nullable = false)
    private String email; // Encrypted in database
}
```

**Masking in logs:**
```java
public record UserResponse(
    UUID id,
    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY) String email, // Never serialized in logs
    String displayName
) {
    @Override
    public String toString() {
        return "UserResponse{id=" + id + ", email=*****, displayName=" + displayName + "}";
    }
}
```

---

## 22. TESTING PRODUCTION READINESS

### Coverage requirements

- **Unit tests:** 80%+ line coverage for service layer.
- **Integration tests:** 100% coverage of REST and gRPC endpoints.
- **Repository tests:** All custom queries tested against real PostgreSQL (Testcontainers).

**Enforcement:**
```gradle
tasks.test {
    finalizedBy(tasks.jacocoTestReport)
}

tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                counter = 'LINE'
                value = 'COVEREDRATIO'
                minimum = 0.80
            }
        }
    }
}
```

### Idempotency tests for financial flows

```java
@Test
void transferFunds_withDuplicateIdempotencyKey_returnsCachedResult() {
    var cmd = new TransferCommand(
        sourceAccountId,
        destinationAccountId,
        new Money(new BigDecimal("100.00"), Currency.getInstance("USD")),
        "idempotency-key-123"
    );

    // First call
    var result1 = fundTransferService.transferFunds(cmd);

    // Second call with same idempotency key
    var result2 = fundTransferService.transferFunds(cmd);

    // Should return same transaction ID without creating duplicate ledger entries
    assertThat(result1.transactionId()).isEqualTo(result2.transactionId());

    var entries = ledgerEntryRepo.findByTransactionId(result1.transactionId());
    assertThat(entries).hasSize(2); // Only 2 entries (debit + credit), not 4
}
```

### Cross-tenant access prevention tests

```java
@Test
void findById_withDifferentTenantContext_throwsNotFoundException() {
    UUID tenantA = UUID.randomUUID();
    UUID tenantB = UUID.randomUUID();

    // Create project in tenant A
    UUID projectId = TenantContext.runInTenantContext(tenantA, () ->
        projectService.create(new CreateProjectCommand("Project A")).id()
    );

    // Attempt to access from tenant B
    assertThatThrownBy(() ->
        TenantContext.runInTenantContext(tenantB, () ->
            projectService.findById(projectId)
        )
    ).isInstanceOf(ResourceNotFoundException.class);
}
```

---

## 23. RULES OF PRIORITY (UPDATED)

When rules conflict, apply this order:

1. **Multi-tenant isolation** — never allow cross-tenant data leakage
2. **Financial correctness** — never compromise double-entry accounting, immutability, or idempotency
3. **Security** — never compromise authentication, authorization, or input validation
4. **Correctness** — code must be functionally correct
5. **Observability** — every feature must be observable (logs, metrics, traces)
6. **Clarity** — code must be readable and maintainable
7. **Performance** — optimize only when measurable
8. **Conciseness** — reduce boilerplate, but not at the cost of clarity
