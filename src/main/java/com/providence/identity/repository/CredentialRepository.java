package com.providence.identity.repository;

import com.providence.identity.domain.Credential;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

/**
 * Repository for Credential entity.
 *
 * Used ONLY in authentication flows (login, password change, lockout).
 * NEVER used in profile-facing queries or controllers.
 */
public interface CredentialRepository extends JpaRepository<Credential, UUID> {

    Optional<Credential> findByEmail(String email);

    Optional<Credential> findByUserId(UUID userId);

    boolean existsByEmail(String email);
}
