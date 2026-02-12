package com.providence.tenant.service;

import com.providence.common.tenant.TenantMigrationRunner;
import com.providence.tenant.domain.Tenant;
import com.providence.tenant.repository.TenantRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class SystemTenantProvisionerTest {

    @Mock
    private TenantRepository tenantRepository;

    @Mock
    private TenantMigrationRunner migrationRunner;

    @Mock
    private DataSource dataSource;

    @Mock
    private Connection connection;

    @Mock
    private Statement statement;

    private SystemTenantProvisioner provisioner;

    @BeforeEach
    void setUp() throws SQLException {
        provisioner = new SystemTenantProvisioner(tenantRepository, migrationRunner, dataSource);
        lenient().when(dataSource.getConnection()).thenReturn(connection);
        lenient().when(connection.createStatement()).thenReturn(statement);
    }

    @Test
    void provision_whenSystemTenantExists_doesNotCreateNewRecord() throws SQLException {
        // Arrange
        var existingTenant = new Tenant(
                SystemTenantProvisioner.SYSTEM_TENANT_ID,
                SystemTenantProvisioner.SYSTEM_TENANT_SLUG,
                "System",
                SystemTenantProvisioner.SYSTEM_TENANT_SCHEMA,
                "ACTIVE",
                "ENTERPRISE",
                -1
        );
        when(tenantRepository.findBySlug(SystemTenantProvisioner.SYSTEM_TENANT_SLUG))
                .thenReturn(Optional.of(existingTenant));

        // Act
        provisioner.provision();

        // Assert
        verify(tenantRepository, never()).save(any(Tenant.class));
        verify(statement).execute("CREATE SCHEMA IF NOT EXISTS t_system");
        verify(migrationRunner).migrate(SystemTenantProvisioner.SYSTEM_TENANT_SCHEMA);
    }

    @Test
    void provision_whenSystemTenantMissing_createsRecord() throws SQLException {
        // Arrange
        when(tenantRepository.findBySlug(SystemTenantProvisioner.SYSTEM_TENANT_SLUG))
                .thenReturn(Optional.empty());

        // Act
        provisioner.provision();

        // Assert
        ArgumentCaptor<Tenant> captor = ArgumentCaptor.forClass(Tenant.class);
        verify(tenantRepository).save(captor.capture());

        Tenant saved = captor.getValue();
        assertThat(saved.getId()).isEqualTo(SystemTenantProvisioner.SYSTEM_TENANT_ID);
        assertThat(saved.getSlug()).isEqualTo("system");
        assertThat(saved.getName()).isEqualTo("System");
        assertThat(saved.getSchemaName()).isEqualTo("t_system");
        assertThat(saved.getStatus()).isEqualTo("ACTIVE");
        assertThat(saved.getSubscriptionTier()).isEqualTo("ENTERPRISE");
        assertThat(saved.getMaxUsers()).isEqualTo(-1);
    }

    @Test
    void provision_createsSchemaAndRunsMigrations() throws SQLException {
        // Arrange
        when(tenantRepository.findBySlug(SystemTenantProvisioner.SYSTEM_TENANT_SLUG))
                .thenReturn(Optional.of(new Tenant(
                        SystemTenantProvisioner.SYSTEM_TENANT_ID,
                        "system", "System", "t_system",
                        "ACTIVE", "ENTERPRISE", -1)));

        // Act
        provisioner.provision();

        // Assert — schema created before migrations
        var inOrder = inOrder(statement, migrationRunner);
        inOrder.verify(statement).execute("CREATE SCHEMA IF NOT EXISTS t_system");
        inOrder.verify(migrationRunner).migrate("t_system");
    }

    @Test
    void provision_isIdempotent_canRunMultipleTimes() throws SQLException {
        // Arrange
        when(tenantRepository.findBySlug(SystemTenantProvisioner.SYSTEM_TENANT_SLUG))
                .thenReturn(Optional.of(new Tenant(
                        SystemTenantProvisioner.SYSTEM_TENANT_ID,
                        "system", "System", "t_system",
                        "ACTIVE", "ENTERPRISE", -1)));

        // Act — run twice
        provisioner.provision();
        provisioner.provision();

        // Assert — no exceptions, migration runner called both times (Flyway is idempotent)
        verify(migrationRunner, times(2)).migrate("t_system");
    }

    @Test
    void systemTenantConstants_haveCorrectValues() {
        assertThat(SystemTenantProvisioner.SYSTEM_TENANT_ID.toString())
                .isEqualTo("00000000-0000-0000-0000-000000000000");
        assertThat(SystemTenantProvisioner.SYSTEM_TENANT_SLUG).isEqualTo("system");
        assertThat(SystemTenantProvisioner.SYSTEM_TENANT_SCHEMA).isEqualTo("t_system");
    }
}
