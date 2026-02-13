package com.providence.identity.service;

import com.providence.identity.domain.User;
import com.providence.identity.domain.UserProfile;
import com.providence.identity.dto.UpdateProfileRequest;
import com.providence.identity.dto.UserProfileResponse;
import com.providence.identity.repository.UserProfileRepository;
import com.providence.identity.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/**
 * Unit tests for UserService.
 *
 * PROV-109: Verifies that UserService reads/writes ONLY UserProfile data
 * and has NO dependency on CredentialRepository.
 */
@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private UserProfileRepository userProfileRepository;

    @InjectMocks
    private UserService userService;

    @Test
    void getProfile_returnsProfileDataOnly() {
        UUID userId = UUID.randomUUID();
        User user = new User("ACTIVE");
        UserProfile profile = new UserProfile(userId, "Jane Doe", "jane@example.com");

        when(userRepository.findById(userId)).thenReturn(Optional.of(user));
        when(userProfileRepository.findByUserId(userId)).thenReturn(Optional.of(profile));

        UserProfileResponse response = userService.getProfile(userId);

        assertThat(response.userId()).isEqualTo(userId);
        assertThat(response.displayName()).isEqualTo("Jane Doe");
        assertThat(response.email()).isEqualTo("jane@example.com");
        assertThat(response.status()).isEqualTo("ACTIVE");
    }

    @Test
    void getProfile_doesNotCallCredentialRepository() {
        UUID userId = UUID.randomUUID();
        User user = new User("ACTIVE");
        UserProfile profile = new UserProfile(userId, "Jane Doe", "jane@example.com");

        when(userRepository.findById(userId)).thenReturn(Optional.of(user));
        when(userProfileRepository.findByUserId(userId)).thenReturn(Optional.of(profile));

        userService.getProfile(userId);

        // PROV-109: UserService.getProfile() must not call CredentialRepository
        // Since CredentialRepository is not even a dependency of UserService,
        // this is enforced structurally — no mock is injected.
        verify(userProfileRepository).findByUserId(userId);
        verifyNoMoreInteractions(userProfileRepository);
    }

    @Test
    void updateProfile_modifiesOnlyProfileFields() {
        UUID userId = UUID.randomUUID();
        User user = new User("ACTIVE");
        UserProfile profile = new UserProfile(userId, "Jane Doe", "jane@example.com");

        when(userRepository.findById(userId)).thenReturn(Optional.of(user));
        when(userProfileRepository.findByUserId(userId)).thenReturn(Optional.of(profile));
        when(userProfileRepository.save(any(UserProfile.class))).thenAnswer(inv -> inv.getArgument(0));

        UpdateProfileRequest request = new UpdateProfileRequest(
                "Jane", "Smith", "Jane Smith",
                "+1-555-0100", "America/New_York", null, null);

        UserProfileResponse response = userService.updateProfile(userId, request);

        assertThat(response.firstName()).isEqualTo("Jane");
        assertThat(response.lastName()).isEqualTo("Smith");
        assertThat(response.displayName()).isEqualTo("Jane Smith");

        verify(userProfileRepository).save(any(UserProfile.class));
        verify(userRepository, never()).save(any());
    }

    @Test
    void userService_hasNoCredentialRepositoryDependency() {
        // Structural verification: UserService constructor takes only
        // UserRepository and UserProfileRepository — no CredentialRepository.
        var constructors = UserService.class.getConstructors();
        assertThat(constructors).hasSize(1);

        var paramTypes = constructors[0].getParameterTypes();
        for (Class<?> type : paramTypes) {
            assertThat(type.getSimpleName())
                    .as("UserService should not depend on CredentialRepository")
                    .doesNotContain("Credential");
        }
    }
}
