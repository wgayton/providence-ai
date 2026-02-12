#!/bin/bash

# ============================================================================
# Providence AI - Local Development Setup Script
# ============================================================================
# This script:
# 1. Starts all infrastructure services (Postgres, Redis, Kafka, Debezium)
# 2. Waits for services to be healthy
# 3. Runs Flyway migrations (public schema)
# 4. Provisions a demo tenant
# 5. Configures Debezium connector
# 6. Verifies the entire stack
#
# Usage:
#   ./scripts/setup.sh
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

info "Starting Providence AI local development environment..."

# ============================================================================
# Step 1: Start Docker Compose services
# ============================================================================
info "Step 1: Starting Docker Compose services..."
docker-compose up -d || error "Failed to start Docker Compose"

# Wait for services to be healthy
info "Waiting for services to be healthy (this may take 60-90 seconds)..."
sleep 10

# Check PostgreSQL
info "Checking PostgreSQL..."
until docker-compose exec -T postgres pg_isready -U providence &> /dev/null; do
    printf "."
    sleep 2
done
success "PostgreSQL is ready"

# Check Redis
info "Checking Redis..."
until docker-compose exec -T redis redis-cli -a redis_dev_password ping &> /dev/null; do
    printf "."
    sleep 2
done
success "Redis is ready"

# Check Kafka
info "Checking Kafka..."
until docker-compose exec -T kafka kafka-broker-api-versions --bootstrap-server localhost:9092 &> /dev/null; do
    printf "."
    sleep 2
done
success "Kafka is ready"

# Check Debezium
info "Checking Debezium..."
until curl -s http://localhost:8083/ &> /dev/null; do
    printf "."
    sleep 2
done
success "Debezium is ready"

# ============================================================================
# Step 2: Run Flyway migrations (public schema)
# ============================================================================
info "Step 2: Running Flyway migrations for public schema..."

# Check if Flyway is available (via Gradle or standalone)
if command -v flyway &> /dev/null; then
    flyway -url=jdbc:postgresql://localhost:5432/providence \
           -user=providence \
           -password=providence_dev_password \
           -locations=filesystem:src/main/resources/db/migration/public \
           -schemas=public \
           migrate || error "Flyway migration failed"
elif [ -f ./gradlew ]; then
    ./gradlew flywayMigrate \
        -Pflyway.url=jdbc:postgresql://localhost:5432/providence \
        -Pflyway.user=providence \
        -Pflyway.password=providence_dev_password \
        -Pflyway.locations=filesystem:src/main/resources/db/migration/public \
        -Pflyway.schemas=public || error "Flyway migration failed"
else
    warn "Flyway not found. Skipping migrations (run manually)."
fi

success "Public schema migrations completed"

# ============================================================================
# Step 3: Provision demo tenant
# ============================================================================
info "Step 3: Provisioning demo tenant 'acme'..."

docker-compose exec -T postgres psql -U providence -d providence <<EOF
-- Insert demo tenant
INSERT INTO public.tenants (id, slug, name, schema_name, status, subscription_tier, contact_email)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'acme',
    'Acme Corporation',
    't_acme',
    'ACTIVE',
    'ENTERPRISE',
    'admin@acme.example.com'
) ON CONFLICT (slug) DO NOTHING;

-- Create tenant schema
CREATE SCHEMA IF NOT EXISTS t_acme;

-- Verify tenant created
SELECT id, slug, name, schema_name, status FROM public.tenants WHERE slug = 'acme';
EOF

success "Demo tenant 'acme' provisioned"

# ============================================================================
# Step 4: Run tenant migrations
# ============================================================================
info "Step 4: Running Flyway migrations for tenant 't_acme'..."

if command -v flyway &> /dev/null; then
    flyway -url=jdbc:postgresql://localhost:5432/providence \
           -user=providence \
           -password=providence_dev_password \
           -locations=filesystem:src/main/resources/db/migration/tenant \
           -schemas=t_acme \
           migrate || warn "Tenant migrations failed (may not exist yet)"
elif [ -f ./gradlew ]; then
    ./gradlew flywayMigrate \
        -Pflyway.url=jdbc:postgresql://localhost:5432/providence \
        -Pflyway.user=providence \
        -Pflyway.password=providence_dev_password \
        -Pflyway.locations=filesystem:src/main/resources/db/migration/tenant \
        -Pflyway.schemas=t_acme || warn "Tenant migrations failed (may not exist yet)"
fi

success "Tenant migrations completed"

# ============================================================================
# Step 5: Configure Debezium connector
# ============================================================================
info "Step 5: Configuring Debezium outbox connector..."

curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "providence-outbox-connector",
    "config": {
      "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
      "database.hostname": "postgres",
      "database.port": "5432",
      "database.user": "providence",
      "database.password": "providence_dev_password",
      "database.dbname": "providence",
      "database.server.name": "providence",
      "table.include.list": "public.outbox_events",
      "plugin.name": "pgoutput",
      "publication.name": "providence_outbox_publication",
      "slot.name": "providence_outbox_slot",
      "transforms": "outbox",
      "transforms.outbox.type": "io.debezium.transforms.outbox.EventRouter",
      "transforms.outbox.table.field.event.id": "id",
      "transforms.outbox.table.field.event.key": "aggregate_id",
      "transforms.outbox.table.field.event.type": "event_type",
      "transforms.outbox.table.field.event.payload": "payload",
      "transforms.outbox.route.topic.replacement": "ecap.events.${routedByValue}",
      "tombstones.on.delete": "false",
      "key.converter": "org.apache.kafka.connect.json.JsonConverter",
      "value.converter": "org.apache.kafka.connect.json.JsonConverter",
      "key.converter.schemas.enable": "false",
      "value.converter.schemas.enable": "false"
    }
  }' || warn "Debezium connector may already exist"

success "Debezium connector configured"

# ============================================================================
# Step 6: Verify the stack
# ============================================================================
info "Step 6: Verifying the entire stack..."

./scripts/verify.sh || warn "Verification had some warnings"

# ============================================================================
# Setup Complete
# ============================================================================
echo ""
echo "============================================================================"
success "Providence AI local development environment is ready!"
echo "============================================================================"
echo ""
echo "Services:"
echo "  PostgreSQL:  localhost:5432 (user: providence, pass: providence_dev_password)"
echo "  Redis:       localhost:6379 (pass: redis_dev_password)"
echo "  Kafka:       localhost:9092"
echo "  Debezium:    http://localhost:8083"
echo "  Kafka UI:    http://localhost:8080"
echo ""
echo "Demo tenant: 'acme' (schema: t_acme)"
echo ""
echo "Next steps:"
echo "  1. Start Spring Boot app: ./gradlew bootRun"
echo "  2. View logs: docker-compose logs -f"
echo "  3. Access Kafka UI: http://localhost:8080"
echo "  4. Check Debezium status: curl http://localhost:8083/connectors/providence-outbox-connector/status"
echo ""
echo "Tear down:"
echo "  docker-compose down           # Stop services"
echo "  docker-compose down -v        # Stop and remove volumes (clean slate)"
echo ""
echo "============================================================================"
