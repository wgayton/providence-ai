package com.providence.identity.service;

import com.providence.identity.domain.Credential;
import com.providence.identity.domain.OtpVerification;
import com.providence.identity.dto.ChangePasswordRequest;
import com.providence.identity.dto.ChangePasswordResponse;
import com.providence.identity.dto.ConfirmPasswordChangeRequest;
import com.providence.identity.dto.ConfirmPasswordChangeResponse;
import com.providence.identity.repository.CredentialRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * Credential service — reads and writes ONLY Credential data.
 *
 * PROV-109: This service has NO dependency on UserProfileRepository.
 * Password operations never touch the user_profiles table.
 *
 * Password changes follow a two-step OTP verification lifecycle:
 *   Step 1 (initiate): Verify current password → generate OTP → return verificationId
 *   Step 2 (confirm):  Verify OTP → apply new password
 */
@Service
public class CredentialService {

    private static final Logger log = LoggerFactory.getLogger(CredentialService.class);
    private static final String PASSWORD_CHANGE_OPERATION = "PASSWORD_CHANGE";

    private final CredentialRepository credentialRepository;
    private final OtpService otpService;
    private final PasswordEncoder passwordEncoder;

    public CredentialService(CredentialRepository credentialRepository, OtpService otpService) {
        this.credentialRepository = credentialRepository;
        this.otpService = otpService;
        this.passwordEncoder = new BCryptPasswordEncoder();
    }

    /**
     * Step 1: Initiate password change.
     *
     * Verifies the current password, hashes the new password, generates an OTP,
     * and stores a pending verification. The password is NOT changed yet.
     *
     * @return response with verificationId and OTP (OTP for dev; delivery via PROV-110)
     */
    @Transactional
    public ChangePasswordResponse initiatePasswordChange(UUID userId, ChangePasswordRequest request) {
        Credential credential = credentialRepository.findByUserId(userId)
                .orElseThrow(() -> new IllegalArgumentException("Credential not found for user: " + userId));

        if (!passwordEncoder.matches(request.currentPassword(), credential.getPasswordHash())) {
            throw new IllegalArgumentException("Current password is incorrect");
        }

        String newPasswordHash = passwordEncoder.encode(request.newPassword());

        OtpService.OtpGenerationResult otpResult = otpService.generateAndStore(
                userId, PASSWORD_CHANGE_OPERATION, newPasswordHash);

        log.info("Password change initiated: userId={}, verificationId={}",
                userId, otpResult.verificationId());

        return new ChangePasswordResponse(
                "OTP sent. Please verify to complete password change.",
                otpResult.verificationId(),
                otpResult.plainOtp()
        );
    }

    /**
     * Step 2: Confirm password change with OTP.
     *
     * Verifies the OTP, retrieves the pending new password hash,
     * and applies the password change.
     *
     * @return response confirming the password was changed
     */
    @Transactional
    public ConfirmPasswordChangeResponse confirmPasswordChange(UUID userId,
                                                                ConfirmPasswordChangeRequest request) {
        OtpVerification verification = otpService.verifyOtp(
                request.verificationId(), userId, request.otpCode());

        Credential credential = credentialRepository.findByUserId(userId)
                .orElseThrow(() -> new IllegalArgumentException("Credential not found for user: " + userId));

        String newPasswordHash = verification.getPayload();
        credential.changePassword(newPasswordHash);
        credentialRepository.save(credential);

        otpService.markConsumed(verification.getId());

        log.info("Password changed: userId={}, verificationId={}", userId, verification.getId());

        return new ConfirmPasswordChangeResponse(
                "Password changed successfully.",
                credential.getPasswordChangedAt()
        );
    }
}
