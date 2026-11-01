# Check the AI on the hosting PC

Run **Check AI.cmd** from the existing project on the computer that hosts Docker and ngrok. The checker is read-only. It does not send data to Google, read or replace `.env`, rebuild services, reset your database, or change the public URL.

It reports the AI service's actual container settings and readiness, together with numeric counts of sanitized AI failures from the last 30 minutes (at most 2,000 log lines). It never prints passwords, API keys, prompts, account IDs, raw logs, or provider response bodies. You can share the resulting JSON for troubleshooting.

- `provider: fixture` and `demo: true`: this host is using development answers. Copying the source ZIP does not copy your private Gemini settings.
- `provider: gemini` with `configured: false`: the running container has no Gemini key. Use **Update AI.cmd** on this hosting PC to configure and test your own key locally.
- `configured: true`: credentials are present, but have **not** been verified by this checker. A valid model and provider quota are still required.
- `readinessUp: false`: the service or one of its backend dependencies is not ready. Resolve that before trying the app again.
- `visionEnabled` / `voiceEnabled`: media requires a configured key and the corresponding explicit server feature flag. Enabling a flag alone does not prove that your chosen model supports that media.
- Recent HTTP `429`: Google reported a quota or rate limit. Respect the retry time shown in the app. Rebuilding Flutter will not reset quota.
- Recent HTTP `400` / `404`: check the configured model and the provider request compatibility locally. The checker deliberately omits Google's raw error response.
- Recent HTTP `503` or transport failures: the upstream service or network was unavailable. Counts can include an older attempt; retry once in the app and run the checker again to compare.

For a real end-to-end check, sign in to the installed app and ask one fictional travel question. Then run the checker on the hosting PC. Do not paste passwords, tokens, verification codes, `.env`, or full `docker inspect` output into chat.

## Enable Gemini on the actual hosting PC

When the app reports a development/demo answer, run **Update AI.cmd** on the computer running the public backend. Enter your Gemini key only in its hidden local prompt and select a model available to your Google project. The updater sends up to three short fictional setup tests for transient server failures, preserves your existing database/email credentials, then rebuilds and recreates only the AI service with `AI_PROVIDER=gemini`. A successful test on another computer does not configure this hosting PC.

Run **Check AI.cmd** again after the updater finishes. Expect `provider: gemini`, `configured: true`, `demo: false` and `readinessUp: true`. Then confirm an actual answer in the signed-in app using its existing backend URL. A successful readiness check by itself does not confirm Google is available.

If an older updater rejects the key before contacting Google, apply the targeted instructions in **AI_SETUP_REPAIR.md**. The repaired updater treats keys as opaque single-line credentials rather than assuming a legacy prefix, punctuation set or 200-character maximum. It stores punctuation literally and temporarily pins only the three verified AI settings for Compose, then restores the caller's environment. For future launches, avoid stale shell AI overrides that contradict the saved `.env`.

Photo and voice need their separately verified server settings, `GEMINI_VISION_ENABLED=true` and `GEMINI_VOICE_ENABLED=true`. Keep an operation disabled until the selected model has been tested for that input; the text-only setup test does not validate images or audio. Secrets stay in the hosting PC's existing `.env`, never in Flutter or the source ZIP.

## Capability contract

`GET /api/v1/guide/capabilities` requires an authenticated account. Its additive `configured`, `demo`, `provider`, and `providerVerified` fields describe configuration only. `providerVerified` is false because this endpoint never makes a paid/quota-consuming provider request. `chat`, `translation`, `itinerary`, `recommendations`, `recap`, `vision`, and `voice` identify implemented/configured operations. Receipt and reservation extraction remain unavailable; their manual flows remain usable.

AI drafts, recommendations and route suggestions require user review before saving. Choosing a destination, editing an itinerary or following a route remains under the user's control; AI does not silently make bookings, upload private drafts, or change a route.

## Khmer and emoji itinerary storage

The backend repair also adds trip migration `V4__unicode_trip_text.sql`. Older Oracle trip columns used implicit byte limits, so a valid Khmer or emoji title could exceed the database limit even when it passed the API's text-length validation. The new migration widens those columns to explicit character limits while retaining existing text and constraints. Oracle documents this conversion in its [ALTER TABLE reference](https://docs.oracle.com/en/database/oracle/oracle-database/21/sqlrf/ALTER-TABLE.html).

Run **Update App Backend.cmd** with the complete source patch on the existing hosting checkout to build the updated **trip-service**, along with AI/discovery/expense services. The updater runs Flyway in a separate schema-owner migration container before replacing the running services; normal runtime containers keep their restricted app accounts and Flyway disabled. If migration fails, the updater stops before replacing service containers. **Update AI.cmd** only rebuilds the AI service and cannot apply this trip migration. Keep the existing `.env` and database volumes; do not edit V1–V3 or recreate the database.

Local Unicode API validation tests pass. A real Oracle round-trip regression is included but runs only when explicit disposable `ORACLE_TEST_*` settings are supplied; this repair has not been applied to or verified against your hosting database from this computer.

The database must already use a Unicode-capable character set (the project's Oracle Docker setup uses AL32UTF8). This migration changes column length semantics; it does not convert an existing database character set. The existing Java API limits still count UTF-16 code units, so supplementary emoji use two units each.

Setup version 2026.10.28.1 reports HTTP 503 as temporary service/capacity failure rather than suggesting it proves an invalid key. Its bounded retry and model-selection behavior is described in `AI_SETUP_REPAIR.md`. No Google availability guarantee is implied.
