import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/features/rpg/encounter_policy.dart';
import 'package:anajak_travel/features/rpg/adventure_controller.dart';

void main() {
  test(
    'seeded rolls, eligibility and cooldown prevent GPS event duplication',
    () {
      final a = EncounterPolicy(random: Random(7));
      final b = EncounterPolicy(random: Random(7));
      final now = DateTime.utc(2026, 10, 24);
      expect(a.roll(now, eligible: false), isFalse);
      for (var i = 0; i < 20; i++) {
        final time = now.add(Duration(minutes: i * 5));
        expect(a.roll(time, eligible: true), b.roll(time, eligible: true));
        expect(a.roll(time, eligible: true), isFalse);
      }
    },
  );
  test(
    'invalid policies are rejected and boundary probability is deterministic',
    () {
      expect(
        () => EncounterPolicy(probability: double.nan),
        throwsArgumentError,
      );
      expect(
        EncounterPolicy(probability: 0).roll(DateTime.now(), eligible: true),
        isFalse,
      );
      expect(
        EncounterPolicy(probability: 1).roll(DateTime.now(), eligible: true),
        isTrue,
      );
    },
  );
  test(
    'server absolute expiry is safe at boundary, across resume, and when malformed',
    () {
      const state = AdventureState(
        session: {'status': 'active', 'expiresAt': '2026-10-24T09:00:00Z'},
      );
      expect(state.expiredAt(DateTime.parse('2026-10-24T08:59:59Z')), isFalse);
      expect(state.expiredAt(DateTime.parse('2026-10-24T09:00:00Z')), isTrue);
      expect(state.expiredAt(DateTime.parse('2026-10-24T11:00:00Z')), isTrue);
      expect(
        const AdventureState(session: {'status': 'active'}).canAct,
        isFalse,
      );
      expect(const AdventureState(session: {'status': 'won'}).expired, isFalse);
    },
  );
}
