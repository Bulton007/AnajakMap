import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/features/authentication/auth_controller.dart';
import 'package:anajak_travel/features/rpg/adventure_controller.dart';
import 'package:anajak_travel/features/rpg/adventure_repository.dart';
import 'package:anajak_travel/features/rpg/adventure_management.dart';
import 'adventure_test.dart' show AdventureFixture, SignedIn;

class ManagementFixture extends AdventureFixture {
  int gold = 20;
  bool empty = false;
  @override
  Future<AdventureSnapshot> profile(String realm) async {
    final previous = await super.profile(realm);
    return AdventureSnapshot({
      ...previous.data,
      'profile': {'xp': 400, 'gold': gold, 'equippedTitle': 'traveler'},
      'monsters': empty
          ? <Json>[]
          : [
              {
                'id': 'owned-1',
                'speciesId': 'mossling',
                'xp': 350,
                'variation': 2,
                'evolution': 0,
              },
              {
                'id': 'owned-2',
                'speciesId': 'amberhorn',
                'xp': 100,
                'variation': 1,
                'evolution': 1,
              },
            ],
      'party': [
        {'slot': 1, 'monsterId': 'owned-1'},
      ],
      'species': empty
          ? <Json>[]
          : [
              ...previous.species,
              {
                'id': 'amberhorn',
                'name': 'Dawn Singha',
                'rarity': 'Rare',
                'element': 'fire',
                'habitat': 'temple',
                'hp': 70,
                'attack': 19,
                'defense': 12,
                'speed': 10,
              },
            ],
      'inventory': empty
          ? <Json>[]
          : [
              {'item': 'crystal', 'quantity': 8},
              {'item': 'potion', 'quantity': 5},
            ],
      'quests': empty
          ? <Json>[]
          : [
              {
                'id': 'first-win',
                'title': 'Win your first battle',
                'progress': 0,
                'target': 1,
                'completed': false,
                'claimed': false,
                'xp': 50,
                'gold': 20,
              },
              {
                'id': 'first-capture',
                'title': 'Capture your first companion',
                'progress': 1,
                'target': 1,
                'completed': true,
                'claimed': false,
                'xp': 50,
                'gold': 20,
              },
            ],
      'achievements': empty
          ? <Json>[]
          : [
              {'id': 'traveler', 'title': 'Traveler', 'unlocked': true},
              {
                'id': 'collector',
                'title': 'Creature Keeper',
                'unlocked': false,
              },
            ],
      'exploration': empty
          ? <Json>[]
          : [
              {
                'id': 'palace',
                'name': 'Royal Palace and the long riverside trail',
                'successes': 2,
                'bosses': 0,
              },
            ],
      'history': empty
          ? <Json>[]
          : [
              {
                'kind': 'normal',
                'status': 'captured',
                'completedAt': '2026-10-25T08:00:00Z',
              },
            ],
    });
  }
}

