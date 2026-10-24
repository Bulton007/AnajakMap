# Anajak audit and implementation checklist — 24 October 2026

Existing app is retained: Flutter/Riverpod/go_router/Dio/secure storage/Drift;
nine Spring Boot services, Oracle, Redis, RabbitMQ and private media behind Nginx.
Repository review covered entry/routing/tokens, connected screens, repositories,
cache/outbox, discovery/photo adapters, AI/chat/media, expenses, notifications and
the server-authoritative RPG. Prior baseline: 108 Flutter tests passed, one live
test skipped; AI module 27 tests passed. Those are test results, not live feature
acceptance on the separate hosting PC.

| Batch | Existing implementation | Confirmed gap / next action |
|---|---|---|
| A: feedback/photos | Shared cards/tokens, licensed temple photo, Wikimedia credit UI, optional photo enrichment | Loading and missing photo look identical; 150/170px image jump; absent global success feedback; add reusable reduced-motion temple success component |
| B: map/navigation | OSM tiles/attribution and valid place markers; Google component remains optional | No route geometry/current-position tracking in OSM widget; no real built-in routing adapter; add explicit location/permission states and verified provider geometry only |
| C: destination/money/IDs | Trip-zone formatters, search revision protection, exact decimal server amounts | Discovery weather/culture fixtures; currency fixture uses **4100**, conflicting with required fixed **4000**; profile exposes raw UUID; audit raw date/money rows |
| D: AI/alerts/safety | Text Gemini chat/translation/planning, owned bounded opt-in context, in-app notification records | Voice/vision disabled in live Gemini adapter; native push not provisioned; emergency contacts exist as trip records but no focused emergency dialing screen |
| E: offline | Account+gateway scoped Drift snapshots/bookmarks/outbox; explicit retries, conflict review | Images have memory caching only; selected destination info not durably cached; no offline tiles/AI/live routes; preserve truthful stale-data labels |
| F: RPG | Seeded randomness in engine; server cooldown/daily limits/expiry/ownership/idempotency; procedural 3D creature renderer | Inventory list, raw expiry timestamp, no client expiry countdown/resume guard; automatic travel encounter notification policy absent |
| G: verification | Broad unit/widget/golden suite; signed Play internal-test bundles | Recheck each batch and rebuild; physical-device/new-PC acceptance remains external |

## Security and external dependencies

- Preserve `.env`, signing keys, databases and existing uncommitted auth/AI work.
- Keep Google/Gmail credentials server-only. Conversation context is default-off.
  User approved consent-based selected-photo export to Gemini; runtime consent
  and the default-off verified-model flag are required before photo processing.
- Public hosting is a temporary tunnel on another PC. Patches here do not update
  that PC until transferred/applied. No stable uptime, production deployment or
  public Play rollout is claimed.
- Remaining development discovery/notification providers must not be presented
  as live. Native push requires a real project/device-token integration; real
  routing, weather and recognition require supported adapters and provider terms.
- Account deletion/retention, privacy review, backups and production operations
  remain release dependencies.

## Batch verification log

Implementation starts with A; later entries record actual changes/checks and
remaining dependencies. No percentage-complete claim is used.

### A — implemented

- Added the code-native three-tower temple success illustration, fade/scale and
  sparkles in reusable `travel_success.dart`; reduced motion disables animation.
- Shared confirmed-save forms, downloaded trips and bookmarked recommendations
  use it. Fixed `ConnectedPlace` incorrectly showing success after a failed cache
  write. Existing network errors and operation identifiers remain intact.
- `place_photo.dart`: stable 170px loading/error/missing states, explicit retry,
  bounded 1200px decode, existing Flutter image cache, valid HTTPS-only sources,
  retained license credit and no misleading destination fallback photograph.
- Changed files: `shared/components/{place_photo,travel_success,remote}.dart`,
  `features/connected/{connected_explore,recommendations,connected_offline}.dart`,
  `test/shared_feedback_test.dart` (all paths under `flutter_app/lib` except test).
