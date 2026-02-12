package com.providence.common.tenant;

import org.flywaydb.core.Flyway;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.sql.DataSource;

/**
 * Runs Flyway migrations on individual tenant schemas.
 *
 * Each tenant schema (t_<slug>) gets its own set of migrations from
 * the tenant migration location. This is called during:
 * - System tenant provisioning (startup)
 * - New tenant provisioning (on-demand)
 */
@Component
public class TenantMigrationRunner {

    private static final Logger log = LoggerFactory.getLogger(TenantMigrationRunner.class);

    private final DataSource dataSource;
    private final String migrationLocations;

    public TenantMigrationRunner(
            DataSource dataSource,
            @Value("${providence.tenant.migration.locations}") String migrationLocations) {
        this.dataSource = dataSource;
        this.migrationLocations = migrationLocations;
    }

    /**
     * Run all tenant Flyway migrations on the given schema.
     *
     * @param schemaName the tenant schema name (e.g., "t_system", "t_acme")
     */
    public void migrate(String schemaName) {
        log.info("Running tenant migrations on schema: {}", schemaName);

        Flyway flyway = Flyway.configure()
                .dataSource(dataSource)
                .locations(migrationLocations)
                .schemas(schemaName)
                .baselineOnMigrate(true)
                .load();

        var result = flyway.migrate();
        log.info("Tenant migration complete: schema={}, migrationsExecuted={}",
                schemaName, result.migrationsExecuted);
    }
}
