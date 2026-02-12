# Spring Security Hierarchy - User Story

> **Story ID:** PROV-106
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P0

---

## User Story

**As a** platform developer
**I want to** implement a Spring Security authority hierarchy that resolves tenant product features, user role grants, and group roles into a unified `GrantedAuthority` set
**So that** `@PreAuthorize` checks work seamlessly across tenant features (with inherited levels), user roles, and group-level permissions

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] **Tenant level:** `public.tenant_product_features` defines enabled capabilities per tenant with feature levels from `public.ref_feature_levels`
- [ ] **Feature levels:** `STANDARD`, `PRO`, `MAX`, `ENTERPRISE` — stored in `public.ref_feature_levels` administered reference table
- [ ] **User level:** `user_feature_entitlements` is a boolean grant (feature key only); the feature level is inherited from the tenant's `tenant_product_features.feature_level`
- [ ] Authority resolution joins user grants with tenant levels to produce `FEATURE_<KEY>_<LEVEL>` authorities
- [ ] **Group level:** Group membership roles from `group_types.available_roles` resolve to `GROUP_{groupId}_{ROLE_KEY}` authorities
- [ ] JWT claims include: `sub` (user ID), `tenant_id`, `roles`, `features`, `exp`
- [ ] Spring Security `GrantedAuthority` hierarchy resolves all levels for `@PreAuthorize` checks
- [ ] `FeatureHierarchyVoter` implementation: `hasAuthority('FEATURE_PROJECT_STANDARD')` passes for users with STANDARD, PRO, MAX, or ENTERPRISE
- [ ] JWT filter extracts tenant context + roles + features into `SecurityContext`
- [ ] Admin endpoint to grant/revoke user feature entitlements (requires `ROLE_ADMIN`)
- [ ] Endpoint requires `Idempotency-Key` header

**Should Have (Nice to Have):**
- [ ] Feature entitlement admin API for tenant administrators
- [ ] Feature usage metrics per tenant/user

**Won't Have (Out of Scope):**
- Tenant subscription management / billing (future story)
- Feature flag service (different concern)

---

## Business Context

### Problem Statement
The platform requires a multi-layered authorization model: tenant subscriptions control which features exist, user grants control who can access them, and group roles provide contextual permissions. The feature level must always come from the tenant (never per-user) to prevent exceeding subscription tiers.

### Target Users
- **Primary:** Platform developers implementing `@PreAuthorize` checks
- **Secondary:** Tenant administrators managing user feature access

### Success Metrics
- Authority resolution < 10ms per request
- Zero feature-level escalation beyond tenant tier

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| User roles | PROV-105 | Prerequisite | Tenant roles must be in authority set |
| Groups | PROV-107 | Integration | Group roles included in authority resolution |
| System tenant | PROV-108 | Prerequisite | Tenant product features require tenants table |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

**Public schema:** `tenant_product_features`, `ref_feature_levels` — see PROV-100 for full DDL.

**Tenant schema:** `user_feature_entitlements` — see PROV-100 for full DDL. Note: no `feature_level` column; level inherited from tenant.

---

## Authority Resolution Flow

```
1. User authenticates → JWT issued
2. JWT filter extracts tenant_id, user_id
3. Load user's tenant roles from user_roles → ROLE_ADMIN, ROLE_USER, etc.
4. Load user's feature grants from user_feature_entitlements → [PROJECT, FINANCE]
5. Load tenant's feature levels from tenant_product_features → PROJECT=STANDARD, FINANCE=PRO
6. Join: user grant + tenant level → FEATURE_PROJECT_STANDARD, FEATURE_FINANCE_PRO
7. Load user's group memberships → GROUP_{groupId}_ADMIN, GROUP_{groupId}_MEMBER
8. Combine all into GrantedAuthority set in SecurityContext
```

**Spring Security Authority Resolution:**
```
GrantedAuthorities for a user session:
├── Tenant Roles:     ROLE_ADMIN, ROLE_USER, ROLE_OWNER
├── User Features:    FEATURE_PROJECT_STANDARD, FEATURE_FINANCE_PRO, ...
│                     (level inherited from tenant_product_features)
└── Group Roles:      GROUP_{groupId}_ADMIN, GROUP_{groupId}_MEMBER
```

---

## Implementation Checklist

### Domain Layer
- [ ] `FeatureEntitlement.java` — Value object: feature key grant (boolean; level inherited from tenant)

### Application Layer
- [ ] `AuthorityResolutionService.java` — Resolves full GrantedAuthority set from roles + features + groups
- [ ] `FeatureEntitlementService.java` — Grant/revoke user feature access with `@Transactional`
- [ ] `FeatureHierarchyVoter.java` — Custom voter: STANDARD < PRO < MAX < ENTERPRISE

### Infrastructure Layer
- [ ] `UserFeatureEntitlementRepository.java` — `JpaRepository`
- [ ] `TenantProductFeatureRepository.java` — Query tenant features by tenant_id
- [ ] JWT token generation: include resolved authorities in claims
- [ ] JWT filter: extract and rebuild GrantedAuthority set

### Adapter Layer
- [ ] Feature entitlement admin endpoints (grant/revoke)

---

## Testing Requirements

**Unit Tests:**
- [ ] Authority resolution: user with PROJECT grant + tenant PROJECT=STANDARD → `FEATURE_PROJECT_STANDARD`
- [ ] Authority resolution: user without grant → feature not in authority set (even if tenant has it)
- [ ] Feature hierarchy: `hasAuthority('FEATURE_PROJECT_STANDARD')` passes for PRO, MAX, ENTERPRISE
- [ ] Feature hierarchy: `hasAuthority('FEATURE_PROJECT_PRO')` fails for STANDARD
- [ ] User cannot exceed tenant tier (tenant has STANDARD, user cannot get PRO)

**Integration Tests:**
- [ ] **Security Hierarchy:** JWT includes tenant features + user roles + group roles → `@PreAuthorize` works
- [ ] **Feature Gating:** Endpoint with `@PreAuthorize("hasAuthority('FEATURE_PROJECT_STANDARD')")` → authorized user passes, unauthorized fails

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
