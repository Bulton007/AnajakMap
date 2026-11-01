# Travel feature verification — 24–29 October 2026

## Map layout/layers test build 12 — 29 October 2026

- Built and installed **Anajak Test 2.0.0-test (12)** on Samsung Galaxy S23 Ultra. APK package metadata, the unchanged public API URL, the new layer tray and the screen-reader correction were verified in the compiled artifact. The existing session and Play-installed app were preserved.
- 44 map layout/routing regressions and ten layer-selector tests passed; targeted static analysis was clean. Coverage includes small/landscape layouts, English/Khmer, large text, both themes, accessible touch targets and screen-reader activation.
- Native phone checks confirmed a larger map, side-by-side start/destination actions, red destination pins, blue start marker, working start/destination map taps and the layer preview tray. Standard, OpenTopoMap terrain and CyclOSM cycling tiles rendered with the correct credits. Cycling tiles loaded progressively and then filled the visible map.
- Switching styles retained the selected pins. Traffic showed its unavailable explanation without replacing the cycling map. Camera/confirmed-route preservation and no extra route request were verified by automated tests; no new live directions request was made in this layout pass.
- Left the standard layer selected and the tray open. Restored the original USB stay-awake setting and removed temporary on-device captures. Local evidence and the test APK remain under ignored `.local/`.
- The preceding hosted legacy-route contract and intermittent AI availability remain backend dependencies. No Play bundle, iOS-device check or release rollout was performed.

## Samsung public-backend check — 29 October 2026

- Reinstalled the separate **Anajak Test 2.0.0-test (11)** package on the connected Samsung Galaxy S23 Ultra using `adb install -r`. Its existing session and the Play-installed app were preserved. Verified the configured ngrok API URL is embedded in the APK.
- Public authentication configuration returned HTTP 200 with registration and email delivery configured. Protected profile and AI capabilities require authentication; external Actuator remains blocked. No registration email was sent in this pass.
- The app restored its session, displayed an Explore place photograph, acquired foreground GPS after a one-time location grant and accepted an arbitrary map destination pin.
- The first fictional companion request failed. A second request in a fresh conversation succeeded and rendered a temple-visiting answer; conversation context remained off. This demonstrates a live answer, not continuous provider reliability. Photo and voice actions were marked unavailable by the serving backend.
- Translating the synthetic phrase `Thank you` to Khmer failed with `AI provider unavailable` (trace `a71d2147-6a3c-4ded-9325-936eb4a170d4`). The draft remained in the form. No translation was saved.
- Road directions failed in `MapRoute.fromJson`. A debugger inspection found a `FormatException`; safe field-name/type inspection showed `durationMinutes`, `estimatedCost`, `currency`, `estimate`, `source`, `mock` and `updatedAt`, with no `distanceMeters`, `durationSeconds` or `coordinates`. This is the older demo response contract, not the current road-routing contract. No GPS coordinate values, credentials or provider response bodies were logged.
- The hosting-PC update was blocked by a `Substring` error in source fingerprinting. Reproduced with a real normalized path, repaired path handling and passed 113 Windows PowerShell 5.1 synthetic checks. The host still needs the repaired launcher to finish building updated services before road directions can be accepted.
- Creature trails opened to its practice/field entry screen. No battle, purchase or reward claim was performed. Temporary debugger breakpoints and local ADB forwarding were removed; no stay-awake setting was changed.
- The larger map, side-by-side selection buttons and revised pin artwork were deferred at the user's request until these connection/backend checks finish. No map layout changes were made in this pass.

## AI / itinerary / map update 11 — 27 October 2026

