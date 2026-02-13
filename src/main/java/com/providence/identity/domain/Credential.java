package com.providence.identity.domain;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/**
 * Credential entity — authentication-only data.
 *
 * Contains ONLY: email (login identifier), password_hash, OTP fields,
 * brute-force protection fields, and password lifecycle timestamps.
 *
 * NEVER exposed in profile-facing APIs, DTOs, or read queries.
 * Lives in tenant schema (t_<tenant>).
 * No bidirectional JPA relationship with UserProfile.
 */
@Entity
@Table(name = "credentials")
public class Credential {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "user_id", nullable = false, unique = true)
    private UUID userId;

    @Column(nullable = false, unique = true, length = 255)
    private String email;

    @Column(name = "password_hash", nullable = false, length = 255)
    private String passwordHash;

    @Column(name = "otp_secret", length = 255)
    private String otpSecret;

    @Column(name = "otp_verified_at")
    private Instant otpVerifiedAt;

    @Column(name = "failed_attempt_count", nullable = false)
    private int failedAttemptCount;

    @Column(name = "locked_until")
    private Instant lockedUntil;

    @Column(name = "last_failed_at")
    private Instant lastFailedAt;

    @Column(name = "password_changed_at", nullable = false)
    private Instant passwordChangedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected Credential() {}

    public Credential(UUID userId, String email, String passwordHash) {
        this.id = UUID.randomUUID();
        this.userId = userId;
        this.email = email;
        this.passwordHash = passwordHash;
        this.failedAttemptCount = 0;
        this.passwordChangedAt = Instant.now();
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public void changePassword(String newPasswordHash) {
        this.passwordHash = newPasswordHash;
        this.passwordChangedAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public String getEmail() { return email; }
    public String getPasswordHash() { return passwordHash; }
    public String getOtpSecret() { return otpSecret; }
    public Instant getOtpVerifiedAt() { return otpVerifiedAt; }
    public int getFailedAttemptCount() { return failedAttemptCount; }
    public Instant getLockedUntil() { return lockedUntil; }
    public Instant getLastFailedAt() { return lastFailedAt; }
    public Instant getPasswordChangedAt() { return passwordChangedAt; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