- Verification: 12 focused feedback/connected/recommendation tests passed.
  A formatter parse regression in `remote.dart` was fixed before testing; one
  analyzer brace lint was corrected. Durable photo caching remains for E.

### B — implemented; live router configuration outstanding

- Red destination pins, blue current-position/origin markers, validated GeoJSON
  polylines, camera bounds, actual metric estimates and explicit no-traffic label.
- Explicit foreground permission explanation, settings action, denied states,
  location stream cleanup on suspension/dispose/hidden route; reroutes only after
  100m displacement and at least 30 seconds. No background permission requested.
- Existing `/discovery/routes` now uses `OsrmRoutes` instead of development route
  numbers. Requires operator-configured `OSRM_URL`; driving only. Unsupported
  modes, missing router and no-route responses never invent a route. OSM credit
  remains. Explore's route chip opens the real map flow.
- Changed: `features/maps/{open_map_screen,map_location}.dart`,
  `shared/models/map_route.dart`, `core/network/travel_repository.dart`,
  `features/connected/{connected_map,connected_explore}.dart`, `app/theme/theme.dart`,
  `test/open_map_test.dart`; backend `discovery-service/.../{DiscoveryApi,OsrmRoutes}.java`,
  `.../test/.../OsrmRoutesTest.java`, `compose.local.yml`.
- Verified: 8 focused map/connected tests passed; analyzer clean; discovery module
  17 tests passed / 6 optional database checks skipped. No live routing provider
  was configured or called. API reference: https://project-osrm.org/docs/v26.4.0/http

### C — implemented; destination culture still requires real editorial/provider data

- Removed the 4100/EUR development conversion fixture. `CurrencyApi` now uses
  one configurable `APP_KHR_PER_USD=4000` BigDecimal rate for USD/KHR, with half-up
  cash rounding and an explicit fixed/non-market label. Other pairs require a
  configured provider. Stored balances and transaction writes are untouched.
- Added exact decimal/locale money display, shortened visible account ID with
  explicit full-ID copy, and suppression of technical IDs in generic user cards.
  Extended generic date formatting to expiry/download/retry timestamps.
- Added coordinate-scoped Open-Meteo weather with 15-minute caching, original
  observation timestamp and provider attribution. No sunny fallback on failure.
  Local testing defaults to Open-Meteo; its free endpoint's non-commercial terms
  must be reviewed before production/commercial use: https://open-meteo.com/en/docs
- Changed: backend `CurrencyApi.java`, `CurrencyApiTest.java`, `DestinationWeather.java`,
  `DestinationWeatherTest.java`, `DiscoveryApi.java`, `compose.local.yml`;
  Flutter `shared/formatting/travel_money.dart`, `shared/components/remote.dart`,
  `features/connected/{connected_shell,offline_trip_cards,discovery_details}.dart`,
  `test/travel_money_test.dart`.
- Verified: 7 focused money/date/panel tests passed; expense module 3 passed;
  discovery module 19 passed / 6 optional database tests skipped; analyzer clean
  after correcting three brace lints. Live destination weather and actual device
  timezones still need hosting/device acceptance.

### D — implemented with external capabilities left explicitly unavailable

- Existing opt-in bounded chat context is preserved. Added authenticated
  `GET /api/v1/guide/capabilities`; old/missing capability endpoints disable photo
  recognition safely. `GEMINI_VISION_ENABLED=false` by default. The hosting
  operator must verify the configured model's image/structured-output support.
- User approved selected-photo sharing. The app asks consent before opening
  upload, restricts recognition to JPEG/PNG up to 4 MiB, prevents duplicate
  submissions, and shows uncertain candidates/explanation rather than raw JSON.
  Backend rechecks capability, consent, media ownership, type/size and bounded
  results. Only the image and language go to Gemini, never account metadata.
  Automated tests use mocked Google responses; no photo was sent to Google.
- Added explicit contact dialer actions and notification cards with readable
  dates/status. Delivery rows are deduplicated by ID. Simulated delivery remains
  labelled; no native push or voice integration is falsely claimed.
