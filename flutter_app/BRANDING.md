# AnajakMap launcher artwork and navigation

Master artwork: `assets/branding/anajak_app_icon.png`.
The current green-and-gold master was supplied by the user on 22 October 2026
and applied without altering the artwork. `flutter_launcher_icons` creates the
Android and iOS launcher sizes. The previous generated indigo version is kept
as `assets/branding/anajak_app_icon_indigo.png` for reference.
No API key or external image download is required to build the app.

Regenerate the platform sizes after replacing the master image:

```sh
flutter pub get
dart run flutter_launcher_icons
```

Configuration: `flutter_launcher_icons.yaml`. Android includes legacy density
icons and adaptive icons with a 16% foreground inset. iOS icons have alpha removed.
The installed app must be rebuilt to update launcher icons; hot reload does not
update native resources. iOS compilation and device validation require macOS/Xcode.

## Original indigo generation prompt (archived version)

Create one polished production mobile app icon for AnajakMap, a Cambodia travel companion with discovery and playful adventure. Square opaque full bleed canvas, no text or letters. Bold simple central symbol combining a graceful location pin and three stylized Angkor temple towers with a subtle compass star, instantly legible at small launcher sizes. Premium vector-like dimensional artwork, deep midnight indigo background, luminous lavender and warm golden temple, small coral and sky blue accents. Cohesive refined silhouette, balanced symmetry, restrained gradients, excellent contrast. Keep all important artwork in the central 60 percent for Android adaptive masking. Background fills every corner; do not draw a rounded square border, phone mockup, watermark or extra icon variations.

## Navigation

Both shells share `AnajakBottomBar`, using `crystal_navigation_bar` 2.0.0.
The floating frosted bar has localized labels, screen-reader selected states,
and tap areas taller than 48dp. Selection is driven directly by the shell's
current route or tab index, including external route changes.
The compact bar occupies 94dp before the system safe-area inset, with 20dp
side margins and a 26dp corner radius.
The bar respects bottom safe areas, both themes and reduced-motion preferences.
The shells extend page content beneath the translucent bar so its 28-sigma
backdrop filter blurs real scrolling content. PageBody reserves the bar inset
at the end of the scroll area so the last controls remain reachable.
For text scaling above roughly 140% or screens narrower than 340dp, Flutter's
native navigation provides more space for accessible labels.

## Validation

- Crystal navigation and screen checks: 14 passed, including route changes and
  large Khmer text. Screen goldens updated for the intentional bar replacement.
- Static analysis: no issues.
- All 25 iOS catalog images checked for expected dimensions and opaque PNG format.
- Previews inspected for the floating crystal bar and English tab labels.
- Green-logo Android debug APK built successfully. Samsung is currently
  disconnected, so installation and device verification of this logo are pending.
  The previous icon/navigation build was visually verified on that device.
