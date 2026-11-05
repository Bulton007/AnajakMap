import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/live_socket.dart';
import '../../core/network/providers.dart';
import '../../shared/formatting/travel_dates.dart';
import '../authentication/auth_controller.dart';
import 'trip_invitations.dart';

class TripChat extends ConsumerStatefulWidget {
  const TripChat({super.key, required this.tripId, required this.accountId})
    : direct = false;
  const TripChat.direct({
    super.key,
    required String peerId,
    required this.accountId,
  }) : tripId = peerId,
       direct = true;
  final bool direct;
  final String tripId, accountId;

  @override
  ConsumerState<TripChat> createState() => _TripChatState();
}

class _TripChatState extends ConsumerState<TripChat> {
  final text = TextEditingController();
  List<Json>? messages;
  WebSocket? socket;
  Timer? refresh;
  Timer? typingTimeout;
  String? typingAccount;
  DateTime? lastTypingSignal;
  bool fetching = false, refreshAgain = false;
  bool failed = false, connecting = false, sending = false;
  bool sessionEnded = false;
  bool more = false, paging = false;
  int page = 0;
  String? retryText, retryKey;
  String? lastReadRequest;

  Future<List<Json>> history(int page) {
    final repo = ref.read(repositoryProvider);
    return widget.direct
        ? repo.directMessages(widget.tripId, page: page)
        : repo.tripMessages(widget.tripId, page: page);
  }

