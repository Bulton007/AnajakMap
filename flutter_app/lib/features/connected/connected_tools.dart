import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../core/network/travel_repository.dart';
import '../../shared/models/server_models.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';
import 'connected_upload.dart';
import 'connected_explore.dart';
import 'connected_generation.dart';

class ConnectedTools extends ConsumerStatefulWidget {
  const ConnectedTools({
    super.key,
    required this.tool,
    required this.profile,
    this.trip,
  });
  final String tool;
  final Json profile;
  final ServerTrip? trip;
  @override
  ConsumerState<ConnectedTools> createState() => _ToolsState();
}

class _ToolsState extends ConsumerState<ConnectedTools> {
  int version = 0, page = 0;
  TravelRepository get repo => ref.read(repositoryProvider);
  String get tripId => widget.trip!.id;
  String get scope =>
      '${ref.read(environmentProvider).normalizedUrl}|${widget.profile['id']}';
  void refresh() {
    if (mounted) {
      setState(() => version++);
    }
  }

  Future<Object?> load() => switch (widget.tool) {
    'expenses' => _expenses(),
    'reservations' => repo.reservations(tripId, page: page),
    'group' => _group(),
    'journal' => repo.journal(tripId, page: page),
    'calendar' => repo.calendar(tripId),
    'transport' => repo.journeys(tripId),
    'contacts' => repo.snapshot(tripId).then((s) => s['contacts']),
    'notifications' => repo.deliveries(page: page),
    'translation' => repo.phrases(),
    _ => Future.value(null),
  };
  Future<Json> _expenses() async => {
    'summary': await repo.summary(tripId),
    'expenses': await repo.expenses(tripId, page: page),
  };
  Future<Json> _group() async => {
    'members': await repo.members(tripId),
    'locations': await repo.locations(tripId),
  };
  Future<void> form(
    String title,
    List<InputSpec> fields,
    Future<Object?> Function(Json, String) submit, {
    String? notice,
  }) async {
    await remoteForm(context, title, fields, submit: submit, notice: notice);
    refresh();
  }

  List<InputSpec> times() => [
    InputSpec(
      'startsAt',
      kind: InputKind.instant,
      initial: '${widget.trip!.startDate}T09:00:00+07:00',
    ),
    InputSpec(
      'endsAt',
      kind: InputKind.instant,
      initial: '${widget.trip!.startDate}T10:00:00+07:00',
    ),
    InputSpec('timezone', initial: widget.trip!.timezone),
  ];
  Future<void> expense({Json? extraction, String? receipt}) async {
    final members = await runRequest(context, () => repo.members(tripId));
    if (members == null || !mounted) {
      return;
    }
    final amount = string(extraction ?? {}, 'amount', '12.50');
    await form(
      'addExpense',
      [
        const InputSpec('description'),
        InputSpec('amount', kind: InputKind.amount, initial: amount),
        InputSpec(
          'currency',
          label: 'currencyCode',
          initial: string(extraction ?? {}, 'currency', 'USD'),
          choices: const ['USD', 'KHR', 'EUR'],
        ),
        for (final m in members)
          InputSpec(
            'split_${string(m, 'accountId')}',
            label: '${context.t('splitAmount')} · ${string(m, 'accountId')}',
            kind: InputKind.amount,
            optional: true,
            initial: string(m, 'accountId') == widget.profile['id']
                ? amount
                : '',
          ),
      ],
      (body, key) async {
        final splits = <String, String>{
          for (final m in members)
            if (body['split_${string(m, 'accountId')}'] != null)
              string(m, 'accountId'): body['split_${string(m, 'accountId')}'],
        };
        BigInt minor(String v) =>
            BigInt.parse(decimalAmount(v).replaceAll('.', ''));
        if (splits.values.fold(BigInt.zero, (sum, v) => sum + minor(v)) !=
            minor(body['amount'])) {
          throw FormatException(context.t('splitHint'));
        }
        return repo.addExpense({
          'tripId': tripId,
          'description': body['description'],
          'amount': body['amount'],
          'currency': body['currency'],
          'splits': splits,
          'receiptId': ?receipt,
        }, key);
      },
      notice:
          '${context.t('splitHint')}\n${context.t('reviewBeforeSave')}${extraction == null ? '' : '\n${context.t('uncertain')}: ${string(extraction, 'source', context.t('sourceUnknown'))}'}',
    );
  }

