package com.providence.identity.service;

import com.providence.identity.domain.Credential;
import com.providence.identity.dto.ChangePasswordRequest;
import com.providence.identity.dto.ChangePasswordResponse;
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
 */
@Service
public class CredentialService {

    private static final Logger log = LoggerFactory.getLogger(CredentialService.class);

    private final CredentialRepository credentialRepository;
    private final PasswordEncoder passwordEncoder;

    public CredentialService(CredentialRepository credentialRepository) {
        this.credentialRepository = credentialRepository;
        this.passwordEncoder = new BCryptPasswordEncoder();
    }

    /**
     * Change password for a user.
     * Writes to credentials table ONLY — never touches user_profiles.
     */
    @Transactional
    public ChangePasswordResponse changePassword(UUID userId, ChangePasswordRequest request) {
        Credential credential = credentialRepository.findByUserId(userId)
                .orElseThrow(() -> new IllegalArgumentException("Credential not found for user: " + userId));

        if (!passwordEncoder.matches(request.currentPassword(), credential.getPasswordHash())) {
            throw new IllegalArgumentException("Current password is incorrect");
        }

        String newHash = passwordEncoder.encode(request.newPassword());
        credential.changePassword(newHash);
        credentialRepository.save(credential);

        log.info("Password changed: userId={}", userId);

        return new ChangePasswordResponse(
                "Password changed successfully.",
                credential.getPasswordChangedAt()
        );
    }
}
