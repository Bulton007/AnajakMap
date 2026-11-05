import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/features/maps/open_map_screen.dart';
import 'package:anajak_travel/features/maps/show_on_map.dart';
import 'package:anajak_travel/features/maps/search_results.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/local_tiles.dart';

void main() {
  test('map entry rejects missing and invalid coordinates', () {
    expect(exploredMapPlace({'name': 'Missing'}), isNull);
    expect(
      exploredMapPlace({'latitude': double.nan, 'longitude': 104.9}),
      isNull,
    );
    expect(exploredMapPlace({'latitude': 91, 'longitude': 104.9}), isNull);
    expect(
      exploredMapPlace({'latitude': '11.57', 'longitude': '104.92'})?.valid,
      isTrue,
    );
  });

  for (final locale in ['en', 'km']) {
    testWidgets(
      'Explore opens selected coordinates in the in-app map in $locale',
      (tester) async {
        const place = {
          'id': 'market',
          'name': 'Central Market',
          'latitude': 11.57,
          'longitude': 104.92,
        };
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: ShowOnMap(place: place)),
            ),
            GoRoute(
              path: '/map',
              builder: (_, state) =>
                  OpenMapScreen(selectedPlace: state.extra as MapPlace),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
            ],
            child: MaterialApp.router(
              routerConfig: router,
              locale: Locale(locale),
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: const [
                Strings.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        ProviderScope.containerOf(
          tester.element(find.byType(ShowOnMap)),
        ).read(searchResultsProvider.notifier).replace([
          {
            'id': 'other',
            'name': 'Other result',
            'latitude': 12.1,
            'longitude': 105.0,
          },
        ]);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
        expect(map.options.initialCenter.latitude, 11.57);
        expect(map.options.initialCenter.longitude, 104.92);
        expect(find.byTooltip('Central Market'), findsOneWidget);
        expect(find.byKey(const ValueKey('map-directions')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
