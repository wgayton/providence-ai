# Providence AI - Enterprise SaaS Platform

> Multi-tenant Project, Resource, Fund, and Human Management platform with event-driven architecture

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Java](https://img.shields.io/badge/Java-25+-orange.svg)](https://openjdk.org/)
[![Spring Boot](https://img.shields.io/badge/Spring%20Boot-4.x-green.svg)](https://spring.io/projects/spring-boot)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17+-blue.svg)](https://www.postgresql.org/)
[![Kafka](https://img.shields.io/badge/Kafka-3.6+-black.svg)](https://kafka.apache.org/)

## 🎯 Overview

Providence AI is a **production-ready, enterprise-grade multi-tenant SaaS platform** that provides:

- **Project Management** — Create, track, and organize projects
- **Resource Management** — Allocate personnel, equipment, and budget
- **Fund Management** — Financial transactions with double-entry accounting
- **Human Management** — User, role, and team management with RBAC

### Key Features

✅ **Schema-per-tenant isolation** — Complete data separation for 10,000+ tenants
✅ **Event-driven architecture** — Debezium CDC + Kafka for guaranteed event delivery
✅ **Universal idempotency** — All operations are replay-safe (network failures don't cause duplicates)
✅ **Immutable audit logging** — SOC 2, GDPR, HIPAA compliance-ready
✅ **Clean Architecture** — Domain-driven design with clear layer boundaries
✅ **Financial correctness** — Idempotent transactions, immutable ledger entries

---

## 🚀 Quick Start

Get the entire stack running in under 5 minutes:

```bash
# 1. Clone the repository
git clone https://github.com/wgayton/providence-ai.git
cd providence-ai

# 2. Start infrastructure (PostgreSQL, Redis, Kafka, Debezium)
./scripts/setup.sh

# 3. Verify everything is working
./scripts/verify.sh

# 4. Start the application
./gradlew bootRun
```

**Services will be available at:**
- **API:** http://localhost:8080
- **Kafka UI:** http://localhost:8080 (Kafka management)
- **PostgreSQL:** localhost:5432 (user: `providence`, password: `providence_dev_password`)
- **Redis:** localhost:6379 (password: `redis_dev_password`)

For detailed setup instructions, see [Getting Started Guide](docs/guides/GETTING_STARTED.md).

---

## 📚 Documentation

### **Architecture**
- [Engineering Standards](docs/architecture/ENGINEERING_STANDARDS.md) — Master coding standards, patterns, and best practices
- [Multi-Tenant Design](docs/architecture/MULTI_TENANT_DESIGN.md) — Schema-per-tenant architecture, tenant isolation patterns
- [Database Schema](docs/architecture/DATABASE_SCHEMA.md) — Public schema design, table specifications, queries
- [Event Streaming](docs/architecture/EVENT_STREAMING.md) — Kafka topics, partitioning, retention, DLQ strategy

### **Guides**
- [Getting Started](docs/guides/GETTING_STARTED.md) — Local development setup, troubleshooting, daily workflow
- [Testing Guide](docs/guides/TESTING_GUIDE.md) — Unit, integration, and end-to-end testing strategies *(Coming Soon)*
- [Deployment Guide](docs/guides/DEPLOYMENT.md) — Production deployment, monitoring, operations *(Coming Soon)*

### **Examples**
- [Project Management](docs/examples/PROJECT_MANAGEMENT.md) — Complete feature implementation with all patterns
- [Resource Management](docs/examples/RESOURCE_MANAGEMENT.md) — Feature skeleton for pattern replication

---

## 🏗️ Architecture

### Technology Stack

| Layer | Technology | Version |
|-------|------------|---------|
| **Language** | Java (LTS) | 25+ |
| **Framework** | Spring Boot | 4.x |
| **Database** | PostgreSQL | 17+ |
| **Cache** | Redis | 7+ |
| **Event Streaming** | Apache Kafka | 3.6+ |
| **CDC** | Debezium | 2.5+ |
| **API** | REST (Spring MVC) + gRPC | — |

### Multi-Tenant Isolation

```
┌─────────────────────────────────────────────────────────────────┐
│                      PostgreSQL Database                         │
├─────────────────────────────────────────────────────────────────┤
│  PUBLIC SCHEMA (cross-tenant infrastructure)                    │
│  • tenants          — Tenant registry                           │
│  • outbox_events    — Debezium CDC source                       │
│  • audit_log        — Immutable audit trail                     │
│  • idempotency_keys — Universal idempotency                     │
│  • inbox_events     — Consumer deduplication                    │
│                                                                  │
│  TENANT SCHEMAS (one per tenant)                                │
│  • t_acme           — Acme Corporation data                     │
│  • t_globex         — Globex Corporation data                   │
│  • t_initech        — Initech data                              │
│  • ... (10,000+ tenants)                                        │
└─────────────────────────────────────────────────────────────────┘
```

Each tenant has a **dedicated PostgreSQL schema** (`t_<tenant_slug>`), providing complete data isolation at the database level.

### Event-Driven Architecture

```
Application → public.outbox_events → Debezium CDC → Kafka → Consumers
                (Transaction)         (At-least-once)   (Exactly-once via inbox)
```

All state changes emit events to Kafka for:
- Real-time notifications
- Search indexing (Elasticsearch/Algolia)
- Analytics and reporting
- Cross-service communication

---

## 🧪 Testing

```bash
# Run all tests
./gradlew test

# Run integration tests only
./gradlew integrationTest

# Run with coverage
./gradlew test jacocoTestReport
```

**Test Coverage Requirements:**
- Unit tests: 80%+ line coverage
- Integration tests: 100% endpoint coverage
- All tests use Testcontainers (PostgreSQL, Kafka, Redis)

---

## 📦 Building

```bash
# Build JAR
./gradlew build

# Build Docker image
docker build -t providence-ai:latest .

# Build and run
./gradlew bootRun
```

---

## 🚢 Deployment

### Prerequisites

- **Java 25+** with virtual threads enabled
- **PostgreSQL 17+** with logical replication (`wal_level=logical`)
- **Redis 7+** for caching
- **Kafka 3.6+** with Debezium Connect
- **Kubernetes 1.28+** (for production)

### Environment Variables

```bash
# Database
SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/providence
SPRING_DATASOURCE_USERNAME=providence
SPRING_DATASOURCE_PASSWORD=${DB_PASSWORD}

# Redis
SPRING_REDIS_HOST=redis
SPRING_REDIS_PASSWORD=${REDIS_PASSWORD}

# Kafka
SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:9092

# Security
JWT_SECRET=${JWT_SECRET}
```

For detailed deployment instructions, see [Deployment Guide](docs/guides/DEPLOYMENT.md) *(Coming Soon)*.

---

## 📊 Monitoring

### Metrics Exposed

- **Application:** Micrometer metrics at `/actuator/metrics`
- **Kafka:** Consumer lag, processing latency, DLQ message count
- **Database:** Connection pool utilization, query performance
- **Events:** Outbox publish rate, inbox processing rate

### Health Checks

- **Liveness:** `/actuator/health/liveness` (Kubernetes liveness probe)
- **Readiness:** `/actuator/health/readiness` (Kubernetes readiness probe)

---

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

1. **Read the standards:** [Engineering Standards](docs/architecture/ENGINEERING_STANDARDS.md)
2. **Use the pattern:** See [Project Management Example](docs/examples/PROJECT_MANAGEMENT.md)
3. **Write tests:** All features require unit + integration tests
4. **Follow commits:** Use conventional commits (feat:, fix:, docs:)
5. **Create PR:** Use our [Pull Request Template](.github/PULL_REQUEST_TEMPLATE.md)

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **Debezium** — Change Data Capture for outbox pattern
- **Spring Boot** — Application framework
- **PostgreSQL** — Multi-tenant database
- **Apache Kafka** — Event streaming platform

---

## 📞 Support

- **Documentation:** [docs/](docs/)
- **Issues:** [GitHub Issues](https://github.com/wgayton/providence-ai/issues)
- **Discussions:** [GitHub Discussions](https://github.com/wgayton/providence-ai/discussions)

---

**Built with ❤️ by the Providence AI Team**
