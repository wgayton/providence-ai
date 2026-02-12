# Providence AI - Claude Code Context

**Auto-loaded context for Claude Code sessions**

This file provides essential project context that Claude Code needs when working on the Providence AI SaaS platform. All patterns, standards, and architectural decisions described here must be followed.

---

## 🎯 Project Overview

**Providence AI** is an enterprise-grade, multi-tenant SaaS platform built on event-driven architecture with schema-per-tenant isolation. The platform provides resource management, project tracking, and financial operations with strict audit compliance and exactly-once processing guarantees.

**Core Capabilities:**
- Schema-per-tenant multi-tenancy (PostgreSQL schema isolation)
- Event-driven architecture via Debezium CDC + Kafka
- Outbox/Inbox patterns for exactly-once processing
- Universal idempotency for all state-changing operations
- Immutable audit logging for compliance
- Financial domain integrity (double-entry accounting)

---

## 📚 Critical Documentation

**Read these files in order when starting work:**

1. **[README.md](README.md)** — Project overview, tech stack, quick start
2. **[docs/architecture/ENGINEERING_STANDARDS.md](docs/architecture/ENGINEERING_STANDARDS.md)** — **MASTER CONSTITUTION** (2,160 lines, 28 sections)
3. **[docs/guides/GETTING_STARTED.md](docs/guides/GETTING_STARTED.md)** — Local development setup
4. **[docs/architecture/MULTI_TENANT_DESIGN.md](docs/architecture/MULTI_TENANT_DESIGN.md)** — Tenancy patterns and context propagation
5. **[docs/architecture/DATABASE_SCHEMA.md](docs/architecture/DATABASE_SCHEMA.md)** — Public schema reference
6. **[docs/architecture/EVENT_STREAMING.md](docs/architecture/EVENT_STREAMING.md)** — Kafka and CDC patterns
7. **[docs/examples/PROJECT_MANAGEMENT.md](docs/examples/PROJECT_MANAGEMENT.md)** — Complete feature example (copy this pattern!)

---

## 🏗️ Technology Stack

| Layer | Technology | Version | Notes |
|-------|-----------|---------|-------|
| **Language** | Java | 25+ | Virtual threads, ScopedValue, modern syntax |
| **Framework** | Spring Boot | 4.x | Spring Framework 7.x |
| **JSON** | Jackson | 3.x | Use `JsonMapper`, not `ObjectMapper` |
| **Database** | PostgreSQL | 17+ | Logical replication enabled |
| **Cache** | Redis | 7+ | Tenant-isolated caching |
| **Event Streaming** | Apache Kafka | 3.6+ | Schema Registry, AVRO/Protobuf |
| **CDC** | Debezium | 2.5+ | Outbox pattern via logical replication |
| **ORM** | Hibernate | 7.1+ | SCHEMA multi-tenancy mode |
| **Migrations** | Flyway | 10+ | Public + tenant schema migrations |
| **Testing** | JUnit | 5/6 | Testcontainers 2.0 for integration tests |
| **Observability** | Micrometer | Latest | OpenTelemetry integration |

---

## 🔐 Critical Architectural Patterns

### 1. Schema-Per-Tenant Multi-Tenancy

**Every tenant gets a dedicated PostgreSQL schema:**
- Tenant schemas: `t_<tenant_slug>` (e.g., `t_acme`, `t_globex`)
- Public schema: Cross-tenant infrastructure (`tenants`, `outbox_events`, `audit_log`, `idempotency_keys`, `inbox_events`)
- Hibernate multi-tenancy: `SCHEMA` mode with `SchemaPerTenantConnectionProvider`
- Connection setup: `SET search_path TO t_<tenant>, public` on acquire

**Tenant Context Propagation:**
```java
// Java 25 ScopedValue (virtual thread compatible)
public static final ScopedValue<String> TENANT_ID = ScopedValue.newInstance();

// Resolution priority: JWT claim → HTTP header → subdomain
String tenantId = TenantContext.getCurrentTenantId();
```

**Rules:**
- ALL business entities must be in tenant schemas (NEVER in public schema)
- ALL queries include tenant predicates (enforced by schema isolation)
- ALL logs include `tenantId` in MDC
- ALL metrics tagged with `tenant_id`
- Cache keys prefixed with tenant: `{tenant}::{key}`

### 2. Event-Driven with Debezium Outbox Pattern

