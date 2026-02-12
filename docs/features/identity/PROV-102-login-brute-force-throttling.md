# Login with Brute-Force Throttling - User Story

> **Story ID:** PROV-102
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P0

---

## User Story

**As a** registered user with a verified account
**I want to** login with my username and password, with the system protecting my account by locking it after 3 consecutive failed attempts
**So that** I can securely access the platform while being protected from brute-force attacks

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] User can login with username/email and password against the tenant subdomain
- [ ] Successful login returns a JWT with claims: `sub` (user ID), `tenant_id`, `roles`, `features`, `exp`
- [ ] System tracks all login attempts (success and failure) in `login_attempts` table with IP, device fingerprint, and user agent
- [ ] After 3 consecutive failed login attempts, the account is locked for a configurable cooldown period (default 15 minutes)
- [ ] `UserLoginSucceededEvent` published on successful login via outbox
- [ ] `UserLoginFailedEvent` published on failed login via outbox
- [ ] `UserAccountLockedEvent` published when account is locked after 3rd failure
- [ ] Locked accounts return `423 Locked` with RFC 9457 ProblemDetail including `Retry-After` header
- [ ] Successful login resets the failed attempt counter to zero
- [ ] Login on expired lockout resets the counter and allows authentication
- [ ] Unverified accounts (status `PENDING_VERIFICATION`) cannot login — returns `403 Forbidden`
- [ ] Audit log entries: `USER_LOGIN_SUCCEEDED`, `USER_LOGIN_FAILED`, `USER_ACCOUNT_LOCKED`
- [ ] Password change endpoint requires `Idempotency-Key` and authenticated JWT
- [ ] `UserPasswordChangedEvent` published on password change via outbox

**Should Have (Nice to Have):**
- [ ] Configurable lockout threshold per subscription tier
- [ ] Progressive lockout (longer cooldowns on repeated lockouts)

**Won't Have (Out of Scope):**
- Registration / OTP (see PROV-101)
- Device fingerprinting storage (see PROV-103, but fingerprint is logged in login_attempts)
- Security alerts on lockout (see PROV-104)
- Session management / concurrent session limits (future story)

---

## Business Context

### Problem Statement
Brute-force attacks are one of the most common threats to user accounts. The platform must balance security (locking accounts after repeated failures) with usability (reasonable cooldown periods, clear error messages). All login activity must be tracked for forensic analysis.

### Target Users
- **Primary:** Registered users authenticating against tenant subdomains
- **Secondary:** Security teams reviewing login attempt logs

### Success Metrics
- Account lockout triggers within 500ms of 3rd failed attempt
- Login API response time < 200ms p99
- Zero false-positive lockouts (only consecutive failures trigger lock)

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| User registration | PROV-101 | Prerequisite | Users must exist to login |
| Credential separation | PROV-109 | Prerequisite | Credential table must exist |
| Security alerts | PROV-104 | Downstream | Lockout triggers security alert (handled in PROV-104) |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

**Tenant Schema Tables:**

`credentials` — lockout fields (`failed_attempt_count`, `locked_until`, `last_failed_at`) — see PROV-100 for full DDL.

`login_attempts` — see [PROV-100](PROV-100-user-identity-access-management.md) Database Schema section.

---

## Domain Events

**Events Emitted:**
- `UserLoginSucceeded` → `ecap.events.User.LoginSucceeded`
- `UserLoginFailed` → `ecap.events.User.LoginFailed`
- `UserAccountLocked` → `ecap.events.User.AccountLocked`
- `UserPasswordChanged` → `ecap.events.User.PasswordChanged` (90-day retention)

**Partition key:** `tenant_id`

---

## API Endpoints

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

**gRPC:**
```protobuf
service AuthService {
    rpc Login(LoginRequest) returns (LoginResponse);
    rpc ChangePassword(ChangePasswordRequest) returns (ChangePasswordResponse);
}
```

---

## Implementation Checklist

### Domain Layer
- [ ] `LoginAttempt.java` — Entity: login attempt record
- [ ] `UserLoginSucceeded.java`, `UserLoginFailed.java`, `UserAccountLocked.java`, `UserPasswordChanged.java` — Domain event records
- [ ] Business rules: 3-attempt lockout, cooldown expiry check, failed count reset on success

### Application Layer
- [ ] `AuthenticationService.login()` — Validates credentials, tracks attempts, emits events in `@Transactional`
- [ ] `AuthenticationService.changePassword()` — Validates current password, updates hash, emits event
- [ ] `LoginThrottleService.java` — Failed attempt tracking, lockout/unlock logic
- [ ] `LoginCommand.java`, `ChangePasswordCommand.java` — Immutable command records

### Infrastructure Layer
- [ ] `LoginAttemptRepository.java` — `JpaRepository<LoginAttempt, UUID>` + recent failures query
- [ ] Outbox integration for login events
- [ ] Audit logging: `USER_LOGIN_SUCCEEDED`, `USER_LOGIN_FAILED`, `USER_ACCOUNT_LOCKED`, `USER_PASSWORD_CHANGED`

### Adapter Layer
- [ ] `AuthController.java` — REST: `POST /api/v1/auth/login`, `POST /api/v1/auth/password/change`
- [ ] `AuthGrpcService.java` — gRPC: `Login`, `ChangePassword`

---

## Testing Requirements

**Unit Tests:**
- [ ] Login: valid credentials + verified account → JWT returned, attempt logged as success
- [ ] Login: invalid password → attempt logged, `failed_attempt_count` incremented
- [ ] Login: 3rd failed attempt → account locked, `UserAccountLockedEvent` emitted
- [ ] Login: locked account → 423 Locked with Retry-After
- [ ] Login: after lockout expires → counter resets, login succeeds
- [ ] Login: unverified account → 403 Forbidden
- [ ] Password change: valid current password → hash updated, event emitted
- [ ] Password change: wrong current password → 401 Unauthorized

**Integration Tests:**
- [ ] **Happy Path:** Login → JWT returned → attempt recorded in `login_attempts`
- [ ] **Brute Force:** 3 failed logins → 423 Locked → wait for cooldown → login succeeds
- [ ] **Cross-Tenant Isolation:** User from tenant A cannot login on tenant B → 401
- [ ] **Audit Logging:** Login success/failure → audit_log entries created

---

## Observability

**Logging:**
```java
log.info("Login succeeded: userId={}, ip={}", userId, ip);
log.warn("Login failed: userId={}, attempt={}/3, ip={}", userId, count, ip);
log.warn("Account locked: userId={}, lockedUntil={}, ip={}", userId, lockedUntil, ip);
log.info("Password changed: userId={}", userId);
```

**Metrics:**
```java
meterRegistry.counter("auth.login.success", "tenant", tenantId).increment();
meterRegistry.counter("auth.login.failed", "tenant", tenantId).increment();
meterRegistry.counter("auth.account.locked", "tenant", tenantId).increment();
meterRegistry.counter("auth.password.changed", "tenant", tenantId).increment();
meterRegistry.timer("auth.login.duration", "tenant", tenantId).record(duration);
```

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
