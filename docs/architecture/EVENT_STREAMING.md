# Kafka Topic Strategy - Providence AI

## 🎯 Overview

This document defines the complete Kafka topic strategy for the Providence AI multi-tenant SaaS platform, covering:

- **Topic naming conventions** (consistent, predictable patterns)
- **Partitioning strategy** (tenant-based for ordering guarantees)
- **Retention policies** (event type-specific durations)
- **Consumer group patterns** (one group per logical consumer)
- **Dead-letter queue (DLQ) strategy** (poison message handling)
- **Monitoring and operations** (lag tracking, rebalancing)

---

## 📋 Topic Naming Convention

**Pattern:** `<namespace>.<category>.<aggregate>.<event-type>`

| Component | Description | Example |
|-----------|-------------|---------|
| **namespace** | Platform identifier | `ecap` (Enterprise Cloud Application Platform) |
| **category** | Event category | `events`, `commands`, `queries` |
| **aggregate** | DDD aggregate root | `Project`, `User`, `FundTransfer` |
| **event-type** | Specific event | `Created`, `Updated`, `Archived` |

**Examples:**
- `ecap.events.Project.Created` — Project aggregate, Created event
- `ecap.events.User.Registered` — User aggregate, Registered event
- `ecap.events.FundTransfer.Completed` — FundTransfer aggregate, Completed event

**Special topics:**
- `ecap.dlq.<original-topic>` — Dead-letter queue for failed messages
- `ecap.retry.<original-topic>` — Retry queue for transient failures

---

