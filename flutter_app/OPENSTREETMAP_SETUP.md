# Active map provider: OpenStreetMap

All app map routes now use Flutter Map with OpenStreetMap standard tiles. No map
API key, account, or billing setup is needed. Google Maps code is dormant and its
local key is not used by these routes. AI remains independent and unchanged.

- HTTPS tiles: https://tile.openstreetmap.org/{z}/{x}/{y}.png
- Visible, linked OpenStreetMap attribution below the map.
- Identifying native User-Agent with app name and public support contact.
- Flutter Map 8.3.2 default built-in HTTP-aware caching on native platforms;
  normal browser caching on web. No cache bypass, bulk download, or offline packs.
- No background prefetch; pan buffer zero. Maximum tile zoom 19.
- Valid backend coordinates become markers; tapping retains the detail sheet.
- No GPS permission or location upload. No directions engine or real monster spawns.
- Public tiles are best effort, not unlimited hosting or a guaranteed SLA.

Policy: https://operations.osmfoundation.org/policies/tiles/
Caching: https://docs.fleaflet.dev/layers/tile-layer/caching

Run the normal Flutter app. No MAP_TILE_URL, MAPS_API_KEY, or Gemini key is needed
for this map. Provider migration for higher traffic will require configuration work.

Tests use local tile images, never automated requests to OSM:

```powershell
flutter test test/open_map_test.dart test/rpg_game_test.dart test/rpg_ui_test.dart --concurrency=1
flutter test integration_test/rpg_maps_device_test.dart -d emulator-5554
```

The automated tests prove rendering, marker interaction and navigation with fixture
tiles. They do not claim public map-server availability or navigation routing.
