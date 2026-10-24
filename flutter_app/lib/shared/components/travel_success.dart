import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/theme.dart';

/// Call only after the mutation/local save has completed successfully.
void showTravelSuccess(BuildContext context, {String? message}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final km = Localizations.localeOf(context).languageCode == 'km';
  final reduced =
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);
  final colors = Theme.of(context).colorScheme;
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      backgroundColor: colors.primaryContainer,
      content: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            const TempleSuccessIllustration(),
            const SizedBox(width: Tokens.gap),
            Expanded(
              child: Text(
                message ?? (km ? 'បានរក្សាទុកដោយជោគជ័យ' : 'Saved successfully'),
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    ),
    snackBarAnimationStyle: reduced ? AnimationStyle.noAnimation : null,
  );
}

/// A bundled code-native Khmer-inspired temple illustration; no remote asset.
class TempleSuccessIllustration extends StatelessWidget {
  const TempleSuccessIllustration({super.key});
  @override
  Widget build(BuildContext context) {
    final reduced =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduced ? 1 : 0, end: 1),
        duration: reduced ? Duration.zero : const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
        builder: (_, progress, _) => Opacity(
          opacity: progress,
          child: Transform.scale(
            scale: .8 + .2 * progress,
            child: CustomPaint(
              size: const Size(64, 64),
              painter: _TemplePainter(
                colors.primary,
                colors.onPrimaryContainer,
                progress,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplePainter extends CustomPainter {
  _TemplePainter(this.color, this.ink, this.progress);
  final Color color, ink;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 64;
    canvas.save();
    canvas.scale(scale);
    final fill = Paint()..color = color;
    final gold = Paint()..color = Tokens.gold;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 43, 48, 13),
        const Radius.circular(5),
      ),
      fill,
    );
    for (final tower in [(16.0, 25.0), (32.0, 13.0), (48.0, 25.0)]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(tower.$1 - 7, tower.$2 + 10, 14, 26),
          const Radius.circular(3),
        ),
        fill,
      );
      for (var tier = 0; tier < 4; tier++) {
        final half = 2.5 + tier * 1.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(tower.$1 - half, tower.$2 + tier * 4, half * 2, 4),
            const Radius.circular(1),
          ),
          gold,
        );
      }
    }
    final face = Paint()..color = ink;
    canvas.drawCircle(const Offset(27, 42), 1.3, face);
    canvas.drawCircle(const Offset(37, 42), 1.3, face);
    canvas.drawArc(
      const Rect.fromLTWH(28, 43, 8, 6),
      0,
      math.pi,
      false,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (var i = 0; i < 5; i++) {
      final angle = i * math.pi * 2 / 5;
      final point = Offset(
        32 + math.cos(angle) * (22 + 6 * progress),
        28 + math.sin(angle) * (22 + 6 * progress),
      );
      canvas.drawCircle(point, 1.5 * progress, gold);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TemplePainter old) =>
      old.progress != progress || old.color != color || old.ink != ink;
}
