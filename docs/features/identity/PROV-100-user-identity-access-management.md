# User Identity & Access Management - User Story

> **Story ID:** PROV-100
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft

---

## User Story

**As a** user visiting a tenant's subdomain
**I want to** register, authenticate via OTP, and manage my identity with secure login protections, device tracking, and role-based group memberships
**So that** my account is secure with brute-force protection and security alerts, my credentials are isolated from my profile, and I can collaborate within tenant-scoped groups that have typed roles

---

## Acceptance Criteria

**Must Have (Required):**

### Registration & OTP
- [ ] User can register against a tenant subdomain (e.g., `acme.providence.ai`) which resolves to the tenant slug
- [ ] Registration initiates an OTP workflow — system sends a one-time password to the user's email or phone
- [ ] User must verify OTP to complete registration; unverified accounts cannot login
- [ ] Registration creates separate `credentials` and `user_profiles` records to prevent accidental credential leakage
- [ ] `UserRegisteredEvent` published to `ecap.events.User.Registered` via outbox pattern
- [ ] Audit log entry created with `event_type=USER_REGISTERED`

### Login & Brute-Force Protection
- [ ] User can login with username/email and password against the tenant subdomain
- [ ] System tracks all login attempts (success and failure) with IP, device fingerprint, and user agent
- [ ] After 3 consecutive failed login attempts, the account is locked (throttled) for a configurable cooldown period
- [ ] `UserAccountLockedEvent` published when account is locked after 3 failed attempts
- [ ] Locked accounts return `423 Locked` with RFC 9457 ProblemDetail response including `Retry-After` header
- [ ] Successful login resets the failed attempt counter

### Security Alerts
- [ ] User is alerted when 3 failed login attempts occur on their account (brute-force detection)
- [ ] User is alerted when a password change event occurs on their account
- [ ] Security alerts are persisted and retrievable via API (`GET /api/v1/users/me/alerts`)
- [ ] `SecurityAlertCreatedEvent` published for downstream notification services (email, push)

### Device Fingerprinting
- [ ] System captures device fingerprint, browser name/version, OS name/version, IP address, and user agent on every authentication event
- [ ] Device records are stored in `user_devices` table linked to the user
- [ ] New (previously unseen) devices trigger a `UserDeviceRegisteredEvent`
- [ ] User can view their registered devices via API (`GET /api/v1/users/me/devices`)
- [ ] User can revoke/remove a device (`DELETE /api/v1/users/me/devices/{deviceId}`)

### User-Tenant Model
- [ ] Users exist under tenants — all user data lives in tenant schema (`t_<slug>`)
- [ ] Credential data (`credentials` table) is physically separate from profile data (`user_profiles` table)
- [ ] A user has one or more tenant-level roles: `ROLE_ADMIN`, `ROLE_USER`, `ROLE_OWNER`
- [ ] `ROLE_OWNER` is a special role — users with this role can terminate the tenant
- [ ] Default tenant named "System" with slug `system` is provisioned on application startup

### Groups & Roles
- [ ] Users can belong to user-defined groups
- [ ] Groups have a type (via `group_types` table) — e.g., `collaboration`, `department`, `team`
- [ ] Each group type defines its available membership roles as a JSONB array (`available_roles` column)
- [ ] The `collaboration` group type defines roles: `OWNER`, `ADMIN`, `EDITOR`, `MEMBER` — extensible via JSONB
- [ ] Group types with `available_roles = NULL` do not support in-group roles (e.g., `department`)
- [ ] Group membership role is validated at the application layer against the group type's `available_roles` keys
- [ ] All enum-like columns (user status, tenant roles, feature levels, group statuses, alert types) use administered reference tables instead of CHECK constraints
- [ ] `GroupCreatedEvent`, `GroupMemberAddedEvent`, `GroupMemberRoleChangedEvent` published via outbox

### Spring Security Hierarchy
- [ ] **Tenant level:** Product features define enabled capabilities as authorities: `FEATURE_<FEATURE_KEY>_<LEVEL>` (e.g., `FEATURE_PROJECT_STANDARD`, `FEATURE_FINANCE_ENTERPRISE`)
- [ ] **Feature levels:** `STANDARD`, `PRO`, `MAX`, `ENTERPRISE` — controls rate limits, user counts, and feature depth
- [ ] **User level:** Tenant roles (`ROLE_ADMIN`, `ROLE_USER`, `ROLE_OWNER`) and per-user feature entitlements
- [ ] **Group level:** Contextual group roles derived from `group_types.available_roles` JSONB (e.g., `GROUP_{groupId}_OWNER`, `GROUP_{groupId}_ADMIN`)
- [ ] JWT claims include: `sub` (user ID), `tenant_id`, `roles`, `features`, `exp`
- [ ] Spring Security `GrantedAuthority` hierarchy resolves all levels for `@PreAuthorize` checks

**Should Have (Nice to Have):**
- [ ] OTP resend with rate limiting (max 3 resends per 10-minute window)
- [ ] Password strength validation (min 12 chars, uppercase, lowercase, digit, special)
- [ ] Trusted device marking — skip MFA on trusted devices
- [ ] Session management — concurrent session limits per subscription tier
- [ ] Group invitation workflow (invite by email, accept/decline)
- [ ] Bulk user import from CSV for tenant administrators
- [ ] Account recovery flow via email verification

**Won't Have (Out of Scope):**
- OAuth2 / Social login (SSO) — defer to future story
- Biometric authentication — separate feature
- LDAP / Active Directory integration — enterprise-tier future work
- Push notification delivery — separate notification service story
- Two-factor authentication via authenticator apps (TOTP) — future enhancement
- User profile avatars/media upload — separate media service

---

## Business Context

### Problem Statement
Enterprise SaaS platforms require robust identity management that isolates authentication credentials from profile data, prevents brute-force attacks, tracks user devices for anomaly detection, and provides flexible role-based access control within multi-tenant boundaries. Users need to register securely via tenant subdomains with OTP verification, and the platform must support hierarchical authorization spanning tenant features, user roles, and group-level permissions.

### Target Users
- **Primary:** End Users — registering and authenticating against tenant subdomains
- **Secondary:** Tenant Administrators (`ROLE_ADMIN`) — managing users, roles, and groups within their tenant
- **Tertiary:** Tenant Owners (`ROLE_OWNER`) — full tenant lifecycle control including termination
- **System:** Platform Operations — managing the default "System" tenant and cross-tenant infrastructure

