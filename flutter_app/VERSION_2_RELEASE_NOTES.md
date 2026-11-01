# Anajak Version 2.0.0

Latest local test build: **2.0.0-test (11)**, installed as **Anajak Test** alongside the Play app. Includes AI-first place recommendations with manual matching, honest AI/demo/connection states, visual Unicode itinerary cards, arbitrary map endpoint pins and optional AI route tips. Samsung native emoji/Khmer screenshots and the Flutter suite passed. The user signed in directly; GPS and pin selection worked. Hosted driving routes still failed, and Gemini activation remains dependent on the hosting PC. See `AI_MAP_UPDATE_11.md`.

Latest Play upload artifact: **2.0.0 (10)** at
`../.local/AnajakMap-2.0.0-10-release.aab`. Its manifest version code and signature
were verified, and its upload certificate matches build 9. Backend URL editing
instructions are in `BACKEND_URL.md`. The build-9 record below is preserved as
history; no new APK was produced for build 10.

The Android package remains `com.anajak.anajak_travel`. Build number 9 follows
the locally tested build 8. Before a Play upload, check that 9 is greater than
every build number already uploaded to your Play Console.

## Changes

- Directions obtains a fresh foreground GPS fix and renders validated road
  geometry. Repeated Directions requests no longer hang. Impossible routes and
  unavailable location have explicit error states.
- Responsive game cards and lists share padding and gaps, align related actions,
  and show loading, empty, error and pending-action states.
- Six distinct Khmer-inspired fantasy companions have original illustrated
  portraits and procedural 3D families. Existing species IDs, stats and progress
  are preserved.
- The map title is simplified; required map attribution remains visible.

## Current local build

The local emulator build uses `config/connected.android.json`, pointing to
`http://10.0.2.2:8080/api/v1/`. It is a debug build of the separate **Anajak Test**
package (`com.anajak.anajak_travel.preview`), preserving the existing preview
app and account data. This address works in the Android emulator; it is not a
public endpoint and is not appropriate for Google Play distribution.

The feature source passed 188 Flutter tests (one optional live test skipped)
and 45 backend tests (ten environment-dependent tests skipped) before this
version metadata change. Device evidence is in `../DEVICE_TEST_REPORT.md`.

## Signed public test build

Signed artifacts using the existing upload keystore:

- `../.local/AnajakMap-2.0.0-9-release.apk`
- `../.local/AnajakMap-2.0.0-9-release.aab`

Both signatures verified and their certificate digests match. The release APK
is not debuggable and passed 16 KiB zip-alignment verification. ARM32, ARM64 and
x86-64 binaries contain the verified public API address in both artifacts.
Use the AAB for an update through Play Console; a directly installed APK signed
with the upload key may differ from the app-signing key held by Google Play.
No Play upload is performed here.

The chosen testing provider is the account-assigned **ngrok** development
domain, forwarding to the initialized PC's Nginx. The public auth configuration
returned HTTP 200; unauthenticated profile access returned 401; Actuator,
Swagger and internal routes returned 404. Registration and email delivery flags
were enabled; a new verification email was not sent in this pass.

## Availability and acceptance

Keep the hosting PC, Docker and ngrok running. Free account quotas still apply.
Run `../Start Public Backend.cmd` after restarting the PC; unattended Windows
startup has not been configured. Changing from the old API origin can require
signing in again. Existing server-side accounts and progress are preserved.

All nine backend services reported readiness UP after compilation, and the
public API boundary checks passed again. No device was connected for a fresh
native test. Test the Play-delivered build and actual account flows before
rollout. See `../HOME_SERVER_URL_SETUP.md` for the URL/PC setup and existing
`PRODUCTION_RELEASE.md` for outstanding production acceptance requirements.

Copyable Play release notes are in `PLAY_RELEASE_NOTES_2.0.0.txt`.
