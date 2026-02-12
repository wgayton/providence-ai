# Resource Management Feature - Implementation Skeleton

## 🎯 Purpose

This skeleton demonstrates how to **replicate the Project Management pattern** for the **Resource Management** feature. It serves as a template for implementing:

- **Resource Management** (this document)
- **Fund Management** (financial transactions)
- **Human Management** (user/role/team management)

---

## 📋 Feature Scope

**Resource Management** tracks allocation of resources (people, equipment, budget) to projects:

- **Allocate resource** to project (with date range)
- **Release resource** from project
- **View resource utilization** (across all projects)
- **Send alerts** when resources are over-allocated (Kafka consumer)

**Entities:**
- `Resource` — Aggregate root (equipment, personnel, budget)
- `ResourceAllocation` — Value object (resource + project + date range)

**Events:**
- `ResourceAllocated` — Resource assigned to project
- `ResourceReleased` — Resource removed from project
- `ResourceOverAllocated` — Resource assigned to multiple projects (alert)

---

## 🏗️ Architecture (Same as Project Management)

```
Domain Layer (src/main/java/com/providence/resource/domain/)
├── Resource.java              # Aggregate root
├── ResourceType.java          # Enum (PERSONNEL, EQUIPMENT, BUDGET)
├── ResourceAllocation.java    # Value object
└── event/
    ├── ResourceEvent.java     # Sealed interface
    ├── ResourceAllocated.java
    └── ResourceReleased.java

Application Layer (src/main/java/com/providence/resource/application/)
├── service/
│   └── ResourceService.java   # Orchestration + transactions
├── command/
│   ├── AllocateResourceCommand.java
│   └── ReleaseResourceCommand.java
└── dto/
    ├── ResourceResponse.java
    ├── AllocateResourceRequest.java
    └── ResourceUtilizationResponse.java

Infrastructure Layer (src/main/java/com/providence/resource/infrastructure/)
├── repository/
│   └── ResourceRepository.java  # JPA repository
├── outbox/
│   └── OutboxService.java       # Shared (com.providence.common.outbox)
└── audit/
    └── AuditLogService.java     # Shared (com.providence.common.audit)

Presentation Layer (src/main/java/com/providence/resource/adapter/)
├── web/
│   ├── ResourceController.java  # REST API
│   └── ResourceMapper.java      # DTO ↔ Domain
└── consumer/
    └── ResourceEventConsumer.java  # Kafka consumer (inbox pattern)

Database (src/main/resources/db/migration/tenant/)
└── V002__create_resources_table.sql  # Tenant-specific schema
```

---

## 📄 Key Files (Skeleton Code)

### 1. Domain Layer: Resource.java

```java
package com.providence.resource.domain;

import com.providence.common.domain.AuditableEntity;
import jakarta.persistence.*;
import java.time.LocalDate;
import java.util.UUID;

@Entity
@Table(name = "resources")
public class Resource extends AuditableEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, length = 100)
    private String name;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private ResourceType type;  // PERSONNEL, EQUIPMENT, BUDGET

    @Column(nullable = false)
    private boolean available = true;

    protected Resource() {}

    public Resource(String name, ResourceType type) {
        if (name == null || name.isBlank()) {
            throw new IllegalArgumentException("Resource name cannot be blank");
        }
        this.id = UUID.randomUUID();
        this.name = name;
        this.type = type;
        this.available = true;
    }

    // Domain method: Allocate to project
    public void allocate(UUID projectId, LocalDate startDate, LocalDate endDate) {
        if (!this.available) {
            throw new BusinessRuleViolation(
                "RESOURCE_UNAVAILABLE",
                "Resource is already allocated"
            );
        }
        if (endDate.isBefore(startDate)) {
            throw new IllegalArgumentException("End date must be after start date");
        }
        this.available = false;
    }

    // Domain method: Release from project
    public void release() {
        if (this.available) {
            throw new BusinessRuleViolation(
                "RESOURCE_NOT_ALLOCATED",
                "Resource is not currently allocated"
            );
        }
        this.available = true;
    }

    public UUID getId() { return id; }
    public String getName() { return name; }
    public ResourceType getType() { return type; }
    public boolean isAvailable() { return available; }
}
```

### 2. Domain Events

```java
package com.providence.resource.domain.event;

import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

public sealed interface ResourceEvent permits
    ResourceAllocated, ResourceReleased {}

public record ResourceAllocated(
    UUID resourceId,
    UUID tenantId,
    UUID projectId,
    String resourceName,
    LocalDate startDate,
    LocalDate endDate,
    Instant occurredAt
) implements ResourceEvent {}

public record ResourceReleased(
    UUID resourceId,
    UUID tenantId,
    UUID projectId,
    Instant occurredAt
) implements ResourceEvent {}
```

### 3. Application Layer: ResourceService.java

