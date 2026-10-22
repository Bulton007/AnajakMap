import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/storage/app_state.dart';
import 'package:anajak_travel/features/rpg/rpg_controller.dart';
import 'package:anajak_travel/features/rpg/rpg_game.dart';
import 'package:anajak_travel/features/rpg/rpg_screen.dart';
import 'package:anajak_travel/features/authentication/auth_controller.dart';
import 'package:anajak_travel/features/authentication/auth_models.dart';

void main() {
  test('practice route is public while account routes remain protected', () {
    const auth = AuthState(phase: AuthPhase.unauthenticated);
    expect(authRedirect(auth, Uri.parse('/rpg')), isNull);
    expect(authRedirect(auth, Uri.parse('/connected')), startsWith('/auth'));
  });
  test('restores saved progress and handles corrupt data honestly', () async {
    SharedPreferences.setMockInitialValues({
      RpgController.storageKey: jsonEncode(
        RpgProgress(xp: 120, gold: 60, collection: {'mossling': 2}).toJson(),
      ),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [preferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(rpgProvider).progress.level, 2);
    expect(container.read(rpgProvider).progress.collection['mossling'], 2);
    await prefs.setString(RpgController.storageKey, 'broken');
    container.invalidate(rpgProvider);
    expect(container.read(rpgProvider).storageError, isTrue);
  });
  for (final locale in ['en', 'km']) {
    for (final brightness in Brightness.values) {
      testWidgets('$locale $brightness small screen at 200% text can battle', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [preferencesProvider.overrideWithValue(prefs)],
            child: MaterialApp(
              theme: Tokens.theme(brightness),
              locale: Locale(locale),
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const RpgScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final habitat = find.widgetWithIcon(
          OutlinedButton,
          Icons.account_balance,
        );
        await tester.scrollUntilVisible(
          habitat.hitTestable(),
          150,
          maxScrolls: 60,
        );
        await tester.pumpAndSettle();
        await tester.tap(habitat);
        await tester.pumpAndSettle();
        final strike = find.widgetWithIcon(FilledButton, Icons.flash_on);
        await tester.scrollUntilVisible(
          strike.hitTestable(),
          150,
          maxScrolls: 60,
        );
        await tester.pumpAndSettle();
        await tester.tap(strike);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
