# Driving routes for local testing

The app draws OpenStreetMap tiles and requests road geometry from
`GET /api/v1/discovery/routes` on the AnajakMap backend. Tile rendering alone
does not provide driving directions. The previous local configuration had no
`OSRM_URL`, so the route endpoint correctly returned 503.

The local Compose overlay now enables `OSRM_DEMO_ENABLED=true`. When `OSRM_URL`
is blank and the backend uses the `dev` or `test` profile, this selects
`https://router.project-osrm.org`. Returned routes use real road geometry,
distance and travel time; the app labels it **Public test routing**.
It has no live traffic, turn-by-turn navigation, offline routing or uptime SLA.
The endpoint can receive the origin and destination only after the user requests
directions. The **Start from** selector also accepts a searched place, so
place-to-place planning works without requesting GPS permission.

When **My location** is selected, **Directions** requests a fresh foreground GPS
fix on every manual tap. The app checks permission, location services, timestamp
and accuracy; it never substitutes a Cambodia origin for the user's coordinates.
Controls scroll on narrow/large-text layouts while leaving the map visible.

Use **Choose destination**, then tap the map to place a custom destination.
**Directions · Driving** routes from a fresh GPS fix to that point; choosing the
pin alone does not send a route request. **Choose start** also accepts a map pin
for planning without location permission. **My location** restores GPS as the
start. Search results from Explore remain available in the selectors. Changing
either endpoint clears the old route before new directions are requested.

After a road route is confirmed, **AI travel tips** opens an optional companion
panel. **Agree and ask AI** sends only the selected endpoint labels and the
confirmed driving distance/time to the existing authenticated conversation API.
The panel excludes GPS coordinates, road geometry and conversation history.
It asks for practical tips without fabricated turns or live-traffic claims;
actual directions keep working if AI is unavailable. This uses the existing
server-side Gemini configuration and does not put provider keys in Flutter.

The router limits road snapping to 1,000 metres at each end and independently
checks returned geometry endpoints. This prevents a public provider with limited
coverage from silently snapping a California origin to Portugal. NoRoute and
NoSegment return 404; excessive route size returns 422. A successful response
must contain real bounded road geometry; no straight-line fallback is created.

An Android emulator's default GPS may be in California. Set an explicit virtual
Cambodia test location in the emulator before testing a Cambodia driving route:

```powershell
adb -s emulator-5554 emu geo fix 104.9315 11.5638
```

This simulates a point in Phnom Penh. It is test data, not the user's physical
location or proof of a field-game visit. A physical device uses its own permitted
GPS fix. Routes do not create an overland connection between disconnected regions.

The page title is **Map**. Compact licence credit stays visible over the map,
as required by the [OpenStreetMap tile policy](https://operations.osmfoundation.org/policies/tiles/).

The [OSRM demo usage policy](https://github.com/Project-OSRM/osrm-backend/wiki/Demo-server)
allows reasonable **non-commercial** testing, at most one request per second.
This backend enforces that interval across route requests in its single local
instance, does not automatically retry demo requests, and returns HTTP 429 with
`Retry-After` when busy. Do not use multiple demo-backed replicas or run load
tests against the public service.

Restart/rebuild the discovery service after applying the source update. No API
key or billing account is required for this local demo. To disable it, set
`OSRM_DEMO_ENABLED=false` in the existing private backend `.env`.

For a public/commercial launch, configure `OSRM_URL` to your own OSRM server or
an OSRM-compatible provider whose terms cover the application. The backend
rejects known public demo URLs outside `dev`/`test`. The provider must use the
[OSRM Route API](https://project-osrm.org/docs/v5.24.0/api/#route-service),
return GeoJSON LineString geometry, meters, and seconds. Keep any provider
credentials on the backend. Do not invent routes when the provider cannot find
one; the app displays a retry or no-road-route state.
