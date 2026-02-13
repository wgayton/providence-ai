package com.providence.identity.service;

import com.providence.identity.domain.Credential;
import com.providence.identity.dto.ChangePasswordRequest;
import com.providence.identity.dto.ChangePasswordResponse;
import com.providence.identity.repository.CredentialRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Unit tests for CredentialService.
 *
 * PROV-109: Verifies that CredentialService reads/writes ONLY Credential data
 * and has NO dependency on UserProfileRepository.
 */
@ExtendWith(MockitoExtension.class)
class CredentialServiceTest {

    @Mock
    private CredentialRepository credentialRepository;

    @InjectMocks
    private CredentialService credentialService;

    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

    @Test
    void changePassword_updatesOnlyCredentials() {
        UUID userId = UUID.randomUUID();
        String currentPassword = "OldP@ssw0rd123";
        String currentHash = encoder.encode(currentPassword);
        Credential credential = new Credential(userId, "jane@example.com", currentHash);

        when(credentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));
        when(credentialRepository.save(any(Credential.class))).thenAnswer(inv -> inv.getArgument(0));

        ChangePasswordRequest request = new ChangePasswordRequest(
                currentPassword, "NewSecureP@ss456");

        ChangePasswordResponse response = credentialService.changePassword(userId, request);

        assertThat(response.message()).isEqualTo("Password changed successfully.");
        assertThat(response.changedAt()).isNotNull();
        verify(credentialRepository).save(any(Credential.class));
    }

    @Test
    void changePassword_rejectsIncorrectCurrentPassword() {
        UUID userId = UUID.randomUUID();
        String currentHash = encoder.encode("ActualPassword123");
        Credential credential = new Credential(userId, "jane@example.com", currentHash);

        when(credentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));

        ChangePasswordRequest request = new ChangePasswordRequest(
                "WrongPassword123", "NewSecureP@ss456");

        assertThatThrownBy(() -> credentialService.changePassword(userId, request))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessage("Current password is incorrect");

        verify(credentialRepository, never()).save(any());
    }

    @Test
    void changePassword_doesNotCallUserProfileRepository() {
        UUID userId = UUID.randomUUID();
        String currentPassword = "OldP@ssw0rd123";
        String currentHash = encoder.encode(currentPassword);
        Credential credential = new Credential(userId, "jane@example.com", currentHash);

        when(credentialRepository.findByUserId(userId)).thenReturn(Optional.of(credential));
        when(credentialRepository.save(any(Credential.class))).thenAnswer(inv -> inv.getArgument(0));

        ChangePasswordRequest request = new ChangePasswordRequest(
                currentPassword, "NewSecureP@ss456");

        credentialService.changePassword(userId, request);

        // PROV-109: CredentialService.changePassword() must not call UserProfileRepository
        // Since UserProfileRepository is not even a dependency of CredentialService,
        // this is enforced structurally — no mock is injected.
        verify(credentialRepository).findByUserId(userId);
        verify(credentialRepository).save(any(Credential.class));
        verifyNoMoreInteractions(credentialRepository);
    }

    @Test
    void credentialService_hasNoUserProfileRepositoryDependency() {
        // Structural verification: CredentialService constructor takes only
        // CredentialRepository — no UserProfileRepository.
        var constructors = CredentialService.class.getConstructors();
        assertThat(constructors).hasSize(1);

        var paramTypes = constructors[0].getParameterTypes();
        for (Class<?> type : paramTypes) {
            assertThat(type.getSimpleName())
                    .as("CredentialService should not depend on UserProfileRepository")
                    .doesNotContain("UserProfile");
        }
    }
}
