import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:latlong2/latlong.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/features/maps/route_guide.dart';
import 'package:anajak_travel/shared/models/map_route.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'connected_contract_test.dart' show MemoryCredentials;

class GuideRoutes extends TravelRepository {
  GuideRoutes() : super(ApiClient('https://test/api/v1/', MemoryCredentials()));
  int conversations = 0, messagesSent = 0;
  String? prompt;
  bool? contextShared;
  Completer<Object?>? pending;
  ApiFailure? failure;
  @override
  Future<Json> conversation() async {
    conversations++;
    return {'id': 'route-tips'};
  }

  @override
  Future<Object?> message(
    String id,
    String text, {
    bool useContext = false,
  }) async {
    messagesSent++;
    prompt = text;
    contextShared = useContext;
    if (failure != null) throw failure!;
    return pending == null
        ? {'text': 'Bring water and check local road signs.'}
        : pending!.future;
  }
}

void main() {
  const route = MapRoute(
    [LatLng(11.5638123, 104.9315123), LatLng(11.5760123, 104.9231123)],
    1234,
    321,
    'OSRM',
  );
  test('AI route summary has only selected names and confirmed estimates', () {
    final text = routeGuidePrompt(
      originName: 'My location',
      destinationName: 'Wat Phnom',
      route: route,
      khmer: false,
    );
    expect(text, contains('"distanceKm":"1.2"'));
    expect(text, contains('"estimatedMinutes":6'));
    expect(text, contains('"liveTraffic":false'));
    expect(text, isNot(contains('11.5638123')));
    expect(text, isNot(contains('104.9315123')));
  });
  Future<void> mount(WidgetTester tester, GuideRoutes repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(
          localizationsDelegates: [Strings.delegate],
          home: Scaffold(
            body: RouteGuidePanel(
              originName: 'My location',
              destinationName: 'Wat Phnom',
              route: route,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'AI tips require explicit agreement and prevent duplicate requests',
    (tester) async {
      final repo = GuideRoutes()..pending = Completer<Object?>();
      await mount(tester, repo);
      expect(repo.conversations, 0);
      expect(repo.messagesSent, 0);
      expect(find.textContaining('Google Gemini'), findsOneWidget);
      final ask = find.byKey(const ValueKey('route-guide-ask'));
      await tester.ensureVisible(ask);
      await tester.tap(ask);
      await tester.pump();
      await tester.tap(ask);
      await tester.pump();
      expect(repo.messagesSent, 1);
      expect(repo.contextShared, false);
      repo.pending!.complete({
        'text': 'Bring water and check local road signs.',
      });
      await tester.pumpAndSettle();
      expect(
        find.text('Bring water and check local road signs.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('provider failure leaves an honest retry state', (tester) async {
    final repo = GuideRoutes()
      ..failure = const ApiFailure('HTTP', 'Unavailable', status: 503);
    await mount(tester, repo);
    await tester.ensureVisible(find.byKey(const ValueKey('route-guide-ask')));
    await tester.tap(find.byKey(const ValueKey('route-guide-ask')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your driving route is still ready.'),
      findsOneWidget,
    );
    expect(find.text('Bring water and check local road signs.'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('route-guide-ask')))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'km']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'route tips remain scrollable at 2x text in $language $brightness',
        (tester) async {
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final repo = GuideRoutes();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [repositoryProvider.overrideWithValue(repo)],
              child: MaterialApp(
                locale: Locale(language),
                supportedLocales: const [Locale('en'), Locale('km')],
                localizationsDelegates: const [
                  Strings.delegate,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                theme: Tokens.theme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
                home: const Scaffold(
                  body: RouteGuidePanel(
                    originName: 'My location',
                    destinationName: 'Wat Phnom',
                    route: route,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(
            find.byKey(const ValueKey('route-guide-ask')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('route-guide-ask')).hitTestable(),
            findsOneWidget,
          );
          expect(repo.messagesSent, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