## 🔄 Event Flow Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                      Spring Boot Service                        │
│                                                                  │
│  @Transactional                                                 │
│  public void createProject() {                                  │
│      // 1. Mutate domain (t_<tenant>.projects)                 │
│      projectRepo.save(project);                                 │
│                                                                  │
│      // 2. Write outbox event (public.outbox_events)           │
│      outboxService.publish(ProjectCreated);                     │
│                                                                  │
│      // Commit → Atomic domain + event                         │
│  }                                                              │
└────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────────┐
│                 Debezium CDC (PostgreSQL → Kafka)               │
│                                                                  │
│  - Reads public.outbox_events via logical replication          │
│  - EventRouter transform extracts event_type                   │
│  - Publishes to: ecap.events.Project.Created                   │
│  - Partition key: tenant_id (for ordering within tenant)       │
└────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────────┐
│                        Kafka Topic                              │
│              ecap.events.Project.Created                        │
│                                                                  │
│  Partitions: 12 (partitioned by tenant_id hash)                │
│  Replication: 3 (for high availability)                        │
│  Retention: 7 days (168 hours)                                 │
└────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌────────────────────────────────────────────────────────────────┐
│                      Kafka Consumers                            │
│                                                                  │
│  Consumer Group: notification-service                           │
│  @KafkaListener(topics = "ecap.events.Project.Created")        │
│  public void handle(ProjectCreated event) {                    │
│      // 1. Check inbox (already processed?)                    │
│      if (inboxService.isProcessed(eventId)) return;            │
│                                                                  │
│      // 2. Mark as processed                                   │
│      inboxService.markProcessed(eventId);                       │
│                                                                  │
│      // 3. Execute business logic                              │
│      notificationService.send(event);                           │
│  }                                                              │
└────────────────────────────────────────────────────────────────┘
```

---

## 🗂️ Topic Inventory

### **1. Project Management Events**

| Topic | Partitions | Retention | Consumers |
|-------|------------|-----------|-----------|
| `ecap.events.Project.Created` | 12 | 7 days | notification-service, analytics-service |
| `ecap.events.Project.Updated` | 12 | 7 days | search-indexer, analytics-service |
| `ecap.events.Project.Archived` | 12 | 7 days | cleanup-service, analytics-service |

### **2. User Management Events**

| Topic | Partitions | Retention | Consumers |
|-------|------------|-----------|-----------|
| `ecap.events.User.Registered` | 12 | 30 days | onboarding-service, email-service |
| `ecap.events.User.RoleAssigned` | 12 | 30 days | permission-cache-updater, audit-service |
| `ecap.events.User.Suspended` | 12 | 90 days | access-revocation-service, audit-service |

### **3. Fund Management Events**

| Topic | Partitions | Retention | Consumers |
|-------|------------|-----------|-----------|
| `ecap.events.FundTransfer.Created` | 12 | 90 days | ledger-reconciliation, fraud-detection |
| `ecap.events.FundTransfer.Completed` | 12 | 90 days | notification-service, analytics-service |
| `ecap.events.FundTransfer.Failed` | 12 | 90 days | retry-service, support-ticket-creator |

**Retention Rationale:**
- **Project events:** 7 days (operational events, rebuild from database)
- **User events:** 30-90 days (compliance, audit trail)
- **Fund events:** 90 days (financial reconciliation, longer retention for compliance)

---

## 🔀 Partitioning Strategy

### **Key Principle: Partition by `tenant_id`**

**Why?**
- ✅ **Ordering guarantees within tenant**: All events for Tenant A go to same partition → processed in order
- ✅ **Parallel processing across tenants**: Tenant A and Tenant B events processed independently
- ✅ **Load balancing**: 12 partitions with 10,000 tenants → ~833 tenants per partition

**Partition Key:** `tenant_id` (UUID)

**Debezium Configuration:**
```json
{
  "transforms.outbox.table.field.event.key": "tenant_id"
}
```

**Result:** Kafka routes events to partition based on hash(tenant_id).

### **Partition Count Decision**

| Scale | Tenants | Partitions | Tenants/Partition | Justification |
|-------|---------|------------|-------------------|---------------|
| **Small** | <100 | 3 | ~33 | Lower overhead, sufficient parallelism |
| **Medium** | 100-1,000 | 6 | ~166 | Balanced parallelism and overhead |
| **Large** | 1,000-10,000 | 12 | ~833 | High parallelism, good load distribution |
| **XL** | 10,000+ | 24 | ~417 | Maximum parallelism, requires more brokers |

**Providence AI Choice:** **12 partitions** (target: 10,000 tenants)

**Rebalancing Considerations:**
- Adding partitions is **complex** (requires manual reassignment, no automatic rebalancing)
- Start with 12 partitions to avoid early rebalancing
- Monitor partition lag and consumer throughput

---

## ⏱️ Retention Policies

### **Retention Strategy by Event Type**

| Event Category | Retention | Rationale | Cleanup Strategy |
|----------------|-----------|-----------|------------------|
| **Operational** | 7 days | Rebuild from DB, short-lived | Auto-delete after 7 days |
| **Audit** | 30 days | Compliance, recent activity | Auto-delete after 30 days |
| **Financial** | 90 days | Reconciliation, fraud detection | Auto-delete after 90 days |
| **Critical** | 365 days | Long-term compliance (GDPR, SOC 2) | Archive to S3 before deletion |

**Configuration:**
```properties
# Kafka topic config (set per topic)
retention.ms=604800000  # 7 days = 7 * 24 * 60 * 60 * 1000
segment.ms=86400000     # 1 day (segment size)
cleanup.policy=delete   # Delete old segments (vs. compact)
```

**Archival Strategy (Long-term Storage):**
- **Tool:** Kafka Connect S3 Sink Connector
- **Format:** Parquet (columnar, compressed)
- **Retention:** After Kafka retention expires (7/30/90 days)
- **Storage:** AWS S3 / Google Cloud Storage / Azure Blob
- **Access:** Athena / BigQuery / Synapse for ad-hoc queries

---

## 👥 Consumer Group Patterns

### **One Consumer Group Per Logical Consumer**

| Consumer Group | Purpose | Topics Subscribed | Commit Strategy |
|----------------|---------|-------------------|-----------------|
| `notification-service` | Send push notifications, emails | `ecap.events.*.Created` | Manual commit after successful send |
| `search-indexer` | Update Elasticsearch, Algolia | `ecap.events.*.Created`, `*.Updated` | Manual commit after index update |
| `analytics-service` | Aggregate metrics, dashboards | All `ecap.events.*` | Auto-commit (idempotent projections) |
| `audit-service` | Compliance, audit log enrichment | `ecap.events.User.*`, `*.FundTransfer.*` | Manual commit after audit write |

**Commit Strategy:**
- **Manual commit (at-least-once):** Use when operations must succeed (e.g., send notification)
- **Auto-commit (at-most-once):** Use when operations are idempotent (e.g., update counter)
- **Transactional commit (exactly-once):** Use with Kafka transactions (complex, avoid unless necessary)

**Inbox Pattern Simplifies This:**
- All consumers use **manual commit after inbox write**
- Inbox pattern guarantees exactly-once effects
- No need for Kafka transactions

---

## ⚠️ Dead-Letter Queue (DLQ) Strategy

### **Problem: Poison Messages**

A "poison message" is an event that causes consumer crashes (e.g., malformed JSON, missing required fields, business rule violation).

**Without DLQ:** Consumer crashes → rebalance → retry same message → crash loop → **consumer stuck**

**With DLQ:** Consumer catches exception → send to DLQ → commit offset → continue processing → **consumer healthy**

### **DLQ Implementation**

**1. DLQ Topic Naming:**
```
ecap.dlq.events.Project.Created
```

**2. Consumer Error Handling:**
```java
@KafkaListener(topics = "ecap.events.Project.Created", groupId = "notification-service")
public void handle(ConsumerRecord<String, ProjectCreated> record) {
    try {
        // 1. Deserialize event
        ProjectCreated event = record.value();

        // 2. Check inbox
        if (inboxService.isProcessed(event.eventId())) return;

        // 3. Process event
        notificationService.send(event);

        // 4. Mark processed
        inboxService.markProcessed(event.eventId());

    } catch (DeserializationException e) {
        // Malformed event → Send to DLQ
        sendToDLQ(record, e);
        // Commit offset (skip this message)

    } catch (BusinessRuleViolation e) {
        // Business rule failed → Send to DLQ
        sendToDLQ(record, e);

    } catch (TransientException e) {
        // Transient failure (network timeout, etc.) → Retry
        throw e; // Kafka will retry

    } catch (Exception e) {
        // Unknown error → Send to DLQ
        sendToDLQ(record, e);
    }
}

