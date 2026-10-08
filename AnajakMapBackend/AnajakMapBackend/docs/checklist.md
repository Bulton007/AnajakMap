The implementation checklist is maintained separately from execution evidence. A checked implementation does not mean that a live provider or target cluster has been verified.

| Feature | Implemented backend behavior | Execution evidence |
|---|---|---|
| 1. AI assistant | Conversations, persisted messages, preferences, media-backed voice operation | Preferences/messages/voice passed final Oracle/API smoke; AI uses explicit dev fixtures |
| 2. Itinerary | Persistent generation jobs, validation, versioned drafts/editing, approval, retrieval | Generate/save/approve/calendar/map passed final smoke; draft editing is implemented but not exhaustively exercised |
| 3. Map/discovery | Search, nearby, coordinates, route adapters, approved trip map | Search grounding, nearby/routes fixtures and trip map passed final smoke |
| 4. Camera | Private upload, S3 bytes, recognition candidates/confidence/explanation, OCR adapter | Media upload, ownership rejection and vision fixture passed; invalid structured responses/signatures covered by tests |
| 5. Replanning | Weather/calendar/delay/skipped-stop inputs, proposals, explicit approve/reject, stale protection | Weather-grounded job, save-proposal and explicit approval passed final smoke |
| 6. Expense | Budgets, decimal expenses, membership-checked splits, receipts, currency adapter | Budget/splits/summary/idempotency, receipt extraction/confirmation and currency fixture passed |
| 7. Food/culture | Provider-backed dishes/places/guidance with dietary inputs | Food/culture dev adapters passed final smoke; live provider accuracy pending |
| 8. Groups | Owner/editor/viewer, invitations/acceptance/removal, votes, expiring opt-in location | Invitations, viewer permissions, voting and opt-in/out location passed final smoke; owner/viewer unit coverage |
| 9. Offline | Versioned trip/calendar/map/contact snapshot, conditional sync, 409 conflicts | Snapshot, contacts and stale edit rejection passed final smoke; conditional version updates tested against Oracle |
| 10. Journal | Private entries, versions, photos/downloads, visits, editable generated recaps | CRUD/stale versions, photos/downloads, denied viewer download, visits and generated recap passed |
| 11. Calendar | Activities reused directly, standalone events, zones, conflict checks, reminders, optional sync | Calendar/events/conflicts/sync fixture and confirmed reminder delivery passed final smoke |
| 12. Reservations | Private documents/downloads, extraction suggestion, versioned user confirmation | Actual S3 upload/download, extraction fixture and user-confirmed record passed final smoke |
| 13. Translation | Text/voice operation and saved phrases | Translation/voice dev adapters and phrase persistence passed final smoke |
| 14. Transport | Provider estimates, persisted legs, departure/arrival/zones/transfers | Transport estimate fixture and saved/retrieved journey legs passed final smoke |

- [x] Nine executable Maven service modules and technical platform without shared business entities/repositories.
- [x] Oracle schemas, constraints, indexes, versions, audit/outbox/idempotency migrations.
- [x] JWT issuer/audience/signature/expiry validation; hashed passwords/codes/rotating refresh tokens; request and attempt limits.
- [x] Local business transactions with audit/outbox, durable broker confirms, bounded retries, inbox deduplication and dead-letter paths.
- [x] Non-owner runtime accounts, append-only audit grants, standalone migration mode and production migration Jobs.
- [x] Oracle-backed calendar cache with 60-second TTL and rollback-safe after-commit invalidation.
- [x] Structured traceable logs, persistent local/deployment logs, readiness and metrics.
- [x] Explicit dev/test mocks; required production integration configuration fails startup.
- [x] Dockerfiles, Compose, OpenShift resources, environment guide, examples, demo-producing smoke script.
- [x] Source tests, real Oracle migration/rollback/audit/version tests, vertical-slice API smoke.
- [x] Final restricted runtime and expanded fourteen-feature API smoke passed after disk/Docker recovery.
- [x] Arbitrary UID 1000999000:0 with read-only root filesystem booted and reported readiness UP.
- [x] Eight aggregated OpenAPI documents returned valid specifications.
- [x] Broker duplicate-event integration and runtime database privilege tests: passed against Oracle and RabbitMQ after Docker recovery.
- [ ] Live provider contracts, production mTLS/log forwarding and target OpenShift validation: require external configuration/environment.

No packing or departure checklist is included in the product.