- Existing configured public backend URL preserved. Anonymous auth configuration returned JSON HTTP 200; the protected AI capability endpoint returned the expected unauthenticated 401.
- A new fictional question in the Play-installed app returned `Development travel guide:`. This confirms demo/fixture responses at the time of testing; it does not verify Gemini.
- Installed the separate `com.anajak.anajak_travel.preview` **Anajak Test** package, version `2.0.0-test`, code 11. The Play app uses a different signing certificate and was preserved with its data.
- Native itinerary visual test passed on Samsung Galaxy S23 Ultra. Reviewed four PNGs in `.local/itinerary-visual-check`: color emoji, joined family emoji, Khmer, localized dates, icons and controls render correctly in both themes. Test content was synthetic, with no backend or user trip writes.
- Restored the normal test-app entry point, and the user signed in directly on the Samsung. Verified foreground GPS centering and arbitrary destination pin selection. The GPS-to-pin Directions request through the hosted backend still failed. A separate synthetic landmark-to-landmark probe from this PC returned real OSRM road geometry (HTTP 200). This does not prove connectivity from the hosting PC; live driving acceptance remains open.
- Flutter analysis clean; complete unit/widget suite: 208 passed, one optional test skipped. New backend AI/Unicode/updater tests passed; the real Oracle round-trip test was skipped. No live database migration was run from this PC.
- Local format validation in the old AI updater rejected the user's key before contacting Google. The repaired updater accepts bounded opaque keys and was checked with synthetic dotted/long credentials and literal dotenv encoding. Actual Google acceptance still requires the hosting PC's hidden setup prompt; no credential was shared in chat.
- Setup and feature boundaries: `flutter_app/AI_MAP_UPDATE_11.md`, `AI_DIAGNOSTICS.md`. No Play Console upload was performed.

## Version-code-10 Play bundle — 26 October 2026

- Built `.local/AnajakMap-2.0.0-10-release.aab`. Parsed its compiled manifest:
  package `com.anajak.anajak_travel`, version name `2.0.0`, version code `10`.
- Verified the bundle signature and that its upload-certificate digest matches
  build 9. Confirmed the configured HTTPS API URL inside each ARM32, ARM64 and
  x86-64 application binary. ZIP integrity passed.
- Evidence: `.local/version10-artifact-check.json`. Only the upload counter was
  changed; no new feature behavior or fresh live backend/device acceptance is
  claimed. No Play Console upload was performed.
- Release URL configuration is `flutter_app/config/production.local.json`;
  public development runs use `flutter_app/config/connected.public.local.json`.
  See `flutter_app/BACKEND_URL.md` for rebuild instructions.

## Version 2 public test build — 25 October 2026

- Built signed **2.0.0 (9)** APK and AAB with the existing upload keystore and
  unchanged `com.anajak.anajak_travel` package. Both signatures verified and
  signing certificate digests matched. The APK is not debuggable and passed
  16 KiB zip-alignment verification. ARM32, ARM64 and x86-64 binaries were
  present; the configured public API URL was verified inside each compiled
  application binary in both artifacts.
- The account-assigned ngrok development domain was configured locally, with
  its credential outside the repository. Public API checks passed before and
  after compilation: auth configuration 200, unauthenticated profile 401, and
  Actuator/Swagger/internal paths 404. Registration and mail-delivery flags were
  enabled; no fresh registration email or AI request was sent in this pass.
- All nine application services reported readiness UP after compilation.
  Database volumes and `.env` credentials were preserved. Running the new public
  launcher again reused the same endpoint without starting a duplicate agent.
  The local ngrok request-payload inspector is disabled.
- `Configure Ngrok.cmd` accepts the account token through a hidden local prompt;
  `Start Public Backend.cmd` starts the initialized backend, checks its proxy
  boundary, then starts or reuses ngrok. Keep the hosting PC, Docker, internet
  and tunnel running. Automatic Windows startup is not configured, and the free
  provider's usage quotas apply. This is a public testing setup, not a promise
  of uninterrupted production availability.
- Artifacts: `.local/AnajakMap-2.0.0-9-release.apk` and
  `.local/AnajakMap-2.0.0-9-release.aab`. Verification evidence is
  `.local/version2-artifact-check.json` and `.local/version2-public-check.json`.
  The earlier feature tree passed 188 Flutter tests (one optional skipped) and
  45 backend tests (ten environment-dependent skipped); this pass changed version
  metadata and hosting launchers, not those feature implementations.
