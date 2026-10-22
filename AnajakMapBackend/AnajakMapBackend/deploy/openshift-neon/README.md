# OpenShift + Neon deployment handoff

Prepared for staging; not deployed. The Oracle local stack remains the default.
The new `prod,neon` profiles select PostgreSQL. These baselines initialize **new
empty schemas**; they do not copy existing Oracle accounts/trips or replace an
existing Flyway history. Existing data needs a separately reviewed export/import.

## Account handoff

Provide the OpenShift console URL, project/namespace, Sandbox versus persistent
cluster, image registry/repository, and Neon project/region. Sign into both
consoles yourself. Do not send passwords, API tokens, JDBC passwords, keystores
or SMTP/Gemini credentials through chat. Use local CLI login and cluster Secrets.

Before deployment inspect `oc whoami`, `oc project`, `oc get resourcequota`,
`oc get limitrange`, `oc get storageclass` (if permitted), registry access and
outbound access to Neon/provider endpoints. The manifests request nine JVMs:
3,456Mi memory / 900m CPU total, with limits of 6,912Mi / 9 CPU. This excludes
Redis, RabbitMQ and media storage. Check actual quota; this is not a capacity
guarantee. Red Hat Developer Sandbox expires after 30 days and is a staging
environment, not the permanent Play Store backend.

## Neon database

Use PostgreSQL 17 and a **direct** endpoint for migrations and runtime. Each
service has a separate schema (`identity`, `trip`, `ai_guide`, `discovery`,
`expense`, `reservation`, `journal`, `notification`, `gateway`), owner role and
runtime role. Hikari is limited to two connections per service (18 total).
Account preferences use Hibernate PostgreSQL large objects; schema selection
also relies on session state. Transaction pooling has not been validated.

Use a JDBC URL without credentials:

```text
jdbc:postgresql://YOUR_DIRECT_NEON_HOST/neondb?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory
```

Supply username/password separately through Secrets. Do not turn off certificate
verification to work around connection errors. Create the owner/runtime roles
in the Neon console with separately generated passwords; runtime roles must not
inherit the database owner or migration roles. Create each schema as an admin:

```sql
CREATE SCHEMA identity AUTHORIZATION identity_owner;
-- Repeat with the matching schema and owner for all nine services.
```

Run migration Jobs using owner credentials before runtime deployments. Then run
`grant-runtime.sql` per schema as its owner using psql variables `schema` and
`runtime_role`. Runtime has DML access, not schema creation or Flyway-history
editing. Keep the owner credentials out of runtime Secrets.

## Configuration and images

Build all nine images from the tested backend source using its root Dockerfile:

```sh
docker build --build-arg SERVICE=identity -t REGISTRY/PROJECT/identity-service:COMMIT .
# Repeat for trip, ai-guide, discovery, expense, reservation, journal,
# notification and gateway; push to the chosen private/public registry.
```

The renderer does not build images, create accounts, send credentials or apply
anything. It renders JSON accepted by `oc apply`. It uses the existing namespace
and lets OpenShift assign a non-root UID. No privileged SCC is needed by the app
images; actual cluster admission and image pull permissions still need checking.

Required Secrets, created locally via `oc create secret generic --from-env-file`
or the console (never commit their values):

- `anajak-shared`: `JWT_PUBLIC_KEY`, `SERVICE_TOKEN`, `DATA_ENCRYPTION_KEY`,
  `REDIS_HOST`, `REDIS_PASSWORD`, `RABBIT_HOST`, `RABBIT_USER`, `RABBIT_PASSWORD`,
  `OBJECT_URL`, `OBJECT_REGION`, `OBJECT_BUCKET`, `OBJECT_ACCESS_KEY`,
  `OBJECT_SECRET_KEY`. For external TLS brokers configure the corresponding
  Spring Redis SSL and RabbitMQ address/SSL environment properties.
- `<service>-migration`: `DB_URL`, `DB_USER`, `DB_PASSWORD` for the owner role.
- `<service>-runtime`: `DB_URL`, `DB_USER`, `DB_PASSWORD` for the runtime role,
  plus that service's existing real provider settings. Identity alone receives
  `JWT_PRIVATE_KEY` and mail/legal configuration; AI alone receives Gemini
  configuration. See `.env.example` and service configuration sources for exact
  names. Do not copy the development `.env` wholesale into shared Secrets.

Redis, RabbitMQ and private S3-compatible storage remain required. Neon replaces
the relational database only. Their location, persistence and TLS configuration
must be chosen with the cluster account. This deployment intentionally does not
start the legacy development MinIO image or fixture adapters. Missing production
provider configuration may prevent a service from becoming ready; resolve that
instead of enabling development mode publicly.

## Deploy in stages

Replace the arguments with the actual namespace, registry and immutable release
tag. Render to ignored `.local/` files from the backend root:

```sh
python deploy/openshift-neon/render.py --namespace PROJECT --image-prefix REGISTRY/PROJECT --image-tag COMMIT --stage migrations > .local/migrations.json
oc apply --dry-run=server -f .local/migrations.json
oc apply -f .local/migrations.json
# Wait for all nine *-migrate Jobs to Complete; inspect failed jobs before continuing.
# Apply runtime grants to each schema, then:
python deploy/openshift-neon/render.py --namespace PROJECT --image-prefix REGISTRY/PROJECT --image-tag COMMIT > .local/app.json
oc apply --dry-run=server -f .local/app.json
oc apply -f .local/app.json
oc get deployments,pods,route -n PROJECT
oc get route anajak-api -n PROJECT -o jsonpath='{.spec.host}'
```

Migration Job names are fixed. A subsequent migration release requires new Job
names or explicit removal of completed Jobs after their logs/results are saved;
do not delete running Jobs blindly. Container stdout must go to monitored cluster
logging; `/tmp` logs are temporary. Review network policies and provider egress
with the actual cluster before opening the service to testers.

Validate public HTTPS, mail verification/recovery, login/refresh/logout, trip
CRUD, reviewed itinerary generation, photos, offline synchronization and RPG
ownership/replay on a staging Neon branch. Backup/restore must include account
large objects and media. Do not point a public app at an expiring staging route.
Only then set Flutter's public `API_BASE_URL` and build a signed release bundle.

## Local evidence

All nine PostgreSQL baselines executed on disposable PostgreSQL 17. Flyway repeat
migrations, retry intervals, inbox deduplication and immutable audit were tested.
Hibernate validates the account schema and round-trips verified accounts and
large-object preferences. These checks do not establish live Neon TLS, cluster
admission, provider availability, complete migration of existing data or load
capacity. All six RPG persistence tests passed on PostgreSQL, covering reward
atomicity, replay/ownership, rollback, captures, inventory/party and progression.
The backend suite finished with 63 tests, zero failures/errors and three skipped
opt-in tests. Renderer tests: three passed.

References: [Neon Java](https://neon.com/docs/guides/java),
[JDBC SSL validation](https://jdbc.postgresql.org/documentation/ssl/),
[Red Hat Sandbox FAQ](https://developers.redhat.com/developer-sandbox/FAQ).
