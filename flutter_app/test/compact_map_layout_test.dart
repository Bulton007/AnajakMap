import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/features/maps/open_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'support/local_tiles.dart';
import 'open_map_test.dart' show TestRoutes;

const _place = MapPlace(
  'palace',
  'Royal Palace with a long destination name · ព្រះបរមរាជវាំង',
  11.5638,
  104.9315,
);

Future<void> _mount(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String locale = 'en',
  double scale = 1,
  Brightness brightness = Brightness.light,
  TravelRepository? routes,
  Environment? environment,
  TileProvider Function()? tileFactory,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mapTileFactoryProvider.overrideWithValue(tileFactory ?? LocalTiles.new),
        if (routes != null) repositoryProvider.overrideWithValue(routes),
        if (environment != null)
          environmentProvider.overrideWithValue(environment),
      ],
      child: MaterialApp(
        theme: Tokens.theme(brightness),
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
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(
          body: TravelOpenMap(navigation: true, places: [_place]),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 320),
  ]) {
    for (final locale in ['en', 'km']) {
      for (final scale in [1.0, 2.0]) {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          testWidgets(
            'side-by-side map actions preserve viewport $size $locale $scale $brightness',
            (tester) async {
              await _mount(
                tester,
                size: size,
                locale: locale,
                scale: scale,
                brightness: brightness,
              );
              final start = tester.getRect(
                find.byKey(const ValueKey('map-pick-start')),
              );
              final destination = tester.getRect(
                find.byKey(const ValueKey('map-pick-destination')),
              );
              expect(start.top, closeTo(destination.top, .1));
              expect(start.height, closeTo(destination.height, .1));
              expect(start.right, lessThan(destination.left));
              for (final target in [start, destination]) {
                expect(target.width, greaterThanOrEqualTo(48));
                expect(target.height, greaterThanOrEqualTo(48));
                expect(target.left, greaterThanOrEqualTo(0));
                expect(target.right, lessThanOrEqualTo(size.width));
              }
              expect(
                tester.getSize(find.byType(FlutterMap)).height,
                greaterThanOrEqualTo(size.height * .6),
              );
              final directions = find.byKey(const ValueKey('map-directions'));
              await tester.ensureVisible(directions);
              await tester.pumpAndSettle();
              expect(directions.hitTestable(), findsOneWidget);
              expect(
                tester.getSize(directions).height,
                greaterThanOrEqualTo(48),
              );
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            },
          );
        }
      }
    }
  }

  testWidgets(
    'normal phone selectors share a row and directions stay visible',
    (tester) async {
      await _mount(tester, size: const Size(320, 568));
      final origin = tester.getRect(
        find.byKey(const ValueKey('map-route-origin')),
      );
      final destination = tester.getRect(
        find.byKey(const ValueKey('map-route-destination')),
      );
      expect(origin.top, closeTo(destination.top, .1));
      expect(origin.right, lessThan(destination.left));
      expect(
        find.byKey(const ValueKey('map-directions')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'destination tip anchors to its point with an accessible target',
    (tester) async {
      await _mount(tester);
      final layer = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      final destination = layer.markers.single;
      expect(destination.point, const LatLng(11.5638, 104.9315));
      expect(destination.alignment, Alignment.topCenter);
      expect(destination.width, greaterThanOrEqualTo(48));
      expect(destination.height, greaterThanOrEqualTo(48));
      expect(find.byKey(const ValueKey('map-pin-palace')), findsOneWidget);
      expect(find.byTooltip(_place.name), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('map-pick-start')));
      await tester.pump();
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(
        const TapPosition(Offset.zero, Offset.zero),
        const LatLng(11.564, 104.931),
      );
      await tester.pumpAndSettle();
      final updated = tester.widget<MarkerLayer>(find.byType(MarkerLayer));
      final start = updated.markers.firstWhere(
        (marker) => marker.point == const LatLng(11.564, 104.931),
      );
      expect(start.alignment, Alignment.center);
      expect(find.byTooltip('Pinned start'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'map styles keep route, camera and configured standard provider',
    (tester) async {
      final routes = TestRoutes();
      var providersCreated = 0;
      await _mount(
        tester,
        routes: routes,
        environment: const Environment(
          tileUrl: 'https://example.test/tiles/{z}/{x}/{y}.png',
          tileAttribution: 'Example maps · © OpenStreetMap contributors',
        ),
        tileFactory: () {
          providersCreated++;
          return LocalTiles();
        },
      );
      await tester.tap(find.byKey(const ValueKey('map-pick-start')));
      await tester.pump();
      expect(find.byKey(const ValueKey('map-layer-toggle')), findsNothing);
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onTap!(
        const TapPosition(Offset.zero, Offset.zero),
        const LatLng(11.564, 104.931),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('map-directions')));
      await tester.tap(find.byKey(const ValueKey('map-directions')));
      await tester.pumpAndSettle();
      expect(routes.calls, 1);
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final center = controller.camera.center;
      final zoom = controller.camera.zoom;

      Future<void> choose(String layer) async {
        await tester.tap(find.byKey(const ValueKey('map-layer-toggle')));
        await tester.pumpAndSettle();
        final option = find.byKey(ValueKey('map-layer-$layer'));
        await tester.ensureVisible(option);
        await tester.tap(option);
        await tester.pumpAndSettle();
      }

      await choose('terrain');
      var tiles = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(
        tiles.urlTemplate,
        'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
      );
      expect(tiles.maxNativeZoom, 17);
      expect(find.textContaining('© OpenTopoMap'), findsOneWidget);
      expect(providersCreated, 2);
      expect(routes.calls, 1);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(controller.camera.center, center);
      expect(controller.camera.zoom, zoom);

      await choose('biking');
      tiles = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tiles.urlTemplate, contains('tile-cyclosm.openstreetmap.fr'));
      expect(find.textContaining('© CyclOSM'), findsOneWidget);
      expect(providersCreated, 3);
      expect(routes.calls, 1);
      expect(controller.camera.center, center);
      expect(controller.camera.zoom, zoom);

      await choose('traffic');
      expect(
        find.byKey(const ValueKey('map-layer-unavailable')),
        findsOneWidget,
      );
      expect(providersCreated, 3);
      expect(routes.calls, 1);
      await tester.tap(find.byKey(const ValueKey('map-layer-close')));
      await tester.pumpAndSettle();
      await choose('standard');
      tiles = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tiles.urlTemplate, 'https://example.test/tiles/{z}/{x}/{y}.png');
      expect(
        find.text('Example maps · © OpenStreetMap contributors'),
        findsOneWidget,
      );
      expect(providersCreated, 4);
      expect(routes.calls, 1);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(controller.camera.center, center);
      expect(controller.camera.zoom, zoom);
      expect(tester.takeException(), isNull);
    },
  );
}
