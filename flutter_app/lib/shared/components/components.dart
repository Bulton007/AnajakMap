import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/localization/strings.dart';
import '../../app/theme/theme.dart';
import '../models/travel.dart';

String money(BuildContext context, int cents) => NumberFormat.currency(
  locale: context.isKhmer ? 'km' : 'en',
  name: 'USD',
  symbol: '\$',
  decimalDigits: 2,
).format(cents / 100);
String tripDates(BuildContext context, Trip trip) =>
    '${DateFormat.MMMd(context.isKhmer ? 'km' : 'en').format(trip.start)} – ${DateFormat.MMMd(context.isKhmer ? 'km' : 'en').format(trip.end)}';

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.padding = 24});
  final List<Widget> children;
  final double padding;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const PageStorageKey('page-scroll'),
    padding: EdgeInsets.fromLTRB(padding, 12, padding, 32),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}

class Section extends StatelessWidget {
  const Section(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.onDark = false});
  final String text;
  final IconData? icon;
  final bool onDark;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: onDark
          ? Colors.black.withValues(alpha: .35)
          : Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: onDark ? Colors.white : null),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .5,
              color: onDark ? Colors.white : null,
            ),
          ),
        ),
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  const Notice(
    this.text, {
    super.key,
    this.icon = Icons.info_outline,
    this.error = false,
  });
  final String text;
  final IconData icon;
  final bool error;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error
          ? Theme.of(context).colorScheme.errorContainer
          : Theme.of(
              context,
            ).colorScheme.secondaryContainer.withValues(alpha: .65),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    ),
  );
}

class Photo extends StatelessWidget {
  const Photo({
    super.key,
    this.height = 210,
    this.child,
    this.radius = 24,
    this.asset = 'angkor',
  });
  final double height, radius;
  final Widget? child;
  final String asset;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      height: child == null
          ? height
          : height *
                (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1, 3),
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/$asset.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, e, s) => const ColoredBox(
              color: Tokens.forest,
              child: Center(
                child: Icon(
                  Icons.landscape_outlined,
                  size: 80,
                  color: Tokens.lime,
                ),
              ),
            ),
          ),
          if (child != null) ...[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x10000000), Color(0xDD112A1C)],
                ),
              ),
            ),
            child!,
          ],
        ],
      ),
    ),
  );
}

class ActionCard extends StatelessWidget {
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(Tokens.radius),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, size: 19),
          ],
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.action,
    this.icon = Icons.explore_outlined,
  });
  final String title, body;
  final Widget? action;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Center(
      child: Column(
        children: [
          Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    ),
  );
}

class ActivityRow extends StatelessWidget {
  const ActivityRow(this.activity, {super.key, this.trailing});
  final Activity activity;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              children: [
                Text(
                  activity.time,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Icon(
                  activity.place == 'market'
                      ? Icons.ramen_dining
                      : Icons.temple_buddhist_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(activity.place),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    context.t(placeCategories[activity.place] ?? 'culture'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(c.t('confirm')),
          ),
        ],
      ),
    ) ??
    false;

Future<void> inform(BuildContext context, String title, String body) =>
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(c.t('close')),
          ),
        ],
      ),
    );

Future<bool> persist(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('storageError'))));
    }
    return false;
  }
}
