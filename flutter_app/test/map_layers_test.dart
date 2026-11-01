import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/features/maps/map_layers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

List<MapLayerDefinition> layers() => buildMapLayerDefinitions(
  standardUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  standardAttribution: '© OpenStreetMap contributors',
);

Widget app({
  required Widget child,
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('km')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: Tokens.theme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

void main() {
  test('only styles with genuine HTTPS tiles and credits are available', () {
    final definitions = layers();
    expect(
      definitions.where((layer) => layer.available).map((layer) => layer.id),
      [MapLayerId.standard, MapLayerId.terrain, MapLayerId.biking],
    );
    expect(definitions[1].maxNativeZoom, 17);
    expect(definitions.last.maxNativeZoom, 19);
    expect(definitions[1].attribution, contains('SRTM'));
    expect(definitions.last.attribution, contains('CyclOSM'));
    expect(
      const MapLayerDefinition(
        id: MapLayerId.terrain,
        tileUrl: 'http://tiles.example/{z}/{x}/{y}.png',
        attribution: 'Test',
      ).available,
      false,
    );
    expect(
      const MapLayerDefinition(
        id: MapLayerId.terrain,
        tileUrl: 'https://tiles.example/{z}/{x}/{y}.png',
      ).available,
      false,
    );
    expect(
      const MapLayerDefinition(
        id: MapLayerId.terrain,
        tileUrl: 'https://user:password@tiles.example/{z}/{x}/{y}.png',
        attribution: 'Test',
      ).available,
      false,
    );
    expect(
      const MapLayerDefinition(
        id: MapLayerId.terrain,
        tileUrl: 'https://tiles.example/{z}/{x}/missing-y.png',
        attribution: 'Test',
      ).available,
      false,
    );
  });

  testWidgets('available style returns actual provider and attribution', (
    tester,
  ) async {
    MapLayerDefinition? selected;
    await tester.pumpWidget(
      app(
        child: MapLayerTray(
          layers: layers(),
          selected: MapLayerId.standard,
          onSelected: (layer) => selected = layer,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('map-layer-terrain')));
    expect(selected?.id, MapLayerId.terrain);
    expect(selected?.tileUrl, contains('tile.opentopomap.org'));
    expect(selected?.attribution, contains('OpenTopoMap'));
    expect(selected?.attributionUrl, 'https://opentopomap.org/about');
    expect(tester.takeException(), isNull);
  });

  testWidgets('traffic and transit explain absence without selecting a layer', (
    tester,
  ) async {
    var selections = 0;
    await tester.pumpWidget(
      app(
        child: MapLayerTray(
          layers: layers(),
          selected: MapLayerId.standard,
          onSelected: (_) => selections++,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('map-layer-traffic')));
    await tester.pump();
    expect(
      find.textContaining('Live traffic is not available.'),
      findsOneWidget,
    );
    expect(selections, 0);
    await tester.tap(find.byKey(const ValueKey('map-layer-transit')));
    await tester.pump();
    expect(
      find.textContaining('Transit maps are not available.'),
      findsOneWidget,
    );
    expect(selections, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screen readers can activate available and unavailable styles', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    try {
      MapLayerDefinition? selected;
      await tester.pumpWidget(
        app(
          child: MapLayerTray(
            layers: layers(),
            selected: MapLayerId.standard,
            onSelected: (layer) => selected = layer,
          ),
        ),
      );
      final terrain = tester.getSemantics(find.bySemanticsLabel('Terrain'));
      expect(terrain.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      terrain.owner!.performAction(terrain.id, SemanticsAction.tap);
      await tester.pump();
      expect(selected?.id, MapLayerId.terrain);
      final traffic = tester.getSemantics(
        find.bySemanticsLabel('Traffic, Unavailable'),
      );
      expect(traffic.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      traffic.owner!.performAction(traffic.id, SemanticsAction.tap);
      await tester.pump();
      expect(selected?.id, MapLayerId.terrain);
      expect(
        find.textContaining('Live traffic is not available.'),
        findsOneWidget,
      );
    } finally {
      semanticsHandle.dispose();
    }
  });

  testWidgets('floating button opens picker and returns selected style', (
    tester,
  ) async {
    MapLayerDefinition? selected;
    await tester.pumpWidget(
      app(
        child: Builder(
          builder: (context) => MapLayersButton(
            onPressed: () async {
              selected = await showMapLayerPicker(
                context,
                layers: layers(),
                selected: MapLayerId.standard,
              );
            },
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('map-layer-toggle'))),
      const Size(48, 48),
    );
    await tester.tap(find.byKey(const ValueKey('map-layer-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('map-layer-tray')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('map-layer-terrain')));
    await tester.pumpAndSettle();
    expect(selected?.id, MapLayerId.terrain);
    expect(find.byKey(const ValueKey('map-layer-tray')), findsNothing);
  });

  testWidgets('More shows real active provider credits', (tester) async {
    await tester.pumpWidget(
      app(
        child: MapLayerTray(layers: layers(), selected: MapLayerId.standard),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('map-layer-more')));
    await tester.tap(find.byKey(const ValueKey('map-layer-more')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('not the calculated driving route'),
      findsOneWidget,
    );
    expect(find.textContaining('© CyclOSM'), findsOneWidget);
    expect(find.textContaining('SRTM'), findsOneWidget);
  });

  for (final locale in [const Locale('en'), const Locale('km')]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        '320px ${locale.languageCode} ${brightness.name} large text remains usable',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          MapLayerDefinition? selected;
          await tester.pumpWidget(
            app(
              locale: locale,
              brightness: brightness,
              scale: 2.5,
              child: MapLayerTray(
                layers: layers(),
                selected: MapLayerId.standard,
                onSelected: (layer) => selected = layer,
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final terrain = find.byKey(const ValueKey('map-layer-terrain'));
          await tester.ensureVisible(terrain);
          await tester.tap(terrain);
          await tester.pump();
          expect(selected?.id, MapLayerId.terrain);
          expect(tester.getSize(terrain).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(terrain).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
