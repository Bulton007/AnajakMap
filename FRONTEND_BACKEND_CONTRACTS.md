# Flutter build 12 / backend contract audit — 29 October 2026

The current Flutter source and current Spring controllers agree on the boundaries below. This is a source audit plus synthetic contract checks, not evidence that every hosted service, external provider or device workflow currently succeeds. No network, Docker, Gmail or Gemini request was made for this audit.

## Shared protocol and hosting

- The Flutter API base must end in `/api/v1/`. The gateway maps `auth` and `profile` to identity, `trips` to trip, `guide` to AI, `discovery` and `rpg` to discovery, and expenses/reservations/journal/notifications to their respective services.
- Successful JSON is wrapped once as `{ "data": ..., "traceId": "...", "timestamp": "..." }`. Binary media and gateway-proxied bytes are deliberately not wrapped a second time. `ApiClient` unwraps `data`; it must not receive HTML, a second envelope or serialized JSON text in place of data.
- Account endpoints require a Bearer access token. Unauthenticated `profile`, `guide/capabilities` and `rpg/capabilities` should return 401. `auth/config` is public.
- The original project uses host Nginx port 8090. The separate fresh `anajakmap-v12` bundle uses **18090** (and gateway 18080), with its own volumes/images. Its public hostname must forward to that same fresh instance. A valid `auth/config` response alone does not establish that discovery/AI images are current. See `FRESH_BACKEND_VALIDATION.md` for the later live fresh-stack acceptance results.

## Authentication and sessions

| Flutter operation | Spring endpoint and response |
| --- | --- |
| Configuration | `GET auth/config`: booleans `emailDelivery`, `registration`, `google`, `apple`; HTTPS legal URLs; nonempty `policyVersion`; `passwordMinLength: 12`, `passwordMaxBytes: 72`. |
| Registration | `POST auth/register`: `name`, `email`, `password`, `legalConsent: true`, the current `policyVersion`. Returns delivery acknowledgement/cooldown, never a verification code or session. |
| Verification/resend | `POST auth/verify` accepts `email` and `code`, returns `verified`; `POST auth/resend-verification` returns privacy-preserving delivery acknowledgement and retry timing. |
| Sign-in | `POST auth/login`: `email`, `password`; returns `accessToken`, `refreshToken`, `expiresIn`, `tokenType`. Flutter confirms the account through `GET profile`. |
| Recovery/reset | `POST auth/forgot-password`: email acknowledgement; `POST auth/reset-password`: `email`, `code`, `password`, then `reset: true`. Reset revokes refresh tokens. |
| Restore/refresh/logout | `GET profile` has `id`, `email`, `name`, `verified`, `preferences`, `version`. `POST auth/refresh` and `auth/logout` accept `refreshToken`. Current access lifetime is 600 seconds; refresh lifetime is 30 days with rotation. |
| Google/Apple | No provider-exchange endpoint exists. Flutter explicitly reports provider sign-in unavailable; it must not pretend a provider token is an app session. |

Password/name validation agrees with the current backend: 12–72 UTF-16 characters and no more than 72 UTF-8 bytes for passwords; display name at most 120 characters. Legal URLs/version and mail availability are runtime configuration. The smoke checker does not send email or create accounts.

## Explore, images, map and routes

| Flutter operation | Required current contract |
| --- | --- |
| Search | `GET discovery/places?query=...&page=0&size=20`: array of place objects with `id`, `name`, numeric `latitude`/`longitude`. Photon/Wikipedia enrichment is separate from fixtures. |
| Photos | `GET discovery/photos?query=...&page=0`: object keyed by the same place IDs. Each available photo includes `url`, `sourceUrl`, `artist`, `license`, `licenseUrl`, `credit`. An empty object is valid when no licensed match/provider is available. |
| Road route | `GET discovery/routes?originLat=...&originLon=...&destinationLat=...&destinationLon=...&mode=driving`: numeric `distanceMeters`, `durationSeconds`, and 2–50,000 GeoJSON coordinate pairs `[longitude, latitude]`, plus `source`. No straight-line substitute is accepted. |
| Other discovery tools | `GET discovery/weather`, `food`, `culture`, `transport`; journeys use `GET/POST discovery/journeys`. Some development-provider responses remain explicitly marked as fixtures. |
| Map layers | OSM/OpenTopoMap/CyclOSM tile images load directly from the configured tile providers. These are Flutter map styles, not new backend routes. Switching styles retains the actual driving route and changes its attribution with the style. Traffic/transit are unavailable without a real feed. |

The observed hosted response containing `durationMinutes`, `estimatedCost`, `currency`, `mock` and `source: development fixture` is the **legacy route fixture**, not this road contract. It cannot draw directions. Rebuild and run the current discovery service; do not weaken the client to invent geometry. The source's `DiscoveryApi` routes driving requests to `OsrmRoutes` before its fixture branch.

Photo URLs are constrained to approved Wikimedia image hosts, with Commons source and approved license metadata. Empty/missing optional photos must not hide otherwise valid search results. The contract checker verifies metadata only; it does not download images or prove visual relevance.

## Companion / AI

