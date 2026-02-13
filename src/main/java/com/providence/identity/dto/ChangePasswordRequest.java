package com.providence.identity.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Request DTO for initiating a password change (Step 1).
 *
 * Verifies current password and generates an OTP.
 * The actual password change only happens after OTP confirmation (Step 2).
 */
public record ChangePasswordRequest(
    @NotBlank(message = "Current password is required")
    String currentPassword,

    @NotBlank(message = "New password is required")
    @Size(min = 12, message = "Password must be at least 12 characters")
    String newPassword
) {}
