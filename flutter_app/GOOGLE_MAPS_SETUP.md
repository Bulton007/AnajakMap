# Google Maps

**Inactive:** The app now uses OpenStreetMap without billing. See
[OPENSTREETMAP_SETUP.md](OPENSTREETMAP_SETUP.md). Instructions below are retained
only for a future, explicitly requested switch back to Google Maps.

The app now uses the official `google_maps_flutter` plugin on Android and iOS.
Open the map icon in the connected app or Creature Trails, or Map in demo Explore.
Trip/explore map screens display valid coordinates returned by the existing backend.
The standalone map opens over Cambodia. It does not invent creature spawn locations.

## Android

1. In Google Cloud, select your project, enable billing and **Maps SDK for Android**.
2. Create an Android-restricted API key. Restrict it to package
   `com.anajak.anajak_travel` and your signing certificate SHA-1, and restrict its
   API access to Maps SDK for Android. Use separate production signing restrictions.
3. Create the ignored file `android/maps.local.properties` with this one line:

```properties
MAPS_API_KEY=YOUR_ANDROID_MAPS_KEY
```

4. Stop and rebuild the app; hot reload cannot update native configuration:

```powershell
flutter run -d emulator-5554 --dart-define-from-file=config/connected.android.json
```

Run `android/gradlew.bat -p android signingReport` for the signing fingerprint.
Do not paste keys into chat or commit them. Mobile SDK keys are embedded in the
app, so platform/API restrictions are essential; these are not Gemini keys.

## iOS (requires macOS/Xcode)

Enable Maps SDK for iOS and create a separate key restricted to your app bundle ID.
Create ignored `ios/Flutter/Maps.local.xcconfig`:

```text
MAPS_API_KEY = YOUR_IOS_MAPS_KEY
```

The app reads that build setting through Info.plist and initializes Google Maps
before plugin registration. Minimum iOS deployment target is now 14.0, matching
the installed plugin. Build and test on a Mac; iOS is not verified on Windows.

## Honest availability and testing

Without a key the screen shows setup guidance and never creates a native map.
Key presence is checked natively; only a boolean reaches Dart. Presence does not
prove Google accepted the key. A blank map with a configured key requires checking
Google Cloud API enablement, billing, restrictions and network access.

Location permission is not requested by this map and the location layer is off.
Google attribution remains provided by the native SDK. Web/desktop Google Maps
initialization is not included in this mobile integration.

```powershell
flutter test test/google_map_test.dart test/rpg_game_test.dart test/rpg_ui_test.dart --concurrency=1
flutter test integration_test/rpg_maps_device_test.dart -d emulator-5554
```

The device test checks RPG interactions and native configuration. Without a real
configured key it only verifies the unavailable state, not live Google map tiles.

Official setup: https://developers.google.com/maps/flutter-package/config
