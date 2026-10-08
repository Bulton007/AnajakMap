# AnajakMap

Backend for an AI Travel Companion, with nine independently runnable Java 21 / Spring Boot microservices and documented APIs for a future Flutter Android/iOS app. No frontend, ticket purchasing, payments, packing lists or departure checklists are included.

## How to run the Spring Boot microservices

### Prerequisites

Install the following tools before starting the project:

- Docker Desktop with at least 8 GB of memory available
- Java 21
- Python 3
- OpenSSL

Make sure Docker Desktop is running, then open a terminal in the project root.

### Start all services

The recommended local setup uses the official Oracle Database image:

```sh
ANJ_ORACLE_FILE=compose.oracle-official.yml ./scripts/start-local.sh
```

On the first run, the script:

1. Creates `.env` with local development secrets if it does not exist.
2. Builds and tests all Maven modules.
3. Starts Oracle, Redis, RabbitMQ, and MinIO.
4. Creates the database schemas and applies migrations.
5. Builds and starts all nine Spring Boot microservices.

The first startup can take several minutes while Docker downloads images and Oracle becomes healthy.

To use the smaller alternative Oracle image instead, run:

```sh
./scripts/start-local.sh
```

### Verify the services

Check the gateway readiness endpoint:

```sh
curl http://127.0.0.1:8080/actuator/health/readiness
```

When startup is complete, it returns:

```json
{"status":"UP"}
```

Run the end-to-end smoke tests:

```sh
python3 scripts/smoke.py
```

Local endpoints:

- API: http://127.0.0.1:8080/api/v1
- Swagger UI: http://127.0.0.1:8080/swagger-ui/index.html
- Readiness: http://127.0.0.1:8080/actuator/health/readiness

Only the gateway is exposed to the host. Oracle, Redis, RabbitMQ, MinIO, and the individual services remain private inside the Docker network.

### View status and logs

For the official Oracle setup:

```sh
docker compose -f compose.yml -f compose.oracle-official.yml -f compose.local.yml -f compose.runtime.yml ps
docker compose -f compose.yml -f compose.oracle-official.yml -f compose.local.yml -f compose.runtime.yml logs -f
```

Press `Ctrl+C` to stop following the logs; this does not stop the containers.

### Stop or restart the services

Stop all containers while keeping database and application data:

```sh
docker compose -f compose.yml -f compose.oracle-official.yml -f compose.local.yml -f compose.runtime.yml down
```

Start the existing containers again:

```sh
docker compose -f compose.yml -f compose.oracle-official.yml -f compose.local.yml -f compose.runtime.yml up -d
```

If you used the alternative Oracle image, remove `-f compose.oracle-official.yml` from these lifecycle commands. Do not add `-v` to `down` unless you intentionally want to delete all local database and service data.

### Build or test without Docker startup

Run all unit tests:

```sh
./mvnw -B test
```

Build all service JAR files:

```sh
./mvnw -B package
```

Oracle tests are opt-in and never substitute H2. Set ORACLE_TEST_URL, ORACLE_TEST_USER and ORACLE_TEST_PASSWORD for a disposable schema with CREATE SESSION/TABLE/TRIGGER privileges and a quota, then run:

```sh
./mvnw -pl platform -am test -Dtest=OraclePersistenceTest -Dsurefire.failIfNoSpecifiedTests=false
```

The test applies Trip's migrations from an empty schema, checks rollback, append-only auditing and conditional version updates. See [validation](docs/validation.md) for the exact local checks and their results. The smoke script creates demo accounts/trips and exercises all fourteen feature areas. Development fixtures are clearly marked and are available only under dev/test profiles.

Configuration lives outside source in `.env` (gitignored). [The environment example](.env.example) contains placeholders; `scripts/init-dev.sh` creates random development credentials and RSA keys without overwriting existing files. Never regenerate passwords while retaining an existing database volume unless you intentionally rotate the matching database accounts. Each service can run using its own jar and environment variables; service ports are 8081–8089 in the order listed in [architecture](docs/architecture.md).

Production has no mock fallback. Read [provider contracts and blocked live tests](docs/providers.md) before configuring a provider. The HTTP adapters target explicit normalized provider contracts; they do not pretend to be direct vendor SDK integrations. Media uses actual S3 Signature V4. [OpenShift deployment instructions](docs/deployment.md) cover migration owners, runtime secrets, persistent logs, readiness, routing and cluster prerequisites. No external deployment has been performed.

API JSON success responses contain `data`, `traceId` and `timestamp`. Errors contain `code`, `message`, `traceId` and `timestamp`. Binary media endpoints return their MIME type and no-store caching. SQL-backed projection keys are uppercase Oracle column names; OpenAPI and [examples](docs/api-examples.md) explain the flow. Version conflicts return 409; fetch the current record or offline snapshot, reconcile edits, and resubmit with its version. Do not automatically overwrite a stale server version.