```java
package com.providence.resource.application.service;

import com.providence.common.tenant.TenantContext;
import com.providence.common.security.SecurityContext;
import com.providence.common.outbox.OutboxService;
import com.providence.common.audit.AuditLogService;
import com.providence.resource.domain.Resource;
import com.providence.resource.domain.event.ResourceAllocated;
import com.providence.resource.infrastructure.repository.ResourceRepository;
import com.providence.resource.application.command.AllocateResourceCommand;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

@Service
public class ResourceService {

    private final ResourceRepository resourceRepo;
    private final OutboxService outboxService;
    private final AuditLogService auditLogService;

    public ResourceService(ResourceRepository resourceRepo,
                           OutboxService outboxService,
                           AuditLogService auditLogService) {
        this.resourceRepo = resourceRepo;
        this.outboxService = outboxService;
        this.auditLogService = auditLogService;
    }

    @Transactional
    public void allocate(AllocateResourceCommand cmd) {
        UUID tenantId = TenantContext.getCurrentTenantId();
        String correlationId = TenantContext.getCurrentCorrelationId();
        UUID actorId = SecurityContext.getCurrentUserId();

        // 1. Load resource (scoped to t_<tenant>)
        Resource resource = resourceRepo.findById(cmd.resourceId())
            .orElseThrow(() -> new ResourceNotFoundException(
                "RESOURCE_NOT_FOUND",
                "Resource not found",
                "Resource",
                cmd.resourceId().toString()
            ));

        // 2. Domain method enforces business rules
        resource.allocate(cmd.projectId(), cmd.startDate(), cmd.endDate());
        resourceRepo.save(resource);

        // 3. Emit domain event to outbox
        ResourceAllocated event = new ResourceAllocated(
            resource.getId(),
            tenantId,
            cmd.projectId(),
            resource.getName(),
            cmd.startDate(),
            cmd.endDate(),
            Instant.now()
        );
        outboxService.publish(OutboxEvent.builder()
            .tenantId(tenantId)
            .aggregateType("Resource")
            .aggregateId(resource.getId())
            .eventType("Allocated")
            .eventVersion(1)
            .correlationId(UUID.fromString(correlationId))
            .actorId(actorId)
            .payload(event)
            .build());

        // 4. Write audit log
        auditLogService.log(AuditEvent.builder()
            .tenantId(tenantId)
            .eventType("RESOURCE_ALLOCATED")
            .aggregateType("Resource")
            .aggregateId(resource.getId())
            .actorId(actorId)
            .correlationId(UUID.fromString(correlationId))
            .payload(Map.of(
                "resourceId", resource.getId().toString(),
                "projectId", cmd.projectId().toString(),
                "startDate", cmd.startDate().toString(),
                "endDate", cmd.endDate().toString()
            ))
            .build());

        // Transaction commits → Debezium publishes to Kafka
    }

    // Similar methods: release(), findById(), listAvailable()
}
```

### 4. Presentation Layer: ResourceController.java

```java
package com.providence.resource.adapter.web;

import com.providence.resource.application.service.ResourceService;
import com.providence.resource.application.command.AllocateResourceCommand;
import com.providence.resource.application.dto.*;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/resources")
@ApiVersion("1.0+")
public class ResourceController {

    private final ResourceService resourceService;
    private final ResourceMapper resourceMapper;

    public ResourceController(ResourceService resourceService, ResourceMapper resourceMapper) {
        this.resourceService = resourceService;
        this.resourceMapper = resourceMapper;
    }

    /**
     * Allocate resource to project.
     *
     * POST /api/resources/{id}/allocate
     * Headers: Idempotency-Key
     * Body: {"projectId": "...", "startDate": "2026-02-01", "endDate": "2026-03-01"}
     */
    @PostMapping("/{id}/allocate")
    @ResponseStatus(HttpStatus.OK)
    public void allocate(
            @PathVariable UUID id,
            @Valid @RequestBody AllocateResourceRequest request) {
        var command = resourceMapper.toCommand(id, request);
        resourceService.allocate(command);
    }

    // Similar endpoints: release(), getById(), list(), utilization()
}
```

### 5. Kafka Consumer: ResourceEventConsumer.java

