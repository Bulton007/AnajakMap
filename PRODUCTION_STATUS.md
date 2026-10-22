# Production status — 22 October 2026

Status: development product with production preparation in progress. Not public
or store-ready. No percentage is assigned because essential dependencies and
acceptance evidence are still missing.

## This implementation

- Dedicated production deployment template with HTTPS proxy, private internal
  ports, production profiles, restricted database accounts, bounded runtime/logs,
  persistent Redis/Rabbit state and external Oracle/private object storage.
- Offline preflight validator and tests; rejects empty/placeholder configuration,
  weak passwords, insecure provider URLs, local API hosts and development modes.
- Android release signing separated from debug; credentials/offline cache excluded
  from backup and device transfer.
- Flutter release gateway safeguards and configurable map tiles/attribution.
- GitHub checks for Flutter analysis/regressions and backend verification.

## Remaining delivery work

| Area | Remaining |
| --- | --- |
| Hosting | Connect OpenShift/Neon accounts, provision database roles/brokers/media storage, deploy and verify TLS |
| Data providers | Replace remaining sample food/culture/weather/routes/transport; verify AI/OCR/voice/translation and currency |
| Accounts | Account deletion/export/retention workflow; verify all provider and deep-link flows |
| Notifications/calendar | Native push SDK/token lifecycle and real delivery; external calendar adapter |
| RPG | Reviewed real destinations, production art, localization, GPS abuse/performance testing |
| Operations | Load/security tests, monitoring/alerts, dependency/image scan, backup/restore drill |
| Mobile | Signing credentials, Android release device tests, iOS archive/device tests |
| Release | Legal/privacy/content review and store metadata/submission |

Deployment instructions: `AnajakMapBackend/AnajakMapBackend/deploy/production/README.md`.
Mobile instructions: `flutter_app/PRODUCTION_RELEASE.md`.
Existing implemented feature contracts: `INTEGRATION.md`.

## Verification in this pass

- Flutter analyzer clean; full suite 82 passed / 1 opt-in live test skipped,
  followed by 5 focused tests passing (including two additional new tests).
- Three production preflight tests passed.
- Production Compose rendered with disposable placeholders using `config --quiet`.
- Caddy configuration validated in a container with networking disabled.
- Android debug manifest compilation passed. A release signing task without
  `key.properties` failed with the intended configuration error.
- No production services were started, no credentials were created, no signed
  release was generated, and no GitHub workflow execution is claimed.

## OpenShift/Neon preparation — 22 October

- Forest-green Flutter theme restored, with colored feature badges rather than
  whole multicolor cards. Compact crystal navigation and backdrop blur retained.
- Flutter: 102 passed, one opt-in test skipped; analyzer clean. Android debug APK
  built; Samsung disconnected before installation of this theme update.
- Nine separate PostgreSQL 17 schema baselines and `neon` profiles added without
  changing the Oracle migration history. JDBC row keys preserve existing APIs.
- Backend: 63 tests, zero failures/errors, three opt-in tests skipped. This
  includes real Flyway migrations for all services, JPA account/preferences
  persistence and all six RPG database tests against disposable PostgreSQL 17.
- OpenShift/Neon renderer: three tests passed. Resources use separate migration
  and runtime Secrets, non-root app containers and an HTTPS gateway-only Route.
- New deployment guide: `AnajakMapBackend/AnajakMapBackend/deploy/openshift-neon/README.md`.
  Play release stages: `flutter_app/PLAY_STORE_RELEASE.md`.
- No live Neon connection, OpenShift deployment, data import, signed AAB or Play
  publication has happened. Account details and live staging validation are next.

## Laptop Nginx testing — 22 October

User selected laptop hosting with a temporary public HTTPS testing URL instead
of proceeding with OpenShift. Nginx and Cloudflare Tunnel now front the existing
local Oracle stack. All persistent containers have restart policies; internal
ports stay private. Local and external proxy checks passed (auth config 200,
protected profile 401, actuator/Swagger/internal paths 404). This remains the
development/test stack with known fixture providers; simulated RPG rewards are
disabled by the laptop overlay. No production uptime or Play readiness is claimed.

See `AnajakMapBackend/AnajakMapBackend/deploy/laptop/README.md`. The current URL
and Flutter configuration are stored only in ignored local files because the
temporary hostname changes on a new tunnel run. Docker Desktop must stay running
after Windows sign-in; plugged-in sleep and hibernation are already Never.
