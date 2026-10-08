import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';
import '../../shared/models/server_models.dart';

class ConnectedOffline extends ConsumerStatefulWidget {
  const ConnectedOffline({super.key, required this.profile, this.trip});
  final Json profile;
  final ServerTrip? trip;
  @override
  ConsumerState<ConnectedOffline> createState() => _OfflineState();
}

class _OfflineState extends ConsumerState<ConnectedOffline> {
  int revision = 0;
  bool syncing = false;
  String get scope =>
      '${ref.read(environmentProvider).normalizedUrl}|${widget.profile['id']}';
  Future<Json> load() async => {
    'snapshots': await ref.read(databaseProvider).cachedEntries(scope, 'trip:'),
    'operations': await ref.read(databaseProvider).pending(scope),
  };
  Future<void> download() async {
    final result = await runRequest(context, () async {
      final data = await ref.read(repositoryProvider).snapshot(widget.trip!.id);
      await ref
          .read(databaseProvider)
          .cache(scope, 'trip:${widget.trip!.id}', data);
      return true;
    });
    if (result == true && mounted) {
      setState(() => revision++);
    }
  }

  Future<void> edit(Json snapshot) async {
    final data = object(snapshot['data']);
    final trip = ServerTrip.fromJson(object(data['trip']));
    await remoteForm(
      context,
      'queueEdit',
      [
        InputSpec('title', initial: trip.title),
        InputSpec('destination', initial: trip.destination),
        InputSpec('timezone', initial: trip.timezone),
        InputSpec('startDate', initial: trip.startDate, kind: InputKind.date),
        InputSpec('endDate', initial: trip.endDate, kind: InputKind.date),
      ],
      submit: (body, key) async {
        await ref.read(databaseProvider).queue(scope, key, 'trip', trip.id, {
          'baseVersion': trip.version,
          'trip': body,
        });
        return true;
      },
    );
    if (mounted) {
      setState(() => revision++);
    }
  }

  Future<void> queueRecord(Json snapshot, String kind) async {
    final trip = ServerTrip.fromJson(object(object(snapshot['data'])['trip']));
    await remoteForm(
      context,
      kind == 'expense' ? 'addExpense' : 'newEntry',
      kind == 'expense'
          ? [
              const InputSpec('description'),
              const InputSpec('amount', kind: InputKind.amount),
              const InputSpec(
                'currency',
                initial: 'USD',
                choices: ['USD', 'KHR', 'EUR'],
              ),
            ]
          : [
              const InputSpec('title', label: 'journalTitle'),
              const InputSpec('content', kind: InputKind.multiline),
            ],
      notice: context.t('queued'),
      submit: (body, key) async {
        await ref.read(databaseProvider).queue(scope, key, kind, trip.id, {
          'tripId': trip.id,
          ...body,
          if (kind == 'expense')
            'splits': {widget.profile['id'].toString(): body['amount']},
          if (kind == 'journal') ...{'recap': '', 'version': 0},
        });
        return true;
      },
    );
    if (mounted) {
      setState(() => revision++);
    }
  }

  Future<void> sync(Json operation) async {
    if (syncing) {
      return;
    }
    setState(() => syncing = true);
    final db = ref.read(databaseProvider), repo = ref.read(repositoryProvider);
    final id = string(operation, 'id'),
        entity = string(operation, 'entity'),
        body = object(operation['body']);
    try {
      await db.mark(scope, id, 'sending');
      switch (string(operation, 'kind')) {
        case 'trip':
          final current = await repo.trip(entity);
          // A lost response can leave an edit committed. Compare every field before replay.
          final desired = object(body['trip']);
          final alreadySaved =
              current.version > integer(body, 'baseVersion') &&
              desired.entries.every((e) => current.editable[e.key] == e.value);
          if (!alreadySaved) {
            await repo.syncTrip(entity, integer(body, 'baseVersion'), desired);
          }
        case 'expense':
          await repo.addExpense(body, id);
        case 'journal':
          await repo.saveJournal(body, id);
        default:
          throw StateError('Unsupported queued operation');
      }
      await db.remove(scope, id);
      try {
        await db.cache(scope, 'trip:$entity', await repo.snapshot(entity));
      } catch (_) {
        /* Confirmed write stays confirmed if cache refresh fails. */
      }
    } on ApiFailure catch (e) {
      await db.mark(
        scope,
        id,
        e.conflict ? 'conflict' : 'queued',
        e.toString(),
      );
      if (mounted && e.conflict && string(operation, 'kind') == 'trip') {
        await resolve(operation);
      }
    } catch (e) {
      await db.mark(scope, id, 'queued', e.toString());
    }
    if (mounted) {
      setState(() {
        syncing = false;
        revision++;
      });
    }
  }

