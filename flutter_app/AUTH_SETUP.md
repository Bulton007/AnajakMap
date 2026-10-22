# Authentication — 6 October 2026

The hosted React prototype was unavailable locally. The Flutter implementation follows the user's written reference and supplied ivory/forest/teal/gold tokens. No React files were modified. Auth uses Riverpod, go_router, Dio and platform secure storage. Bundled temple photography, Noto Sans Khmer and Cormorant Garamond have attribution/license files under `assets/`.

## Working code and boundaries

`AuthRepository`, `AuthController`, `AuthState`, `AuthFailure`, `AuthSession` and `AuthUser` separate screens from transport/storage. Reusable auth components are in `lib/features/authentication/auth_components.dart`.

| Operation | Actual Spring endpoint | Behavior |
|---|---|---|
| Configuration | GET `/api/v1/auth/config` (added) | Public capability/legal metadata; no credentials |
| Registration | POST `/auth/register` | Name, email, password, true legalConsent, exact policyVersion; pending verification |
| Verify | POST `/auth/verify` | Email + emailed code; does not automatically sign in |
| Resend | POST `/auth/resend-verification` (added) | Generic acknowledgement; shared 60-second resend cooldown |
| Sign in | POST `/auth/login` | Server-confirmed tokens followed by GET `/profile` |
| Recovery | POST `/auth/forgot-password` | Same acknowledgement for existing/nonexistent accounts |
| Reset | POST `/auth/reset-password` | Email + code + password; revokes refresh tokens |
| Refresh | POST `/auth/refresh` | Existing single-flight rotation after HTTP 401 |
| Sign out | POST `/auth/logout` | Revokes refresh token; local secure credentials cleared even offline |
| Current user | GET `/api/v1/profile` | Used to confirm and restore sessions |

All abbreviated paths above are relative to `/api/v1`. Backend access JWTs last 600 seconds; refresh tokens last 30 days and rotate. Sign-out/password reset revoke refresh tokens; already issued access JWTs can remain valid until their ten-minute expiry, per the existing backend contract. Offline restoration only uses a previously saved profile and is labelled offline; new offline sign-in is never successful.

Passwords require 12–72 UTF-16 code units and at most 72 UTF-8 bytes, matching Spring `@Size` and the bcrypt byte check. Names allow 120 characters. Consent and its policy version/time are recorded server-side by Oracle migration `V3__registration_consent.sql`. Passwords and consent are not saved in preferences. Codes are six random digits, hashed for validation, encrypted while queued for mail, expire after 15 minutes, and have server attempt limits. **No application response contains a verification/reset code, including in dev mode.**

`/auth` has no bottom navigation. `/connected` is guarded; only confirmed/restored accounts enter it. An allowlisted intended destination is retained through sign-in. `/guest` is a read-only bundled Cambodia introduction, clearly labelled as unauthenticated and editorial. It does not make protected API calls or create guest drafts, so no silent draft upload/merge occurs.

## Gmail delivery without a paid email service

Sender configuration is private and deployment-specific. Existing verified accounts can sign in. Registration, resend and recovery show unavailable until delivery is configured; registration also requires real legal URLs. Nothing falsely claims an email was sent: successful submissions say queued, because delivery is asynchronous.

1. Create or choose a Gmail sender you control. Enable Google 2-Step Verification. If eligible, generate an **app password** for this backend. Do not use your normal Gmail password and do not paste either into chat.
2. Privately edit the backend's existing ignored `.env` at `C:\anajak_map\AnajakMapBackend\AnajakMapBackend\.env`. Preserve all existing values and add:

```dotenv
GMAIL_USERNAME=
GMAIL_APP_PASSWORD=
AUTH_TERMS_URL=
AUTH_PRIVACY_URL=
AUTH_POLICY_VERSION=
# Optional, after a real verified app-link domain is configured:
AUTH_LINK_BASE=
```

Set the first two to your sender/app password, the next two to your published HTTPS legal documents, and policy version to your actual document version. Do not use placeholder legal documents for real users. These values belong only on the backend. SMTP uses `smtp.gmail.com:587`, required STARTTLS, hostname checks, and bounded timeouts. No client secret or Gmail password is compiled into Flutter. Gmail sending is subject to account limits and spam controls; it is not an unlimited production email service.

