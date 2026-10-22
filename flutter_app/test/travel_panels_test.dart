import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/shared/components/travel_panels.dart';
import 'package:anajak_travel/features/connected/offline_trip_cards.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('km');
  });
  Future<void> show(
    WidgetTester tester,
    Widget child, {
    String locale = 'en',
    double scale = 1,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => Strings.delegate.load(Locale(locale)));
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(locale),
        supportedLocales: const [Locale('en'), Locale('km')],
        localizationsDelegates: const [
          Strings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(brightness: brightness),
        builder: (context, body) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: body!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(24), child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'photo hero fills the card width and failure offers a readable explanation',
    (tester) async {
      await show(
        tester,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TravelHero(title: 'Short', subtitle: 'Cambodia'),
            GenerationStatusPanel(
              status: 'FAILED',
              failureCode: 'AI_RATE_LIMITED',
              retryAt: '2026-10-22T08:00:00Z',
            ),
          ],
        ),
      );
      expect(tester.getSize(find.byType(TravelHero)).width, 312);
      expect(find.textContaining('usage limit'), findsOneWidget);
      expect(
        find.text('Your trip is safe. No changes were saved.'),
        findsOneWidget,
      );
      expect(find.textContaining('Oct 22, 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'calendar presents Oracle fields as readable times without database IDs or coordinates',
    (tester) async {
      await show(
        tester,
        const CalendarPanel(
          zone: 'Asia/Phnom_Penh',
          data: {
            'events': [],
            'activities': [
              {
                'ID': 'internal-892hiubiu',
                'TITLE': 'Royal Palace',
                'STARTS_AT': '2026-10-17T02:00:00Z',
                'ENDS_AT': '2026-10-17T03:00:00Z',
                'LATITUDE': 11.5638,
                'SOURCE': 'Development fixture',
              },
            ],
          },
        ),
      );
      expect(find.text('Royal Palace'), findsOneWidget);
      expect(find.textContaining('9:00'), findsOneWidget);
      expect(find.textContaining('892hiubiu'), findsNothing);
      expect(find.textContaining('11.5638'), findsNothing);
      expect(find.textContaining('2026-10-17T'), findsNothing);
      await tester.tap(find.text('Source'));
      await tester.pumpAndSettle();
      expect(find.text('Development fixture'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'download summary formats saved date and preserves all action callbacks',
    (tester) async {
      final actions = <String>[];
      await show(
        tester,
        DownloadedTripCard(
          snapshot: const {
            'savedAt': '2026-10-21T15:08:25.840845Z',
            'data': {
              'trip': {
                'id': 'hidden-id',
                'title': 'Weekend journey',
                'destination': 'Siem Reap',
                'timezone': 'Asia/Phnom_Penh',
                'startDate': '2026-10-24',
                'endDate': '2026-10-25',
              },
            },
          },
          onOpen: () => actions.add('open'),
          onEdit: () => actions.add('edit'),
          onExpense: () => actions.add('expense'),
          onJournal: () => actions.add('journal'),
        ),
      );
      expect(find.textContaining('2026-10-21T'), findsNothing);
      expect(find.textContaining('Oct 21, 2026'), findsOneWidget);
      for (final label in [
        'Open downloaded trip',
        'Queue edit for synchronization',
        'Add expense',
        'Capture a moment',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(actions, ['open', 'edit', 'expense', 'journal']);
    },
  );
  for (final locale in ['en', 'km']) {
    testWidgets(
      'visual status and hero fit $locale with large text in dark theme',
      (tester) async {
        await show(
          tester,
          Column(
            children: [
              const TravelHero(
                title: 'ដំណើរកម្សាន្ត · Journey',
                subtitle: 'Cambodia',
                icon: Icons.auto_awesome,
              ),
              const GenerationStatusPanel(status: 'SUCCEEDED'),
              const CompanionAnswer(
                data: {
                  'text': 'សួស្តី · Welcome traveler',
                  'source': 'Google Gemini',
                  'mock': false,
                },
              ),
            ],
          ),
          locale: locale,
          scale: 2,
          brightness: Brightness.dark,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(Image), findsOneWidget);
        expect(find.textContaining('892hiubiu'), findsNothing);
      },
    );
  }
}