- No Android device was connected for a new native acceptance check. The APK
  and AAB were verified as build artifacts; no Play upload was performed. Use
  the AAB to update a Play-installed app through Play's signing/distribution
  process. Do not uninstall an existing app to work around signing differences.

## Latest pass: routes, game layout and Khmer-inspired companions — build 8

**Anajak Test 1.0.2-test (8)** was installed in place on the x86-64 emulator,
preserving its existing app data. Full Flutter verification passed **188 tests**
with one optional live test skipped. Targeted backend verification passed
**45 tests**, with ten environment-dependent tests skipped.

- Native Directions obtained a fresh foreground location and displayed a blue
  road polyline with an approximately **1.6 km / 3 min** estimate. Repeating
  Directions completed successfully. This check used an explicitly configured
  emulator test location in Phnom Penh (longitude 104.9315, latitude 11.5638);
  it does **not** verify physical field GPS or a real journey. Impossible routes,
  unavailable location, cancellation and service failures retain honest states.
- Map branding was simplified; mandatory OpenStreetMap attribution remains in
  a compact credit. The current public OSRM demo is a test dependency, provides
  estimates without live traffic, and must be replaced by an owned/licensed
  routing service before production.
- Inventory cards now align their actions and disable purchases when game gold
  is insufficient. Native inventory and quest screens showed consistent card
  gaps, padding and progress. Automated coverage includes responsive game pages,
  large text, localization and pending-action feedback; server-confirmed rewards
  and account/practice separation remain enforced.
- The guide visibly displayed all six distinct new portraits. Original vector
  portraits and matching procedural 3D families use Khmer-inspired fantasy
  motifs, localized names and fictional lore. Stable species IDs, statistics,
  encounter weights and saved collections remain unchanged. These are invented
  companions, not historical reconstructions; see `flutter_app/KHMER_CREATURE_ART.md`.

Evidence is local and excluded from Git: `.local/update8-map-route.png`,
`.local/update8-map-repeat.png`, `.local/update8-creature-guide.png`,
`.local/update8-inventory.png` and `.local/update8-quests.png`. Emulator APK:
`.local/AnajakMap-1.0.2-8-emulator.apk`. This task did not run AI requests, send
real email, verify field RPG location acceptance, or upload a Play Store release.

## Earlier passes

Earlier device pass: connected Samsung SM-S918B, Android 16, AnajakMap
1.0.2, build 6. Existing app data was preserved. USB port forwarding connects the
app's localhost API to Nginx on this PC; keep the cable connected for this build.

## Game, photo and voice update

- Adventure now offers **Play practice**, selects an unlocked trail and starter,
  and requires acknowledgement before a server encounter. Field destinations
  remain subject to safety review, GPS and proximity checks. The local test
  configuration enables the separate practice realm; it creates no redeemable
  travel rewards.
- Live gateway RPG verification passed **57 checks** across two encounters,
  including a captured companion that persisted after reload, server XP/gold,
  quest claims and a shop purchase. Repeated requests did not duplicate rewards
  or charges. The second encounter waited for the normal server cooldown; field
  progress remained uninitialized. Evidence: `.local/game-practice-results.json`.
- Photo and voice support are implemented behind separate backend flags, both
  false by default. The configured local `gemini-3.5-flash-lite` model returned
  successful responses to a synthetic PNG and a synthesized fictional WAV in
  direct provider probes. The image response correctly avoided claiming that the
  drawing was a real landmark. Evidence: `.local/multimodal-probe-results.json`.
- Native voice input records locally, then requires explicit provider-sharing
  consent and **Send recording**. The backend accepts validated PCM16 WAV only,
  0.25–60 seconds, up to 4 MiB. It returns a transcript and text answer; spoken
  answer playback/TTS is not implemented. Backgrounding cancels recording.
