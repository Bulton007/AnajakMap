#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
[ -e .env ] || ./scripts/init-dev.sh
./mvnw -B package
# Uses the optional Oracle image override only if explicitly selected.
ANJ_ORACLE_FILE=${ANJ_ORACLE_FILE:-compose.yml}
if [ "$ANJ_ORACLE_FILE" = compose.yml ]; then
 docker compose -f compose.yml -f compose.local.yml up -d oracle redis rabbitmq minio object-init
else
 docker compose -f compose.yml -f "$ANJ_ORACLE_FILE" -f compose.local.yml up -d oracle redis rabbitmq minio object-init
fi
ANJ_READY=false
for attempt in $(seq 1 120); do
 if [ "$(docker inspect -f '{{.State.Health.Status}}' "$(docker compose ps -q oracle)")" = healthy ]; then ANJ_READY=true; break; fi
 sleep 2
done
[ "$ANJ_READY" = true ] || { echo 'Oracle failed to become healthy'; exit 1; }
docker compose exec -T oracle bash /container-entrypoint-initdb.d/01-schemas.sh
# Build the final jars into non-root application images.
docker compose -f compose.yml -f compose.local.yml build
for service in identity trip ai-guide discovery expense reservation journal notification gateway; do
 docker compose -f compose.yml -f compose.local.yml run --rm --no-deps -e MIGRATE_ONLY=true "$service-service"
done
docker compose exec -T oracle bash -s < scripts/grant-runtime.sh
if [ "$ANJ_ORACLE_FILE" = compose.yml ]; then
 docker compose -f compose.yml -f compose.local.yml -f compose.runtime.yml up -d
else
 docker compose -f compose.yml -f "$ANJ_ORACLE_FILE" -f compose.local.yml -f compose.runtime.yml up -d
fi
printf 'AnajakMap is starting at http://127.0.0.1:8080. Run python3 scripts/smoke.py after readiness is UP.\n'
