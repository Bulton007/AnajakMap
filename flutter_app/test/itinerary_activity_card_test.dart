import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/features/connected/itinerary_activity_card.dart';
import 'package:anajak_travel/shared/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('km');
  });

  const title = '🛕 ប្រាសាទអង្គរ · Family 👨‍👩‍👧‍👦 ❤️';
  final activity = ServerActivity.fromJson({
    'id': 'stop',
    'title': title,
    'startsAt': '2026-10-28T02:00:00Z',
    'endsAt': '2026-10-28T03:00:00Z',
    'source': 'Original travel source',
  });

  test('activity round trip retains Khmer, emoji and joined sequences', () {
    expect(ServerActivity.fromJson(activity.toDraft()).title, title);
    for (final brightness in Brightness.values) {
      expect(
        Tokens.theme(brightness).textTheme.bodyMedium?.fontFamilyFallback,
        containsAll(Tokens.emojiFallback),
      );
    }
  });

  for (final locale in ['en', 'km']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'itinerary stop fits 320dp at large text in $locale / $brightness',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.runAsync(() => Strings.delegate.load(Locale(locale)));
          var edits = 0;
          var selections = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: Tokens.theme(brightness),
              locale: Locale(locale),
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: const [
                Strings.delegate,
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
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ItineraryActivityCard(
                      activity: activity,
                      zone: 'Asia/Phnom_Penh',
                      selected: true,
                      onSelected: (_) => selections++,
                      showEdit: true,
                      onEdit: () => edits++,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(title), findsOneWidget);
          expect(find.byIcon(Icons.temple_buddhist_rounded), findsOneWidget);
          expect(find.textContaining('2026-10-28T'), findsNothing);
          expect(
            find.text('Original travel source').hitTestable(),
            findsNothing,
          );
          await tester.ensureVisible(find.byType(Checkbox));
          await tester.tap(find.byType(Checkbox));
          expect(selections, 1);
          await tester.ensureVisible(find.byType(OutlinedButton));
          await tester.tap(find.byType(OutlinedButton));
          expect(edits, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
