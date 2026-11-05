import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/features/authentication/auth_controller.dart';
import 'package:anajak_travel/features/rpg/adventure_controller.dart';
import 'package:anajak_travel/features/rpg/adventure_repository.dart';
import 'package:anajak_travel/features/rpg/adventure_screen.dart';
import 'adventure_test.dart' show AdventureFixture, SignedIn, session;

class EntryFixture extends AdventureFixture {
  bool practiceEnabled = true;
  bool fieldUnavailable = false;
  bool reviewed = false;
  DateTime? nextEncounter;
  @override
  Future<Json> capabilities() async => {'practiceEnabled': practiceEnabled};
  @override
  Future<List<Json>> world(String realm) async {
    if (realm == 'field' && fieldUnavailable) {
      throw const ApiFailure(
        'UNAVAILABLE',
        'Field world unavailable',
        status: 503,
      );
    }
    return [
      for (final destination in await super.world(realm))
        {
          ...destination,
          if (reviewed) 'APPROVED': 1,
          if (reviewed) 'ACCESSIBLE': 1,
        },
    ];
  }

  @override
  Future<AdventureSnapshot> profile(String realm) async {
    final current = await super.profile(realm);
    return AdventureSnapshot({
      ...current.data,
      'profile': {
        ...current.profile,
        if (nextEncounter != null)
          'NEXT_ENCOUNTER': nextEncounter!.toUtc().toIso8601String(),
      },
    });
  }
}

