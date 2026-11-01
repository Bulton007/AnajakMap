import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/shared/components/remote.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'instant fields use date and time pickers and submit UTC instants',
    (tester) async {
      Map<String, dynamic>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: const [Locale('en'), Locale('km')],
          localizationsDelegates: const [
            Strings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => remoteForm(
                    context,
                    'addEvent',
                    const [
                      InputSpec(
                        'startsAt',
                        kind: InputKind.instant,
                        initial: '2026-10-30T09:00:00+07:00',
                      ),
                      InputSpec(
                        'endsAt',
                        kind: InputKind.instant,
                        initial: '2026-10-30T10:00:00+07:00',
                      ),
                    ],
                    submit: (body, _) async {
                      submitted = body;
                      return true;
                    },
                  ),
                  child: const Text('Open form'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2026-10-30T'), findsNothing);
      await tester.tap(find.byType(TextFormField).first);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(TimePickerDialog), findsNothing);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(submitted?['startsAt'], endsWith('Z'));
      expect(submitted?['endsAt'], endsWith('Z'));
      expect(submitted?.containsKey('timezone'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
