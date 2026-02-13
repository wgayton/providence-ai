package com.providence.identity.repository;

import com.providence.identity.domain.OtpVerification;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

/**
 * Repository for OTP verification lifecycle.
 * Used ONLY in authentication/credential flows — never in profile queries.
 */
public interface OtpVerificationRepository extends JpaRepository<OtpVerification, UUID> {

    Optional<OtpVerification> findByIdAndUserIdAndStatus(UUID id, UUID userId, String status);
}
