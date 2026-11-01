import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:anajak_travel/features/maps/open_map_screen.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'support/local_tiles.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:anajak_travel/features/maps/map_location.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/shared/models/map_route.dart';
import 'package:latlong2/latlong.dart';
import 'connected_contract_test.dart' show MemoryCredentials;

class TestLocation extends MapLocationAccess {
  final updates = StreamController<Position>.broadcast();
  int reads = 0, watchReads = 0;
  String? issue;
  Completer<Position>? pending;
  double latitude = 11.5, longitude = 104.9;
  Duration age = Duration.zero;
  @override
  Future<Position> current({bool requestPermission = true}) async {
    reads++;
    if (issue != null) throw MapLocationIssue(issue!);
    if (pending != null) return pending!.future;
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now().subtract(age),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Stream<Position> watch() {
    watchReads++;
    return updates.stream;
  }

  @override
  Future<bool> settings(bool service) async => true;
}

class TestRoutes extends TravelRepository {
  TestRoutes() : super(ApiClient('https://test/api/v1/', MemoryCredentials()));
  int calls = 0;
  ApiFailure? failure;
  List<double>? coordinates;
  List<Json> searchRows = const [];
  @override
  Future<List<Json>> places(
    String query, {
    int page = 0,
    CancelToken? cancel,
  }) async => searchRows;
  @override
  Future<MapRoute> route(double a, double b, double c, double d) async {
    calls++;
    coordinates = [a, b, c, d];
    if (failure != null) throw failure!;
    return MapRoute([LatLng(a, b), LatLng(c, d)], 1234, 321, 'OSRM test');
  }
}

void main() {
  Future<void> mountCurrentMap(
    WidgetTester tester,
    TestLocation location,
    TestRoutes routes, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
          mapClockProvider.overrideWithValue(tester.binding.clock.now),
          mapLocationProvider.overrideWithValue(location),
          repositoryProvider.overrideWithValue(routes),
        ],
        child: MaterialApp(
          theme: ThemeData.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: TravelOpenMap(
              navigation: true,
              places: [
                MapPlace(
                  'palace',
                  'Royal Palace with a long destination label',
                  11.5638,
                  104.9315,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'destination search pins the selected backend place and routes to it',
    (tester) async {
      final location = TestLocation();
      final routes = TestRoutes()
        ..searchRows = [
          {
            'id': 'angkor-wat',
            'name': 'Angkor Wat',
            'latitude': 13.4125,
            'longitude': 103.8670,
          },
        ];
      await mountCurrentMap(tester, location, routes);
      await tester.tap(find.byKey(const ValueKey('map-search-destination')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Angkor Wat');
      await tester.pumpAndSettle();
      expect(find.text('Angkor Wat'), findsWidgets);
      await tester.tap(find.text('Angkor Wat').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-pin-angkor-wat')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('map-route-destination')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await location.updates.close();
    },
  );

  testWidgets(
    'Directions alone obtains permission and refreshes current GPS for each route',
    (tester) async {
      final location = TestLocation();
      final routes = TestRoutes();
      await mountCurrentMap(tester, location, routes);
      expect(location.reads, 0);
      await tester.tap(find.byKey(const ValueKey('map-directions')));
      await tester.pumpAndSettle();
      expect(location.reads, 0);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(location.reads, 1);
      expect(routes.coordinates, [11.5, 104.9, 11.5638, 104.9315]);
      // Hold the second foreground fix explicitly: a route must not keep using
      // the previous point while GPS is pending, or submit twice while busy.
      location.pending = Completer<Position>();
      await tester.tap(find.byKey(const ValueKey('map-directions')));
      await tester.pump();
      expect(location.reads, 2);
      expect(routes.calls, 1);
      expect(find.byType(PolylineLayer), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('map-directions')))
            .onPressed,
        isNull,
      );
      location.pending!.complete(
        Position(
          latitude: 11.501,
          longitude: 104.901,
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
      // Map camera/tile painting is independent of whether our request finished.
      // Bound pumping on the actual backend-call state instead of global idle.
      for (var frame = 0; frame < 40 && routes.calls < 2; frame++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        routes.calls,
        2,
        reason:
            'GPS reads=${location.reads}, watches=${location.watchReads}, listener=${location.updates.hasListener}, progress=${find.byType(LinearProgressIndicator).evaluate().length}, messages=${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).where((text) => text != null).join(" | ")}',
      );
      expect(routes.coordinates, [11.501, 104.901, 11.5638, 104.9315]);
      expect(location.watchReads, 1);
      expect(location.updates.hasListener, true);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('map-directions')))
            .onPressed,
        isNotNull,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await location.updates.close();
    },
  );

  testWidgets(
    'far-away current GPS is not silently replaced by a Cambodia origin',
    (tester) async {
      final location = TestLocation()
        ..latitude = 37.422
        ..longitude = -122.084;
      final routes = TestRoutes()
        ..failure = const ApiFailure('HTTP', 'No route', status: 404);
      await mountCurrentMap(tester, location, routes);
      await tester.tap(find.byKey(const ValueKey('map-directions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(routes.coordinates, [37.422, -122.084, 11.5638, 104.9315]);
      expect(find.textContaining('No driving route connects'), findsOneWidget);
      expect(
        find.textContaining('Your GPS start is over 1,000 km'),
        findsOneWidget,
      );
      expect(find.byType(PolylineLayer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await location.updates.close();
    },
  );

  testWidgets('stale GPS cannot create driving estimates', (tester) async {
    final location = TestLocation()..age = const Duration(minutes: 5);
    final routes = TestRoutes();
    await mountCurrentMap(tester, location, routes);
    await tester.tap(find.byKey(const ValueKey('map-directions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(routes.calls, 0);
    expect(find.textContaining('Your GPS fix is old.'), findsOneWidget);
    expect(find.byType(PolylineLayer), findsNothing);
    expect(location.updates.hasListener, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await location.updates.close();
  });

  for (final size in [const Size(320, 568), const Size(600, 320)]) {
    testWidgets(
      'map controls stay scrollable and preserve map at large text $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final location = TestLocation();
        final routes = TestRoutes();
        await mountCurrentMap(tester, location, routes, scale: 2);
        await tester.ensureVisible(
          find.byKey(const ValueKey('map-directions')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('map-directions')).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.getSize(find.byType(FlutterMap)).height,
          greaterThan(100),
        );
        expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await location.updates.close();
      },
    );
  }

  Future<void> showDirections(
    WidgetTester tester,
    TestLocation location,
    TestRoutes routes,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
          mapClockProvider.overrideWithValue(tester.binding.clock.now),
          mapLocationProvider.overrideWithValue(location),
          repositoryProvider.overrideWithValue(routes),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: TravelOpenMap(
              navigation: true,
              places: [
                MapPlace('destination', 'Royal Palace', 11.5638, 104.9315),
                MapPlace('start', 'Wat Phnom', 11.576, 104.9231),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-route-origin')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wat Phnom').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Directions · Driving'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'map pins support arbitrary destinations without Explore results',
    (tester) async {
      final location = TestLocation();
      final routes = TestRoutes();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
            mapLocationProvider.overrideWithValue(location),
            repositoryProvider.overrideWithValue(routes),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TravelOpenMap(navigation: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('map-directions')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('map-pick-destination')));
      await tester.pump();
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(
        const TapPosition(Offset.zero, Offset.zero),
        const LatLng(11.57, 104.93),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Pinned destination'), findsOneWidget);
      expect(
        routes.calls,
        0,
        reason: 'Choosing a pin alone must not upload GPS or ask Gemini',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('map-directions')));
      await tester.tap(find.byKey(const ValueKey('map-directions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(routes.coordinates, [11.5, 104.9, 11.57, 104.93]);
      expect(find.byType(PolylineLayer), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await location.updates.close();
    },
  );

  testWidgets('custom start and destination can route without device location', (
    tester,
  ) async {
    final location = TestLocation()..issue = 'denied';
    final routes = TestRoutes();
    await mountCurrentMap(tester, location, routes);
    Future<void> pin(String control, LatLng point) async {
      await tester.ensureVisible(find.byKey(ValueKey(control)));
      await tester.tap(find.byKey(ValueKey(control)));
      await tester.pump();
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(
        const TapPosition(Offset.zero, Offset.zero),
        point,
      );
      await tester.pumpAndSettle();
    }

    await pin('map-pick-start', const LatLng(11.55, 104.91));
    await pin('map-pick-destination', const LatLng(11.57, 104.93));
    await tester.ensureVisible(find.byKey(const ValueKey('map-directions')));
    await tester.tap(find.byKey(const ValueKey('map-directions')));
    await tester.pumpAndSettle();
    expect(location.reads, 0);
    expect(routes.coordinates, [11.55, 104.91, 11.57, 104.93]);
    // Replacing a pin clears the confirmed route rather than showing stale data.
    await pin('map-pick-destination', const LatLng(11.58, 104.94));
    expect(find.byType(PolylineLayer), findsNothing);
    expect(routes.calls, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await location.updates.close();
  });

  testWidgets('choosing only a custom start does not invent a destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapTileFactoryProvider.overrideWithValue(LocalTiles.new)],
        child: const MaterialApp(
          home: Scaffold(body: TravelOpenMap(navigation: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('map-pick-start')));
    await tester.pump();
    tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(
      const TapPosition(Offset.zero, Offset.zero),
      const LatLng(11.55, 104.91),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('map-directions')))
          .onPressed,
      isNull,
    );
    expect(find.byType(PolylineLayer), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('place-to-place directions work without requesting GPS', (
    tester,
  ) async {
    final location = TestLocation()..issue = 'denied';
    final routes = TestRoutes();
    await showDirections(tester, location, routes);
    expect(location.reads, 0);
    expect(routes.calls, 1);
    expect(routes.coordinates, [11.576, 104.9231, 11.5638, 104.9315]);
    expect(find.byType(PolylineLayer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await location.updates.close();
  });

  testWidgets(
    'changing origin while GPS is pending cancels the old route and tracking',
    (tester) async {
      final location = TestLocation()..pending = Completer<Position>();
      final routes = TestRoutes();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
            mapLocationProvider.overrideWithValue(location),
            repositoryProvider.overrideWithValue(routes),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TravelOpenMap(
                navigation: true,
                places: [
                  MapPlace('destination', 'Royal Palace', 11.5638, 104.9315),
                  MapPlace('start', 'Wat Phnom', 11.576, 104.9231),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Directions · Driving'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(location.reads, 1);
      await tester.tap(find.byKey(const ValueKey('map-route-origin')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Wat Phnom').last);
      await tester.pump(const Duration(milliseconds: 400));
      location.pending!.complete(
        Position(
          latitude: 11.5,
          longitude: 104.9,
          timestamp: DateTime.now(),
          accuracy: 5,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(routes.calls, 0);
      expect(location.updates.hasListener, false);
      expect(find.byType(PolylineLayer), findsNothing);
      await tester.tap(find.text('Directions · Driving'));
      await tester.pumpAndSettle();
      expect(routes.calls, 1);
      expect(routes.coordinates, [11.576, 104.9231, 11.5638, 104.9315]);
      expect(location.reads, 1);
      expect(location.updates.hasListener, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await location.updates.close();
    },
  );

  testWidgets(
    'route rate limit prevents immediate retry and uses server timing',
    (tester) async {
      final location = TestLocation();
      final routes = TestRoutes()
        ..failure = const ApiFailure(
          'HTTP',
          'Busy',
          status: 429,
          retryAfterSeconds: 3,
        );
      await showDirections(tester, location, routes);
      expect(find.text('Retry in 3s'), findsOneWidget);
      expect(routes.calls, 1);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Retry in 3s'),
      );
      expect(button.onPressed, isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('Directions · Driving'), findsOneWidget);
      expect(routes.calls, 1);
      expect(find.byType(PolylineLayer), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await location.updates.close();
    },
  );

  testWidgets(
    'missing router explains backend configuration without a fake line',
    (tester) async {
      final location = TestLocation();
      final routes = TestRoutes()
        ..failure = const ApiFailure('HTTP', 'Not configured', status: 503);
      await showDirections(tester, location, routes);
      expect(
        find.text('Driving routes are not configured on this backend yet.'),
        findsOneWidget,
      );
      expect(find.byType(PolylineLayer), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await location.updates.close();
    },
  );
  test(
    'route parsing rejects fabricated/malformed geometry and preserves GeoJSON coordinate order',
    () {
      final route = MapRoute.fromJson({
        'coordinates': [
          [104.9, 11.5],
          [104.91, 11.6],
        ],
        'distanceMeters': 1234,
        'durationSeconds': 321,
      });
      expect(route.points.first.latitude, 11.5);
      expect(route.meters, 1234);
      expect(
        () => MapRoute.fromJson({
          'coordinates': [],
          'distanceMeters': 5,
          'durationSeconds': 10,
        }),
        throwsFormatException,
      );
      expect(
        () => MapRoute.fromJson({
          'coordinates': [
            [104.9, 11.5],
            [104.91, 999],
          ],
          'distanceMeters': 5,
          'durationSeconds': 10,
        }),
        throwsFormatException,
      );
    },
  );
  for (final denied in [false, true]) {
    testWidgets(
      'directions require explicit permission and stop GPS on dispose (denied=$denied)',
      (tester) async {
        final location = TestLocation()..issue = denied ? 'settings' : null;
        final routes = TestRoutes();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
              mapLocationProvider.overrideWithValue(location),
              repositoryProvider.overrideWithValue(routes),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: TravelOpenMap(
                  navigation: true,
                  places: [MapPlace('one', 'Destination', 11.6, 104.91)],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(location.reads, 0);
        await tester.tap(find.text('Directions · Driving'));
        await tester.pumpAndSettle();
        expect(location.reads, 0);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        if (denied) {
          expect(routes.calls, 0);
          expect(find.text('Open settings'), findsOneWidget);
          expect(find.byType(PolylineLayer), findsNothing);
        } else {
          expect(routes.calls, 1);
          expect(find.byType(PolylineLayer), findsOneWidget);
          expect(find.textContaining('no live traffic'), findsOneWidget);
          expect(location.updates.hasListener, true);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(location.updates.hasListener, false);
        await location.updates.close();
      },
    );
  }
  testWidgets('configured tile service and attribution are used', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
          environmentProvider.overrideWithValue(
            const Environment(
              tileUrl: 'https://tiles.example.com/{z}/{x}/{y}.png',
              tileAttribution: 'Example maps · © OpenStreetMap contributors',
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: TravelOpenMap())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate,
      'https://tiles.example.com/{z}/{x}/{y}.png',
    );
    expect(
      find.text('Example maps · © OpenStreetMap contributors'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'keyless map shows attribution and only valid interactive markers',
    (tester) async {
      MapPlace? selected;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [mapTileFactoryProvider.overrideWithValue(LocalTiles.new)],
          child: MaterialApp(
            home: Scaffold(
              body: TravelOpenMap(
                places: const [
                  MapPlace('good', 'Temple', 13.4125, 103.867),
                  MapPlace('bad', 'Invalid', 95, 200),
                ],
                onPlaceSelected: (p) => selected = p,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byTooltip('Invalid'), findsNothing);
      await tester.tap(find.byTooltip('Temple'));
      expect(selected?.id, 'good');
      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(layer.panBuffer, 0);
      expect(
        layer.urlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