- Changed: backend `ai-guide-service/src/main/java/com/anajakmap/aiguide/`
  `{GuideProvider,GuideAdapters,GuideApi,GeminiGuideProvider}.java`,
  `src/test/java/com/anajakmap/aiguide/GeminiVisionTest.java`, `compose.local.yml`;
  Flutter `core/network/{providers,travel_repository}.dart`,
  `features/connected/{connected_tools,connected_upload}.dart`,
  `shared/components/{travel_panels,travel_alerts}.dart`,
  `test/{photo_consent,travel_alerts}_test.dart`.
- Verified: AI module 30 tests passed, including default-off/cancelled consent,
  image bounds and metadata exclusion. Alert/chat focused suite 6 passed; final
  consent/policy/adventure suite 12 passed. Analyzer clean. A missing Strings
  delegate in the new test fixture was fixed before the successful rerun.
- Still external: supported model confirmation, deployed privacy/retention
  review for photos, native push project/token plumbing and voice provider.

### E — implemented bounded destination/photo caching; existing outbox retained

- Drift stores account-and-gateway-scoped Wikimedia thumbnails (32 × 512 KiB
  maximum) and non-mock destination information (40 entries). Thumbnails use a
  separate unauthenticated HTTP client, exact HTTPS host restriction, no redirects,
  bounded streaming and image signature checks. Attribution stays visible.
- Destination requests preserve original timestamps; failed requests show an
  explicitly stale saved copy and manual retry. Different destinations/accounts
  cannot reuse one another's entries. Optional photo failures remain nonfatal.
- Existing trip snapshots, explicit outbox retry/idempotency and conflict review
  remain unchanged. No offline AI or bulk map tile download is claimed.
- Changed: Flutter `core/storage/{travel_database,place_photo_cache}.dart`,
  `core/network/providers.dart`, `features/connected/{cached_discovery,connected_explore}.dart`,
  `shared/components/{offline_place_photo,place_photo,visual}.dart`,
  `test/place_photo_cache_test.dart`.
- Verified: 12 focused cache/connected/chat/alert tests passed; all three new
  cache tests cover offline reads, account isolation, unsafe/oversized input and
  bounded pruning without deleting trip snapshots. Analyzer warnings for two
  unnecessary assertions were fixed before the clean run.

### F — implemented foreground random discovery and expiry/inventory improvements

- Optional foreground discovery rolls with controlled Random input, default 25%
  probability and five-minute check cooldown. Checks happen once a minute only
  on the current resumed adventure screen with explicit safety/feature opt-in.
  No roll on every GPS update. Server still chooses weighted species and enforces
  reviewed destinations, accurate recent location, level/daily/cooldown limits,
  ownership and idempotency. No client-generated reward or background GPS.
- Newly discovered encounters show the existing procedural 3D scene with Fight,
  Ignore (server retreat), and absolute server countdown. Expired battle actions
  are disabled and the active visual is removed; refresh reconciles server state.
  Countdown stops in background and recalculates on resume. Server duration is
  configurable (60–3600 seconds, default 900), including exact expiry boundary.
- Inventory uses the existing responsive equal-height grid, with one column at
  large text/narrow widths. Purchase actions and prices remain server-backed.
  Reward/transaction timestamps are formatted. Bestiary is collapsed and clearly
  labelled as a guide, not nearby encounters. Existing 3D rendering is preserved.
- Added readable action icons for strike/magic/burst/guard/heal/capture/retreat.
  Included the cached Cupertino icon font package (`pubspec.yaml`,
  `pubspec.lock`) after the release compiler identified a missing font family.
- Changed: Flutter `features/rpg/{adventure_controller,adventure_screen,adventure_management,
  encounter_countdown,encounter_policy}.dart`, `test/{adventure,encounter_policy}_test.dart`;
  backend `discovery-service/src/main/java/com/anajakmap/discovery/rpg/RpgService.java`,
  `compose.local.yml`.
- Verified: original RPG regression 20 tests passed, then policy/consent/adventure
  12 passed. Fixed a Dart environment-config constructor error before rerunning.
  Final combined backend discovery suite 19 passed / 6 DB checks skipped.
