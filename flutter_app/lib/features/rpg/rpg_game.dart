import 'dart:math';

enum Biome { temple, beach }

enum Grade { common, rare, epic }

enum BattlePhase { exploring, battling, won, captured, escaped, lost }

enum BattleMove { strike, magic, capture, flee }

class Creature {
  const Creature(
    this.id,
    this.name,
    this.biome,
    this.grade,
    this.level,
    this.hue,
  );
  final String id, name;
  final Biome biome;
  final Grade grade;
  final int level, hue;
  int get health => 32 + level * 8;
  int get reward => 12 + level * 6;
}

const creatures = [
  Creature('mossling', 'Mossling', Biome.temple, Grade.common, 1, 150),
  Creature('amberhorn', 'Amberhorn', Biome.temple, Grade.rare, 3, 38),
  Creature('moonwarden', 'Moonwarden', Biome.temple, Grade.epic, 5, 265),
  Creature('bubblefin', 'Bubblefin', Biome.beach, Grade.common, 1, 185),
  Creature('coralclaw', 'Coralclaw', Biome.beach, Grade.rare, 3, 350),
  Creature('tidewing', 'Tidewing', Biome.beach, Grade.epic, 5, 215),
];

/// Practice progress is device-local and never represents an account balance.
class RpgProgress {
  RpgProgress({
    this.xp = 0,
    this.gold = 0,
    Map<String, int> collection = const {},
  }) : collection = Map.unmodifiable(collection);
  final int xp, gold;
  final Map<String, int> collection;
  int get level => 1 + xp ~/ 100;
  Map<String, dynamic> toJson() => {
    'xp': xp,
    'gold': gold,
    'collection': collection,
  };
  factory RpgProgress.fromJson(Map<String, dynamic> json) {
    final xp = json['xp'] as int;
    final gold = json['gold'] as int;
    final owned = Map<String, int>.from(json['collection'] as Map);
    if (xp < 0 ||
        gold < 0 ||
        owned.entries.any(
          (e) => !creatures.any((c) => c.id == e.key) || e.value < 1,
        )) {
      throw const FormatException('Invalid practice progress');
    }
    return RpgProgress(xp: xp, gold: gold, collection: owned);
  }
}

class RpgGame {
  RpgGame({
    RpgProgress? progress,
    this.biome = Biome.temple,
    this.phase = BattlePhase.exploring,
    this.creature,
    this.enemyHp = 0,
    this.playerHp = 100,
    this.mana = 3,
    this.crystals = 3,
    this.message = 'intro',
    this.damage = 0,
    this.busy = false,
    this.storageError = false,
  }) : progress = progress ?? RpgProgress();
  final RpgProgress progress;
  final Biome biome;
  final BattlePhase phase;
  final Creature? creature;
  final int enemyHp, playerHp, mana, crystals, damage;
  final String message;
  final bool busy, storageError;
  bool get active => phase == BattlePhase.battling;
  RpgGame saving({required bool busy, required bool error}) => RpgGame(
    progress: progress,
    biome: biome,
    phase: phase,
    creature: creature,
    enemyHp: enemyHp,
    playerHp: playerHp,
    mana: mana,
    crystals: crystals,
    message: message,
    damage: damage,
    busy: busy,
    storageError: error,
  );
}

class RpgEngine {
  RpgEngine([Random? random]) : random = random ?? Random();
  final Random random;
  RpgGame encounter(RpgGame state, Biome biome) {
    if (state.active || state.busy) return state;
    final roll = random.nextInt(100);
    final grade = roll < 60
        ? Grade.common
        : roll < 90
        ? Grade.rare
        : Grade.epic;
    final creature = creatures.firstWhere(
      (c) => c.biome == biome && c.grade == grade,
    );
    return RpgGame(
      progress: state.progress,
      biome: biome,
      phase: BattlePhase.battling,
      creature: creature,
      enemyHp: creature.health,
      message: 'encounter',
      storageError: state.storageError,
    );
  }

  RpgGame move(RpgGame s, BattleMove move) {
    if (!s.active || s.busy) return s;
    final c = s.creature!;
    var hp = s.enemyHp, mana = s.mana, crystals = s.crystals;
    var phase = BattlePhase.battling, message = 'strike', damage = 0;
    if (move == BattleMove.flee) {
      phase = BattlePhase.escaped;
      message = 'escaped';
    } else if (move == BattleMove.capture) {
      if (crystals == 0) return s;
      crystals--;
      final chance = captureChance(s);
      if (random.nextDouble() < chance) {
        phase = BattlePhase.captured;
        message = 'captured';
      } else {
        message = 'captureMiss';
      }
    } else {
      if (move == BattleMove.magic && mana == 0) return s;
      if (move == BattleMove.magic) mana--;
      damage = (move == BattleMove.magic ? 23 : 12) + random.nextInt(6);
      hp = max(0, hp - damage);
      message = move == BattleMove.magic ? 'magicHit' : 'strike';
      if (hp == 0) {
        phase = BattlePhase.won;
        message = 'won';
      }
    }
    var playerHp = s.playerHp;
    if (phase == BattlePhase.battling) {
      playerHp = max(0, playerHp - (7 + c.level * 2 + random.nextInt(4)));
      if (playerHp == 0) {
        phase = BattlePhase.lost;
        message = 'lost';
      }
    }
    var progress = s.progress;
    if (phase == BattlePhase.won || phase == BattlePhase.captured) {
      progress = RpgProgress(
        xp: progress.xp + c.reward * 2,
        gold: progress.gold + c.reward,
        collection: {
          ...progress.collection,
          if (phase == BattlePhase.captured)
            c.id: (progress.collection[c.id] ?? 0) + 1,
        },
      );
    }
    return RpgGame(
      progress: progress,
      biome: s.biome,
      phase: phase,
      creature: c,
      enemyHp: hp,
      playerHp: playerHp,
      mana: mana,
      crystals: crystals,
      message: message,
      damage: damage,
      storageError: s.storageError,
    );
  }

  double captureChance(RpgGame s) =>
      (0.25 +
              0.6 * (1 - s.enemyHp / s.creature!.health) -
              s.creature!.grade.index * 0.07)
          .clamp(0.1, 0.85);
}
