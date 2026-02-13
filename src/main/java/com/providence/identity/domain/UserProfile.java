package com.providence.identity.domain;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/**
 * User profile entity — personal information safe for API responses.
 *
 * Contains ONLY: name, email, phone, preferences, bio.
 * NEVER contains credential data (password, OTP, lockout state).
 *
 * Lives in tenant schema (t_<tenant>).
 * No bidirectional JPA relationship with Credential.
 */
@Entity
@Table(name = "user_profiles")
public class UserProfile {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "user_id", nullable = false, unique = true)
    private UUID userId;

    @Column(name = "first_name", length = 100)
    private String firstName;

    @Column(name = "last_name", length = 100)
    private String lastName;

    @Column(name = "display_name", nullable = false, length = 255)
    private String displayName;

    @Column(nullable = false, length = 255)
    private String email;

    @Column(length = 50)
    private String phone;

    @Column(length = 50)
    private String timezone;

    @Column(length = 10)
    private String locale;

    @Column(columnDefinition = "TEXT")
    private String bio;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected UserProfile() {}

    public UserProfile(UUID userId, String displayName, String email) {
        this.id = UUID.randomUUID();
        this.userId = userId;
        this.displayName = displayName;
        this.email = email;
        this.timezone = "UTC";
        this.locale = "en-US";
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public void updateProfile(String firstName, String lastName, String displayName,
                              String phone, String timezone, String locale, String bio) {
        if (firstName != null) this.firstName = firstName;
        if (lastName != null) this.lastName = lastName;
        if (displayName != null) this.displayName = displayName;
        if (phone != null) this.phone = phone;
        if (timezone != null) this.timezone = timezone;
        if (locale != null) this.locale = locale;
        if (bio != null) this.bio = bio;
        this.updatedAt = Instant.now();
    }

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public String getFirstName() { return firstName; }
    public String getLastName() { return lastName; }
    public String getDisplayName() { return displayName; }
    public String getEmail() { return email; }
    public String getPhone() { return phone; }
    public String getTimezone() { return timezone; }
    public String getLocale() { return locale; }
    public String getBio() { return bio; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
}