- Explore photos now use a compact 48dp photo-credit info button instead of the
  large reference row. The credit dialog retains author, licence and source.
- Full Flutter regression: **150 passed**, one optional live test skipped.
  The final voice request-envelope correction then passed all nine voice tests.
  Modified game, voice and photo files pass static analysis. Backend verification:
  **59 AI tests** and **9 platform tests** passed;
  four environment-dependent integration tests were skipped.

- Both synthetic media checks also passed through Nginx, authenticated gateway,
  account-owned media upload/storage and Gemini: image recognition and actual
  audio transcription/text response. Evidence: `.local/multimodal-gateway-results.json`.
  Flutter voice submits the required Spring `input` envelope, covered by its
  request contract assertion.

- Android 1.0.2 build 7 installed on the Samsung using an in-place update;
  existing sign-in and player state survived. Native checks confirmed enabled
  photo/voice cards, the voice recording screen, loaded Central Market photos
  with the compact credit icon, practice entry and actual server battle HP
  changes after Strike.
- Native synthetic photo recognition passed through the phone, upload gateway
  and Gemini. Flutter displayed the correct explanation that the drawing was
  synthetic and no real landmark could be identified.
- The device test exposed a hidden battle after starting from lower controls.
  The final revision reveals new/resumed battles automatically and preserves
  scroll during HP updates. Five entry tests passed, including this regression.
- All **11 final voice tests** passed, including Android permission-dialog
  inactive/resumed behavior and cancellation when backgrounded during permission.
  Targeted analysis is clean. The microphone was not activated automatically.
- The user completed the physical microphone acceptance check on the Samsung
  and reported **"Transcript and answer appeared"**. This confirms the manual
  recording, consent, upload and displayed-response flow for this test. This is
  user-reported acceptance, separate from the automated synthetic-audio checks.

The final revision was rebuilt and installed successfully. A fresh native
practice entry automatically resumed the existing Moonwarden battle with the
3D scene, Strike and Magic visible, preserving its server HP values. All nine
application services were restored; AI, discovery and expense report readiness
UP. The user subsequently confirmed the physical microphone check succeeded.
This remains a USB test build, forwarding device port 8080 to this PC's Nginx
port 8090. Keep the cable connected. No Play Store release was uploaded.

The disposable diagnostic identity, refresh tokens and AI fixture metadata were
removed after gateway tests; RPG audit records and ledgers were preserved.
Only test-owned object-store files remain subject to the existing retention.
Automated provider/gateway probes used synthetic media and a disposable
diagnostic identity; native photo testing used the synthetic drawing, and the
user performed the manual voice test. The RPG
test history is retained because its ledger and inventory transactions are
append-only; no live player history was removed.

## OPPO local connection — 25 October 2026

- OPPO CPH2629, Android 16, arm64, was authorized over USB.
- Its existing `com.anajak.anajak_travel` version 1.0.0 (1) uses a different
  signing certificate. Android correctly rejected an in-place debug update;
  the original app and its data were preserved.
- Installed **Anajak Test 1.0.2-test (7)** as the separate
  `com.anajak.anajak_travel.preview` debug package. APK metadata confirmed its
  package, label and launcher activity before installation. The normal package
  ID and label remain unchanged without the opt-in preview flag; release builds
  reject that flag.
- USB reverse forwards phone port 8080 to this PC's Nginx port 8090. All nine
  backend services reported readiness UP after packaging. The test app launched
  to its sign-in screen without recent fatal/unhandled exceptions.
- Sign-in and authenticated feature acceptance on the OPPO remain for the user;
  no credentials, downloads or drafts were copied from another device or app.
  Keep USB connected. See `flutter_app/README.md` for repeatable setup.

## Android emulator launch — 25 October 2026

- Built a native x86-64 debug APK for `emulator-5554` (Android 16, 16 KiB page
  emulator). Confirmed `lib/x86_64/libflutter.so` before installing the separate
  **Anajak Test 1.0.2-test (7)** package; the existing app was preserved.
