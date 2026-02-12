# Credential/Profile Separation Enforcement - User Story

> **Story ID:** PROV-109
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P0

---

## User Story

**As a** platform security architect
**I want to** enforce physical separation between credential data (passwords, OTP secrets, lockout state) and user profile data (name, email, preferences)
**So that** credential data can never be accidentally leaked through API responses, logging, caching, or serialization

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] `credentials` table and `user_profiles` table are physically separate, joined only by `user_id` FK to `users`
- [ ] `credentials` contains ONLY: email (login identifier), password_hash, otp_secret, otp_verified_at, failed_attempt_count, locked_until, last_failed_at, password_changed_at
- [ ] `user_profiles` contains ONLY: first_name, last_name, display_name, email, phone, timezone, locale, bio
- [ ] `GET /api/v1/users/me` response includes profile data and roles but NEVER password_hash, otp_secret, or any credential field
- [ ] `GET /api/v1/users` (admin list) response NEVER includes credential fields
- [ ] No JPA entity or DTO exposes credential fields in profile-facing queries
- [ ] `credentials` table is never joined with `user_profiles` in read queries exposed to API clients
- [ ] User profile update (`PUT /api/v1/users/me`) only modifies `user_profiles` — never touches `credentials`
- [ ] Password change (`POST /api/v1/auth/password/change`) only modifies `credentials` — never touches `user_profiles`
- [ ] Jackson serialization of profile DTOs does not include credential fields (enforced by DTO design, not `@JsonIgnore` on entities)

**Should Have (Nice to Have):**
- [ ] Static analysis rule or architectural test preventing credential fields in profile DTOs
- [ ] ArchUnit test enforcing no dependency from profile DTOs to credential entities

**Won't Have (Out of Scope):**
- Encryption at rest for credential fields (infrastructure concern)
- Column-level database encryption (future enhancement)

---

## Business Context

### Problem Statement
Accidental credential leakage is a critical security risk. If credential data (password hashes, OTP secrets) is mixed with profile data in the same entity or DTO, a single serialization mistake can expose sensitive authentication material in API responses, logs, or cache entries. Physical table separation with strict DTO boundaries eliminates this class of vulnerability.

### Target Users
- **Primary:** Platform developers writing user-facing APIs
- **Secondary:** Security auditors verifying separation invariant

### Success Metrics
- Zero credential fields in any API response (verified by integration tests)
- Zero credential fields in structured log output

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| User registration | PROV-101 | Co-dependent | Tables created together |
| Login | PROV-102 | Integration | Login reads credentials; profile endpoints read profiles |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Design Principles

1. **Separate tables:** `credentials` and `user_profiles` are distinct tables with no shared columns beyond `user_id`
2. **Separate entities:** `Credential.java` and `UserProfile.java` are independent JPA entities — never fetched together in profile queries
3. **Separate DTOs:** `UserProfileResponse` contains only profile fields; `CredentialRepository` is only used in authentication flows
4. **No `@JsonIgnore` reliance:** Separation is structural (different classes), not annotation-based

## Database Schema

`credentials`, `user_profiles` — see [PROV-100](PROV-100-user-identity-access-management.md) Database Schema section for full DDL.

---

## Implementation Checklist

### Domain Layer
- [ ] `Credential.java` — Entity: authentication-only fields, NEVER exposed in profile APIs
- [ ] `UserProfile.java` — Entity: personal info, safe for API responses
- [ ] No bidirectional JPA relationship between Credential and UserProfile

### Application Layer
- [ ] `UserService.getProfile()` — Reads from `UserProfileRepository` only
- [ ] `AuthenticationService.login()` — Reads from `CredentialRepository` only
- [ ] `AuthenticationService.changePassword()` — Writes to `CredentialRepository` only
- [ ] `UserService.updateProfile()` — Writes to `UserProfileRepository` only

### Infrastructure Layer
- [ ] `CredentialRepository.java` — Used ONLY in authentication service
- [ ] `UserProfileRepository.java` — Used ONLY in user profile service

### Adapter Layer
- [ ] `UserProfileResponse.java` — DTO record with ONLY profile fields (no credential data)
- [ ] `UserController.getMe()` — Returns `UserProfileResponse`
- [ ] `UserController.listUsers()` — Returns paginated `UserProfileResponse` (no credentials)

---

## Testing Requirements

**Unit Tests:**
- [ ] `UserProfileResponse` record does not have fields named `passwordHash`, `otpSecret`, `failedAttemptCount`, `lockedUntil`
- [ ] `UserService.getProfile()` does not call `CredentialRepository`
- [ ] `AuthenticationService.changePassword()` does not call `UserProfileRepository`

**Integration Tests:**
- [ ] **Credential Separation:** `GET /api/v1/users/me` response JSON does NOT contain keys: `passwordHash`, `password_hash`, `otpSecret`, `otp_secret`, `failedAttemptCount`, `lockedUntil`
- [ ] **Admin List:** `GET /api/v1/users` response does NOT contain credential fields for any user
- [ ] **Profile Update:** `PUT /api/v1/users/me` with profile fields → `credentials` table unchanged
- [ ] **Password Change:** `POST /api/v1/auth/password/change` → `user_profiles` table unchanged

**Architectural Tests (ArchUnit):**
- [ ] No class in `dto` package imports from `Credential.java`
- [ ] `UserProfileResponse` has no field of type that references credential data

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
