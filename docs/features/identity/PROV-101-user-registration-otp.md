# User Registration with OTP Workflow - User Story

> **Story ID:** PROV-101
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P0

---

## User Story

**As a** new user visiting a tenant's subdomain (e.g., `acme.providence.ai`)
**I want to** register an account with my email and password, then verify ownership via a one-time password sent to my email
**So that** my identity is verified before I can access the platform, preventing unauthorized account creation

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] User can register against a tenant subdomain (e.g., `acme.providence.ai`) which resolves to the tenant slug
- [ ] Registration initiates an OTP workflow — system sends a one-time password to the user's email
- [ ] User must verify OTP to complete registration; unverified accounts cannot login
- [ ] Registration creates separate `credentials` and `user_profiles` records (see PROV-109)
- [ ] User status is `PENDING_VERIFICATION` after registration, becomes `ACTIVE` after OTP verification
- [ ] `UserRegisteredEvent` published to `ecap.events.User.Registered` via outbox pattern
- [ ] `UserOtpVerifiedEvent` published to `ecap.events.User.OtpVerified` on successful verification
- [ ] Audit log entries created with `event_type=USER_REGISTERED` and `event_type=USER_OTP_VERIFIED`
- [ ] Registration endpoint requires `Idempotency-Key` header — duplicate keys return cached response
- [ ] OTP verification endpoint requires `Idempotency-Key` header
- [ ] Input validation: username (required, unique), email (valid format), password (required), displayName (required)
- [ ] Duplicate username returns `409 Conflict` with RFC 9457 ProblemDetail
- [ ] Invalid/expired OTP returns `401 Unauthorized`

**Should Have (Nice to Have):**
- [ ] OTP resend with rate limiting (max 3 resends per 10-minute window)
- [ ] Password strength validation (min 12 chars, uppercase, lowercase, digit, special)
- [ ] OTP expiry (configurable, default 10 minutes)

**Won't Have (Out of Scope):**
- Login flow (see PROV-102)
- Device fingerprinting on registration (see PROV-103)
- Social login / OAuth2 (future story)
- Account recovery (future story)

---

## Business Context

### Problem Statement
Users need a secure way to create accounts within their organization's tenant boundary. Email verification via OTP prevents unauthorized registrations and ensures the user controls the email address associated with the account.

### Target Users
- **Primary:** New users registering for the first time on a tenant subdomain
- **Secondary:** Tenant administrators monitoring registration activity

### Success Metrics
- Registration-to-verified conversion rate > 90% (OTP completion)
- Registration API response time < 200ms p99
- OTP delivery time < 5 seconds from registration

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| Credential/profile separation | PROV-109 | Co-dependent | Tables created together; separation invariant enforced |
| System tenant | PROV-108 | Prerequisite | Default tenant must exist for integration testing |
| Reference tables | PROV-100 | Shared | `ref_user_statuses` seeded in tenant migration V001 |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

**Tenant Schema Tables** (created in this story):

`users`, `credentials`, `user_profiles` — see [PROV-100](PROV-100-user-identity-access-management.md) Database Schema section for full DDL.

**Key tables:**
- `users` — Aggregate root with `status` FK to `ref_user_statuses`
- `credentials` — Username, password hash, OTP secret, verification timestamp
- `user_profiles` — First name, last name, display name, email, phone, preferences

**Migration:** `V002__create_users_and_credentials.sql` in `/src/main/resources/db/migration/tenant/`

---

## Domain Events

**Events Emitted:**
- `UserRegistered` → `ecap.events.User.Registered` (12 partitions, 30-day retention)
- `UserOtpVerified` → `ecap.events.User.OtpVerified`

**Partition key:** `tenant_id`

---

## API Endpoints

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
  "displayName": "Jane Doe"
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

**gRPC:**
```protobuf
service AuthService {
    rpc Register(RegisterRequest) returns (RegisterResponse);
    rpc VerifyOtp(VerifyOtpRequest) returns (VerifyOtpResponse);
}
```

---

## Implementation Checklist

### Domain Layer (`com.providence.identity.domain`)
- [ ] `User.java` — Aggregate root with status lifecycle (`PENDING_VERIFICATION` → `ACTIVE`)
- [ ] `UserId.java` — Value object (record)
- [ ] `Credential.java` — Entity: username, password hash, OTP secret, otp_verified_at
- [ ] `UserProfile.java` — Entity: personal info separated from credentials
- [ ] `UserRegistered.java` — Domain event record
- [ ] `UserOtpVerified.java` — Domain event record
- [ ] Business rules: OTP verification gate, username uniqueness

### Application Layer (`com.providence.identity.service`)
- [ ] `AuthenticationService.register()` — Creates user + credential + profile + outbox event in single `@Transactional`
- [ ] `AuthenticationService.verifyOtp()` — Validates OTP, transitions status, emits event
- [ ] `RegisterCommand.java` — Immutable command record
- [ ] `VerifyOtpCommand.java` — Immutable command record
- [ ] DTOs: `RegisterRequest`, `RegisterResponse`, `VerifyOtpRequest`, `VerifyOtpResponse`

### Infrastructure Layer
- [ ] `UserRepository.java` — `JpaRepository<User, UUID>`
- [ ] `CredentialRepository.java` — `JpaRepository<Credential, UUID>` + `findByUsername`
- [ ] `UserProfileRepository.java` — `JpaRepository<UserProfile, UUID>`
- [ ] Outbox repository integration for `UserRegistered`, `UserOtpVerified`
- [ ] Audit logging: `USER_REGISTERED`, `USER_OTP_VERIFIED`

### Adapter Layer
- [ ] `AuthController.java` — REST: `POST /api/v1/auth/register`, `POST /api/v1/auth/verify-otp`
- [ ] `AuthGrpcService.java` — gRPC: `Register`, `VerifyOtp`

---

## Testing Requirements

**Unit Tests:**
- [ ] Registration: valid input → creates user (PENDING_VERIFICATION), credential, profile, outbox event
- [ ] Registration: duplicate username → 409 Conflict
- [ ] Registration: missing required fields → validation error
- [ ] OTP verification: valid OTP → user status becomes ACTIVE, JWT returned
- [ ] OTP verification: invalid OTP → 401 Unauthorized, status unchanged
- [ ] OTP verification: already verified user → idempotent success
- [ ] Idempotency: duplicate key on register → returns cached response

**Integration Tests:**
- [ ] **Happy Path:** Register → OTP verify → user ACTIVE in database → events on Kafka
- [ ] **Idempotency:** Duplicate `Idempotency-Key` → same response, no duplicate user
- [ ] **Cross-Tenant Isolation:** Register on tenant A → user not visible on tenant B
- [ ] **Validation:** Missing fields → 400 ProblemDetail
- [ ] **Audit Logging:** Registration → audit_log entry created

---

## Observability

**Logging:**
```java
log.info("User registered: userId={}, username={}", userId, username);
log.info("OTP verified: userId={}", userId);
log.warn("OTP verification failed: userId={}, reason={}", userId, reason);
```

**Metrics:**
```java
meterRegistry.counter("auth.register", "tenant", tenantId).increment();
meterRegistry.counter("auth.otp.verified", "tenant", tenantId).increment();
meterRegistry.timer("auth.register.duration", "tenant", tenantId).record(duration);
```

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
