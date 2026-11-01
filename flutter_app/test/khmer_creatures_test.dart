import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:anajak_travel/features/rpg/creature_catalog.dart';
import 'package:anajak_travel/features/rpg/creature_portrait_painter.dart';
import 'package:anajak_travel/features/rpg/rpg_game.dart';
import 'package:anajak_travel/features/rpg/rpg_screen.dart';
import 'package:anajak_travel/features/rpg/battle_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new names retain every persisted species ID and game balance', () {
    expect(creatureConcepts.map((c) => c.id), [
      'mossling',
      'amberhorn',
      'moonwarden',
      'bubblefin',
      'coralclaw',
      'tidewing',
    ]);
    expect(creatureConcepts.map((c) => c.design).toSet().length, 6);
    for (final creature in creatures) {
      expect(creatureDisplayName(creature.id), creature.name);
      expect(
        creatureDisplayName(creature.id, language: 'km'),
        contains(RegExp(r'[\u1780-\u17ff]')),
      );
      expect(creatureLore(creature.id), isNotEmpty);
    }
    final restored = RpgProgress.fromJson({
      'xp': 120,
      'gold': 35,
      'collection': {'mossling': 2, 'tidewing': 1},
    });
    expect(restored.collection, {'mossling': 2, 'tidewing': 1});
    expect(creatures.map((c) => c.level), [1, 3, 5, 1, 3, 5]);
    expect(creatureInspirationNotice(), contains('invented'));
  });

  testWidgets('six portraits have six genuinely different opaque silhouettes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final silhouettes = <String>{};
      for (final creature in creatures) {
        final recorder = ui.PictureRecorder();
        KhmerCreaturePainter(
          creature,
        ).paint(Canvas(recorder), const Size(180, 180));
        final picture = recorder.endRecording();
        final image = await picture.toImage(180, 180);
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final mask = Uint8List(180 * 180);
        var opaque = 0;
        for (var i = 0; i < mask.length; i++) {
          // Ignore the shared translucent halo/shadow; compare creature anatomy.
          mask[i] = pixels.getUint8(i * 4 + 3) > 180 ? 1 : 0;
          opaque += mask[i];
        }
        expect(opaque, greaterThan(2000));
        silhouettes.add(base64Encode(mask));
        image.dispose();
        picture.dispose();
      }
      expect(silhouettes.length, 6);
    });
  });

  for (final locale in ['en', 'km']) {
    testWidgets(
      '3D and illustrated views render every family at large text in $locale',
      (tester) async {
        tester.view.physicalSize = const Size(340, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final creature in creatures) {
          final session = <String, dynamic>{
            'status': 'active',
            'revision': 1,
            'battle': {
              'enemy': {'speciesId': creature.id, 'hp': 60, 'evolution': 0},
              'ally': {'speciesId': 'mossling', 'hp': 60, 'evolution': 0},
            },
          };
          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('$locale-${creature.id}'),
              locale: Locale(locale),
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: BattleScene(session: session),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(find.byType(CustomPaint), findsWidgets);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.byType(FilterChip).first);
          await tester.tap(find.byType(FilterChip).first);
          await tester.pumpAndSettle();
          expect(find.byType(CreaturePortrait), findsOneWidget);
          expect(tester.takeException(), isNull);
          expect(session['revision'], 1);
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
