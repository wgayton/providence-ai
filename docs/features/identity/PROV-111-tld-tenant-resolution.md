# TLD User-to-Tenant Resolution - User Story

> **Story ID:** PROV-111
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Related:** [PROV-101](PROV-101-user-registration-otp.md) (registration populates map), [PROV-102](PROV-102-login-brute-force-throttling.md) (login consumes map)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P1

---

## User Story

**As a** registered user accessing Providence from a mobile app or a client that does not use tenant subdomains
**I want to** log in using only my email and password at the top-level domain (e.g., `providence.ai`)
**So that** the system resolves my tenant automatically and I can authenticate without knowing or providing my tenant subdomain

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] `public.user_tenant_map` table maps login email → tenant(s), populated atomically during registration (same transaction as user creation)
- [ ] `POST /api/v1/auth/resolve-tenant` endpoint accepts `{ "email": "..." }` and returns the tenant(s) associated with that email
- [ ] If email maps to exactly one tenant → return tenant slug directly (single-tenant resolution)
- [ ] If email maps to multiple tenants → return list of tenants for user to select (multi-tenant disambiguation)
- [ ] If email maps to no tenants → return `404 Not Found` with RFC 9457 ProblemDetail (generic message to prevent email enumeration)
- [ ] Tenant resolution response does NOT reveal whether the email exists — `404` message is identical for "no account" and "email not found"
- [ ] `POST /api/v1/auth/login` at TLD level accepts `{ "email": "...", "password": "...", "tenantSlug": "..." }` for multi-tenant users
- [ ] Mobile app flow: resolve-tenant → (optional tenant selection) → login with resolved tenant context
- [ ] `user_tenant_map` entry created in same transaction as user registration (outbox atomicity)
- [ ] `user_tenant_map` entry deleted when user account is deleted (`ON DELETE CASCADE` via `user_id` FK)
- [ ] `user_tenant_map.email` is always stored as lowercase (case-insensitive lookup)
- [ ] Rate limiting on resolve-tenant endpoint: max 10 requests per IP per minute (prevents email enumeration brute force)
- [ ] Audit log entry: `TENANT_RESOLUTION_REQUESTED`, `TENANT_RESOLUTION_SUCCEEDED`, `TENANT_RESOLUTION_FAILED`
- [ ] All resolve-tenant responses include `Cache-Control: no-store` (prevents caching of tenant associations)

**Should Have (Nice to Have):**
- [ ] Resolve-tenant response includes tenant display name and logo URL for mobile app tenant picker UI
- [ ] Remember last-used tenant in mobile app (client-side preference, not server state)
- [ ] `user_tenant_map` supports email change propagation — when user changes email in a tenant, the map entry is updated

**Won't Have (Out of Scope):**
- Phone number-based tenant resolution (future story, depends on PROV-110 SMS path)
- SSO/OAuth2 tenant resolution (future story)
- Automatic tenant creation from TLD registration (tenants are pre-provisioned)
- Tenant switching within an active session (requires re-authentication)

---

## Business Context

### Problem Statement
Mobile applications and API clients that don't use browser-based subdomain routing have no natural way to determine which tenant a user belongs to. Without TLD-level tenant resolution, these clients would need to hardcode tenant subdomains or require users to manually enter their organization's slug — a poor user experience. The `public.user_tenant_map` provides a cross-tenant lookup that resolves a user's email to their tenant(s) while protecting against email enumeration attacks.

### Target Users
- **Primary:** Mobile app users who don't have subdomain context
- **Secondary:** API clients and third-party integrations authenticating against the TLD
- **Tertiary:** Users who belong to multiple tenants and need to select which organization to log into

### Success Metrics
- Tenant resolution API response time < 50ms p99 (simple index lookup)
- Email enumeration protection: identical response times for existing and non-existing emails
- Multi-tenant user disambiguation rate: 100% (user always gets a clear tenant selection)
- Zero orphaned `user_tenant_map` entries (cascade delete verified)

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| User registration | PROV-101 | Prerequisite | Registration populates `user_tenant_map` atomically |
| Login with throttling | PROV-102 | Integration | TLD login uses resolved tenant context |
| Credential separation | PROV-109 | Prerequisite | `credentials.email` is the login identifier |
| System tenant | PROV-108 | Prerequisite | Default tenant must exist for integration testing |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

**Public Schema** (`public.user_tenant_map`):

See [PROV-100](PROV-100-user-identity-access-management.md) Database Schema section for full DDL.