```java
package com.providence.resource.adapter.consumer;

import com.providence.common.inbox.InboxService;
import com.providence.resource.domain.event.ResourceAllocated;
import com.providence.notification.service.NotificationService;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Component
public class ResourceEventConsumer {

    private final InboxService inboxService;
    private final NotificationService notificationService;

    public ResourceEventConsumer(InboxService inboxService,
                                 NotificationService notificationService) {
        this.inboxService = inboxService;
        this.notificationService = notificationService;
    }

    @KafkaListener(
        topics = "ecap.events.Resource.Allocated",
        groupId = "resource-allocation-service"
    )
    @Transactional
    public void handleResourceAllocated(
            @Payload ResourceAllocated event,
            @Header(KafkaHeaders.RECEIVED_KEY) UUID eventId,
            @Header("tenantId") String tenantIdHeader) {

        UUID tenantId = UUID.fromString(tenantIdHeader);

        // 1. Check inbox (already processed?)
        if (inboxService.isProcessed(tenantId, "ResourceAllocationTracker", eventId)) {
            return; // Duplicate event → Skip
        }

        // 2. Mark as processed
        inboxService.markProcessed(tenantId, "ResourceAllocationTracker", eventId,
            "ecap.events.Resource.Allocated", 0, 0L);

        // 3. Apply business logic
        notificationService.sendResourceAllocatedNotification(
            event.resourceId(),
            event.projectId(),
            event.startDate(),
            event.endDate()
        );

        // Transaction commits → Exactly-once effect
    }
}
```

### 6. Database Migration: V002__create_resources_table.sql

```sql
-- ============================================================================
-- V002: Create resources table (tenant schema)
-- ============================================================================
-- Location: src/main/resources/db/migration/tenant/V002__create_resources_table.sql
-- Applied to: t_<tenant> schema
-- ============================================================================

CREATE TABLE IF NOT EXISTS resources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(100) NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('PERSONNEL', 'EQUIPMENT', 'BUDGET')),
    available BOOLEAN NOT NULL DEFAULT TRUE,

    -- Audit timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID,
    updated_by UUID
);

-- Indexes
CREATE INDEX idx_resources_type ON resources(type);
CREATE INDEX idx_resources_available ON resources(available) WHERE available = TRUE;
CREATE INDEX idx_resources_name ON resources(name);

-- Trigger: Auto-update updated_at
CREATE OR REPLACE FUNCTION update_resources_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_resources_updated_at
    BEFORE UPDATE ON resources
    FOR EACH ROW
    EXECUTE FUNCTION update_resources_updated_at();

COMMENT ON TABLE resources IS
    'Resource management table. Tracks personnel, equipment, and budget allocations.';
```

---

## ✅ Implementation Checklist

To implement Resource Management, follow these steps:

- [ ] **Copy skeleton code** from this document
- [ ] **Create packages**: `com.providence.resource.*`
- [ ] **Domain layer**: Resource.java, ResourceType.java, ResourceEvent.java
- [ ] **Application layer**: ResourceService.java, AllocateResourceCommand.java, DTOs
- [ ] **Infrastructure layer**: ResourceRepository.java (reuse OutboxService, AuditLogService)
- [ ] **Presentation layer**: ResourceController.java, ResourceMapper.java
- [ ] **Kafka consumer**: ResourceEventConsumer.java (inbox pattern)
- [ ] **Database**: V002__create_resources_table.sql (tenant schema)
- [ ] **Tests**: IdempotencyTest, CrossTenantIsolationTest, InboxDeduplicationTest
- [ ] **Kafka topics**: Create `ecap.events.Resource.Allocated`, `ecap.events.Resource.Released`
- [ ] **Verify**: Run integration tests, check outbox → Kafka → inbox flow

---

## 🔄 Pattern Replication for Other Features

| Feature | Aggregate | Events | Complexity |
|---------|-----------|--------|------------|
| **Resource Management** | Resource | ResourceAllocated, ResourceReleased | Medium (this skeleton) |
| **Fund Management** | FundTransfer | TransferCreated, TransferCompleted | High (financial correctness) |
| **Human Management** | User | UserRegistered, RoleAssigned | Medium (RBAC integration) |

**Steps to replicate:**
1. Copy `FEATURE_EXAMPLE_PROJECT_MANAGEMENT.md` structure
2. Replace "Project" with your aggregate name (e.g., "Resource", "FundTransfer", "User")
3. Define domain events specific to your aggregate
4. Implement service with outbox + audit (same pattern)
5. Create REST controller with idempotency (same pattern)
6. Add Kafka consumer with inbox pattern (same pattern)
7. Write tenant migration (CREATE TABLE in t_<tenant> schema)
8. Add integration tests (idempotency, isolation, inbox)

---

## 📚 Related Documentation

- [FEATURE_EXAMPLE_PROJECT_MANAGEMENT.md](FEATURE_EXAMPLE_PROJECT_MANAGEMENT.md) — Full implementation reference
- [CLAUDE.md](CLAUDE.md) — Master engineering constitution
- [PUBLIC_SCHEMA_DESIGN.md](PUBLIC_SCHEMA_DESIGN.md) — Database schema reference
- [KAFKA_TOPIC_STRATEGY.md](KAFKA_TOPIC_STRATEGY.md) — Event streaming patterns

---

**Status:** Skeleton ready ✅
**Next:** Implement full Resource Management feature based on Project Management pattern
**Estimated LOC:** ~1,200 lines (domain, application, infrastructure, presentation, tests)
