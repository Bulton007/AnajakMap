Every example is sent to /api/v1 on the Gateway. JSON results are wrapped in `{data, traceId, timestamp}`; projection rows from JDBC use uppercase field names. Use the appropriate data field as the next request input. Swagger aggregates all service schemas at the Gateway.

1. POST /auth/register: `{"email":"traveler@example.com","password":"AnajakDemo!2026#"}` → 201. Under dev, data.developmentCode is returned; production queues email instead.
2. POST /auth/verify: `{"email":"traveler@example.com","code":"<verification code>"}`.
3. POST /auth/login with the email/password → data.accessToken and data.refreshToken. Send `Authorization: Bearer <accessToken>` on authenticated requests.
4. GET /profile. PUT /profile/preferences: `{"preferences":{"pace":"relaxed","dietary":["vegetarian"],"language":"en"},"version":0}`. Use the actual profile version.
5. POST /trips with `Idempotency-Key: demo-trip-001`: `{"title":"Phnom Penh weekend","destination":"Phnom Penh","timezone":"Asia/Phnom_Penh","startDate":"2026-09-13","endDate":"2026-09-14"}` → data.id. Use current dates or your intended trip dates.
6. POST /guide/itinerary-jobs with a new idempotency key: `{"tripId":"<id>","preferences":{"pace":"relaxed"}}` → 202, data.jobId.
7. GET /guide/jobs/<jobId> until data.job.STATUS is SUCCEEDED or FAILED. Failure has ERROR_CODE; no fabricated itinerary is returned.
8. POST /guide/jobs/<jobId>/save-draft with an idempotency key → 201, data.itineraryId/version.
9. POST /trips/<tripId>/itineraries/approve: `{"itineraryId":"<id>","version":0}`.
10. GET /trips/<tripId>/calendar and /map. GET /offline for a versioned download. PUT /sync uses `{baseVersion,trip:{title,destination,timezone,startDate,endDate}}`; 409 requires reconciliation against the latest snapshot.

Additional paths are documented in OpenAPI. The smoke test provides executable examples for all of these:

- Conversations: POST /guide/conversations; POST/GET /guide/conversations/<id>/messages with `{text}`.
- Itinerary editing: PUT /trips/<id>/itineraries/<itineraryId> with `{version,itinerary:{activities,source}}`; only drafts are editable. Save a new draft to revise an approved itinerary.
- Replanning: POST /guide/replanning-jobs with tripId/preferences (include skippedStops/delayMinutes); POST /guide/jobs/<id>/save-proposal; POST /trips/<tripId>/replanning-proposals/<proposalId>/approve or /reject. Calendar/map remain unchanged before approval.
- Group: POST /trips/<id>/invitations with accountId/role (EDITOR or VIEWER); invitee POST /invitations/accept; POST /votes with activityId/value; PUT /location with enabled/latitude/longitude. Location sharing expires after five minutes and disabling consent deletes the location.
- Discovery: GET /discovery/places?query=Phnom%20Penh, /nearby?latitude=11.56&longitude=104.93, /weather, /food, /culture, /routes, /transport. POST/GET /discovery/journeys persists legs independently of provider estimates.
- Camera/voice: multipart POST /guide/media with file; POST /guide/vision or /voice with `{input:{mediaId}}`. Recognition returns candidates/confidence and remains uncertain. Translation: POST /guide/translation with `{input:{text,targetLanguage}}`; POST/GET /guide/phrases persists text.
- Budget: PUT /expenses/budget with tripId/amount/currency/version. POST /expenses with idempotency key and `{tripId,description,amount,currency,splits:{"<member>":"12.50"},receiptId?}`. Splits must exactly sum to the expense, and every participant must be an accepted trip member/owner. GET /expenses/summary?tripId=<id> groups totals by currency.
- Receipts: multipart POST /expenses/receipts with tripId/file; POST /<receiptId>/extract. Extraction is a suggestion; the user creates/confirms an expense. GET /expenses/currency?from=USD&to=KHR&amount=10.00 returns explicit source/update/estimate metadata.
- Bookings: multipart POST /reservations/documents with tripId/file; POST /documents/<id>/extract; POST /documents/<id>/confirm with provider/reference/timezone/startsAt/endsAt/version. GET /reservations?tripId=<id>. Existing bookings are organized; nothing is bought.
- Journal: POST /journal with idempotency key and tripId/title/content/recap/version. PUT /journal/<id> guards version and ownership. multipart POST /journal/<id>/photos; POST /journal/visits; POST /journal/<id>/generate-recap?version=<n> saves an editable recap.
- Calendar: POST /trips/<id>/calendar/events with title/startsAt/endsAt/timezone. Overlap returns 409. POST /calendar/sync is optional and adapter-backed.
- Notifications: POST /notifications/devices with token/platform; POST /reminders with title/dueAt; GET /deliveries. Development deliveries are marked MOCK_DELIVERED.
- Sessions: POST /auth/refresh with refreshToken rotates it; /logout revokes it. /forgot-password takes email and /reset-password takes email/code/password. Verification/reset codes expire in fifteen minutes; Redis caps requests and attempts.

Pagination uses page/size on trips and expenses; page on bounded journal/message/reservation/delivery listings. Expense sorting accepts created_at or amount. Sensitive media downloads return binary with Cache-Control: no-store. Version conflicts and duplicate keys with different input return 409. Idempotency keys are 8–128 alphanumeric/underscore/hyphen characters and scoped to actor/operation; reuse the exact key only for the same operation and payload.
