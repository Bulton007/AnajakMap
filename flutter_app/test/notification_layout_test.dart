import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/shared/components/travel_alerts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  for (final locale in ['en', 'km']) {
    testWidgets('notification title and icon align in $locale', (tester) async {
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
          home: Scaffold(
            body: TravelNotificationCard(
              delivery: const {
                'title': 'New private message',
                'kind': 'chat.direct-message',
                'dueAt': '2026-11-05T12:30:00Z',
                'status': 'MOCK_DELIVERED',
              },
              onOpen: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text(
        locale == 'km' ? 'សារឯកជនថ្មី' : 'New private message',
      );
      expect(
        tester.getCenter(title).dy,
        closeTo(tester.getCenter(find.byIcon(Icons.forum_outlined)).dy, .1),
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('notification content and actions fit narrow large-text layout', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [Strings.delegate],
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: TravelNotificationCard(
                unread: true,
                sender: const Text('Travel companion'),
                delivery: const {
                  'title': 'You have a trip invitation',
                  'kind': 'group.invited',
                  'dueAt': '2026-11-05T12:30:00Z',
                  'status': 'MOCK_DELIVERED',
                  'detail': 'A weekend in Cambodia',
                },
                actions: [
                  TextButton(
                    onPressed: () => opened = true,
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Unread'), findsOneWidget);
    expect(find.text('Travel companion'), findsOneWidget);
    await tester.ensureVisible(find.text('Open'));
    await tester.tap(find.text('Open'));
    expect(opened, isTrue);
  });
}
