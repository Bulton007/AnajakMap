import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/features/connected/connected_tools.dart';
import 'package:anajak_travel/app/localization/strings.dart';

void main() {
  testWidgets(
    'photo sharing needs explicit consent and cancellation never opens upload',
    (tester) async {
      await tester.runAsync(() => Strings.delegate.load(const Locale('en')));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              Strings.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: const AssistanceTask(task: 'vision', profile: {'id': 'test'}),
          ),
        ),
      );
      final choose = find.byType(FilledButton).first;
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(find.text('Share a photo with AI?'), findsOneWidget);
      expect(find.textContaining('Google Gemini'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.widget<FilledButton>(choose).onPressed, isNotNull);
    },
  );
}
