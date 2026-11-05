# AnajakMap collaboration verification

## Version 3 release preparation

- Version is 3.0.0, build 13; package ID is unchanged. Public backend auth config returned 200 and the protected journey endpoint returned 401 to an anonymous request. The active tunnel points to the existing updated backend on port 18090.
- Final full Flutter run: 273 passed, one optional live test skipped; analyzer clean. Relevant backend reactor: 60 passed, 14 environment-dependent tests skipped. Separate RPG Oracle integration verification is recorded below.
- Full-suite verification found unsafe provider access during notification-shell disposal. The device service and notification scope are now cached during initialization. After visual review, 11 screenshot baselines were refreshed for the intentional shared UI changes; the final full suite passed without updating screenshots.
- Release signing configuration is prepared locally but awaits the existing upload keystore and signing settings. Signing files, production-local JSON and generated bundles are ignored and not staged. No signed AAB or Play upload is claimed.

## Compact UI and map follow-up

- Profile now groups identity information in a compact account card and keeps language and appearance controls in an expandable section. System, light, and dark options use readable selection rows with a visible selected state.
- Notification cards have smaller spacing and icons, a compact open action, and localized Khmer event titles. Phone notification controls remain available in an expandable section.
- Shared page content now fills its available width. This fixes the narrow Khmer home banner. Headline sizes and letter spacing were adjusted, while the system text scale remains respected. Main-tab safe areas now clear the bottom navigation.
- Explore place details have a smaller title and an immediately visible Open directly in map action. Missing, nonfinite, or out-of-range coordinates disable the action. Real selected coordinates and name pass through the existing map route. A live emulator check selected Wat Saravan in the destination panel.
- Restored floating search and bottom controls around the existing OpenStreetMap implementation. Routing, provider attribution, and layer controls remain connected. Long press can select a destination.
- All 60 focused UI and map tests passed, including route entry, invalid coordinates, Khmer layout, theme selection, map layers, permission flows, and small screens. All 60 game behavior and layout tests passed. The game remains subject to its documented field-location restrictions and still needs real-phone GPS field verification.

## Restart correction

On November 5 the normal Version 12 launcher recreated the earlier service images. The running trip service returned HTTP 404 for the new invitation inbox and private conversation routes. Restoring the tested collaboration images fixed both emulator screens.

After starting the base local backend, run `Start Collaboration Backend.cmd` from this checkout to apply `compose.collaboration.yml`. The launcher reuses the private backend's existing environment file and running infrastructure. It checks that the tested images exist and starts the collaboration services plus the journey-enabled discovery service with the WebSocket proxy configuration. Images must be rebuilt if the backend code changes or the local images are removed. New installations must apply the journey migration and runtime grants described in `flutter_app/RPG_SETUP.md` before starting the runtime image.

Both failed emulator screens were retried successfully. Private messages showed its traveler action and empty list. Trip invitations showed its empty state. Backend readiness returned UP.

## Implemented

- Trip owners can look up a verified traveler by their shared account code, invite them, review invitation status, and cancel a pending invitation. Invitees can accept or decline from the notification center. Pending invitations do not grant trip access. Repeating a pending invitation or an already completed response does not create another event.
- The notification service uses the existing outbox, RabbitMQ consumer, and deliveries table. Invitation responses and new chat messages have durable inbox entries. Foreground clients use an account-scoped WebSocket to refresh the unread count and notification center. The center supports individual and bulk mark-as-read, and opens the matching invitation, trip, or chat.
- Trips and approved activities can prefill the existing reminder form. A pending reminder can be edited or cancelled. The delivery worker rechecks eligibility when it claims a reminder, so an edit to a later due time or a cancellation wins if it completes before the claim.
- Private and trip chats use the existing bearer token and gateway. The database persists messages, with paginated history and idempotent send retries. Private conversations show unread counts and read receipts. Both chat types show timestamps, sender names when available, typing indicators, and connection status. Clients fetch authorized history after WebSocket signals and periodically retry a disconnected socket.

## Backend and database

- Identity lookup is in `identity-service/.../Auth.java`. Invitations and chat are in `trip-service/.../TripApi.java` and `TripChatApi.java`. The existing access helper is in `platform/.../TripAccess.java`.
- Notification inbox and reminders are in `notification-service/.../NotificationApi.java` and `DeliveryWorker.java`. Socket handling is in `gateway-service/.../TripChatSocket.java`. The laptop Nginx configuration forwards WebSocket upgrade headers.
- Oracle trip migrations V5–V8 add group messages, invitation status, private messages, and private read receipts. Notification V4 adds inbox event type, actor, trip, detail, and read timestamp. PostgreSQL migrations cover the same structures. The Oracle migrations were applied on the local test stack using the schema owner and narrow runtime grants.

