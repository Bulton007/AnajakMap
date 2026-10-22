import 'dart:async';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/storage/travel_database.dart';
import 'package:anajak_travel/features/connected/recommendations.dart';
import 'connected_contract_test.dart'
    show MemoryCredentials, Transport, response;

const place = {
  'id': 'osm:W:456',
  'name': 'Temple visit',
  'category': 'place_of_worship',
  'source': 'OpenStreetMap / Photon',
  'matchedInterest': 'culture',
  'latitude': 13.4,
  'longitude': 103.8,
  'references': [
    {'title': 'OpenStreetMap', 'url': 'https://www.openstreetmap.org/way/456'},
  ],
};
const matched = {
  'items': [place],
  'mode': 'preference_match',
  'aiStatus': 'not_requested',
  'query': 'temple Siem Reap',
  'retrievedAt': '2026-10-21T16:00:00Z',
};
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('km');
  });
  Future<TravelDatabase> show(
    WidgetTester tester,
    Future<ResponseBody> Function(RequestOptions) handler, {
    String locale = 'en',
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => Strings.delegate.load(Locale(locale)));
    final db = TravelDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final api = ApiClient(
      'https://example.test/api/v1/',
      MemoryCredentials(),
      transport: Dio()..httpClientAdapter = Transport(handler),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiProvider.overrideWithValue(api),
          databaseProvider.overrideWithValue(db),
          environmentProvider.overrideWithValue(
            const Environment(apiUrl: 'https://example.test/api/v1/'),
          ),
        ],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('km')],
          localizationsDelegates: const [
            Strings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: Tokens.theme(Brightness.dark),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const TripRecommendations(profile: {'id': 'account'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets(
    'real-place matches retain sources, save locally and never imply AI or trip approval',
    (tester) async {
      final requests = <Json>[];
      var writes = 0;
      final db = await show(tester, (r) async {
        if (r.path == 'guide/recommendations') {
          requests.add(object(r.data));
          return response(matched);
        }
        if (r.path == 'discovery/photos') return response({});
        if (r.method != 'GET') writes++;
        throw StateError('Unexpected ${r.path}');
      });
      await tester.ensureVisible(find.text('Find places for me'));
      await tester.tap(find.text('Find places for me'));
      await tester.pumpAndSettle();
      expect(requests.single['useAi'], false);
      expect(requests.single['interests'], ['culture']);
      expect(find.text('Temple visit'), findsOneWidget);
      expect(find.textContaining('not AI-generated'), findsOneWidget);
      await tester.ensureVisible(find.text('Sources & photo credits'));
      await tester.tap(find.text('Sources & photo credits'));
      await tester.pumpAndSettle();
      expect(find.text('OpenStreetMap'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Save place'));
      await tester.tap(find.byTooltip('Save place'));
      await tester.pumpAndSettle();
      final saved = await tester.runAsync(
        () =>
            db.cachedEntries('https://example.test/api/v1/|account', 'place:'),
      );
      expect(saved!.single['data']['id'], 'osm:W:456');
      expect(writes, 0);
    },
  );
  testWidgets(
    'stale recommendation request cannot overwrite edited destination',
    (tester) async {
      final pending = Completer<ResponseBody>();
      var calls = 0;
      await show(tester, (r) async {
        if (r.path == 'guide/recommendations') {
          calls++;
          return pending.future;
        }
        return response({});
      });
      await tester.ensureVisible(find.text('Find places for me'));
      await tester.tap(find.text('Find places for me'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Kampot');
      pending.complete(response(matched));
      await tester.pumpAndSettle();
      expect(find.text('Temple visit'), findsNothing);
      expect(calls, 1);
    },
  );
  testWidgets('AI quota fallback keeps matches and prevents early AI retry', (
    tester,
  ) async {
    await show(tester, (r) async {
      if (r.path == 'guide/recommendations') {
        return response({
          ...matched,
          if (object(r.data)['useAi'] == true) ...{
            'aiStatus': 'rate_limited',
            'retryAt': '2099-01-01T00:00:00Z',
          },
        });
      }
      return response({});
    });
    await tester.ensureVisible(find.text('Find places for me'));
    await tester.tap(find.text('Find places for me'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ask AI to choose & explain'));
    await tester.tap(find.text('Ask AI to choose & explain'));
    await tester.pumpAndSettle();
    expect(find.text('Temple visit'), findsOneWidget);
    expect(
      find.textContaining('Your place matches still work'),
      findsOneWidget,
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Ask AI to choose & explain'),
    );
    expect(button.onPressed, isNull);
  });
  testWidgets('Khmer recommendation form handles 200 percent text', (
    tester,
  ) async {
    await show(tester, (r) async => response({}), locale: 'km', scale: 2);
    expect(tester.takeException(), isNull);
  });
  test('shared accent pairs retain readable contrast in both themes', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final brightness in Brightness.values) {
      final theme = Tokens.theme(brightness);
      expect(
        contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}