Future<void> openAdventure(
  WidgetTester tester,
  EntryFixture repo, {
  Future<Json> Function()? location,
  bool practiceTools = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(SignedIn.new),
        adventureRepositoryProvider.overrideWithValue(repo),
        if (location != null)
          adventureLocationProvider.overrideWithValue(location),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: AdventureScreen(practiceTools: practiceTools),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('field play never sends an encounter when GPS is unavailable', () async {
    final repo = EntryFixture()..reviewed = true;
    final container = ProviderContainer(
      overrides: [
        adventureRepositoryProvider.overrideWithValue(repo),
        adventureLocationProvider.overrideWithValue(() async {
          throw const ApiFailure('GPS', 'Location permission denied');
        }),
      ],
    );
    addTearDown(container.dispose);
    final field = adventureProvider(('alice', 'field'));
    final subscription = container.listen(field, (_, _) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero);
    await container.read(field.notifier).start('palace', 'owned-1', true);
    expect(repo.calls, isEmpty);
    expect(container.read(field).failure?.code, 'GPS');
    expect(container.read(field).pending, isFalse);
  });

  testWidgets(
    'normal play never promotes practice or enables fixture encounters',
    (tester) async {
      final repo = EntryFixture();
      await openAdventure(tester, repo, practiceTools: false);
      expect(find.text('Your adventure'), findsOneWidget);
      expect(find.textContaining('Start a journey'), findsOneWidget);
      expect(find.byKey(const Key('adventure-play-practice')), findsNothing);
      expect(find.text('Server practice'), findsNothing);
      expect(find.text('Royal Palace'), findsNothing);
      final map = find.widgetWithText(OutlinedButton, 'Choose on map');
      expect(tester.widget<OutlinedButton>(map).onPressed, isNull);
      final start = find.byKey(const Key('adventure-start-encounter'));
      await tester.ensureVisible(start);
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      expect(repo.calls, isEmpty);
    },
  );

  testWidgets('real play uses field endpoint and measured GPS', (tester) async {
    final repo = EntryFixture()..reviewed = true;
    final measured = <String, dynamic>{
      'latitude': 11.5638,
      'longitude': 104.9315,
      'accuracy': 10,
      'mocked': false,
      'measuredAt': DateTime.now().toUtc().toIso8601String(),
    };
    var gpsRequests = 0;
    await openAdventure(
      tester,
      repo,
      practiceTools: false,
      location: () async {
        gpsRequests++;
        return measured;
      },
    );
    await tester.tap(find.byKey(const Key('adventure-choose-destination')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Royal Palace'));
    await tester.tap(find.text('Royal Palace'));
    await tester.pumpAndSettle();
    final consent = find.byKey(const Key('adventure-safety-consent'));
    await tester.ensureVisible(consent);
    await tester.tap(
      find.descendant(of: consent, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    final start = find.byKey(const Key('adventure-start-encounter'));
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(gpsRequests, 1);
    expect(repo.calls.single.$1, 'field/encounters');
    expect(repo.calls.single.$2['location'], measured);
  });

  test(
    'a failed field load retains configured practice availability',
    () async {
      final repo = EntryFixture()..fieldUnavailable = true;
      final container = ProviderContainer(
        overrides: [adventureRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final field = adventureProvider(('alice', 'field'));
      final subscription = container.listen(field, (_, _) {});
      addTearDown(subscription.close);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(field).failure, isNotNull);
      expect(container.read(field).capabilities['practiceEnabled'], isTrue);
    },
  );

  test(
    'server cooldown blocks another encounter without blocking battle actions',
    () async {
      final repo = EntryFixture()
        ..nextEncounter = DateTime.now().add(const Duration(minutes: 5));
      final container = ProviderContainer(
        overrides: [adventureRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final practice = adventureProvider(('alice', 'practice'));
      final subscription = container.listen(practice, (_, _) {});
      addTearDown(subscription.close);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(practice).canAct, isTrue);
      expect(container.read(practice).canStart, isFalse);
      await container.read(practice.notifier).start('palace', 'owned-1', true);
      expect(repo.calls, isEmpty);
      repo.active = session();
      await container.read(practice.notifier).load();
      await container.read(practice.notifier).move('capture');
      expect(repo.calls.single.$2['move'], 'capture');
    },
  );

  testWidgets(
    'practice launch reveals the confirmed battle without GPS or repeated jumps',
    (tester) async {
      final repo = EntryFixture();
      var gpsRequests = 0;
      await openAdventure(
        tester,
        repo,
        location: () async {
          gpsRequests++;
          throw const ApiFailure('GPS', 'Not requested during practice');
        },
      );
      final launch = find.byKey(const Key('adventure-play-practice'));
      await tester.ensureVisible(launch);
      await tester.tap(launch);
      await tester.pumpAndSettle();
      final consent = find.byKey(const Key('adventure-safety-consent'));
      final checkbox = find.descendant(
        of: consent,
        matching: find.byType(Checkbox),
      );
      await tester.scrollUntilVisible(
        checkbox.hitTestable(),
        200,
        maxScrolls: 40,
      );
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      final start = find.byKey(const Key('adventure-start-encounter'));
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(repo.calls.single.$1, 'practice/encounters');
      expect(repo.calls.single.$2['destinationId'], 'palace');
      expect(repo.calls.single.$2['monsterId'], 'owned-1');
      expect(repo.calls.single.$2['location'], isNull);
      expect(gpsRequests, 0);
      // Starting from the destination controls must reveal the battle above
      // them without another user scroll, including an actionable first move.
      expect(
        find.widgetWithText(OutlinedButton, 'Strike').hitTestable(),
        findsOneWidget,
      );
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      final offset = scroll.position.pixels;
      final current = repo.active!;
      final battle = object(current['battle']);
      repo.active = {
        ...current,
        'revision': 1,
        'battle': {
          ...battle,
          'enemy': {...object(battle['enemy']), 'hp': 20},
        },
      };
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AdventureScreen)),
      );
      await container
          .read(adventureProvider(('alice', 'practice')).notifier)
          .load();
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, closeTo(offset, .1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unconfigured server practice offers explicitly separate device play',
    (tester) async {
      final repo = EntryFixture()..practiceEnabled = false;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const AdventureScreen(practiceTools: true),
          ),
          GoRoute(
            path: '/rpg',
            builder: (_, _) =>
                const Scaffold(body: Text('Separate device practice')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(SignedIn.new),
            adventureRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('never becomes an account reward'),
        findsOneWidget,
      );
      final launch = find.byKey(const Key('adventure-play-practice'));
      await tester.ensureVisible(launch);
      await tester.tap(launch);
      await tester.pumpAndSettle();
      expect(find.text('Separate device practice'), findsOneWidget);
      expect(repo.calls, isEmpty);
    },
  );

  test(
    'completed encounter can be dismissed without changing confirmed progress',
    () async {
      final repo = EntryFixture()..active = session();
      final container = ProviderContainer(
        overrides: [adventureRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      final practice = adventureProvider(('alice', 'practice'));
      final subscription = container.listen(practice, (_, _) {});
      addTearDown(subscription.close);
      await Future<void>.delayed(Duration.zero);
      final controller = container.read(practice.notifier);
      controller.dismissCompletedEncounter();
      expect(container.read(practice).active, isTrue);
      await controller.move('capture');
      final confirmed = container.read(practice).snapshot;
      controller.dismissCompletedEncounter();
      expect(container.read(practice).session, isNull);
      expect(container.read(practice).snapshot, same(confirmed));
      expect(repo.calls, hasLength(1));
    },
  );
}