  Future<void> receipt() async {
    final file = await uploadMedia(
      context,
      'expenses/receipts',
      tripId: tripId,
    );
    if (file == null || !mounted) {
      return;
    }
    final extracted = await runRequest(
      context,
      () => repo.extractReceipt(string(file, 'id')),
    );
    if (extracted != null && mounted) {
      await expense(
        extraction: object(extracted['extraction']),
        receipt: string(file, 'id'),
      );
    }
  }

  Future<void> reservation({Json? document}) async {
    final extracted = object(document?['extraction']);
    await form(
      'addReservation',
      [
        InputSpec('provider', initial: string(extracted, 'provider')),
        InputSpec(
          'reference',
          label: 'referenceNumber',
          initial: string(extracted, 'reference'),
        ),
        for (final f in times())
          InputSpec(
            f.key,
            kind: f.kind,
            initial: string(extracted, f.key, f.initial),
          ),
      ],
      (body, key) => document == null
          ? repo.manualReservation({'tripId': tripId, ...body}, key)
          : repo.confirmReservation(string(document, 'documentId'), {
              ...body,
              'version': integer(document, 'version'),
            }),
      notice: context.t('reviewBeforeSave'),
    );
  }

  Future<void> extractBooking() async {
    final file = await uploadMedia(
      context,
      'reservations/documents',
      tripId: tripId,
    );
    if (file == null || !mounted) {
      return;
    }
    final draft = await runRequest(
      context,
      () => repo.extractReservation(string(file, 'documentId')),
    );
    if (draft != null && mounted) {
      await reservation(document: draft);
    }
  }

  Future<void> journal({Json? entry, Json? suggested}) async {
    await form(
      entry == null ? 'newEntry' : 'edit',
      [
        InputSpec(
          'title',
          label: 'journalTitle',
          initial: string(entry ?? {}, 'title'),
        ),
        InputSpec(
          'content',
          kind: InputKind.multiline,
          initial: string(entry ?? {}, 'content'),
        ),
        InputSpec(
          'recap',
          kind: InputKind.multiline,
          optional: true,
          initial: string(
            suggested ?? entry ?? {},
            'text',
            string(entry ?? {}, 'recap'),
          ),
        ),
      ],
      (body, key) => repo.saveJournal(
        {
          ...body,
          'recap': body['recap'] ?? '',
          'tripId': tripId,
          'version': integer(entry ?? {}, 'version'),
        },
        key,
        id: entry == null ? null : string(entry, 'id'),
      ),
      notice: suggested == null ? null : context.t('aiTrustBody'),
    );
  }

