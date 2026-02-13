package com.providence.identity.dto;

import java.time.Instant;

/**
 * Response DTO for password change.
 * Contains ONLY confirmation — never credential data.
 */
public record ChangePasswordResponse(
    String message,
    Instant changedAt
) {}
