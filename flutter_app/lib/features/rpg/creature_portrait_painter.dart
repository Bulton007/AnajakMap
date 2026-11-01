import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'creature_catalog.dart';
import 'rpg_game.dart';

/// Original vector characters. Each family has its own silhouette and anatomy.
class KhmerCreaturePainter extends CustomPainter {
  KhmerCreaturePainter(this.creature);
  final Creature creature;
  static const ink = Color(0xff153c35), gold = Color(0xfff6d38b);
  final brush = Paint()..isAntiAlias = true;
  late Canvas canvas;
  late Color body, accent;

  void oval(Rect rect, Color color, {bool shade = true}) {
    brush
      ..style = PaintingStyle.fill
      ..color = color
      ..shader = shade
          ? RadialGradient(
              colors: [
                Color.lerp(color, Colors.white, .35)!,
                color,
                Color.lerp(color, ink, .24)!,
              ],
              center: const Alignment(-.4, -.7),
              radius: 1.3,
            ).createShader(rect)
          : null;
    canvas.drawOval(rect, brush);
    brush.shader = null;
  }

  void shape(Path path, Color color) {
    brush
      ..style = PaintingStyle.fill
      ..color = color
      ..shader = null;
    canvas.drawPath(path, brush);
  }

  void stroke(Path path, Color color, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void eyes(Offset center, {double spread = 17, double size = 8}) {
    for (final side in [-1.0, 1.0]) {
      final point = center + Offset(spread * side, 0);
      oval(
        Rect.fromCenter(center: point, width: size * 1.6, height: size * 2),
        ink,
        shade: false,
      );
      oval(
        Rect.fromCircle(center: point + Offset(-2, -3), radius: size * .29),
        Colors.white,
        shade: false,
      );
      oval(
        Rect.fromCenter(
          center: point + Offset(side * 8, 14),
          width: 12,
          height: 5,
        ),
        const Color(0xffeeb2a3),
        shade: false,
      );
    }
    stroke(
      Path()
        ..moveTo(center.dx - 7, center.dy + 17)
        ..quadraticBezierTo(
          center.dx,
          center.dy + 25,
          center.dx + 7,
          center.dy + 17,
        ),
      ink,
      2.4,
    );
  }

  void lotus(Offset center, double radius) {
    for (final angle in [-.7, -.35, 0.0, .35, .7]) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      shape(
        Path()
          ..moveTo(0, 4)
          ..quadraticBezierTo(-radius * .65, -radius * .55, 0, -radius)
          ..quadraticBezierTo(radius * .65, -radius * .55, 0, 4)
          ..close(),
        accent,
      );
      canvas.restore();
    }
    oval(Rect.fromCenter(center: center, width: radius * 1.5, height: 7), body);
  }

  void snake() {
    final tail = Path()
      ..moveTo(13, 23)
      ..cubicTo(86, 16, 101, 76, 22, 77)
      ..cubicTo(-59, 88, -83, 55, -46, 43)
      ..cubicTo(-8, 31, 31, 55, 2, 61);
    stroke(tail, Color.lerp(body, ink, .18)!, 33);
    stroke(tail, body, 25);
    final neck = Path()
      ..moveTo(-20, 47)
      ..cubicTo(-41, 9, -39, -20, -19, -38)
      ..lineTo(20, -35)
      ..cubicTo(39, -1, 30, 23, 20, 46)
      ..close();
    shape(neck, body);
    shape(
      Path()
        ..moveTo(0, 10)
        ..cubicTo(-84, -7, -74, -73, -34, -72)
        ..quadraticBezierTo(0, -111, 34, -72)
        ..cubicTo(74, -73, 84, -7, 0, 10)
        ..close(),
      Color.lerp(body, ink, .13)!,
    );
    for (final side in [-1.0, 1.0]) {
      stroke(
        Path()
          ..moveTo(side * 13, -8)
          ..quadraticBezierTo(side * 58, -36, side * 35, -65),
        accent,
        4,
      );
    }
    oval(const Rect.fromLTWH(-35, -64, 70, 70), body);
    oval(const Rect.fromLTWH(-12, 4, 24, 42), accent);
    for (var i = 0; i < 4; i++) {
      stroke(
        Path()
          ..moveTo(-8, 10 + i * 8.0)
          ..lineTo(8, 10 + i * 8.0),
        body,
        2,
      );
    }
    eyes(const Offset(0, -36), spread: 15, size: 7);
    lotus(const Offset(0, -66), 24);
  }

