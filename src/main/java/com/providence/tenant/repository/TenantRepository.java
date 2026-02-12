package com.providence.tenant.repository;

import com.providence.tenant.domain.Tenant;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Repository for {@link Tenant} entities in the public schema.
 *
 * Used for tenant resolution, provisioning, and administration.
 * Schema-per-tenant: queries always target {@code public.tenants}.
 */
public interface TenantRepository extends JpaRepository<Tenant, UUID> {

    Optional<Tenant> findBySlug(String slug);

    Optional<Tenant> findBySchemaName(String schemaName);

    boolean existsBySlug(String slug);

    @Query("SELECT t FROM Tenant t WHERE t.status = 'ACTIVE'")
    List<Tenant> findAllActive();
}
