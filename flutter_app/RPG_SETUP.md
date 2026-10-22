# Creature trails — connected RPG

## Implemented

The connected app game icon opens `/adventure`; destination details pass their ID
into it. Authentication preserves the destination. The existing OpenStreetMap
widget selects informational destination pins; it does not claim live monster
locations. Pushed map routes preserve the previous view on return.

Account adventure provides a starter monster, six original species in the bestiary,
three-member parties, destination encounters, server-controlled turn-based combat,
capture, XP/levels, evolution, unique owned instances, recurring and milestone quests,
persistent inventory, a game-gold shop, titles, guardians and reward history.
No AI calls, paid maps, new production dependencies or services were added.

| Mode | Storage | Location | Rewards |
| --- | --- | --- | --- |
| Device practice `/rpg` | Existing SharedPreferences | Simulated temple/beach | Editable local test values |
| Server practice | Oracle practice realm | Explicit simulation, no GPS | Separate test XP/gold/collection |
| Field adventure | Oracle field realm | Explicit GPS request and server checks | Game XP/gold only; redemption disabled |

Device practice is never uploaded. Server practice requires
`RPG_SIMULATION_ENABLED=true` AND the backend dev or test profile. The local compose
override enables it. Never deploy the dev compose configuration to production.
Seeded Royal Palace, National Museum and Wat Phnom IDs match discovery fixtures.
They are unreviewed, with field gameplay disabled. Server practice uses these
three temple habitats. Beach species are in the bestiary and device practice;
a server beach destination must be configured before server beach encounters work.

## Run locally

Docker Desktop Linux engine must be running. This session uses port 8088 because
Steam occupies 8080; the default remains 8080 without an override.

```powershell
cd C:\anajak_map\AnajakMapBackend\AnajakMapBackend
$env:GATEWAY_HTTP_PORT='8088'
# Build after source changes, migrate, grant runtime access, start services:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\start-local.ps1
# Subsequent starts with current images may add -SkipBuild.
Invoke-RestMethod http://127.0.0.1:8088/actuator/health/readiness

cd C:\anajak_map\flutter_app
flutter run -d emulator-5554 --dart-define=API_BASE_URL=http://10.0.2.2:8088/api/v1/
```

Sign in with a verified account → game icon → Server practice → choose destination
and companion → confirm safety → start encounter. Strike, magic, guard, heal,
capture and retreat all use server outcomes. Claim completed quests in the journal.
The default cooldown is five minutes and daily limit is ten per account/realm,
reset at UTC midnight. Active sessions resume after app restart and expire in 15 minutes.

USB device: `adb reverse tcp:8088 tcp:8088`, then use API_BASE_URL
`http://127.0.0.1:8088/api/v1/`. iOS simulator uses localhost; iOS device testing
was not performed on this Windows host. Never embed real credentials in Dart defines.

## API and database

Gateway routes rpg to discovery-service. All endpoints require the existing JWT;
identity comes from its subject. Responses retain `{data, traceId, timestamp}`.

| Method | Path under /api/v1/rpg | Purpose |
| --- | --- | --- |
| GET | /capabilities | Simulation/redemption availability |
| GET | /{realm}/world | Destination rules and review flags |
| GET | /{realm}/profile | Progress, collection, species, quests, ledger, active session |
| POST | /{realm}/encounters | destinationId, monsterId, safeConfirmed, optional location |
| POST | /{realm}/battles/{id}/actions | revision, move, optional monsterId for switch |
| POST | /{realm}/quests/{id}/claim | Completed quest reward, once per applicable period |
| POST | /{realm}/party | monsterIds: 1–3 owned instances |
| POST | /{realm}/monsters/{id}/evolve | stage: expected current stage, 0 or 1 |
| POST | /{realm}/inventory/purchase | item: potion/crystal, quantity: 1–10 |
| POST | /{realm}/title | id: unlocked achievement title |

Realm is practice or field. POSTs require Idempotency-Key (8–128 alphanumeric,
underscore or hyphen characters). Moves: strike, magic, guard, heal, capture,
retreat, burst, switch. Reusing a key with a changed payload is rejected.
Encounter creation accepts kind: wild/boss (wild by default).

Discovery migration V3__rpg.sql adds rpg_players, rpg_destinations, rpg_monsters,
rpg_sessions, rpg_ledger, ownership indexes, foreign keys, nonnegative balances,
unique reward sources and an append-only ledger trigger. No existing progress is
migrated. Writes lock the account/realm row; state, collection, balances,
idempotency records, audit and outbox commit together. Stale battle revisions
are rejected. There is one active encounter and a 100-instance MVP collection limit.

Flutter prevents duplicate submissions and retains the exact request/key after
uncertain network/5xx outcomes. Mutations refresh authoritative state; no optimistic
rewards are granted. Keys are in memory only. After app termination, profile reload
reconciles saved sessions/collection/ledger without silently repeating the action.

## Rules

- Habitat species weights: Common 60%, Rare 30%, Epic 10%.
- Level: min(50, 1 + floor(XP/100)); HP: species HP + 4 × level + variation (0–5).
- Speed determines turn order; ties favor player. Guard is prepared before attacks.
- Raw damage: (attack + 2 × level + variation) × (magic ? 1.4 : 1) − (defense + level)/2.
  Apply magic affinity (1.5 advantage, 0.75 disadvantage), critical ×1.5 (10% chance),
  round, subtract shield and clamp to at least one damage.
