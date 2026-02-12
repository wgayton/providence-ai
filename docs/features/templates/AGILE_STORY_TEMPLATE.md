# [Feature Name] - User Story

> **Story ID:** PROV-XXX
> **Author:** [Your Name]
> **Date:** YYYY-MM-DD
> **Status:** Draft | Ready | In Progress | Done

---

## 📖 User Story

**As a** [role/actor]
**I want to** [capability/action]
**So that** [business value/outcome]

---

## ✅ Acceptance Criteria

**Must Have (Required):**
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

**Should Have (Nice to Have):**
- [ ] Optional criterion 1
- [ ] Optional criterion 2

**Won't Have (Out of Scope):**
- Explicitly excluded item 1
- Explicitly excluded item 2

---

## 🎯 Business Context

### Problem Statement
[What problem does this solve? Why does it matter?]

### Target Users
- **Primary:** [e.g., Tenant Administrators]
- **Secondary:** [e.g., Project Managers, Viewers]

### Success Metrics
- [Metric 1: e.g., Reduce manual work by X%]
- [Metric 2: e.g., Improve response time to Y seconds]

---

<details>
<summary><strong>🏗️ Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Feature Scope

**Affected Domains:**
- [ ] Project Management
- [ ] Resource Management
- [ ] Fund Management
- [ ] Human Management
- [ ] Tenant Administration

**Integration Points:**
- APIs: [REST endpoints, gRPC services]
- Events: [Domain events emitted]
- Consumers: [Services that listen to events]

---

## Database Schema

**Tenant Schema Changes** (`t_<tenant>`):
```sql
-- Example: New table or columns required
CREATE TABLE IF NOT EXISTS projects (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    -- ...
);
```

**Public Schema Changes** (if any):
```sql
-- Only for cross-tenant infrastructure (outbox, audit, etc.)
```

**Migration File:** `V{XXX}__{description}.sql` in `/src/main/resources/db/migration/tenant/`

---

## Domain Events

**Events Emitted** (via Outbox Pattern):
```java
// Example:
ProjectCreatedEvent {
    eventId: UUID
    tenantId: String
    projectId: UUID
    name: String
    createdBy: UUID
    occurredAt: Instant
}
```

**Kafka Topics:**
- `ecap.events.{EventType}` (e.g., `ecap.events.ProjectCreated`)

**Events Consumed:**
- `ecap.events.{EventType}` → [Consumer service name]

---

## API Endpoints

**REST:**
```http
POST /api/v1/{resource}
GET /api/v1/{resource}/{id}
PUT /api/v1/{resource}/{id}
DELETE /api/v1/{resource}/{id}
```

**gRPC:**
```protobuf
service {ServiceName} {
    rpc Create{Resource}(Create{Resource}Request) returns (Create{Resource}Response);
    rpc Get{Resource}(Get{Resource}Request) returns (Get{Resource}Response);
}
```

---

## Implementation Checklist

### Domain Layer (`com.providence.{feature}.domain`)
- [ ] Value objects (e.g., `ProjectId`, `ProjectName`)
- [ ] Aggregate root entity (e.g., `Project.java`)
- [ ] Domain events (sealed interface, records)
- [ ] Business rules and invariants

### Application Layer (`com.providence.{feature}.application`)
- [ ] Service class with `@Transactional` boundaries
- [ ] Command objects (immutable records)
- [ ] DTOs (request/response records)
- [ ] Validation with Jakarta Validation 3.1

### Infrastructure Layer (`com.providence.{feature}.infrastructure`)
- [ ] JPA repository (extends `JpaRepository`)
- [ ] Outbox repository integration
- [ ] Audit logging integration

### Adapter Layer (`com.providence.{feature}.adapter`)
- [ ] REST controller with `@RestController`
- [ ] gRPC service (if applicable)
- [ ] Kafka consumer (if consuming events)
- [ ] DTOs with OpenAPI annotations

### Cross-Cutting Concerns
- [ ] Multi-tenancy: Tenant context propagation via `ScopedValue`
- [ ] Idempotency: `Idempotency-Key` header support
- [ ] Outbox pattern: Events written in same transaction
- [ ] Inbox pattern: Kafka consumers check for duplicates
- [ ] Audit logging: All state changes logged
- [ ] Structured logging: MDC includes `tenantId`, `correlationId`, `userId`
- [ ] Metrics: Custom metrics tagged with `tenant_id`

---

## Testing Requirements