private void sendToDLQ(ConsumerRecord<?, ?> record, Exception error) {
    DLQRecord dlqRecord = DLQRecord.builder()
        .originalTopic(record.topic())
        .originalPartition(record.partition())
        .originalOffset(record.offset())
        .originalKey(record.key())
        .originalValue(record.value())
        .errorMessage(error.getMessage())
        .stackTrace(ExceptionUtils.getStackTrace(error))
        .timestamp(Instant.now())
        .build();

    kafkaTemplate.send("ecap.dlq." + record.topic(), dlqRecord);
}
```

**3. DLQ Monitoring:**
- **Alert:** DLQ messages > 0 → notify engineering team
- **Dashboard:** Track DLQ message count per topic
- **Retry:** Manual replay of DLQ messages after fix

**4. DLQ Replay:**
```bash
# Read DLQ messages
kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic ecap.dlq.events.Project.Created \
  --from-beginning

# After fixing the issue, replay DLQ messages to original topic
# (Manual process or automated replay service)
```

---

## 📊 Monitoring and Observability

### **Key Metrics to Track**

| Metric | Description | Alert Threshold | Action |
|--------|-------------|-----------------|--------|
| **Consumer Lag** | Messages behind | >10,000 msgs | Scale consumers or optimize processing |
| **DLQ Message Count** | Poison messages | >0 | Investigate error patterns |
| **Processing Latency** | Time to process event | >5 seconds | Optimize business logic |
| **Rebalance Frequency** | Consumer group rebalances | >1/hour | Investigate consumer crashes |
| **Partition Skew** | Uneven load across partitions | >20% variance | Repartition or adjust tenant distribution |

### **Monitoring Tools**

1. **Kafka UI (Provectus):** Web UI for topic/consumer management
   - URL: http://localhost:8080
   - Features: View topics, consumers, messages, lag

2. **Kafka JMX Metrics → Prometheus:**
   ```yaml
   # prometheus.yml
   scrape_configs:
     - job_name: 'kafka'
       static_configs:
         - targets: ['kafka:9092']
   ```

3. **Grafana Dashboards:**
   - Consumer Lag by Topic
   - Processing Latency (p50, p95, p99)
   - DLQ Message Count
   - Partition Throughput

---

## 🚀 Topic Creation Strategy

### **Auto-Create vs. Manual Create**

| Approach | Pros | Cons | Recommendation |
|----------|------|------|----------------|
| **Auto-create** | No manual work | Inconsistent config (partitions, retention) | ❌ Avoid in production |
| **Manual create** | Consistent config, explicit control | Manual work for each topic | ✅ Use in production |

**Providence AI Strategy:** **Manual topic creation** via Terraform or Kafka CLI

### **Topic Creation Template**

```bash
#!/bin/bash
# scripts/create-topics.sh

