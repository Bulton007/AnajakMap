# Active map provider: OpenStreetMap

App maps use Flutter Map with OpenStreetMap standard tiles by default. The map
layer picker also offers terrain and cycling tile styles. These styles need no
API key or billing account. Google Maps code remains dormant; the picker does
not enable Google Maps services.

The Layers button opens a tray of illustrated style previews. Changing the base
map keeps the camera, selected pins and any confirmed road route. **Biking is a
map style, not bicycle routing**: the configured route engine still provides
driving directions. Live traffic and transit feeds are not configured and are
shown as unavailable rather than drawing simulated overlays.

| Style | Tile service | Credits | Native tile zoom |
| --- | --- | --- | --- |
| Map | Existing `MAP_TILE_URL` override or OpenStreetMap standard | Existing override or © OpenStreetMap contributors | 19 |
| Terrain | OpenTopoMap | © OpenStreetMap contributors · SRTM · © OpenTopoMap (CC-BY-SA) | 17 |
| Biking | CyclOSM, hosted by OpenStreetMap France | © CyclOSM · © OpenStreetMap contributors | 19 |

Provider sources: [OpenTopoMap](https://github.com/der-stefan/OpenTopoMap),
[CyclOSM tile service](https://github.com/cyclosm/cyclosm-cartocss-style/blob/master/README.md).
OpenTopoMap documents that its raster tiles are deprecated while it moves toward
vector tiles. All public services remain external dependencies; production scale
may require a maintained tile host. Layer definitions can be supplied separately
from their selector UI to support a future provider change.

- HTTPS tiles: https://tile.openstreetmap.org/{z}/{x}/{y}.png
- Visible, linked attribution on the map, updated for the selected style.
- Identifying native User-Agent with app name and public support contact.
- Flutter Map 8.3.2 default built-in HTTP-aware caching on native platforms;
  normal browser caching on web. No cache bypass, bulk download, or offline packs.
- No bulk or offline tile download; pan buffer zero. Tile zoom follows the style.
- Valid backend coordinates become markers; tapping retains the detail sheet.
- Foreground location is requested only after the map's location explanation.
  Directions send the selected origin/destination to the backend and configured
  routing service. Map style changes do not make a new directions request.
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
