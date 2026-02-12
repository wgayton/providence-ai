# CLAUDE.MD ENHANCEMENT PROPOSAL
## Schema-Per-Tenant + Event-Driven Architecture

This document contains the proposed enhancements to CLAUDE.md to incorporate:
- Schema-per-tenant multi-tenancy (replaces row-level security)
- Debezium + Kafka event-driven architecture
- Universal idempotency for all state-changing operations
- Public schema infrastructure
- Enhanced Clean Architecture enforcement

---

## SECTION 17: MULTI-TENANT ARCHITECTURE (SCHEMA-PER-TENANT)

### Tenancy model

**Architecture choice:** Schema-per-tenant (Hibernate SCHEMA multi-tenancy)

- Single PostgreSQL database instance
- One dedicated schema per tenant: `t_<tenant_id>` (e.g., `t_acme`, `t_globex`)
- Shared infrastructure tables in `public` schema:
  - `public.tenants` — tenant registry
  - `public.outbox_events` — Debezium outbox for all tenants
  - `public.audit_log` — immutable audit log for all tenants
  - `public.idempotency_keys` — global idempotency tracking
  - `public.inbox_events` — consumer deduplication

**Benefits:**
- Complete data isolation (impossible to query across tenants without explicit `SET search_path`)
- Simplified queries (no `WHERE tenant_id =` clauses)
- Tenant-specific schema evolution (add columns to one tenant without affecting others)
- Easier compliance (backup/restore/delete entire tenant schema)

**Trade-offs:**
- More complex Flyway migrations (must apply to each tenant schema)
- Connection pool management (must set `search_path` per request)
- Cannot use foreign keys between tenant schemas and public schema

---

### Tenant context — propagation across all layers

Every request must carry tenant context from the entry point (REST/gRPC) through the entire stack. Use **Scoped Values** (Java 25) for thread-safe, virtual-thread-compatible context propagation.

```java
package com.providence.common.tenant;

import java.util.UUID;
import java.util.function.Supplier;

public final class TenantContext {
    private static final ScopedValue<UUID> TENANT_ID = ScopedValue.newInstance();
    private static final ScopedValue<String> CORRELATION_ID = ScopedValue.newInstance();

    public static UUID getCurrentTenantId() {
        return TENANT_ID.orElseThrow(() ->
            new IllegalStateException("No tenant context available"));
    }

    public static String getCurrentCorrelationId() {
        return CORRELATION_ID.orElse(UUID.randomUUID().toString());
    }

    public static <R> R runInTenantContext(UUID tenantId, String correlationId, Supplier<R> operation) {
        return ScopedValue
            .where(TENANT_ID, tenantId)
            .where(CORRELATION_ID, correlationId)
            .call(operation);
    }

    public static void runInTenantContext(UUID tenantId, String correlationId, Runnable operation) {
        ScopedValue
            .where(TENANT_ID, tenantId)
            .where(CORRELATION_ID, correlationId)
            .run(operation);
    }
}
```

---

### Tenant resolution strategy

**Priority (evaluated in order):**

1. **JWT claim** — `tenantId` field in access token
2. **HTTP header** — `X-Tenant-Id` (fallback for API keys)
3. **Subdomain** — extract from `Host` header (e.g., `acme.api.providence.ai` → `acme`)

**Implementation:**

```java
package com.providence.common.tenant;

import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Component;
import org.slf4j.MDC;

import java.io.IOException;
import java.util.UUID;

@Component
public class TenantResolutionFilter implements Filter {

    private final TenantRegistry tenantRegistry;

    public TenantResolutionFilter(TenantRegistry tenantRegistry) {
        this.tenantRegistry = tenantRegistry;
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest httpRequest = (HttpServletRequest) request;
        UUID tenantId = resolveTenantId(httpRequest);
        String correlationId = resolveCorrelationId(httpRequest);

        // Validate tenant exists
        if (!tenantRegistry.exists(tenantId)) {
            throw new TenantNotFoundException("Tenant not found: " + tenantId);
        }

        // Set MDC for logging
        MDC.put("tenantId", tenantId.toString());
        MDC.put("correlationId", correlationId);

        try {
            // Propagate via ScopedValue
            TenantContext.runInTenantContext(tenantId, correlationId, () -> {
                try {
                    chain.doFilter(request, response);
                } catch (IOException | ServletException e) {
                    throw new RuntimeException(e);
                }
            });
        } finally {
            MDC.clear();
        }
    }

    private UUID resolveTenantId(HttpServletRequest request) {
        // 1. Try JWT claim
        var auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.getPrincipal() instanceof Jwt jwt) {
            String tenantIdClaim = jwt.getClaimAsString("tenantId");
            if (tenantIdClaim != null) {
                return UUID.fromString(tenantIdClaim);
            }
        }

        // 2. Try X-Tenant-Id header
        String headerTenantId = request.getHeader("X-Tenant-Id");
        if (headerTenantId != null) {
            return UUID.fromString(headerTenantId);
        }

        // 3. Try subdomain
        String host = request.getHeader("Host");
        if (host != null && host.contains(".")) {
            String subdomain = host.split("\\.")[0];
            return tenantRegistry.findBySlug(subdomain)
                .orElseThrow(() -> new TenantNotFoundException("Tenant not found for subdomain: " + subdomain));
        }

        throw new TenantNotFoundException("Cannot resolve tenant from request");
    }

    private String resolveCorrelationId(HttpServletRequest request) {
        String correlationId = request.getHeader("X-Correlation-Id");
        return (correlationId != null) ? correlationId : UUID.randomUUID().toString();
    }
}
```

