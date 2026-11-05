import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';
import '../../shared/formatting/travel_dates.dart';
import 'trip_chat.dart';
import 'trip_invitations.dart';

class DirectMessages extends ConsumerWidget {
  const DirectMessages({super.key, required this.accountId});
  final String accountId;

  Future<void> open(
    BuildContext context,
    String peer,
    VoidCallback refresh,
  ) async {
    if (peer.isEmpty || peer == accountId) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TripChat.direct(peerId: peer, accountId: accountId),
      ),
    );
    if (context.mounted) refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.isKhmer ? 'សារឯកជន' : 'Private messages'),
      ),
      body: RemoteContent<List<Json>>(
        load: repo.directConversations,
        builder: (rows, refresh) => PageBody(
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.person_search_outlined),
              label: Text(
                context.isKhmer ? 'រកអ្នកធ្វើដំណើរ' : 'Find traveler',
              ),
              onPressed: () async {
                final result = await remoteForm(
                  context,
                  'message',
                  [const InputSpec('accountId')],
                  submit: (input, _) =>
                      repo.traveler(input['accountId'].toString().trim()),
                );
                if (result != null && context.mounted) {
                  await open(context, string(object(result), 'id'), refresh);
                }
              },
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty) Text(context.t('empty')),
            for (final row in rows)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: TravelerName(accountId: string(row, 'peerId')),
                  subtitle: Text(
                    [
                      string(row, 'message'),
                      inboxDateTime(
                        string(row, 'sentAt'),
                        locale: context.isKhmer ? 'km' : 'en',
                      ),
                    ].join('\n'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => open(context, string(row, 'peerId'), refresh),
                  trailing: integer(row, 'unreadCount') > 0
                      ? Badge(label: Text(string(row, 'unreadCount')))
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
