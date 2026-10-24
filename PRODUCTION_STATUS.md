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

## Companion and signed testing update — 24 October

- Built and signature-verified Android 1.0.1, version code 3, target SDK 36,
  using the existing app ID `com.anajak.anajak_travel` and local upload keystore.
- Flutter: 108 tests passed, one opt-in live test skipped; analyzer clean.
  Reviewed and updated the two registration-unavailable screen goldens.
- AI module: 27 tests passed with mocked provider responses. Conversation
  ownership, default-off context, text/metadata bounds and provider request
  sanitization are covered. Shared platform tests also passed with four optional
  database checks skipped in this run.
- Chat now retains confirmed turns in the open screen, supports suggested
  questions/copying, preserves failed drafts and honors server retry timing.
  Sharing up to 12 previous messages requires the explicit English/Khmer switch;
  older clients keep latest-question-only behavior.
- New-PC `Update AI.cmd` validates a local Gemini key/model with one fictional
  request, builds and restarts only the AI service. Script success/failure paths
  were checked with simulated Google/Docker operations in Windows PowerShell 5.1.
- The backend update has not been applied to the separate hosting PC by this
  agent. Live Gemini acceptance and physical-device testing of build 3 remain
  pending there. No new Play Console upload or publication is claimed.

Instructions and limits: `AI_UPDATE.md`. Other production dependencies above
remain outstanding; this testing update is not a claim that every feature is ready.

## Audit and Android testing update 1.0.2 — 24 October

- Preserved the existing architecture and completed batches documented in
  `APP_AUDIT.md`: confirmed-save feedback, photo fallbacks/caching, current GPS
  and real-provider routing adapter, destination weather, fixed 4000 KHR/USD,
  readable dates/IDs, contact/notification cards, consent-gated photo recognition,
  foreground random encounters, absolute expiry and responsive inventory.
- Final Flutter regression: 126 passed / one opt-in live test skipped;
  analyzer clean. Backend: 61 passed / 10 optional database checks skipped.
  Model/provider requests were mocked; no user photo was sent to Google.
- Signed Android 1.0.2, version code 4, target SDK 36 built successfully and
  upload signature verified. Artifact: `.local/anajakmap-1.0.2-4.aab`.
  Added the missing Cupertino icon font; final build has no missing-font warning.
- New-PC source patch: `.local/anajak-backend-update-1.0.2.zip` with
  `Update App Backend.cmd`. See `APP_UPDATE_SETUP.md`. No credentials included.
  Updater syntax and laptop Compose configuration were validated; no update was
  run on the separate hosting PC and no Play Console release was uploaded.
- Photo recognition stays default-off until the operator verifies the configured
  image model. Real router URL, destination cultural content, native push, reviewed
  gameplay locations, stable public hosting, iOS and physical-device acceptance
  remain dependencies. This is an internal-testing update, not production approval.

## Extracted backend patch installer fix — 24 October

- Fixed the missing `.env` update path: a complete extracted patch can install
  its allowlisted source files into the one initialized hosting checkout, retaining
  credentials and backing up overwritten source files before copying.
- Added ambiguity/explicit-target guards, path/junction rejection, full validation
  before writes, source hash checks, and a read-only `-CheckOnly` preview.
- Windows PowerShell 5.1: 23 regression checks passed. Simulated full installation
  verified overlay copying, backup creation, child updater execution and unchanged
  `.env`; no real backend was restarted during these tests.

## Runtime readiness recovery — 24 October

- Replaced the invalid Docker `State.Health.Status` lookup with per-container
  Actuator readiness checks; local Spring images have no Docker healthcheck.
  Added bounded startup retries and an existing-image `-SkipBuild` recovery path.
- The updater now starts stopped dependencies and includes an existing tunnel
  overlay without removing/restarting the tunnel container.
- Windows PowerShell 5.1: 20 readiness tests and 23 source-installer tests passed;
  the full isolated updater/skip-build check also passed.
- Live recovery on this workspace PC resumed Oracle/Redis/RabbitMQ/media and all
  backend services. AI guide, discovery and expense returned readiness UP.
  Local and current public tunnel checks passed: auth config 200, unauthenticated
  profile 401, internal/Actuator/Swagger paths blocked with 404. Registration and
  email delivery are configured; no inbox delivery or Gemini generation was tested.
- Fixed temporary URL extraction to read only the current container session's
  logs and select the latest URL, avoiding stale URLs after a tunnel restart.
  `flutter_app/config/connected.public.local.json` was refreshed locally and stays
  ignored. Existing installed builds need rebuilding when their tunnel URL changes.
- Three additional isolated tunnel-startup regressions passed: retained logs are
  excluded, the latest current-session URL wins, and missing URL logs leave the
  existing Flutter configuration untouched. No Samsung device was connected for
  physical-device testing during this runtime recovery.