### Success Metrics
- Registration-to-verified conversion rate > 90% (OTP completion)
- Zero unauthorized cross-tenant access (100% tenant isolation)
- Account lockout triggers within 500ms of 3rd failed attempt
- Security alert delivery < 60 seconds from triggering event
- Device fingerprint capture rate: 100% of authentication events
- Login API response time < 200ms p99

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Feature Scope

**Affected Domains:**
- [ ] Human Management (primary — users, credentials, profiles, devices, groups)
- [ ] Tenant Administration (tenant features, default System tenant, subscription tiers)

**Integration Points:**
- **APIs:** REST endpoints for auth, users, devices, alerts, groups
- **Events Emitted:** `UserRegistered`, `UserOtpVerified`, `UserLoginSucceeded`, `UserLoginFailed`, `UserAccountLocked`, `UserPasswordChanged`, `UserDeviceRegistered`, `SecurityAlertCreated`, `UserRoleAssigned`, `UserRoleRevoked`, `GroupCreated`, `GroupMemberAdded`, `GroupMemberRemoved`, `GroupMemberRoleChanged`
- **Events Consumed:** `SecurityAlertCreated` → Notification Service (email/push delivery)
- **Consumers:** `notification-service` group consumes security alerts for email dispatch

---

## Database Schema

### Public Schema Changes

**Feature Levels Reference** (`public.ref_feature_levels`):
```sql
-- Administered reference table for subscription feature levels
-- Controls rate limits, user counts, and feature depth per tier
CREATE TABLE IF NOT EXISTS public.ref_feature_levels (
    code VARCHAR(20) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default feature levels
INSERT INTO public.ref_feature_levels (code, label, description, display_order)
VALUES
    ('STANDARD', 'Standard', 'Base tier with core functionality', 1),
    ('PRO', 'Professional', 'Enhanced tier with advanced features and higher limits', 2),
    ('MAX', 'Max', 'Premium tier with maximum feature depth', 3),
    ('ENTERPRISE', 'Enterprise', 'Full platform access with unlimited capacity', 4)
ON CONFLICT (code) DO NOTHING;
```

**Tenant Product Features** (`public.tenant_product_features`):
```sql
-- Defines what product features each tenant has enabled at their subscription tier
-- Used for Spring Security authority resolution: FEATURE_<key>_<level>
CREATE TABLE IF NOT EXISTS public.tenant_product_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,

    -- Feature identifier (e.g., 'PROJECT', 'FINANCE', 'RESOURCE', 'HUMAN')
    feature_key VARCHAR(100) NOT NULL,

    -- Subscription level — references administered ref_feature_levels table
    feature_level VARCHAR(20) NOT NULL
        REFERENCES public.ref_feature_levels(code),

    -- Whether this feature is currently active for the tenant
    enabled BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Each tenant has at most one entry per feature key
    CONSTRAINT uq_tenant_feature UNIQUE (tenant_id, feature_key),

    -- Feature key must be UPPER_SNAKE_CASE
    CONSTRAINT chk_feature_key_format CHECK (feature_key ~ '^[A-Z][A-Z0-9_]*$')
);

CREATE INDEX idx_tenant_features_tenant ON public.tenant_product_features(tenant_id)
    WHERE enabled = TRUE;
```

**Default System Tenant Seed** (added to tenant provisioning):
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

**Migration Files:**
- `V006__create_ref_feature_levels_table.sql` in `/src/main/resources/db/migration/public/`
- `V007__create_tenant_product_features_table.sql` in `/src/main/resources/db/migration/public/`

---

### Tenant Schema Changes (`t_<tenant>`)

**User Statuses Reference** (`ref_user_statuses`):
```sql
-- Administered reference table for user lifecycle statuses
CREATE TABLE IF NOT EXISTS ref_user_statuses (
    code VARCHAR(30) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_user_statuses (code, label, description, display_order)
VALUES
    ('PENDING_VERIFICATION', 'Pending Verification', 'Registered, awaiting OTP verification', 1),
    ('ACTIVE', 'Active', 'Verified and able to login', 2),
    ('SUSPENDED', 'Suspended', 'Disabled by administrator', 3),
    ('DEACTIVATED', 'Deactivated', 'Self-deactivated by user', 4)
ON CONFLICT (code) DO NOTHING;
```

**Tenant Roles Reference** (`ref_tenant_roles`):
```sql
-- Administered reference table for tenant-level user roles
-- ROLE_ prefix follows Spring Security convention
CREATE TABLE IF NOT EXISTS ref_tenant_roles (
    code VARCHAR(50) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_tenant_roles (code, label, description, display_order)
VALUES
    ('ROLE_OWNER', 'Owner', 'Full tenant control including termination', 1),
    ('ROLE_ADMIN', 'Administrator', 'User management and configuration', 2),
    ('ROLE_USER', 'User', 'Standard authenticated user', 3)
ON CONFLICT (code) DO NOTHING;
```

**Group Statuses Reference** (`ref_group_statuses`):
```sql
-- Administered reference table for group lifecycle statuses
CREATE TABLE IF NOT EXISTS ref_group_statuses (
    code VARCHAR(20) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_group_statuses (code, label, description, display_order)
VALUES
    ('ACTIVE', 'Active', 'Group is operational', 1),
    ('ARCHIVED', 'Archived', 'Group is read-only and no longer active', 2)
ON CONFLICT (code) DO NOTHING;
```

**Alert Types Reference** (`ref_alert_types`):
```sql
-- Administered reference table for security alert classifications
CREATE TABLE IF NOT EXISTS ref_alert_types (
    code VARCHAR(50) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_alert_types (code, label, description, display_order)
VALUES
    ('BRUTE_FORCE_DETECTED', 'Brute Force Detected', '3 failed login attempts on the account', 1),
    ('PASSWORD_CHANGED', 'Password Changed', 'Account password was changed', 2),
    ('NEW_DEVICE_LOGIN', 'New Device Login', 'Login from a previously unrecognized device', 3),
    ('ACCOUNT_LOCKED', 'Account Locked', 'Account locked due to failed login attempts', 4),
    ('ACCOUNT_UNLOCKED', 'Account Unlocked', 'Account unlocked after cooldown period expired', 5)
ON CONFLICT (code) DO NOTHING;
```

---

**Users — Identity Anchor** (`users`):
```sql
-- Core identity record — aggregate root for the User bounded context
-- Deliberately minimal: no credentials, no profile data
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- User lifecycle — references administered ref_user_statuses table
    status VARCHAR(30) NOT NULL DEFAULT 'PENDING_VERIFICATION'
        REFERENCES ref_user_statuses(code),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_status ON users(status) WHERE status = 'ACTIVE';
```

