# Cambodia search and discovery UI

Place search uses Photon / OpenStreetMap through discovery-service. No mobile key or billing account is required. Local Compose sets PHOTON_BASE_URL=https://photon.komoot.io. For another deployment set that variable on discovery-service; use your own Photon deployment if traffic grows.

Search is submitted explicitly, restricted to Cambodia (KH), cached for 24 hours, and limited to 50 results per query. Uncached queries are globally spaced by two seconds using Redis. Provider failures return unavailable; they never become unrelated sample destinations. Public Photon has usage limits and no availability guarantee: https://github.com/komoot/photon . OSM coverage is not exhaustive.

Explore and its map share the same search results and coordinates. Editing a query clears old results; late responses cannot overwrite a newer query. Third-party destinations are not automatically approved RPG encounter sites.

Trip dates use the trip IANA time zone, including Asia/Phnom_Penh, and readable localized date/time ranges. Invalid dates show a dash and unknown time zones fall back to explicitly labeled UTC.

Culture and other discovery cards show icons, spacing, and a bundled Cambodia photograph or map as appropriate. Food, culture, weather and route estimates still use the existing development providers locally and are explicitly labeled sample data. Existing sample itineraries are not rewritten by place search.

Explore requests `/discovery/photos?query=...&page=...` after loading each results page. The backend matches English/Khmer Wikipedia article titles and coordinates within 5 km, then resolves freely licensed Wikimedia Commons images and their author/license metadata. Photo metadata is cached for 24 hours; outgoing photo batches are globally spaced by three seconds. Images load directly from Wikimedia. Missing images, uncertain matches and provider failures retain the fallback; photo coverage is not guaranteed for every place. No random stock images are substituted.

Cards and place details show photos with a credit button containing artist, credit, license link and original Commons page. The source is not a proof of current appearance. The place query now requests international names from Photon, while accepting multilingual search text. Keep provider attribution and review Wikimedia/Photon usage limits as traffic grows.

The local AI/discovery containers use `EXTERNAL_DNS` (default `1.1.1.1`) after Docker Desktop's resolver failed to resolve Wikipedia during verification. Override this with your network's approved resolver if needed; Docker's internal service-name routing remains in place. This is a local Compose setting, not a change to the computer's global DNS. Photon has a bounded 20-second response timeout; optional photo calls have 8-second response timeouts.

Validation: Flutter search race and timezone tests; backend country filtering, cache/pagination and failure tests. Live provider availability must be checked separately from unit tests.

20 October verification: authenticated gateway search returned Angkor Wat among
20 results; `/discovery/photos` returned one licensed image with attribution.
Both `upload.wikimedia.org` and the API's `thumb.wikimedia.org` thumbnail host are
accepted. Matching, license rejection, untrusted-host rejection and provider
failure tests pass. This proves the checked place, not universal photo coverage.