- Still external: destination gameplay review, licensed final creature assets,
  native background encounter notifications. Skill artwork remains the existing
  implementation; a bespoke animated skill asset pack is not completed.

### G — regression checks and release preparation

- Full Flutter suite: **126 passed / 1 opt-in live test skipped**. Analyzer: no
  issues. Both languages/themes and existing small-screen/200% text regressions
  passed. No new physical Samsung, iOS, network-loss field or background-push
  acceptance test is claimed.
- Combined backend suite: **61 passed / 10 optional database checks skipped**
  (platform 9/4, AI 30/0, discovery 19/6, expense 3/0). Provider requests are mocked.
- Hosting updater PowerShell parser and full laptop Compose `config --quiet`
  passed. The updater has not been executed on the separate hosting PC.
- Added `Update App Backend.cmd`, backend `scripts/update-app-backend.ps1`, and
  `APP_UPDATE_SETUP.md`; preserve hosting-PC `.env`, data volumes and tunnel.
- The initial signed Android compilation succeeded; a missing Cupertino icon
  font warning was fixed, analyzer rerun clean and the full 126/1 Flutter suite
  rerun successfully. Final artifact/signature result is recorded below.
- Final release: `com.anajak.anajak_travel`, Android **1.0.2 (4)**, target SDK
  **36**. `flutter build appbundle --release` succeeded and `jarsigner -verify`
  confirmed the upload signature. Delivered `.local/anajakmap-1.0.2-4.aab`;
  SHA-256 `5375a5f795ffaa0d5fe5cddf0c39060edcbe25d2d215c19308ab0d7e5a5f2824`.
- `.local/anajak-backend-update-1.0.2.zip` contains only allowlisted backend
  source, scripts and documentation; archive contents were inspected to exclude
  `.env`, local release config and signing material. See `APP_UPDATE_SETUP.md`.
  No Play upload or iOS build was performed. Later hosting recovery is recorded
  below; updates to any other PC still require applying the Git/source update.

## Hosting follow-up checks

Readiness follow-up: local application images do not declare Docker HEALTHCHECK,
so the old `.State.Health.Status` template was invalid. Added
`scripts/{backend-readiness,test-backend-readiness}.ps1`; the updater requires
Actuator HTTP success and JSON `UP` for all three service ports, tolerates startup
retries, and starts stopped dependencies. `-SkipBuild` finishes an already-built
update without repeating compilation. Existing tunnel overlay is retained.
Windows PowerShell 5.1: 20 readiness tests and 23 installer tests passed, plus
the isolated complete overlay/child-run/skip-build check. Live recovery succeeded:
AI guide, discovery and expense each reported readiness UP after dependencies
were resumed. No Google generation requests or emails were sent by these checks.
The full stack and public tunnel were subsequently resumed. Local and public
proxy checks passed (auth config 200, unauthenticated profile 401, blocked internal
paths 404). Fixed stale tunnel URL extraction to use only the current session and
its latest URL; three isolated startup regression cases passed. Flutter's ignored
`connected.public.local.json` now points at the current tunnel. Samsung was not
connected during this recovery, so physical-device acceptance remains outstanding.

Hosting updater follow-up: an extracted patch without `.env` now discovers the
single initialized checkout through ancestry and Docker labels, validates the
explicit `backend-update-files.txt`, backs up overwritten sources, copies and
hash-verifies listed files, and runs the updated hosting script there. It never
copies or recreates credentials. Ambiguous targets require `-HostingRoot`; an
explicit different target is rejected from an already initialized checkout.
Windows PowerShell 5.1: 23 installer regression checks passed, plus an isolated
full dry-run/apply/child-run check with simulated Docker. Original `.env` hashes
were preserved, and no real services were changed by these checks. Added
`scripts/{backend-update-install,test-update-installer}.ps1` and the root manifest.

## Highest-priority next task

Run a Samsung end-to-end acceptance pass against the restored backend using the
current `connected.public.local.json`, beginning with login and AI chat. Configure
the optional real router and confirm image model support before enabling those
features. Stable hosting, destination-specific culture data, native push, iOS,
privacy/retention and operations checks remain production dependencies.
