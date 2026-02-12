# Providence AI - Local Development Guide

## 🚀 Quick Start

Get the entire stack running in under 5 minutes:

```bash
# 1. Start all infrastructure services
./scripts/setup.sh

# 2. Verify everything is working
./scripts/verify.sh

# 3. Start Spring Boot application
./gradlew bootRun
```

That's it! The stack is now running with:
- ✅ PostgreSQL with public schema migrations
- ✅ Redis for caching
- ✅ Kafka for event streaming
- ✅ Debezium for CDC outbox pattern
- ✅ Demo tenant 'acme' provisioned

---

## 📦 Prerequisites

- **Docker** (20.10+) and **Docker Compose** (2.0+)
- **Java** (25+) with **Gradle** (or Maven)
- **Optional:** `jq` for JSON parsing in verification script

---

## 🏗️ Infrastructure Stack

| Service | Port | Purpose | Credentials |
|---------|------|---------|-------------|
| **PostgreSQL** | 5432 | Primary database | user: `providence`<br>pass: `providence_dev_password` |
| **Redis** | 6379 | Cache + session store | pass: `redis_dev_password` |
| **Kafka** | 9092 | Event streaming | No auth (local) |
| **Zookeeper** | 2181 | Kafka coordination | No auth (local) |
| **Debezium** | 8083 | CDC connector | HTTP REST API |
| **Kafka UI** | 8080 | Web UI for Kafka | http://localhost:8080 |

---

## 📝 Detailed Setup Steps

### Step 1: Start Infrastructure

```bash
# Start all services in detached mode
docker-compose up -d

# View logs
docker-compose logs -f

# View logs for specific service
docker-compose logs -f postgres
docker-compose logs -f debezium
```

Wait for all services to be healthy (~60-90 seconds):
- PostgreSQL: Logical replication enabled
- Kafka: Broker ready
- Debezium: Connect API accessible

### Step 2: Run Flyway Migrations

Public schema migrations (cross-tenant infrastructure):

```bash
# Option 1: Via Gradle
./gradlew flywayMigrate \
  -Pflyway.url=jdbc:postgresql://localhost:5432/providence \
  -Pflyway.user=providence \
  -Pflyway.password=providence_dev_password \
  -Pflyway.locations=filesystem:src/main/resources/db/migration/public \
  -Pflyway.schemas=public

# Option 2: Via standalone Flyway CLI
flyway -url=jdbc:postgresql://localhost:5432/providence \
       -user=providence \
       -password=providence_dev_password \
       -locations=filesystem:src/main/resources/db/migration/public \
       -schemas=public \
       migrate
```

Verify migrations:

```bash
docker-compose exec postgres psql -U providence -d providence -c "
  SELECT table_name FROM information_schema.tables
  WHERE table_schema = 'public'
  ORDER BY table_name;
"
```

Expected tables:
- `tenants`
- `outbox_events`
- `audit_log`
- `idempotency_keys`
- `inbox_events`

### Step 3: Provision Demo Tenant

```bash
docker-compose exec postgres psql -U providence -d providence <<EOF
-- Insert demo tenant
INSERT INTO public.tenants (id, slug, name, schema_name, status, subscription_tier)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'acme',
    'Acme Corporation',
    't_acme',
    'ACTIVE',
    'ENTERPRISE'
);

-- Create tenant schema
CREATE SCHEMA t_acme;

-- Verify
SELECT id, slug, name, schema_name, status FROM public.tenants;
EOF
```

Run tenant migrations:

```bash
./gradlew flywayMigrate \
  -Pflyway.url=jdbc:postgresql://localhost:5432/providence \
  -Pflyway.user=providence \
  -Pflyway.password=providence_dev_password \
  -Pflyway.locations=filesystem:src/main/resources/db/migration/tenant \
  -Pflyway.schemas=t_acme
```

### Step 4: Configure Debezium Outbox Connector

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @scripts/debezium-connector.json
```

Verify connector status:

```bash
curl http://localhost:8083/connectors/providence-outbox-connector/status | jq
```

Expected output:
```json
{
  "name": "providence-outbox-connector",
  "connector": {
    "state": "RUNNING",
    "worker_id": "debezium:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "debezium:8083"
    }
  ]
}
```

### Step 5: Verify Stack

```bash
./scripts/verify.sh
```

This checks:
- ✅ All 5 public schema tables exist
- ✅ Demo tenant 'acme' exists
- ✅ Tenant schema 't_acme' exists
- ✅ Logical replication publication exists
- ✅ Replication slot exists
- ✅ Redis responds to PING
- ✅ Kafka broker is reachable
- ✅ Debezium connector is RUNNING
- ✅ All Docker services are healthy

---

## 🧪 Testing the Outbox Pattern

Test end-to-end event flow (domain mutation → outbox → Debezium → Kafka):

### 1. Insert an outbox event

```sql
docker-compose exec postgres psql -U providence -d providence <<EOF
INSERT INTO public.outbox_events (
    id, tenant_id, aggregate_type, aggregate_id, event_type, event_version,
    occurred_at, correlation_id, actor_id, payload
) VALUES (
    gen_random_uuid(),
    '11111111-1111-1111-1111-111111111111',
    'Project',
    gen_random_uuid(),
    'ProjectCreated',
    1,
    NOW(),
    gen_random_uuid(),
    gen_random_uuid(),
    '{"projectId": "550e8400-e29b-41d4-a716-446655440000", "name": "Test Project", "description": "Testing outbox"}'::jsonb
);
EOF
```

### 2. Verify Kafka topic was created

```bash
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list
```

Expected: `ecap.events.ProjectCreated`

### 3. Consume the event from Kafka

```bash
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic ecap.events.ProjectCreated \
  --from-beginning
