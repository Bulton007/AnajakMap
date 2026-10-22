# Google Play release stages

Publishing is the last stage, after the persistent HTTPS backend and Neon branch
pass device acceptance. Current app ID: `com.anajak.anajak_travel`.
Do not change it after publishing. The green theme retains the compact crystal
bar; feature badges use limited sky/violet/gold/coral accents.

## Before the first upload

1. Confirm the developer identity, Play Console account type, public app name,
   support email and countries. Use your own Play Console login; never share the
   account password or signing keys in chat.
2. Complete production backend checks in `deploy/openshift-neon/README.md`.
   Disable or finish unimplemented/sample features before public availability.
3. Implement and verify account/data deletion, including a discoverable in-app
   path and a functional public request page. Current production status still
   lists this as outstanding. Do not claim it is complete in Data safety.
4. Review privacy/Terms to cover actual location, photos, email and AI-provider
   processing, retention and deletion. Complete Data safety, age/content rating,
   permissions declarations and reviewer access with truthful disclosures.
5. Configure an upload keystore locally, back it up securely, and enroll in Play
   App Signing. Use `PRODUCTION_RELEASE.md` for signing and the HTTPS Flutter
   config. Every upload needs an incremented build number.

```sh
flutter build appbundle --release --dart-define-from-file=config/production.local.json --build-number=NEXT_NUMBER
```

The release bundle is `build/app/outputs/bundle/release/app-release.aab`.
The command above needs actual configuration and signing; no signed bundle or
Play submission is claimed yet. Verify the current target API requirement in
Play Console before building, as policy dates change.

## Testing and publication

Upload to internal testing first. Test the Play-delivered signed app on physical
Android devices: auth/mail links, permission denial, foreground/background,
Khmer, text scaling, maps, trips, offline queues, AI errors and RPG safety.
Provide working reviewer access when required. Prepare real screenshots, the
launcher icon, a feature graphic, description and support/privacy/deletion URLs.

For personal developer accounts created after 13 November 2023, Google's current
requirements include a closed test with at least 12 testers continuously opted
in for 14 days before applying for production access. Account eligibility and
Google review control when production can begin; publishing cannot be guaranteed
in a single session. After approval, review the concrete release and use a
staged rollout, crash/error monitoring and an established rollback plan.

Official references checked 22 October 2026:
- [Testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)
- [Flutter Android release guide](https://docs.flutter.dev/deployment/android)
