import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../formatting/travel_dates.dart';

class EmergencyContactCard extends StatefulWidget {
  const EmergencyContactCard({
    super.key,
    required this.contact,
    this.openDialer,
  });
  final Json contact;
  final Future<bool> Function(Uri)? openDialer;
  @override
  State<EmergencyContactCard> createState() => _EmergencyContactCardState();
}

class _EmergencyContactCardState extends State<EmergencyContactCard> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final phone = string(widget.contact, 'phone'),
        normalized = phone.replaceAll(RegExp(r'[ ()-]'), '');
    final valid = RegExp(r'^\+?\d{3,20}$').hasMatch(normalized);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.contact_emergency_outlined),
            const SizedBox(height: 12),
            Text(
              string(widget.contact, 'label'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SelectableText(phone),
            const SizedBox(height: 8),
            Text(
              context.isKhmer
                  ? 'បើកកម្មវិធីហៅទូរសព្ទរបស់ឧបករណ៍។ មិនហៅដោយស្វ័យប្រវត្តិទេ។'
                  : 'Opens your device dialer. No call is placed automatically.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: !valid || busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      var opened = false;
                      try {
                        final uri = Uri(scheme: 'tel', path: normalized);
                        opened = widget.openDialer != null
                            ? await widget.openDialer!(uri)
                            : await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                      } catch (_) {}
                      if (!context.mounted) return;
                      setState(() => busy = false);
                      if (!opened) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              context.isKhmer
                                  ? 'មិនអាចបើកកម្មវិធីហៅទូរសព្ទបានទេ។ សូមប្រើលេខខាងលើ។'
                                  : 'Could not open the dialer. Use the number above.',
                            ),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.dialpad),
              label: Text(
                context.isKhmer ? 'បើកកម្មវិធីហៅទូរសព្ទ' : 'Open dialer',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TravelNotificationCard extends StatelessWidget {
  const TravelNotificationCard({
    super.key,
    required this.delivery,
    this.sender,
    this.actions = const [],
    this.unread = false,
    this.onOpen,
  });
  final Json delivery;
  final Widget? sender;
  final List<Widget> actions;
  final bool unread;
  final VoidCallback? onOpen;
  @override
  Widget build(BuildContext context) {
    final status = string(delivery, 'status');
    final title = context.isKhmer
        ? switch (string(delivery, 'kind')) {
            'chat.direct-message' => 'សារឯកជនថ្មី',
            'chat.trip-message' => 'សារថ្មីក្នុងដំណើរ',
            'group.invited' => 'ការអញ្ជើញចូលរួមដំណើរ',
            'group.joined' => 'បានទទួលយកការអញ្ជើញ',
            'group.invitation-rejected' => 'បានបដិសេធការអញ្ជើញ',
            'group.invitation-cancelled' => 'បានលុបចោលការអញ្ជើញ',
            _ => string(delivery, 'title'),
          }
        : string(delivery, 'title');
    final colors = Theme.of(context).colorScheme;
    final detail = string(delivery, 'detail');
    final icon = switch (string(delivery, 'kind')) {
      'chat.direct-message' || 'chat.trip-message' => Icons.forum_outlined,
      'group.invited' => Icons.person_add_alt_1_outlined,
      'group.joined' => Icons.how_to_reg_outlined,
      'group.invitation-rejected' ||
      'group.invitation-cancelled' => Icons.person_remove_outlined,
      _ => Icons.notifications_outlined,
    };
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: unread
          ? colors.primaryContainer.withValues(alpha: .35)
          : colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    status == 'DEAD' ? Icons.error_outline : icon,
                    color: colors.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                ),
                if (unread)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Tooltip(
                      message: context.isKhmer ? 'មិនទាន់អាន' : 'Unread',
                      child: Icon(Icons.circle, size: 8, color: colors.primary),
                    ),
                  ),
                if (onOpen != null)
                  IconButton(
                    tooltip: context.isKhmer ? 'បើក' : 'Open',
                    onPressed: onOpen,
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sender != null || detail.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      ?sender,
                      if (detail.isNotEmpty) Text(detail),
                    ],
                    const SizedBox(height: 4),
                    Tooltip(
                      message: travelDateTime(
                        string(delivery, 'dueAt'),
                        locale: context.isKhmer ? 'km' : 'en',
                      ),
                      child: Text(
                        inboxDateTime(
                          string(delivery, 'dueAt'),
                          locale: context.isKhmer ? 'km' : 'en',
                        ),
                      ),
                    ),
                    if (['PENDING', 'CANCELLED', 'DEAD'].contains(status)) ...[
                      const SizedBox(height: 4),
                      Text(switch (status) {
                        'PENDING' =>
                          context.isKhmer ? 'បានកំណត់ពេល' : 'Scheduled',
                        'CANCELLED' =>
                          context.isKhmer ? 'បានលុបចោល' : 'Cancelled',
                        _ =>
                          context.isKhmer ? 'មិនអាចផ្ញើបាន' : 'Delivery failed',
                      }),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, children: actions),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