  void lion() {
    stroke(
      Path()
        ..moveTo(28, 51)
        ..cubicTo(83, 75, 88, 9, 64, 8)
        ..cubicTo(45, 4, 48, 33, 69, 27),
      body,
      12,
    );
    oval(const Rect.fromLTWH(60, 0, 25, 28), accent);
    oval(const Rect.fromLTWH(-39, 3, 78, 75), body);
    for (final side in [-1.0, 1.0]) {
      oval(
        Rect.fromCenter(center: Offset(side * 31, 72), width: 42, height: 24),
        body,
      );
    }
    final mane = Path();
    for (var i = 0; i <= 48; i++) {
      final a = i / 48 * math.pi * 2;
      final r = i.isEven ? 62.0 : 54.0;
      final p = Offset(math.sin(a) * r, -26 + math.cos(a) * r);
      if (i == 0) {
        mane.moveTo(p.dx, p.dy);
      } else {
        mane.lineTo(p.dx, p.dy);
      }
    }
    shape(mane..close(), Color.lerp(body, const Color(0xffa86637), .4)!);
    for (final side in [-1.0, 1.0]) {
      oval(Rect.fromCircle(center: Offset(side * 32, -52), radius: 15), accent);
      stroke(
        Path()
          ..moveTo(side * 45, -17)
          ..cubicTo(side * 73, -40, side * 39, -64, side * 39, -39),
        accent,
        4,
      );
    }
    oval(const Rect.fromLTWH(-39, -65, 78, 77), body);
    oval(const Rect.fromLTWH(-25, -17, 50, 29), accent);
    eyes(const Offset(0, -34), spread: 16, size: 7);
    shape(
      Path()
        ..moveTo(-7, -12)
        ..lineTo(7, -12)
        ..lineTo(0, -5)
        ..close(),
      ink,
    );
    lotus(const Offset(0, -66), 17);
    oval(Rect.fromCircle(center: const Offset(0, 35), radius: 9), accent);
  }

  void bird() {
    for (final side in [-1.0, 1.0]) {
      for (var i = 0; i < 5; i++) {
        shape(
          Path()
            ..moveTo(side * 24, 4)
            ..quadraticBezierTo(
              side * (75 + i * 7),
              -85 + i * 18.0,
              side * (105 - i * 8),
              -48 + i * 22.0,
            )
            ..quadraticBezierTo(side * 68, 41, side * 24, 41)
            ..close(),
          Color.lerp(
            body,
            i.isEven ? Colors.white : ink,
            i.isEven ? .18 : .12,
          )!,
        );
        stroke(
          Path()
            ..moveTo(side * 31, 16)
            ..lineTo(side * (89 - i * 7), -39 + i * 19.0),
          accent,
          2,
        );
      }
      oval(
        Rect.fromCenter(center: Offset(side * 17, 76), width: 28, height: 15),
        accent,
      );
    }
    oval(const Rect.fromLTWH(-35, -7, 70, 83), body);
    oval(
      const Rect.fromLTWH(-22, 10, 44, 56),
      Color.lerp(body, Colors.white, .45)!,
    );
    oval(const Rect.fromLTWH(-36, -66, 72, 73), body);
    for (final side in [-1.0, 1.0]) {
      shape(
        Path()
          ..moveTo(side * 15, -64)
          ..quadraticBezierTo(side * 49, -100, side * 35, -46)
          ..close(),
        accent,
      );
    }
    eyes(const Offset(0, -36), spread: 16, size: 7);
    shape(
      Path()
        ..moveTo(-10, -17)
        ..lineTo(0, -25)
        ..lineTo(10, -17)
        ..lineTo(0, -5)
        ..close(),
      accent,
    );
    lotus(const Offset(0, -69), 20);
    for (var i = 0; i < 3; i++) {
      shape(
        Path()
          ..moveTo(-14 + i * 10.0, 62)
          ..lineTo(-18 + i * 12.0, 93)
          ..lineTo(1 + i * 9.0, 70)
          ..close(),
        Color.lerp(body, ink, .17)!,
      );
    }
  }

  void makara() {
    shape(
      Path()
        ..moveTo(38, 22)
        ..quadraticBezierTo(87, -6, 106, -62)
        ..quadraticBezierTo(123, -13, 88, 14)
        ..quadraticBezierTo(118, 22, 99, 57)
        ..quadraticBezierTo(70, 29, 38, 52)
        ..close(),
      body,
    );
    oval(const Rect.fromLTWH(-58, -3, 133, 70), body);
    for (var i = 0; i < 5; i++) {
      shape(
        Path()
          ..moveTo(-25 + i * 17.0, 0)
          ..lineTo(-17 + i * 17.0, -23 + i * 3.0)
          ..lineTo(-7 + i * 17.0, 3)
          ..close(),
        accent,
      );
    }
    for (final side in [-1.0, 1.0]) {
      oval(
        Rect.fromCenter(center: Offset(side * 31, 63), width: 41, height: 21),
        accent,
      );
    }
    oval(const Rect.fromLTWH(-67, -55, 75, 71), body);
    stroke(
      Path()
        ..moveTo(-46, -10)
        ..cubicTo(-105, -5, -114, -46, -91, -47)
        ..cubicTo(-73, -48, -77, -23, -93, -29),
      body,
      18,
    );
    stroke(
      Path()
        ..moveTo(-45, -8)
        ..cubicTo(-105, -2, -109, -39, -93, -41),
      accent,
      4,
    );
    eyes(const Offset(-29, -29), spread: 14, size: 7);
    lotus(const Offset(-28, -58), 17);
    stroke(
      Path()
        ..moveTo(76, 14)
        ..quadraticBezierTo(95, 0, 102, -35),
      accent,
      3,
    );
  }

