import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import 'rpg_game.dart';
import 'rpg_screen.dart';
import 'creature_catalog.dart';

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
              '${creatureDisplayName(string(enemy, 'speciesId'), language: Localizations.localeOf(context).languageCode)} ${widget.session['status']} — 3D battle scene',
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
            useFallback ? 'Illustrated view' : 'Drag to look around',
            useFallback ? 'ទិដ្ឋភាពរូបគំនូរ' : 'អូសដើម្បីមើលជុំវិញ',
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
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
    final concept =
        creatureConcept(string(fighter, 'speciesId')) ?? creatureConcepts.first;
    final color = Color(concept.color), accent = Color(concept.accent);
    final dark = Color.lerp(color, const Color(0xff153c35), .32)!;
    final light = Color.lerp(color, Colors.white, .25)!;
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
    void ball(
      double x,
      double y,
      double z,
      double rx,
      double ry,
      double rz,
      Color c, {
      bool small = false,
    }) {
      sphere(
        p(x, y, z),
        _V(rx * scale, ry * scale, rz * scale),
        c,
        rings: small ? 3 : null,
        segments: small ? 6 : null,
      );
    }

    void face(double x, double y, double z, {double spread = .13}) {
      for (final side in [-1.0, 1.0]) {
        ball(
          x + side * spread,
          y,
          z,
          .065,
          .08,
          .04,
          Colors.white,
          small: true,
        );
        ball(
          x + side * spread,
          y - .005,
          z - .035,
          .031,
          .045,
          .018,
          const Color(0xff143b35),
          small: true,
        );
        ball(
          x + side * spread - .012,
          y + .018,
          z - .05,
          .012,
          .016,
          .009,
          Colors.white,
          small: true,
        );
      }
      ball(x, y - .12, z - .02, .035, .025, .02, accent, small: true);
    }

    void fin(
      double side,
      double rootY,
      double tipX,
      double tipY,
      double depth,
      Color c,
    ) {
      triangle(
        p(side * .23, rootY, depth),
        p(side * tipX, tipY, depth + .06),
        p(side * .47, rootY - .35, depth),
        c,
      );
      triangle(
        p(side * .23, rootY, depth),
        p(side * .47, rootY - .35, depth),
        p(side * .32, rootY - .25, depth - .1),
        dark,
      );
    }

    switch (concept.design) {
      case CreatureDesign.snake:
        // Coiled body and broad cobra-like fan; no arms or legs.
        ball(0, .17, .1, .62, .16, .42, dark);
        ball(.2, .28, .1, .43, .13, .31, color);
        ball(-.18, .38, 0, .33, .13, .23, color);
        ball(0, .72, -.02, .18, .43, .2, color);
        ball(0, .76, -.19, .11, .32, .055, accent);
        triangle(p(0, .78, .05), p(-.57, 1.15, .03), p(-.35, 1.65, .06), dark);
        triangle(p(0, .78, .05), p(.35, 1.65, .06), p(.57, 1.15, .03), dark);
        triangle(
          p(-.1, .85, -.01),
          p(-.47, 1.15, -.02),
          p(-.3, 1.5, -.01),
          accent,
        );
        triangle(
          p(.1, .85, -.01),
          p(.3, 1.5, -.01),
          p(.47, 1.15, -.02),
          accent,
        );
        ball(0, 1.27, -.13, .27, .31, .22, light);
        face(0, 1.31, -.35, spread: .11);
        for (final x in [-.13, 0.0, .13]) {
          spike(
            p(x, 1.53, -.1),
            .07 * scale,
            (x == 0 ? 0.22 : 0.15) * scale,
            accent,
          );
        }
      case CreatureDesign.lion:
        // Rounded guardian cub, scalloped mane, four paws and curled tail.
        ball(0, .49, .03, .4, .44, .34, color);
        for (final side in [-1.0, 1.0]) {
          ball(side * .28, .12, -.2, .18, .13, .22, light);
          ball(side * .3, .18, .24, .15, .14, .17, dark);
        }
        for (var i = 0; i < 10; i++) {
          final angle = i * math.pi / 5;
          ball(
            math.sin(angle) * .36,
            1.12 + math.cos(angle) * .34,
            .015,
            .19,
            .19,
            .2,
            dark,
            small: true,
          );
        }
        ball(0, 1.14, -.14, .32, .31, .28, color);
        ball(0, .99, -.36, .23, .14, .07, accent);
        for (final side in [-1.0, 1.0]) {
          ball(side * .26, 1.4, -.15, .12, .13, .1, accent, small: true);
        }
        face(0, 1.2, -.4);
        for (var i = 0; i < 9; i++) {
          final angle = i * math.pi / 6;
          ball(
            .5 + .15 * math.cos(angle),
            .54 + .23 * math.sin(angle),
            .21,
            .065,
            .07,
            .07,
            color,
            small: true,
          );
        }
        ball(.51, .34, .21, .12, .11, .11, accent, small: true);
      case CreatureDesign.bird:
        // Broad layered feather fans, a beak, talons and a long tail.
        for (final side in [-1.0, 1.0]) {
          for (var feather = 0; feather < 4; feather++) {
            fin(
              side,
              .94 - feather * .04,
              1.05 - feather * .13,
              1.35 - feather * .2,
              .08 + feather * .02,
              feather.isEven ? color : light,
            );
          }
          ball(side * .16, .12, -.1, .15, .07, .19, accent, small: true);
        }
        for (final x in [-.2, 0.0, .2]) {
          triangle(
            p(x, .4, .15),
            p(x * .7, .06, .49),
            p(x + .12, .35, .22),
            dark,
          );
        }
        ball(0, .63, 0, .3, .44, .26, color);
        ball(0, .65, -.22, .21, .29, .065, light);
        ball(0, 1.21, -.05, .29, .3, .25, color);
        face(0, 1.25, -.31, spread: .12);
        triangle(
          p(-.1, 1.13, -.31),
          p(0, .96, -.51),
          p(.1, 1.13, -.31),
          accent,
        );
        for (final side in [-1.0, 1.0]) {
          spike(p(side * .18, 1.43, .01), .08 * scale, .26 * scale, accent);
        }
      case CreatureDesign.makara:
        // Low aquatic body, curling elephant-like snout and swept fin tail.
        ball(.06, .45, .05, .59, .29, .32, color);
        ball(-.36, .88, -.04, .31, .27, .25, light);
        face(-.36, .93, -.31, spread: .12);
        for (var i = 0; i < 9; i++) {
          final angle = i * math.pi / 7;
          ball(
            -.65 - .17 * math.sin(angle),
            .68 + .19 * math.cos(angle),
            -.22,
            .095,
            .09,
            .09,
            color,
            small: true,
          );
        }
        for (final side in [-1.0, 1.0]) {
          ball(side * .38, .15, -.12, .22, .08, .17, accent, small: true);
        }
        triangle(p(.47, .4, .05), p(.97, 1.1, .1), p(.78, .39, .08), color);
        triangle(p(.47, .4, .05), p(.78, .39, .08), p(1.0, .14, .12), light);
        for (var i = 0; i < 4; i++) {
          spike(p(-.15 + i * .19, .71, .06), .08 * scale, .2 * scale, accent);
        }
      case CreatureDesign.turtle:
        // Flat domed shell, small head, four broad flippers and shell panels.
        for (final side in [-1.0, 1.0]) {
          for (final depth in [-.3, .3]) {
            ball(side * .53, .19, depth, .26, .065, .17, color, small: true);
          }
        }
        ball(0, .42, .02, .58, .27, .53, dark);
        ball(0, .51, .02, .49, .23, .45, color);
        ball(0, .5, -.56, .23, .2, .23, light);
        face(0, .54, -.78, spread: .1);
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3, b = (i + 1) * math.pi / 3;
          triangle(
            p(0, .755, 0),
            p(math.cos(a) * .31, .69, math.sin(a) * .28),
            p(math.cos(b) * .31, .69, math.sin(b) * .28),
            i.isEven ? accent : light,
          );
        }
        spike(p(0, .46, .48), .07 * scale, .15 * scale, accent);
      case CreatureDesign.monkey:
        // Long curling tail, round ears, cheek mask and separate arms.
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          ball(
            -.49 + .19 * math.cos(a),
            .69 + .28 * math.sin(a),
            .22,
            .065,
            .065,
            .065,
            color,
            small: true,
          );
        }
        ball(0, .53, .03, .3, .4, .27, color);
        ball(0, .53, -.23, .17, .27, .055, accent);
        for (final side in [-1.0, 1.0]) {
          ball(side * .4, .58, .02, .12, .3, .12, color);
          ball(side * .42, .35, -.04, .13, .07, .13, accent, small: true);
          ball(side * .21, .12, -.08, .17, .1, .21, light, small: true);
          ball(side * .36, 1.15, -.04, .17, .18, .11, color, small: true);
          ball(side * .36, 1.15, -.13, .1, .11, .04, accent, small: true);
        }
        ball(0, 1.15, -.05, .32, .34, .28, color);
        ball(0, 1.13, -.25, .27, .26, .1, const Color(0xfff4e4c6));
        face(0, 1.18, -.36, spread: .12);
        ball(0, 1.43, -.05, .3, .035, .26, accent, small: true);
        spike(p(0, 1.44, -.05), .09 * scale, .16 * scale, accent);
    }
    if (evolution > 0) {
      ball(0, .67, -.4, .09, .12, .045, accent, small: true);
    }
    if (evolution > 1) {
      for (final side in [-1.0, 1.0]) {
        ball(side * .18, .67, -.34, .04, .065, .035, accent, small: true);
      }
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
