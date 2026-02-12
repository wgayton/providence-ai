# OTP SMS Delivery Path - User Story

> **Story ID:** PROV-110
> **Parent Epic:** [PROV-100](PROV-100-user-identity-access-management.md)
> **Related:** [PROV-101](PROV-101-user-registration-otp.md) (email OTP path)
> **Author:** Claude (Product Developer Persona)
> **Date:** 2026-02-12
> **Status:** Draft
> **Priority:** P1

---

## User Story

**As a** new user registering on a tenant subdomain
**I want to** receive my one-time password via SMS to my phone number instead of (or in addition to) email
**So that** I can verify my identity quickly using my mobile device, even if I don't have immediate access to my email inbox

---

## Acceptance Criteria

**Must Have (Required):**
- [ ] User can provide a phone number during registration (optional field alongside email)
- [ ] Phone number validated in E.164 format (e.g., `+15551234567`) using Jakarta Validation custom constraint
- [ ] When phone number is provided, user can choose OTP delivery channel: `EMAIL` or `SMS`
- [ ] OTP delivery channel stored in `credentials.otp_channel` column (FK to `ref_otp_channels`)
- [ ] `ref_otp_channels` administered reference table seeded with `EMAIL` and `SMS`
- [ ] SMS OTP sent via an abstracted `OtpDeliveryService` with pluggable provider (Twilio, AWS SNS, etc.)
- [ ] SMS message content: `"Your Providence verification code is: {code}. It expires in 10 minutes. Do not share this code."`
- [ ] SMS delivery attempt recorded in `otp_delivery_attempts` table (channel, phone, status, provider_reference, sent_at)
- [ ] OTP verification endpoint (`POST /api/v1/auth/verify-otp`) works identically regardless of delivery channel
- [ ] SMS rate limiting: max 3 SMS sends per phone number per 10-minute window (separate from email rate limit)
- [ ] Rate limit exceeded returns `429 Too Many Requests` with RFC 9457 ProblemDetail and `Retry-After` header
- [ ] OTP resend endpoint (`POST /api/v1/auth/otp/resend`) supports channel selection for resend
- [ ] `OtpSmsDeliveredEvent` published via outbox on successful SMS dispatch
- [ ] `OtpSmsFailedEvent` published via outbox on SMS delivery failure
- [ ] Circuit breaker on SMS provider client — opens after 5 consecutive failures, half-open after 30 seconds
- [ ] When SMS circuit breaker is open, fall back to email delivery and return `202 Accepted` with message indicating fallback
- [ ] Audit log entry: `OTP_SMS_SENT`, `OTP_SMS_FAILED`, `OTP_SMS_RATE_LIMITED`
- [ ] All SMS mutation endpoints require `Idempotency-Key` header

**Should Have (Nice to Have):**
- [ ] SMS delivery receipt webhook (provider confirms delivery to handset)
- [ ] Phone number verification status (`phone_verified_at` on `user_profiles`)
- [ ] Configurable SMS provider per tenant (tenant-level provider configuration)
- [ ] Dual-channel OTP: send to both email and SMS simultaneously

**Won't Have (Out of Scope):**
- Voice call OTP delivery (future story)
- WhatsApp / messaging app delivery (future story)
- Phone number as login identifier (PROV-101 uses username/email)
- International number validation beyond E.164 format (carrier-level validation)
- SMS template localization (future i18n story)

---

## Business Context

### Problem Statement
Email-based OTP delivery has inherent latency (spam filters, inbox delays) and accessibility gaps (users without immediate email access). SMS provides a faster, more direct delivery channel that most users can access instantly on their mobile device. However, SMS is a paid channel with abuse potential, requiring strict rate limiting, cost controls, and circuit breaker patterns.

### Target Users
- **Primary:** New users who prefer or require SMS-based verification
- **Secondary:** Users in environments where email delivery is slow or unreliable
- **Tertiary:** Tenant administrators configuring OTP delivery preferences

### Success Metrics
- SMS OTP delivery time < 10 seconds from request (provider SLA dependent)
- SMS delivery success rate > 95% (provider dependent)
- SMS rate limit violations < 5% of total SMS OTP requests
- Fallback to email on SMS failure: 100% coverage (zero lost OTPs)
- Circuit breaker recovery time < 60 seconds after provider recovery

