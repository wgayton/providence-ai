package com.providence.common.tenant;

import org.hibernate.context.spi.CurrentTenantIdentifierResolver;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Resolves the current tenant identifier (schema name) for Hibernate.
 *
 * Returns the schema name from {@link TenantContext} if set,
 * otherwise falls back to "public" for non-tenant-scoped operations.
 */
public class TenantIdentifierResolver implements CurrentTenantIdentifierResolver<String> {

    private static final Logger log = LoggerFactory.getLogger(TenantIdentifierResolver.class);
    private static final String DEFAULT_SCHEMA = "public";

    @Override
    public String resolveCurrentTenantIdentifier() {
        String schema = TenantContext.getSchema();
        if (schema != null) {
            return schema;
        }
        log.trace("No tenant context set, using default schema: {}", DEFAULT_SCHEMA);
        return DEFAULT_SCHEMA;
    }

    @Override
    public boolean validateExistingCurrentSessions() {
        return true;
    }
}