**Transactional Outbox Pattern:**
```java
@Transactional
public ProjectId createProject(CreateProjectCommand cmd) {
    // 1. Mutate domain aggregate
    var project = Project.create(cmd);
    projectRepository.save(project);

    // 2. Write outbox event in SAME transaction
    var event = new ProjectCreatedEvent(project);
    outboxRepository.save(OutboxEvent.from(event));

    return project.getId();
}
```

**Flow:**
1. Domain mutation + outbox write in same transaction (atomicity guaranteed)
2. Debezium CDC reads `public.outbox_events` via PostgreSQL logical replication
3. EventRouter transform routes to Kafka topic: `ecap.events.ProjectCreated`
4. Partition key: `tenant_id` (ordering guarantees within tenant)
5. Consumers process events via Inbox pattern (exactly-once)

**Kafka Topic Naming:**
- Events: `ecap.events.<EventType>` (e.g., `ecap.events.ProjectCreated`)
- Commands: `ecap.commands.<CommandType>` (e.g., `ecap.commands.ProvisionTenant`)
- DLQ: `ecap.dlq.<original-topic-name>` (e.g., `ecap.dlq.events.ProjectCreated`)

**Partitioning Strategy:**
- Partition key: `tenant_id` (ordering within tenant)
- Default partitions: 12 (adjust based on tenant count and throughput)

### 3. Inbox Pattern for Consumer Deduplication

**All Kafka consumers MUST use Inbox pattern:**
```java
@KafkaListener(topics = "ecap.events.ProjectCreated")
public void handle(ProjectCreatedEvent event) {
    // 1. Check inbox for duplicate
    if (inboxRepository.existsByEventId(event.getEventId())) {
        log.debug("Duplicate event {}, skipping", event.getEventId());
        return; // Already processed
    }

    // 2. Process event + write inbox record in same transaction
    try {
        processEvent(event);
        inboxRepository.save(new InboxEvent(event));
    } catch (Exception e) {
        throw e; // Kafka redelivery
    }
}
```

**Inbox Table:**
- Primary key: `(tenant_id, consumer_name, event_id)`
- Guarantees exactly-once effects (idempotent processing)
- Prevents duplicate processing on Kafka redelivery

### 4. Universal Idempotency

**ALL state-changing operations REQUIRE idempotency keys:**

**REST API:**
```
POST /api/v1/projects
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

**gRPC:**
```protobuf
message CreateProjectRequest {
  string idempotency_key = 1; // Required for mutations
  // ... other fields
}
```

**Implementation:**
```java
// 1. Check idempotency cache
var cacheKey = IdempotencyKey.of(tenantId, principalId, "CreateProject", idempotencyKey);
var cached = idempotencyRepository.findById(cacheKey);
if (cached.isPresent()) {
    return cached.get().getResponse(); // Return cached result
}

// 2. Execute command
var result = executeCommand(cmd);

// 3. Cache result (24h TTL)
idempotencyRepository.save(new IdempotencyRecord(cacheKey, result));
return result;
```

**Rules:**
- Required for: POST, PUT, PATCH, DELETE (REST) and all gRPC mutations
- Cache in `public.idempotency_keys` for 24 hours
- Return cached response on duplicate key (200 OK, not 409 Conflict)
- Composite key: `(tenant_id, principal_id, command_name, idempotency_key)`

### 5. Immutable Audit Logging

**ALL state changes logged to `public.audit_log`:**
```java
auditService.log(AuditEvent.builder()
    .tenantId(tenantId)
    .eventType("PROJECT_CREATED")
    .actorId(userId)
    .aggregateType("Project")
    .aggregateId(projectId)
    .payload(Map.of("name", projectName, "budget", budget))
    .occurredAt(Instant.now())
    .build());