---

## Dependencies

| Dependency | Story | Type | Notes |
|-----------|-------|------|-------|
| Registration + email OTP | PROV-101 | Prerequisite | Core registration flow and OTP verification must exist |
| Credential separation | PROV-109 | Prerequisite | `credentials` table must exist for `otp_channel` column |
| Reference tables | PROV-100 | Shared | Pattern for administered ref tables established |

---

<details>
<summary><strong>Architecture & Implementation Details</strong> (Expand during implementation)</summary>

## Database Schema

### Tenant Schema Changes

**OTP Channels Reference** (`ref_otp_channels`):
```sql
-- Administered reference table for OTP delivery channels
CREATE TABLE IF NOT EXISTS ref_otp_channels (
    code VARCHAR(20) PRIMARY KEY,
    label VARCHAR(100) NOT NULL,
    description TEXT,
    display_order INT NOT NULL DEFAULT 0,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO ref_otp_channels (code, label, description, display_order)
VALUES
    ('EMAIL', 'Email', 'OTP delivered via email', 1),
    ('SMS', 'SMS', 'OTP delivered via SMS text message', 2)
ON CONFLICT (code) DO NOTHING;
```

**Credential Table Addition** (alter existing `credentials` table):
```sql
-- Add OTP channel preference to credentials
ALTER TABLE credentials
    ADD COLUMN otp_channel VARCHAR(20) NOT NULL DEFAULT 'EMAIL'
        REFERENCES ref_otp_channels(code);
```

**OTP Delivery Attempts** (`otp_delivery_attempts`):
```sql
-- Tracks every OTP delivery attempt for auditing, rate limiting, and debugging
CREATE TABLE IF NOT EXISTS otp_delivery_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Delivery channel
    channel VARCHAR(20) NOT NULL
        REFERENCES ref_otp_channels(code),

    -- Destination (email address or phone number)
    destination VARCHAR(255) NOT NULL,

    -- Delivery status
    status VARCHAR(20) NOT NULL DEFAULT 'SENT',  -- SENT, DELIVERED, FAILED, RATE_LIMITED

    -- Provider tracking
    provider_name VARCHAR(100),          -- e.g., 'twilio', 'aws_sns'
    provider_reference VARCHAR(255),     -- provider message ID for tracing

    -- Failure details (NULL on success)
    failure_reason TEXT,

    -- Was this a fallback from another channel?
    fallback_from VARCHAR(20)
        REFERENCES ref_otp_channels(code),

    sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_otp_delivery_user ON otp_delivery_attempts(user_id, sent_at DESC);
CREATE INDEX idx_otp_delivery_destination ON otp_delivery_attempts(destination, sent_at DESC);
CREATE INDEX idx_otp_delivery_rate_limit ON otp_delivery_attempts(destination, channel, sent_at DESC)
    WHERE sent_at > NOW() - INTERVAL '10 minutes';
```

**Migration:** `V004__add_otp_sms_support.sql` in `/src/main/resources/db/migration/tenant/`

---

## Domain Events

**Events Emitted:**
- `OtpSmsDelivered` → `ecap.events.Otp.SmsDelivered`
- `OtpSmsFailed` → `ecap.events.Otp.SmsFailed`

```java
public record OtpSmsDelivered(
    UUID eventId,
    String tenantId,
    UUID userId,
    String phoneNumber,    // masked: +1***4567
    String providerName,
    String providerReference,
    Instant occurredAt
) {}

public record OtpSmsFailed(
    UUID eventId,
    String tenantId,
    UUID userId,
    String phoneNumber,    // masked
    String providerName,
    String failureReason,
    boolean fallbackToEmail,
    Instant occurredAt
) {}
```

**Kafka Topics:**
- `ecap.events.Otp.SmsDelivered` (12 partitions, 30-day retention)
- `ecap.events.Otp.SmsFailed` (12 partitions, 90-day retention)

**Partition key:** `tenant_id`

---

## API Endpoints

**Registration (modified — adds optional phone and channel):**
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
  "phone": "+15551234567",
  "otpChannel": "SMS"
}

