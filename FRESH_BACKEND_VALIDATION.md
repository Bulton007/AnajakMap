# Fresh backend validation — 29 October 2026

The private fresh bundle uses project `anajakmap-v12`, an independent Oracle database/session key set, local Nginx port 18090 and gateway port 18080. Its private `.env` is included directly inside the backend folder. The original `anajakmap` data and containers were not reset or replaced.

## Passed checks

- **447 startup checks** in Windows PowerShell 5.1 and 7, including actual installed Compose CLI argument parsing, path normalization, strict credential comparisons, Docker JSON array parsing, project/port isolation, migration ordering and environment restoration.
- **52 synthetic API-contract checks** covering the Flutter build 12 response shapes. These tests do not call Google or send email.
- Full current-source Maven build: **127 tests passed, zero failures/errors, 12 optional database tests skipped** (139 total test entries). Skipped integration tests are not counted as passed.
- Both real Compose configurations validated privately. Only loopback ports 18080/18090 are published; database/broker/media volumes and application image names are separate from the original project.
- Matching new RSA signing keys and a 256-bit encryption key validated without printing key material.
- Fresh schemas/migrations and runtime grants completed. All nine services reported readiness UP, Nginx was healthy, public auth configuration returned 200, protected endpoints returned anonymous 401 and Actuator/Swagger/internal proxy paths returned 404.
- Gmail SMTP authenticated the included sender configuration successfully over TLS. **No email was sent**, so actual inbox delivery was not verified in this pass.
- A disposable, pre-verified synthetic identity tested actual login, current-user profile, refresh rotation and logout revocation through the fresh Nginx API. Verification was seeded directly only for the diagnostic account; this does not claim a live registration/email-code test.
- Royal Palace to Wat Phnom returned **45 road geometry points, 1,729.9 metres**. An initial upstream 502 was followed by a successful bounded API retry; the public router remains an external best-effort test dependency.
- Explore returned **20 places and 11 licensed photo candidates**; one actual image download passed byte-format checks.
- A synthetic Khmer/emoji trip title survived a real Oracle write/read round trip.
- Gemini returned real companion text, Khmer translation, two grounded recommendations and a completed four-activity itinerary job. Prompts were fictional; conversation context was off, and the itinerary was not saved or approved.
- A practice RPG encounter started, replaying its request was idempotent, and retreat ended it without rewards. No real field battle, purchase or reward claim was performed.

The first itinerary probe omitted the required `Idempotency-Key`; the corrected probe, matching Flutter's actual request, passed. The API currently maps that malformed manual request to 500 instead of 400, an error-classification hardening item rather than a failure of the existing Flutter request contract. Initial attempts and successful rechecks are preserved separately in the bundled JSON reports. Synthetic identities were removed; append-only fictional game diagnostics were retained only in the local test database. Database volumes/test records are not in the ZIP.

## Scope and remaining dependencies

This validates the selected backend workflows and startup on the development PC. It does not establish production uptime or prove every phone workflow. The ngrok public handoff was not performed from this PC; use the owning account and the included fresh public launcher on the hosting PC. The target PC's network, Gmail delivery rules, Google quota/model availability and public map/search/router capacity remain external dependencies.

Google/Apple sign-in, receipt/reservation AI extraction, live traffic/transit and any explicitly marked development fixtures remain as documented in `FRONTEND_BACKEND_CONTRACTS.md`. Photo/voice implementation and flags are included, but fresh live image/audio provider acceptance was not repeated here. Public legal pages retain their existing draft policy version. No Play Store upload or production certification is claimed.

The media compatibility Dockerfile now copies the official Go builder's existing CA bundle instead of depending on a separate apt-mirror download. Fresh migration commands use supported Compose flags, and the retry guard handles Windows PowerShell 5.1 Docker JSON arrays without weakening credential validation.