Future<void> showManagement(
  WidgetTester tester,
  ManagementFixture repo,
  String section, {
  Size size = const Size(320, 680),
  double scale = 2,
  String language = 'en',
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(SignedIn.new),
        adventureRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: Tokens.theme(brightness),
        locale: Locale(language),
        supportedLocales: const [Locale('en'), Locale('km')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: AdventureManagement(
          scope: ('alice', 'practice'),
          initial: section,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> checkWholePage(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find.byType(Scrollable).first,
  );
  for (var step = 0; step < 35; step++) {
    expect(tester.takeException(), isNull);
    if (scrollable.position.pixels >= scrollable.position.maxScrollExtent) {
      break;
    }
    await tester.drag(
      find.byKey(const Key('rpg-management-list')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
  expect(
    scrollable.position.pixels,
    closeTo(scrollable.position.maxScrollExtent, 1),
  );
}

void main() {
  for (final language in ['en', 'km']) {
    testWidgets(
      'collection searches catalog names, legacy IDs and elements in $language',
      (tester) async {
        await showManagement(
          tester,
          ManagementFixture(),
          'collection',
          language: language,
          size: const Size(500, 1000),
          scale: 1,
        );
        for (final query in ['Lotus Naga', 'នាគឈូក', 'mossling', 'earth']) {
          await tester.enterText(find.byType(TextField), query);
          await tester.pumpAndSettle();
          expect(find.byType(ExpansionTile), findsOneWidget, reason: query);
          expect(
            find.descendant(
              of: find.byType(ExpansionTile),
              matching: find.text(language == 'km' ? 'នាគឈូក' : 'Lotus Naga'),
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final section in [
    'collection',
    'party',
    'inventory',
    'quests',
    'achievements',
  ]) {
    for (final language in ['en', 'km']) {
      for (final brightness in Brightness.values) {
        testWidgets(
          '$section stays readable at 320px / 200% in $language $brightness',
          (tester) async {
            await showManagement(
              tester,
              ManagementFixture(),
              section,
              language: language,
              brightness: brightness,
            );
            await checkWholePage(tester);
          },
        );
      }
    }
  }

  testWidgets(
    'inventory cards share a row height and aligned buttons; zero gold cannot buy',
    (tester) async {
      final repo = ManagementFixture()..gold = 0;
      await showManagement(
        tester,
        repo,
        'inventory',
        size: const Size(420, 1000),
        scale: 1,
      );
      final crystal = find.byKey(const Key('rpg-inventory-crystal'));
      final potion = find.byKey(const Key('rpg-inventory-potion'));
      await tester.scrollUntilVisible(crystal, 200);
      final first = tester.getRect(crystal), second = tester.getRect(potion);
      expect(first.top, closeTo(second.top, .1));
      expect(first.height, closeTo(second.height, .1));
      expect(second.left - first.right, closeTo(16, .1));
      final buyCrystal = find.byKey(const Key('rpg-buy-crystal'));
      final buyPotion = find.byKey(const Key('rpg-buy-potion'));
      expect(
        tester.getRect(buyCrystal).bottom,
        closeTo(tester.getRect(buyPotion).bottom, .1),
      );
      expect(tester.widget<FilledButton>(buyCrystal).onPressed, isNull);
      expect(tester.widget<FilledButton>(buyPotion).onPressed, isNull);
      expect(repo.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ten gold enables potion only, keeping purchase controls aligned',
    (tester) async {
      await showManagement(
        tester,
        ManagementFixture()..gold = 10,
        'inventory',
        size: const Size(420, 1000),
        scale: 1,
      );
      final crystal = find.byKey(const Key('rpg-buy-crystal'));
      final potion = find.byKey(const Key('rpg-buy-potion'));
      await tester.scrollUntilVisible(crystal, 200);
      expect(tester.widget<FilledButton>(crystal).onPressed, isNull);
      expect(tester.widget<FilledButton>(potion).onPressed, isNotNull);
      expect(
        tester.getRect(crystal).bottom,
        closeTo(tester.getRect(potion).bottom, .1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quest cards keep a visible 16dp gap and server completion gates claim',
    (tester) async {
      final repo = ManagementFixture();
      await showManagement(
        tester,
        repo,
        'quests',
        size: const Size(500, 1200),
        scale: 1,
      );
      final first = find.byKey(const Key('rpg-quest-first-win'));
      final second = find.byKey(const Key('rpg-quest-first-capture'));
      await tester.scrollUntilVisible(second, 200);
      expect(
        tester.getRect(second).top - tester.getRect(first).bottom,
        closeTo(16, .1),
      );
      final claims = find.widgetWithText(OutlinedButton, 'Claim reward');
      expect(claims, findsNWidgets(2));
      expect(tester.widget<OutlinedButton>(claims.first).onPressed, isNull);
      expect(tester.widget<OutlinedButton>(claims.last).onPressed, isNotNull);
      expect(repo.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a recoverable action failure shows pending feedback and blocks more purchases',
    (tester) async {
      final repo = ManagementFixture()..failNext = true;
      await showManagement(
        tester,
        repo,
        'inventory',
        size: const Size(420, 1000),
        scale: 1,
      );
      final buy = find.byKey(const Key('rpg-buy-potion'));
      await tester.scrollUntilVisible(buy, 200);
      await tester.tap(buy);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Action awaiting confirmation'),
        -200,
      );
      expect(find.text('Retry pending action'), findsOneWidget);
      expect(repo.calls, hasLength(1));
      await tester.scrollUntilVisible(buy, 200);
      expect(tester.widget<FilledButton>(buy).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty management data has a visible recovery state instead of blank lists',
    (tester) async {
      await showManagement(
        tester,
        ManagementFixture()..empty = true,
        'party',
        scale: 1,
      );
      await tester.scrollUntilVisible(
        find.text('Your companions will appear here after capture.'),
        200,
      );
      expect(find.byIcon(Icons.pets_rounded), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
