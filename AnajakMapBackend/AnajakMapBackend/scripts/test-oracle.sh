#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Container tests reach Oracle through its private Docker network, without publishing its port.
docker compose exec -T oracle bash -s < scripts/create-test-schema.sh
docker run --rm --network anajakmap_default --env-file .env \
 -e ORACLE_TEST_URL=jdbc:oracle:thin:@oracle:1521/FREEPDB1 -e ORACLE_TEST_USER=TRIP_TEST \
 -v "$PWD:/workspace" -v "${ANJ_MAVEN_REPOSITORY:-/tmp/anajak-oracle-m2}:/root/.m2/repository" -w /workspace \
 maven:3.9.15-eclipse-temurin-21 sh -c 'export ORACLE_TEST_PASSWORD="$TRIP_DB_PASSWORD" ORACLE_RUNTIME_PASSWORD="$TRIP_APP_PASSWORD" EVENT_TEST_PASSWORD="$NOTIFICATION_APP_PASSWORD"; mvn -B -pl platform -am test -Dtest=OraclePersistenceTest,OracleRuntimePermissionsTest,OracleEventDeliveryTest -Dsurefire.failIfNoSpecifiedTests=false'