## API surface

All paths below are under `/api/v1`.

| Area | HTTP endpoints |
| --- | --- |
| Traveler lookup | `GET /profile/travelers/{accountId}` |
| Invitations | `GET /trips/invitations`, `GET/POST /trips/{tripId}/invitations`, `POST /trips/{tripId}/invitations/accept`, `POST /trips/{tripId}/invitations/reject`, `DELETE /trips/{tripId}/invitations/{accountId}` |
| Reminders and notification inbox | `POST /notifications/reminders`, `PUT/DELETE /notifications/reminders/{id}`, `GET /notifications/deliveries`, `GET /notifications/unread`, `PUT /notifications/deliveries/{id}/read`, `PUT /notifications/deliveries/read` |
| Trip chat | `GET/POST /trips/{tripId}/chat`, `POST /trips/{tripId}/chat/typing` |
| Private chat | `GET /trips/direct-chat`, `GET/POST /trips/direct-chat/{peerId}`, `GET /trips/direct-chat/{peerId}/access`, `POST /trips/direct-chat/{peerId}/typing`, `PUT /trips/direct-chat/{peerId}/read/{messageId}` |

WebSocket destinations are `/notifications/live`, `/trips/{tripId}/chat/live`, and `/trips/direct-chat/{peerId}/live`. A socket binds to its authorized destination during the authenticated upgrade. Frames carry a readiness signal, a data-change signal, or a typing sender identifier. Message and notification bodies come from the corresponding authenticated HTTP endpoints.

## Flutter files

- Networking changes are in `api_client.dart`, `providers.dart`, `travel_repository.dart`, and `live_socket.dart`.
- The connected UI changes are in `connected_shell.dart`, `connected_tools.dart`, `connected_trips.dart`, `trip_invitations.dart`, `trip_chat.dart`, and `direct_messages.dart`.
- `remote.dart` now updates its stored future synchronously in `setState`, fixing the assertion hit when refreshing after an invitation response.

## Checks executed

- Two disposable verified accounts signed in independently against the running Oracle-backed test stack. Their WebSockets connected through Nginx. The recipient received an invitation signal and the correct trip and inviter identifiers. Duplicate invite and accept calls left one invitation and one participant. A pending invitee received HTTP 403 from group history. Declines and cancellations appeared in the correct inbox.
- The invitation was opened and accepted from the Android emulator notification center. The sender’s membership API showed the accepted traveler. The foreground alert frame was verified in the live gateway test. The emulator check verified the notification center and navigation.
- Two authenticated sessions exchanged private messages, verified idempotent send retry, disconnected and reconnected, and loaded a message sent while disconnected. An accepted member received a group chat event. A Khmer message persisted. Reading it changed the private unread count from one to zero and sent the sender a live receipt. An authenticated typing event reached the recipient’s deployed WebSocket.
- A reminder was created in the Android emulator and moved from Pending to development delivery. On the running backend, a rescheduled reminder fired at the new time and a cancelled reminder remained cancelled after its original due time.
- Flutter analyzer reported no issues and all 11 focused widget tests passed. The identity, trip, notification, gateway, and platform Maven runs passed, with opt-in database tests skipped in Maven. The independent live checks exercised Oracle. A broader Flutter run reported two sign-in screenshot differences.

## Remaining verification and infrastructure

- The server push adapter remains in development mode. Connected inbox events now create real phone notifications through the local notification plugin. New remote messages received after the application process has terminated still require a configured push provider and registered device tokens. iOS runtime and PostgreSQL were not run.
- The private chat list has unread counts and read receipts. Group-level read receipts, profile images, and remote online presence remain open. The app uses exact account-code lookup, since the project has no public name directory.
- The live reconnect and receipt checks used separate authenticated sessions. A full logout/account-switch walkthrough and simultaneous chat walkthrough on both emulator UIs remain to be verified.

## Native phone notification update

