import 'package:flutter/material.dart';
import 'place_photo.dart';
import '../../app/theme/theme.dart';

/// Shared visual language for travel and adventure actions.
IconData featureIcon(String key) => switch (key) {
  'collection' => Icons.pets_rounded,
  'party' || 'group' => Icons.groups_rounded,
  'inventory' => Icons.backpack_rounded,
  'quests' => Icons.explore_rounded,
  'achievements' => Icons.emoji_events_rounded,
  'food' => Icons.restaurant_rounded,
  'culture' => Icons.temple_buddhist_rounded,
  'weather' => Icons.wb_sunny_rounded,
  'routes' || 'generate' => Icons.route_rounded,
  'transport' => Icons.directions_bus_rounded,
  'expenses' => Icons.account_balance_wallet_rounded,
  'reservations' => Icons.hotel_rounded,
  'journal' => Icons.auto_stories_rounded,
  'calendar' => Icons.calendar_month_rounded,
  'contacts' => Icons.contact_phone_rounded,
  'offline' => Icons.download_for_offline_rounded,
  'translate' => Icons.translate_rounded,
  'vision' => Icons.camera_alt_rounded,
  'voice' => Icons.mic_rounded,
  'chat' => Icons.forum_rounded,
  'map' => Icons.map_rounded,
  _ => Icons.explore_rounded,
};

class VisualHero extends StatelessWidget {
  const VisualHero({
    super.key,
    required this.title,
    required this.caption,
    this.action,
  });
  final String title, caption;
  final Widget? action;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/angkor.jpg',
            fit: BoxFit.cover,
            excludeFromSemantics: true,
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Colors.black.withValues(alpha: .25),
                  const Color(0xFF0C2926).withValues(alpha: .94),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.explore_rounded,
                color: Color(0xFFF8DB9B),
                size: 32,
              ),
              const SizedBox(height: 32),
              Text(
                caption,
                style: const TextStyle(
                  color: Color(0xFFF8DB9B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: Colors.white),
              ),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ],
    ),
  );
}

class VisualAction extends StatelessWidget {
  const VisualAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.compact = false,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool compact;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    // Keep cards calm; color belongs to feature badges and illustrations.
    final tone = switch (icon) {
      Icons.map_rounded || Icons.travel_explore || Icons.route_rounded => 0,
      Icons.auto_awesome || Icons.forum_rounded || Icons.translate_rounded => 2,
      Icons.pets_rounded || Icons.emoji_events_rounded => 3,
      Icons.restaurant_rounded || Icons.wb_sunny_rounded => 1,
      _ => 4,
    };
    final accent = Tokens.accent(context, tone);
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.surface,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(compact ? 12 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.background,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: accent.foreground, size: 28),
              ),
              SizedBox(height: compact ? 8 : 16),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: colors.onSurface),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
              if (!compact) const SizedBox(height: 8),
              if (!compact)
                Icon(
                  onTap == null
                      ? Icons.schedule_rounded
                      : Icons.arrow_forward_rounded,
                  size: 20,
                  color: accent.foreground,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Equal-height rows that grow with translated labels and accessible text sizes.
class VisualActions extends StatelessWidget {
  const VisualActions({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns =
          MediaQuery.textScalerOf(context).scale(14) > 23 || box.maxWidth < 300
          ? 1
          : box.maxWidth > 600
          ? 3
          : 2;
      return Column(
        children: [
          for (var start = 0; start < children.length; start += columns)
            Padding(
              padding: EdgeInsets.only(
                bottom: start + columns < children.length ? 12 : 0,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: 12),
                      Expanded(
                        child: start + column < children.length
                            ? children[start + column]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class DestinationCard extends StatelessWidget {
  const DestinationCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.photo,
    this.photoWidget,
  });
  final Map<String, dynamic>? photo;
  final Widget? photoWidget;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photoWidget != null)
              photoWidget!
            else if (photo != null)
              PlacePhoto(name: title, photo: photo)
            else
              Container(
                height: 110,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colors.secondaryContainer,
                      colors.tertiaryContainer,
                    ],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -8,
                      bottom: -24,
                      child: Icon(
                        Icons.landscape_rounded,
                        size: 160,
                        color: colors.primary.withValues(alpha: .12),
                      ),
                    ),
                    Center(
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 44,
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.arrow_forward_rounded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