KAFKA_BROKER="localhost:9092"

# Create Project events
kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --topic ecap.events.Project.Created \
  --partitions 12 \
  --replication-factor 3 \
  --config retention.ms=604800000 \
  --config segment.ms=86400000 \
  --config cleanup.policy=delete

kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --topic ecap.events.Project.Updated \
  --partitions 12 \
  --replication-factor 3 \
  --config retention.ms=604800000

kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --topic ecap.events.Project.Archived \
  --partitions 12 \
  --replication-factor 3 \
  --config retention.ms=604800000

# Create DLQ topics
kafka-topics --bootstrap-server $KAFKA_BROKER --create \
  --topic ecap.dlq.events.Project.Created \
  --partitions 1 \
  --replication-factor 3 \
  --config retention.ms=2592000000  # 30 days

# Verify topics
kafka-topics --bootstrap-server $KAFKA_BROKER --list | grep ecap
```

---

## 🔧 Debezium Connector Configuration (Enhanced)

```json
{
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
    "transforms.outbox.table.field.event.key": "tenant_id",
    "transforms.outbox.table.field.event.type": "event_type",
    "transforms.outbox.table.field.event.payload": "payload",
    "transforms.outbox.route.topic.replacement": "ecap.events.${routedByValue}",

    "tombstones.on.delete": "false",

    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "false",
    "value.converter.schemas.enable": "false",

    "snapshot.mode": "initial",
    "heartbeat.interval.ms": "10000",
    "max.batch.size": "2048",
    "max.queue.size": "8192"
  }
}
```

**Key Configuration Explained:**

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `event.key` | `tenant_id` | Partition by tenant (ordering within tenant) |
| `route.topic.replacement` | `ecap.events.${routedByValue}` | Dynamic topic routing based on event_type |
| `snapshot.mode` | `initial` | Take initial snapshot of existing outbox events |
| `heartbeat.interval.ms` | `10000` | Send heartbeat every 10s (keeps replication slot alive) |
| `max.batch.size` | `2048` | Batch size for CDC reads (higher = better throughput) |

---

## 🧪 Testing Kafka Setup

### **1. Start Infrastructure**

```bash
./scripts/setup.sh
```

### **2. Create Topics**

```bash
./scripts/create-topics.sh
```

### **3. Test Outbox → Kafka Flow**

```sql
-- Insert test event
INSERT INTO public.outbox_events (
    id, tenant_id, aggregate_type, aggregate_id, event_type, event_version,
    occurred_at, correlation_id, actor_id, payload
) VALUES (
    gen_random_uuid(),
    '11111111-1111-1111-1111-111111111111',
    'Project',
    gen_random_uuid(),
    'Created',
    1,
    NOW(),
    gen_random_uuid(),
    gen_random_uuid(),
    '{"projectId": "test-123", "name": "Test Project"}'::jsonb
);
```

### **4. Verify Kafka Topic**

```bash
# Check topic was created
kafka-topics --bootstrap-server localhost:9092 --list | grep Project.Created

# Consume message
kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic ecap.events.Project.Created \
  --from-beginning
```

Expected output:
```json
{
  "projectId": "test-123",
  "name": "Test Project"
}
```

---

## 📋 Operational Checklist

### **Before Production:**

- [ ] All topics created manually with consistent config
- [ ] Partition count sufficient for tenant scale (12+ for 10K tenants)
- [ ] Replication factor = 3 (high availability)
- [ ] Retention policies match compliance requirements
- [ ] Debezium connector configured and RUNNING
- [ ] Consumer groups defined with clear ownership
- [ ] DLQ topics created for all event topics
- [ ] Monitoring dashboards configured (consumer lag, DLQ count)
- [ ] Alerting rules configured (lag > threshold, DLQ > 0)
- [ ] Disaster recovery plan documented (topic recreation, offset management)

### **Production Monitoring:**

- [ ] Consumer lag < 10,000 messages (alerts configured)
- [ ] DLQ message count = 0 (alerts on >0)
- [ ] Rebalance frequency < 1/hour
- [ ] Processing latency p95 < 5 seconds
- [ ] Partition utilization balanced (<20% variance)

---

**Status:** Production-ready ✅
**Last Updated:** 2026-02-12
**Maintainer:** Providence AI Engineering Team
