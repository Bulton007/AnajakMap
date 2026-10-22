import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'rpg_controller.dart';
import 'rpg_game.dart';

String rpgText(BuildContext context, String en, String km) =>
    Localizations.localeOf(context).languageCode == 'km' ? km : en;

class RpgEntry extends StatelessWidget {
  const RpgEntry({super.key});
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      minVerticalPadding: 16,
      leading: const Icon(Icons.auto_awesome),
      title: Text(
        rpgText(context, 'Creature trails', 'ដំណើរស្វែងរកសត្វវេទមន្ត'),
      ),
      subtitle: Text(
        rpgText(
          context,
          'Play the local RPG prototype',
          'សាកល្បងហ្គេម RPG នៅលើឧបករណ៍',
        ),
      ),
      trailing: const Icon(Icons.arrow_forward),
      onTap: () => context.push('/rpg'),
    ),
  );
}

class RpgScreen extends ConsumerWidget {
  const RpgScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = ref.watch(rpgProvider);
    final controller = ref.read(rpgProvider.notifier);
    String t(String en, String km) => rpgText(context, en, km);
    final c = game.creature;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Creature trails', 'ដំណើរស្វែងរកសត្វវេទមន្ត')),
        actions: [
          IconButton(
            tooltip: t('Account adventure', 'ដំណើរផ្សងព្រេងក្នុងគណនី'),
            onPressed: () => context.push('/adventure'),
            icon: const Icon(Icons.cloud_outlined),
          ),
          IconButton(
            tooltip: 'OpenStreetMap',
            onPressed: () => context.push('/map'),
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/adventure'),
                  icon: const Icon(Icons.cloud_outlined),
                  label: Text(
                    t('Open account adventure', 'បើកដំណើរផ្សងព្រេងក្នុងគណនី'),
                  ),
                ),
                Text(
                  t(
                    'A little magic along the way.',
                    'វេទមន្តតូចមួយនៅតាមដំណើរ។',
                  ),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  t(
                    'PRACTICE • Simulated locations. Progress stays on this device, shared by anyone using it. Gold has no cash value. No AI or GPS is used.',
                    'សាកល្បង • ទីតាំងក្លែងធ្វើ។ វឌ្ឍនភាពរក្សាទុកនៅឧបករណ៍នេះ និងចែករំលែកជាមួយអ្នកប្រើឧបករណ៍។ មាសគ្មានតម្លៃជាប្រាក់។ មិនប្រើ AI ឬ GPS ទេ។',
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.star_outline),
                      label: Text(
                        '${t('Level', 'កម្រិត')} ${game.progress.level}',
                      ),
                    ),
                    Chip(label: Text('${game.progress.xp} XP')),
                    Chip(
                      avatar: const Icon(Icons.toll),
                      label: Text('${game.progress.gold} ${t('gold', 'មាស')}'),
                    ),
                  ],
                ),
                if (game.storageError) ...[
                  Text(
                    t(
                      'Progress could not be restored or saved. Current rewards may be lost when you close the app.',
                      'មិនអាចស្ដារ ឬរក្សាទុកវឌ្ឍនភាពបានទេ។ រង្វាន់អាចបាត់បង់ពេលបិទកម្មវិធី។',
                    ),
                  ),
                  TextButton(
                    onPressed: game.busy ? null : controller.save,
                    child: Text(t('Retry saving', 'ព្យាយាមរក្សាទុកម្ដងទៀត')),
                  ),
                ],
                const SizedBox(height: 16),
                Text(
                  t('Choose a habitat', 'ជ្រើសរើសទីជម្រក'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                for (final biome in Biome.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: game.active || game.busy
                          ? null
                          : () => controller.encounter(biome),
                      icon: Icon(
                        biome == Biome.temple
                            ? Icons.account_balance
                            : Icons.beach_access,
                      ),
                      label: Text(
                        biome == Biome.temple
                            ? t(
                                'Temple grove · ancient guardians',
                                'ព្រៃប្រាសាទ · អ្នកការពារបុរាណ',
                              )
                            : t(
                                'Coral coast · ocean companions',
                                'ឆ្នេរផ្កាថ្ម · មិត្តសមុទ្រ',
                              ),
                      ),
                    ),
                  ),
                if (c == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      t(
                        'Choose a habitat to meet your first creature. Each encounter starts with full health, 3 spells and 3 capture crystals.',
                        'ជ្រើសទីជម្រកដើម្បីជួបសត្វដំបូង។ រាល់ការជួបមានសុខភាពពេញ វេទមន្ត ៣ និងគ្រីស្តាល់ចាប់ ៣។',
                      ),
                    ),
                  ),
                if (c != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            c.name,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Text(
                            '${_grade(context, c.grade)} · ${t('Level', 'កម្រិត')} ${c.level}',
                          ),
                          CreaturePortrait(creature: c),
                          _Health(
                            label: '${c.name} HP',
                            value: game.enemyHp,
                            max: c.health,
                          ),
                          const SizedBox(height: 12),
                          _Health(
                            label: t('Your health', 'សុខភាពអ្នក'),
                            value: game.playerHp,
                            max: 100,
                          ),
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              _message(context, game),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (game.phase == BattlePhase.won ||
                              game.phase == BattlePhase.captured)
                            Text(
                              '+${c.reward * 2} XP · +${c.reward} ${t('practice gold', 'មាសសាកល្បង')}',
                            ),
                          if (game.busy) ...[
                            const SizedBox(height: 8),
                            const LinearProgressIndicator(),
                          ],
                          if (game.active) ...[
                            const SizedBox(height: 16),
                            Text(
                              t(
                                'The creature responds after every strike, spell or missed capture. Lower its health to improve capture odds.',
                                'សត្វវាយតបក្រោយការវាយ វេទមន្ត ឬចាប់មិនបាន។ បន្ថយសុខភាពវាដើម្បីបង្កើនឱកាសចាប់។',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _Move(
                                  label: t('Strike', 'វាយ'),
                                  icon: Icons.flash_on,
                                  onPressed: () =>
                                      controller.move(BattleMove.strike),
                                ),
                                _Move(
                                  label:
                                      '${t('Magic', 'វេទមន្ត')} (${game.mana}/3)',
                                  icon: Icons.auto_awesome,
                                  onPressed: game.mana == 0
                                      ? null
                                      : () => controller.move(BattleMove.magic),
                                ),
                                _Move(
                                  label:
                                      '${t('Capture', 'ចាប់')} (${game.crystals}/3) · ${(controller.engine.captureChance(game) * 100).round()}%',
                                  icon: Icons.diamond_outlined,
                                  onPressed: game.crystals == 0
                                      ? null
                                      : () =>
                                            controller.move(BattleMove.capture),
                                ),
                                _Move(
                                  label: t('Leave safely', 'ចាកចេញ'),
                                  icon: Icons.directions_walk,
                                  onPressed: () =>
                                      controller.move(BattleMove.flee),
                                ),
                              ],
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                t(
                                  'Choose either habitat above for another encounter.',
                                  'ជ្រើសទីជម្រកខាងលើដើម្បីជួបម្ដងទៀត។',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  '${t('Your collection', 'បណ្ដុំរបស់អ្នក')} · ${game.progress.collection.length}/${creatures.length}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  t(
                    'Capture creatures to collect them. Winning a battle gives XP and gold; it does not capture the creature.',
                    'ចាប់សត្វដើម្បីប្រមូល។ ឈ្នះការប្រយុទ្ធទទួល XP និងមាស ប៉ុន្តែមិនចាប់សត្វទេ។',
                  ),
                ),
                const SizedBox(height: 12),
                for (final creature in creatures)
                  Card(
                    child: ListTile(
                      minVerticalPadding: 12,
                      leading: Icon(
                        game.progress.collection.containsKey(creature.id)
                            ? Icons.pets
                            : Icons.lock_outline,
                      ),
                      title: Text(creature.name),
                      subtitle: Text(
                        '${_grade(context, creature.grade)} · ${creature.biome == Biome.temple ? t('Temple', 'ប្រាសាទ') : t('Beach', 'ឆ្នេរ')}',
                      ),
                      trailing: Text(
                        '×${game.progress.collection[creature.id] ?? 0}',
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  t(
                    'Original 2D concept art for this prototype. Animated 3D creatures and verified location rewards are planned separately.',
                    'រូបភាពគំនិត 2D សម្រាប់ការសាកល្បង។ សត្វ 3D មានចលនា និងរង្វាន់ទីតាំងពិតនឹងអភិវឌ្ឍបន្ថែម។',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Move extends StatelessWidget {
  const _Move({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    onPressed: onPressed,
    icon: Icon(icon),
    label: Text(label),
  );
}

class _Health extends StatelessWidget {
  const _Health({required this.label, required this.value, required this.max});
  final String label;
  final int value, max;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label · $value/$max'),
      const SizedBox(height: 4),
      LinearProgressIndicator(
        value: value / max,
        minHeight: 8,
        semanticsLabel: label,
      ),
    ],
  );
}

String _grade(BuildContext context, Grade grade) => switch (grade) {
  Grade.common => rpgText(context, 'Common', 'ធម្មតា'),
  Grade.rare => rpgText(context, 'Rare', 'កម្រ'),
  Grade.epic => rpgText(context, 'Epic', 'អស្ចារ្យ'),
};

String _message(BuildContext c, RpgGame game) {
  String t(String en, String km) => rpgText(c, en, km);
  return switch (game.message) {
    'encounter' => t(
      'A wild companion appears!',
      'មិត្តព្រៃមួយបានបង្ហាញខ្លួន!',
    ),
    'strike' => t(
      'Your strike dealt ${game.damage} damage. The creature struck back.',
      'អ្នកវាយបាន ${game.damage}។ សត្វបានវាយតប។',
    ),
    'magicHit' => t(
      'Your spell dealt ${game.damage} damage. The creature struck back.',
      'វេទមន្តវាយបាន ${game.damage}។ សត្វបានវាយតប។',
    ),
    'captureMiss' => t(
      'It escaped the crystal and struck back!',
      'វាគេចពីគ្រីស្តាល់ ហើយវាយតប!',
    ),
    'captured' => t(
      'Captured! A new companion joins your collection.',
      'ចាប់បាន! មិត្តថ្មីចូលបណ្ដុំរបស់អ្នក។',
    ),
    'won' => t(
      'Victory! The creature retreats into its habitat.',
      'ឈ្នះ! សត្វបានត្រឡប់ទៅទីជម្រក។',
    ),
    'escaped' => t(
      'You left safely. No rewards earned.',
      'អ្នកចាកចេញដោយសុវត្ថិភាព។ គ្មានរង្វាន់។',
    ),
    'lost' => t(
      'Time to rest. Try another encounter with full health.',
      'ដល់ពេលសម្រាក។ សាកជួបម្ដងទៀតជាមួយសុខភាពពេញ។',
    ),
    _ => '',
  };
}

/// Original vector concept art, deliberately labelled 2D rather than AR/3D.
class CreaturePortrait extends StatelessWidget {
  const CreaturePortrait({super.key, required this.creature});
  final Creature creature;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: creature.name,
    child: SizedBox(
      height: 230,
      width: double.infinity,
      child: CustomPaint(painter: _CreaturePainter(creature)),
    ),
  );
}

class _CreaturePainter extends CustomPainter {
  _CreaturePainter(this.creature);
  final Creature creature;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    final scale = math.min(size.width / 280, size.height / 230);
    canvas.scale(scale);
    final color = HSLColor.fromAHSL(
      1,
      creature.hue.toDouble(),
      .55,
      .58,
    ).toColor();
    final paint = Paint();
    canvas.drawCircle(
      Offset.zero,
      95,
      paint..color = color.withValues(alpha: .12),
    );
    canvas.drawOval(
      const Rect.fromLTWH(-68, 80, 136, 15),
      paint..color = Colors.black.withValues(alpha: .12),
    );
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawCircle(
        Offset(math.cos(a) * 100, math.sin(a) * 90),
        2 + i % 3.0,
        paint..color = const Color(0xffc69b48),
      );
    }
    final sea = creature.biome == Biome.beach;
    for (final side in [-1.0, 1.0]) {
      final fin = Path()
        ..moveTo(side * 40, -20)
        ..quadraticBezierTo(side * 110, sea ? -70 : -90, side * 70, 32)
        ..lineTo(side * 32, 30)
        ..close();
      canvas.drawPath(fin, paint..color = color);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(side * 38, 72), width: 40, height: 25),
        paint,
      );
    }
    final body = const Rect.fromLTWH(-63, -60, 126, 140);
    paint.shader = RadialGradient(
      colors: [
        Color.lerp(color, Colors.white, .55)!,
        color,
        Color.lerp(color, const Color(0xff0c2926), .55)!,
      ],
      center: const Alignment(-.4, -.6),
      radius: 1.2,
    ).createShader(body);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, Radius.circular(sea ? 65 : 40)),
      paint,
    );
    paint.shader = null;
    for (final side in [-1.0, 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(side * 24, -12), width: 20, height: 26),
        paint..color = const Color(0xff0c2926),
      );
      canvas.drawCircle(
        Offset(side * 24 - 3, -17),
        4,
        paint..color = Colors.white,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(side * 36, 10), width: 17, height: 8),
        paint..color = const Color(0xffefb1a7),
      );
    }
    canvas.drawArc(
      const Rect.fromLTWH(-10, 10, 20, 14),
      0,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xff0c2926)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final crown = Path()
      ..moveTo(-25, -53)
      ..lineTo(-32, -85)
      ..lineTo(-8, -71)
      ..lineTo(0, -99)
      ..lineTo(12, -72)
      ..lineTo(32, -85)
      ..lineTo(24, -53)
      ..close();
    canvas.drawPath(crown, paint..color = const Color(0xfff8db9b));
    for (var i = 0; i <= creature.grade.index; i++) {
      canvas.drawCircle(
        Offset((i - creature.grade.index / 2) * 18, 47),
        5,
        paint..color = const Color(0xfff8db9b),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CreaturePainter oldDelegate) =>
      oldDelegate.creature != creature;
}