```

**Critical Rules:**
- NEVER delete audit logs (triggers prevent UPDATE/DELETE)
- Archive to cold storage after 7 years for compliance
- Include: actor_id, event_type, aggregate_id, payload (JSONB), timestamp
- Log privilege changes, financial operations, and data mutations

### 6. Financial Domain Integrity

**Double-Entry Accounting (Immutable Ledger):**
```java
// Every transfer creates offsetting entries
@Transactional(isolation = Isolation.SERIALIZABLE)
public TransferId transfer(TransferCommand cmd) {
    // Debit source account
    ledger.createEntry(LedgerEntry.builder()
        .accountId(cmd.getSourceAccountId())
        .amount(cmd.getAmount().negate()) // Negative = debit
        .build());

    // Credit destination account
    ledger.createEntry(LedgerEntry.builder()
        .accountId(cmd.getDestinationAccountId())
        .amount(cmd.getAmount()) // Positive = credit
        .build());

    return transferId;
}
```

**Rules:**
- Use `BigDecimal` for amounts (NEVER `float` or `double`)
- Store amounts as integers (cents: amount × 100) in database
- Immutable ledger entries (no updates, only new entries)
- Idempotency keys prevent duplicate transfers
- SERIALIZABLE isolation or pessimistic locking for critical operations
- Currency stored separately (ISO 4217 codes: USD, EUR, etc.)

### 7. Clean Architecture Enforcement

**Feature-Sliced Package Structure:**
```
com.providence.{feature}/
├── domain/                 # Pure domain logic (NO Spring)
│   ├── Project.java       # @Entity aggregate root
│   ├── ProjectId.java     # Value object (record)
│   └── event/
│       └── ProjectCreatedEvent.java  # Sealed domain event
│
├── service/               # Application layer
│   └── ProjectService.java  # @Service with @Transactional
│
├── repository/            # Infrastructure (Spring Data)
│   └── ProjectRepository.java  # JpaRepository
│
├── adapter/
│   ├── web/               # REST controllers
│   │   └── ProjectController.java
│   ├── grpc/              # gRPC services
│   │   └── ProjectGrpcService.java
│   └── infra/             # External integrations
│       └── NotificationClient.java
│
└── dto/                   # Request/response records
    ├── CreateProjectRequest.java
    └── ProjectResponse.java
```

**Dependency Rules:**
- Domain layer: Pure logic, NO Spring annotations (except pragmatic `@Entity`)
- Application layer: Services with `@Transactional` boundaries
- Infrastructure layer: Repositories, Kafka consumers, external clients
- Presentation layer: REST/gRPC adapters, DTOs only
- Dependency direction: Inner → Outer (NEVER reversed)

---

## 📋 Database Schema Reference

### Public Schema (Cross-Tenant Infrastructure)

**Tables:**
1. **`public.tenants`** — Tenant registry (id, slug, schema_name, status, subscription_tier)
2. **`public.outbox_events`** — Debezium CDC source (aggregate_type, event_type, payload JSONB)
3. **`public.audit_log`** — Immutable audit trail (event_type, actor_id, aggregate_id, payload JSONB)
4. **`public.idempotency_keys`** — Universal idempotency cache (24h TTL)
5. **`public.inbox_events`** — Kafka consumer deduplication (tenant_id, consumer_name, event_id)

**Migrations:**
- Location: `src/main/resources/db/migration/public/`
- Versioning: `V001__`, `V002__`, etc.
- Applied to: Public schema only

### Tenant Schemas (Per-Tenant Business Data)

**Naming:** `t_<tenant_slug>` (e.g., `t_acme`)

**Business Tables (examples):**
- `projects` — Project management entities
- `resources` — Resource allocation
- `ledger_entries` — Financial transactions (double-entry)
- `allocations` — Resource-project assignments

**Migrations:**
- Location: `src/main/resources/db/migration/tenant/`
- Applied to: ALL tenant schemas on creation and upgrade
- Flyway pattern: Execute tenant migrations for each `t_*` schema

---

## 🚀 Local Development

**Quick Start:**
```bash
# 1. Start infrastructure (PostgreSQL, Kafka, Redis, Debezium)
cd src/main/resources/db/migration/public
docker compose up -d

# 2. Verify services
docker compose ps

# 3. Run Flyway migrations
./gradlew flywayMigrate

# 4. Create demo tenant
psql -h localhost -U postgres -d providence -f scripts/create-tenant.sql

# 5. Configure Debezium connector
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @scripts/debezium-connector.json

# 6. Start application
./gradlew bootRun

# 7. Test outbox pattern
curl -X POST http://localhost:8080/api/v1/projects \
  -H "X-Tenant-ID: acme" \
  -H "Idempotency-Key: $(uuidgen)" \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Project", "budget": 100000}'
```

**Docker Compose Services:**
- PostgreSQL: `localhost:5432` (user: postgres, password: postgres, db: providence)
- Redis: `localhost:6379`
- Kafka: `localhost:9092`
- Kafka UI: `http://localhost:8080`
- Debezium Connect: `localhost:8083`

---

## 🧪 Testing Standards