---

### Data isolation — Hibernate SCHEMA multi-tenancy

Configure Hibernate to automatically switch PostgreSQL schemas based on tenant context.

**Hibernate configuration:**

```java
package com.providence.common.tenant;

import org.hibernate.cfg.AvailableSettings;
import org.hibernate.context.spi.CurrentTenantIdentifierResolver;
import org.hibernate.engine.jdbc.connections.spi.MultiTenantConnectionProvider;
import org.springframework.boot.autoconfigure.orm.jpa.HibernatePropertiesCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.SQLException;
import java.util.Map;
import java.util.UUID;

@Configuration
public class MultiTenancyConfig {

    @Bean
    public HibernatePropertiesCustomizer hibernatePropertiesCustomizer(
            MultiTenantConnectionProvider connectionProvider,
            CurrentTenantIdentifierResolver tenantResolver) {

        return hibernateProperties -> hibernateProperties.putAll(Map.of(
            AvailableSettings.MULTI_TENANT_CONNECTION_PROVIDER, connectionProvider,
            AvailableSettings.MULTI_TENANT_IDENTIFIER_RESOLVER, tenantResolver,
            // Use SCHEMA strategy
            "hibernate.multi_tenant_strategy", "SCHEMA"
        ));
    }

    @Bean
    public MultiTenantConnectionProvider multiTenantConnectionProvider(DataSource dataSource) {
        return new SchemaPerTenantConnectionProvider(dataSource);
    }

    @Bean
    public CurrentTenantIdentifierResolver currentTenantIdentifierResolver() {
        return new TenantIdentifierResolver();
    }
}
```

**Connection provider:**

```java
package com.providence.common.tenant;

import org.hibernate.engine.jdbc.connections.spi.MultiTenantConnectionProvider;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.SQLException;

public class SchemaPerTenantConnectionProvider implements MultiTenantConnectionProvider<String> {

    private final DataSource dataSource;

    public SchemaPerTenantConnectionProvider(DataSource dataSource) {
        this.dataSource = dataSource;
    }

    @Override
    public Connection getAnyConnection() throws SQLException {
        return dataSource.getConnection();
    }

    @Override
    public void releaseAnyConnection(Connection connection) throws SQLException {
        connection.close();
    }

    @Override
    public Connection getConnection(String tenantIdentifier) throws SQLException {
        Connection connection = getAnyConnection();
        // Set search_path to tenant schema + public
        String searchPath = "t_" + tenantIdentifier + ", public";
        connection.createStatement().execute("SET search_path TO " + searchPath);
        return connection;
    }

    @Override
    public void releaseConnection(String tenantIdentifier, Connection connection) throws SQLException {
        // Reset search_path to public
        connection.createStatement().execute("SET search_path TO public");
        connection.close();
    }

    @Override
    public boolean supportsAggressiveRelease() {
        return false;
    }

    @Override
    public boolean isUnwrappableAs(Class<?> unwrapType) {
        return false;
    }

    @Override
    public <T> T unwrap(Class<T> unwrapType) {
        return null;
    }
}
```

**Tenant identifier resolver:**

```java
package com.providence.common.tenant;

import org.hibernate.context.spi.CurrentTenantIdentifierResolver;

public class TenantIdentifierResolver implements CurrentTenantIdentifierResolver<String> {

    @Override
    public String resolveCurrentTenantIdentifier() {
        try {
            return TenantContext.getCurrentTenantId().toString();
        } catch (IllegalStateException e) {
            // Fallback to public schema for system operations
            return "public";
        }
    }

    @Override
    public boolean validateExistingCurrentSessions() {
        return false;
    }
}
```

---

### Entity design — no tenant discriminator needed

With schema-per-tenant, entities do NOT need a `tenant_id` column. The schema itself provides isolation.

```java
package com.providence.project.domain;

import com.providence.common.domain.AuditableEntity;
import jakarta.persistence.*;
import java.util.UUID;

@Entity
@Table(name = "projects") // Created in t_<tenant> schema
public class Project extends AuditableEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(length = 500)
    private String description;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ProjectStatus status;

    // No tenant_id column needed!

    // Domain methods
    public void archive() {
        if (this.status == ProjectStatus.ARCHIVED) {
            throw new BusinessRuleViolation("PROJECT_ALREADY_ARCHIVED",
                "Project is already archived");
        }
        this.status = ProjectStatus.ARCHIVED;
    }
}
```

---

### Public schema design — cross-tenant infrastructure

Tables in the `public` schema are visible to all tenants and used for cross-cutting concerns.

