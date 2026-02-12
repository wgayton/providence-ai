# Security Alerts - User Story

> **Story ID:** PROV-104
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P1

---

## User Story

**As a** registered user
**I want to** receive security alerts when suspicious activity occurs on my account (brute-force attempts, password changes, new device logins)
**So that** I am immediately aware of potential threats and can take action to secure my account

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] User is alerted when 3 failed login attempts occur on their account (brute-force detection → `BRUTE_FORCE_DETECTED`)
- [ ] User is alerted when a password change event occurs (`PASSWORD_CHANGED`)
- [ ] User is alerted when a login from a new (previously unseen) device occurs (`NEW_DEVICE_LOGIN`)
- [ ] User is alerted when their account is locked (`ACCOUNT_LOCKED`) or unlocked (`ACCOUNT_UNLOCKED`)
- [ ] Alert types are stored in the `ref_alert_types` administered reference table
- [ ] Security alerts are persisted in `security_alerts` table and retrievable via `GET /api/v1/users/me/alerts`
- [ ] Alerts support pagination and filtering by `unreadOnly`
- [ ] User can acknowledge an alert via `PUT /api/v1/users/me/alerts/{alertId}/acknowledge`
- [ ] `SecurityAlertCreatedEvent` published via outbox for downstream notification services (email, push)
- [ ] Kafka consumer for `SecurityAlertCreated` events uses inbox pattern for exactly-once processing
- [ ] Audit log entry created with `event_type=SECURITY_ALERT_CREATED`

**Should Have (Nice to Have):**
- [ ] Alert severity levels (INFO, WARNING, CRITICAL)
- [ ] Bulk acknowledge endpoint

**Won't Have (Out of Scope):**
- Email/push notification delivery (separate notification service story)
- Alert preferences/settings (future story)

---

## Business Context

### Problem Statement
Users need timely notification of security-relevant events on their accounts. Persisted alerts provide an audit trail of security incidents and enable downstream notification services to deliver alerts via email or push.

### Target Users
- **Primary:** Authenticated users monitoring their account security
- **Secondary:** Notification service consuming alert events for delivery

### Success Metrics
- Security alert creation < 500ms from triggering event
- Alert acknowledgment API < 100ms p99

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| Login / brute-force | PROV-102 | Prerequisite | Lockout events trigger alerts |
| Device fingerprinting | PROV-103 | Prerequisite | New device events trigger alerts |
| Reference tables | PROV-100 | Shared | `ref_alert_types` seeded in tenant migration V001 |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

`security_alerts`, `ref_alert_types` — see [PROV-100](PROV-100-user-identity-access-management.md) Database Schema section for full DDL.

---

## Domain Events

**Events Emitted:**
- `SecurityAlertCreated` → `ecap.events.SecurityAlert.Created`

**Events Consumed:**
- `ecap.events.SecurityAlert.Created` → `notification-service` consumer group (sends email/push)
- `ecap.events.User.AccountLocked` → triggers `ACCOUNT_LOCKED` alert creation

---

## API Endpoints

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
  ],
  "page": { "number": 0, "size": 20, "totalElements": 5, "totalPages": 1 }
}
```

```http
PUT /api/v1/users/me/alerts/{alertId}/acknowledge
Authorization: Bearer <jwt>

Response: 200 OK
{ "alertId": "a1b2c3d4-...", "acknowledgedAt": "2026-02-12T10:30:00Z" }
```

---

## Implementation Checklist

### Domain Layer
- [ ] `SecurityAlert.java` — Entity: alert type, title, message, context JSONB, acknowledged_at
- [ ] `SecurityAlertCreated.java` — Domain event record

### Application Layer
- [ ] `SecurityAlertService.java` — Alert creation, listing (paginated), acknowledgment with `@Transactional`
- [ ] Called from `LoginThrottleService` on lockout, from `AuthenticationService` on password change, from `DeviceService` on new device

### Infrastructure Layer
- [ ] `SecurityAlertRepository.java` — `JpaRepository<SecurityAlert, UUID>` + unread query
- [ ] `RefAlertTypeRepository.java` — Reference table repository
- [ ] `SecurityAlertEventConsumer.java` — Kafka consumer with inbox pattern for notification dispatch
- [ ] Outbox integration for `SecurityAlertCreated`

### Adapter Layer
- [ ] `SecurityAlertController.java` — REST: `GET /api/v1/users/me/alerts`, `PUT /api/v1/users/me/alerts/{alertId}/acknowledge`

---

## Testing Requirements

**Unit Tests:**
- [ ] Alert creation: valid input → alert persisted, outbox event written
- [ ] Alert listing: returns paginated, filtered by unreadOnly
- [ ] Alert acknowledgment: sets `acknowledged_at`, idempotent on re-acknowledge
- [ ] Alert type validation: invalid type → rejected

**Integration Tests:**
- [ ] **Brute Force Flow:** 3 failed logins → account locked → `BRUTE_FORCE_DETECTED` + `ACCOUNT_LOCKED` alerts created → retrievable via API
- [ ] **Password Change:** Change password → `PASSWORD_CHANGED` alert created
- [ ] **Inbox Deduplication:** Replay `SecurityAlertCreated` Kafka event → consumer skips duplicate
- [ ] **Cross-Tenant Isolation:** Alerts not visible across tenants

---

## Observability

**Metrics:**
```java
meterRegistry.counter("security.alert.created", "tenant", tenantId, "type", alertType).increment();
```

**Operational Alerts:**
- Account lockout rate > 10/minute per tenant → PagerDuty alert

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
