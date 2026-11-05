import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/features/maps/map_location.dart';
import 'package:anajak_travel/features/maps/open_map_screen.dart';
import 'package:anajak_travel/features/rpg/adventure_controller.dart';
import 'package:anajak_travel/features/rpg/journey_controller.dart';
import 'package:anajak_travel/features/rpg/journey_screen.dart';
import 'adventure_test.dart' show AdventureFixture;
import 'support/local_tiles.dart';

Position fix(DateTime time, {bool mocked = false, double accuracy = 10}) =>
    Position(
      latitude: 11.55,
      longitude: 104.92,
      timestamp: time,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
      isMocked: mocked,
    );

class JourneyLocation implements MapLocationAccess {
  Position position = fix(DateTime.now().subtract(const Duration(seconds: 20)));
  bool denied = false;
  @override
  Future<Position> current({bool requestPermission = true}) async {
    if (denied) throw const MapLocationIssue('denied');
    return position;
  }

  @override
  Stream<Position> watch() => const Stream.empty();
  @override
  Future<bool> settings(bool service) async => true;
}

class JourneyFixture extends AdventureFixture {
  bool ended = false;
  final saved = <Json>[];
  @override
  Future<Json> journey() async => {};
  Json view() => {
    'journey': {
      'ID': 'real-journey',
      'ENDED_AT': ended ? DateTime.now().toIso8601String() : null,
      'DISTANCE_M': 0,
    },
    'points': saved,
  };
  @override
  Future<List<Json>> world(String realm) async => saved.length < 2
      ? []
      : [
          {
            'ID': 'visited-1',
            'NAME': 'Journey stop',
            'LATITUDE': 11.55,
            'LONGITUDE': 104.92,
            'VISITED': 1,
          },
        ];
  @override
  Future<Json> mutate(String path, Json body, String key) async {
    calls.add((path, body, key));
    if (path == 'journey/start') return view();
    if (path.endsWith('/stop')) {
      ended = true;
      return view();
    }
    saved.add(body);
    return {
      'accepted': true,
      'distanceM': 0,
      if (saved.length >= 2) 'destinationId': 'visited-1',
    };
  }
}

Future<void> flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test(
    'journey uploads actual fixes, discovers a stop, pauses and ends',
    () async {
      final repo = JourneyFixture(), location = JourneyLocation();
      final stream = StreamController<Position>.broadcast();
      addTearDown(stream.close);
      final container = ProviderContainer(
        overrides: [
          adventureRepositoryProvider.overrideWithValue(repo),
          gpsLocationProvider.overrideWithValue(location),
          journeyPositionStreamProvider.overrideWithValue(() => stream.stream),
        ],
      );
      addTearDown(container.dispose);
      final provider = journeyProvider('alice');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await flush();
      final controller = container.read(provider.notifier);
      await controller.start();
      expect(container.read(provider).tracking, isTrue);
      expect(repo.saved.single['latitude'], 11.55);
      stream.add(fix(DateTime.now()));
      await flush();
      expect(container.read(provider).destinationId, 'visited-1');
      expect(container.read(provider).points, hasLength(2));
      controller.pause();
      expect(stream.hasListener, isFalse);
      final count = repo.calls.length;
      stream.add(fix(DateTime.now().add(const Duration(seconds: 1))));
      await flush();
      expect(repo.calls.length, count);
      await controller.stop();
      expect(container.read(provider).active, isFalse);
      expect(repo.calls.last.$1, 'journey/real-journey/stop');
      expect(repo.calls.map((c) => c.$3).toSet().length, repo.calls.length);
    },
  );
  for (final issue in ['denied', 'mocked', 'accuracy']) {
    test('journey does not start or upload with $issue GPS', () async {
      final repo = JourneyFixture(), location = JourneyLocation();
      location.denied = issue == 'denied';
      location.position = fix(
        DateTime.now(),
        mocked: issue == 'mocked',
        accuracy: issue == 'accuracy' ? 100 : 10,
      );
      final container = ProviderContainer(
        overrides: [
          adventureRepositoryProvider.overrideWithValue(repo),
          gpsLocationProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);
      final provider = journeyProvider('alice');
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await flush();
      await container.read(provider.notifier).start();
      expect(repo.calls, isEmpty);
      expect(container.read(provider).issue, issue);
      expect(container.read(provider).tracking, isFalse);
    });
  }
  test(
    'journey route does not bridge tracking gaps or invalid coordinates',
    () {
      final now = DateTime.now();
      Json p(int seconds) => {
        'latitude': 11.55,
        'longitude': 104.92,
        'measuredAt': now.add(Duration(seconds: seconds)).toIso8601String(),
      };
      expect(
        journeyRouteSegments([
          p(0),
          p(15),
          p(120),
          p(135),
        ]).map((s) => s.length),
        [2, 2],
      );
      expect(journeyCoordinate({'latitude': 91, 'longitude': 0}), isNull);
      expect(journeyCoordinate({}), isNull);
    },
  );
  for (final locale in ['en', 'km']) {
    testWidgets(
      'journey $locale fits a narrow phone with large text and pauses in background',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = JourneyFixture(), location = JourneyLocation();
        final stream = StreamController<Position>.broadcast();
        addTearDown(stream.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              adventureRepositoryProvider.overrideWithValue(repo),
              gpsLocationProvider.overrideWithValue(location),
              journeyPositionStreamProvider.overrideWithValue(
                () => stream.stream,
              ),
              mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
            ],
            child: MaterialApp(
              theme: Tokens.theme(Brightness.light),
              locale: Locale(locale),
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const JourneyScreen(account: 'alice'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final start = find.byKey(const Key('journey-track'));
        await tester.ensureVisible(start);
        await tester.tap(start);
        await tester.pumpAndSettle();
        expect(stream.hasListener, isTrue);
        expect(tester.takeException(), isNull);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        expect(stream.hasListener, isTrue);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(stream.hasListener, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(stream.hasListener, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
