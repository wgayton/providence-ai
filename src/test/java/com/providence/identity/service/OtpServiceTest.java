package com.providence.identity.service;

import com.providence.identity.domain.OtpVerification;
import com.providence.identity.repository.OtpVerificationRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Unit tests for OtpService.
 *
 * Verifies OTP generation, storage, verification, and lifecycle management.
 */
@ExtendWith(MockitoExtension.class)
class OtpServiceTest {

    @Mock
    private OtpVerificationRepository otpVerificationRepository;

    @InjectMocks
    private OtpService otpService;

    @Test
    void generateAndStore_creates6DigitOtpAndStoresPendingVerification() {
        UUID userId = UUID.randomUUID();
        when(otpVerificationRepository.save(any(OtpVerification.class)))
                .thenAnswer(inv -> inv.getArgument(0));

        OtpService.OtpGenerationResult result = otpService.generateAndStore(
                userId, "PASSWORD_CHANGE", "payload-data");

        assertThat(result.plainOtp()).hasSize(6);
        assertThat(result.plainOtp()).matches("\\d{6}");
        assertThat(result.verificationId()).isNotNull();

        ArgumentCaptor<OtpVerification> captor = ArgumentCaptor.forClass(OtpVerification.class);
        verify(otpVerificationRepository).save(captor.capture());
        OtpVerification saved = captor.getValue();
        assertThat(saved.getUserId()).isEqualTo(userId);
        assertThat(saved.getOperationType()).isEqualTo("PASSWORD_CHANGE");
        assertThat(saved.getPayload()).isEqualTo("payload-data");
        assertThat(saved.getStatus()).isEqualTo("PENDING");
        assertThat(saved.getExpiresAt()).isAfter(Instant.now());
    }

    @Test
    void verifyOtp_withCorrectCode_marksVerified() {
        UUID userId = UUID.randomUUID();
        UUID verificationId = UUID.randomUUID();

        // Generate an OTP first to get a valid hash
        when(otpVerificationRepository.save(any(OtpVerification.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        OtpService.OtpGenerationResult generated = otpService.generateAndStore(
                userId, "PASSWORD_CHANGE", "payload");

        // Create a verification record with the hash from the generated result
        ArgumentCaptor<OtpVerification> captor = ArgumentCaptor.forClass(OtpVerification.class);
        verify(otpVerificationRepository).save(captor.capture());
        OtpVerification pendingVerification = captor.getValue();

        when(otpVerificationRepository.findByIdAndUserIdAndStatus(
                pendingVerification.getId(), userId, "PENDING"))
                .thenReturn(Optional.of(pendingVerification));

        OtpVerification result = otpService.verifyOtp(
                pendingVerification.getId(), userId, generated.plainOtp());

        assertThat(result.getStatus()).isEqualTo("VERIFIED");
        assertThat(result.getVerifiedAt()).isNotNull();
    }

    @Test
    void verifyOtp_withIncorrectCode_throwsAndIncrementsAttemptCount() {
        UUID userId = UUID.randomUUID();
        UUID verificationId = UUID.randomUUID();
        OtpVerification verification = new OtpVerification(
                userId, "PASSWORD_CHANGE", "$2a$10$dummyhash", "payload",
                Instant.now().plusSeconds(300));

        when(otpVerificationRepository.findByIdAndUserIdAndStatus(verificationId, userId, "PENDING"))
                .thenReturn(Optional.of(verification));

        assertThatThrownBy(() -> otpService.verifyOtp(verificationId, userId, "000000"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("Invalid OTP code");

        assertThat(verification.getAttemptCount()).isEqualTo(1);
        verify(otpVerificationRepository).save(verification); // once for recording failed attempt
    }

    @Test
    void verifyOtp_whenExpired_throws() {
        UUID userId = UUID.randomUUID();
        UUID verificationId = UUID.randomUUID();
        OtpVerification verification = new OtpVerification(
                userId, "PASSWORD_CHANGE", "$2a$10$dummyhash", "payload",
                Instant.now().minusSeconds(60)); // already expired

        when(otpVerificationRepository.findByIdAndUserIdAndStatus(verificationId, userId, "PENDING"))
                .thenReturn(Optional.of(verification));

        assertThatThrownBy(() -> otpService.verifyOtp(verificationId, userId, "123456"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("expired");
    }

    @Test
    void verifyOtp_whenNotFound_throws() {
        UUID userId = UUID.randomUUID();
        UUID verificationId = UUID.randomUUID();

        when(otpVerificationRepository.findByIdAndUserIdAndStatus(verificationId, userId, "PENDING"))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> otpService.verifyOtp(verificationId, userId, "123456"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("not found");
    }

    @Test
    void markConsumed_updatesStatus() {
        UUID verificationId = UUID.randomUUID();
        OtpVerification verification = new OtpVerification(
                UUID.randomUUID(), "PASSWORD_CHANGE", "hash", "payload",
                Instant.now().plusSeconds(300));
        verification.markVerified();

        when(otpVerificationRepository.findById(verificationId))
                .thenReturn(Optional.of(verification));

        otpService.markConsumed(verificationId);

        assertThat(verification.getStatus()).isEqualTo("CONSUMED");
        assertThat(verification.getConsumedAt()).isNotNull();
        verify(otpVerificationRepository).save(verification);
    }
}
