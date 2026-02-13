package com.providence.identity.service;

import com.providence.identity.domain.Credential;
import com.providence.identity.domain.OtpVerification;
import com.providence.identity.dto.ChangePasswordRequest;
import com.providence.identity.dto.ChangePasswordResponse;
import com.providence.identity.dto.ConfirmPasswordChangeRequest;
import com.providence.identity.dto.ConfirmPasswordChangeResponse;
import com.providence.identity.repository.CredentialRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * Unit tests for CredentialService.
 *
 * PROV-109: Verifies that CredentialService reads/writes ONLY Credential data
 * and has NO dependency on UserProfileRepository.
 *
 * Verifies the two-step OTP verification lifecycle for password changes.
 */
@ExtendWith(MockitoExtension.class)
class CredentialServiceTest {

    @Mock
    private CredentialRepository credentialRepository;

    @Mock
    private OtpService otpService;

    @InjectMocks
    private CredentialService credentialService;

    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

    // --- Step 1: Initiate Password Change ---

    @Test
    void initiatePasswordChange_verifiesCurrentPasswordAndGeneratesOtp() {
        UUID userId = UUID.randomUUID();
        String currentPassword = "OldP@ssw0rd123";
        String currentHash = encoder.encode(currentPassword);
        Credential credential = new Credential(userId, "jane@example.com", currentHash);
        UUID verificationId = UUID.randomUUID();

        when(credentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));
        when(otpService.generateAndStore(eq(userId), eq("PASSWORD_CHANGE"), any()))
                .thenReturn(new OtpService.OtpGenerationResult(verificationId, "123456"));

        ChangePasswordResponse response = credentialService.initiatePasswordChange(
                userId, new ChangePasswordRequest(currentPassword, "NewSecureP@ss456"));

        assertThat(response.message()).contains("OTP sent");
        assertThat(response.verificationId()).isEqualTo(verificationId);
        assertThat(response.otp()).isEqualTo("123456");

        // Password NOT changed yet
        verify(credentialRepository, never()).save(any());
    }

    @Test
    void initiatePasswordChange_rejectsIncorrectCurrentPassword() {
        UUID userId = UUID.randomUUID();
        String currentHash = encoder.encode("ActualPassword123");
        Credential credential = new Credential(userId, "jane@example.com", currentHash);

        when(credentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));

        assertThatThrownBy(() -> credentialService.initiatePasswordChange(
                userId, new ChangePasswordRequest("WrongPassword123", "NewSecureP@ss456")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Current password is incorrect");

        verify(otpService, never()).generateAndStore(any(), any(), any());
    }

    // --- Step 2: Confirm Password Change ---

    @Test
    void confirmPasswordChange_appliesPasswordAfterOtpVerification() {
        UUID userId = UUID.randomUUID();
        UUID verificationId = UUID.randomUUID();
        String newPasswordHash = encoder.encode("NewSecureP@ss456");
        Credential credential = new Credential(userId, "jane@example.com", encoder.encode("OldP@ssw0rd123"));

        OtpVerification verification = new OtpVerification(
                userId, "PASSWORD_CHANGE", "otp-hash", newPasswordHash,
                Instant.now().plusSeconds(300));
        verification.markVerified();

        when(otpService.verifyOtp(verificationId, userId, "123456")).thenReturn(verification);
        when(credentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));
        when(credentialRepository.save(any(Credential.class))).thenAnswer(inv -> inv.getArgument(0));

        ConfirmPasswordChangeResponse response = credentialService.confirmPasswordChange(
                userId, new ConfirmPasswordChangeRequest(verificationId, "123456"));

        assertThat(response.message()).isEqualTo("Password changed successfully.");
        assertThat(response.changedAt()).isNotNull();
        verify(credentialRepository).save(any(Credential.class));
        verify(otpService).markConsumed(verification.getId());
    }

    @Test
    void confirmPasswordChange_doesNotModifyProfileData() {
        UUID userId = UUID.randomUUID();
        UUID verificationId = UUID.randomUUID();
        String newPasswordHash = encoder.encode("NewSecureP@ss456");
        Credential credential = new Credential(userId, "jane@example.com", encoder.encode("OldP@ssw0rd123"));

        OtpVerification verification = new OtpVerification(
                userId, "PASSWORD_CHANGE", "otp-hash", newPasswordHash,
                Instant.now().plusSeconds(300));
        verification.markVerified();

        when(otpService.verifyOtp(verificationId, userId, "123456")).thenReturn(verification);
        when(credentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));
        when(credentialRepository.save(any(Credential.class))).thenAnswer(inv -> inv.getArgument(0));

        credentialService.confirmPasswordChange(
                userId, new ConfirmPasswordChangeRequest(verificationId, "123456"));

        // PROV-109: CredentialService must not call UserProfileRepository
        verify(credentialRepository).findByUserId(userId);
        verify(credentialRepository).save(any(Credential.class));
        verifyNoMoreInteractions(credentialRepository);
    }

    // --- Structural Separation ---

    @Test
    void credentialService_hasNoUserProfileRepositoryDependency() {
        var constructors = CredentialService.class.getConstructors();
        assertThat(constructors).hasSize(1);

        var paramTypes = constructors[0].getParameterTypes();
        for (Class<?> type : paramTypes) {
            assertThat(type.getSimpleName())
                    .as("CredentialService should not depend on UserProfileRepository")
                    .doesNotContain("UserProfile");
        }
    }
}
