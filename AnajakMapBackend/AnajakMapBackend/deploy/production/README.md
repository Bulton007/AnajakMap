# Production deployment preparation

This is a separate, undeployed Compose stack. It does not reuse the local `.env`,
database volumes, development profiles, source-built legacy MinIO, or test mail
adapter. Do not expose the development Compose stack to the internet.

## Required before first deployment

- A Linux Docker host, a public API domain pointing to it, and SSH access.
- Private Oracle with all nine owner schemas migrated, then restricted `_APP`
  users granted access. Use the existing schema/migration/grant process with
  separate production credentials. Do not run migrations with runtime accounts.
- A maintained S3-compatible service with a private bucket, narrowly scoped keys,
  versioning/retention and a tested restore procedure.
- Published images for all nine services, built from a tested commit using the
  root backend Dockerfile (`--build-arg SERVICE=identity`, and so on). `IMAGE_PREFIX`
  is the registry/repository prefix; `IMAGE_TAG` is a unique commit/release tag.
  Lock deployment images to reviewed digests before launch.
- Real API adapters for discovery, currency, AI and push matching the backend
  contracts. These variables are **not generic provider API URLs**: the adapters
  must implement the paths/payloads used in the Java classes. A Google/Gemini key
  alone does not implement all of them. Photon supplies only place search.
- Gmail SMTP sender + app password, or a real mail adapter; reviewed public legal
  URLs and policy version. No secret belongs in Flutter configuration.

Nine JVMs are retained from the current architecture. Their configured memory
ceilings total 6.75 GiB, excluding RabbitMQ, Redis, Docker, OS and external Oracle.
Measure actual use and load-test before choosing the server. This is not a tested
capacity promise for a small VPS, and it is not a Kubernetes deployment.

## Configure and start

From this directory on the server:

```sh
cp .env.example .env
chmod 600 .env
# Fill .env locally using your secret manager/editor.
python3 preflight.py --env-file .env
docker compose --env-file .env config --quiet
docker compose --env-file .env pull
# Only after database migrations, grants and provider verification:
docker compose --env-file .env up -d
docker compose ps
docker compose exec -T gateway-service \
  wget -qO- http://127.0.0.1:8089/actuator/health/readiness
```

Do not print `docker compose config` without `--quiet`: resolved configuration
contains secrets. The preflight check prints field names, never their values.
It checks configuration shape, not credential validity or provider availability.

Only Caddy publishes ports 80/443. Restrict SSH to administrator addresses. Keep
Oracle, Redis, RabbitMQ and service ports private. Configure DNS A/AAAA records
correctly; remove unusable IPv6 records. Caddy requests and renews certificates
when the real domain and reachable ports are available. Its persistent data
volume contains certificate material; protect it. See
[Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https).

The proxy exposes `/api/v1/*` only. Actuator, API docs and internal routes are not
public. Exact web CORS origins may be configured; native Android/iOS does not need
CORS. Runtime applications use read-only filesystems, dropped capabilities and
bounded log storage. Logs in tmpfs are temporary; send stdout to a durable log
system before launch. Configure alerts for readiness failures, error rate,
queue backlog, storage, certificate expiry and backup failures. Restart policies
restart exited containers; an unhealthy container is not automatically repaired.

## Release and recovery checks

1. Back up Oracle, media, Redis/Rabbit persistent state and encryption/signing
   keys. Keep encrypted off-host copies and document key recovery.
2. Restore into an isolated environment and prove account login, trip retrieval,
   queued operations and private media download work. Record restore duration.
3. Check email verification/reset, rotating refresh, expired sessions,
   account isolation, uploads, real itinerary generation and RPG authorization
   against production-like data.
4. Exercise the signed Android build and an iOS archive on physical devices.
5. Set Flutter `API_BASE_URL=https://YOUR_DOMAIN/api/v1/`. Do not distribute a
   localhost/USB configuration.
6. For rollback, retain the previous immutable image tag and deploy it only if
   the migrated schema remains backward compatible. Do not auto-downgrade Oracle
   or delete volumes. For incompatible schema changes use the reviewed recovery
   plan and backup, with an explicit data-loss window.

## Known launch blockers

No server/domain, live provider adapter suite, production database/media setup,
release signing credentials, restore drill or iOS validation has been supplied.
Native push registration, account deletion/data-retention handling, production
RPG content review and art/performance work remain engineering tasks. A successful
Compose render is not a completed production deployment.
