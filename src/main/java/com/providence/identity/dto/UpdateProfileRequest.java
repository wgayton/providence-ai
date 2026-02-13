package com.providence.identity.dto;

import jakarta.validation.constraints.Size;

/**
 * Request DTO for updating user profile.
 * Contains ONLY profile fields — never credential data.
 */
public record UpdateProfileRequest(
    @Size(max = 100, message = "First name cannot exceed 100 characters")
    String firstName,

    @Size(max = 100, message = "Last name cannot exceed 100 characters")
    String lastName,

    @Size(max = 255, message = "Display name cannot exceed 255 characters")
    String displayName,

    @Size(max = 50, message = "Phone cannot exceed 50 characters")
    String phone,

    @Size(max = 50, message = "Timezone cannot exceed 50 characters")
    String timezone,

    @Size(max = 10, message = "Locale cannot exceed 10 characters")
    String locale,

    String bio
) {}
