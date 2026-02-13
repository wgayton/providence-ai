package com.providence.identity.service;

import com.providence.identity.domain.User;
import com.providence.identity.domain.UserProfile;
import com.providence.identity.dto.UpdateProfileRequest;
import com.providence.identity.dto.UserProfileResponse;
import com.providence.identity.repository.UserProfileRepository;
import com.providence.identity.repository.UserRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * User profile service — reads and writes ONLY UserProfile data.
 *
 * PROV-109: This service has NO dependency on CredentialRepository.
 * Profile operations never touch the credentials table.
 */
@Service
public class UserService {

    private static final Logger log = LoggerFactory.getLogger(UserService.class);

    private final UserRepository userRepository;
    private final UserProfileRepository userProfileRepository;

    public UserService(UserRepository userRepository,
                       UserProfileRepository userProfileRepository) {
        this.userRepository = userRepository;
        this.userProfileRepository = userProfileRepository;
    }

    /**
     * Get user profile by user ID.
     * Reads from user_profiles table ONLY — never touches credentials.
     */
    @Transactional(readOnly = true)
    public UserProfileResponse getProfile(UUID userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + userId));

        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new IllegalArgumentException("Profile not found for user: " + userId));

        return toResponse(profile, user);
    }

    /**
     * Update user profile.
     * Writes to user_profiles table ONLY — never touches credentials.
     */
    @Transactional
    public UserProfileResponse updateProfile(UUID userId, UpdateProfileRequest request) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + userId));

        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new IllegalArgumentException("Profile not found for user: " + userId));

        profile.updateProfile(
                request.firstName(),
                request.lastName(),
                request.displayName(),
                request.phone(),
                request.timezone(),
                request.locale(),
                request.bio()
        );

        userProfileRepository.save(profile);
        log.info("Profile updated: userId={}", userId);

        return toResponse(profile, user);
    }

    /**
     * List all active user profiles (admin operation).
     * Returns profile data ONLY — never includes credential fields.
     */
    @Transactional(readOnly = true)
    public Page<UserProfileResponse> listActiveProfiles(Pageable pageable) {
        return userProfileRepository.findAllActiveProfiles(pageable)
                .map(profile -> {
                    User user = userRepository.findById(profile.getUserId()).orElse(null);
                    return toResponse(profile, user);
                });
    }

    private UserProfileResponse toResponse(UserProfile profile, User user) {
        return new UserProfileResponse(
                profile.getUserId(),
                profile.getDisplayName(),
                profile.getFirstName(),
                profile.getLastName(),
                profile.getEmail(),
                profile.getPhone(),
                profile.getTimezone(),
                profile.getLocale(),
                profile.getBio(),
                user != null ? user.getStatus() : null,
                profile.getCreatedAt()
        );
    }
}
