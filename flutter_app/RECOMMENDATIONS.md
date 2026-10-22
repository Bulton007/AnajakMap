# Personalized recommendations and expanded colors

Open **Companion → Find my kind of place**, or the matching action in Explore.
Choose a saved trip or enter a Cambodian destination, select Culture/Food/Nature/Beach/City, and choose 3, 5 or 8 suggestions. This pace setting controls suggestion count; it does not claim optimized travel times or visit duration.

The new authenticated `POST /api/v1/guide/recommendations` contract accepts:

```json
{"destination":"Siem Reap","interests":["culture"],"pace":"balanced","language":"en","useAi":false}
```

The Spring controller searches the existing Cambodia-filtered discovery service, ranks retrieved categories against selected interests and returns `items`, `mode`, `aiStatus`, `query`, and `retrievedAt`. Flutter fetches optional photo metadata using that returned query. Each card retains trusted place identifiers, coordinates, source attribution and original OSM reference URLs. Invalid identifiers never become source links. The map reference supports name/location/category, not recommendation opinions, ticket prices or opening hours. Retrieval time is not the source's last-update time.

`useAi:false` is the default: preference matching is useful without Gemini and is explicitly labeled as such. **Ask AI to choose & explain** requests one grounded Gemini selection from supplied place indices. Model output cannot choose arbitrary places or control reference links. Failures retain usable preference matches; successful AI results use `mode:ai_grounded`. Provider quota errors with retry metadata create a shared Redis cooldown, returned as `retryAt`. The new endpoint never writes to a trip.

**Save place** writes only to the existing account/backend-scoped device cache. **Add to trip** opens editable title/time fields, includes the current approved activities in a review draft, and uses the existing explicit approval flow. It does not silently approve an itinerary or upload a guest draft. **View place** retains map, details and photo licensing behavior.

Photos use the existing Wikipedia/Commons matcher and licensed attribution UI. Exact normalized names may omit a trailing “temple” only when matching article names; the existing coordinate and license checks still apply. Missing images show an interest-specific colored icon. There is no guarantee of a photograph for every result.

Shared themes now use violet primary controls, warm gold navigation/notice accents, coral/sky/rose/teal action-card variants, warm light backgrounds and navy dark surfaces. Existing bundled photography and fonts retain their attribution. Visual baselines were intentionally refreshed for the palette change.

No additional secret is required for preference recommendations or photo matching in the existing local configuration. Optional AI explanations use the existing server-only Gemini credentials. The provider's exhausted quota remains a dependency for live AI generation. Grounded recommendation model contracts were tested with mocks; no successful live AI recommendation is claimed.

This is a bounded retrieval/ranking/explanation workflow. Persistent conversational preference memory, live opening-hours/price providers, route optimization, web research citations, weather replanning, autonomous bookings, and RPG quest recommendations are not implemented by this feature.

Verification: backend ranking, trusted reference construction, optional-AI fallback, provider cooldown and invalid model selection tests; Flutter source disclosure, local saving without trip writes, stale-response protection, quota fallback, Khmer at 200% text, theme contrast and full application regression suite.

Live device check: the Samsung's authenticated recommendation request returned HTTP 200 in 1558 ms. The app displayed Baphuon temple from the real Cambodia-filtered place provider, its address/category match, and a Wikimedia photograph with author and CC BY-SA 4.0 attribution. Other places without verified photos retained colored category illustrations. No Gemini request or trip approval was submitted during this check. The full Flutter suite passed 100 tests (one opt-in live test skipped); the AI-service suite passed 21 tests. The final Companion card-padding correction passed nine targeted UI tests.