| Flutter operation | Spring contract |
| --- | --- |
| Capability gating | `GET guide/capabilities`: provider string, boolean `configured`, `demo`, `providerVerified`, `chat`, `translation`, `itinerary`, `recommendations`, `recap`, `vision`, `voice`, `receipt`, `reservation`. This is configuration only; current `providerVerified` is false because this GET never calls Google. |
| Chat | `POST guide/conversations` with `{}` returns `{id}`. `POST guide/conversations/{id}/messages` accepts `text` and optional `useContext`; returns nonempty `text`. Context defaults off; at most 12 owned messages are used when explicitly enabled. |
| Translation | `POST guide/translation` accepts `{input:{text,targetLanguage:"km"}}` (or `en`); returns nonempty `text`. Saving a phrase is a separate `POST guide/phrases`. |
| Image recognition | Upload JPEG/PNG to multipart `POST guide/media`, receive `mediaId`; then `POST guide/vision` with `{input:{mediaId,shareWithProvider:true,language}}`. Returns `possibleLandmarks` (name/confidence), `explanation`, `extractedText`. Capability and explicit user consent are required. |
| Voice | Upload the selected/recorded supported audio to `guide/media`, then `POST guide/voice` with the same consent envelope. Returns nonempty `transcript`, `text` and `mock:false` for the live voice screen. The voice screen sends the required sharing flag. |
| Itinerary/replanning | `POST guide/itinerary-jobs` or `replanning-jobs` accepts `tripId` and `preferences`, with `Idempotency-Key`. Poll `GET guide/jobs/{id}`; saving is explicit via `save-draft` / `save-proposal`, then trip approval. |
| Recommendations | `POST guide/recommendations` accepts preference data, returns real candidate places/ranking metadata. AI ranking depends on actual Gemini configuration; fallback preference matches stay distinct. |
| Receipt/booking AI | Current capabilities explicitly report `receipt:false`, `reservation:false`. Manual receipt/booking workflows remain the supported path; these are not completed live Gemini integrations. |

The smoke checker deliberately makes **no** conversation, translation, media, generation or other provider request. A shape/configuration pass is not proof of key permissions, model quota, Khmer quality, media support or provider reliability. Those require separately authorized fictional/sample-media acceptance tests.

## Account-owned travel and game state

`TravelRepository` uses the existing Spring paths for trip create/list/detail/sync, itineraries/drafts/approval, calendar/map/offline snapshots, invitations/members, votes, contacts, group location, replanning proposals, expense budgets/summary/splits, reservations and uploads, journal/photos/visits, notifications/devices/reminders. These writes retain their current ownership, version and idempotency requirements. This audit did not create/edit/approve a trip, migrate a database, upload media, schedule a notification or test group authorization end to end.

`AdventureRepository` agrees with `RpgApi`:

- `GET rpg/capabilities`: `practiceEnabled`, `fieldRequiresReviewedDestination`, `redemptionEnabled`, `partySize:3`.
- Realms are **`field`** and **`practice`**. Practice additionally requires its server flag and a dev/test profile. Device-only practice is a separate Flutter mode and never imports balances into the account.
- `GET rpg/{realm}/world` returns reviewed destination/spawn rules. `GET rpg/{realm}/profile` returns `realm`, object `profile`, arrays `monsters`, `species`, `quests`, `ledger`, `party`, `inventory`, `achievements`, `exploration`, `history`, and nullable `activeSession`. SQL projections may use uppercase keys; Flutter's shared field helper normalizes them.
- Profile GET is **not strictly side-effect-free**: it can initialize a first starter and expire overdue sessions. The checker requires explicit `-CheckRpgProfile` for this operation; use a dedicated test account.
- Encounter starts, battle actions, quest claims, party changes, evolution, purchases and equipped titles use POST paths under that realm with `Idempotency-Key`. Field starts carry fresh location plus safety confirmation; actions carry the server revision. The checker never invokes these writes or changes a ledger/reward/inventory.

## Host smoke checker

From the backend folder, Windows PowerShell 5.1 or newer:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\frontend-contract-smoke.ps1
```

Default checks are anonymous `auth/config` shape and the three protected 401 boundaries. To inspect an authenticated test account, add `-Authenticated`; the token prompt is hidden. Use only a disposable test account token, never an email password, Gemini key or refresh token. Do not put tokens on the command line or paste them into chat.

Additional opt-in switches:

| Switch | Effect |
| --- | --- |
| `-CheckRoute` | One public Cambodia-landmark route request; may consume the routing provider's test allowance. No device GPS or stored trip data. Rejects the legacy fixture. |
| `-CheckPlaces` | Fictional Phnom Penh search plus optional licensed-photo metadata; may call external place/photo services. No image download. |
| `-CheckRpgProfile` | Reads the field snapshot and may initialize/expire the test account's RPG state, as described above. No battles/purchases/claims. |
| `-BaseUrl https://YOUR-HOST/api/v1/` | Tests the selected HTTPS backend instead of local Nginx. Cleartext is accepted only for loopback. Redirects are not followed with the access token. |

For automation inside an existing PowerShell process, dot-source the script and call `Invoke-AnajakFrontendContractSmoke` with a `SecureString` token already in memory. Only safe check names/status/pass flags are returned; profile data, tokens, coordinates and provider bodies are not logged. The checker does not refresh tokens automatically. A 401 on protected checks requires a fresh unexpired dedicated test token.

`scripts/test-frontend-contract-smoke.ps1` passed **52 synthetic Windows PowerShell 5.1 checks**. The tests replace transport before orchestration and exercise valid/invalid envelopes, auth limits/legal links, capability shape, route geometry/legacy rejection, photos/licenses, RPG realm shape, optional-check gating and token-free result output. No live network request was made.

Fresh database hosting still requires readiness, migrations and real provider/email/device acceptance. Existing production users and data are not transferred by a source ZIP or this checker.
