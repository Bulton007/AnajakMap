# Mobile production release

Release builds require an explicit HTTPS gateway ending in `/api/v1/` and
`APP_MODE=connected`. Missing/invalid configuration stops startup before account
restoration or requests. Local debug/emulator/USB defaults still work.

Copy `config/production.example.json` to `config/production.local.json` and replace
the domain. This contains only public client configuration, never Gemini, SMTP,
database or backend secrets. Custom tile providers now use `MAP_TILE_URL` and
`MAP_ATTRIBUTION`; provide an HTTPS `{z}/{x}/{y}` template and the required credit.
Empty map settings retain the existing OSM tiles; verify provider usage terms
and expected traffic before launch.

Create and securely back up an upload keystore, following the
[Flutter Android release guide](https://docs.flutter.dev/deployment/android).
Copy `android/key.properties.example` to ignored `android/key.properties` and
complete it locally. Relative keystore paths resolve from the `android` folder.
Release builds no longer sign with the debug key.

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test --concurrency=1
flutter build appbundle --release --dart-define-from-file=config/production.local.json
```

Use a new build number for each store upload. Do not replace the existing package
identifier after publishing. Keep signing keys separate from the repository.
A release signed with a different key cannot update a debug install in place;
do not uninstall a user's debug app until unsynced local work is preserved.

Android cloud backup and device-transfer rules exclude app data, including
credentials and offline queues. This prevents account caches from being restored
unexpectedly, but unsynced drafts are not recoverable from Android backup.
Server backups remain separately required.

iOS archives require macOS/Xcode, an Apple team and provisioning. Configure the
same public API, verify secure storage, permissions and deep links on a device.
No iOS archive or store submission is claimed.

## Release acceptance

- Production HTTPS, real verification/reset mail, auth expiry/refresh and logout.
- Registration/legal links, account deletion and retention policy implementation.
- Each enabled discovery/AI/media/push feature uses a verified real adapter.
- No development fixtures or test-only RPG rewards in the production backend.
- Small screens, keyboard, both themes, Khmer/English and text scaling on devices.
- Offline conflicts, queued work, crash recovery and upgrade behavior.
- Location/AR privacy, destination safety review and production RPG assets.
- Store privacy disclosures, licenses, screenshots and support contact reviewed.

CI runs Flutter analysis/tests and backend Maven verification on pushes/PRs.
CI has not run on GitHub until these changes are pushed. Oracle integration tests,
provider calls, signing and device tests require separate configured environments.
