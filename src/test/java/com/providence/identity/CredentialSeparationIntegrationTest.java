package com.providence.identity;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.json.JsonMapper;
import com.providence.identity.domain.Credential;
import com.providence.identity.domain.User;
import com.providence.identity.domain.UserProfile;
import com.providence.identity.repository.CredentialRepository;
import com.providence.identity.repository.UserProfileRepository;
import com.providence.identity.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.UUID;

import static org.hamcrest.Matchers.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Integration tests verifying credential/profile separation in API responses.
 *
 * PROV-109: Ensures that credential fields NEVER appear in profile endpoints
 * and that profile updates NEVER touch the credentials table.
 *
 * Requires Docker (Testcontainers).
 */
@SpringBootTest
@AutoConfigureMockMvc
@Testcontainers
class CredentialSeparationIntegrationTest {

    @Container
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:17-alpine")
            .withDatabaseName("providence_test")
            .withUsername("postgres")
            .withPassword("postgres");

    @DynamicPropertySource
    static void configureProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", postgres::getJdbcUrl);
        registry.add("spring.datasource.username", postgres::getUsername);
        registry.add("spring.datasource.password", postgres::getPassword);
    }

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private CredentialRepository credentialRepository;

    @Autowired
    private UserProfileRepository userProfileRepository;

    @Autowired
    private JsonMapper jsonMapper;

    private UUID testUserId;
    private final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder();

    @BeforeEach
    void setUp() {
        // Seed test data directly — registration flow comes in PROV-101
        User user = new User("ACTIVE");
        userRepository.save(user);
        testUserId = user.getId();

        Credential credential = new Credential(
                testUserId, "jane@example.com",
                encoder.encode("SecureP@ssw0rd123"));
        credentialRepository.save(credential);

        UserProfile profile = new UserProfile(
                testUserId, "Jane Doe", "jane@example.com");
        userProfileRepository.save(profile);
    }

    /**
     * GET /api/v1/users/me — response must NOT contain credential fields.
     */
    @Test
    void getMyProfile_responseDoesNotContainCredentialFields() throws Exception {
        mockMvc.perform(get("/api/v1/users/me")
                        .header("X-User-ID", testUserId.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId").value(testUserId.toString()))
                .andExpect(jsonPath("$.displayName").value("Jane Doe"))
                .andExpect(jsonPath("$.email").value("jane@example.com"))
                .andExpect(jsonPath("$.status").value("ACTIVE"))
                // PROV-109: Credential fields must NEVER appear
                .andExpect(jsonPath("$.passwordHash").doesNotExist())
                .andExpect(jsonPath("$.password_hash").doesNotExist())
                .andExpect(jsonPath("$.otpSecret").doesNotExist())
                .andExpect(jsonPath("$.otp_secret").doesNotExist())
                .andExpect(jsonPath("$.failedAttemptCount").doesNotExist())
                .andExpect(jsonPath("$.failed_attempt_count").doesNotExist())
                .andExpect(jsonPath("$.lockedUntil").doesNotExist())
                .andExpect(jsonPath("$.locked_until").doesNotExist());
    }

    /**
     * GET /api/v1/users — admin list must NOT contain credential fields.
     */
    @Test
    void listUsers_responseDoesNotContainCredentialFields() throws Exception {
        mockMvc.perform(get("/api/v1/users")
                        .param("page", "0")
                        .param("size", "20"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content[0].passwordHash").doesNotExist())
                .andExpect(jsonPath("$.content[0].password_hash").doesNotExist())
                .andExpect(jsonPath("$.content[0].otpSecret").doesNotExist())
                .andExpect(jsonPath("$.content[0].otp_secret").doesNotExist())
                .andExpect(jsonPath("$.content[0].failedAttemptCount").doesNotExist())
                .andExpect(jsonPath("$.content[0].lockedUntil").doesNotExist());
    }

    /**
     * PUT /api/v1/users/me — must only modify user_profiles, not credentials.
     */
    @Test
    void updateProfile_doesNotModifyCredentials() throws Exception {
        Credential beforeUpdate = credentialRepository.findByUserId(testUserId).orElseThrow();
        String hashBefore = beforeUpdate.getPasswordHash();

        mockMvc.perform(put("/api/v1/users/me")
                        .header("X-User-ID", testUserId.toString())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                            {
                                "firstName": "Jane",
                                "lastName": "Smith",
                                "displayName": "Jane Smith"
                            }
                            """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.displayName").value("Jane Smith"));

        // Verify credentials table is unchanged
        Credential afterUpdate = credentialRepository.findByUserId(testUserId).orElseThrow();
        org.assertj.core.api.Assertions.assertThat(afterUpdate.getPasswordHash())
                .isEqualTo(hashBefore);
    }

    /**
     * Two-step OTP password change must only modify credentials, not user_profiles.
     *
     * Step 1: POST /api/v1/auth/password/change → returns verificationId + OTP
     * Step 2: POST /api/v1/auth/password/change/confirm → applies password change
     */
    @Test
    void changePassword_otpLifecycle_doesNotModifyProfile() throws Exception {
        UserProfile beforeChange = userProfileRepository.findByUserId(testUserId).orElseThrow();
        String displayNameBefore = beforeChange.getDisplayName();

        // Step 1: Initiate password change — verify current password, get OTP
        MvcResult initiateResult = mockMvc.perform(post("/api/v1/auth/password/change")
                        .header("X-User-ID", testUserId.toString())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                            {
                                "currentPassword": "SecureP@ssw0rd123",
                                "newPassword": "NewSecureP@ss456"
                            }
                            """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.verificationId").exists())
                .andExpect(jsonPath("$.otp").exists())
                .andReturn();

        // Extract verificationId and OTP from Step 1 response
        JsonNode initiateBody = jsonMapper.readTree(
                initiateResult.getResponse().getContentAsString());
        String verificationId = initiateBody.get("verificationId").asText();
        String otp = initiateBody.get("otp").asText();

        // Step 2: Confirm password change with OTP
        mockMvc.perform(post("/api/v1/auth/password/change/confirm")
                        .header("X-User-ID", testUserId.toString())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                            {
                                "verificationId": "%s",
                                "otpCode": "%s"
                            }
                            """.formatted(verificationId, otp)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message").value("Password changed successfully."))
                .andExpect(jsonPath("$.changedAt").exists());

        // Verify user_profiles table is unchanged after full OTP lifecycle
        UserProfile afterChange = userProfileRepository.findByUserId(testUserId).orElseThrow();
        org.assertj.core.api.Assertions.assertThat(afterChange.getDisplayName())
                .isEqualTo(displayNameBefore);

        // Verify password was actually changed
        Credential afterCred = credentialRepository.findByUserId(testUserId).orElseThrow();
        org.assertj.core.api.Assertions.assertThat(
                encoder.matches("NewSecureP@ss456", afterCred.getPasswordHash())).isTrue();
    }

    /**
     * Password change initiate response must not expose credential data.
     * It should only contain message, verificationId, and OTP.
     */
    @Test
    void changePasswordInitiate_responseDoesNotExposeCredentials() throws Exception {
        mockMvc.perform(post("/api/v1/auth/password/change")
                        .header("X-User-ID", testUserId.toString())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                            {
                                "currentPassword": "SecureP@ssw0rd123",
                                "newPassword": "NewSecureP@ss456"
                            }
                            """))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.passwordHash").doesNotExist())
                .andExpect(jsonPath("$.password_hash").doesNotExist())
                .andExpect(jsonPath("$.otpSecret").doesNotExist())
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.verificationId").exists())
                .andExpect(jsonPath("$.otp").exists());
    }

    /**
     * Password change confirm response must not expose credential data.
     * It should only contain message and changedAt.
     */
    @Test
    void changePasswordConfirm_responseDoesNotExposeCredentials() throws Exception {
        // Step 1: Initiate to get verificationId and OTP
        MvcResult initiateResult = mockMvc.perform(post("/api/v1/auth/password/change")
                        .header("X-User-ID", testUserId.toString())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                            {
                                "currentPassword": "SecureP@ssw0rd123",
                                "newPassword": "NewSecureP@ss456"
                            }
                            """))
                .andExpect(status().isOk())
                .andReturn();

        JsonNode initiateBody = jsonMapper.readTree(
                initiateResult.getResponse().getContentAsString());
        String verificationId = initiateBody.get("verificationId").asText();
        String otp = initiateBody.get("otp").asText();

        // Step 2: Confirm and verify response fields
        mockMvc.perform(post("/api/v1/auth/password/change/confirm")
                        .header("X-User-ID", testUserId.toString())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                            {
                                "verificationId": "%s",
                                "otpCode": "%s"
                            }
                            """.formatted(verificationId, otp)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.passwordHash").doesNotExist())
                .andExpect(jsonPath("$.password_hash").doesNotExist())
                .andExpect(jsonPath("$.otpSecret").doesNotExist())
                .andExpect(jsonPath("$.newPasswordHash").doesNotExist())
                .andExpect(jsonPath("$.message").exists())
                .andExpect(jsonPath("$.changedAt").exists());
    }
}