  Future<void> loadOlder() async {
    if (paging || !more) return;
    setState(() => paging = true);
    try {
      final rows = await history(page + 1);
      if (!mounted) return;
      final ids = messages!.map((row) => string(row, 'id')).toSet();
      setState(() {
        messages = [
          ...messages!,
          ...rows.where((row) => ids.add(string(row, 'id'))),
        ];
        page++;
        more = rows.length == 50;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.t('requestFailed'))));
      }
    } finally {
      if (mounted) setState(() => paging = false);
    }
  }

  String t(String en, String km) => context.isKhmer ? km : en;

  @override
  void initState() {
    super.initState();
    ref.listenManual(authControllerProvider, (previous, next) {
      if (previous?.authenticated == true &&
          (!next.authenticated ||
              string(next.session!.user.profile, 'id') != widget.accountId)) {
        setState(() {
          sessionEnded = true;
          messages = null;
          failed = true;
        });
        refresh?.cancel();
        typingTimeout?.cancel();
        text.clear();
        unawaited(socket?.close());
      }
    });
    unawaited(sync());
    refresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (ModalRoute.of(context)?.isCurrent == true) unawaited(sync());
    });
  }

  Future<void> sync() async {
    await load();
    if (mounted) unawaited(connect());
  }

  Future<void> load() async {
    if (sessionEnded) return;
    if (fetching) {
      refreshAgain = true;
      return;
    }
    fetching = true;
    try {
      final rows = await history(0);
      if (mounted && !sessionEnded) {
        setState(() {
          final ids = rows.map((row) => string(row, 'id')).toSet();
          messages = [
            ...rows,
            if (page > 0)
              ...?messages?.where((row) => !ids.contains(string(row, 'id'))),
          ];
          if (page == 0) more = rows.length == 50;
          failed = false;
        });
        if (widget.direct) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              unawaited(markRead(rows));
            }
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      fetching = false;
      if (mounted && refreshAgain) {
        refreshAgain = false;
        unawaited(load());
      }
    }
  }

  Future<void> markRead(List<Json> rows) async {
    final unread = rows.where(
      (row) =>
          string(row, 'senderId') != widget.accountId &&
          field(row, 'readAt') == null,
    );
    if (unread.isEmpty) return;
    final id = string(unread.first, 'id');
    if (id.isEmpty || id == lastReadRequest) return;
    lastReadRequest = id;
    try {
      await ref.read(repositoryProvider).readDirectMessages(widget.tripId, id);
    } catch (_) {
      if (lastReadRequest == id) lastReadRequest = null;
    }
  }

  Future<void> connect() async {
    if (socket != null || connecting || failed || sessionEnded) return;
    connecting = true;
    try {
      final tripId = Uri.encodeComponent(widget.tripId);
      final connection = await openLiveSocket(
        ref.read(apiProvider),
        widget.direct
            ? 'trips/direct-chat/$tripId/live'
            : 'trips/$tripId/chat/live',
      );
      if (connection == null) return;
      if (!mounted || sessionEnded) {
        await connection.close();
        return;
      }
      setState(() => socket = connection);
      void disconnected() {
        if (mounted && socket == connection) setState(() => socket = null);
      }

      connection.listen(
        (event) {
          if (!mounted) return;
          if (event == 'ready' || event == 'changed') {
            unawaited(load());
          } else if (event is String && event.startsWith('typing:')) {
            final account = event.substring(7);
            if (account.isEmpty || account == widget.accountId) return;
            typingTimeout?.cancel();
            setState(() => typingAccount = account);
            typingTimeout = Timer(const Duration(seconds: 5), () {
              if (mounted) setState(() => typingAccount = null);
            });
          }
        },
        onDone: disconnected,
        onError: (Object _) => disconnected(),
      );
    } catch (_) {
      // History continues to refresh while the socket is unavailable.
    } finally {
      connecting = false;
    }
  }

  Future<void> typing(String value) async {
    if (value.trim().isEmpty || socket == null) return;
    final now = DateTime.now();
    if (lastTypingSignal case final last?
        when now.difference(last) < const Duration(seconds: 4)) {
      return;
    }
    lastTypingSignal = now;
    try {
      await ref
          .read(repositoryProvider)
          .chatTyping(widget.tripId, direct: widget.direct);
    } catch (_) {
      // Typing signals are transient and do not affect message delivery.
    }
  }

  Future<void> send() async {
    final value = text.text.trim();
    if (sending || value.isEmpty || sessionEnded) return;
    setState(() => sending = true);
    try {
      if (retryText != value) {
        retryText = value;
        retryKey = ApiClient.operationId();
      }
      final repo = ref.read(repositoryProvider);
      if (widget.direct) {
        await repo.sendDirectMessage(widget.tripId, value, retryKey!);
      } else {
        await repo.sendTripMessage(widget.tripId, value, retryKey!);
      }
      retryText = retryKey = null;
      if (!mounted) return;
      if (text.text.trim() == value) text.clear();
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('Message could not be sent.', 'មិនអាចផ្ញើសារបាន។')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    refresh?.cancel();
    typingTimeout?.cancel();
    unawaited(socket?.close());
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: widget.direct
          ? TravelerName(accountId: widget.tripId)
          : Text(t('Trip chat', 'ជជែកក្នុងដំណើរ')),
      actions: [
        IconButton(
          tooltip: context.t('refresh'),
          onPressed: sync,
          icon: Icon(socket == null ? Icons.refresh : Icons.bolt),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  socket == null ? Icons.sync : Icons.circle,
                  size: socket == null ? 14 : 7,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  socket == null
                      ? t('Reconnecting…', 'កំពុងភ្ជាប់ឡើងវិញ…')
                      : t('Connected', 'បានភ្ជាប់'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: failed
                ? Center(
                    child: TextButton(
                      onPressed: sync,
                      child: Text(context.t('retry')),
                    ),
                  )
                : messages == null
                ? const Center(child: CircularProgressIndicator())
                : messages!.isEmpty
                ? Center(
                    child: Text(
                      t('Start the conversation', 'ចាប់ផ្តើមការសន្ទនា'),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages!.length + (more ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == messages!.length) {
                        return TextButton(
                          onPressed: paging ? null : loadOlder,
                          child: Text(
                            t('Load older messages', 'ផ្ទុកសារចាស់ៗ'),
                          ),
                        );
                      }
                      final row = messages![index];
                      final sender = string(row, 'senderId');
                      final own = sender == widget.accountId;
                      final day = conversationDay(
                        string(row, 'sentAt'),
                        locale: context.isKhmer ? 'km' : 'en',
                      );
                      final previousDay = index + 1 < messages!.length
                          ? conversationDay(
                              string(messages![index + 1], 'sentAt'),
                              locale: context.isKhmer ? 'km' : 'en',
                            )
                          : null;
                      return Column(
                        children: [
                          if (day != previousDay && day != '—')
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                day,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          _MessageBubble(
                            row: row,
                            own: own,
                            direct: widget.direct,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (typingAccount case final account?)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 6,
                children: [
                  TravelerName(accountId: account),
                  Text(t('is typing…', 'កំពុងវាយ…')),
                ],
              ),
            ),
          if (messages != null && !failed)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: text,
                      onChanged: typing,
                      minLines: 1,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        hintText: context.t('message'),
                        counterText: '',
                        filled: true,
                        fillColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder(
                    valueListenable: text,
                    builder: (context, value, _) => IconButton.filled(
                      tooltip: t('Send', 'ផ្ញើ'),
                      onPressed: sending || value.text.trim().isEmpty
                          ? null
                          : send,
                      icon: sending
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.row,
    required this.own,
    required this.direct,
  });
  final Json row;
  final bool own, direct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final km = context.isKhmer;
    final foreground = own ? colors.onPrimary : colors.onSurface;
    final secondary = own
        ? colors.onPrimary.withValues(alpha: .75)
        : colors.onSurfaceVariant;
    final read = field(row, 'readAt') != null;
    return Align(
      alignment: own ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .82,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: own ? colors.primary : colors.surfaceContainerLow,
          border: own ? null : Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(own ? 18 : 5),
            bottomRight: Radius.circular(own ? 5 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultTextStyle.merge(
              style: theme.textTheme.labelSmall?.copyWith(color: secondary),
              child: own
                  ? Text(km ? 'អ្នក' : 'You')
                  : TravelerName(accountId: string(row, 'senderId')),
            ),
            const SizedBox(height: 4),
            SelectableText(
              string(row, 'message'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: foreground,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 6),
            Tooltip(
              message: travelDateTime(
                string(row, 'sentAt'),
                locale: km ? 'km' : 'en',
              ),
              child: Wrap(
                spacing: 5,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (string(row, 'sentAt').isNotEmpty)
                    Text(
                      conversationTime(
                        string(row, 'sentAt'),
                        locale: km ? 'km' : 'en',
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                  if (direct && own) ...[
                    Icon(
                      read ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14,
                      color: secondary,
                    ),
                    Text(
                      read
                          ? (km ? 'បានអាន' : 'Read')
                          : (km ? 'បានផ្ញើ' : 'Sent'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
