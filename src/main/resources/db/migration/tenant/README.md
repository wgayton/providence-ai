# Tenant Schema Migrations

This directory contains Flyway migrations that are applied to each tenant's schema (t_<tenant_slug>).

These migrations define the tenant-specific data structures:
- projects
- resources  
- ledger_entries
- budgets
- etc.

Migrations are applied by TenantMigrationManager to all tenant schemas automatically.
