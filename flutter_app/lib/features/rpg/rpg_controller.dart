import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/app_state.dart';
import 'rpg_game.dart';

final rpgProvider = NotifierProvider<RpgController, RpgGame>(RpgController.new);

class RpgController extends Notifier<RpgGame> {
  static const storageKey = 'anajak.rpg.practice.v1';
  final engine = RpgEngine();
  @override
  RpgGame build() {
    final raw = ref.read(preferencesProvider).getString(storageKey);
    if (raw == null) return RpgGame();
    try {
      return RpgGame(
        progress: RpgProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      );
    } catch (_) {
      return RpgGame(storageError: true);
    }
  }

  void encounter(Biome biome) => state = engine.encounter(state, biome);
  Future<void> move(BattleMove move) async {
    final next = engine.move(state, move);
    if (identical(next, state)) return;
    final changed = !identical(next.progress, state.progress);
    state = next;
    if (changed) await save();
  }

  Future<void> save() async {
    if (state.busy) return;
    state = state.saving(busy: true, error: state.storageError);
    var ok = false;
    try {
      ok = await ref
          .read(preferencesProvider)
          .setString(storageKey, jsonEncode(state.progress.toJson()));
    } catch (_) {
      // Keep earned practice progress in memory and offer an explicit retry.
    }
    if (ref.mounted) state = state.saving(busy: false, error: !ok);
  }
}
