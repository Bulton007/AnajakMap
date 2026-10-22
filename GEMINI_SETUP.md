# Gemini integration — 21 October 2026

Latest diagnostic: the configured model returned HTTP 429 with provider retry delay 53959 seconds (quota exhausted). An alternative account-listed model returned 503. Further live generation tests were stopped. No successful end-to-end generation is claimed. The adapter now preserves sanitized retry metadata in `Retry-After`; itinerary job responses expose `retryAt`, and quota errors become terminal `AI_RATE_LIMITED` jobs with explicit recovery guidance. Temporary provider failures use bounded slower backoff. Provider response bodies and credentials are never returned or logged.

Implemented server-side in ai-guide-service, behind the existing GuideProvider interface. Flutter keeps its existing authenticated endpoints and proposal approval flow. On 21 October, a direct Google request returned a complete structured Khmer translation from the configured 3.8 Flash model. However, authenticated gateway translation tests still failed: sanitized backend diagnostics recorded upstream HTTP 503, and one attempt recorded UnresolvedAddressException. End-to-end app AI is therefore NOT verified working. Model listing alone does not prove generation availability: an account-listed 2.5 Flash Lite model returned 404. Mocked contract tests pass.

The local AI container now has configurable primary/fallback DNS (`EXTERNAL_DNS`, default 1.1.1.1; `EXTERNAL_DNS_FALLBACK`, default 8.8.8.8). Fallback DNS did not resolve Google's 503 responses. Provider diagnostics record only status codes or exception class names, never credentials, prompts or response bodies. Normal identity/email configuration was restored after disposable-account tests, and temporary local test credentials were removed.

Companion action cards now align to the tallest card in each row and switch to one column for large text. Photo identification and voice assistance are explicitly disabled and labeled unavailable. Six targeted Flutter tests passed, Flutter analysis was clean, and the debug APK was built and installed on the connected Samsung. The phone was locked during screenshot verification; device visual confirmation remains outstanding.

## Supported first phase

- Chat (single request text, not conversation-history memory), text translation and editable text recaps.
- New itinerary proposals using only supplied discovery places. Gemini selects place indices; the backend supplies original names, coordinates and sources and validates trip dates, ordering and duration. Results remain estimates requiring approval.
- Missing key returns unavailable. Provider errors are sanitized; blocked/truncated/malformed output is rejected. No secrets, prompts or provider error bodies are logged by the adapter.
- Receipt, reservation extraction, vision, voice and weather/calendar replanning explicitly return unavailable in Gemini mode. They do not fall back to fake results.
- Discovery and weather can still be development fixtures. A Gemini-generated itinerary is not evidence that its source places or opening hours are live. Existing runtime development warnings intentionally remain.

## Private configuration

Create a key in https://aistudio.google.com/ and add these to the backend's ignored .env. Never paste the key into chat, Flutter configuration, GitHub or a screenshot.

```dotenv
GEMINI_API_KEY=your-private-key
AI_PROVIDER=gemini
GEMINI_MODEL=gemini-3.8-flash
```

Use fictional test information on a free tier. Review Google's data-use terms and pricing before sending user information. Account IDs, tokens and email are not intentionally supplied by this adapter, but text a user types can itself contain personal data. Free access and limits are account-dependent. Budget controls, live quality evaluation and provider privacy disclosures remain required before production.

## Build and enable locally

From `AnajakMapBackend/AnajakMapBackend`, first build the changed Java artifacts (Java 21/Maven or the existing Docker build helper). Then run:

```powershell
docker compose -f compose.yml -f compose.media-source.yml -f compose.local.yml -f compose.runtime.yml -f compose.gemini.yml build ai-guide-service
docker compose -f compose.yml -f compose.media-source.yml -f compose.local.yml -f compose.runtime.yml -f compose.gemini.yml up -d --no-deps ai-guide-service
```

`compose.local.yml` now reads `AI_PROVIDER`, `GEMINI_API_KEY` and `GEMINI_MODEL` from the ignored `.env`, so normal local restarts retain the selection. The optional Gemini overlay also selects it explicitly and requires a key. To deliberately use fixtures locally, set `AI_PROVIDER=fixture` and recreate without the Gemini overlay. No credential fallback is embedded in source.

A previously embedded credential was removed from Compose and moved to ignored local configuration. Rotate that key before production; never add the replacement to tracked files.

Timeouts are ordered: AI provider 45 seconds, gateway AI proxy 55 seconds, Flutter receive 60 seconds.

Default external endpoint: `https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`; credential header: `x-goog-api-key`. Requests use structured JSON responses, a 45-second read timeout, input limits and a 4096 output-token ceiling. A model consuming that ceiling on reasoning may yield incomplete output, which is rejected rather than saved. Model availability must be verified with the configured account.

## Verification

Run `mvn -pl ai-guide-service -am test` for provider tests and existing validation tests. Mock tests cover transport/header contract, Khmer output, missing configuration, unsupported tasks, provider 429 sanitization, incomplete/empty output, grounded coordinates and out-of-range schedules/place indices. Tests do not spend API credits.

After enabling with a key, sign in to Flutter and try an English/Khmer chat, text translation and a one-day itinerary. Review the proposal before saving. Confirm the source says Gemini, inspect actual token cost in the provider dashboard, and verify malformed/unavailable states. No real model quality, accuracy or successful paid call is claimed by the mocked tests.

References: https://ai.google.dev/api/generate-content and https://ai.google.dev/gemini-api/docs/structured-output .