**Credentials — Login Data** (`credentials`):
```sql
-- SEPARATE from user_profiles to prevent accidental credential leakage
-- Contains ONLY authentication-related data
CREATE TABLE IF NOT EXISTS credentials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    -- Login identifier (unique within tenant)
    username VARCHAR(255) NOT NULL UNIQUE,

    -- bcrypt/argon2 password hash (NEVER store plaintext)
    password_hash VARCHAR(255) NOT NULL,

    -- OTP verification
    otp_secret VARCHAR(255),          -- TOTP secret for OTP generation
    otp_verified_at TIMESTAMPTZ,      -- NULL = not yet verified

    -- Brute-force protection
    failed_attempt_count INT NOT NULL DEFAULT 0,
    locked_until TIMESTAMPTZ,         -- NULL = not locked
    last_failed_at TIMESTAMPTZ,

    -- Password lifecycle
    password_changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_credentials_username ON credentials(username);
CREATE INDEX idx_credentials_user_id ON credentials(user_id);
CREATE INDEX idx_credentials_locked ON credentials(user_id)
    WHERE locked_until IS NOT NULL AND locked_until > NOW();
```

**User Profiles — Personal Information** (`user_profiles`):
```sql
-- Profile information SEPARATE from credentials
-- Safe to expose in API responses without risk of credential leakage
CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,

    -- Identity
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    display_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),

    -- Preferences
    timezone VARCHAR(50) DEFAULT 'UTC',
    locale VARCHAR(10) DEFAULT 'en-US',

    -- Metadata
    bio TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_profiles_email ON user_profiles(email);
CREATE INDEX idx_user_profiles_user_id ON user_profiles(user_id);
```

**User Devices — Fingerprinting** (`user_devices`):
```sql
-- Device fingerprint tracking for security and anomaly detection
CREATE TABLE IF NOT EXISTS user_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Fingerprint (hash of device characteristics)
    fingerprint_hash VARCHAR(255) NOT NULL,

    -- Device details
    device_name VARCHAR(255),          -- user-friendly name (e.g., "Chrome on MacOS")
    device_type VARCHAR(50),           -- DESKTOP, MOBILE, TABLET, UNKNOWN
    os_name VARCHAR(100),              -- e.g., "macOS", "Windows", "Android"
    os_version VARCHAR(50),            -- e.g., "14.2", "11"
    browser_name VARCHAR(100),         -- e.g., "Chrome", "Firefox", "Safari"
    browser_version VARCHAR(50),       -- e.g., "120.0.6099"

    -- Network
    ip_address INET NOT NULL,
    user_agent TEXT,

    -- Trust & lifecycle
    trusted BOOLEAN NOT NULL DEFAULT FALSE,
    first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Unique device per user (same fingerprint = same device)
    CONSTRAINT uq_user_device_fingerprint UNIQUE (user_id, fingerprint_hash)
);

CREATE INDEX idx_user_devices_user ON user_devices(user_id);
CREATE INDEX idx_user_devices_fingerprint ON user_devices(fingerprint_hash);
CREATE INDEX idx_user_devices_last_seen ON user_devices(user_id, last_seen_at DESC);
```

**Login Attempts — Audit & Throttling** (`login_attempts`):
```sql
-- Records every login attempt for security analysis and throttling
CREATE TABLE IF NOT EXISTS login_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- NULL if user not found
    username VARCHAR(255) NOT NULL,                       -- attempted username (even if invalid)

    -- Outcome
    success BOOLEAN NOT NULL,
    failure_reason VARCHAR(100),  -- 'INVALID_PASSWORD', 'ACCOUNT_LOCKED', 'OTP_NOT_VERIFIED', 'USER_NOT_FOUND'

    -- Device context
    ip_address INET NOT NULL,
    device_fingerprint VARCHAR(255),
    user_agent TEXT,

    attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_login_attempts_user ON login_attempts(user_id, attempted_at DESC);
CREATE INDEX idx_login_attempts_ip ON login_attempts(ip_address, attempted_at DESC);
CREATE INDEX idx_login_attempts_recent ON login_attempts(user_id, success, attempted_at DESC)
    WHERE attempted_at > NOW() - INTERVAL '1 hour';
```

**User Roles — Tenant-Level Authorization** (`user_roles`):
```sql
-- Tenant-level roles assigned to users
-- ROLE_OWNER is special: can terminate the tenant
CREATE TABLE IF NOT EXISTS user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Role name — references administered ref_tenant_roles table
    -- ROLE_ prefix follows Spring Security convention
    role VARCHAR(50) NOT NULL
        REFERENCES ref_tenant_roles(code),

    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    assigned_by UUID, -- user who assigned this role (NULL for system-assigned)

    -- Each user has at most one entry per role
    CONSTRAINT uq_user_role UNIQUE (user_id, role)
);

CREATE INDEX idx_user_roles_user ON user_roles(user_id);
CREATE INDEX idx_user_roles_role ON user_roles(role);
```

**User Feature Entitlements** (`user_feature_entitlements`):
```sql
-- Per-user feature access within what the tenant allows
-- Resolves to Spring Security authorities: FEATURE_<key>_<level>
CREATE TABLE IF NOT EXISTS user_feature_entitlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Feature key matching tenant_product_features.feature_key
    feature_key VARCHAR(100) NOT NULL,

    -- Feature level (cannot exceed tenant's level)
    -- References public.ref_feature_levels via search_path
    feature_level VARCHAR(20) NOT NULL
        REFERENCES public.ref_feature_levels(code),

    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    granted_by UUID,

    CONSTRAINT uq_user_feature UNIQUE (user_id, feature_key),
    CONSTRAINT chk_feature_key_format CHECK (feature_key ~ '^[A-Z][A-Z0-9_]*$')
);

CREATE INDEX idx_user_features_user ON user_feature_entitlements(user_id);
```