### Unit Tests (No Spring Context)
```java
@ExtendWith(MockitoExtension.class)
class {Feature}ServiceTest {
    // Test business logic in isolation
    // Target: 80%+ line coverage
}
```

**Test Cases:**
- [ ] Happy path: Valid input produces expected output
- [ ] Validation: Invalid input throws appropriate exceptions
- [ ] Business rules: Domain invariants enforced

### Integration Tests (Testcontainers)
```java
@SpringBootTest
@Testcontainers
class {Feature}IntegrationTest {
    // Test full stack with real PostgreSQL, Kafka, Redis
    // Target: 100% endpoint coverage
}
```

**Test Scenarios:**
- [ ] **Happy Path:** Create resource → Event published → Consumer processes
- [ ] **Idempotency:** Duplicate `Idempotency-Key` returns cached response (200 OK)
- [ ] **Cross-Tenant Isolation:** Attempt to access another tenant's data → 403 Forbidden
- [ ] **Inbox Deduplication:** Replay Kafka event → Consumer skips duplicate
- [ ] **Validation:** Invalid input → 400 Bad Request with ProblemDetail
- [ ] **Audit Logging:** State change → Audit log entry created
- [ ] **Error Handling:** External service failure → Graceful degradation or retry

---

## Security & Authorization

**Authentication:**
- JWT required in `Authorization: Bearer <token>` header
- Token claims: `sub` (user ID), `tenant_id`, `roles`, `exp`

**Authorization:**
- [ ] `@PreAuthorize` annotations on service methods
- [ ] Required roles: [e.g., `TENANT_ADMIN`, `PROJECT_MANAGER`]
- [ ] Tenant isolation verified in integration tests

---

## Observability

**Logging:**
```java
MDC.put("tenantId", tenantId);
MDC.put("correlationId", correlationId);
log.info("Action completed: resourceId={}, detail={}", id, detail);
```

**Metrics:**
```java
meterRegistry.counter("{feature}.created", "tenant", tenantId).increment();
meterRegistry.timer("{feature}.create.duration").record(duration);
```

**Tracing:**
- Automatic OpenTelemetry instrumentation
- Span attributes: `tenant.id`, `user.id`, `http.method`

---

## Production Readiness

- [ ] **Financial Amounts:** Uses `BigDecimal` (NEVER float/double)
- [ ] **Multi-Tenancy:** `ScopedValue` for tenant context
- [ ] **Data Isolation:** Queries scoped to tenant schema
- [ ] **Outbox Pattern:** Domain mutation + event in same transaction
- [ ] **Inbox Pattern:** Kafka consumers deduplicate via inbox table
- [ ] **Idempotency:** All state-changing operations require `Idempotency-Key`
- [ ] **Audit Logging:** Privilege changes and financial operations logged
- [ ] **Circuit Breakers:** Applied to external service calls
- [ ] **gRPC Deadlines:** Set on all client calls (e.g., 5s timeout)
- [ ] **Graceful Degradation:** Fallback behavior defined
- [ ] **Documentation:** API docs and architecture diagrams updated

</details>

---

<details>
<summary><strong>📚 Reference Documentation</strong></summary>

## Related Documentation

- **Master Standards:** [docs/architecture/ENGINEERING_STANDARDS.md](../../architecture/ENGINEERING_STANDARDS.md)
- **Complete Example:** [docs/examples/PROJECT_MANAGEMENT.md](../../examples/PROJECT_MANAGEMENT.md)
- **Multi-Tenancy:** [docs/architecture/MULTI_TENANT_DESIGN.md](../../architecture/MULTI_TENANT_DESIGN.md)
- **Event Streaming:** [docs/architecture/EVENT_STREAMING.md](../../architecture/EVENT_STREAMING.md)
- **Database Schema:** [docs/architecture/DATABASE_SCHEMA.md](../../architecture/DATABASE_SCHEMA.md)

## Implementation Pattern

Study `PROJECT_MANAGEMENT.md` as the canonical example. Copy its structure for:
- Package organization (`domain/`, `application/`, `infrastructure/`, `adapter/`)
- Outbox pattern implementation
- Inbox pattern implementation
- Idempotency handling
- Multi-tenant context propagation
- Test structure (unit + integration)

</details>

---

## 📝 Notes

[Add any additional context, decisions, or considerations here]

---

**Status Legend:**
- **Draft** — Story is being written, not ready for implementation
- **Ready** — Story is complete and ready to be picked up
- **In Progress** — Implementation has started
- **Done** — Implementation complete, tests passing, deployed

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
