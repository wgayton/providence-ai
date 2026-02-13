package com.providence.identity.adapter.web;

import com.providence.identity.dto.UpdateProfileRequest;
import com.providence.identity.dto.UserProfileResponse;
import com.providence.identity.service.UserService;
import jakarta.validation.Valid;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

/**
 * REST controller for user profile operations.
 *
 * PROV-109: All responses contain ONLY profile data — never credential fields.
 * Credential separation enforced by DTO design (UserProfileResponse record).
 *
 * Note: Authentication (JWT) will be added in PROV-102/PROV-106.
 * Current user ID is passed via X-User-ID header for development.
 */
@RestController
@RequestMapping("/api/v1/users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    /**
     * GET /api/v1/users/me — Current user's profile.
     * Returns profile + status but NEVER credential fields.
     */
    @GetMapping("/me")
    public ResponseEntity<UserProfileResponse> getMyProfile(
            @RequestHeader("X-User-ID") UUID userId) {
        UserProfileResponse profile = userService.getProfile(userId);
        return ResponseEntity.ok(profile);
    }

    /**
     * PUT /api/v1/users/me — Update current user's profile.
     * Only modifies user_profiles table — never touches credentials.
     */
    @PutMapping("/me")
    public ResponseEntity<UserProfileResponse> updateMyProfile(
            @RequestHeader("X-User-ID") UUID userId,
            @Valid @RequestBody UpdateProfileRequest request) {
        UserProfileResponse profile = userService.updateProfile(userId, request);
        return ResponseEntity.ok(profile);
    }

    /**
     * GET /api/v1/users — List all active user profiles (admin).
     * Response NEVER includes credential fields for any user.
     */
    @GetMapping
    public ResponseEntity<Page<UserProfileResponse>> listUsers(Pageable pageable) {
        Page<UserProfileResponse> profiles = userService.listActiveProfiles(pageable);
        return ResponseEntity.ok(profiles);
    }
}