**Group Types** (`group_types`):
```sql
-- Defines the types of groups that can be created
-- Each group type declares its own available membership roles as a JSONB array
-- Roles are linked to the group type: only roles defined here are valid for memberships
CREATE TABLE IF NOT EXISTS group_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(100) NOT NULL,
    slug VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,

    -- Available roles for this group type, stored as a JSONB array of role objects
    -- Each object: {"key": "OWNER", "label": "Owner", "description": "...", "display_order": 1}
    -- NULL or empty array means this group type does not support in-group roles
    -- The "key" field is what gets stored in group_memberships.role
    available_roles JSONB DEFAULT NULL,

    -- System-defined types cannot be deleted by users
    system_defined BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed default group types with role definitions
INSERT INTO group_types (id, name, slug, description, available_roles, system_defined)
VALUES
    (gen_random_uuid(), 'Collaboration', 'collaboration',
     'Groups for team collaboration with role-based access',
     '[
       {"key": "OWNER",  "label": "Owner",         "description": "Full control of the group",            "display_order": 1},
       {"key": "ADMIN",  "label": "Administrator",  "description": "Can manage members and settings",      "display_order": 2},
       {"key": "EDITOR", "label": "Editor",         "description": "Can edit group content",               "display_order": 3},
       {"key": "MEMBER", "label": "Member",         "description": "Standard group member with read access","display_order": 4}
     ]'::jsonb,
     TRUE),
    (gen_random_uuid(), 'Department', 'department',
     'Organizational department grouping',
     NULL,  -- no in-group roles
     TRUE),
    (gen_random_uuid(), 'Team', 'team',
     'Project or functional team grouping',
     '[
       {"key": "LEAD",   "label": "Team Lead",  "description": "Leads the team",        "display_order": 1},
       {"key": "MEMBER", "label": "Member",      "description": "Standard team member",  "display_order": 2}
     ]'::jsonb,
     TRUE)
ON CONFLICT (slug) DO NOTHING;
```

**Groups** (`groups`):
```sql
-- User-defined groups within a tenant
CREATE TABLE IF NOT EXISTS groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(255) NOT NULL,
    description TEXT,

    group_type_id UUID NOT NULL REFERENCES group_types(id) ON DELETE RESTRICT,

    -- Lifecycle — references administered ref_group_statuses table
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
        REFERENCES ref_group_statuses(code),

    created_by UUID NOT NULL REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_groups_type ON groups(group_type_id);
CREATE INDEX idx_groups_status ON groups(status) WHERE status = 'ACTIVE';
CREATE INDEX idx_groups_created_by ON groups(created_by);
```

**Group Memberships** (`group_memberships`):
```sql
-- Tracks which users belong to which groups, with their in-group role
-- The valid roles are defined by the group's type (group_types.available_roles JSONB)
-- Role validation is enforced at the application layer by checking the role key
-- against the group type's available_roles array
CREATE TABLE IF NOT EXISTS group_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- In-group role — must match a "key" value in the parent group's
    -- group_type.available_roles JSONB array
    -- NULL when the group type has no available_roles defined
    role VARCHAR(50),

    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    invited_by UUID REFERENCES users(id),

    -- Each user can only be in a group once
    CONSTRAINT uq_group_membership UNIQUE (group_id, user_id)
);

CREATE INDEX idx_group_memberships_group ON group_memberships(group_id);
CREATE INDEX idx_group_memberships_user ON group_memberships(user_id);
CREATE INDEX idx_group_memberships_role ON group_memberships(group_id, role)
    WHERE role IS NOT NULL;
```

**Security Alerts** (`security_alerts`):
```sql
-- Persisted security notifications for users
-- Consumed by notification service for email/push delivery
CREATE TABLE IF NOT EXISTS security_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Alert classification — references administered ref_alert_types table
    alert_type VARCHAR(50) NOT NULL
        REFERENCES ref_alert_types(code),

    -- Alert content
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,

    -- Context (device info, IP, location, etc.)
    context JSONB,

    -- Lifecycle
    acknowledged_at TIMESTAMPTZ, -- NULL = unread
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_security_alerts_user ON security_alerts(user_id, created_at DESC);
CREATE INDEX idx_security_alerts_unread ON security_alerts(user_id)
    WHERE acknowledged_at IS NULL;
```

**Migration Files:**
- `V001__create_reference_tables.sql` in `/src/main/resources/db/migration/tenant/` (ref_user_statuses, ref_tenant_roles, ref_group_statuses, ref_alert_types)
- `V002__create_users_and_credentials.sql` in `/src/main/resources/db/migration/tenant/`
- `V003__create_groups_and_memberships.sql` in `/src/main/resources/db/migration/tenant/`

---

## Domain Events

**Events Emitted** (via Outbox Pattern):

```java
public sealed interface UserEvent permits
    UserRegistered, UserOtpVerified, UserLoginSucceeded, UserLoginFailed,
    UserAccountLocked, UserPasswordChanged, UserDeviceRegistered,
    UserRoleAssigned, UserRoleRevoked {
    UUID eventId();
    String tenantId();
    UUID userId();
    Instant occurredAt();
}

public record UserRegistered(
    UUID eventId,
    String tenantId,
    UUID userId,
    String username,
    String email,
    String deviceFingerprint,
    String ipAddress,
    Instant occurredAt
) implements UserEvent {}

public record UserLoginFailed(
    UUID eventId,
    String tenantId,
    UUID userId,
    String username,
    String ipAddress,
    String deviceFingerprint,
    String failureReason,
    int failedAttemptCount,
    Instant occurredAt
) implements UserEvent {}

public record UserAccountLocked(
    UUID eventId,
    String tenantId,
    UUID userId,
    String username,
    int failedAttemptCount,
    Instant lockedUntil,
    String ipAddress,
    Instant occurredAt
) implements UserEvent {}

public record UserPasswordChanged(
    UUID eventId,
    String tenantId,
    UUID userId,
    String ipAddress,
    String deviceFingerprint,
    Instant occurredAt
) implements UserEvent {}

public record UserDeviceRegistered(
    UUID eventId,
    String tenantId,
    UUID userId,
    UUID deviceId,
    String deviceType,
    String browserName,
    String osName,
    String ipAddress,
    Instant occurredAt
) implements UserEvent {}

public record SecurityAlertCreated(
    UUID eventId,
    String tenantId,
    UUID userId,
    UUID alertId,
    String alertType,
    String title,
    String message,
    Instant occurredAt
) implements UserEvent {}

public sealed interface GroupEvent permits
    GroupCreated, GroupMemberAdded, GroupMemberRemoved, GroupMemberRoleChanged {
    UUID eventId();
    String tenantId();
    UUID groupId();
    Instant occurredAt();
}

public record GroupCreated(
    UUID eventId,
    String tenantId,
    UUID groupId,
    String name,
    String groupType,
    UUID createdBy,
    Instant occurredAt
) implements GroupEvent {}

public record GroupMemberAdded(
    UUID eventId,
    String tenantId,
    UUID groupId,
    UUID userId,
    String role,
    UUID addedBy,
    Instant occurredAt
) implements GroupEvent {}

public record GroupMemberRoleChanged(
    UUID eventId,
    String tenantId,
    UUID groupId,
    UUID userId,
    String previousRole,
    String newRole,
    UUID changedBy,
    Instant occurredAt
) implements GroupEvent {}
```

