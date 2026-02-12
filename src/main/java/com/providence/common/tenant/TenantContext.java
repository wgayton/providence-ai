package com.providence.common.tenant;

import java.util.UUID;

/**
 * Thread-local tenant context for schema-per-tenant multi-tenancy.
 *
 * Stores the current tenant ID and schema name for the executing thread.
 * Used by {@link TenantIdentifierResolver} to provide Hibernate with the
 * current tenant schema, and by {@link SchemaPerTenantConnectionProvider}
 * to SET search_path on acquired connections.
 *
 * <p>Migration path: When Java 25+ is available, migrate to {@code ScopedValue}
 * for virtual thread compatibility.</p>
 */
public final class TenantContext {

    private static final ThreadLocal<UUID> CURRENT_TENANT_ID = new ThreadLocal<>();
    private static final ThreadLocal<String> CURRENT_SCHEMA = new ThreadLocal<>();

    private TenantContext() {}

    public static void setTenantId(UUID tenantId) {
        CURRENT_TENANT_ID.set(tenantId);
    }

    public static UUID getTenantId() {
        return CURRENT_TENANT_ID.get();
    }

    public static void setSchema(String schema) {
        CURRENT_SCHEMA.set(schema);
    }

    public static String getSchema() {
        return CURRENT_SCHEMA.get();
    }

    public static void clear() {
        CURRENT_TENANT_ID.remove();
        CURRENT_SCHEMA.remove();
    }
}