**public.tenants:**

```sql
CREATE TABLE public.tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slug VARCHAR(50) UNIQUE NOT NULL, -- URL-safe identifier (e.g., 'acme')
    name VARCHAR(100) NOT NULL,
    schema_name VARCHAR(63) NOT NULL, -- 't_acme'
    status VARCHAR(20) NOT NULL, -- ACTIVE, SUSPENDED, DELETED
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tenants_slug ON public.tenants(slug);
CREATE INDEX idx_tenants_status ON public.tenants(status);
```

**public.outbox_events (Debezium):**

```sql
CREATE TABLE public.outbox_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id),
    aggregate_type VARCHAR(100) NOT NULL, -- 'Project', 'User', etc.
    aggregate_id UUID NOT NULL,
    event_type VARCHAR(100) NOT NULL, -- 'ProjectCreated', 'UserRegistered'
    event_version INT NOT NULL DEFAULT 1,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    correlation_id UUID NOT NULL,
    causation_id UUID, -- ID of event that caused this event (event chain)
    actor_id UUID, -- User who triggered the event
    payload JSONB NOT NULL,
    published_at TIMESTAMPTZ -- Set by Debezium after publishing to Kafka
);

CREATE INDEX idx_outbox_tenant_occurred ON public.outbox_events(tenant_id, occurred_at);
CREATE INDEX idx_outbox_published_at ON public.outbox_events(published_at) WHERE published_at IS NULL;
```

**public.audit_log:**

```sql
CREATE TABLE public.audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL REFERENCES public.tenants(id),
    event_type VARCHAR(100) NOT NULL,
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id UUID NOT NULL,
    actor_id UUID NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    correlation_id UUID NOT NULL,
    ip_address INET,
    user_agent TEXT,
    payload JSONB NOT NULL
);

CREATE INDEX idx_audit_tenant_occurred ON public.audit_log(tenant_id, occurred_at DESC);
CREATE INDEX idx_audit_aggregate ON public.audit_log(tenant_id, aggregate_type, aggregate_id);
CREATE INDEX idx_audit_actor ON public.audit_log(tenant_id, actor_id, occurred_at DESC);
```

**public.idempotency_keys:**

```sql
CREATE TABLE public.idempotency_keys (
    tenant_id UUID NOT NULL REFERENCES public.tenants(id),
    principal_id UUID NOT NULL, -- User or service account
    command_name VARCHAR(100) NOT NULL, -- 'CreateProject', 'TransferFunds'
    idempotency_key VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    response_payload JSONB, -- Cached response for idempotent replay
    PRIMARY KEY (tenant_id, principal_id, command_name, idempotency_key)
);

CREATE INDEX idx_idempotency_created ON public.idempotency_keys(created_at);
```

**public.inbox_events (consumer deduplication):**

```sql
CREATE TABLE public.inbox_events (
    tenant_id UUID NOT NULL,
    consumer_name VARCHAR(100) NOT NULL, -- 'ProjectionUpdater', 'NotificationSender'
    event_id UUID NOT NULL, -- From Kafka message
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (tenant_id, consumer_name, event_id)
);
```

---

### Cache isolation — tenant-scoped keys

All cache keys must include the tenant ID prefix (same as before).

```java
@Service
public class ProjectService {
    private final ProjectRepository projectRepo;

    @Cacheable(value = "projects", key = "T(com.providence.common.tenant.TenantContext).currentTenantId + ':' + #id")
    public Project findById(UUID id) {
        return projectRepo.findById(id)
            .orElseThrow(() -> new ResourceNotFoundException("PROJECT_NOT_FOUND", "Project not found", "Project", id.toString()));
    }

    @CacheEvict(value = "projects", key = "T(com.providence.common.tenant.TenantContext).currentTenantId + ':' + #id")
    public void update(UUID id, UpdateProjectCommand cmd) {
        // ...
    }
}
```

---

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
                // With schema-per-tenant, cross-tenant access is prevented at DB level
                // This provides an additional application-level check
                return true; // Simplified - add domain-specific permission checks here
            }

            @Override
            public boolean hasPermission(Authentication auth, Serializable targetId, String targetType, Object permission) {
                // Load entity and verify it exists in current tenant's schema
                // If schema isolation is correct, loading will fail automatically
                return true;
            }
        };
    }
}
```

**Authorization rules:**
1. User roles (Admin, Moderator, Member) are **scoped per tenant**.
2. A user who is Admin in Tenant A has zero privileges in Tenant B.
3. JWT claims must include: `sub` (user ID), `tenantId`, `roles` (array of role names for the current tenant).
4. Schema-per-tenant provides defense-in-depth: even if application logic fails, database isolation prevents cross-tenant access.

---

### Observability — tenant tagging

**Logging:**
```java
// Already handled by TenantResolutionFilter setting MDC
// Every log line will include tenantId and correlationId
```

**Metrics:**
```java
meterRegistry.counter("projects.created",
    "tenant_id", TenantContext.getCurrentTenantId().toString()).increment();
