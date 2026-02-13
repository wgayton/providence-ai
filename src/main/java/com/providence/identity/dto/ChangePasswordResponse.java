package com.providence.identity.dto;

import java.util.UUID;

/**
 * Response DTO for password change initiation (Step 1).
 *
 * Returns a verification ID and the OTP (for development — delivery via
 * email/SMS comes in PROV-110). The caller must submit the OTP via the
 * confirm endpoint to complete the password change.
 */
public record ChangePasswordResponse(
    String message,
    UUID verificationId,
    String otp
) {}
