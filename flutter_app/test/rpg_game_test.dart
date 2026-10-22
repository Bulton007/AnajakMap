import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/features/rpg/rpg_game.dart';

class FixedRandom implements Random {
  FixedRandom(this.value);
  final double value;
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => (value * max).floor();
  @override
  bool nextBool() => value < .5;
}

void main() {
  test(
    'habitat and rarity determine encounter, active encounters cannot reroll',
    () {
      for (final biome in Biome.values) {
        for (final value in [0.0, .7, .95]) {
          final engine = RpgEngine(FixedRandom(value));
          final game = engine.encounter(RpgGame(), biome);
          expect(game.creature!.biome, biome);
          expect(
            game.creature!.grade,
            value < .6
                ? Grade.common
                : value < .9
                ? Grade.rare
                : Grade.epic,
          );
          expect(identical(engine.encounter(game, biome), game), isTrue);
        }
      }
    },
  );
  test('victory awards once and does not capture', () {
    final engine = RpgEngine(FixedRandom(0));
    var game = engine.encounter(RpgGame(), Biome.temple);
    while (game.active) {
      game = engine.move(game, BattleMove.strike);
    }
    expect(game.phase, BattlePhase.won);
    expect(game.progress.gold, game.creature!.reward);
    expect(game.progress.collection, isEmpty);
    expect(identical(engine.move(game, BattleMove.capture), game), isTrue);
  });
  test('capture adds collection and awards exactly once', () {
    final engine = RpgEngine(FixedRandom(0));
    final game = engine.move(
      engine.encounter(RpgGame(), Biome.beach),
      BattleMove.capture,
    );
    expect(game.phase, BattlePhase.captured);
    expect(game.progress.collection['bubblefin'], 1);
    expect(identical(engine.move(game, BattleMove.capture), game), isTrue);
    expect(
      RpgProgress.fromJson(game.progress.toJson()).collection,
      game.progress.collection,
    );
  });
  test(
    'failed capture consumes crystal, enemy retaliates, empty supply cannot act',
    () {
      final engine = RpgEngine(FixedRandom(.99));
      var game = engine.encounter(RpgGame(), Biome.beach);
      for (var i = 0; i < 3; i++) {
        game = engine.move(game, BattleMove.capture);
      }
      expect(game.crystals, 0);
      expect(game.playerHp, lessThan(100));
      expect(game.progress.gold, 0);
      expect(identical(engine.move(game, BattleMove.capture), game), isTrue);
    },
  );
  test(
    'weaker health improves capture odds; fleeing and loss award nothing',
    () {
      final engine = RpgEngine(FixedRandom(.99));
      var game = engine.encounter(RpgGame(), Biome.temple);
      final chance = engine.captureChance(game);
      game = engine.move(game, BattleMove.strike);
      expect(engine.captureChance(game), greaterThan(chance));
      expect(engine.move(game, BattleMove.flee).progress.gold, 0);
      for (var i = 0; i < 3; i++) {
        game = engine.move(game, BattleMove.capture);
      }
      while (game.active) {
        game = engine.move(game, BattleMove.strike);
      }
      expect(game.phase, BattlePhase.lost);
      expect(game.progress.gold, 0);
    },
  );
  test(
    'new encounter restores supplies, retains progress and busy state blocks actions',
    () {
      final engine = RpgEngine(FixedRandom(0));
      var game = engine.move(
        engine.encounter(RpgGame(), Biome.temple),
        BattleMove.capture,
      );
      game = engine.encounter(game, Biome.beach);
      expect(game.crystals, 3);
      expect(game.playerHp, 100);
      expect(game.progress.gold, greaterThan(0));
      final busy = game.saving(busy: true, error: false);
      expect(identical(engine.move(busy, BattleMove.strike), busy), isTrue);
    },
  );
}
