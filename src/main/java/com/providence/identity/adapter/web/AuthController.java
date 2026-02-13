package com.providence.identity.adapter.web;

import com.providence.identity.dto.ChangePasswordRequest;
import com.providence.identity.dto.ChangePasswordResponse;
import com.providence.identity.service.CredentialService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

/**
 * REST controller for authentication operations.
 *
 * PROV-109: Password change only modifies credentials — never touches user_profiles.
 * Full auth endpoints (register, login) will be added in PROV-101/PROV-102.
 *
 * Note: Authentication (JWT) will be added in PROV-102/PROV-106.
 * Current user ID is passed via X-User-ID header for development.
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final CredentialService credentialService;

    public AuthController(CredentialService credentialService) {
        this.credentialService = credentialService;
    }

    /**
     * POST /api/v1/auth/password/change — Change password.
     * Only modifies credentials table — never touches user_profiles.
     */
    @PostMapping("/password/change")
    public ResponseEntity<ChangePasswordResponse> changePassword(
            @RequestHeader("X-User-ID") UUID userId,
            @Valid @RequestBody ChangePasswordRequest request) {
        ChangePasswordResponse response = credentialService.changePassword(userId, request);
        return ResponseEntity.ok(response);
    }
}
