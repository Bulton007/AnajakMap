                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              # Change the Flutter backend URL

For signed Android/Google Play builds, edit:

    flutter_app/config/production.local.json

Keep connected mode and set the public HTTPS API base, including `/api/v1/`:

```json
{
  "APP_MODE": "connected",
  "API_BASE_URL": "https://reaction-parched-grip.ngrok-free.dev/api/v1/",
  "MAP_TILE_URL": "",
  "MAP_ATTRIBUTION": ""
}
```

This is public client configuration. Never add Gemini keys, Gmail passwords,
database credentials or ngrok account tokens to this file or to Flutter.

From the Flutter project directory:

```powershell
cd C:\anajak_map\flutter_app
flutter build appbundle --release --dart-define-from-file=config/production.local.json --build-number=10
```

The current requested upload uses version name `2.0.0` and version code `10`.
If 10 has already been uploaded to Play, use a larger unused build number for
the next upload. The package remains `com.anajak.anajak_travel`.

The URL is compiled into the app. Editing this JSON does not change an installed
app; rebuild it and distribute the new version after changing the hostname.
Moving the backend to another PC while retaining the same public hostname does
not by itself require another app build.

For `flutter run` against the public server, edit the separate ignored file:

    flutter_app/config/connected.public.local.json

Then run:

```powershell
flutter run --dart-define-from-file=config/connected.public.local.json
```

`lib/core/config/environment.dart` reads the compile-time values; it is not the
place to hardcode a new backend address. Both `*.local.json` files stay outside
Git. Keep private backend configuration in the hosting PC's backend `.env`.
