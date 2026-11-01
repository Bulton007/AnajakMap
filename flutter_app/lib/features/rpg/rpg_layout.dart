import 'package:flutter/material.dart';

const rpgCardGap = 16.0;
const rpgContentPadding = 20.0;

/// All game pages use the same inset and card rhythm, including expanded lists.
class RpgPanel extends StatelessWidget {
  const RpgPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(rpgContentPadding),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    color: color,
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

/// Intrinsic row height keeps related card actions aligned without fixed heights.
/// Large text and narrow windows automatically use fewer columns.
class RpgCardGrid extends StatelessWidget {
  const RpgCardGrid({
    super.key,
    required this.children,
    this.minCardWidth = 160,
    this.maxColumns = 2,
  });
  final List<Widget> children;
  final double minCardWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final minimum = minCardWidth * scale.clamp(1.0, 1.8);
      final columns =
          ((constraints.maxWidth + rpgCardGap) / (minimum + rpgCardGap))
              .floor()
              .clamp(1, maxColumns)
              .toInt();
      final rows = <Widget>[];
      for (var start = 0; start < children.length; start += columns) {
        if (rows.isNotEmpty) rows.add(const SizedBox(height: rpgCardGap));
        rows.add(
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < columns; index++) ...[
                  if (index != 0) const SizedBox(width: rpgCardGap),
                  Expanded(
                    child: start + index < children.length
                        ? children[start + index]
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      );
    },
  );
}

List<Widget> spacedRpgItems(
  Iterable<Widget> children, {
  double gap = rpgCardGap,
}) {
  final result = <Widget>[];
  for (final child in children) {
    if (result.isNotEmpty) result.add(SizedBox(height: gap));
    result.add(child);
  }
  return result;
}

class RpgFact extends StatelessWidget {
  const RpgFact(this.icon, this.label, {super.key});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      Flexible(child: Text(label)),
    ],
  );
}

class RpgEmptyState extends StatelessWidget {
  const RpgEmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => RpgPanel(
    child: Column(
      children: [
        Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}