**Kafka Topics:**
- `ecap.events.User.Registered` — Registration events (12 partitions, 30-day retention)
- `ecap.events.User.OtpVerified` — OTP verification completions
- `ecap.events.User.LoginSucceeded` — Successful logins
- `ecap.events.User.LoginFailed` — Failed login attempts
- `ecap.events.User.AccountLocked` — Account lockout events
- `ecap.events.User.PasswordChanged` — Password change events (90-day retention)
- `ecap.events.User.DeviceRegistered` — New device fingerprints
- `ecap.events.User.RoleAssigned` — Role assignment events (30-day retention)
- `ecap.events.User.RoleRevoked` — Role revocation events
- `ecap.events.SecurityAlert.Created` — Security alert events
- `ecap.events.Group.Created` — Group creation events
- `ecap.events.Group.MemberAdded` — Member addition events
- `ecap.events.Group.MemberRemoved` — Member removal events
- `ecap.events.Group.MemberRoleChanged` — Role change within groups

**Partition key:** `tenant_id` for all topics (ordering within tenant)

**Events Consumed:**
- `ecap.events.SecurityAlert.Created` → `notification-service` consumer group (sends email/push)
- `ecap.events.User.AccountLocked` → `notification-service` consumer group (sends lockout email)

---

## API Endpoints

### Authentication

```http
POST /api/v1/auth/register
Host: {tenant-slug}.providence.ai
Idempotency-Key: {uuid}
Content-Type: application/json

{
  "username": "jane.doe",
  "email": "jane@example.com",
  "password": "SecureP@ssw0rd123",
  "firstName": "Jane",
  "lastName": "Doe",
  "displayName": "Jane Doe",
  "deviceFingerprint": "a1b2c3d4e5..."
}

Response: 201 Created
{
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "status": "PENDING_VERIFICATION",
  "message": "OTP sent to registered email. Please verify to activate your account."
}
```

```http
POST /api/v1/auth/verify-otp
Host: {tenant-slug}.providence.ai
Idempotency-Key: {uuid}
Content-Type: application/json

{
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "otpCode": "482910"
}

Response: 200 OK
{
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "status": "ACTIVE",
  "token": "<jwt-token>",
  "expiresAt": "2026-02-12T11:30:00Z"
}
```

```http
POST /api/v1/auth/login
Host: {tenant-slug}.providence.ai
Content-Type: application/json

{
  "username": "jane.doe",
  "password": "SecureP@ssw0rd123",
  "deviceFingerprint": "a1b2c3d4e5..."
}

Response: 200 OK
{
  "token": "<jwt-token>",
  "expiresAt": "2026-02-12T11:30:00Z",
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "roles": ["ROLE_USER"],
  "features": ["FEATURE_PROJECT_STANDARD", "FEATURE_FINANCE_PRO"]
}

Response: 423 Locked (after 3 failures)
{
  "type": "https://providence.ai/problems/account-locked",
  "title": "Account Locked",
  "status": 423,
  "detail": "Account locked due to 3 consecutive failed login attempts. Try again after the lockout period.",
  "instance": "/api/v1/auth/login",
  "retryAfter": "2026-02-12T10:45:00Z"
}
```

```http
POST /api/v1/auth/password/change
Host: {tenant-slug}.providence.ai
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}
Content-Type: application/json

{
  "currentPassword": "OldP@ssw0rd",
  "newPassword": "NewSecureP@ss123"
}

Response: 200 OK
{
  "message": "Password changed successfully.",
  "changedAt": "2026-02-12T10:30:00Z"
}
```

### User Management

```http
GET /api/v1/users/me
Authorization: Bearer <jwt>

Response: 200 OK
{
  "userId": "7c9e6679-...",
  "displayName": "Jane Doe",
  "firstName": "Jane",
  "lastName": "Doe",
  "email": "jane@example.com",
  "roles": ["ROLE_USER"],
  "features": ["FEATURE_PROJECT_STANDARD"],
  "status": "ACTIVE",
  "createdAt": "2026-02-12T08:00:00Z"
}
```

```http
PUT /api/v1/users/me
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}
Content-Type: application/json

{
  "firstName": "Jane",
  "lastName": "Smith",
  "displayName": "Jane Smith",
  "phone": "+1-555-0100",
  "timezone": "America/New_York"
}
```

```http
GET /api/v1/users (Admin only)
Authorization: Bearer <jwt>
X-Tenant-ID: acme

Query params: ?page=0&size=20&status=ACTIVE&role=ROLE_USER

Response: 200 OK
{
  "content": [...],
  "page": { "number": 0, "size": 20, "totalElements": 150, "totalPages": 8 }
}
```

```http
PUT /api/v1/users/{userId}/roles (Admin only)
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}

{ "roles": ["ROLE_USER", "ROLE_ADMIN"] }
```

### Devices

```http
GET /api/v1/users/me/devices
Authorization: Bearer <jwt>

Response: 200 OK
[
  {
    "deviceId": "d1a2b3c4-...",
    "deviceName": "Chrome on macOS",
    "deviceType": "DESKTOP",
    "browserName": "Chrome",
    "browserVersion": "120.0.6099",
    "osName": "macOS",
    "osVersion": "14.2",
    "ipAddress": "192.168.1.100",
    "trusted": false,
    "firstSeenAt": "2026-02-10T14:00:00Z",
    "lastSeenAt": "2026-02-12T09:30:00Z"
  }
]
```

```http
DELETE /api/v1/users/me/devices/{deviceId}
Authorization: Bearer <jwt>
Idempotency-Key: {uuid}

Response: 204 No Content
```

### Security Alerts

```http
GET /api/v1/users/me/alerts
Authorization: Bearer <jwt>

Query params: ?unreadOnly=true&page=0&size=20

Response: 200 OK
{
  "content": [
    {
      "alertId": "a1b2c3d4-...",
      "alertType": "BRUTE_FORCE_DETECTED",
      "title": "Suspicious Login Activity",
      "message": "3 failed login attempts detected from IP 203.0.113.42 using Chrome on Windows.",
      "context": {
        "ipAddress": "203.0.113.42",
        "deviceType": "DESKTOP",
        "browserName": "Chrome"
      },
      "acknowledgedAt": null,
      "createdAt": "2026-02-12T10:15:00Z"
    }
  ]
}
```

```http
PUT /api/v1/users/me/alerts/{alertId}/acknowledge
Authorization: Bearer <jwt>

Response: 200 OK
{ "alertId": "a1b2c3d4-...", "acknowledgedAt": "2026-02-12T10:30:00Z" }
```

### Groups

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

### gRPC

