import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anajak_travel/core/storage/app_state.dart';
import 'package:anajak_travel/shared/models/travel.dart';

void main() {
  test('money is parsed into exact minor units', () {
    expect(parseMoney('12.50'), 1250);
    expect(parseMoney('0.01'), 1);
    expect(parseMoney('123456789.99'), 12345678999);
    for (final invalid in ['0', '-1', '1.234', 'NaN', '1e3', '']) {
      expect(parseMoney(invalid), isNull);
    }
  });
  test('trip JSON round trip retains dates, money and revision', () {
    final trip = AppController.seed().trips.first;
    final copy = Trip.fromJson(
      jsonDecode(jsonEncode(trip.toJson())) as Map<String, dynamic>,
    );
    expect(copy.toJson(), trip.toJson());
    expect(copy.days, 3);
    expect(
      () => copy.activities.add(const Activity(place: 'angkor', day: 0)),
      throwsUnsupportedError,
    );
  });
  test(
    'proposal does not commit before approval and cannot apply twice',
    () async {
      final p = TripProposal(AppController.seed().trips.first);
      var commits = 0;
      expect(commits, 0);
      await p.approve((_) async {
        commits++;
      });
      expect(p.phase, ProposalPhase.completed);
      expect(commits, 1);
      await expectLater(
        p.approve((_) async {
          commits++;
        }),
        throwsStateError,
      );
      expect(commits, 1);
    },
  );
  test(
    'discarded proposals cannot be committed; failed approval can retry',
    () async {
      final p = TripProposal(AppController.seed().trips.first)..discard();
      await expectLater(p.approve((_) async {}), throwsStateError);
      final retry = TripProposal(AppController.seed().trips.first);
      await expectLater(
        retry.approve((_) async {
          throw StateError('failed');
        }),
        throwsStateError,
      );
      expect(retry.phase, ProposalPhase.failed);
      await retry.approve((_) async {});
      expect(retry.phase, ProposalPhase.completed);
    },
  );
  test(
    'local persistence survives restart and rejects stale itinerary changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
      );
      final controller = container.read(appStateProvider.notifier);
      final trip = container.read(appStateProvider).trips.first;
      await controller.updateActivities(trip.id, trip.revision, [
        ...trip.activities,
        const Activity(place: 'river', day: 0),
      ]);
      await expectLater(
        controller.updateActivities(trip.id, trip.revision, []),
        throwsStateError,
      );
      expect(container.read(appStateProvider).trips.first.activities.length, 5);
      controller.offline(true);
      await controller.addRecord(
        const TravelRecord(
          id: 'x',
          tripId: 'sample',
          kind: 'expenses',
          title: 'Lunch',
          cents: 1250,
        ),
      );
      container.dispose();
      final restored = ProviderContainer(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
      );
      expect(restored.read(appStateProvider).records.single.cents, 1250);
      expect(restored.read(appStateProvider).trips.first.activities.length, 5);
      restored.dispose();
    },
  );
}