  Future<void> resolve(Json operation) async {
    final current = await runRequest(
      context,
      () => ref.read(repositoryProvider).trip(string(operation, 'entity')),
    );
    if (current == null || !mounted) {
      return;
    }
    final desired = object(object(operation['body'])['trip']);
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.t('conflictTitle')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.t('localChange')),
                ServerResult(desired),
                const Divider(),
                Text(c.t('serverChange')),
                ServerResult(current.editable),
                Text(c.t('conflictReview')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(c.t('close')),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    final result = await remoteForm(
      context,
      'reviewMerge',
      [
        for (final entry in current.editable.entries)
          InputSpec(
            entry.key,
            initial: entry.value.toString(),
            kind: ['startDate', 'endDate'].contains(entry.key)
                ? InputKind.date
                : InputKind.text,
          ),
      ],
      submit: (body, key) async {
        // Preserve the old operation until a new version-checked write is confirmed.
        final saved = await ref
            .read(repositoryProvider)
            .syncTrip(current.id, current.version, body);
        await ref.read(databaseProvider).remove(scope, string(operation, 'id'));
        return saved;
      },
    );
    if (result != null && mounted) {
      setState(() => revision++);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('offline'))),
    body: RemoteContent<Json>(
      key: ValueKey(revision),
      load: load,
      builder: (data, _) => PageBody(
        children: [
          Notice(context.t('offlineCacheNotice')),
          const SizedBox(height: 16),
          if (widget.trip != null)
            FilledButton.icon(
              onPressed: download,
              icon: const Icon(Icons.download),
              label: Text(context.t('downloadTrip')),
            ),
          Section(context.t('savedTrips')),
          for (final item in objects(data['snapshots']))
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      string(object(object(item['data'])['trip']), 'title'),
                    ),
                    subtitle: Text(
                      '${context.t('savedAt')}: ${item['savedAt']}',
                    ),
                    onTap: () => openScreen(
                      context,
                      Scaffold(
                        appBar: AppBar(title: Text(context.t('offline'))),
                        body: PageBody(
                          children: [
                            Notice(context.t('cachedRead')),
                            ServerResult(item['data']),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => edit(item),
                    child: Text(context.t('queueEdit')),
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: () => queueRecord(item, 'expense'),
                        child: Text(context.t('addExpense')),
                      ),
                      TextButton(
                        onPressed: () => queueRecord(item, 'journal'),
                        child: Text(context.t('newEntry')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (objects(data['snapshots']).isEmpty) Text(context.t('empty')),
          Section(context.t('pendingOperations')),
          for (final op in objects(data['operations']))
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${op['kind']} · ${op['state']}'),
                    if (op['error'] != null)
                      Notice(op['error'].toString(), error: true),
                    ServerResult(op['body']),
                    Wrap(
                      spacing: 12,
                      children: [
                        FilledButton(
                          onPressed: syncing ? null : () => sync(op),
                          child: Text(context.t('retry')),
                        ),
                        TextButton(
                          onPressed: syncing
                              ? null
                              : () async {
                                  if (await confirmDialog(
                                    context,
                                    context.t('discard'),
                                    context.t('discardConfirm'),
                                  )) {
                                    await ref
                                        .read(databaseProvider)
                                        .remove(scope, string(op, 'id'));
                                    if (mounted) {
                                      setState(() => revision++);
                                    }
                                  }
                                },
                          child: Text(context.t('discard')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (objects(data['operations']).isEmpty) Text(context.t('noPending')),
        ],
      ),
    ),
  );
}