- Water beats fire, fire beats earth, earth beats water. Physical attacks are neutral.
- Magic costs one of three energy; strike/guard restore one. Guard absorbs 12 damage.
- Two potions per encounter restore up to 30 HP and clear poison. Enemy magic every
  third turn; two-turn poison every fourth turn. Poison costs five HP per turn.
- Three capture attempts. Chance: clamp(0.2 + 0.65 × missingHpFraction −
  (Epic ? 0.12 : 0), 0.08, 0.85).
- Victory/capture: 30 + enemyLevel × 10 XP; 10 + enemyLevel × 5 gold.
  Only capture creates an owned instance. First-win/first-capture quests each award
  50 XP + 20 gold once per realm. Retreat, defeat and expiry give no reward.
- Health and energy reset per encounter; consumables come from persistent inventory.
  Fifty turns maximum. Game gold buys potions/crystals and funds evolution, with no
  cash value. Separate travel points remain zero; redemption is unavailable.

RpgRules is independent of UI/database. Tests inject seeded randomness; production
uses SecureRandom. Species/ability rules are versioned Java definitions in this MVP,
not an admin-editable content catalog. Destination limits/boundaries are database rules.

## Location policy

Field encounters require approval/accessibility/minimum level, safe stationary
confirmation, a GPS sample at most 60 seconds old (no more than five seconds future),
accuracy >0 and <=50m, mock=false, and distance + accuracy inside the radius.
GPS is requested once on explicit start, never continuously. Raw GPS is not written
to RPG tables or audits. These checks do not prove physical presence; a compromised
client can lie. Reviewed safe boundaries, attestation and abuse detection remain
necessary before public field launch. Do not simply approve the fixtures for release.
No money, vouchers, real discounts or external rewards are granted.

## Tests

```powershell
cd C:\anajak_map\flutter_app
flutter analyze
flutter test test/adventure_test.dart test/rpg_game_test.dart test/rpg_ui_test.dart test/open_map_test.dart test/auth_test.dart
```

Java 21/Maven from backend root:

```text
mvn -B -ntp -pl discovery-service,gateway-service -am package
```

RpgPersistenceTest requires an ISOLATED discovery test schema and environment:
RPG_ORACLE_TEST=true, ORACLE_TEST_URL, ORACLE_TEST_USER, ORACLE_TEST_PASSWORD.
Never use a live schema. Run only RPG tests against that schema:

```text
mvn -B -ntp -pl discovery-service -am test -Dtest=Rpg*Test -Dsurefire.failIfNoSpecifiedTests=false
```

Tests cover real Oracle migrations, rollback, ownership, concurrent quest rewards,
capture replay, realm isolation, expiry/restoration, JWT protection, validation,
response envelope, seeded combat, location boundaries and Flutter retry behavior.
UI tests cover 320×640 layouts, 200% text, English/Khmer and both themes.

Live emulator test: scripts/rpg-test-account.py creates a disposable account only
with the existing isolated compose.auth-test.yml mail adapter active and a random
MAIL_TEST_KEY. Restore normal identity configuration after creating the fixture.
It sends no real email and writes credentials to ignored
flutter_app/.local/rpg-device.local.json. Never commit/share this file or test APK.

```text
flutter test integration_test/adventure_server_test.dart -d emulator-5554 --dart-define-from-file=.local/rpg-device.local.json
```

The test logs in through the real backend, starts/acts in an encounter, reloads the
saved revision and finishes a battle. Tokens remain in memory and are revoked at
teardown. Delete the local test configuration after use.

## Progression and procedural 3D extension

V4__rpg_progression.sql preserves existing progress and adds persistent inventory,
append-only item/spending transactions, saved parties, individual battle combatants,
evolution stages, weighted destination spawn rules and battle completion timestamps.
Existing accounts receive five potions and eight crystals as a migration baseline.
Party changes, purchases and evolution are blocked during active encounters.

- Evolution: level 4 / 75 gold, then level 8 / 150 gold; maximum two stages.
  Each stage adds 12 HP, 4 attack, 2 defense and 2 guard shield.
- Burst unlocks at level 3, costs two energy and uses 1.6× magic damage.
  Player attacks have 95% accuracy. Switching consumes a turn; surviving reserves
  can replace a defeated companion. Only the finishing companion gains battle XP.
- Potions cost 10 gold; crystals cost 15. Server actions consume persistent stock,
  bounded to two potions and three capture attempts in each battle. Victory drops
  a potion; capture drops a crystal, subject to the inventory cap.
- Daily quest: two wins, reset UTC midnight. Weekly: three captures, Monday UTC.
  Collection, evolution, guardian, level and destination milestones are also available.
- Three successful encounters at a destination unlock its guardian. Guardians
  cannot be captured, become stronger below half HP and grant triple battle rewards.
  Titles are earned cosmetics; no real-money purchase or redemption is present.

BattleScene uses original procedural 3D meshes projected and lit by CustomPainter,
with orbit drag, idle/action/capture effects, reduced-motion and low-detail modes,
and an explicit 2D fallback. These are temporary low-poly models, not rigged assets.
There are no additional model downloads or external art licenses. Existing fonts
retain their bundled licenses. New collection details show server-computed stats.

## Outstanding

Rigged production 3D assets, physical-device performance benchmarks, legendary
species/events, richer status combinations, admin content tools, social features
and multiplayer remain unimplemented. The real destination catalog needs review;
the three seeded field destinations remain disabled, and no beach coordinates were invented.
English/Khmer controls and themes work; server battle logs/errors still use English
and need localized codes. Physical-device/iOS testing, public-location safety review,
attestation and production operational hardening remain outstanding.