```

**Important:** With 10,000+ tenants, tagging metrics with `tenant_id` can cause cardinality explosion. Consider:
- Aggregate metrics across all tenants (`projects.created` without tag)
- Use separate tenant-specific metrics only for premium/enterprise tenants
- Export raw metrics to a time-series database for tenant-level analytics

**Distributed tracing:**
```java
Span.current().setAttribute("tenant.id", TenantContext.getCurrentTenantId().toString());
Span.current().setAttribute("correlation.id", TenantContext.getCurrentCorrelationId());
```

---

### Flyway migrations — per-tenant schema management

**Challenge:** Migrations must be applied to each tenant schema.

**Solution:** Maintain separate migration paths for public and tenant schemas.

**Directory structure:**
```
src/main/resources/db/migration/
├── public/
│   ├── V001__create_tenants_table.sql
│   ├── V002__create_outbox_events_table.sql
│   ├── V003__create_audit_log_table.sql
│   └── V004__create_idempotency_keys_table.sql
└── tenant/
    ├── V001__create_projects_table.sql
    ├── V002__create_resources_table.sql
    └── V003__create_ledger_entries_table.sql
```

**Flyway configuration:**

```java
package com.providence.common.migration;

import org.flywaydb.core.Flyway;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.util.List;

@Component
public class TenantMigrationManager {

    private final DataSource dataSource;
    private final TenantRegistry tenantRegistry;

    public TenantMigrationManager(DataSource dataSource, TenantRegistry tenantRegistry) {
        this.dataSource = dataSource;
        this.tenantRegistry = tenantRegistry;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void migrateAllTenants() {
        // 1. Migrate public schema first
        migratePublicSchema();

        // 2. Migrate each tenant schema
        List<Tenant> tenants = tenantRegistry.findAll();
        for (Tenant tenant : tenants) {
            migrateTenantSchema(tenant.getSchemaName());
        }
    }

    private void migratePublicSchema() {
        Flyway flyway = Flyway.configure()
            .dataSource(dataSource)
            .locations("classpath:db/migration/public")
            .schemas("public")
            .baselineOnMigrate(true)
            .load();
        flyway.migrate();
    }

    private void migrateTenantSchema(String schemaName) {
        Flyway flyway = Flyway.configure()
            .dataSource(dataSource)
            .locations("classpath:db/migration/tenant")
            .schemas(schemaName)
            .baselineOnMigrate(true)
            .load();
        flyway.migrate();
    }

    public void provisionNewTenant(UUID tenantId, String slug) {
        String schemaName = "t_" + slug;

        // 1. Create schema
        try (var conn = dataSource.getConnection();
             var stmt = conn.createStatement()) {
            stmt.execute("CREATE SCHEMA " + schemaName);
        } catch (Exception e) {
            throw new RuntimeException("Failed to create schema: " + schemaName, e);
        }

        // 2. Insert into public.tenants
        tenantRegistry.register(tenantId, slug, schemaName);

        // 3. Run tenant migrations
        migrateTenantSchema(schemaName);
    }
}
```

---

### Testing — cross-tenant access prevention

```java
package com.providence.project;

import com.providence.common.tenant.TenantContext;
import com.providence.project.domain.Project;
import com.providence.project.service.ProjectService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.UUID;

import static org.assertj.core.api.Assertions.*;

@SpringBootTest
@Testcontainers
class ProjectCrossTenantisolationTest {

    @Autowired
    private ProjectService projectService;

    @Autowired
    private TenantProvisioningService tenantProvisioningService;

    @Test
    void findById_withDifferentTenantContext_throwsNotFoundException() {
        // Setup: Create two tenants
        UUID tenantA = UUID.randomUUID();
        UUID tenantB = UUID.randomUUID();
        tenantProvisioningService.provision(tenantA, "tenant-a");
        tenantProvisioningService.provision(tenantB, "tenant-b");

        // Create project in tenant A
        UUID projectId = TenantContext.runInTenantContext(tenantA, UUID.randomUUID().toString(), () ->
            projectService.create(new CreateProjectCommand("Project A")).id()
        );

        // Attempt to access from tenant B (should fail)
        assertThatThrownBy(() ->
            TenantContext.runInTenantContext(tenantB, UUID.randomUUID().toString(), () ->
                projectService.findById(projectId)
            )
        ).isInstanceOf(ResourceNotFoundException.class);
    }
}
```

---

## SECTION 24: EVENT-DRIVEN ARCHITECTURE (OUTBOX/INBOX PATTERNS)

### Architectural mandate

Every state-changing operation must be:
- **Idempotent** — safe to apply multiple times
- **Logged** — immutable audit trail
- **Replayable** — can reconstruct state from events
- **Correlated** — traced through distributed system
- **Tenant-scoped** — isolated per tenant
- **Atomic** — transaction includes domain mutation + event emission

**Flow:**

```
Command → Transaction → Domain Mutation → Outbox Event → Commit
  ↓
Debezium CDC reads outbox_events table
  ↓
Publishes to Kafka (ecap.events.<EventType>)
  ↓
Consumers read events → Inbox deduplication → Apply projection
```

---

### Outbox pattern implementation

**Step 1: Define domain event**

```java
package com.providence.project.domain.event;

import java.time.Instant;
import java.util.UUID;

public sealed interface ProjectEvent permits
    ProjectCreated, ProjectUpdated, ProjectArchived {
    UUID projectId();
    UUID tenantId();
    Instant occurredAt();
}

public record ProjectCreated(
    UUID projectId,
    UUID tenantId,
    String name,
    String description,
    Instant occurredAt
) implements ProjectEvent {}
```

**Step 2: Write to outbox in same transaction**

```java
package com.providence.project.service;

import com.providence.common.tenant.TenantContext;
import com.providence.common.outbox.OutboxService;
import com.providence.project.domain.Project;
import com.providence.project.domain.event.ProjectCreated;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

@Service
public class ProjectService {

