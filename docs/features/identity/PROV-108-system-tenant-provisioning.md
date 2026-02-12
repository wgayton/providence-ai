# Default System Tenant Provisioning - User Story

> **Story ID:** PROV-108
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P0

---

## User Story

**As a** platform operator
**I want to** have a default "System" tenant automatically provisioned on application startup with full ENTERPRISE capabilities
**So that** internal platform operations have a dedicated tenant context and integration tests have a reliable baseline tenant

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] Default tenant named "System" with slug `system` and schema `t_system` is provisioned on application startup
- [ ] System tenant has a well-known UUID: `00000000-0000-0000-0000-000000000000`
- [ ] System tenant status is `ACTIVE` with subscription tier `ENTERPRISE` and unlimited users (`max_users = -1`)
- [ ] Provisioning is idempotent — `ON CONFLICT (slug) DO NOTHING` prevents duplicates on restart
- [ ] System tenant schema `t_system` is created and all tenant migrations applied
- [ ] System tenant has all product features enabled at `ENTERPRISE` level
- [ ] Provisioning runs before any other application bootstrap that depends on tenant context

**Should Have (Nice to Have):**
- [ ] System tenant has a default `ROLE_OWNER` user (platform super-admin)
- [ ] Health check includes system tenant existence verification

**Won't Have (Out of Scope):**
- Tenant provisioning API for non-system tenants (separate story)
- Tenant termination flow (separate story)
- Multi-tenant migration runner (infrastructure concern)

---

## Business Context

### Problem Statement
The platform requires a known tenant for internal operations, background jobs, and integration testing. Without a guaranteed baseline tenant, startup sequences that depend on tenant context would fail. The system tenant also serves as the ENTERPRISE reference for feature hierarchy testing.

### Target Users
- **Primary:** Platform operations / DevOps
- **Secondary:** Integration test suites requiring a baseline tenant

### Success Metrics
- System tenant available within 5 seconds of application startup
- Zero startup failures due to missing system tenant

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| None | — | — | This is a foundational story with no prerequisites |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

**Public Schema Seed:**
```sql
-- System tenant: default internal tenant (slug = 'system')
INSERT INTO public.tenants (id, slug, name, schema_name, status, subscription_tier, max_users)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    'system',
    'System',
    't_system',
    'ACTIVE',
    'ENTERPRISE',
    -1  -- unlimited users
) ON CONFLICT (slug) DO NOTHING;
```

**Tenant Schema:** Standard tenant migrations applied to `t_system` schema (reference tables, user tables, group tables).

---

## Implementation Checklist

### Application Layer
- [ ] `SystemTenantProvisioner.java` — `@Component` with `@EventListener(ApplicationReadyEvent.class)` or Flyway callback
- [ ] Inserts system tenant record if not exists
- [ ] Creates `t_system` schema if not exists
- [ ] Runs tenant Flyway migrations on `t_system`
- [ ] Seeds system tenant product features (all features at ENTERPRISE level)

### Infrastructure Layer
- [ ] SQL seed script: `V008__seed_system_tenant.sql` or application-level provisioner
- [ ] Flyway configuration for tenant schema migration execution

---

## Testing Requirements

**Unit Tests:**
- [ ] Provisioner: system tenant does not exist → creates tenant + schema
- [ ] Provisioner: system tenant already exists → no-op (idempotent)

**Integration Tests:**
- [ ] **System Tenant:** Application startup → system tenant exists in `public.tenants`
- [ ] **Schema Exists:** `t_system` schema exists with all expected tables
- [ ] **Product Features:** System tenant has ENTERPRISE features enabled

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
