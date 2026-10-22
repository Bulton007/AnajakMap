# Anajak Travel RPG implementation — 2026-10-16

## Delivered and playable

The authenticated `/adventure` route now connects destination encounters, server
combat/capture, account collection, XP, evolution and quests. Existing OSM maps,
authentication, travel routes and device-local practice remain intact.

- Six original species; configurable destination spawn weights and difficulty.
- Three-member saved parties, turn-consuming switches and surviving reserves.
- Persistent potions/crystals, game-gold purchases and append-only transactions.
- Two evolution stages; computed stats, level-gated burst ability and stronger guard.
- Daily/weekly UTC quests, collection/evolution/level/destination milestones.
- Unlockable guardian battles, stronger second phase and triple game rewards.
- Achievement titles, exploration totals, collection search and battle history.
- Procedural low-poly 3D creatures with camera orbit, action/capture effects,
  reduced motion, low-detail mode and 2D fallback. These are temporary original
  meshes, not production rigged models. No external model download is required.

## Modules and persistence

Backend discovery package: RpgRules, RpgService, RpgApi and RpgProgression.
V3 establishes account/realm-owned progress, sessions and immutable reward ledger.
V4 adds inventory, spending/item transactions, parties, combatants, evolution,
spawn weights, difficulty, guardian rules and completion timestamps. Both are
applied to the local Oracle database. Existing progress is preserved.

New POST operations under `/api/v1/rpg/{realm}`: `/party`,
`/monsters/{id}/evolve`, `/inventory/purchase`, `/title`.
Encounters accept `kind`; actions accept `burst` and `switch` plus a companion ID.
All mutations use JWT ownership, an account row lock and transactional idempotency.
Stale revisions, unaffordable purchases, duplicate party members and unowned
companions are rejected. Rewards and spending cannot be accepted from the client.

Flutter modules: adventure_repository/controller/screen, adventure_management,
battle_scene. The management views share the existing account/realm provider,
error handling and retry key. No new production service or rendering dependency.

## Verification

- Backend package passed: 15 RPG tests, including six against isolated Oracle 23.
- Flutter analyzer clean; full suite: 76 passed, one existing skipped test.
- UI coverage includes collection/evolution/inventory/title actions, procedural
  painting/orbit/fallback, reduced motion, small screens, large text and themes.
- Reviewed the updated Explore screenshot; its golden now includes the existing
  RPG entry. Map navigation asserts OSM attribution with local tile fixtures.
- Live Android integration passed against the real local gateway/identity/Oracle:
  sign-in, encounter, action, saved revision reload, terminal ledger consistency,
  party/inventory/quest/history contracts, with purchase assertions on a win.
  The isolated email adapter was removed, normal identity configuration restored,
  test session revoked, and ignored test credentials deleted.
- Normal debug app rebuilt, installed and launched on emulator-5554 against port
  8088. Startup logs showed skipped frames in debug mode; this does not establish
  production rendering performance, which remains unbenchmarked.

## Boundaries and remaining work

Server practice is functional and stores separate test balances. Field gameplay
still rejects all three unreviewed seeded destinations. GPS checks are not proof
against a compromised client; public launch needs reviewed access/boundaries and
abuse controls. Beach species exist, but no real beach destination was invented.
No cash, discounts or external reward redemption is enabled.

Production rigged art, physical-device/iOS performance measurements, legendary
content/events, multiplayer/social features and admin content tools remain future
work. Server quest names, logs and errors still need full Khmer localization.
The procedural renderer is a functional temporary implementation, not final art.

Run commands, API details, rules and test configuration: `flutter_app/RPG_SETUP.md`.
Local gateway uses port 8088 because another application occupies 8080.
No public deployment was performed.
