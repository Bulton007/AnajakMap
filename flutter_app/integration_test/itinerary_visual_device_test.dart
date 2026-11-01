import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/features/connected/itinerary_activity_card.dart';
import 'package:anajak_travel/shared/models/server_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// This entry point never launches the app's repository, auth or database.
/// All displayed content is synthetic, and no trip/account changes are made.
Future<void> main() async {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('en');
  await initializeDateFormatting('km');

  testWidgets('native itinerary emoji, Khmer and themes', (tester) async {
    var converted = false;
    for (final locale in ['en', 'km']) {
      for (final brightness in Brightness.values) {
        final title = locale == 'km'
            ? '🛕 ប្រាសាទអង្គរវត្ត · 👨‍👩‍👧‍👦'
            : '🛕 Angkor Wat · 👨‍👩‍👧‍👦';
        final activity = ServerActivity.fromJson({
          'id': 'synthetic-visual-stop',
          'title': title,
          'startsAt': '2026-10-28T02:00:00Z',
          'endsAt': '2026-10-28T03:00:00Z',
          'source': '',
        });
        var edits = 0;
        var selections = 0;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey('$locale-${brightness.name}'),
            debugShowCheckedModeBanner: false,
            theme: Tokens.theme(brightness),
            locale: Locale(locale),
            supportedLocales: const [Locale('en'), Locale('km')],
            localizationsDelegates: const [
              Strings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(
              appBar: AppBar(
                title: Text(locale == 'km' ? 'ផែនការដំណើរ' : 'Itinerary'),
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          locale == 'km'
                              ? 'សាកល្បងរូបភាព · គ្មានការផ្ញើទិន្នន័យ'
                              : 'Visual test · synthetic content only',
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '🛕 🌿 🍜 ❤️ 👨‍👩‍👧‍👦',
                          key: const ValueKey('native-emoji-sample'),
                          style: Tokens.theme(brightness)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 20),
                        ItineraryActivityCard(
                          activity: activity,
                          zone: 'Asia/Phnom_Penh',
                          selected: true,
                          onSelected: (_) => selections++,
                          showEdit: true,
                          onEdit: () => edits++,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(
          Theme.of(tester.element(find.text(title)))
              .textTheme
              .bodyMedium
              ?.fontFamilyFallback,
          containsAll(Tokens.emojiFallback),
        );
        expect(find.byIcon(Icons.temple_buddhist_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (!converted) {
          await binding.convertFlutterSurfaceToImage();
          converted = true;
        }
        await tester.pumpAndSettle();
        final bytes = await binding.takeScreenshot(
          'itinerary-$locale-${brightness.name}',
        );
        expect(bytes, isNotEmpty);
        await tester.ensureVisible(find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        expect(selections, 1);
        await tester.ensureVisible(find.byType(OutlinedButton));
        await tester.tap(find.byType(OutlinedButton));
        expect(edits, 1);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