```protobuf
service AuthService {
    rpc Register(RegisterRequest) returns (RegisterResponse);
    rpc VerifyOtp(VerifyOtpRequest) returns (VerifyOtpResponse);
    rpc Login(LoginRequest) returns (LoginResponse);
    rpc ChangePassword(ChangePasswordRequest) returns (ChangePasswordResponse);
}

service UserService {
    rpc GetUser(GetUserRequest) returns (UserResponse);
    rpc UpdateProfile(UpdateProfileRequest) returns (UserResponse);
    rpc ListUsers(ListUsersRequest) returns (ListUsersResponse);
    rpc AssignRoles(AssignRolesRequest) returns (UserResponse);
}

service GroupService {
    rpc CreateGroup(CreateGroupRequest) returns (GroupResponse);
    rpc AddMember(AddMemberRequest) returns (MembershipResponse);
    rpc RemoveMember(RemoveMemberRequest) returns (google.protobuf.Empty);
    rpc ChangeMemberRole(ChangeMemberRoleRequest) returns (MembershipResponse);
}
```

---

## Implementation Checklist

### Domain Layer (`com.providence.identity.domain`)
- [ ] `User.java` — Aggregate root entity with status lifecycle
- [ ] `UserId.java` — Value object (record)
- [ ] `Credential.java` — Entity: username, password hash, OTP, lockout state
- [ ] `UserProfile.java` — Entity: personal info separated from credentials
- [ ] `UserDevice.java` — Entity: device fingerprint, browser, OS details
- [ ] `LoginAttempt.java` — Entity: login attempt record
- [ ] `SecurityAlert.java` — Entity: security notification
- [ ] `UserRole.java` — Value object: `ROLE_ADMIN`, `ROLE_USER`, `ROLE_OWNER`
- [ ] `FeatureEntitlement.java` — Value object: feature key + level
- [ ] `Group.java` — Aggregate root for groups
- [ ] `GroupId.java` — Value object (record)
- [ ] `GroupType.java` — Entity: group type definition
- [ ] `GroupMembership.java` — Entity: user-group with role
- [ ] `GroupRoleDefinition.java` — Value object (record): deserialized from `group_types.available_roles` JSONB (`key`, `label`, `description`, `displayOrder`)
- [ ] `DeviceFingerprint.java` — Value object: fingerprint hash + device details
- [ ] Domain events (sealed interface hierarchy — `UserEvent`, `GroupEvent`)
- [ ] Business rules: 3-attempt lockout, OTP verification gate, credential separation invariant, group role validation against type's available_roles

### Application Layer (`com.providence.identity.service`)
- [ ] `AuthenticationService.java` — Registration, OTP, login, password change with `@Transactional`
- [ ] `UserService.java` — Profile CRUD, role assignment with `@Transactional`
- [ ] `DeviceService.java` — Device fingerprinting, registration, revocation
- [ ] `SecurityAlertService.java` — Alert creation, retrieval, acknowledgment
- [ ] `GroupService.java` — Group CRUD, membership management with `@Transactional`
- [ ] `LoginThrottleService.java` — Failed attempt tracking, lockout/unlock logic
- [ ] Command objects: `RegisterCommand`, `LoginCommand`, `ChangePasswordCommand`, `CreateGroupCommand`, etc.
- [ ] DTOs: request/response records for all endpoints

### Infrastructure Layer (`com.providence.identity.repository`)
- [ ] `UserRepository.java` — `JpaRepository<User, UUID>`
- [ ] `CredentialRepository.java` — `JpaRepository<Credential, UUID>` + `findByUsername`
- [ ] `UserProfileRepository.java` — `JpaRepository<UserProfile, UUID>`
- [ ] `UserDeviceRepository.java` — `JpaRepository<UserDevice, UUID>` + `findByUserIdAndFingerprintHash`
- [ ] `LoginAttemptRepository.java` — `JpaRepository<LoginAttempt, UUID>` + recent failures query
- [ ] `SecurityAlertRepository.java` — `JpaRepository<SecurityAlert, UUID>` + unread query
- [ ] `UserRoleRepository.java` — `JpaRepository<UserRole, UUID>`
- [ ] `UserFeatureEntitlementRepository.java`
- [ ] `GroupRepository.java` — `JpaRepository<Group, UUID>`
- [ ] `GroupTypeRepository.java` — `JpaRepository<GroupType, UUID>` + `findBySlug`
- [ ] `GroupMembershipRepository.java` — `JpaRepository<GroupMembership, UUID>`
- [ ] Reference table repositories: `RefUserStatusRepository`, `RefTenantRoleRepository`, `RefGroupStatusRepository`, `RefAlertTypeRepository`
- [ ] Outbox repository integration for all domain events
- [ ] Audit logging integration for all state changes

### Adapter Layer (`com.providence.identity.adapter`)
- [ ] `AuthController.java` — REST: `/api/v1/auth/*` endpoints
- [ ] `UserController.java` — REST: `/api/v1/users/*` endpoints
- [ ] `DeviceController.java` — REST: `/api/v1/users/me/devices/*` endpoints
- [ ] `SecurityAlertController.java` — REST: `/api/v1/users/me/alerts/*` endpoints
- [ ] `GroupController.java` — REST: `/api/v1/groups/*` endpoints
- [ ] `AuthGrpcService.java` — gRPC service for auth operations
- [ ] `UserGrpcService.java` — gRPC service for user operations
- [ ] `GroupGrpcService.java` — gRPC service for group operations
- [ ] `SecurityAlertEventConsumer.java` — Kafka consumer for alert → notification dispatch

### Cross-Cutting Concerns
- [ ] Multi-tenancy: Tenant context propagation via `ScopedValue` — subdomain resolves to `tenant_id`
- [ ] Idempotency: `Idempotency-Key` header on all state-changing endpoints
- [ ] Outbox pattern: All domain events written in same transaction as mutation
- [ ] Inbox pattern: `SecurityAlertEventConsumer` deduplicates via inbox table
- [ ] Audit logging: `USER_REGISTERED`, `USER_LOGIN_FAILED`, `USER_ACCOUNT_LOCKED`, `USER_PASSWORD_CHANGED`, `USER_ROLE_ASSIGNED`, `GROUP_CREATED`, `GROUP_MEMBER_ADDED`, `GROUP_MEMBER_ROLE_CHANGED`
- [ ] Structured logging: MDC includes `tenantId`, `correlationId`, `userId`
- [ ] Metrics: `auth.register.count`, `auth.login.count`, `auth.login.failed`, `auth.account.locked`, `auth.otp.verified`, `group.created`, `group.member.added` — all tagged with `tenant_id`
- [ ] Spring Security: JWT filter extracts tenant + roles + features into `SecurityContext`

---

## Testing Requirements

