Validation performed on 2026-09-13 with Microsoft OpenJDK 21.0.10, Maven 3.9.11 and Docker Desktop 29.4.1.

Final outcome: all nine services run with restricted Oracle application users and Gateway readiness UP. Fifteen source tests and three real Oracle/RabbitMQ integration tests passed. The final expanded fourteen-feature smoke passed, including actual S3 upload/download, private journal download rejection and confirmed MOCK_DELIVERED reminders. All eight aggregated OpenAPI specifications returned valid paths. The application image booted with arbitrary UID 1000999000:0 and a read-only root filesystem, then reported readiness UP. The temporary UID test container was removed. Live travel/AI/email/push/calendar adapters remain explicit development fixtures until production endpoints/credentials are configured; OpenShift cluster deployment remains untested.

The initial source test run passed 13 tests with no failures; three Oracle-dependent tests were skipped because their opt-in environment was absent. Twenty-eight YAML files passed SnakeYAML parsing with duplicate keys rejected; shell and Python syntax checks passed.

The current source test suite runs with `./mvnw -B test`: JWT issuer/audience/signature/expiry checks; deterministic hashing; bounded unavailable/slow provider behavior; outbox exhaustion; authenticated randomized secret encryption; media MIME/signature rejection; rollback-safe calendar cache eviction; owner/viewer permissions; empty/invalid AI itinerary and structured response rejection; explicit production configuration failure; mock uncertainty labeling. Oracle tests are opt-in rather than H2 substitutions.

Real Oracle checks ran against `container-registry.oracle.com/database/free:latest`, reporting Oracle 23.26.3. The initial runtime found a boolean schema mapping mismatch and a VARCHAR2(8000) migration error; both were corrected. OraclePersistenceTest then passed against the existing Trip schema and a fresh TRIP_TEST schema, applying all three Trip migrations from scratch and verifying transaction rollback, append-only auditing and conditional optimistic version updates. Flyway emitted a warning that this Oracle release was newer than its tested database matrix; actual migration behavior was exercised, but a production Oracle/Flyway support combination should be validated separately.

All nine service containers started on Oracle with separate service schemas. The executed vertical-slice smoke passed registration, verification, login, versioned preferences, stale edits, trip creation, duplicate protection, place-grounded AI generation, draft saving, approval, calendar/map retrieval, group invitations/acceptance/viewer permissions, expenses/budgets/splits/summary, journal CRUD/stale edits, offline snapshots, translation fixtures, phrase persistence, refresh rotation and logout revocation. The passed demo trip was 9f8f7212-6489-43de-a59e-3f2a78a54ed4. These checks used explicit dev provider fixtures and the earlier API response shape, before the final envelope, restricted-user and additional-feature changes.

The final expanded `scripts/smoke.py` also exercises real S3 media upload, ownership rejection, vision/voice adapters, reservation upload/extract/confirm, receipt-linked expenses, currency fixtures, journal photos/recaps/visits, contacts, location opt-in/out, voting, calendar conflicts/sync, discovery adapters, persisted transport legs, weather-grounded replan approval, reminders and forgot/reset password. It unwraps the final JSON envelope. After Docker recovery, it completed successfully against the final release.

During final image builds the host disk reached approximately 117 MB free and Docker stopped. Only AnajakMap's reproducible jar outputs and its Maven download archive were removed, recovering about 750 MB. Docker could not recover with the remaining capacity. No business database volumes or unrelated project files were deleted. The initial disk blocker was later resolved; the final source, container and integration checks completed successfully. Rebuild jars before using Dockerfile.local because the generated jars were removed during recovery.

Resume verification after freeing at least 5 GB:

```sh
ANJ_ORACLE_FILE=compose.oracle-official.yml ./scripts/start-local.sh
python3 scripts/smoke.py
ANJ_MAVEN_REPOSITORY=/private/tmp/anajak-m2 ./scripts/test-oracle.sh
```

The Oracle script compiles/runs OraclePersistenceTest plus the newly added OracleRuntimePermissionsTest (audit UPDATE/DELETE/trigger modification and cross-schema reads must be denied) and OracleEventDeliveryTest (two confirmed messages with the same ID create one delivery). Those latter two tests were initially blocked, then passed after Docker recovery. Running the test script requires the restricted runtime startup to have completed and Notification to be ready. It creates a disposable TRIP_TEST schema if missing and leaves diagnostic test rows; it does not clean business schemas.

Compose YAML and shell/Python syntax can be checked independently:

```sh
docker compose -f compose.yml -f compose.local.yml -f compose.runtime.yml config --quiet
sh -n scripts/start-local.sh scripts/test-oracle.sh scripts/init-dev.sh
python3 -m py_compile scripts/*.py
```

Never print expanded Compose configuration containing real secrets into shared logs. No live AI/maps/weather/currency/transport/email/push/calendar credentials were provided, and no target OpenShift environment was deployed. Their exact pending integration tests are listed in providers.md. Local MinIO started and its private bucket initialization completed; the final upload/download flow passed after recovery. The source implementation, deterministic mocks and external validation status are tracked in checklist.md.

Recovery verification on 2026-09-13: disk capacity was restored, Docker's stuck backend was relaunched without resetting its disk image, and 6.636 GB of AnajakMap-specific build cache was reclaimed. The startup script completed all final migrations and restricted-user grants. OraclePersistenceTest, OracleRuntimePermissionsTest and OracleEventDeliveryTest all passed (3 tests, 0 failures/errors/skips). Startup found an OpenAPI bean-name collision and typed-map envelope serialization error; both were fixed and covered by new regression tests. The rebuilt source suite passed. Expanded feature smoke verification passed; the earlier disk blocker is resolved. The last passed smoke trip is c0161a56-e5f8-4743-b2dc-155e2e62b116.