    private final ProjectRepository projectRepo;
    private final OutboxService outboxService;
    private final AuditLogService auditLogService;

    @Transactional
    public Project create(CreateProjectCommand cmd) {
        UUID tenantId = TenantContext.getCurrentTenantId();
        String correlationId = TenantContext.getCurrentCorrelationId();

        // 1. Create domain entity
        Project project = new Project(cmd.name(), cmd.description());
        projectRepo.save(project);

        // 2. Write audit log (public schema)
        auditLogService.log(AuditEvent.builder()
            .tenantId(tenantId)
            .eventType("PROJECT_CREATED")
            .aggregateType("Project")
            .aggregateId(project.getId())
            .actorId(SecurityContext.getCurrentUserId())
            .correlationId(UUID.fromString(correlationId))
            .payload(Map.of("name", project.getName()))
            .build());

        // 3. Write outbox event (public schema)
        ProjectCreated event = new ProjectCreated(
            project.getId(),
            tenantId,
            project.getName(),
            project.getDescription(),
            Instant.now()
        );

        outboxService.publish(OutboxEvent.builder()
            .tenantId(tenantId)
            .aggregateType("Project")
            .aggregateId(project.getId())
            .eventType("ProjectCreated")
            .eventVersion(1)
            .correlationId(UUID.fromString(correlationId))
            .causationId(null) // First event in chain
            .actorId(SecurityContext.getCurrentUserId())
            .payload(event)
            .build());

        // Transaction commits → Debezium reads outbox_events → publishes to Kafka
        return project;
    }
}
```

**Step 3: OutboxService implementation**

```java
package com.providence.common.outbox;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class OutboxService {

    private final EntityManager entityManager;
    private final ObjectMapper objectMapper;

    public OutboxService(EntityManager entityManager, ObjectMapper objectMapper) {
        this.entityManager = entityManager;
        this.objectMapper = objectMapper;
    }

    public void publish(OutboxEvent event) {
        // Insert into public.outbox_events
        String sql = """
            INSERT INTO public.outbox_events (
                id, tenant_id, aggregate_type, aggregate_id, event_type, event_version,
                occurred_at, correlation_id, causation_id, actor_id, payload
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?::jsonb)
        """;

        entityManager.createNativeQuery(sql)
            .setParameter(1, UUID.randomUUID())
            .setParameter(2, event.tenantId())
            .setParameter(3, event.aggregateType())
            .setParameter(4, event.aggregateId())
            .setParameter(5, event.eventType())
            .setParameter(6, event.eventVersion())
            .setParameter(7, event.occurredAt())
            .setParameter(8, event.correlationId())
            .setParameter(9, event.causationId())
            .setParameter(10, event.actorId())
            .setParameter(11, objectMapper.writeValueAsString(event.payload()))
            .executeUpdate();
    }
}
```

---

### Debezium configuration

**docker-compose.yml (for local development):**

```yaml
version: '3.8'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://localhost:9092

  debezium:
    image: debezium/connect:2.5
    depends_on:
      - kafka
    ports:
      - "8083:8083"
    environment:
      BOOTSTRAP_SERVERS: kafka:9092
      GROUP_ID: 1
      CONFIG_STORAGE_TOPIC: debezium_configs
      OFFSET_STORAGE_TOPIC: debezium_offsets
      STATUS_STORAGE_TOPIC: debezium_statuses
```

**Debezium connector configuration:**

```json
{
  "name": "providence-outbox-connector",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "localhost",
    "database.port": "5432",
    "database.user": "providence",
    "database.password": "password",
    "database.dbname": "providence",
    "table.include.list": "public.outbox_events",
    "transforms": "outbox",
    "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
    "transforms.outbox.table.field.event.id": "id",
    "transforms.outbox.table.field.event.key": "aggregate_id",
    "transforms.outbox.table.field.event.type": "event_type",
    "transforms.outbox.table.field.event.payload": "payload",
    "transforms.outbox.route.topic.replacement": "ecap.events.${routedByValue}",
    "tombstones.on.delete": "false",
    "slot.name": "providence_outbox_slot",
    "publication.name": "providence_outbox_publication"
  }
}
```

**Result:** Events published to Kafka topics:
- `ecap.events.ProjectCreated`
- `ecap.events.ProjectUpdated`
- `ecap.events.ProjectArchived`

---

### Inbox pattern (consumer deduplication)

**Kafka consumer with inbox deduplication:**

```java
package com.providence.notification.consumer;