### Unit Tests (No Spring Context)
```java
@ExtendWith(MockitoExtension.class)
class AuthenticationServiceTest {
    @Mock private CredentialRepository credentialRepo;
    @Mock private UserRepository userRepo;
    @Mock private LoginAttemptRepository loginAttemptRepo;
    @Mock private OutboxRepository outboxRepo;
    @InjectMocks private AuthenticationService authService;

    // Target: 80%+ line coverage
}
```

**Test Cases:**
- [ ] Registration: valid input → creates user (PENDING_VERIFICATION), credential, profile, outbox event
- [ ] Registration: duplicate username → 409 Conflict
- [ ] OTP verification: valid OTP → user status becomes ACTIVE
- [ ] OTP verification: invalid OTP → 401 Unauthorized, status unchanged
- [ ] Login: valid credentials + verified account → JWT returned, attempt logged as success
- [ ] Login: invalid password → attempt logged, failed count incremented
- [ ] Login: 3rd failed attempt → account locked, `UserAccountLockedEvent` emitted, security alert created
- [ ] Login: locked account → 423 Locked with Retry-After
- [ ] Login: after lockout expires → counter resets, login succeeds
- [ ] Password change → `UserPasswordChangedEvent` emitted, security alert created
- [ ] Device fingerprint: new device → `UserDeviceRegistered` event
- [ ] Device fingerprint: known device → `last_seen_at` updated, no event
- [ ] Group creation: valid input → group created, creator added as OWNER
- [ ] Group member role change: collaboration type → role updated (role key validated against available_roles JSONB)
- [ ] Group member role change: type with no available_roles → role change rejected (400 Bad Request)
- [ ] Group member role change: invalid role key not in available_roles → rejected (400 Bad Request)
- [ ] Credential separation: profile query never returns password hash

### Integration Tests (Testcontainers)
```java
@SpringBootTest
@Testcontainers
class IdentityIntegrationTest {
    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:17");

    @Container
    static KafkaContainer kafka = new KafkaContainer(
        DockerImageName.parse("confluentinc/cp-kafka:7.5.0"));

    // Target: 100% endpoint coverage
}
```

**Test Scenarios:**
- [ ] **Happy Path:** Register → OTP verify → Login → JWT with correct claims
- [ ] **Idempotency:** Duplicate `Idempotency-Key` on register → same response (200 OK, not duplicate user)
- [ ] **Cross-Tenant Isolation:** User from tenant A cannot login on tenant B's subdomain → 401
- [ ] **Brute Force:** 3 failed logins → account locked → security alert created → alert retrievable via API
- [ ] **Device Tracking:** Login from new device → `user_devices` record created → event on Kafka
- [ ] **Inbox Deduplication:** Replay `SecurityAlertCreated` Kafka event → notification consumer skips duplicate
- [ ] **Validation:** Missing required fields → 400 Bad Request with ProblemDetail
- [ ] **Authorization:** Non-admin user calls `PUT /api/v1/users/{id}/roles` → 403 Forbidden
- [ ] **ROLE_OWNER:** User with ROLE_OWNER can trigger tenant termination; ROLE_ADMIN cannot
- [ ] **Group Roles:** Add member to collaboration group with role → verify role in membership
- [ ] **Security Hierarchy:** JWT includes tenant features + user roles + group roles → `@PreAuthorize` works
- [ ] **Credential Separation:** `GET /api/v1/users/me` response does NOT contain password hash, OTP secret, or any credential data
- [ ] **Audit Logging:** Registration, login failure, password change, role assignment → all create audit log entries
- [ ] **System Tenant:** Default "System" tenant with slug `system` exists on startup

---

## Security & Authorization

**Authentication:**
- OTP for registration verification (email-delivered one-time password)
- JWT (RS256 asymmetric) for session tokens
- Token claims: `sub` (user ID), `tenant_id`, `roles[]`, `features[]`, `exp`
- Subdomain routing: `{slug}.providence.ai` → resolves tenant context

**Authorization:**
- [ ] `@PreAuthorize("hasRole('ROLE_ADMIN')")` — User management, role assignment
- [ ] `@PreAuthorize("hasRole('ROLE_OWNER')")` — Tenant termination
- [ ] `@PreAuthorize("hasRole('ROLE_USER')")` — Self-service profile, devices, alerts
- [ ] `@PreAuthorize("hasAuthority('FEATURE_PROJECT_STANDARD')")` — Feature-gated operations
- [ ] Group-level authorization: verify user has `GROUP_ADMIN` or `GROUP_OWNER` role for group-management operations
- [ ] Tenant isolation: all user data scoped to `t_<slug>` schema; cross-tenant access returns 403

**Spring Security Authority Resolution:**
```
GrantedAuthorities for a user session:
├── Tenant Roles:     ROLE_ADMIN, ROLE_USER, ROLE_OWNER
├── Tenant Features:  FEATURE_PROJECT_STANDARD, FEATURE_FINANCE_PRO, ...
├── User Features:    FEATURE_RESOURCE_MAX (per-user override)
└── Group Roles:      GROUP_{groupId}_ADMIN, GROUP_{groupId}_MEMBER
```

**Brute-Force Protection:**
- 3 consecutive failed attempts → lock account
- Lockout duration: configurable (default 15 minutes)
- Reset failed count on successful login
- Log all attempts with IP, user agent, device fingerprint
- Security alert created on lockout

---

## Observability

**Logging:**
```java
MDC.put("tenantId", tenantId);
MDC.put("correlationId", correlationId);
MDC.put("userId", userId);

log.info("User registered: userId={}, username={}", userId, username);
log.warn("Login failed: userId={}, attempt={}/3, ip={}", userId, count, ip);
log.warn("Account locked: userId={}, lockedUntil={}, ip={}", userId, lockedUntil, ip);
log.info("Password changed: userId={}", userId);
log.info("New device registered: userId={}, deviceType={}, browser={}", userId, type, browser);
log.info("Group created: groupId={}, name={}, type={}", groupId, name, type);
```

**Metrics:**
```java
meterRegistry.counter("auth.register", "tenant", tenantId).increment();
meterRegistry.counter("auth.otp.verified", "tenant", tenantId).increment();
meterRegistry.counter("auth.login.success", "tenant", tenantId).increment();
meterRegistry.counter("auth.login.failed", "tenant", tenantId).increment();
meterRegistry.counter("auth.account.locked", "tenant", tenantId).increment();
meterRegistry.counter("auth.password.changed", "tenant", tenantId).increment();
meterRegistry.counter("device.registered", "tenant", tenantId).increment();
meterRegistry.counter("security.alert.created", "tenant", tenantId, "type", alertType).increment();
meterRegistry.counter("group.created", "tenant", tenantId).increment();
meterRegistry.counter("group.member.added", "tenant", tenantId).increment();
meterRegistry.timer("auth.login.duration", "tenant", tenantId).record(duration);
meterRegistry.timer("auth.register.duration", "tenant", tenantId).record(duration);
```

