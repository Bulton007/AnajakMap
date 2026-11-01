import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';
import '../../app/theme/theme.dart';
import '../../shared/formatting/travel_dates.dart';
import '../../shared/models/server_models.dart';

/// A visual stop that keeps the original Unicode title intact. Its native icon
/// also remains available on devices without a glyph for a newly added emoji.
class ItineraryActivityCard extends StatelessWidget {
  const ItineraryActivityCard({
    super.key,
    required this.activity,
    required this.zone,
    this.order = 0,
    this.selected,
    this.onSelected,
    this.showEdit = false,
    this.onEdit,
    this.action,
  });

  final ServerActivity activity;
  final String zone;
  final int order;
  final bool? selected;
  final ValueChanged<bool>? onSelected;
  final bool showEdit;
  final VoidCallback? onEdit;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = Tokens.accent(context, order);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.background,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      itineraryActivityIcon(activity.title),
                      color: accent.foreground,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    activity.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.schedule_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    travelTimeRange(
                      activity.startsAt,
                      activity.endsAt,
                      zone: zone,
                      locale: context.isKhmer ? 'km' : 'en',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            if (activity.source.isNotEmpty) ...[
              const SizedBox(height: 8),
              ExpansionTile(
                key: PageStorageKey(
                  'stop-source-${activity.id}-${activity.startsAt}-$order',
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                leading: const Icon(Icons.info_outline_rounded, size: 20),
                title: Text(
                  context.t('source'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(activity.source),
                  ),
                ],
              ),
            ],
            if (selected != null || showEdit || action != null) ...[
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              if (selected != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: selected,
                  onChanged: onSelected == null
                      ? null
                      : (value) => onSelected!(value!),
                  title: Text(
                    context.isKhmer ? 'បញ្ចូលទីតាំងនេះ' : 'Include this stop',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              if (showEdit)
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  label: Text(context.t('edit')),
                ),
              if (action != null)
                Align(alignment: Alignment.centerRight, child: action!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Decorative hints only; the title remains the source of truth for the stop.
IconData itineraryActivityIcon(String title) {
  final value = title.toLowerCase();
  if (RegExp(
    r'food|lunch|dinner|breakfast|restaurant|café|cafe|ម្ហូប|អាហារ|☕|🍜|🍽|🍲',
  ).hasMatch(value)) {
    return Icons.restaurant_rounded;
  }
  if (RegExp(r'beach|island|sea|coast|ឆ្នេរ|កោះ|🌊|🏖|🏝').hasMatch(value)) {
    return Icons.beach_access_rounded;
  }
  if (RegExp(
    r'temple|palace|museum|pagoda|angkor|wat |ប្រាសាទ|វត្ត|🏛|🛕',
  ).hasMatch(value)) {
    return Icons.temple_buddhist_rounded;
  }
  if (RegExp(
    r'park|forest|waterfall|mountain|garden|ភ្នំ|ព្រៃ|សួន|🌿|🌳|⛰',
  ).hasMatch(value)) {
    return Icons.forest_rounded;
  }
  if (RegExp(r'market|shop|ផ្សារ|🛍').hasMatch(value)) {
    return Icons.storefront_rounded;
  }
  return Icons.explore_rounded;
}
