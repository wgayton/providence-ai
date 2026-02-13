package com.providence.identity.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Request DTO for changing password.
 * Only modifies credentials — never touches user_profiles.
 */
public record ChangePasswordRequest(
    @NotBlank(message = "Current password is required")
    String currentPassword,

    @NotBlank(message = "New password is required")
    @Size(min = 12, message = "Password must be at least 12 characters")
    String newPassword
) {}
