# Device Fingerprinting and Tracking - User Story

> **Story ID:** PROV-103
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P0

---

## User Story

**As a** registered user
**I want to** have my devices tracked and fingerprinted on every authentication event so I can view and manage my recognized devices
**So that** I am aware of all devices accessing my account, enabling anomaly detection and device-level security

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] System captures device fingerprint, browser name/version, OS name/version, IP address, and user agent on every authentication event
- [ ] Device records stored in `user_devices` table linked to the user
- [ ] Same device fingerprint updates `last_seen_at` and `ip_address` rather than creating a duplicate
- [ ] New (previously unseen) devices trigger a `UserDeviceRegisteredEvent` via outbox
- [ ] User can view registered devices via `GET /api/v1/users/me/devices`
- [ ] User can revoke/remove a device via `DELETE /api/v1/users/me/devices/{deviceId}` (requires `Idempotency-Key`)
- [ ] Device fingerprint capture rate: 100% of authentication events
- [ ] Unique constraint `(user_id, fingerprint_hash)` prevents duplicate device records

**Should Have (Nice to Have):**
- [ ] Trusted device marking — skip MFA on trusted devices
- [ ] Device naming (user can rename a device)

**Won't Have (Out of Scope):**
- Security alerts on new device login (see PROV-104)
- Device-based session management (future story)

---

## Business Context

### Problem Statement
Tracking which devices access a user's account is critical for security monitoring and anomaly detection. Users need visibility into their active devices and the ability to revoke access from unrecognized ones.

### Target Users
- **Primary:** Authenticated users managing their device list
- **Secondary:** Security teams analyzing device patterns across tenants

### Success Metrics
- Device fingerprint capture rate: 100% of authentication events
- Device list API response time < 100ms p99

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| User registration | PROV-101 | Prerequisite | Users must exist |
| Login flow | PROV-102 | Integration | Fingerprint captured during login |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

`user_devices` — see [PROV-100](PROV-100-user-identity-access-management.md) Database Schema section for full DDL.

---

## Domain Events

**Events Emitted:**
- `UserDeviceRegistered` → `ecap.events.User.DeviceRegistered`

**Partition key:** `tenant_id`

---

## API Endpoints

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

---

## Implementation Checklist

### Domain Layer
- [ ] `UserDevice.java` — Entity: fingerprint hash, device details, trust flag, timestamps
- [ ] `DeviceFingerprint.java` — Value object: fingerprint hash + device characteristics
- [ ] `UserDeviceRegistered.java` — Domain event record

### Application Layer
- [ ] `DeviceService.java` — Fingerprint registration/update, device listing, revocation with `@Transactional`
- [ ] Called from `AuthenticationService.login()` to register/update device on each login

### Infrastructure Layer
- [ ] `UserDeviceRepository.java` — `JpaRepository<UserDevice, UUID>` + `findByUserIdAndFingerprintHash`
- [ ] Outbox integration for `UserDeviceRegistered`

### Adapter Layer
- [ ] `DeviceController.java` — REST: `GET /api/v1/users/me/devices`, `DELETE /api/v1/users/me/devices/{deviceId}`

---

## Testing Requirements

**Unit Tests:**
- [ ] New device fingerprint → creates `user_devices` record, emits `UserDeviceRegistered` event
- [ ] Known device fingerprint → updates `last_seen_at` and `ip_address`, no event emitted
- [ ] Device revocation → deletes record
- [ ] List devices → returns all devices for user, ordered by last_seen_at desc

**Integration Tests:**
- [ ] **Happy Path:** Login from new device → device record created → event on Kafka
- [ ] **Device Tracking:** Login from known device → `last_seen_at` updated, no duplicate created
- [ ] **Cross-Tenant Isolation:** User's devices not visible from another tenant
- [ ] **Revocation:** Delete device → 204, device no longer in list

---

## Observability

**Metrics:**
```java
meterRegistry.counter("device.registered", "tenant", tenantId).increment();
```

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
