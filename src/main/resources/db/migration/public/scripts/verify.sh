#!/bin/bash

# ============================================================================
# Providence AI - Infrastructure Verification Script
# ============================================================================
# Verifies that all components are working correctly:
# - Database tables exist
# - Debezium connector is running
# - Kafka topics are created
# - Services are healthy
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

success() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
info() { echo -e "${YELLOW}→${NC} $1"; }

echo "============================================================================"
echo "Providence AI - Infrastructure Verification"
echo "============================================================================"
echo ""

# ============================================================================
# 1. PostgreSQL
# ============================================================================
info "Checking PostgreSQL..."

# Check public schema tables
PUBLIC_TABLES=$(docker-compose exec -T postgres psql -U providence -d providence -tAc "
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('tenants', 'outbox_events', 'audit_log', 'idempotency_keys', 'inbox_events');
")

if [ "$PUBLIC_TABLES" -eq 5 ]; then
    success "All 5 public schema tables exist"
else
    fail "Public schema tables missing (expected 5, found $PUBLIC_TABLES)"
fi

# Check demo tenant
TENANT_COUNT=$(docker-compose exec -T postgres psql -U providence -d providence -tAc "
SELECT COUNT(*) FROM public.tenants WHERE slug = 'acme';
")

if [ "$TENANT_COUNT" -eq 1 ]; then
    success "Demo tenant 'acme' exists"
else
    fail "Demo tenant 'acme' not found"
fi

# Check tenant schema exists
TENANT_SCHEMA=$(docker-compose exec -T postgres psql -U providence -d providence -tAc "
SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name = 't_acme';
")

if [ "$TENANT_SCHEMA" -eq 1 ]; then
    success "Tenant schema 't_acme' exists"
else
    fail "Tenant schema 't_acme' not found"
fi

# Check logical replication
PUBLICATION=$(docker-compose exec -T postgres psql -U providence -d providence -tAc "
SELECT COUNT(*) FROM pg_publication WHERE pubname = 'providence_outbox_publication';
")

if [ "$PUBLICATION" -eq 1 ]; then
    success "Logical replication publication exists"
else
    fail "Logical replication publication missing"
fi

SLOT=$(docker-compose exec -T postgres psql -U providence -d providence -tAc "
SELECT COUNT(*) FROM pg_replication_slots WHERE slot_name = 'providence_outbox_slot';
")

if [ "$SLOT" -eq 1 ]; then
    success "Replication slot exists"
else
    fail "Replication slot missing"
fi

# ============================================================================
# 2. Redis
# ============================================================================
info "Checking Redis..."

REDIS_PING=$(docker-compose exec -T redis redis-cli -a redis_dev_password ping 2>/dev/null)

if [ "$REDIS_PING" == "PONG" ]; then
    success "Redis is responding"
else
    fail "Redis is not responding"
fi

# ============================================================================
# 3. Kafka
# ============================================================================
info "Checking Kafka..."

# Check if Kafka is reachable
if docker-compose exec -T kafka kafka-broker-api-versions --bootstrap-server localhost:9092 &>/dev/null; then
    success "Kafka broker is reachable"
else
    fail "Kafka broker is not reachable"
fi

# List topics (should include Debezium internal topics)
TOPICS=$(docker-compose exec -T kafka kafka-topics --bootstrap-server localhost:9092 --list 2>/dev/null | wc -l)

if [ "$TOPICS" -gt 0 ]; then
    success "Kafka topics exist ($TOPICS topics)"
else
    fail "No Kafka topics found"
fi

# ============================================================================
# 4. Debezium
# ============================================================================
info "Checking Debezium..."

# Check if Debezium API is accessible
if curl -s http://localhost:8083/ &>/dev/null; then
    success "Debezium Connect is accessible"
else
    fail "Debezium Connect is not accessible"
fi

# Check connector status
CONNECTOR_STATUS=$(curl -s http://localhost:8083/connectors/providence-outbox-connector/status 2>/dev/null | jq -r '.connector.state' 2>/dev/null || echo "NOT_FOUND")

if [ "$CONNECTOR_STATUS" == "RUNNING" ]; then
    success "Debezium connector is RUNNING"
elif [ "$CONNECTOR_STATUS" == "NOT_FOUND" ]; then
    fail "Debezium connector not found (run setup.sh)"
else
    fail "Debezium connector status: $CONNECTOR_STATUS"
fi

# ============================================================================
# 5. Docker Services Health
# ============================================================================
info "Checking Docker service health..."

HEALTHY=$(docker-compose ps --format json | jq -r 'select(.Health == "healthy") | .Name' 2>/dev/null | wc -l)
TOTAL=$(docker-compose ps --format json | jq -r '.Name' 2>/dev/null | wc -l)

if [ "$HEALTHY" -eq "$TOTAL" ]; then
    success "All Docker services are healthy ($HEALTHY/$TOTAL)"
else
    fail "Some services are unhealthy ($HEALTHY/$TOTAL)"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "============================================================================"
echo "Verification Complete"
echo "============================================================================"
echo ""
echo "Quick commands:"
echo "  View logs:           docker-compose logs -f"
echo "  Restart services:    docker-compose restart"
echo "  Check connector:     curl http://localhost:8083/connectors/providence-outbox-connector/status | jq"
echo "  Kafka UI:            http://localhost:8080"
echo ""
echo "Database connection:"
echo "  psql -h localhost -U providence -d providence"
echo "  Password: providence_dev_password"
echo ""
echo "============================================================================"