```

Expected output:
```json
{
  "projectId": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Test Project",
  "description": "Testing outbox"
}
```

### 4. Verify event was published (check outbox table)

```sql
docker-compose exec postgres psql -U providence -d providence <<EOF
SELECT id, event_type, aggregate_type, occurred_at, published_at
FROM public.outbox_events
ORDER BY occurred_at DESC
LIMIT 5;
EOF
```

If `published_at` is NULL, Debezium hasn't processed it yet. Check connector logs:

```bash
docker-compose logs debezium | grep ERROR
```

---

## 🔧 Common Tasks

### Access PostgreSQL

```bash
# Via Docker Compose
docker-compose exec postgres psql -U providence -d providence

# Via local psql client
psql -h localhost -p 5432 -U providence -d providence
# Password: providence_dev_password
```

### Access Redis

```bash
# Via Docker Compose
docker-compose exec redis redis-cli -a redis_dev_password

# Test connection
docker-compose exec redis redis-cli -a redis_dev_password PING
# Expected: PONG
```

### View Kafka Topics

```bash
# List all topics
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --list

# Describe a topic
docker-compose exec kafka kafka-topics --bootstrap-server localhost:9092 --describe --topic ecap.events.ProjectCreated
```

### View Kafka Messages

```bash
# Consume from beginning
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic ecap.events.ProjectCreated \
  --from-beginning

# Consume with key
docker-compose exec kafka kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic ecap.events.ProjectCreated \
  --property print.key=true \
  --from-beginning
```

### Restart Debezium Connector

```bash
# Delete connector
curl -X DELETE http://localhost:8083/connectors/providence-outbox-connector

# Recreate connector
./scripts/setup.sh
```

### Clean Slate (Reset Everything)

```bash
# Stop and remove all containers + volumes
docker-compose down -v

# Restart from scratch
./scripts/setup.sh
```

---

## 🐛 Troubleshooting

### Issue: Debezium connector not RUNNING

**Check connector status:**
```bash
curl http://localhost:8083/connectors/providence-outbox-connector/status | jq
```

**Check connector logs:**
```bash
docker-compose logs debezium | tail -100
```

**Common causes:**
- PostgreSQL logical replication not enabled (check `wal_level`)
- Publication or replication slot missing
- Wrong database credentials in connector config

**Fix:**
```bash
# Verify logical replication
docker-compose exec postgres psql -U providence -d providence -c "SHOW wal_level;"
# Expected: logical

# Verify publication
docker-compose exec postgres psql -U providence -d providence -c "SELECT * FROM pg_publication;"

# Recreate connector
curl -X DELETE http://localhost:8083/connectors/providence-outbox-connector
./scripts/setup.sh
```

### Issue: Kafka topics not created

**Check Kafka logs:**
```bash
docker-compose logs kafka | grep ERROR
```

**Check if Kafka is reachable:**
```bash
docker-compose exec kafka kafka-broker-api-versions --bootstrap-server localhost:9092
```

**Manually create topic:**
```bash
docker-compose exec kafka kafka-topics \
  --bootstrap-server localhost:9092 \
  --create \
  --topic ecap.events.ProjectCreated \
  --partitions 3 \
  --replication-factor 1
```

### Issue: Flyway migrations fail

**Check if public schema exists:**
```bash
docker-compose exec postgres psql -U providence -d providence -c "\dn"
```

**Check migration history:**
```bash
docker-compose exec postgres psql -U providence -d providence -c "SELECT * FROM flyway_schema_history ORDER BY installed_rank;"
```

**Reset Flyway (CAUTION: deletes all data):**
```bash
./gradlew flywayClean  # Drops all objects in managed schemas
./gradlew flywayMigrate  # Reapply migrations
```

### Issue: Services not healthy

**Check Docker Compose status:**
```bash
docker-compose ps
```

**Restart unhealthy service:**
```bash
docker-compose restart <service-name>
```

**View service logs:**
```bash
docker-compose logs -f <service-name>
```

---

## 📚 Additional Resources

- [PUBLIC_SCHEMA_DESIGN.md](PUBLIC_SCHEMA_DESIGN.md) — Database schema reference
- [FEATURE_EXAMPLE_PROJECT_MANAGEMENT.md](FEATURE_EXAMPLE_PROJECT_MANAGEMENT.md) — Complete feature implementation
- [CLAUDE.md](CLAUDE.md) — Master engineering constitution
- [Debezium PostgreSQL Connector Docs](https://debezium.io/documentation/reference/stable/connectors/postgresql.html)
- [Kafka Documentation](https://kafka.apache.org/documentation/)

---

## 🔄 Daily Workflow

```bash
# Morning: Start infrastructure
docker-compose up -d

# Development: Run Spring Boot app
./gradlew bootRun

# Testing: Run tests against local stack
./gradlew test

# Debugging: View logs
docker-compose logs -f

# Evening: Stop infrastructure (preserve data)
docker-compose down

# OR: Stop and clean everything
docker-compose down -v
```

---

## ⚡ Performance Tuning (Local Dev)

For faster iteration, reduce service resource usage:

1. **Reduce Kafka log retention:**
   - Edit `docker-compose.yml`: `KAFKA_LOG_RETENTION_HOURS: 24`

2. **Use fewer Kafka partitions:**
   - Edit `docker-compose.yml`: `KAFKA_NUM_PARTITIONS: 1`

3. **Disable Kafka UI:**
   - Comment out `kafka-ui` service in `docker-compose.yml`

4. **Use H2 instead of PostgreSQL** (not recommended, but faster):
   - Configure Spring Boot `application-dev.yml` to use H2

---

**Status:** Production-ready ✅
**Last Updated:** 2026-02-12
**Maintainer:** Providence AI Engineering Team