**Tracing:**
- Automatic OpenTelemetry instrumentation for HTTP, gRPC, JDBC, Kafka
- Span attributes: `tenant.id`, `user.id`, `http.method`, `auth.event_type`

**Alerts:**
- Account lockout rate > 10/minute per tenant → PagerDuty alert
- Registration failure rate > 50% → Investigation trigger
- OTP verification timeout rate > 20% → UX review

---

## Production Readiness

- [ ] **Multi-Tenancy:** `ScopedValue` for tenant context, subdomain → slug resolution
- [ ] **Data Isolation:** All user data in tenant schema (`t_<slug>`), cross-tenant access returns 403
- [ ] **Outbox Pattern:** All domain events (register, login, lock, password, device, group) in same transaction
- [ ] **Inbox Pattern:** Notification consumer deduplicates via inbox table
- [ ] **Idempotency:** All state-changing endpoints require `Idempotency-Key`
- [ ] **Audit Logging:** Registration, login failures, password changes, role changes, group mutations → `public.audit_log`
- [ ] **Circuit Breakers:** Applied to OTP email delivery service
- [ ] **gRPC Deadlines:** Set on all auth/user/group client calls (5s timeout)
- [ ] **Graceful Degradation:** If OTP email service is down, queue OTP for retry; return 202 Accepted
- [ ] **Password Hashing:** bcrypt or Argon2id with secure work factor
- [ ] **Credential Isolation:** `credentials` table never joined with `user_profiles` in read queries exposed to clients
- [ ] **Rate Limiting:** OTP resend (3 per 10 min), login (configurable per tier), registration (per IP)
- [ ] **System Tenant:** "System" tenant (slug: `system`) auto-provisioned on startup
- [ ] **Documentation:** API docs and architecture diagrams updated

</details>

---

<details>
<summary><strong>Reference Documentation</strong></summary>

## Related Documentation

- **Master Standards:** [docs/architecture/ENGINEERING_STANDARDS.md](../../architecture/ENGINEERING_STANDARDS.md)
- **Complete Example:** [docs/examples/PROJECT_MANAGEMENT.md](../../examples/PROJECT_MANAGEMENT.md)
- **Multi-Tenancy:** [docs/architecture/MULTI_TENANT_DESIGN.md](../../architecture/MULTI_TENANT_DESIGN.md)
- **Event Streaming:** [docs/architecture/EVENT_STREAMING.md](../../architecture/EVENT_STREAMING.md)
- **Database Schema:** [docs/architecture/DATABASE_SCHEMA.md](../../architecture/DATABASE_SCHEMA.md)

## Implementation Pattern

Study `PROJECT_MANAGEMENT.md` as the canonical example. Copy its structure for:
- Package organization (`domain/`, `service/`, `repository/`, `adapter/`)
- Outbox pattern implementation
- Inbox pattern implementation
- Idempotency handling
- Multi-tenant context propagation
- Test structure (unit + integration)

</details>

---

## Notes

### Epic Decomposition

This story is comprehensive and may be decomposed into sub-stories during sprint planning:

| Sub-Story | Scope | Priority |
|-----------|-------|----------|
| PROV-101 | User registration with OTP workflow | P0 |
| PROV-102 | Login with brute-force throttling (3-attempt lockout) | P0 |
| PROV-103 | Device fingerprinting and tracking | P0 |
| PROV-104 | Security alerts (failed login, password change) | P1 |
| PROV-105 | User roles and tenant-level RBAC | P0 |
| PROV-106 | Spring Security hierarchy (tenant features + user features) | P0 |
| PROV-107 | Groups, group types, and group memberships | P1 |
| PROV-108 | Default "System" tenant provisioning | P0 |
| PROV-109 | Credential/profile separation enforcement | P0 |

### Key Architectural Decisions

1. **Credential separation:** `credentials` and `user_profiles` are physically separate tables joined only by `user_id`. API responses for profile endpoints NEVER include credential fields. This prevents accidental leakage through serialization, logging, or caching.

2. **Tenant product features in public schema:** `public.tenant_product_features` lives in the public schema because it describes what the tenant subscription includes — this is cross-tenant infrastructure akin to the `tenants` table itself. Per-user feature entitlements live in the tenant schema.

3. **Group types define available roles as JSONB:** `group_types.available_roles` is a JSONB array of role objects (`{"key", "label", "description", "display_order"}`). Each group type declares exactly which roles are valid for its memberships. The `collaboration` type defines `OWNER`, `ADMIN`, `EDITOR`, `MEMBER`; `team` defines `LEAD`, `MEMBER`; `department` has `NULL` (no roles). This links roles directly to the group type, makes them extensible without schema changes, and prevents role confusion across group types. Validation is enforced at the application layer by checking membership role against the type's available_roles keys.

4. **Administered reference tables instead of CHECK constraints:** All enum-like columns (user statuses, tenant roles, feature levels, group statuses, alert types) use reference tables (`ref_*`) with FK constraints instead of `CHECK (x IN (...))`. This allows administrators to add, deactivate, or relabel values without DDL changes. Each reference table follows a standard structure: `code` (PK), `label`, `description`, `display_order`, `active`, `created_at`. Public-schema reference tables (`ref_feature_levels`) are shared across tenants; tenant-schema reference tables are per-tenant.

5. **Login attempts vs. audit log:** `login_attempts` is a tenant-schema table optimized for throttling queries (recent failures per user). The `public.audit_log` also records login events but serves a different purpose (compliance, forensics). Both are written.

6. **Device fingerprint as unique constraint:** `(user_id, fingerprint_hash)` ensures the same device is not duplicated. If the fingerprint matches, we update `last_seen_at` and `ip_address` rather than creating a new record.

7. **Spring Security authority format:** `FEATURE_<KEY>_<LEVEL>` enables hierarchical feature gating. A `@PreAuthorize("hasAuthority('FEATURE_PROJECT_STANDARD')")` check will pass for users with STANDARD, PRO, MAX, or ENTERPRISE access when a custom `FeatureHierarchyVoter` is implemented.

---

**Status Legend:**
- **Draft** — Story is being written, not ready for implementation
- **Ready** — Story is complete and ready to be picked up
- **In Progress** — Implementation has started
- **Done** — Implementation complete, tests passing, deployed

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
