import 'package:flutter/material.dart';
import 'rpg_game.dart';
import 'rpg_screen.dart';

class CreatureAvatar extends StatelessWidget {
  const CreatureAvatar({super.key, required this.speciesId});
  final String speciesId;
  @override
  Widget build(BuildContext context) {
    final species = creatures.where((c) => c.id == speciesId).firstOrNull;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 56,
          height: 56,
          child: species == null
              ? const Icon(Icons.pets_rounded)
              : FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: 180,
                    height: 180,
                    child: CreaturePortrait(creature: species),
                  ),
                ),
        ),
      ),
    );
  }
}