  Future<void> location(bool enabled) async {
    final deniedMessage = context.t('locationDenied');
    if (!enabled) {
      await runRequest(context, () => repo.location(tripId, false, 0, 0));
      refresh();
      return;
    }
    if (!await confirmDialog(
          context,
          context.t('shareLocation'),
          context.t('locationConsent'),
        ) ||
        !mounted) {
      return;
    }
    await runRequest(context, () async {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError(deniedMessage);
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 20),
        ),
      );
      return repo.location(tripId, true, p.latitude, p.longitude);
    });
    refresh();
  }

  Widget action(String label, VoidCallback run, {IconData icon = Icons.add}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 10),
        child: OutlinedButton.icon(
          onPressed: run,
          icon: Icon(icon, size: 18),
          label: Text(context.t(label)),
        ),
      );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t(widget.tool)),
      actions: [
        IconButton(
          tooltip: context.t('refresh'),
          onPressed: refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: RemoteContent<Object?>(
      key: ValueKey('$version:$page'),
      load: load,
      builder: (data, _) => PageBody(
        children: [
          if (widget.trip != null) ...[
            Text(
              widget.trip!.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            children: [
              if (widget.tool == 'expenses') ...[
                action('addExpense', () => expense()),
                action(
                  'scanExpense',
                  receipt,
                  icon: Icons.document_scanner_outlined,
                ),
                action(
                  'budget',
                  () => form(
                    'budget',
                    [
                      const InputSpec(
                        'amount',
                        label: 'budgetAmount',
                        kind: InputKind.amount,
                      ),
                      const InputSpec(
                        'currency',
                        initial: 'USD',
                        choices: ['USD', 'KHR', 'EUR'],
                      ),
                    ],
                    (body, _) async {
                      final budgets = objects(
                        (await repo.summary(tripId))['budgets'],
                      );
                      return repo.budget(
                        tripId,
                        body['amount'],
                        body['currency'],
                        budgets.isEmpty ? 0 : integer(budgets.first, 'version'),
                      );
                    },
                  ),
                ),
                action('currencyConvert', () async {
                  final result = await remoteForm(
                    context,
                    'currencyConvert',
                    [
                      const InputSpec(
                        'from',
                        label: 'fromCurrency',
                        initial: 'USD',
                        choices: ['USD', 'KHR', 'EUR'],
                      ),
                      const InputSpec(
                        'to',
                        label: 'toCurrency',
                        initial: 'KHR',
                        choices: ['USD', 'KHR', 'EUR'],
                      ),
                      const InputSpec('amount', kind: InputKind.amount),
                    ],
                    submit: (body, _) =>
                        repo.currency(body['from'], body['to'], body['amount']),
                  );
                  if (context.mounted && result != null) {
                    openScreen(
                      context,
                      Scaffold(
                        appBar: AppBar(
                          title: Text(context.t('currencyConvert')),
                        ),
                        body: PageBody(children: [ServerResult(result)]),
                      ),
                    );
                  }
                }),
              ],
              if (widget.tool == 'reservations') ...[
                action('addReservation', () => reservation()),
                action('extraction', extractBooking, icon: Icons.upload_file),
              ],
              if (widget.tool == 'group') ...[
                action(
                  'inviteMember',
                  () => form(
                    'inviteMember',
                    [
                      const InputSpec('accountId'),
                      const InputSpec(
                        'role',
                        initial: 'VIEWER',
                        choices: ['VIEWER', 'EDITOR'],
                      ),
                    ],
                    (b, _) => repo.invite(tripId, b['accountId'], b['role']),
                  ),
                ),
                action(
                  'shareLocation',
                  () => location(true),
                  icon: Icons.my_location,
                ),
                action(
                  'stopSharing',
                  () => location(false),
                  icon: Icons.location_disabled,
                ),
              ],
              if (widget.tool == 'journal') ...[
                action('newEntry', () => journal()),
                action(
                  'visitedPlace',
                  () => form('visitedPlace', [
                    const InputSpec('place'),
                    const InputSpec('visitedAt', kind: InputKind.instant),
                    const InputSpec('latitude', kind: InputKind.number),
                    const InputSpec('longitude', kind: InputKind.number),
                  ], (b, _) => repo.visit({'tripId': tripId, ...b})),
                ),
              ],
              if (widget.tool == 'calendar') ...[
                action(
                  'addEvent',
                  () => form('addEvent', [
                    const InputSpec('title'),
                    ...times(),
                  ], (b, _) => repo.event(tripId, b)),
                ),
                action('syncCalendar', () async {
                  if (await confirmDialog(
                        context,
                        context.t('syncCalendar'),
                        context.t('confirm'),
                      ) &&
                      context.mounted) {
                    await runRequest(
                      context,
                      () => repo.syncCalendar(tripId, ApiClient.operationId()),
                    );
                    refresh();
                  }
                }),
              ],
              if (widget.tool == 'contacts')
                action(
                  'addContact',
                  () => form('addContact', [
                    const InputSpec('label', label: 'title'),
                    const InputSpec('phone'),
                  ], (b, _) => repo.contact(tripId, b['label'], b['phone'])),
                ),
              if (widget.tool == 'transport')
                action(
                  'addJourney',
                  () => form('addJourney', [
                    const InputSpec('origin'),
                    const InputSpec('destination'),
                    const InputSpec('departure', kind: InputKind.instant),
                    const InputSpec('arrival', kind: InputKind.instant),
                    InputSpec('timezone', initial: widget.trip!.timezone),
                    const InputSpec('transferDetails'),
                    const InputSpec('source'),
                  ], (b, _) => repo.saveJourney({'tripId': tripId, ...b})),
                ),
              if (widget.tool == 'notifications')
                action(
                  'addReminder',
                  () => form('addReminder', [
                    const InputSpec('title'),
                    const InputSpec('dueAt', kind: InputKind.instant),
                  ], (b, _) => repo.reminder(b['title'], b['dueAt'])),
                ),
            ],
          ),
          if (widget.tool == 'notifications') Notice(context.t('pushSetup')),
          if (widget.tool == 'journal') ...[
            for (final entry in objects(data))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        string(entry, 'title'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(string(entry, 'content')),
                      if (string(entry, 'recap').isNotEmpty)
                        Text(string(entry, 'recap')),
                      Wrap(
                        children: [
                          action(
                            'edit',
                            () => journal(entry: entry),
                            icon: Icons.edit_outlined,
                          ),
                          action('generateRecap', () async {
                            final result = await runRequest(
                              context,
                              () => repo.guide('recap', {
                                'text': string(entry, 'content'),
                              }),
                            );
                            if (result != null && mounted) {
                              await journal(
                                entry: entry,
                                suggested: object(result),
                              );
                            }
                          }, icon: Icons.auto_awesome),
                          action('uploadPhoto', () async {
                            await uploadMedia(
                              context,
                              'journal/${string(entry, 'id')}/photos',
                              tripId: null,
                            );
                            refresh();
                          }, icon: Icons.photo_camera_outlined),
                          action(
                            'photos',
                            () => openScreen(
                              context,
                              JournalPhotos(entryId: string(entry, 'id')),
                            ),
                            icon: Icons.photo_library_outlined,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (objects(data).isEmpty) Text(context.t('empty')),
          ] else ...[
            const SizedBox(height: 16),
            ServerResult(data),
          ],
          if (widget.tool == 'group')
            for (final member in objects(object(data)['members']))
              if (string(member, 'role') != 'OWNER')
                TextButton(
                  onPressed: () async {
                    if (await confirmDialog(
                          context,
                          context.t('removeMember'),
                          string(member, 'accountId'),
                        ) &&
                        context.mounted) {
                      await runRequest(
                        context,
                        () => repo.removeMember(
                          tripId,
                          string(member, 'accountId'),
                        ),
                      );
                      refresh();
                    }
                  },
                  child: Text(
                    '${context.t('removeMember')}: ${string(member, 'accountId')}',
                  ),
                ),
          if ([
            'expenses',
            'reservations',
            'journal',
            'notifications',
          ].contains(widget.tool))
            Row(
              children: [
                IconButton(
                  tooltip: context.t('back'),
                  onPressed: page == 0 ? null : () => setState(() => page--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${page + 1}'),
                IconButton(
                  tooltip: context.t('next'),
                  onPressed: () => setState(() => page++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class JournalPhotos extends ConsumerWidget {
  const JournalPhotos({super.key, required this.entryId});
  final String entryId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(context.t('photos'))),
    body: RemoteContent<List<Json>>(
      load: () => ref.read(repositoryProvider).photos(entryId),
      builder: (rows, _) => PageBody(
        children: [
          for (final row in rows)
            FutureBuilder(
              future: ref
                  .read(repositoryProvider)
                  .media('journal/photos/${string(row, 'id')}/content'),
              builder: (c, s) => s.hasData
                  ? Image.memory(s.data!)
                  : s.hasError
                  ? Notice('${s.error}', error: true)
                  : const LinearProgressIndicator(),
            ),
          if (rows.isEmpty) Text(context.t('empty')),
        ],
      ),
    ),
  );
}

class CompanionTasks extends ConsumerWidget {
  const CompanionTasks({super.key, required this.profile});
  final Json profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    children: [
      Text(
        context.t('aiTitle'),
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 16),
      Notice(context.t('aiTrustBody')),
      const SizedBox(height: 20),
      for (final task in ['generate', 'translate', 'vision', 'voice', 'chat'])
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ActionCard(
            icon: Icons.auto_awesome_outlined,
            title: context.t(task),
            subtitle: context.t('aiSubtitle'),
            onTap: () async {
              if (task == 'generate') {
                final trip = await selectTrip(context, ref);
                if (trip != null && context.mounted) {
                  openScreen(
                    context,
                    ConnectedGeneration(trip: trip, profile: profile),
                  );
                }
              } else {
                openScreen(
                  context,
                  AssistanceTask(task: task, profile: profile),
                );
              }
            },
          ),
        ),
    ],
  );
}

class AssistanceTask extends ConsumerStatefulWidget {
  const AssistanceTask({super.key, required this.task, required this.profile});
  final String task;
  final Json profile;
  @override
  ConsumerState<AssistanceTask> createState() => _AssistanceState();
}

class _AssistanceState extends ConsumerState<AssistanceTask> {
  Object? result;
  String? conversationId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t(widget.task))),
    body: PageBody(
      children: [
        Notice(context.t('aiTrustBody')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            final repo = ref.read(repositoryProvider);
            if (widget.task == 'vision' || widget.task == 'voice') {
              final media = await uploadMedia(
                context,
                'guide/media',
                audio: widget.task == 'voice',
              );
              if (media == null || !context.mounted) {
                return;
              }
              final data = await runRequest(
                context,
                () => repo.guide(widget.task, {'mediaId': media['mediaId']}),
              );
              if (mounted) {
                setState(() => result = data);
              }
            } else {
              final data = await remoteForm(
                context,
                widget.task,
                [
                  InputSpec(
                    'text',
                    label: widget.task == 'chat'
                        ? 'message'
                        : 'translationText',
                    kind: InputKind.multiline,
                  ),
                  if (widget.task != 'chat')
                    const InputSpec(
                      'targetLanguage',
                      initial: 'km',
                      choices: ['km', 'en'],
                    ),
                ],
                submitLabel: 'confirm',
                submit: (body, _) async {
                  if (widget.task == 'chat') {
                    conversationId ??= string(await repo.conversation(), 'id');
                    return repo.message(conversationId!, body['text']);
                  }
                  return repo.guide('translation', body);
                },
              );
              if (mounted && data != null) {
                setState(() => result = data);
              }
            }
          },
          child: Text(
            context.t(
              widget.task == 'vision' || widget.task == 'voice'
                  ? 'chooseFile'
                  : 'next',
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (result != null) ...[
          ServerResult(result),
          const SizedBox(height: 16),
          if (widget.task == 'translate')
            OutlinedButton(
              onPressed: () => remoteForm(
                context,
                'saveTranslation',
                [
                  InputSpec(
                    'text',
                    kind: InputKind.multiline,
                    initial: string(
                      object(result),
                      'translatedText',
                      string(object(result), 'text'),
                    ),
                  ),
                ],
                submit: (b, _) =>
                    ref.read(repositoryProvider).savePhrase(b['text']),
              ),
              child: Text(context.t('saveTranslation')),
            ),
        ],
        if (widget.task == 'translate')
          TextButton(
            onPressed: () => openScreen(
              context,
              ConnectedTools(tool: 'translation', profile: widget.profile),
            ),
            child: Text(context.t('savedPhrases')),
          ),
      ],
    ),
  );
}