Response: 201 Created
{
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "status": "PENDING_VERIFICATION",
  "otpChannel": "SMS",
  "message": "OTP sent via SMS to +1***4567. Please verify to activate your account."
}
```

**OTP Resend (new endpoint):**
```http
POST /api/v1/auth/otp/resend
Host: {tenant-slug}.providence.ai
Idempotency-Key: {uuid}
Content-Type: application/json

{
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "channel": "SMS"
}

Response: 200 OK
{
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "otpChannel": "SMS",
  "message": "OTP resent via SMS to +1***4567.",
  "remainingResends": 2
}

Response: 429 Too Many Requests
{
  "type": "https://providence.ai/problems/otp-rate-limited",
  "title": "OTP Rate Limited",
  "status": 429,
  "detail": "Maximum SMS resend limit (3) reached. Try again after the cooldown window.",
  "instance": "/api/v1/auth/otp/resend",
  "retryAfter": "2026-02-12T10:20:00Z"
}

Response: 200 OK (fallback)
{
  "userId": "7c9e6679-...",
  "otpChannel": "EMAIL",
  "message": "SMS delivery unavailable. OTP sent via email to j***@example.com as fallback.",
  "fallbackFrom": "SMS"
}
```

**OTP Verify (unchanged — works for both channels):**
```http
POST /api/v1/auth/verify-otp
Host: {tenant-slug}.providence.ai
Idempotency-Key: {uuid}
Content-Type: application/json

{
  "userId": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "otpCode": "482910"
}
```

**gRPC:**
```protobuf
service AuthService {
    rpc ResendOtp(ResendOtpRequest) returns (ResendOtpResponse);
}

