import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/shared/components/travel_alerts.dart';

void main() {
  testWidgets('contact opens a validated dialer URI only after explicit tap', (
    tester,
  ) async {
    Uri? opened;
    await tester.runAsync(() => Strings.delegate.load(const Locale('en')));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [Strings.delegate],
        home: Scaffold(
          body: EmergencyContactCard(
            contact: const {
              'label': 'My trusted contact',
              'phone': '+855 12 345 678',
            },
            openDialer: (uri) async {
              opened = uri;
              return true;
            },
          ),
        ),
      ),
    );
    expect(opened, isNull);
    await tester.tap(find.text('Open dialer'));
    await tester.pumpAndSettle();
    expect(opened?.scheme, 'tel');
    expect(opened?.path, '+85512345678');
    expect(tester.takeException(), isNull);
  });
  testWidgets('unsafe phone input cannot launch another URL scheme', (
    tester,
  ) async {
    await tester.runAsync(() => Strings.delegate.load(const Locale('en')));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [Strings.delegate],
        home: const Scaffold(
          body: EmergencyContactCard(
            contact: {'label': 'Invalid', 'phone': 'https://example.test'},
          ),
        ),
      ),
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