```sql
-- Cross-tenant lookup: maps login email → tenant for TLD-level authentication
-- Populated atomically during registration (same transaction)
CREATE TABLE IF NOT EXISTS public.user_tenant_map (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL,
    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_user_tenant_email UNIQUE (email, tenant_id)
);

CREATE INDEX idx_user_tenant_map_email ON public.user_tenant_map(email);
CREATE INDEX idx_user_tenant_map_tenant ON public.user_tenant_map(tenant_id);
```

**Migration:** `V008__create_user_tenant_map_table.sql` in `/src/main/resources/db/migration/public/`

**Key design decisions:**
- **Public schema:** The table is in `public` because it spans all tenants — querying across `t_*` schemas would be impractical
- **Email stored lowercase:** `LOWER(email)` enforced at insertion to ensure case-insensitive lookups
- **Multi-tenant support:** Same email can appear in multiple rows (one per tenant) for users with accounts in multiple organizations
- **Cascade delete:** `ON DELETE CASCADE` on `tenant_id` FK ensures cleanup when a tenant is removed

---

## Domain Events

**Events Emitted:**
- `TenantResolutionRequested` → (not published to Kafka — logged to audit only, high volume)

**Events Consumed:**
- `UserRegistered` → Populates `user_tenant_map` entry (or handled synchronously in registration transaction)
- `UserDeleted` → Removes `user_tenant_map` entry (handled by CASCADE or explicit cleanup)

---

## API Endpoints

**Tenant Resolution:**
```http
POST /api/v1/auth/resolve-tenant
Host: providence.ai
Content-Type: application/json

{
  "email": "jane@example.com"
}

Response: 200 OK (single tenant)
{
  "email": "jane@example.com",
  "tenants": [
    {
      "tenantSlug": "acme",
      "tenantName": "Acme Corporation"
    }
  ],
  "requiresSelection": false
}

Response: 200 OK (multiple tenants)
{
  "email": "jane@example.com",
  "tenants": [
    {
      "tenantSlug": "acme",
      "tenantName": "Acme Corporation"
    },
    {
      "tenantSlug": "globex",
      "tenantName": "Globex Inc"
    }
  ],
  "requiresSelection": true
}

Response: 404 Not Found (no mapping — generic message)
{
  "type": "https://providence.ai/problems/tenant-not-found",
  "title": "Tenant Not Found",
  "status": 404,
  "detail": "Unable to resolve tenant for the provided credentials.",
  "instance": "/api/v1/auth/resolve-tenant"
}
```

**TLD Login (with tenant context):**
```http
POST /api/v1/auth/login
Host: providence.ai
Content-Type: application/json

{
  "email": "jane@example.com",
  "password": "SecureP@ssw0rd123",
  "tenantSlug": "acme",
  "deviceFingerprint": "a1b2c3d4e5..."
}

Response: 200 OK
{
  "token": "<jwt-token>",
  "expiresAt": "2026-02-12T11:30:00Z",
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "tenantSlug": "acme",
  "roles": ["ROLE_USER"],
  "features": ["FEATURE_PROJECT_STANDARD", "FEATURE_FINANCE_PRO"]
}
```

**Mobile App Flow:**
1. User opens app → enters email
2. App calls `POST /api/v1/auth/resolve-tenant` with email
3. If single tenant → proceed directly to login with resolved `tenantSlug`
4. If multiple tenants → show tenant picker → user selects → proceed to login
5. App calls `POST /api/v1/auth/login` with email, password, and resolved `tenantSlug`
6. App stores JWT and `tenantSlug` for subsequent API calls

**gRPC:**
```protobuf
service AuthService {
    rpc ResolveTenant(ResolveTenantRequest) returns (ResolveTenantResponse);
}

message ResolveTenantRequest {
    string email = 1;
}

message ResolveTenantResponse {
    string email = 1;
    repeated TenantInfo tenants = 2;
    bool requires_selection = 3;
}

message TenantInfo {
    string tenant_slug = 1;
    string tenant_name = 2;
}
```

---

## Implementation Checklist

### Domain Layer (`com.providence.identity.domain`)
- [ ] `UserTenantMapping.java` — Entity: email, tenant_id, user_id (public schema entity)
- [ ] Business rules: email normalization (lowercase), multi-tenant disambiguation logic

### Application Layer (`com.providence.identity.service`)
- [ ] `TenantResolutionService.resolveTenant()` — Looks up `user_tenant_map` by email, returns tenant(s)
- [ ] `AuthenticationService.register()` — Modified to write `user_tenant_map` entry in same transaction
- [ ] `ResolveTenantCommand.java` — Immutable command record
- [ ] DTOs: `ResolveTenantRequest`, `ResolveTenantResponse`, `TenantInfo`

