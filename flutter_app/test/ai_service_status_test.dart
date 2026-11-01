import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/features/connected/ai_service_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/shared/components/travel_panels.dart';

void main() {
  test('old and current development replies are identified as demo', () {
    expect(isDemoGuideAnswer({'text': 'Development travel guide: test'}), true);
    expect(isDemoGuideAnswer({'mock': true, 'text': 'Example'}), true);
    expect(
      isDemoGuideAnswer({'source': 'Development fixture', 'text': 'Example'}),
      true,
    );
    expect(
      isDemoGuideAnswer({
        'mock': false,
        'text': 'Real answer',
        'source': 'Google Gemini',
      }),
      false,
    );
  });
  Future<void> show(
    WidgetTester tester,
    Future<Json> Function() load, {
    String locale = 'en',
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => Strings.delegate.load(Locale(locale)));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [guideCapabilitiesProvider.overrideWith((ref) => load())],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('km')],
          localizationsDelegates: [
            Strings.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: Tokens.theme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: AiServiceStatus()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('network failure is retryable and never labeled unconfigured', (
    tester,
  ) async {
    var calls = 0;
    await show(tester, () async {
      if (++calls == 1) {
        throw const ApiFailure('NETWORK', 'private diagnostics');
      }
      return {'configured': true, 'demo': false, 'providerVerified': false};
    });
    expect(find.text('Could not check AI'), findsOneWidget);
    expect(find.textContaining('setup needed'), findsNothing);
    expect(find.textContaining('private diagnostics'), findsNothing);
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('AI assistance · you stay in control'), findsOneWidget);
    expect(find.textContaining('verified'), findsNothing);
  });

  testWidgets('demo and missing configuration are honest distinct states', (
    tester,
  ) async {
    await show(tester, () async => {'configured': false, 'demo': true});
    expect(find.text('Sample answers, not live AI.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await show(tester, () async => {'configured': false, 'demo': false});
    expect(find.text('AI setup needed on your server'), findsOneWidget);
    expect(find.text('Manual trip planning is available.'), findsOneWidget);
  });

  testWidgets('status supports large Khmer text on a small screen', (
    tester,
  ) async {
    await show(
      tester,
      () async => {'configured': false},
      locale: 'km',
      scale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
