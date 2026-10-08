# Anajak — Flutter + Spring Boot + Oracle

Flutter now starts in **connected mode**. The separate UI demo remains available with `--dart-define=APP_MODE=demo`. Development backend providers return clearly labelled fixtures; a working API connection does not mean live AI/weather/maps are configured.

## Start locally on Windows

```powershell
cd C:\anajak_map\AnajakMapBackend\AnajakMapBackend
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/start-local.ps1
cd C:\anajak_map\flutter_app
flutter pub get
powershell.exe -NoProfile -ExecutionPolicy Bypass -File run-connected.ps1 -Target web
```

The startup script preserves existing `.env` credentials and database volumes, tests/packages Java inside Linux, builds Docker images, creates Oracle schemas, runs Flyway migrations, grants restricted runtime access and starts the gateway at `http://localhost:8080`. Use `-SkipBuild` only after current images are built. `-OfficialOracle` selects the optional official full Oracle image for a fresh volume; do not switch Oracle versions against an existing volume.

Read [AUTH_SETUP.md](AUTH_SETUP.md) for authentication and Gmail setup. Verification/reset codes are delivered only by email, never displayed by the app or returned by the API. No Gmail sender or legal URLs are configured yet, so registration/recovery remain explicitly unavailable; existing verified accounts can sign in.

Web uses port **7777**, matching the gateway's exact CORS allowlist. For an Android emulator use `powershell.exe -ExecutionPolicy Bypass -File run-connected.ps1 -Target android` (gateway host `10.0.2.2`). For production, configure an HTTPS gateway in a separate JSON file and use `--dart-define-from-file=...`. Never put backend passwords, private keys or service tokens in Flutter configuration.

### Samsung / physical Android over USB

Start the backend, connect the unlocked phone with USB debugging enabled, and approve its computer authorization prompt. Then run:

```powershell
cd C:\anajak_map\flutter_app
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\run-device.ps1
```

The helper selects the single authorized Android device, checks gateway readiness, forwards the phone's localhost port 8080 to this computer, and launches connected mode. Keep USB connected; rerun after reconnecting. With multiple devices, pass `-DeviceId R5CW1048X8L` for this Samsung. It also sets a short Java socket directory for this process to avoid the local Windows Java loopback failure.

To run native integration checks, pass `-Test -TestConfig config/auth-test.local.json` containing a dedicated, already verified test account as described in `AUTH_SETUP.md`. Tests create travel records, use a separate secure-storage key and cache scope, and clean their local credentials/cache. After testing, rerun without `-Test` to restore the normal app.

Set `MAP_TILE_URL` and `MAP_ATTRIBUTION` for an approved tile provider. Without them the map explains configuration requirements; real place lists still come from the API. Offline downloads do not bulk-download map tiles.

## Architecture

- Riverpod injects `Environment`, `ApiClient`, `TravelRepository`, sessions and Drift.
- Widgets use repository methods; Dio unwraps the backend envelope and preserves error/trace IDs.
- Authentication uses secure platform storage, rotating refresh tokens and a shared in-flight refresh.
- Models normalize Oracle projection casing. Money uses exact decimal strings, not floating-point totals.
- Drift stores downloaded snapshots, local bookmarks, generation recovery IDs and a durable account/server-scoped outbox.
- Trip edits carry their original server version. Conflicts show local and server details for explicit review. Confirmed writes are never reported before a server response or a follow-up server-state check.
- AI generation, extraction and recap results remain reviewable until the user approves. Reservations are records, not purchases.

See [INTEGRATION.md](../INTEGRATION.md) for the feature/API matrix, setup boundaries and verification. See [Kubernetes setup](../AnajakMapBackend/AnajakMapBackend/deploy/kubernetes/README.md) for the portable local manifests. No remote cluster is modified by generation/rendering commands.

## Checks

```powershell
flutter analyze
flutter test
flutter test test/live_backend_test.dart --dart-define=RUN_LIVE=true
flutter build web --dart-define-from-file=config/connected.web.json
```

The opt-in live test now requires a dedicated email-verified test account and creates travel records through the same repositories used by the app. It requires the running local stack. Ordinary tests do not contact the backend. Web previews and golden baselines do not establish Android/iOS device compatibility.

Validated toolchain: Flutter 3.44.1 / Dart 3.12.1, Java 21. Android debug build and installation succeed on Samsung SM-S918B / Android 16; `run-device.ps1` handles the Windows Java socket-directory workaround. iOS requires macOS/Xcode. Bundled artwork/font attribution is in [assets/ATTRIBUTION.md](assets/ATTRIBUTION.md).

## Local data

Connected tokens/profile metadata use secure storage. Downloaded travel data and pending edits are stored in Drift under an account + gateway namespace. Signing out keeps downloads for the same account; another account cannot see them in the app. These caches are not separately encrypted at rest. Browser storage can be cleared by the browser. Protect the device and do not assume offline storage is a backup. Camera/file/location access occurs only on an explicit action; group location sharing expires after five minutes.
