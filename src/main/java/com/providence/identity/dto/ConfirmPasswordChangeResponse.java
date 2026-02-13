package com.providence.identity.dto;

import java.time.Instant;

/**
 * Response DTO for password change confirmation (Step 2).
 * Contains ONLY confirmation — never credential data.
 */
public record ConfirmPasswordChangeResponse(
    String message,
    Instant changedAt
) {}
