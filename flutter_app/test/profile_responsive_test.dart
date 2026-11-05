import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/storage/app_state.dart';
import 'package:anajak_travel/features/profile/profile.dart';
import 'package:anajak_travel/shared/components/components.dart';
import 'package:anajak_travel/shared/components/visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Khmer banner fills its container and theme choices fit large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [preferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            locale: const Locale('km'),
            supportedLocales: const [Locale('en'), Locale('km')],
            theme: Tokens.theme(Brightness.light),
            localizationsDelegates: const [
              Strings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(2)),
              child: child!,
            ),
            home: const Scaffold(
              body: PageBody(
                children: [
                  VisualHero(
                    title: 'នៅកន្លែងថ្មីៗ បង្កើតអនុស្សាវរីយ៍',
                    caption: 'កម្ពុជា',
                  ),
                  PreferencesControls(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(VisualHero)).width, closeTo(280, .1));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byIcon(Icons.dark_mode_outlined));
      await tester.tap(find.byIcon(Icons.dark_mode_outlined));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PreferencesControls)),
      );
      expect(container.read(appStateProvider).theme, ThemeMode.dark);
      expect(tester.takeException(), isNull);
    },
  );
}
