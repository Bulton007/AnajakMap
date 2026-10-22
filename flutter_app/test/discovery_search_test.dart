import 'dart:async';
import 'package:intl/date_symbol_data_local.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/features/connected/connected_explore.dart';
import 'package:anajak_travel/features/maps/search_results.dart';
import 'package:anajak_travel/shared/formatting/travel_dates.dart';
import 'connected_contract_test.dart'
    show MemoryCredentials, Transport, response;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('km');
  });
  test('trip dates convert UTC into destination time including DST', () {
    expect(
      travelTimeRange(
        '2026-10-17T02:00:00.000+00:00',
        '2026-10-17T03:00:00.000+00:00',
      ),
      contains('9:00'),
    );
    expect(tripTime('2026-07-01T12:00:00Z', 'America/New_York')!.hour, 8);
    expect(tripTime('2026-01-01T12:00:00Z', 'America/New_York')!.hour, 7);
    expect(travelDate('bad'), '—');
    expect(travelDateRange('2026-10-17', '2026-10-17'), 'Oct 17, 2026');
  });
  testWidgets(
    'editing clears stale results and map, late responses cannot replace newer search',
    (tester) async {
      await tester.runAsync(() => Strings.delegate.load(const Locale('en')));
      final pending = Completer<ResponseBody>();
      final oldPhotos = Completer<ResponseBody>();
      final api = ApiClient(
        'https://example.test/api/v1/',
        MemoryCredentials(),
        transport: Dio()
          ..httpClientAdapter = Transport((r) async {
            if (r.path == 'discovery/photos') {
              if (r.queryParameters['query'] == 'Phnom Penh') {
                return oldPhotos.future;
              }
              return response({});
            }
            if (r.queryParameters['query'] == 'Kampot') return pending.future;
            return response([
              {
                'id': 'place',
                'name': r.queryParameters['query'] == 'Siem Reap'
                    ? 'Angkor'
                    : 'Royal Palace',
                'latitude': 11.5,
                'longitude': 104.9,
              },
            ]);
          }),
      );
      final container = ProviderContainer(
        overrides: [apiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: const [Strings.delegate],
            home: const Scaffold(
              body: ConnectedExplore(profile: {'id': 'test'}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Royal Palace'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Kampot');
      await tester.pump();
      expect(find.text('Royal Palace'), findsNothing);
      expect(container.read(searchResultsProvider), isEmpty);
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Siem Reap');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(find.text('Angkor'), findsOneWidget);
      pending.complete(
        response([
          {'id': 'late', 'name': 'Kampot'},
        ]),
      );
      oldPhotos.complete(
        response({
          'place': {'url': 'https://upload.wikimedia.org/old-place.jpg'},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Angkor'), findsOneWidget);
      expect(container.read(searchResultsProvider).single['name'], 'Angkor');
      expect(container.read(searchResultsProvider).single['photo'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