- Added `DeviceNotifications` using `flutter_local_notifications`. Android has a high-importance notification channel, notification permission, a monochrome icon, reminder receivers, and an optional precise-alarm permission. iOS has permission requests and foreground notification presentation configured.
- Connected inbox events create phone notifications instead of SnackBars. A notification tap checks its account scope and opens the corresponding invitation or conversation through the existing authenticated screens. Posted IDs are persisted to prevent replay after app restart.
- New and edited reminders are also scheduled with the operating system. Cancellation removes the native schedule. Server data remains authoritative and refresh reconciles visible reminder entries. A change made on another device needs connectivity to update an already scheduled local reminder.
- Logout cancels the active account's native notifications and schedules. Notification preferences expose permission status, phone settings, a real test notification, and a test reminder. Android timing may be delayed without the optional precise-alarm permission.
- On Android emulator 5554, notification permission was granted through the system prompt. The test notification appeared in Android's tray. A 15-second reminder appeared while the app was backgrounded. A further scheduled reminder was verified by its new native notification ID after the app process was terminated with its own debug UID.
- A message sent from emulator 5556 generated a native notification on backgrounded emulator 5554. Tapping it opened the correct conversation and displayed the new message.
- The final focused test run passed all eight tests, covering native posting deduplication, reminder rescheduling and cancellation, permission denial, account isolation, date formatting, notification layout, and chat/invitation behavior. Flutter analyzer reported no issues. iOS configuration has not been device-tested.
# Real game entry follow-up

- Normal Creature trails entry now shows the existing account-backed field adventure, with English/Khmer copy and a destination action when reviewed locations exist.
- Practice entry controls require `RPG_PRACTICE_TOOLS=true` in a non-release build. Release builds hide those controls regardless of the flag. Existing developer practice and separate data remain intact.
- No fixture locations were approved and no GPS or backend reward rules were bypassed. The current seeded destinations remain unavailable for field encounters.
- Focused adventure tests: 19 passed, including normal-entry availability and field endpoint/GPS forwarding. Flutter analyzer and diff whitespace checks passed.
- Both running Android emulator apps restarted. The English emulator's actual game screen showed the real adventure entry and clear unavailable-locations message, with no practice promotion. This was an entry-screen check, not live GPS gameplay verification.
- Updated product choice: random creatures at places the player actually visits, with live GPS journey tracking. Personal GPS stops now enable encounters without approving development fixtures. Approved public locations remain supported.
- Added opt-in foreground tracking with real position, recorded route, distance, pause/resume/end, and personal visited-stop markers. Routes save to the authenticated account; tracking pauses when leaving the screen or app. Untracked gaps are not drawn or counted as travelled distance. English/Khmer and narrow phones with large text are covered.
- Backend migration adds account-owned journeys, GPS points and visited stops. Fresh, accurate, non-mocked GPS and stationary samples establish stops; other accounts cannot read them or use them for encounters. Existing server combat, rarity weights, rewards, cooldown and daily limits remain authoritative.
- Validation: 27 Flutter tests passed. All 18 selected backend tests passed, including 8 actual Oracle persistence tests in a disposable schema and a clean migration through V5. The first Oracle run exhausted connections; test setup now uses bounded pools and migrates the shared test schema once. Analyzer passed. Physical-device field verification and iOS runtime testing remain outstanding.
- Local rollout applied V5 as DISCOVERY, granted runtime access to the three new tables, and started `anajakmap/discovery-service:journey-v1`. Backend readiness returned UP. Both Android emulator apps restarted with the new game entry. Android GPS uses the native location manager without requiring Google's optional network Location Accuracy service.
- Actual Android emulator test on Emulator Test B: granted foreground location permission, started live tracking, recorded a personal stop, fully backgrounded/reopened the app and observed Tracking paused, entered a GPS-checked field encounter, used Magic/Strike/Capture against a randomly selected River Makara, and received the confirmed capture outcome (+40 XP, +15 game gold). The account collection showed the owned River Makara instance and 15 gold. No mock combat or database reward edits were used. This used the emulator's GPS, not physical travel. Tracking was paused when leaving the journey screen. Screenshots: `flutter_app/build/journey-new-ui.png` and `flutter_app/build/journey-capture.png`.
- Files for this follow-up: Flutter `features/rpg/adventure_{screen,controller,repository}.dart`, new `journey_{screen,controller}.dart`, shared `features/maps/map_location.dart`, `test/{journey,adventure_entry}_test.dart`; discovery `Rpg{Api,Service,Rules,Progression,Journey}.java`, Oracle V5/PostgreSQL V2 migrations, `Rpg{Api,Persistence}Test.java`; `compose.collaboration.yml`, its launcher, and `RPG_SETUP.md`. No push was performed.
