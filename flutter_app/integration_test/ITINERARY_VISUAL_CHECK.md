Native itinerary visual check
=============================

This isolated test displays synthetic English/Khmer itinerary cards in both
themes, including temple, food, heart and joined family emoji. It uses no
backend, credentials, user trips, location or persistent application data.

From `C:\anajak_map\flutter_app`, after any other Flutter build has finished:

```powershell
$env:ORG_GRADLE_PROJECT_ANAJAK_PREVIEW = 'true'
flutter drive --no-pub --debug -d DEVICE_ID --driver=test_driver/itinerary_visual_driver.dart --target=integration_test/itinerary_visual_device_test.dart
```

`ANAJAK_PREVIEW=true` installs the separate `com.anajak.anajak_travel.preview`
test package. Keep the phone unlocked. Replace `DEVICE_ID` with its ADB serial.
The test checks Unicode preservation, native fallback configuration, layout and
selection/edit controls. PNG captures are saved on this PC under
`C:\anajak_map\.local\itinerary-visual-check`.

Open all four PNG files and inspect the actual glyphs: emoji should be visible,
the family sequence should appear joined, and Khmer text should be legible.
A successful automated assertion does not by itself prove glyph appearance.

Afterward reinstall the normal **Anajak Test** main-entry-point APK with
`adb -s DEVICE_ID install -r -t PATH_TO_PREVIEW_MAIN_APK` and open it. Replacing
the test entry point this way keeps the preview package usable; never uninstall
or clear the Play-installed app or its user data for this visual check.
