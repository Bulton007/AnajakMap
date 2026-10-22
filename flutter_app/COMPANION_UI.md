# Companion interface update — 21 October 2026

Follow-up device inspection found that the photo hero shrank to its text width, and a failed generation left no recovery actions. The hero now fills the available content width. Failed plans include a localized explanation, retry with a fresh operation key, and a return-to-trip action. Quota failures use provider-supplied retry timing and disable premature retries. The backend terminates rate-limited jobs instead of immediately sending two more attempts, and temporary outages use bounded 30/60-second backoff. Tests exercise failure → retry → review → explicit approval without spending API quota.

Verified on the unlocked Samsung after installation: reopened the existing “hell mod” trip and selected its saved failed request. The full-width photograph, localized failure explanation, “Try again” and “Back to my trip” controls rendered correctly. No new generation was submitted during this device check. Eight targeted Flutter tests and 15 AI-service tests passed; Flutter analysis was clean. Backend readiness was UP. The quota limitation remains an external dependency, not a successful generation.

The connected Companion, translation/chat, itinerary review, Calendar and Offline screens reuse a bundled licensed Cambodia photo, shared theme colors, Material icons and localized English/Khmer copy. The photo is decorative and does not identify each itinerary stop. Attribution remains in `assets/ATTRIBUTION.md`.

Calendar uses activity/event cards, destination-timezone date formatting and expandable source attribution. Database IDs and numeric coordinates no longer appear in its normal view. Downloaded trips show formatted save dates, destinations and icon actions; opening a snapshot shows its calendar, map-point names and essential contacts. Queued edits show a readable preview while preserving explicit retry/discard behavior.

Itinerary generation shows actual pending, paused, failed and successful server states. Internal job identifiers remain in account-scoped local storage and network requests. Resume selects this trip's saved requests by title/date rather than requiring copied IDs. Generation and approval logic still require confirmed backend responses and explicit approval. Development/source disclosures remain available.

Provider behavior is unchanged by this UI work. Gemini's previously observed HTTP 503 issue remains unresolved; photo recognition and voice remain unavailable. This interface update does not certify those integrations as working.

Verification: Flutter analysis clean; tests cover Oracle calendar projections, hidden IDs, readable dates, all download-card callbacks, English/Khmer at 200% text, both card themes, existing sign-in/approval flows, and backend contracts. Device visual confirmation may require unlocking the Samsung.
