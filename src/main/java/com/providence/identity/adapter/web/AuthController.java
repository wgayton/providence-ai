package com.providence.identity.adapter.web;

import com.providence.identity.dto.ChangePasswordRequest;
import com.providence.identity.dto.ChangePasswordResponse;
import com.providence.identity.dto.ConfirmPasswordChangeRequest;
import com.providence.identity.dto.ConfirmPasswordChangeResponse;
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
 * Password change follows two-step OTP verification lifecycle:
 *   POST /api/v1/auth/password/change          → Initiate (verify password, generate OTP)
 *   POST /api/v1/auth/password/change/confirm   → Confirm (verify OTP, apply change)
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
     * Step 1: Initiate password change.
     *
     * Verifies the current password, generates an OTP, and returns a verification ID.
     * The password is NOT changed until the OTP is confirmed in Step 2.
     */
    @PostMapping("/password/change")
    public ResponseEntity<ChangePasswordResponse> initiatePasswordChange(
            @RequestHeader("X-User-ID") UUID userId,
            @Valid @RequestBody ChangePasswordRequest request) {
        ChangePasswordResponse response = credentialService.initiatePasswordChange(userId, request);
        return ResponseEntity.ok(response);
    }

    /**
     * Step 2: Confirm password change with OTP.
     *
     * Verifies the OTP code against the pending verification, then applies the
     * password change. Only modifies credentials table — never touches user_profiles.
     */
    @PostMapping("/password/change/confirm")
    public ResponseEntity<ConfirmPasswordChangeResponse> confirmPasswordChange(
            @RequestHeader("X-User-ID") UUID userId,
            @Valid @RequestBody ConfirmPasswordChangeRequest request) {
        ConfirmPasswordChangeResponse response = credentialService.confirmPasswordChange(userId, request);
        return ResponseEntity.ok(response);
    }
}
