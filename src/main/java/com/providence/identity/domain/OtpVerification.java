package com.providence.identity.domain;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/**
 * OTP verification entity — tracks pending OTP-gated operations.
 *
 * Lifecycle: PENDING → VERIFIED → CONSUMED (or EXPIRED)
 *
 * Used for password changes, registration confirmation, and other
 * operations that require OTP verification before completion.
 * Lives in tenant schema (t_<tenant>).
 */
@Entity
@Table(name = "otp_verifications")
public class OtpVerification {

    public static final int DEFAULT_MAX_ATTEMPTS = 5;

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "operation_type", nullable = false, length = 50)
    private String operationType;

    @Column(name = "otp_hash", nullable = false, length = 255)
    private String otpHash;

    @Column(columnDefinition = "JSONB")
    private String payload;

    @Column(nullable = false, length = 20)
    private String status;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "verified_at")
    private Instant verifiedAt;

    @Column(name = "consumed_at")
    private Instant consumedAt;

    @Column(name = "attempt_count", nullable = false)
    private int attemptCount;

    @Column(name = "max_attempts", nullable = false)
    private int maxAttempts;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected OtpVerification() {}

    public OtpVerification(UUID userId, String operationType, String otpHash,
                           String payload, Instant expiresAt) {
        this.id = UUID.randomUUID();
        this.userId = userId;
        this.operationType = operationType;
        this.otpHash = otpHash;
        this.payload = payload;
        this.status = "PENDING";
        this.expiresAt = expiresAt;
        this.attemptCount = 0;
        this.maxAttempts = DEFAULT_MAX_ATTEMPTS;
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public boolean isExpired() {
        return Instant.now().isAfter(expiresAt);
    }

    public boolean isMaxAttemptsExceeded() {
        return attemptCount >= maxAttempts;
    }

    public boolean isPending() {
        return "PENDING".equals(status);
    }

    public void recordFailedAttempt() {
        this.attemptCount++;
        this.updatedAt = Instant.now();
        if (isMaxAttemptsExceeded()) {
            this.status = "EXPIRED";
        }
    }

    public void markVerified() {
        this.status = "VERIFIED";
        this.verifiedAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public void markConsumed() {
        this.status = "CONSUMED";
        this.consumedAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public String getOperationType() { return operationType; }
    public String getOtpHash() { return otpHash; }
    public String getPayload() { return payload; }
    public String getStatus() { return status; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getVerifiedAt() { return verifiedAt; }
    public Instant getConsumedAt() { return consumedAt; }
    public int getAttemptCount() { return attemptCount; }
    public int getMaxAttempts() { return maxAttempts; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
