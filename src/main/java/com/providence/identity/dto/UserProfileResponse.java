package com.providence.identity.dto;

import java.time.Instant;
import java.util.UUID;

/**
 * Profile response DTO — contains ONLY profile fields.
 *
 * PROV-109: Credential separation enforced by DTO design, not @JsonIgnore.
 * This record intentionally excludes: passwordHash, otpSecret,
 * failedAttemptCount, lockedUntil, lastFailedAt, passwordChangedAt.
 *
 * Roles and features will be added in PROV-105/PROV-106.
 */
public record UserProfileResponse(
    UUID userId,
    String displayName,
    String firstName,
    String lastName,
    String email,
    String phone,
    String timezone,
    String locale,
    String bio,
    String status,
    Instant createdAt
) {}
