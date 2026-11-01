import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/features/authentication/auth_controller.dart';
import 'package:anajak_travel/features/rpg/adventure_controller.dart';
import 'package:anajak_travel/features/rpg/adventure_repository.dart';
import 'package:anajak_travel/features/rpg/adventure_management.dart';
import 'package:anajak_travel/features/rpg/battle_scene.dart';
import 'package:anajak_travel/features/rpg/rpg_screen.dart'
    show CreaturePortrait;
import 'adventure_test.dart' show AdventureFixture, SignedIn, session;

Finder managementScroll() => find
    .descendant(
      of: find.byKey(const Key('rpg-management-list')),
      matching: find.byType(Scrollable),
    )
    .first;

class ProgressionFixture extends AdventureFixture {
  @override
  Future<AdventureSnapshot> profile(String realm) async {
    final old = await super.profile(realm);
    return AdventureSnapshot({
      ...old.data,
      'profile': {'XP': 400, 'GOLD': 500, 'EQUIPPED_TITLE': 'traveler'},
      'monsters': [
        {
          'ID': 'owned-1',
          'SPECIES_ID': 'mossling',
          'XP': 350,
          'EVOLUTION': 0,
          'VARIATION': 2,
        },
      ],
      'party': [
        {'SLOT': 1, 'MONSTER_ID': 'owned-1'},
      ],
      'inventory': [
        {'ITEM': 'potion', 'QUANTITY': 5},
      ],
      'achievements': [
        {'id': 'traveler', 'title': 'Traveler', 'unlocked': true},
        {'id': 'first-win', 'title': 'Trailblazer', 'unlocked': true},
      ],
    });
  }
}

void main() {
  testWidgets(
    'collection search and evolution submit owned instance and expected stage',
    (tester) async {
      final repo = ProgressionFixture();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(SignedIn.new),
            adventureRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: const AdventureManagement(scope: ('alice', 'practice')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not-a-species');
      await tester.pump();
      expect(find.byType(ExpansionTile), findsNothing);
      await tester.enterText(find.byType(TextField), 'moss');
      await tester.pump();
      await tester.tap(find.text('Lotus Naga'));
      await tester.pumpAndSettle();
      final evolve = find.byKey(const Key('rpg-evolve-owned-1'));
      await tester.scrollUntilVisible(
        evolve.hitTestable(),
        200,
        scrollable: managementScroll(),
      );
      await tester.pumpAndSettle();
      expect(evolve.hitTestable(), findsOneWidget);
      expect(tester.widget<OutlinedButton>(evolve).onPressed, isNotNull);
      await tester.tap(evolve);
      await tester.pumpAndSettle();
      expect(repo.calls.single.$1, 'practice/monsters/owned-1/evolve');
      expect(repo.calls.single.$2, {'stage': 0});
    },
  );
  testWidgets(
    'inventory and title buttons perform real repository operations',
    (tester) async {
      final repo = ProgressionFixture();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(SignedIn.new),
            adventureRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: const AdventureManagement(
              scope: ('alice', 'practice'),
              initial: 'inventory',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final purchase = find.byKey(const Key('rpg-buy-potion'));
      await tester.scrollUntilVisible(
        purchase.hitTestable(),
        200,
        scrollable: managementScroll(),
      );
      await tester.pumpAndSettle();
      expect(purchase.hitTestable(), findsOneWidget);
      expect(tester.widget<FilledButton>(purchase).onPressed, isNotNull);
      await tester.tap(purchase);
      await tester.pumpAndSettle();
      expect(repo.calls.single.$1, 'practice/inventory/purchase');
      expect(repo.calls.single.$2, {'item': 'potion', 'quantity': 1});
      final achievements = find.text('Achievements');
      await tester.scrollUntilVisible(
        achievements.hitTestable(),
        -200,
        scrollable: managementScroll(),
      );
      await tester.pumpAndSettle();
      expect(achievements.hitTestable(), findsOneWidget);
      await tester.tap(achievements);
      await tester.pumpAndSettle();
      final equip = find.byKey(const Key('rpg-equip-first-win'));
      await tester.scrollUntilVisible(
        equip.hitTestable(),
        200,
        scrollable: managementScroll(),
      );
      await tester.pumpAndSettle();
      expect(equip.hitTestable(), findsOneWidget);
      expect(tester.widget<OutlinedButton>(equip).onPressed, isNotNull);
      await tester.tap(equip);
      await tester.pumpAndSettle();
      expect(repo.calls.last.$1, 'practice/title');
      expect(repo.calls.last.$2, {'id': 'first-win'});
    },
  );
  testWidgets('procedural 3D paints, orbits, animates and falls back', (
    tester,
  ) async {
    final sceneKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(Brightness.light),
        home: Scaffold(
          body: RepaintBoundary(
            key: sceneKey,
            child: BattleScene(session: session()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.drag(find.byType(GestureDetector).first, const Offset(35, 0));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    // Capture a real raster of the projected meshes for visual review.
    final boundary =
        sceneKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('.local').create(recursive: true);
      await File(
        '.local/rpg-3d-preview.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.tap(find.text('Motion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2D fallback'));
    await tester.pumpAndSettle();
    expect(find.text('Illustrated view'), findsOneWidget);
    expect(find.byType(CreaturePortrait), findsOneWidget);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, '2D fallback'))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('unknown creature renders safe fallback with reduced motion', (
    tester,
  ) async {
    final data = session();
    data['battle'] = {
      ...object(data['battle']),
      'enemy': {'speciesId': 'future-species', 'hp': 20},
    };
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: BattleScene(session: data)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Illustrated view'), findsOneWidget);
    expect(find.byIcon(Icons.pets), findsOneWidget);
    expect(find.byType(CreaturePortrait), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
