# Groups, Group Types, and Group Memberships - User Story

> **Story ID:** PROV-107
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P1

---

## User Story

**As a** tenant user
**I want to** create and join groups that have typed roles defined by the group type, with membership roles validated against the group type's available roles
**So that** I can collaborate within tenant-scoped groups where each group type defines its own role structure (e.g., collaboration groups have OWNER/ADMIN/EDITOR/MEMBER, team groups have LEAD/MEMBER)

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] Users can create groups by selecting a group type (e.g., `collaboration`, `department`, `team`)
- [ ] Group types define available membership roles as a JSONB array (`group_types.available_roles`)
- [ ] The `collaboration` type defines: `OWNER`, `ADMIN`, `EDITOR`, `MEMBER`
- [ ] The `team` type defines: `LEAD`, `MEMBER`
- [ ] The `department` type has `available_roles = NULL` (no in-group roles)
- [ ] Group creator is automatically added as `OWNER` (or first role in available_roles) on creation
- [ ] Adding a member requires specifying a role key that exists in the group type's `available_roles`
- [ ] Assigning a role to a member of a group type with no `available_roles` is rejected (400 Bad Request)
- [ ] Assigning an invalid role key (not in `available_roles`) is rejected (400 Bad Request)
- [ ] Group status managed via `ref_group_statuses` reference table (ACTIVE, ARCHIVED)
- [ ] System-defined group types cannot be deleted
- [ ] `GroupCreatedEvent`, `GroupMemberAddedEvent`, `GroupMemberRemovedEvent`, `GroupMemberRoleChangedEvent` published via outbox
- [ ] All mutation endpoints require `Idempotency-Key` header
- [ ] Audit log entries for group mutations

**Should Have (Nice to Have):**
- [ ] Group invitation workflow (invite by email, accept/decline)
- [ ] Custom group types (tenant admins can create new types with custom role definitions)

**Won't Have (Out of Scope):**
- Group-level permissions on resources (future story)
- Group chat / messaging (separate feature)

---

## Business Context

### Problem Statement
Organizations need flexible grouping with role structures that vary by purpose. A collaboration group needs granular roles (owner, admin, editor, member) while a department group just needs membership. By defining roles on the group type as JSONB, each type controls its own role vocabulary without schema changes.

### Target Users
- **Primary:** Users creating and managing groups within their tenant
- **Secondary:** Tenant administrators managing group types

### Success Metrics
- Group creation API < 200ms p99
- Zero invalid role assignments (100% validation against available_roles)

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| User registration | PROV-101 | Prerequisite | Users must exist to create/join groups |
| Reference tables | PROV-100 | Shared | `ref_group_statuses` seeded in tenant migration V001 |
| Security hierarchy | PROV-106 | Downstream | Group roles resolved to GROUP_{groupId}_{ROLE} authorities |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

`group_types`, `groups`, `group_memberships`, `ref_group_statuses` — see [PROV-100](PROV-100-user-identity-access-management.md) Database Schema section for full DDL.

**Key design:**
- `group_types.available_roles` — JSONB array of `{"key", "label", "description", "display_order"}` objects
- `group_memberships.role` — VARCHAR(50), nullable; must match a `key` in the parent group type's `available_roles`
- Validation enforced at application layer, not DB constraint

---

## Domain Events

**Events Emitted:**
- `GroupCreated` → `ecap.events.Group.Created`
- `GroupMemberAdded` → `ecap.events.Group.MemberAdded`
- `GroupMemberRemoved` → `ecap.events.Group.MemberRemoved`
- `GroupMemberRoleChanged` → `ecap.events.Group.MemberRoleChanged`

**Partition key:** `tenant_id`

---

## API Endpoints

```http
POST /api/v1/groups
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}
Content-Type: application/json

{
  "name": "Frontend Team",
  "description": "Frontend engineering collaboration group",
  "groupTypeSlug": "collaboration"
}

Response: 201 Created
{
  "groupId": "g1a2b3c4-...",
  "name": "Frontend Team",
  "groupType": "collaboration",
  "availableRoles": [
    {"key": "OWNER", "label": "Owner"},
    {"key": "ADMIN", "label": "Administrator"},
    {"key": "EDITOR", "label": "Editor"},
    {"key": "MEMBER", "label": "Member"}
  ],
  "memberCount": 1,
  "createdAt": "2026-02-12T10:30:00Z"
}
```

```http
POST /api/v1/groups/{groupId}/members
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}

{ "userId": "7c9e6679-...", "role": "EDITOR" }

Response: 201 Created
```

```http
PUT /api/v1/groups/{groupId}/members/{userId}/role
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}

{ "role": "ADMIN" }

Response: 200 OK
```

```http
DELETE /api/v1/groups/{groupId}/members/{userId}
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}

Response: 204 No Content
```

**gRPC:**
```protobuf
service GroupService {
    rpc CreateGroup(CreateGroupRequest) returns (GroupResponse);
    rpc AddMember(AddMemberRequest) returns (MembershipResponse);
    rpc RemoveMember(RemoveMemberRequest) returns (google.protobuf.Empty);
    rpc ChangeMemberRole(ChangeMemberRoleRequest) returns (MembershipResponse);
}
```

---

## Implementation Checklist

### Domain Layer
- [ ] `Group.java` — Aggregate root with name, description, type, status
- [ ] `GroupId.java` — Value object (record)
- [ ] `GroupType.java` — Entity with `available_roles` JSONB
- [ ] `GroupMembership.java` — Entity: user-group with role
- [ ] `GroupRoleDefinition.java` — Value object (record): deserialized from available_roles JSONB
- [ ] Domain events: `GroupCreated`, `GroupMemberAdded`, `GroupMemberRemoved`, `GroupMemberRoleChanged`
- [ ] Business rules: role validation against type's available_roles, creator auto-added as first role

### Application Layer
- [ ] `GroupService.java` — CRUD, membership management with `@Transactional`
- [ ] `CreateGroupCommand.java`, `AddMemberCommand.java`, `ChangeMemberRoleCommand.java`

### Infrastructure Layer
- [ ] `GroupRepository.java` — `JpaRepository<Group, UUID>`
- [ ] `GroupTypeRepository.java` — `JpaRepository<GroupType, UUID>` + `findBySlug`
- [ ] `GroupMembershipRepository.java` — `JpaRepository<GroupMembership, UUID>`
- [ ] `RefGroupStatusRepository.java`
- [ ] Outbox and audit logging integration

### Adapter Layer
- [ ] `GroupController.java` — REST endpoints
- [ ] `GroupGrpcService.java` — gRPC service

---

## Testing Requirements

**Unit Tests:**
- [ ] Group creation: valid type → group created, creator added with first available role
- [ ] Add member: valid role for collaboration type → membership created
- [ ] Add member: role not in available_roles → 400 Bad Request
- [ ] Add member: department type (no roles) with role specified → 400 Bad Request
- [ ] Add member: department type with no role → membership created with NULL role
- [ ] Role change: valid new role → updated, event emitted
- [ ] Role change: invalid role → 400 Bad Request

**Integration Tests:**
- [ ] **Happy Path:** Create group → add member with role → verify membership in DB → events on Kafka
- [ ] **Group Roles:** Collaboration group roles validated; team group LEAD/MEMBER only
- [ ] **Cross-Tenant Isolation:** Groups not visible across tenants
- [ ] **Audit Logging:** Group creation, member add, role change → audit entries

---

## Observability

**Metrics:**
```java
meterRegistry.counter("group.created", "tenant", tenantId).increment();
meterRegistry.counter("group.member.added", "tenant", tenantId).increment();
```

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
