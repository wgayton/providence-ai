package com.providence.tenant.service;

import com.providence.common.tenant.TenantMigrationRunner;
import com.providence.tenant.domain.Tenant;
import com.providence.tenant.repository.TenantRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;
import java.sql.SQLException;
import java.util.UUID;

/**
 * Provisions the default "System" tenant on application startup.
 *
 * The System tenant is a well-known tenant used for:
 * - Internal platform operations
 * - Integration test baseline
 * - ENTERPRISE feature reference
 *
 * <p>Provisioning is idempotent — safe to run on every startup.
 * The tenant record is seeded by Flyway migration V008; this provisioner
 * handles schema creation and tenant-specific migrations.</p>
 *
 * @see com.providence.common.tenant.TenantMigrationRunner
 */
@Component
public class SystemTenantProvisioner {

    private static final Logger log = LoggerFactory.getLogger(SystemTenantProvisioner.class);

    public static final UUID SYSTEM_TENANT_ID = UUID.fromString("00000000-0000-0000-0000-000000000000");
    public static final String SYSTEM_TENANT_SLUG = "system";
    public static final String SYSTEM_TENANT_SCHEMA = "t_system";

    private final TenantRepository tenantRepository;
    private final TenantMigrationRunner migrationRunner;
    private final DataSource dataSource;

    public SystemTenantProvisioner(TenantRepository tenantRepository,
                                   TenantMigrationRunner migrationRunner,
                                   DataSource dataSource) {
        this.tenantRepository = tenantRepository;
        this.migrationRunner = migrationRunner;
        this.dataSource = dataSource;
    }

    /**
     * Provisions the system tenant after the application context is ready.
     *
     * This runs after Flyway public-schema migrations have completed,
     * so the system tenant row already exists in {@code public.tenants}.
     *
     * Steps:
     * 1. Verify the system tenant record exists
     * 2. Create the {@code t_system} schema if it doesn't exist
     * 3. Run tenant Flyway migrations on {@code t_system}
     */
    @EventListener(ApplicationReadyEvent.class)
    public void provision() {
        log.info("Provisioning system tenant: slug={}, schema={}", SYSTEM_TENANT_SLUG, SYSTEM_TENANT_SCHEMA);

        verifySystemTenantRecord();
        createSchemaIfNotExists();
        migrationRunner.migrate(SYSTEM_TENANT_SCHEMA);

        log.info("System tenant provisioned successfully: schema={}", SYSTEM_TENANT_SCHEMA);
    }

    private void verifySystemTenantRecord() {
        var tenant = tenantRepository.findBySlug(SYSTEM_TENANT_SLUG);
        if (tenant.isEmpty()) {
            log.warn("System tenant record not found in public.tenants — creating it");
            tenantRepository.save(new Tenant(
                    SYSTEM_TENANT_ID,
                    SYSTEM_TENANT_SLUG,
                    "System",
                    SYSTEM_TENANT_SCHEMA,
                    "ACTIVE",
                    "ENTERPRISE",
                    -1
            ));
        } else {
            log.debug("System tenant record verified: {}", tenant.get());
        }
    }

    private void createSchemaIfNotExists() {
        try (var conn = dataSource.getConnection();
             var stmt = conn.createStatement()) {
            stmt.execute("CREATE SCHEMA IF NOT EXISTS " + SYSTEM_TENANT_SCHEMA);
            log.debug("Schema ensured: {}", SYSTEM_TENANT_SCHEMA);
        } catch (SQLException e) {
            throw new RuntimeException("Failed to create system tenant schema: " + SYSTEM_TENANT_SCHEMA, e);
        }
    }
}
