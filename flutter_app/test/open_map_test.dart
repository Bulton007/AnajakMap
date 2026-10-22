import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:anajak_travel/features/maps/open_map_screen.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'support/local_tiles.dart';

void main() {
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
