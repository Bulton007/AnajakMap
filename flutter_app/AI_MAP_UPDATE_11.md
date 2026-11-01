# AnajakMap test update 11

The existing `config/production.local.json` URL is preserved. The Android package for physical testing is `com.anajak.anajak_travel.preview` (**Anajak Test**); it coexists with the Play-installed app and uses a separate credential store. Sign in locally on the phone, never by sharing a password in chat.

Implemented changes:

- Recommendations ask AI to choose and explain by default, with an explicit switch for manual preference matching. Fallback place matches remain clearly labeled.
- AI status distinguishes a failed connection check, missing configuration and demo answers. Connection checks have an explicit retry. Older `Development travel guide:` replies also receive a visible demo label.
- Itinerary cards preserve Unicode titles, request native emoji fonts, show category icons and localized times, and retain manual editing and approval.
- Map controls support arbitrary start/destination pins and routing from current GPS. Selecting another endpoint clears the previous route. Optional AI travel tips require agreement and share only the route summary; they do not select roads or provide live turn-by-turn navigation.
- Backend AI replies that are malformed, blocked or truncated produce a safe retryable server error. User validation errors retain their normal status.
- The Oracle trip migration widens text columns to explicit character limits for Khmer and emoji. It does not replace previous migrations or reset data.

## Hosting PC steps

1. Download `AnajakMap-Backend-Update11.zip` and extract its contents over the **existing project root** containing `Start Backend.cmd`. The package excludes `.env`, keys and database data. Retain the hosting PC's original private configuration.
2. Run **Update App Backend.cmd**. It builds the updated services, runs the trip migration under the established schema-owner migration path, and checks runtime readiness. A migration failure stops service replacement.
3. Get a key from [Google AI Studio](https://aistudio.google.com/app/apikey). Run **Update AI.cmd** on this same hosting PC. Enter the key only in its hidden prompt and select a model available to your Google project. The helper sends one short fictional text request before activating Gemini.
4. Run **Check AI.cmd**. Expect `provider: gemini`, `configured: true`, `demo: false`, and `readinessUp: true`. This checker does not call Google; confirm a real answer separately in the signed-in app.
5. Photo and voice remain unavailable until the selected model has been verified for those inputs and their server flags are enabled. Receipt and reservation extraction remain manual.

The phone test against the configured public URL returned a development/fixture chat answer. Changing or rebuilding Flutter cannot activate Gemini on the hosting PC. A successful text setup test does not validate every AI operation or its quota.

## Validation

Flutter static analysis is clean. The complete Flutter unit/widget suite passes 208 tests with one optional test skipped, including map pin selection, AI consent and retry, duplicate submission prevention, itinerary approval, Khmer, large text and both themes. The isolated native visual test also passed on the connected Samsung Galaxy S23 Ultra. All four English/Khmer, light/dark screenshots were reviewed: color emoji, joined family emoji and Khmer glyphs render correctly. The normal Anajak Test 11 entry point was reinstalled, and the user signed in directly. Foreground GPS and map pin selection worked. The live Directions request through the hosted backend still failed; a separate synthetic OSRM probe from this PC succeeded. Route acceptance and real Gemini activation remain open on the hosting PC.

Backend checks include 68 AI tests, five trip Unicode/validation tests and updater safety/orchestration checks. These are mocked/offline checks; the opt-in Oracle round-trip test was skipped because no test Oracle database was available. Apply the migration and verify AI on the actual hosting PC before a Play Store rollout.
