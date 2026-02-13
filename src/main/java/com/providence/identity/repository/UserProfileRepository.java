package com.providence.identity.repository;

import com.providence.identity.domain.UserProfile;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;
import java.util.UUID;

/**
 * Repository for UserProfile entity.
 *
 * Used ONLY in profile-facing queries and controllers.
 * NEVER joins with or fetches Credential data.
 */
public interface UserProfileRepository extends JpaRepository<UserProfile, UUID> {

    Optional<UserProfile> findByUserId(UUID userId);

    @Query("""
        SELECT p FROM UserProfile p
        JOIN User u ON u.id = p.userId
        WHERE u.status = 'ACTIVE'
        """)
    Page<UserProfile> findAllActiveProfiles(Pageable pageable);
}