import com.providence.common.inbox.InboxService;
import com.providence.project.domain.event.ProjectCreated;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Component
public class ProjectEventConsumer {

    private final InboxService inboxService;
    private final NotificationService notificationService;

    @KafkaListener(topics = "ecap.events.ProjectCreated", groupId = "notification-service")
    @Transactional
    public void handleProjectCreated(ProjectCreated event,
                                      @Header("eventId") String eventId,
                                      @Header("tenantId") String tenantId) {

        UUID tenantUuid = UUID.fromString(tenantId);
        UUID eventUuid = UUID.fromString(eventId);

        // 1. Check if already processed (idempotent)
        if (inboxService.isProcessed(tenantUuid, "NotificationSender", eventUuid)) {
            return; // Already processed, skip
        }

        // 2. Mark as processed (prevents duplicate processing on retry)
        inboxService.markProcessed(tenantUuid, "NotificationSender", eventUuid);

        // 3. Apply business logic
        notificationService.sendProjectCreatedNotification(event);

        // Transaction commits → event marked as processed
    }
}
```

**InboxService implementation:**

```java
package com.providence.common.inbox;

import jakarta.persistence.EntityManager;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service
public class InboxService {

    private final EntityManager entityManager;

    public InboxService(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    public boolean isProcessed(UUID tenantId, String consumerName, UUID eventId) {
        String sql = """
            SELECT COUNT(*) FROM public.inbox_events
            WHERE tenant_id = ? AND consumer_name = ? AND event_id = ?
        """;

        Long count = (Long) entityManager.createNativeQuery(sql)
            .setParameter(1, tenantId)
            .setParameter(2, consumerName)
            .setParameter(3, eventId)
            .getSingleResult();

        return count > 0;
    }

    public void markProcessed(UUID tenantId, String consumerName, UUID eventId) {
        String sql = """
            INSERT INTO public.inbox_events (tenant_id, consumer_name, event_id)
            VALUES (?, ?, ?)
            ON CONFLICT DO NOTHING
        """;

        entityManager.createNativeQuery(sql)
            .setParameter(1, tenantId)
            .setParameter(2, consumerName)
            .setParameter(3, eventId)
            .executeUpdate();
    }
}
```

---

## SECTION 25: UNIVERSAL IDEMPOTENCY

### Mandate

ALL state-changing REST and gRPC endpoints MUST enforce idempotency.

**Requirements:**
- Client provides `Idempotency-Key` header (REST) or `idempotency-key` metadata (gRPC)
- Server stores key in `public.idempotency_keys` with composite key: `(tenant_id, principal_id, command_name, idempotency_key)`
- Duplicate requests return cached response without re-executing logic
- Idempotency keys expire after 24 hours (configurable)

---

### REST idempotency interceptor

```java
package com.providence.common.idempotency;

import com.providence.common.tenant.TenantContext;
import jakarta.servlet.*;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.util.UUID;

@Component
public class IdempotencyFilter implements Filter {

    private final IdempotencyService idempotencyService;

    public IdempotencyFilter(IdempotencyService idempotencyService) {
        this.idempotencyService = idempotencyService;
    }

    @Override
    public void doFilter(ServletRequest request, ServletResponse response, FilterChain chain)
            throws IOException, ServletException {

        HttpServletRequest httpRequest = (HttpServletRequest) request;
        HttpServletResponse httpResponse = (HttpServletResponse) response;

        // Only apply to state-changing methods
        String method = httpRequest.getMethod();
        if (!method.equals("POST") && !method.equals("PUT") && !method.equals("PATCH") && !method.equals("DELETE")) {
            chain.doFilter(request, response);
            return;
        }

        // Check for idempotency key
        String idempotencyKey = httpRequest.getHeader("Idempotency-Key");
        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            httpResponse.setStatus(400);
            httpResponse.getWriter().write("{\"error\": \"Idempotency-Key header required for state-changing operations\"}");
            return;
        }

        UUID tenantId = TenantContext.getCurrentTenantId();
        UUID principalId = SecurityContext.getCurrentUserId();
        String commandName = deriveCommandName(httpRequest);

        // Check if already processed
        var cachedResponse = idempotencyService.getCachedResponse(tenantId, principalId, commandName, idempotencyKey);
        if (cachedResponse.isPresent()) {
            // Return cached response
            httpResponse.setStatus(cachedResponse.get().statusCode());
            httpResponse.setContentType("application/json");
            httpResponse.getWriter().write(cachedResponse.get().body());
            return;
        }

        // Proceed with request
        ResponseCapturingWrapper responseWrapper = new ResponseCapturingWrapper(httpResponse);
        chain.doFilter(request, responseWrapper);

        // Cache response for future replays
        if (responseWrapper.getStatus() >= 200 && responseWrapper.getStatus() < 300) {
            idempotencyService.cacheResponse(
                tenantId, principalId, commandName, idempotencyKey,
                responseWrapper.getStatus(), responseWrapper.getCapturedContent()
            );
        }
    }

