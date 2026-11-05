import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';
import '../../shared/components/travel_panels.dart';

class TripInvitations extends ConsumerStatefulWidget {
  const TripInvitations({super.key, this.onAccepted, this.tripId});
  final VoidCallback? onAccepted;
  final String? tripId;

  @override
  ConsumerState<TripInvitations> createState() => _TripInvitationsState();
}

class _TripInvitationsState extends ConsumerState<TripInvitations> {
  final accepting = <String>{};

  String t(String en, String km) => context.isKhmer ? km : en;

  Future<void> respond(
    String id,
    VoidCallback refresh, {
    required bool accept,
  }) async {
    if (accepting.contains(id)) return;
    setState(() => accepting.add(id));
    try {
      final repo = ref.read(repositoryProvider);
      final result = await runRequest(
        context,
        () => accept ? repo.acceptInvite(id) : repo.rejectInvite(id),
      );
      if (mounted && result != null) {
        refresh();
        if (accept) widget.onAccepted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? t('Trip joined', 'បានចូលរួមដំណើរ')
                  : t('Invitation declined', 'បានបដិសេធការអញ្ជើញ'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => accepting.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Trip invitations', 'ការអញ្ជើញចូលរួមដំណើរ'))),
    body: RemoteContent<List<Json>>(
      load: () async {
        final rows = await ref.read(repositoryProvider).pendingInvitations();
        return widget.tripId == null
            ? rows
            : rows
                  .where((row) => string(row, 'tripId') == widget.tripId)
                  .toList();
      },
      builder: (invitations, refresh) => PageBody(
        children: [
          if (invitations.isEmpty)
            VisualEmpty(
              icon: Icons.mail_outline,
              title: t('No pending invitations', 'គ្មានការអញ្ជើញកំពុងរង់ចាំ'),
            ),
          for (final invitation in invitations) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      string(invitation, 'title'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(string(invitation, 'destination')),
                    if (string(invitation, 'inviterId').isNotEmpty)
                      TravelerName(accountId: string(invitation, 'inviterId')),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed:
                          accepting.contains(string(invitation, 'tripId'))
                          ? null
                          : () => respond(
                              string(invitation, 'tripId'),
                              refresh,
                              accept: true,
                            ),
                      child: Text(context.t('acceptInvitation')),
                    ),
                    TextButton(
                      onPressed:
                          accepting.contains(string(invitation, 'tripId'))
                          ? null
                          : () => respond(
                              string(invitation, 'tripId'),
                              refresh,
                              accept: false,
                            ),
                      child: Text(t('Decline', 'បដិសេធ')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          TextButton(onPressed: refresh, child: Text(context.t('refresh'))),
        ],
      ),
    ),
  );
}

class TravelerName extends ConsumerWidget {
  const TravelerName({super.key, required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(travelerProvider(accountId)).asData?.value;
    final name = string(profile ?? {}, 'displayName');
    return Text(name.isEmpty ? accountId.split('-').first : name);
  }
}