**Coverage Requirements:**
- Unit tests: 80%+ line coverage
- Integration tests: 100% endpoint coverage

**Test Categories:**

### Unit Tests (No Spring Context)
```java
@ExtendWith(MockitoExtension.class)
class ProjectServiceTest {
    @Mock private ProjectRepository repository;
    @InjectMocks private ProjectService service;

    @Test
    void createProject_shouldSaveAndReturnId() {
        // Arrange, Act, Assert
    }
}
```

### Integration Tests (Testcontainers)
```java
@SpringBootTest
@Testcontainers
class ProjectIntegrationTest {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:17");

    @Container
    static KafkaContainer kafka = new KafkaContainer(DockerImageName.parse("confluentinc/cp-kafka:7.5.0"));

    @Test
    void createProject_shouldPublishEventToKafka() {
        // Given, When, Then
    }
}
```

### Critical Test Scenarios (REQUIRED)
1. **Idempotency Tests:** Duplicate keys return cached responses
2. **Cross-Tenant Tests:** Verify tenant isolation (expect failures)
3. **Inbox Tests:** Duplicate Kafka events are skipped
4. **Outbox Tests:** Domain mutations publish events to Kafka
5. **Financial Tests:** Ledger balances sum to zero (double-entry)
6. **Validation Tests:** Invalid inputs return 400 with ProblemDetail

---

## 🔒 Security Patterns

**Authentication:**
- OTP (One-Time Password) for initial auth
- JWT (RS256 asymmetric) for session tokens
- Token claims: `sub` (user ID), `tenant_id`, `roles`, `exp`

**Authorization:**
- RBAC (Role-Based Access Control) with Spring Security
- Tenant-scoped roles: `TENANT_ADMIN`, `PROJECT_MANAGER`, `VIEWER`
- Method security: `@PreAuthorize("hasRole('TENANT_ADMIN')")`

**Multi-Tenant Isolation:**
- Database-level: Schema-per-tenant (PostgreSQL enforced)
- Application-level: Tenant context checks in services
- Test isolation: Attempt cross-tenant access, verify 403 Forbidden

**Input Validation:**
- Jakarta Validation 3.1 constraints on all DTOs
- Example: `@NotBlank`, `@Size(min=1, max=255)`, `@Email`, `@Pattern`

**Error Handling:**
- RFC 9457 ProblemDetail for structured errors
- Format: `{"type": "...", "title": "...", "status": 400, "detail": "...", "instance": "..."}`

---

## 📊 Observability

**Structured Logging (Logback + MDC):**
```java
MDC.put("tenantId", tenantId);
MDC.put("correlationId", correlationId);
MDC.put("userId", userId);

log.info("Project created: projectId={}, name={}", projectId, projectName);
```

**Metrics (Micrometer):**
```java
// Tag with tenant_id for multi-tenant visibility
meterRegistry.counter("project.created", "tenant", tenantId).increment();
meterRegistry.timer("project.create.duration", "tenant", tenantId).record(duration);
```

**Distributed Tracing (OpenTelemetry):**
- Automatic instrumentation for HTTP, gRPC, JDBC, Kafka
- Trace context propagation: `traceparent` header (W3C standard)
- Span attributes: `tenant.id`, `user.id`, `http.method`, `db.statement`

**Health Checks:**
- Spring Boot Actuator: `/actuator/health`
- Custom health indicators: Database connectivity, Kafka producer, Redis cache

---

## ⚠️ Production Readiness Checklist

**Before implementing any feature, verify:**

- [ ] **Domain Model:** Uses `BigDecimal` for financial amounts
- [ ] **Multi-Tenancy:** Tenant context propagation via `ScopedValue`
- [ ] **Data Isolation:** All queries include tenant predicates (schema-per-tenant enforces this)
- [ ] **Outbox Pattern:** Event written in same transaction as domain mutation
- [ ] **Inbox Pattern:** Kafka consumers check for duplicate events
- [ ] **Idempotency:** All state-changing endpoints require `Idempotency-Key`
- [ ] **Audit Logging:** Events logged for privilege changes and financial operations
- [ ] **Structured Logging:** Includes `tenantId` and `correlationId` in MDC
- [ ] **Metrics:** Custom metrics tagged with `tenant_id`
- [ ] **Circuit Breakers:** Applied to external service calls
- [ ] **gRPC Deadlines:** Set on all client calls (e.g., 5s timeout)
- [ ] **Graceful Degradation:** Fallback behavior with caching
- [ ] **Testing:** Includes idempotency and cross-tenant isolation verification
- [ ] **Documentation:** Updated API docs and architecture diagrams