### Infrastructure Layer
- [ ] `UserTenantMapRepository.java` — `JpaRepository<UserTenantMapping, UUID>` + `findByEmail(String email)`
- [ ] Rate limiting: 10 requests per IP per minute on resolve-tenant endpoint
- [ ] Audit logging: `TENANT_RESOLUTION_REQUESTED`, `TENANT_RESOLUTION_SUCCEEDED`, `TENANT_RESOLUTION_FAILED`

### Adapter Layer
- [ ] `AuthController.java` — Add `POST /api/v1/auth/resolve-tenant` endpoint
- [ ] Modify `POST /api/v1/auth/login` to accept optional `tenantSlug` for TLD-level login
- [ ] `AuthGrpcService.java` — Add `ResolveTenant` RPC
- [ ] Response headers: `Cache-Control: no-store` on all resolve-tenant responses

### Configuration
- [ ] `application.yml` rate limiting properties:
  ```yaml
  providence:
    auth:
      resolve-tenant:
        rate-limit:
          max-requests: 10
          window-minutes: 1
  ```

---

## Testing Requirements

**Unit Tests:**
- [ ] Resolve-tenant: email maps to one tenant → returns single tenant with `requiresSelection=false`
- [ ] Resolve-tenant: email maps to multiple tenants → returns list with `requiresSelection=true`
- [ ] Resolve-tenant: email maps to no tenants → returns 404 ProblemDetail
- [ ] Resolve-tenant: case-insensitive email lookup (`Jane@Example.com` matches `jane@example.com`)
- [ ] Registration: creates `user_tenant_map` entry in same transaction
- [ ] Registration: `user_tenant_map` email stored as lowercase
- [ ] TLD login: valid email + password + tenantSlug → JWT returned with tenant context
- [ ] TLD login: valid email but wrong tenantSlug → 401 Unauthorized
- [ ] Rate limiting: 11th request within 1 minute → 429 Too Many Requests

**Integration Tests:**
- [ ] **Happy Path (Single Tenant):** Register on tenant A → resolve-tenant → returns tenant A → login with tenant A → JWT
- [ ] **Happy Path (Multi-Tenant):** Register on tenant A and B → resolve-tenant → returns both → login with selected tenant → JWT
- [ ] **Email Enumeration Protection:** resolve-tenant for non-existent email → 404 with same timing as existing email
- [ ] **Rate Limiting:** 10 rapid resolve-tenant calls → 200 OK; 11th → 429 Too Many Requests
- [ ] **Cascade Delete:** Delete tenant → `user_tenant_map` entries for that tenant removed
- [ ] **Registration Atomicity:** Registration fails → no `user_tenant_map` entry (transaction rollback)
- [ ] **Audit Trail:** resolve-tenant calls → audit_log entries created
- [ ] **Cross-Tenant Isolation:** resolve-tenant reveals tenant slugs but NOT user data from other tenants

---

## Security Considerations

- [ ] **Email enumeration protection:** Response for non-existent emails is identical to no-mapping-found (same status, same timing)
- [ ] **Timing attack mitigation:** Add constant-time comparison or artificial delay to equalize response times
- [ ] **Rate limiting:** Strict per-IP rate limiting prevents brute-force email scanning
- [ ] **No credential exposure:** resolve-tenant only returns tenant slug/name — never user data, passwords, or account status
- [ ] **Cache-Control:** `no-store` header prevents proxies from caching tenant associations
- [ ] **Lowercase normalization:** All emails stored and queried as lowercase to prevent case-based bypass

---

## Observability

**Logging:**
```java
log.info("Tenant resolution requested: email={}", maskedEmail);
log.info("Tenant resolution succeeded: email={}, tenantCount={}", maskedEmail, count);
log.warn("Tenant resolution failed: email={}, reason=not_found", maskedEmail);
log.warn("Tenant resolution rate limited: ip={}, attempts={}/10", ip, attempts);
```

**Metrics:**
```java
meterRegistry.counter("auth.resolve_tenant.requested").increment();
meterRegistry.counter("auth.resolve_tenant.succeeded", "tenant_count", String.valueOf(count)).increment();
meterRegistry.counter("auth.resolve_tenant.not_found").increment();
meterRegistry.counter("auth.resolve_tenant.rate_limited").increment();
meterRegistry.timer("auth.resolve_tenant.duration").record(duration);
```

**Operational Alerts:**
- Resolve-tenant 404 rate > 50% over 5 minutes → potential email enumeration attack
- Rate limit violations > 100/minute across all IPs → coordinated scanning

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