    private String deriveCommandName(HttpServletRequest request) {
        // Derive from URL path (e.g., POST /api/projects → "CreateProject")
        String path = request.getRequestURI();
        String method = request.getMethod();
        // Simplified - enhance based on your routing conventions
        return method + "_" + path.replaceAll("/", "_");
    }
}
```

---

### IdempotencyService

```java
package com.providence.common.idempotency;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.persistence.EntityManager;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;

@Service
public class IdempotencyService {

    private final EntityManager entityManager;
    private final ObjectMapper objectMapper;

    public IdempotencyService(EntityManager entityManager, ObjectMapper objectMapper) {
        this.entityManager = entityManager;
        this.objectMapper = objectMapper;
    }

    public Optional<CachedResponse> getCachedResponse(UUID tenantId, UUID principalId,
                                                       String commandName, String idempotencyKey) {
        String sql = """
            SELECT response_payload FROM public.idempotency_keys
            WHERE tenant_id = ? AND principal_id = ? AND command_name = ? AND idempotency_key = ?
            AND created_at > ?
        """;

        Instant cutoff = Instant.now().minus(24, ChronoUnit.HOURS);

        var result = entityManager.createNativeQuery(sql)
            .setParameter(1, tenantId)
            .setParameter(2, principalId)
            .setParameter(3, commandName)
            .setParameter(4, idempotencyKey)
            .setParameter(5, cutoff)
            .getResultList();

        if (result.isEmpty()) {
            return Optional.empty();
        }

        String json = (String) result.get(0);
        try {
            return Optional.of(objectMapper.readValue(json, CachedResponse.class));
        } catch (Exception e) {
            return Optional.empty();
        }
    }

    @Transactional
    public void cacheResponse(UUID tenantId, UUID principalId, String commandName,
                               String idempotencyKey, int statusCode, String body) {
        String sql = """
            INSERT INTO public.idempotency_keys (tenant_id, principal_id, command_name, idempotency_key, response_payload)
            VALUES (?, ?, ?, ?, ?::jsonb)
            ON CONFLICT (tenant_id, principal_id, command_name, idempotency_key) DO NOTHING
        """;

        CachedResponse response = new CachedResponse(statusCode, body);

        try {
            entityManager.createNativeQuery(sql)
                .setParameter(1, tenantId)
                .setParameter(2, principalId)
                .setParameter(3, commandName)
                .setParameter(4, idempotencyKey)
                .setParameter(5, objectMapper.writeValueAsString(response))
                .executeUpdate();
        } catch (Exception e) {
            throw new RuntimeException("Failed to cache idempotency response", e);
        }
    }
}

record CachedResponse(int statusCode, String body) {}
```

---

### gRPC idempotency interceptor

```java
package com.providence.common.idempotency;

import io.grpc.*;
import org.springframework.stereotype.Component;

import java.util.UUID;

@Component
public class GrpcIdempotencyInterceptor implements ServerInterceptor {

    private final IdempotencyService idempotencyService;

    public GrpcIdempotencyInterceptor(IdempotencyService idempotencyService) {
        this.idempotencyService = idempotencyService;
    }

    @Override
    public <ReqT, RespT> ServerCall.Listener<ReqT> interceptCall(
            ServerCall<ReqT, RespT> call,
            Metadata headers,
            ServerCallHandler<ReqT, RespT> next) {

        // Extract idempotency key from metadata
        String idempotencyKey = headers.get(Metadata.Key.of("idempotency-key", Metadata.ASCII_STRING_MARSHALLER));

        if (idempotencyKey == null || idempotencyKey.isBlank()) {
            call.close(Status.INVALID_ARGUMENT.withDescription("idempotency-key metadata required"), new Metadata());
            return new ServerCall.Listener<>() {};
        }

        UUID tenantId = TenantContext.getCurrentTenantId();
        UUID principalId = SecurityContext.getCurrentUserId();
        String commandName = call.getMethodDescriptor().getFullMethodName();

        // Check cache
        var cachedResponse = idempotencyService.getCachedResponse(tenantId, principalId, commandName, idempotencyKey);
        if (cachedResponse.isPresent()) {
            // Return cached response (deserialize from JSON to protobuf)
            // Implementation depends on your protobuf message types
            // ...
            return new ServerCall.Listener<>() {};
        }

        // Proceed with call
        return next.startCall(call, headers);
    }
}
```

---

## SECTION 26: CLEAN ARCHITECTURE ENFORCEMENT

### Layer definitions

```
┌─────────────────────────────────────────────────────┐
│              Presentation Layer                      │
│  (REST Controllers, gRPC Services, DTO Mappers)     │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│              Application Layer                       │
│  (Use Cases, Command Handlers, Transaction Mgmt)    │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│              Domain Layer                            │
│  (Entities, Aggregates, Domain Events, Value Objs)  │
└──────────────────▲──────────────────────────────────┘
                   │
