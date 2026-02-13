package com.providence.identity.dto;

import org.junit.jupiter.api.Test;

import java.lang.reflect.RecordComponent;
import java.util.Arrays;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unit tests verifying credential/profile separation in DTOs.
 *
 * PROV-109: UserProfileResponse must NEVER contain credential fields.
 * Separation is enforced by DTO design (record fields), not @JsonIgnore.
 */
class CredentialSeparationDtoTest {

    /**
     * Credential field names that must NEVER appear in profile DTOs.
     */
    private static final Set<String> FORBIDDEN_CREDENTIAL_FIELDS = Set.of(
            "passwordHash", "password_hash",
            "otpSecret", "otp_secret",
            "failedAttemptCount", "failed_attempt_count",
            "lockedUntil", "locked_until",
            "lastFailedAt", "last_failed_at",
            "passwordChangedAt", "password_changed_at"
    );

    @Test
    void userProfileResponse_doesNotContainCredentialFields() {
        RecordComponent[] components = UserProfileResponse.class.getRecordComponents();
        var fieldNames = Arrays.stream(components)
                .map(RecordComponent::getName)
                .toList();

        for (String forbidden : FORBIDDEN_CREDENTIAL_FIELDS) {
            assertThat(fieldNames)
                    .as("UserProfileResponse must not contain credential field: %s", forbidden)
                    .doesNotContain(forbidden);
        }
    }

    @Test
    void userProfileResponse_containsOnlyExpectedFields() {
        RecordComponent[] components = UserProfileResponse.class.getRecordComponents();
        var fieldNames = Arrays.stream(components)
                .map(RecordComponent::getName)
                .toList();

        assertThat(fieldNames).containsExactlyInAnyOrder(
                "userId", "displayName", "firstName", "lastName",
                "email", "phone", "timezone", "locale", "bio",
                "status", "createdAt"
        );
    }

    @Test
    void updateProfileRequest_doesNotContainCredentialFields() {
        RecordComponent[] components = UpdateProfileRequest.class.getRecordComponents();
        var fieldNames = Arrays.stream(components)
                .map(RecordComponent::getName)
                .toList();

        for (String forbidden : FORBIDDEN_CREDENTIAL_FIELDS) {
            assertThat(fieldNames)
                    .as("UpdateProfileRequest must not contain credential field: %s", forbidden)
                    .doesNotContain(forbidden);
        }

        // Also verify no password field exists
        assertThat(fieldNames).doesNotContain("password", "currentPassword", "newPassword");
    }

    @Test
    void changePasswordRequest_doesNotContainProfileFields() {
        RecordComponent[] components = ChangePasswordRequest.class.getRecordComponents();
        var fieldNames = Arrays.stream(components)
                .map(RecordComponent::getName)
                .toList();

        // Password change DTO should not contain any profile fields
        assertThat(fieldNames).doesNotContain(
                "firstName", "lastName", "displayName", "phone",
                "timezone", "locale", "bio"
        );

        // Should contain only password fields
        assertThat(fieldNames).containsExactlyInAnyOrder("currentPassword", "newPassword");
    }
}
