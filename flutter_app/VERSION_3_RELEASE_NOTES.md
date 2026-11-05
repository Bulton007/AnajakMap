# Anajak 3.0.0 (13)

Package ID remains `com.anajak.anajak_travel`. Version code 13 follows the local
version-code-12 app. Check Play Console for a higher previously uploaded number
before uploading; this workspace does not have Play Console upload history.

This version includes account-backed GPS journeys and random creature encounters,
trip invitation notifications, private/trip chat, native notification reminders,
direct in-app map entry from explored places, compact profile/notification UI,
and English/Khmer layout improvements. OpenStreetMap remains the map provider.
Journey tracking is foreground-only and pauses when leaving its screen or app.
New messages while the app is terminated still require a remote push provider;
foreground WebSocket delivery and already-scheduled phone reminders are supported.

## Existing backend

The local public tunnel uses `https://reaction-parched-grip.ngrok-free.dev/api/v1/`
and forwards to the existing version-12 backend on port 18090. Public auth config
returned 200 and the authenticated journey route rejected an anonymous request
with 401 during preparation. Keep the backend PC, Docker and tunnel running.
This build does not move the backend or replace its database.

The updated local service overlay is `compose.collaboration.yml`; use
`Start Collaboration Backend.cmd` after starting the existing base backend.
The local database already has the collaboration and journey migrations applied.
For another backend installation, apply the migrations and runtime grants before
using this client; see `RPG_SETUP.md` and `../COLLABORATION_REPORT.md`.

## Build

Local `config/production.local.json` contains only public client settings and
points to the existing HTTPS backend. Local `android/key.properties` is prepared
but awaits the existing upload keystore and signing settings. Both files and all
keystores stay ignored by Git. A signed bundle is not yet produced.

```powershell
flutter build appbundle --release --dart-define-from-file=config/production.local.json --build-name=3.0.0 --build-number=13
```

Expected bundle path: `build/app/outputs/bundle/release/app-release.aab`.
Verify the bundle version and upload certificate after signing. The upload
certificate must match the existing Play upload key; do not substitute a debug
key or create a replacement without the appropriate upload-key reset.

## Validation

- Full Flutter suite: 273 passed, one optional live test skipped; analyzer clean.
- Relevant backend reactor: 60 passed, 14 environment-dependent tests skipped.
  The 8 RPG Oracle persistence tests separately passed in a disposable schema.
- Fixed notification cleanup on widget disposal, and refreshed 11 visually
  reviewed screenshots for the shared layout changes before the final full run.
- Signed-bundle verification awaits the upload keystore and its local settings.

The emulator gameplay check captured River Makara through real server battle
actions, confirmed 40 XP/15 gold, and displayed the owned instance in collection.
Physical GPS movement, Play-delivered installation and iOS runtime checks remain
outstanding. No Play upload is performed by this task.