┌──────────────────┴──────────────────────────────────┐
│              Infrastructure Layer                    │
│  (JPA, Redis, Kafka, External Services, DB Impl)    │
└─────────────────────────────────────────────────────┘
```

**Dependency direction:** Inner layers NEVER depend on outer layers.

---

### Domain layer rules

**Location:** `com.providence.{feature}.domain`

**Allowed dependencies:**
- Standard Java types (`java.util`, `java.time`, `java.math`)
- JSpecify annotations (`@Nullable`)
- **NO Spring** (`@Service`, `@Component`, etc.)
- **NO JPA** (`@Entity` is pragmatically allowed if documented)
- **NO Jackson** (`@JsonProperty`, etc.)

**Example:**

```java
package com.providence.project.domain;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.UUID;

// Pure domain aggregate
public class Project {
    private final UUID id;
    private String name;
    private ProjectStatus status;
    private final Instant createdAt;
    private Instant updatedAt;

    // Constructor enforces invariants
    public Project(String name) {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Project name cannot be blank");
        }
        this.id = UUID.randomUUID();
        this.name = name;
        this.status = ProjectStatus.ACTIVE;
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    // Domain methods enforce business rules
    public void archive() {
        if (this.status == ProjectStatus.ARCHIVED) {
            throw new BusinessRuleViolation("PROJECT_ALREADY_ARCHIVED",
                "Cannot archive an already archived project");
        }
        this.status = ProjectStatus.ARCHIVED;
        this.updatedAt = Instant.now();
    }

    // Getters only - no public setters
    public UUID id() { return id; }
    public String name() { return name; }
    public ProjectStatus status() { return status; }
}
```

---

### Application layer rules

**Location:** `com.providence.{feature}.service`

**Responsibilities:**
- Orchestrate use cases
- Define transaction boundaries (`@Transactional`)
- Coordinate between domain and infrastructure
- Emit domain events to outbox

**Example:**

```java
package com.providence.project.service;

import com.providence.common.outbox.OutboxService;
import com.providence.common.tenant.TenantContext;
import com.providence.project.domain.Project;
import com.providence.project.domain.event.ProjectCreated;
import com.providence.project.repository.ProjectRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProjectService {

    private final ProjectRepository projectRepo;
    private final OutboxService outboxService;

    public ProjectService(ProjectRepository projectRepo, OutboxService outboxService) {
        this.projectRepo = projectRepo;
        this.outboxService = outboxService;
    }

    @Transactional
    public Project create(CreateProjectCommand cmd) {
        // 1. Create domain aggregate
        Project project = new Project(cmd.name());
        projectRepo.save(project);

        // 2. Emit domain event to outbox
        ProjectCreated event = new ProjectCreated(
            project.id(),
            TenantContext.getCurrentTenantId(),
            project.name(),
            Instant.now()
        );
        outboxService.publish(event);

        return project;
    }
}
```

---

### Infrastructure layer rules

**Location:** `com.providence.{feature}.adapter.infra`

**Responsibilities:**
- Implement port interfaces (repositories, external services)
- JPA entity mappings (if separate from domain)
- Redis, Kafka, HTTP client implementations

**Example:**

```java
package com.providence.project.repository;

import com.providence.project.domain.Project;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

// Port interface (defined in domain or application layer)
public interface ProjectRepository extends JpaRepository<Project, UUID> {
    // Custom queries
}
```

---

### Presentation layer rules

**Location:** `com.providence.{feature}.adapter.web` and `com.providence.{feature}.adapter.grpc`

**Responsibilities:**
- Accept DTOs (not domain entities)
- Validate input
- Map DTOs ↔ domain objects
- Call application services
- Return DTOs (never domain entities)

**Example:**

```java
package com.providence.project.adapter.web;

import com.providence.project.dto.CreateProjectRequest;
import com.providence.project.dto.ProjectResponse;
import com.providence.project.service.ProjectService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/projects")
public class ProjectController {

    private final ProjectService projectService;
    private final ProjectMapper projectMapper;

    @PostMapping
    public ProjectResponse create(@Valid @RequestBody CreateProjectRequest request) {
        var command = projectMapper.toCommand(request);
        var project = projectService.create(command);
        return projectMapper.toResponse(project);
    }
}
```

---

## SUMMARY: KEY CHANGES TO CLAUDE.MD

1. **Section 1:** Add Kafka + Debezium to tech stack ✅
2. **Section 17:** Replace entirely with schema-per-tenant architecture
3. **New Section 24:** Event-Driven Architecture (Outbox/Inbox)
4. **New Section 25:** Universal Idempotency
5. **New Section 26:** Clean Architecture Enforcement
6. **Section 19 (Checklist):** Update to include event emission, idempotency, public schema design

---

## NEXT STEPS

Would you like me to:

1. **Apply these changes directly to CLAUDE.md** (replace Section 17, add new sections)?
2. **Generate the public schema migration SQL** (`V001__create_public_infrastructure.sql`)?
3. **Create a complete working example** of a feature (e.g., Project Management) using all patterns?
4. **Design the Kafka topic strategy** (partitioning, retention, compaction)?

Let me know which direction to proceed!
