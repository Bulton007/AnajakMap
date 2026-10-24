import 'package:flutter/material.dart';
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
  int reads = 0;
  String? issue;
  @override
  Future<Position> current({bool requestPermission = true}) async {
    reads++;
    if (issue != null) throw MapLocationIssue(issue!);
    return Position(
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
    );
  }

  @override
  Stream<Position> watch() => updates.stream;
  @override
  Future<bool> settings(bool service) async => true;
}

class TestRoutes extends TravelRepository {
  TestRoutes() : super(ApiClient('https://test/api/v1/', MemoryCredentials()));
  int calls = 0;
  @override
  Future<MapRoute> route(double a, double b, double c, double d) async {
    calls++;
    return MapRoute([LatLng(a, b), LatLng(c, d)], 1234, 321, 'OSRM test');
  }
}

void main() {
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