---

## 🎓 Common Workflows

### Adding a New Feature

1. **Read Example:** Study `docs/examples/PROJECT_MANAGEMENT.md`
2. **Create Package:** `com.providence.{feature}/domain`, `service`, `repository`, `adapter`, `dto`
3. **Domain Layer:** Define aggregates, value objects, domain events
4. **Application Layer:** Create service with `@Transactional` boundaries
5. **Infrastructure:** JPA repositories, Kafka consumers
6. **Presentation:** REST controllers, gRPC services, DTOs
7. **Testing:** Unit tests (80%+), integration tests (100% endpoints)
8. **Documentation:** Update architecture docs if introducing new patterns

### Creating a New Tenant Schema Migration

1. Create SQL file: `src/main/resources/db/migration/tenant/V{XXX}__{description}.sql`
2. Define table schema with tenant-specific business entities
3. Test migration on local dev tenant: `./gradlew flywayMigrate`
4. Verify schema applied to all `t_*` schemas

### Debugging Outbox Pattern

1. Check outbox table: `SELECT * FROM public.outbox_events WHERE processed_at IS NULL;`
2. Verify Debezium connector: `curl http://localhost:8083/connectors/providence-outbox-connector/status`
3. Check Kafka topic: `kafka-console-consumer --bootstrap-server localhost:9092 --topic ecap.events.ProjectCreated --from-beginning`
4. Review Debezium logs: `docker logs debezium-connect`

### Handling Kafka Consumer Failures

1. Check DLQ topic: `ecap.dlq.events.ProjectCreated`
2. Review error logs in consumer
3. Fix root cause (data format, business logic, external service)
4. Replay DLQ messages with manual processing or reprocessing job

---

## 📞 Getting Help

**Priority 1: Read Documentation**
- Start with `docs/architecture/ENGINEERING_STANDARDS.md` (master reference)
- Check `docs/examples/PROJECT_MANAGEMENT.md` for complete feature example

**Priority 2: Search Codebase**
- Use Grep/Glob tools to find similar patterns
- Study existing implementations before creating new code

**Priority 3: Ask Clarifying Questions**
- Use AskUserQuestion tool if requirements are unclear
- Verify architectural decisions before implementing

**Priority 4: External Resources**
- Spring Boot 4 docs: https://spring.io/projects/spring-boot
- Debezium outbox pattern: https://debezium.io/documentation/reference/stable/transformations/outbox-event-router.html
- Kafka best practices: https://kafka.apache.org/documentation/

---

## 🚨 Critical Rules (NEVER VIOLATE)

1. **NEVER delete audit logs** (triggers prevent this, but don't try to circumvent)
2. **NEVER use float/double for money** (always `BigDecimal`)
3. **NEVER skip idempotency keys** for state-changing operations
4. **NEVER bypass tenant context checks** (security violation)
5. **NEVER commit sensitive data** (credentials, API keys, PII)
6. **NEVER use `ObjectMapper`** (use `JsonMapper` in Jackson 3)
7. **NEVER put business entities in public schema** (tenant schema only)
8. **NEVER skip outbox pattern** for domain events (atomicity guarantee)
9. **NEVER skip inbox pattern** for Kafka consumers (exactly-once guarantee)
10. **NEVER modify ledger entries** after creation (immutability guarantee)

---

## 📦 Key Files & Locations

**Configuration:**
- Application config: `src/main/resources/application.yml`
- Docker Compose: `src/main/resources/db/migration/public/docker-compose.yml`
- Debezium connector: `scripts/debezium-connector.json`

**Migrations:**
- Public schema: `src/main/resources/db/migration/public/`
- Tenant schema: `src/main/resources/db/migration/tenant/`

**Documentation:**
- Architecture: `docs/architecture/`
- Guides: `docs/guides/`
- Examples: `docs/examples/`

**Source Code:**
- Main: `src/main/java/com/providence/`
- Tests: `src/test/java/com/providence/`

---

**This CLAUDE.md file is automatically loaded by Claude Code at the start of each session. All patterns and rules described here are mandatory. Refer to linked documentation for detailed specifications.**

**Last Updated:** 2026-02-12
**Version:** 1.0.0
**Project:** Providence AI SaaS Platform
