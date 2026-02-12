#!/bin/bash

# ============================================================================
# Providence AI - Kafka Topic Creation Script
# ============================================================================
# Creates all required Kafka topics with consistent configuration.
#
# Usage:
#   ./scripts/create-topics.sh
#
# Prerequisites:
#   - Kafka must be running (docker-compose up kafka)
#   - Kafka CLI tools available in container
# ============================================================================

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

KAFKA_BROKER="localhost:9092"
PARTITIONS=12
REPLICATION_FACTOR=1  # Use 3 in production with 3+ brokers
RETENTION_7_DAYS=604800000    # 7 days in ms
RETENTION_30_DAYS=2592000000  # 30 days in ms
RETENTION_90_DAYS=7776000000  # 90 days in ms

info "Creating Kafka topics for Providence AI..."

# ============================================================================
# Project Management Events
# ============================================================================
info "Creating Project Management topics..."

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.Project.Created \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_7_DAYS \
  --config segment.ms=86400000 \
  --config cleanup.policy=delete

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.Project.Updated \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_7_DAYS

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.Project.Archived \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_7_DAYS

success "Project Management topics created"

# ============================================================================
# User Management Events
# ============================================================================
info "Creating User Management topics..."

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.User.Registered \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_30_DAYS

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.User.RoleAssigned \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_30_DAYS

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.User.Suspended \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_90_DAYS

success "User Management topics created"

# ============================================================================
# Fund Management Events
# ============================================================================
info "Creating Fund Management topics..."

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.FundTransfer.Created \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_90_DAYS

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.FundTransfer.Completed \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_90_DAYS

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.events.FundTransfer.Failed \
  --partitions $PARTITIONS \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_90_DAYS

success "Fund Management topics created"

# ============================================================================
# Dead-Letter Queue (DLQ) Topics
# ============================================================================
info "Creating DLQ topics..."

# Project DLQs
docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.dlq.events.Project.Created \
  --partitions 1 \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_30_DAYS

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.dlq.events.Project.Updated \
  --partitions 1 \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_30_DAYS

docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --if-not-exists \
  --topic ecap.dlq.events.Project.Archived \
  --partitions 1 \
  --replication-factor $REPLICATION_FACTOR \
  --config retention.ms=$RETENTION_30_DAYS

success "DLQ topics created"

# ============================================================================
# Verify Topics
# ============================================================================
info "Verifying topic creation..."

echo ""
echo "============================================================================"
echo "Created Topics:"
echo "============================================================================"
docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --list | grep ecap

echo ""
echo "============================================================================"
echo "Topic Details (sample):"
echo "============================================================================"
docker-compose exec -T kafka kafka-topics --bootstrap-server $KAFKA_BROKER --describe --topic ecap.events.Project.Created

echo ""
success "All Kafka topics created successfully!"
echo ""
echo "Next steps:"
echo "  1. Verify Debezium connector: curl http://localhost:8083/connectors"
echo "  2. Test event flow: ./scripts/test-event-flow.sh"
echo "  3. Monitor consumer lag: ./scripts/monitor-lag.sh"
echo ""
