# User Roles and Tenant-Level RBAC - User Story

> **Story ID:** PROV-105
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P0

---

## User Story

**As a** tenant administrator
**I want to** assign tenant-level roles (`ROLE_ADMIN`, `ROLE_USER`, `ROLE_OWNER`) to users, with roles managed via an administered reference table
**So that** access control is enforced across the platform with `ROLE_OWNER` having the special ability to terminate the tenant

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] Users can have one or more tenant-level roles from the `ref_tenant_roles` reference table
- [ ] Default roles seeded: `ROLE_OWNER` (full tenant control), `ROLE_ADMIN` (user management), `ROLE_USER` (standard access)
- [ ] `ROLE_OWNER` is a special role — users with this role can terminate the tenant; `ROLE_ADMIN` cannot
- [ ] Admin endpoint `PUT /api/v1/users/{userId}/roles` assigns roles (requires `ROLE_ADMIN` or `ROLE_OWNER`)
- [ ] Endpoint requires `Idempotency-Key` header
- [ ] `UserRoleAssignedEvent` published via outbox when a role is assigned
- [ ] `UserRoleRevokedEvent` published via outbox when a role is removed
- [ ] Audit log entries: `USER_ROLE_ASSIGNED`, `USER_ROLE_REVOKED`
- [ ] New users receive `ROLE_USER` by default on registration
- [ ] Role assignment is idempotent — assigning an existing role is a no-op
- [ ] Roles appear in JWT claims on next login
- [ ] `@PreAuthorize("hasRole('ROLE_ADMIN')")` gates user management endpoints
- [ ] `@PreAuthorize("hasRole('ROLE_OWNER')")` gates tenant termination

**Should Have (Nice to Have):**
- [ ] Administrators can add custom roles to `ref_tenant_roles` via admin API
- [ ] Role assignment history (who assigned, when)

**Won't Have (Out of Scope):**
- Group-level roles (see PROV-107)
- Feature entitlements (see PROV-106)
- Spring Security hierarchy resolution (see PROV-106)

---

## Business Context

### Problem Statement
Multi-tenant platforms require role-based access control scoped to each tenant. Roles must be extensible (via administered reference tables rather than hardcoded enums) and auditable. The `ROLE_OWNER` designation provides a clear authorization boundary for destructive tenant operations.

### Target Users
- **Primary:** Tenant administrators assigning roles to users
- **Secondary:** Tenant owners with full lifecycle control

### Success Metrics
- Zero unauthorized role escalations (100% enforcement via `@PreAuthorize`)
- Role assignment API < 100ms p99

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| User registration | PROV-101 | Prerequisite | Users must exist to receive roles |
| Reference tables | PROV-100 | Shared | `ref_tenant_roles` seeded in tenant migration V001 |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

`user_roles`, `ref_tenant_roles` — see [PROV-100](PROV-100-user-identity-access-management.md) Database Schema section for full DDL.

---

## Domain Events

**Events Emitted:**
- `UserRoleAssigned` → `ecap.events.User.RoleAssigned` (30-day retention)
- `UserRoleRevoked` → `ecap.events.User.RoleRevoked`

**Partition key:** `tenant_id`

---

## API Endpoints

```http
PUT /api/v1/users/{userId}/roles (Admin only)
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}

{ "roles": ["ROLE_USER", "ROLE_ADMIN"] }

Response: 200 OK
{
  "userId": "7c9e6679-...",
  "roles": ["ROLE_USER", "ROLE_ADMIN"],
  "updatedAt": "2026-02-12T10:30:00Z"
}
```

```http
GET /api/v1/users (Admin only)
Authorization: Bearer <jwt>
Query params: ?page=0&size=20&status=ACTIVE&role=ROLE_USER

Response: 200 OK
{
  "content": [...],
  "page": { "number": 0, "size": 20, "totalElements": 150, "totalPages": 8 }
}
```

**gRPC:**
```protobuf
service UserService {
    rpc AssignRoles(AssignRolesRequest) returns (UserResponse);
    rpc ListUsers(ListUsersRequest) returns (ListUsersResponse);
}
```

---

## Implementation Checklist

### Domain Layer
- [ ] `UserRole.java` — Value object with FK to `ref_tenant_roles`
- [ ] `UserRoleAssigned.java`, `UserRoleRevoked.java` — Domain event records

### Application Layer
- [ ] `UserService.assignRoles()` — Computes diff (added/removed), emits events per change, in `@Transactional`

### Infrastructure Layer
- [ ] `UserRoleRepository.java` — `JpaRepository<UserRole, UUID>`
- [ ] `RefTenantRoleRepository.java` — Reference table repository
- [ ] Outbox and audit logging integration

### Adapter Layer
- [ ] `UserController.java` — REST: `PUT /api/v1/users/{userId}/roles`, `GET /api/v1/users`
- [ ] `UserGrpcService.java` — gRPC: `AssignRoles`, `ListUsers`

---

## Testing Requirements

**Unit Tests:**
- [ ] Assign role: new role → `UserRoleAssigned` event emitted
- [ ] Assign role: already has role → no-op, no event
- [ ] Remove role: role revoked → `UserRoleRevoked` event emitted
- [ ] Invalid role code → validation error
- [ ] Non-admin caller → 403 Forbidden

**Integration Tests:**
- [ ] **Authorization:** Non-admin calls role assignment → 403
- [ ] **ROLE_OWNER:** Only ROLE_OWNER can trigger tenant termination; ROLE_ADMIN cannot
- [ ] **Audit Logging:** Role assignment → audit_log entries
- [ ] **JWT Claims:** After role change, next login JWT includes updated roles

---

## Observability

**Metrics:**
```java
meterRegistry.counter("user.role.assigned", "tenant", tenantId, "role", role).increment();
meterRegistry.counter("user.role.revoked", "tenant", tenantId, "role", role).increment();
```

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