- Uses `config/connected.android.json`, connecting directly to
  `http://10.0.2.2:8080/api/v1/`. An HTTP request from inside the emulator returned
  200 from the public authentication configuration endpoint.
- The app launched and its light-theme sign-in screen rendered correctly, with
  no recent fatal/unhandled startup errors. Backend services were restored after
  compilation and gateway readiness reported UP. User sign-in remains manual.
- Local APK: `.local/AnajakMap-1.0.2-7-emulator.apk`; screenshot:
  `.local/emulator-anajak-running.png`.

## Earlier Samsung pass: verified behavior

| Check | Result |
| --- | --- |
| Driving API | Real OSRM route: Royal Palace to Wat Phnom, 1,729.9 m, 45 geometry points |
| Samsung map | Blue road route and distance/time estimate visibly rendered |
| Explore API | Phnom Penh returned 20 results, including 11 licensed photos |
| Photo downloads | Central Market, Freedom Park and National Museum JPEGs returned 200 with valid image bytes and attribution |
| Samsung photos | Royal Palace and Silver Pagoda photographs visibly rendered with credits |
| Khmer translation | Live Gemini response contained Khmer text |
| Samsung translation | Final phone-to-backend-to-Gemini request rendered `Thank you` as `អរគុណ។`, with no foreign-script letters |
| Companion chat | Live reply succeeded |
| Conversation follow-up | Live reply succeeded using bounded fictional context |
| Recommendations | Real candidate places ranked by Gemini; `ai_grounded` mode confirmed |
| Itinerary | Live job succeeded with four grounded activities |
| Replanning | Live job succeeded; calendar constraints stay inside the backend |

All live AI checks used a disposable diagnostic identity and fictional text.
Its account, credentials, chats, jobs and trip were removed afterward. This pass
did not submit the user's real conversations or photos to Gemini and did not
send registration email.

## Fixes and regression checks

- Local routing now has an explicitly labelled public OSRM test provider, with
  one request per second maximum. Place-to-place origins work without GPS.
- Changing route selections during GPS loading cancels the old request and
  prevents its tracking stream from restarting. Nine map tests passed.
- Exact city searches add geographically checked Wikipedia sights; images are
  licensed from Wikimedia, including its current thumbnail host. Missing
  licensed images retain an honest fallback.
- Culture recommendations retrieve the enriched city candidates and support
  strictly validated Wikipedia reference links.
- Normal generation no longer depends on the reservations service. Replanning
  no longer makes an invalid weather request or sends calendar data to Google.
- A final native translation check exposed a Thai response to a Khmer request;
  translation now names the requested language explicitly and rejects foreign
  scripts instead of presenting them as successful Khmer. At most one corrective
  attempt is made using the same input; persistent mismatches return 502.
- Local Gemini model switched from `gemini-3.8-flash` (observed 503 errors) to
  Google-listed `gemini-3.5-flash-lite`, which passed all six live workflows.
- Full Flutter regression run: 133 passed, one optional live test skipped.
  The final GPS cancellation regression was then verified in the nine-map-test
  run. Targeted backend runs: 34 AI tests and 16 discovery tests passed. The
  modified Flutter source files pass static analysis without issues.

## Scope

The six AI workflows were verified through the real gateway and provider, and
translation was additionally verified on the phone. This does not imply that
every AI screen was exercised on the phone. Vision and voice were unavailable
during that build-6 pass; their new implementation and verification scope are
recorded above. Gemini receipt/booking extraction remains unavailable; manual
entry stays enabled. No Play upload, iOS device test, production hosting, or field RPG
acceptance was performed in this pass. The public route demo is for reasonable
non-commercial testing; production needs an owned/licensed routing service.

Logs and screenshots are local under `.local/`, excluded from Git. The source
update manifest includes the new backend classes; existing credentials are not
part of that update. A separate hosting PC needs its own model setting checked.