  void turtle() {
    for (final side in [-1.0, 1.0]) {
      for (final y in [-1.0, 1.0]) {
        canvas.save();
        canvas.translate(side * 52, 22 + y * 32);
        canvas.rotate(-side * y * .65);
        oval(const Rect.fromLTWH(-13, -27, 26, 54), body);
        canvas.restore();
      }
    }
    shape(
      Path()
        ..moveTo(-11, 70)
        ..lineTo(0, 95)
        ..lineTo(11, 70)
        ..close(),
      body,
    );
    oval(const Rect.fromLTWH(-31, -84, 62, 59), body);
    oval(const Rect.fromLTWH(-58, -35, 116, 120), Color.lerp(body, ink, .25)!);
    oval(const Rect.fromLTWH(-49, -28, 98, 104), body);
    final shell = Path()
      ..moveTo(0, -21)
      ..lineTo(27, -4)
      ..lineTo(27, 31)
      ..lineTo(0, 49)
      ..lineTo(-27, 31)
      ..lineTo(-27, -4)
      ..close();
    stroke(shell, accent, 4);
    for (final side in [-1.0, 1.0]) {
      stroke(
        Path()
          ..moveTo(side * 27, -4)
          ..lineTo(side * 45, -11),
        accent,
        3,
      );
      stroke(
        Path()
          ..moveTo(side * 27, 31)
          ..lineTo(side * 46, 42),
        accent,
        3,
      );
      stroke(
        Path()
          ..moveTo(side * 6, 49)
          ..lineTo(side * 19, 70),
        accent,
        3,
      );
    }
    eyes(const Offset(0, -62), spread: 12, size: 6);
    lotus(const Offset(0, -84), 12);
    oval(Rect.fromCircle(center: const Offset(0, 14), radius: 8), accent);
  }

  void monkey() {
    stroke(
      Path()
        ..moveTo(-24, 48)
        ..cubicTo(-112, 92, -108, -24, -76, -27)
        ..cubicTo(-46, -26, -50, 12, -74, 8),
      body,
      13,
    );
    oval(const Rect.fromLTWH(-31, 0, 62, 78), body);
    for (final side in [-1.0, 1.0]) {
      stroke(
        Path()
          ..moveTo(side * 25, 11)
          ..quadraticBezierTo(side * 60, 24, side * 49, 48),
        body,
        17,
      );
      oval(
        Rect.fromCenter(center: Offset(side * 50, 44), width: 23, height: 14),
        accent,
      );
      oval(
        Rect.fromCenter(center: Offset(side * 29, 77), width: 37, height: 19),
        body,
      );
      oval(Rect.fromCircle(center: Offset(side * 40, -32), radius: 19), body);
      oval(Rect.fromCircle(center: Offset(side * 40, -32), radius: 11), accent);
    }
    oval(const Rect.fromLTWH(-40, -74, 80, 82), body);
    oval(const Rect.fromLTWH(-32, -60, 64, 63), const Color(0xfff4e4c6));
    shape(
      Path()
        ..moveTo(-12, -59)
        ..quadraticBezierTo(0, -43, 12, -59)
        ..lineTo(0, -70)
        ..close(),
      body,
    );
    eyes(const Offset(0, -35), spread: 15, size: 7);
    oval(
      Rect.fromCenter(center: const Offset(0, 35), width: 22, height: 34),
      accent,
    );
    lotus(const Offset(0, -75), 20);
  }

  @override
  void paint(Canvas canvas, Size size) {
    this.canvas = canvas;
    final concept = creatureConcept(creature.id) ?? creatureConcepts.first;
    body = Color(concept.color);
    accent = Color(concept.accent);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(math.min(size.width / 260, size.height / 230));
    oval(
      const Rect.fromLTWH(-95, -95, 190, 190),
      body.withValues(alpha: .09),
      shade: false,
    );
    oval(
      const Rect.fromLTWH(-75, 85, 150, 13),
      ink.withValues(alpha: .12),
      shade: false,
    );
    switch (concept.design) {
      case CreatureDesign.snake:
        snake();
      case CreatureDesign.lion:
        lion();
      case CreatureDesign.bird:
        bird();
      case CreatureDesign.makara:
        makara();
      case CreatureDesign.turtle:
        turtle();
      case CreatureDesign.monkey:
        monkey();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(KhmerCreaturePainter oldDelegate) =>
      oldDelegate.creature != creature;
}
