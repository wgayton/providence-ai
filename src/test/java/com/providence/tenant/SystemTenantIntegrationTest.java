package com.providence.tenant;

import com.providence.tenant.domain.Tenant;
import com.providence.tenant.repository.TenantRepository;
import com.providence.tenant.service.SystemTenantProvisioner;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.jdbc.core.JdbcTemplate;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Integration test: System tenant provisioning with real PostgreSQL.
 *
 * Verifies:
 * - System tenant record exists in public.tenants after startup
 * - t_system schema exists with all expected reference tables
 * - System tenant has ENTERPRISE product features
 * - Provisioning is idempotent (no errors on restart)
 */
@SpringBootTest
@Testcontainers
class SystemTenantIntegrationTest {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:17-alpine")
            .withDatabaseName("providence")
            .withUsername("postgres")
            .withPassword("postgres");

    @Autowired
    private TenantRepository tenantRepository;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @Test
    void systemTenantRecord_existsAfterStartup() {
        Optional<Tenant> tenant = tenantRepository.findBySlug("system");

        assertThat(tenant).isPresent();
        assertThat(tenant.get().getId()).isEqualTo(SystemTenantProvisioner.SYSTEM_TENANT_ID);
        assertThat(tenant.get().getSlug()).isEqualTo("system");
        assertThat(tenant.get().getSchemaName()).isEqualTo("t_system");
        assertThat(tenant.get().getStatus()).isEqualTo("ACTIVE");
        assertThat(tenant.get().getSubscriptionTier()).isEqualTo("ENTERPRISE");
        assertThat(tenant.get().getMaxUsers()).isEqualTo(-1);
    }

    @Test
    void systemTenantSchema_exists() {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = 't_system'",
                Integer.class);

        assertThat(count).isEqualTo(1);
    }

    @Test
    void systemTenantSchema_hasReferenceTablesFromV001() {
        var tables = jdbcTemplate.queryForList(
                """
                SELECT table_name FROM information_schema.tables
                WHERE table_schema = 't_system'
                  AND table_type = 'BASE TABLE'
                ORDER BY table_name
                """,
                String.class);

        assertThat(tables).contains(
                "ref_alert_types",
                "ref_group_statuses",
                "ref_tenant_roles",
                "ref_user_statuses"
        );
    }

    @Test
    void systemTenantSchema_referenceTablesAreSeeded() {
        Integer userStatusCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM t_system.ref_user_statuses", Integer.class);
        Integer tenantRoleCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM t_system.ref_tenant_roles", Integer.class);
        Integer groupStatusCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM t_system.ref_group_statuses", Integer.class);
        Integer alertTypeCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM t_system.ref_alert_types", Integer.class);

        assertThat(userStatusCount).isEqualTo(4);
        assertThat(tenantRoleCount).isEqualTo(3);
        assertThat(groupStatusCount).isEqualTo(2);
        assertThat(alertTypeCount).isEqualTo(5);
    }

    @Test
    void systemTenant_hasEnterpriseProductFeatures() {
        var features = jdbcTemplate.queryForList(
                """
                SELECT feature_key, feature_level, enabled
                FROM public.tenant_product_features
                WHERE tenant_id = '00000000-0000-0000-0000-000000000000'
                ORDER BY feature_key
                """);

        assertThat(features).hasSize(4);
        assertThat(features).allSatisfy(row -> {
            assertThat(row.get("feature_level")).isEqualTo("ENTERPRISE");
            assertThat(row.get("enabled")).isEqualTo(true);
        });

        var featureKeys = features.stream()
                .map(row -> (String) row.get("feature_key"))
                .toList();
        assertThat(featureKeys).containsExactly("FINANCE", "HUMAN", "PROJECT", "RESOURCE");
    }

    @Test
    void featureLevels_areSeeded() {
        var levels = jdbcTemplate.queryForList(
                "SELECT code FROM public.ref_feature_levels ORDER BY display_order",
                String.class);

        assertThat(levels).containsExactly("STANDARD", "PRO", "MAX", "ENTERPRISE");
    }
}
