import 'dart:math';

/// Foreground opt-in checks only. Server still owns proximity and reward rules.
class EncounterPolicy {
  EncounterPolicy({
    Random? random,
    this.probability = .25,
    this.cooldown = const Duration(minutes: 5),
  }) : random = random ?? Random.secure() {
    if (!probability.isFinite ||
        probability < 0 ||
        probability > 1 ||
        cooldown.isNegative) {
      throw ArgumentError('Invalid encounter policy');
    }
  }
  final Random random;
  final double probability;
  final Duration cooldown;
  DateTime? nextCheck;
  bool roll(DateTime now, {required bool eligible}) {
    if (!eligible || (nextCheck?.isAfter(now) ?? false)) return false;
    // Consume the check even on a miss; GPS updates never generate repeated rolls.
    nextCheck = now.add(cooldown);
    return random.nextDouble() < probability;
  }
}
