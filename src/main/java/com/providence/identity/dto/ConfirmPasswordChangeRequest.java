package com.providence.identity.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.UUID;

/**
 * Request DTO for confirming a password change with OTP (Step 2).
 *
 * The verificationId comes from the initiate step.
 * The otpCode is the 6-digit code sent to the user.
 */
public record ConfirmPasswordChangeRequest(
    @NotNull(message = "Verification ID is required")
    UUID verificationId,

    @NotBlank(message = "OTP code is required")
    @Size(min = 6, max = 6, message = "OTP code must be 6 digits")
    String otpCode
) {}