3. From the backend folder run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/start-local.ps1` to build/migrate/start. After the images are current, `-SkipBuild` is sufficient for configuration changes. Existing volumes are preserved.
4. Register a test account you own, wait for the email (worker checks every 30 seconds), and enter its code. Check spam if needed. The worker retries at most five times while the code is valid. Mail queue acknowledgements do not guarantee inbox delivery. Run one identity-service mail worker replica with the current SMTP queue implementation; SMTP has no exactly-once delivery guarantee.

To check Gmail independently of registration, run `python scripts/test-gmail.py` from the backend folder. It checks STARTTLS and authentication without sending mail or logging credentials. Add `--send-test` to send one test message to the sender's own mailbox. Confirm receipt in Inbox/Spam; SMTP acceptance alone does not establish delivery. Remove Google's display spaces when saving the app password. This check does not bypass required legal links or validate the Oracle mail queue.

For a separately authorized Kubernetes deployment, the existing `scripts/kubernetes-secrets.py` includes these values in identity service/migration Secrets when supplied. No cluster was modified for this task. Use a proper secret manager for production and run the V3 migration before starting the updated identity image.

Official setup/limits: [Google app passwords](https://support.google.com/accounts/answer/185833), [Gmail sending limits](https://support.google.com/mail/answer/22839). App passwords require 2-Step Verification and may be unavailable for some account policies. Google recommends OAuth for clients that support it; this implementation uses a server-only SMTP app password. Enabling Gmail delivery does **not** enable Google social sign-in.

## Verification/reset links

Manual emailed-code entry works without an app-link domain. `AuthLink` also parses HTTPS links matching an exact configured origin/path, using fragments such as `https://your-owned-host/auth/link#reset?email=...&code=...`. Fragments avoid ordinary server access-log query recording. The app requires confirmation before verification/reset; merely opening a link never authenticates.

To activate native link opening, first own and host the real HTTPS domain and set the same `AUTH_LINK_BASE` in backend environment and Flutter `--dart-define`. Then:

- Android: add an `android:autoVerify="true"` HTTPS intent filter for that exact host/path on MainActivity, with VIEW/DEFAULT/BROWSABLE; publish `/.well-known/assetlinks.json` containing the app ID and release certificate SHA-256 fingerprint.
- iOS: enable Associated Domains with `applinks:your-owned-host`, publish `/.well-known/apple-app-site-association` with your Apple team ID, bundle ID and auth path, and include the entitlement in signing.
- Host a safe fallback page for unopened links. Do not load analytics or third-party resources on it, record fragments, or redirect to arbitrary destinations.

The `app_links` listener validates links before routing and holds codes only in memory. Flutter's default deep-link routing is disabled to avoid handing raw credential links directly to go_router. Domain association, fallback hosting and real-device link opening remain outstanding because no domain/team/certificate configuration was supplied. Wrong-host links are ignored; invalid/expired server codes show recovery actions.

## Google / Apple

Neither provider is configured, and the backend has no provider-exchange endpoint. The UI explicitly says unavailable and renders no imitation buttons. `SocialSignInButton` accepts an official native/SDK-rendered button for a future integration. No hand-drawn provider logos, embedded secrets, fabricated endpoint, or fake successful social login exists.

Outstanding: OAuth client IDs, Google Android signing certificate/iOS configuration, Apple capability/team/service configuration, native SDK flows, PKCE/state/nonce as required by the chosen flow, backend audience/issuer/expiry/signature/nonce validation and account-linking policy. Only after those exist should official provider buttons be enabled. Provider cancellation is covered at the controller boundary, not claimed as a live SDK test.

## Tests and local launch

```powershell
cd C:\anajak_map\flutter_app
flutter analyze
flutter test
powershell.exe -ExecutionPolicy Bypass -File .\run-device.ps1
```

`test/auth_test.dart` covers validation, session restoration, revoked refresh, offline honesty, server retry timing, route guards, duplicate submits, cancellation, consent, verification and reset errors/success, plus English/Khmer, both themes, 320dp screens, 2× text and keyboard insets. Golden images are under `test/goldens/auth_*`.

Existing live travel tests now require a **dedicated, already email-verified test account**, not the removed development-code API. Put only that disposable account in an ignored local file `config/auth-test.local.json` with `AUTH_TEST_EMAIL` and `AUTH_TEST_PASSWORD`; never use a personal account. Run `run-device.ps1 -Test -TestConfig config/auth-test.local.json`, then run without `-Test` to restore the normal app. Test defines are embedded in test APKs: never distribute those APKs. Desktop live tests use `--dart-define=RUN_LIVE=true --dart-define-from-file=config/auth-test.local.json`. These tests create travel records.

For backend automated email tests, `compose.auth-test.yml` is an explicit isolated mail adapter, not real Gmail. It captures messages in memory, requires a random `MAIL_TEST_KEY`, and exposes its test inbox only on loopback port 8095. Use `scripts/test-auth-mail.ps1` after starting the local stack; it restores normal identity configuration and removes the test sink in `finally`. Never include this overlay in normal startup or production. It validates the email queue without returning codes through the app API or sending external mail.

## Outstanding deliverables

Actual Gmail inbox delivery, real Terms/Privacy URLs, verified app-link hosting, Google/Apple SDK/backend integrations, iOS signing/build/device checks, Android TalkBack and iOS VoiceOver manual review, production release verification, and Khmer translation review require the relevant accounts/devices/configuration. Figma authoring access is unavailable: matching Figma components and clickable flows remain outstanding. Flutter auth contains no fake authentication or demo-success path; the existing separate `APP_MODE=demo` travel UI remains explicitly demo-only.
