import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import 'rpg_game.dart';
import 'rpg_screen.dart';

/// Original procedural meshes, perspective projection and depth-sorted triangles.
/// This renderer is deliberately separate from combat; it never predicts outcomes.
class BattleScene extends StatefulWidget {
  const BattleScene({super.key, required this.session});
  final Json session;
  @override
  State<BattleScene> createState() => _BattleSceneState();
}

class _BattleSceneState extends State<BattleScene>
    with TickerProviderStateMixin {
  late final AnimationController idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  late final AnimationController effect = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool fallback = false, low = true, motion = true;
  double yaw = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motion();
  }

  void _motion() {
    if (motion && !fallback && !MediaQuery.disableAnimationsOf(context)) {
      idle.repeat();
    } else {
      idle.stop();
      effect.stop();
    }
  }

  @override
  void didUpdateWidget(covariant BattleScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session['revision'] != widget.session['revision'] &&
        motion &&
        !MediaQuery.disableAnimationsOf(context)) {
      effect.forward(from: 0);
    }
  }

  @override
  void dispose() {
    idle.dispose();
    effect.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final battle = object(widget.session['battle']);
    final enemy = object(battle['enemy']), ally = object(battle['ally']);
    final creature = creatures
        .where((c) => c.id == string(enemy, 'speciesId'))
        .firstOrNull;
    final useFallback = fallback || creature == null;
    return Column(
      children: [
        Semantics(
          image: true,
          label:
              '${string(enemy, 'speciesId')} ${widget.session['status']} — procedural 3D battle scene',
          child: RepaintBoundary(
            child: SizedBox(
              height: 260,
              width: double.infinity,
              child: useFallback
                  ? creature == null
                        ? const Center(child: Icon(Icons.pets, size: 80))
                        : CreaturePortrait(creature: creature)
                  : GestureDetector(
                      onHorizontalDragUpdate: (d) => setState(
                        () => yaw = (yaw + d.delta.dx / 160).clamp(-.7, .7),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedBuilder(
                          animation: Listenable.merge([idle, effect]),
                          builder: (_, _) => CustomPaint(
                            painter: _ScenePainter(
                              ally,
                              enemy,
                              string(widget.session, 'status'),
                              idle.value,
                              effect.value,
                              yaw,
                              low,
                              creature.biome == Biome.beach,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        Text(
          rpgText(
            context,
            useFallback
                ? '2D fallback artwork'
                : 'Procedural 3D • temporary original models • drag to orbit',
            useFallback
                ? 'រូបភាពជំនួស 2D'
                : '3D បង្កើតដោយកូដ • ម៉ូដែលបណ្ដោះអាសន្ន • អូសដើម្បីបង្វិល',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: Text(rpgText(context, '2D fallback', 'ជំនួស 2D')),
              selected: fallback,
              onSelected: (v) {
                setState(() => fallback = v);
                _motion();
              },
            ),
            FilterChip(
              label: Text(rpgText(context, 'Low detail', 'លម្អិតទាប')),
              selected: low,
              onSelected: (v) => setState(() => low = v),
            ),
            FilterChip(
              label: Text(rpgText(context, 'Motion', 'ចលនា')),
              selected: motion,
              onSelected: (v) {
                setState(() => motion = v);
                _motion();
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _V {
  const _V(this.x, this.y, this.z);
  final double x, y, z;
  _V operator +(_V b) => _V(x + b.x, y + b.y, z + b.z);
  _V operator -(_V b) => _V(x - b.x, y - b.y, z - b.z);
  _V cross(_V b) => _V(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x);
  double get length => math.sqrt(x * x + y * y + z * z);
}

class _Face {
  const _Face(this.a, this.b, this.c, this.color);
  final _V a, b, c;
  final Color color;
  double get depth => (a.z + b.z + c.z) / 3;
}

class _ScenePainter extends CustomPainter {
  _ScenePainter(
    this.ally,
    this.enemy,
    this.status,
    this.time,
    this.effect,
    this.yaw,
    this.low,
    this.beach,
  );
  final Json ally, enemy;
  final String status;
  final double time, effect, yaw;
  final bool low, beach;
  final faces = <_Face>[];
  _V rotate(_V p) => _V(
    p.x * math.cos(yaw) + p.z * math.sin(yaw),
    p.y,
    -p.x * math.sin(yaw) + p.z * math.cos(yaw),
  );
  Offset project(_V p, Size size) {
    final scale = size.shortestSide * 1.7 / (p.z + 6);
    return Offset(
      size.width / 2 + p.x * scale,
      size.height * .72 - p.y * scale,
    );
  }

  void triangle(_V a, _V b, _V c, Color color) =>
      faces.add(_Face(rotate(a), rotate(b), rotate(c), color));
  void sphere(_V center, _V radii, Color color, {int? rings, int? segments}) {
    final r = rings ?? (low ? 4 : 7), s = segments ?? (low ? 7 : 12);
    _V vertex(int i, int j) {
      final p = math.pi * i / r, a = math.pi * 2 * j / s;
      return center +
          _V(
            radii.x * math.sin(p) * math.cos(a),
            radii.y * math.cos(p),
            radii.z * math.sin(p) * math.sin(a),
          );
    }

    for (var i = 0; i < r; i++) {
      for (var j = 0; j < s; j++) {
        final a = vertex(i, j),
            b = vertex(i + 1, j),
            c = vertex(i + 1, j + 1),
            d = vertex(i, j + 1);
        triangle(a, b, c, color);
        triangle(a, c, d, color);
      }
    }
  }

  void spike(_V base, double width, double height, Color color) {
    final tip = base + _V(0, height, 0);
    final a = base + _V(-width, 0, -width),
        b = base + _V(width, 0, -width),
        c = base + _V(width, 0, width),
        d = base + _V(-width, 0, width);
    triangle(a, b, tip, color);
    triangle(b, c, tip, color);
    triangle(c, d, tip, color);
    triangle(d, a, tip, color);
  }

  void monster(Json fighter, _V at, double size, bool wild) {
    final id = string(fighter, 'speciesId');
    final concept = creatures.where((c) => c.id == id).firstOrNull;
    final color = HSVColor.fromAHSV(
      1,
      (concept?.hue ?? 150).toDouble(),
      .5,
      .85,
    ).toColor();
    final evolution = integer(fighter, 'evolution');
    final bob = math.sin(time * math.pi * 2 + (wild ? 0 : 2)) * .045;
    final pulse = math.sin(effect * math.pi);
    final alive = integer(fighter, 'hp') > 0;
    final captured = wild && status == 'captured';
    final scale = size * (captured ? .22 : 1) * (1 + evolution * .09);
    final position =
        at + _V(wild ? pulse * .07 : pulse * .12, alive ? bob : -.25, 0);
    _V p(double x, double y, double z) =>
        position + _V(x * scale, y * scale, z * scale);
    sphere(
      p(0, .55, 0),
      _V(.46 * scale, (alive ? .55 : .22) * scale, .38 * scale),
      color,
    );
    sphere(
      p(0, 1.13, -.08),
      _V(.39 * scale, .32 * scale, .32 * scale),
      Color.lerp(color, Colors.white, .12)!,
    );
    for (final side in [-1.0, 1.0]) {
      sphere(
        p(side * .2, .13, -.12),
        _V(.16 * scale, .12 * scale, .23 * scale),
        color,
      );
      sphere(
        p(side * .15, 1.19, -.36),
        _V(.08 * scale, .09 * scale, .035 * scale),
        Colors.white,
        rings: 3,
        segments: 6,
      );
      sphere(
        p(side * .15, 1.19, -.39),
        _V(.035 * scale, .05 * scale, .02 * scale),
        const Color(0xff102f35),
        rings: 3,
        segments: 5,
      );
      if (id == 'amberhorn' || id == 'coralclaw') {
        spike(
          p(side * .23, 1.35, 0),
          .11 * scale,
          .4 * scale,
          const Color(0xffffd986),
        );
      } else if (id == 'moonwarden' || id == 'tidewing') {
        triangle(
          p(side * .35, .9, 0),
          p(side * (.95 + .08 * math.sin(time * math.pi * 2)), 1.2, .1),
          p(side * .6, .45, .1),
          Color.lerp(color, Colors.white, .3)!,
        );
        triangle(
          p(side * .35, .9, 0),
          p(side * .6, .45, .1),
          p(side * .48, .45, -.1),
          color,
        );
      } else {
        spike(
          p(side * .2, 1.35, .05),
          .1 * scale,
          .25 * scale,
          Color.lerp(color, const Color(0xffa4d378), .5)!,
        );
      }
    }
    if (evolution > 0) {
      spike(p(0, 1.4, 0), .13 * scale, .25 * scale, const Color(0xffffd986));
    }
    if (evolution > 1) {
      sphere(
        p(0, .7, -.38),
        _V(.12 * scale, .14 * scale, .06 * scale),
        const Color(0xffffdf92),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    faces.clear();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: beach
              ? const [Color(0xff5fbdcf), Color(0xffe8d9b4)]
              : const [Color(0xff172c35), Color(0xff547b67)],
        ).createShader(Offset.zero & size),
    );
    triangle(
      const _V(-5, -.1, -3),
      const _V(5, -.1, 7),
      const _V(5, -.1, -3),
      beach ? const Color(0xffd6c59b) : const Color(0xff304f40),
    );
    triangle(
      const _V(-5, -.1, -3),
      const _V(-5, -.1, 7),
      const _V(5, -.1, 7),
      beach ? const Color(0xffd6c59b) : const Color(0xff304f40),
    );
    if (!beach) {
      for (final x in [-2.4, 0.0, 2.4]) {
        spike(_V(x, 0, 3), .6, 2.6, const Color(0xff607368));
        sphere(_V(x, 1, 3), const _V(.45, .9, .4), const Color(0xff718174));
      }
    }
    monster(ally, const _V(-1.05, 0, -.1), .82, false);
    monster(enemy, const _V(.85, 0, .9), 1.03, true);
    faces.sort((a, b) => b.depth.compareTo(a.depth));
    for (final face in faces) {
      final normal = (face.b - face.a).cross(face.c - face.a),
          length = normal.length;
      if (length < .00001) continue;
      final light =
          (.65 + (normal.y * .55 - normal.x * .25 - normal.z * .3) / length)
              .clamp(.32, 1.0);
      final base = face.color;
      final shade = Color.fromARGB(
        255,
        (base.r * 255 * light).round(),
        (base.g * 255 * light).round(),
        (base.b * 255 * light).round(),
      );
      final a = project(face.a, size),
          b = project(face.b, size),
          c = project(face.c, size);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy)
          ..lineTo(c.dx, c.dy)
          ..close(),
        Paint()..color = shade,
      );
    }
    if (effect > 0 && effect < 1) {
      for (var i = 0; i < 10; i++) {
        final angle = i * math.pi / 5;
        canvas.drawCircle(
          Offset(
            size.width * .65 + math.cos(angle) * effect * 60,
            size.height * .45 + math.sin(angle) * effect * 60,
          ),
          3 * (1 - effect),
          Paint()..color = const Color(0xffffdb9b),
        );
      }
    }
    if (status == 'captured') {
      canvas.drawCircle(
        project(rotate(const _V(.85, .4, .9)), size),
        28,
        Paint()
          ..color = const Color(0xffffdb9b)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.time != time ||
      old.effect != effect ||
      old.yaw != yaw ||
      old.low != low ||
      old.ally != ally ||
      old.enemy != enemy ||
      old.status != status;
}