message ResendOtpRequest {
    string idempotency_key = 1;
    string user_id = 2;
    string channel = 3;  // EMAIL or SMS
}
```

---

## Implementation Checklist

### Domain Layer (`com.providence.identity.domain`)
- [ ] `OtpChannel.java` — Value object representing delivery channel (EMAIL, SMS)
- [ ] `OtpDeliveryAttempt.java` — Entity: channel, destination, status, provider reference
- [ ] `OtpSmsDelivered.java` — Domain event record
- [ ] `OtpSmsFailed.java` — Domain event record
- [ ] Business rules: SMS rate limit (3 per phone per 10 min), E.164 phone format validation
- [ ] Phone number masking utility: `+15551234567` → `+1***4567`

### Application Layer (`com.providence.identity.service`)
- [ ] `OtpDeliveryService.java` — Strategy interface for OTP delivery
- [ ] `EmailOtpDeliveryStrategy.java` — Email delivery (existing PROV-101 logic extracted)
- [ ] `SmsOtpDeliveryStrategy.java` — SMS delivery via provider client
- [ ] `OtpDeliveryOrchestrator.java` — Channel selection, rate limiting, fallback logic, circuit breaker
- [ ] `OtpRateLimitService.java` — Checks delivery attempts within 10-min window per destination+channel
- [ ] `ResendOtpCommand.java` — Immutable command record
- [ ] DTOs: `ResendOtpRequest`, `ResendOtpResponse`

### Infrastructure Layer (`com.providence.identity.adapter.infra`)
- [ ] `SmsProviderClient.java` — Abstracted SMS provider client (Twilio/AWS SNS)
- [ ] `TwilioSmsProvider.java` — Twilio implementation (or AWS SNS, configurable)
- [ ] Circuit breaker: `@CircuitBreaker(name = "smsProvider", fallbackMethod = "fallbackToEmail")`
- [ ] `OtpDeliveryAttemptRepository.java` — `JpaRepository<OtpDeliveryAttempt, UUID>` + rate limit queries
- [ ] `RefOtpChannelRepository.java` — Reference table repository
- [ ] Outbox integration for `OtpSmsDelivered`, `OtpSmsFailed`
- [ ] Audit logging: `OTP_SMS_SENT`, `OTP_SMS_FAILED`, `OTP_SMS_RATE_LIMITED`

### Adapter Layer
- [ ] `AuthController.java` — Add `POST /api/v1/auth/otp/resend` endpoint
- [ ] Modify `POST /api/v1/auth/register` to accept optional `phone` and `otpChannel` fields
- [ ] `AuthGrpcService.java` — Add `ResendOtp` RPC

### Configuration
- [ ] `application.yml` SMS provider properties:
  ```yaml
  providence:
    otp:
      sms:
        provider: twilio  # or aws-sns
        rate-limit:
          max-sends: 3
          window-minutes: 10
        circuit-breaker:
          failure-threshold: 5
          half-open-after-seconds: 30
  ```

---

## Testing Requirements

**Unit Tests:**
- [ ] SMS delivery: valid phone → provider called, `OtpSmsDelivered` event emitted, delivery attempt recorded
- [ ] SMS delivery: provider failure → `OtpSmsFailed` event emitted, fallback to email triggered
- [ ] SMS rate limit: 4th SMS within 10 min → `429 Too Many Requests`, `OTP_SMS_RATE_LIMITED` audit entry
- [ ] SMS rate limit: after 10 min window expires → counter resets, SMS allowed
- [ ] Phone validation: valid E.164 (`+15551234567`) → accepted
- [ ] Phone validation: invalid format (`555-1234567`, `5551234567`) → `400 Bad Request`
- [ ] Channel selection: `otpChannel=SMS` with no phone → `400 Bad Request`
- [ ] Channel selection: `otpChannel=EMAIL` (default) → email delivery (existing behavior)
- [ ] Resend: valid resend within limit → new OTP sent, previous OTP invalidated
- [ ] Resend: already verified user → `400 Bad Request`
- [ ] Circuit breaker: 5 consecutive failures → circuit opens, fallback to email
- [ ] Circuit breaker: after half-open period → next SMS attempt allowed
- [ ] Phone masking: `+15551234567` → `+1***4567` in events and responses

**Integration Tests:**
- [ ] **Happy Path SMS:** Register with phone + SMS channel → SMS OTP sent → verify OTP → user ACTIVE
- [ ] **Fallback:** SMS provider down (circuit open) → email fallback → verify OTP → user ACTIVE
- [ ] **Rate Limiting:** 3 SMS resends → 429 on 4th → wait → succeeds again
- [ ] **Idempotency:** Duplicate resend `Idempotency-Key` → same response
- [ ] **Cross-Tenant Isolation:** SMS delivery attempts not visible across tenants
- [ ] **Audit Trail:** SMS sent, failed, rate-limited → audit_log entries
- [ ] **Outbox:** SMS events appear on Kafka topics

---

## Security Considerations

- [ ] Phone numbers masked in all API responses, events, and logs (`+1***4567`)
- [ ] OTP codes never logged (even at DEBUG level)
- [ ] SMS message content does not include tenant name or user identity (prevents social engineering)
- [ ] Rate limiting per destination phone number prevents SMS bombing attacks
- [ ] Circuit breaker prevents cascading cost from provider outages
- [ ] Provider API credentials stored in secrets manager (never in config files or environment variables)

---

## Observability

**Logging:**
```java
log.info("OTP SMS sent: userId={}, destination=+1***4567, provider={}", userId, provider);
log.warn("OTP SMS failed: userId={}, provider={}, reason={}", userId, provider, reason);
log.warn("OTP SMS rate limited: destination=+1***4567, attempts={}/3", attempts);
log.info("OTP SMS fallback to email: userId={}, reason={}", userId, reason);
```

**Metrics:**
```java
meterRegistry.counter("otp.sms.sent", "tenant", tenantId, "provider", provider).increment();
meterRegistry.counter("otp.sms.failed", "tenant", tenantId, "provider", provider).increment();
meterRegistry.counter("otp.sms.rate_limited", "tenant", tenantId).increment();
meterRegistry.counter("otp.sms.fallback", "tenant", tenantId).increment();
meterRegistry.timer("otp.sms.delivery.duration", "tenant", tenantId, "provider", provider).record(duration);
```

**Operational Alerts:**
- SMS delivery failure rate > 10% over 5 minutes → PagerDuty alert
- Circuit breaker open → immediate alert
- SMS rate limit violations > 20/minute per tenant → abuse investigation

</details>

---

**Template Version:** 1.0.0
**Last Updated:** 2026-02-12
