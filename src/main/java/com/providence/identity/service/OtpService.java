package com.providence.identity.service;

import com.providence.identity.domain.OtpVerification;
import com.providence.identity.repository.OtpVerificationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

/**
 * OTP generation, storage, and verification service.
 *
 * Generates 6-digit OTP codes, stores BCrypt hashes, and enforces
 * expiration and max-attempt limits.
 *
 * Delivery (email/SMS) is handled externally (PROV-110).
 */
@Service
public class OtpService {

    private static final Logger log = LoggerFactory.getLogger(OtpService.class);
    private static final Duration OTP_TTL = Duration.ofMinutes(5);
    private static final int OTP_LENGTH = 6;

    private final OtpVerificationRepository otpVerificationRepository;
    private final PasswordEncoder otpEncoder;
    private final SecureRandom secureRandom;

    public OtpService(OtpVerificationRepository otpVerificationRepository) {
        this.otpVerificationRepository = otpVerificationRepository;
        this.otpEncoder = new BCryptPasswordEncoder();
        this.secureRandom = new SecureRandom();
    }

    /**
     * Generate a new OTP, hash it, and store a pending verification record.
     *
     * @return result containing the verification ID and plain OTP (for delivery)
     */
    @Transactional
    public OtpGenerationResult generateAndStore(UUID userId, String operationType, String payload) {
        String plainOtp = generateOtp();
        String otpHash = otpEncoder.encode(plainOtp);

        OtpVerification verification = new OtpVerification(
                userId, operationType, otpHash, payload,
                Instant.now().plus(OTP_TTL));
        otpVerificationRepository.save(verification);

        log.info("OTP generated: userId={}, operation={}, verificationId={}",
                userId, operationType, verification.getId());

        return new OtpGenerationResult(verification.getId(), plainOtp);
    }

    /**
     * Verify an OTP code against a pending verification record.
     *
     * @throws IllegalArgumentException if verification not found, expired, or OTP incorrect
     * @throws IllegalStateException if max attempts exceeded
     */
    @Transactional
    public OtpVerification verifyOtp(UUID verificationId, UUID userId, String otpCode) {
        OtpVerification verification = otpVerificationRepository
                .findByIdAndUserIdAndStatus(verificationId, userId, "PENDING")
                .orElseThrow(() -> new IllegalArgumentException(
                        "Verification not found or already completed"));

        if (verification.isExpired()) {
            throw new IllegalArgumentException("OTP has expired. Please request a new one.");
        }

        if (verification.isMaxAttemptsExceeded()) {
            throw new IllegalStateException("Maximum OTP attempts exceeded. Please request a new one.");
        }

        if (!otpEncoder.matches(otpCode, verification.getOtpHash())) {
            verification.recordFailedAttempt();
            otpVerificationRepository.save(verification);
            throw new IllegalArgumentException("Invalid OTP code. "
                    + (verification.getMaxAttempts() - verification.getAttemptCount())
                    + " attempts remaining.");
        }

        verification.markVerified();
        otpVerificationRepository.save(verification);

        log.info("OTP verified: userId={}, verificationId={}", userId, verificationId);
        return verification;
    }

    /**
     * Mark a verified OTP as consumed after the operation completes.
     */
    @Transactional
    public void markConsumed(UUID verificationId) {
        otpVerificationRepository.findById(verificationId).ifPresent(v -> {
            v.markConsumed();
            otpVerificationRepository.save(v);
        });
    }

    private String generateOtp() {
        int bound = (int) Math.pow(10, OTP_LENGTH);
        int otp = secureRandom.nextInt(bound);
        return String.format("%0" + OTP_LENGTH + "d", otp);
    }

    /**
     * Result of OTP generation — contains the verification ID and the plain OTP
     * (plain OTP is needed for delivery via email/SMS).
     */
    public record OtpGenerationResult(UUID verificationId, String plainOtp) {}
}
