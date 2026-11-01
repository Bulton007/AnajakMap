# Map layout and layers — test build 12

The Android test package remains `com.anajak.anajak_travel.preview` (**Anajak Test**), version name `2.0.0-test`, version code `12`. The configured public backend remains `https://reaction-parched-grip.ngrok-free.dev/api/v1/`. This is a separate test installation; it does not replace the Play-signed app.

## Changes

- Start and destination selection actions share one row. Normal phone layouts also show the two place selectors beside each other; large text uses full-width selectors inside the scrollable control area.
- Compact controls leave at least 60% of the map body's height for the map in the tested narrow, normal and landscape layouts.
- A conventional red destination pin has a dark center and anchors its tip to the chosen coordinate. GPS and route origins remain visually distinct in blue.
- The Layers button opens illustrated Map, Terrain, Traffic, Transit, Biking and More choices. Map uses the existing standard/custom tile configuration; Terrain uses OpenTopoMap and Biking uses CyclOSM. Provider credits and native tile zoom update with the chosen style.
- Traffic and transit show an unavailable explanation without changing the selected map. More shows provider credits and explains that styles do not change the calculated driving route.
- Switching styles retains the map camera, selected pins and confirmed road geometry, without sending a new directions request. Biking does not imply bicycle directions.

## Validation

44 map layout/routing regression tests and ten layer-selector tests passed. Coverage includes narrow phones, landscape, English/Khmer, large text, both themes, accessible touch targets, screen-reader activation, unavailable styles, camera/route preservation and configured standard tiles. Targeted static analysis reported no issues. Widget tests use local images and do not call public tile services.

One bounded Cambodia tile check for each public style returned HTTP 200 with PNG bytes on the development PC. Public tile service availability remains external and best effort; see `OPENSTREETMAP_SETUP.md` for provider policy sources.

Installed build 12 on the Samsung Galaxy S23 Ultra with the existing test-app session preserved. Visually verified the larger map, side-by-side controls, red pins and preview tray. Standard, terrain and cycling tiles rendered with their respective credits. Both start and destination map taps worked; switching styles retained those pins. Traffic displayed its unavailable explanation without replacing the active cycling map. The app was left with the standard layer selected and the tray open. The original USB stay-awake setting was restored afterward. No live road-route success, new AI request, email, account reward or Play rollout is claimed by this layout check.

The preceding live Samsung pass found the public backend still serving an older demo route contract, and Khmer translation returned `AI provider unavailable`. These layout changes do not claim to fix those hosted services. Apply the separately supplied startup repair and finish the hosting update before accepting live driving/AI behavior.

No new Play Store bundle or rollout is part of this test update.
