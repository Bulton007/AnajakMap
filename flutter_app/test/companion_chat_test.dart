import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/features/connected/companion_chat.dart';
import 'connected_contract_test.dart' show MemoryCredentials;

class ChatRepository extends TravelRepository {
  ChatRepository()
    : super(ApiClient('https://example.test/api/v1/', MemoryCredentials()));
  int sent = 0;
  bool? sharedContext;
  Object? failure;
  Completer<Object?>? pending;
  @override
  Future<Json> conversation() async => {'id': 'owned-chat'};
  @override
  Future<Object?> message(
    String id,
    String text, {
    bool useContext = false,
  }) async {
    sent++;
    sharedContext = useContext;
    if (failure != null) throw failure!;
    return pending == null
        ? {'text': 'Consider a relaxed temple morning.', 'mock': false}
        : pending!.future;
  }
}

void main() {
  Future<void> show(
    WidgetTester tester,
    ChatRepository repo, {
    String locale = 'en',
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() => Strings.delegate.load(Locale(locale)));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [repositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          locale: Locale(locale),
          supportedLocales: const [Locale('en'), Locale('km')],
          localizationsDelegates: const [
            Strings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: Tokens.theme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const CompanionChat(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'shows confirmed conversation turns and never sends history without opt-in',
    (tester) async {
      final repo = ChatRepository();
      await show(tester, repo);
      await tester.enterText(find.byType(TextField), 'A day in Siem Reap?');
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(repo.sharedContext, false);
      expect(find.text('A day in Siem Reap?'), findsOneWidget);
      expect(find.text('Consider a relaxed temple morning.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'And the next day?');
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(find.text('And the next day?'), findsOneWidget);
      tester.widget<ListView>(find.byType(ListView)).controller!.jumpTo(0);
      await tester.pumpAndSettle();
      expect(find.text('A day in Siem Reap?'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'explicit context consent is sent and duplicate submissions are prevented',
    (tester) async {
      final repo = ChatRepository()..pending = Completer<Object?>();
      await show(tester, repo);
      await tester.tap(find.byType(SwitchListTile));
      await tester.enterText(find.byType(TextField), 'A follow-up question');
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      expect(repo.sent, 1);
      expect(repo.sharedContext, true);
      expect(find.text('Consider a relaxed temple morning.'), findsNothing);
      repo.pending!.complete({'text': 'Confirmed answer'});
      await tester.pumpAndSettle();
      expect(find.text('Confirmed answer'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'quota failure preserves the question and respects server retry timing',
    (tester) async {
      final repo = ChatRepository()
        ..failure = const ApiFailure(
          'LIMIT',
          'private diagnostics',
          status: 429,
          retryAfterSeconds: 2,
        );
      await show(tester, repo);
      await tester.enterText(find.byType(TextField), 'Keep this question');
      await tester.pump();
      await tester.tap(find.byTooltip('Send question'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Keep this question',
      );
      expect(find.textContaining('private diagnostics'), findsNothing);
      await tester.tap(find.byTooltip('Send question'));
      expect(repo.sent, 1);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      await tester.pump(const Duration(seconds: 3));
      repo.failure = null;
      await tester.tap(find.byTooltip('Send question'));
      await tester.pumpAndSettle();
      expect(repo.sent, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Khmer, large text and keyboard keep composer reachable', (
    tester,
  ) async {
    await show(tester, ChatRepository(), locale: 'km', scale: 2);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'សួស្តី');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('ផ្ញើសំណួរ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
