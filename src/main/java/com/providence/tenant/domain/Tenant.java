package com.providence.tenant.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;

/**
 * Tenant entity — maps to {@code public.tenants}.
 *
 * Represents a tenant in the multi-tenant SaaS platform.
 * Each tenant has a dedicated PostgreSQL schema (t_<slug>)
 * for complete data isolation.
 *
 * <p>This entity is in the public schema and is accessible
 * regardless of the current tenant context.</p>
 */
@Entity
@Table(name = "tenants", schema = "public")
public class Tenant {

    @Id
    private UUID id;

    @Column(nullable = false, unique = true, length = 50)
    private String slug;

    @Column(nullable = false, length = 100)
    private String name;

    @Column(name = "schema_name", nullable = false, unique = true, length = 63)
    private String schemaName;

    @Column(nullable = false, length = 20)
    private String status;

    @Column(name = "subscription_tier", length = 50)
    private String subscriptionTier;

    @Column(name = "max_users")
    private Integer maxUsers;

    @Column(name = "max_storage_gb")
    private Integer maxStorageGb;

    @Column(name = "contact_email", length = 255)
    private String contactEmail;

    @Column(name = "contact_phone", length = 50)
    private String contactPhone;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    protected Tenant() {}

    public Tenant(UUID id, String slug, String name, String schemaName,
                  String status, String subscriptionTier, Integer maxUsers) {
        this.id = id;
        this.slug = slug;
        this.name = name;
        this.schemaName = schemaName;
        this.status = status;
        this.subscriptionTier = subscriptionTier;
        this.maxUsers = maxUsers;
        this.createdAt = Instant.now();
        this.updatedAt = Instant.now();
    }

    public UUID getId() { return id; }
    public String getSlug() { return slug; }
    public String getName() { return name; }
    public String getSchemaName() { return schemaName; }
    public String getStatus() { return status; }
    public String getSubscriptionTier() { return subscriptionTier; }
    public Integer getMaxUsers() { return maxUsers; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }

    @Override
    public String toString() {
        return "Tenant{id=" + id + ", slug='" + slug + "', schema='" + schemaName + "'}";
    }
}
