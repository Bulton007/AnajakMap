import '../../shared/components/visual.dart';
import '../../shared/components/travel_panels.dart';
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
import 'companion_chat.dart';
import '../../shared/components/travel_alerts.dart';
import 'connected_explore.dart';
import 'connected_generation.dart';
import 'recommendations.dart';
import 'voice_assistance.dart';
import 'ai_service_status.dart';
import 'connected_trips.dart';
import 'trip_invitations.dart';
import 'trip_chat.dart';
import 'device_notification_settings.dart';

class ConnectedTools extends ConsumerStatefulWidget {
  const ConnectedTools({
    super.key,
    required this.tool,
    required this.profile,
    this.trip,
    this.initialNotification,
  });
  final String tool;
  final Json profile;
  final ServerTrip? trip;
  final Json? initialNotification;
  @override
  ConsumerState<ConnectedTools> createState() => _ToolsState();
}

class _ToolsState extends ConsumerState<ConnectedTools> {
  int version = 0, page = 0;
  @override
  void initState() {
    super.initState();
    if (widget.tool == 'notifications') {
      ref.listenManual(notificationUpdateProvider, (_, _) => refresh());
      if (widget.initialNotification case final notification?) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) openNotification(notification);
        });
      }
    }
  }

  TravelRepository get repo => ref.read(repositoryProvider);
  String get tripId => widget.trip!.id;
  String get scope =>
      '${ref.read(environmentProvider).normalizedUrl}|${widget.profile['id']}';
  void refresh() {
    if (mounted) {
      setState(() => version++);
    }
  }

  Future<void> notificationAction(Future<Object?> Function() action) async {
    final done = await runRequest(context, () async {
      await action();
      return true;
    });
    if (mounted && done == true) ref.invalidate(notificationUpdateProvider);
  }

  Future<void> openNotification(Json row) async {
    final id = string(row, 'id');
    await notificationAction(() => repo.readNotification(id));
    if (!mounted) return;
    final trip = string(row, 'tripId');
    final account = string(widget.profile, 'id');
    if (string(row, 'kind') == 'chat.direct-message') {
      openScreen(
        context,
        TripChat.direct(peerId: string(row, 'actorId'), accountId: account),
      );
      return;
    }
    if (trip.isEmpty) return;
    switch (string(row, 'kind')) {
      case 'group.invited':
        openScreen(context, TripInvitations(tripId: trip));
      case 'group.joined':
      case 'group.invitation-rejected':
      case 'itinerary.approved':
        openScreen(
          context,
          ConnectedTripDetail(tripId: trip, profile: widget.profile),
        );
      case 'chat.trip-message':
        openScreen(context, TripChat(tripId: trip, accountId: account));
    }
  }

  Widget notificationCard(Json row) {
    final id = string(row, 'id');
    final sender = string(row, 'actorId');
    final due = DateTime.tryParse(string(row, 'dueAt'));
    final pending =
        string(row, 'kind') == 'REMINDER' && string(row, 'status') == 'PENDING';
    final unread =
        field(row, 'readAt') == null &&
        due != null &&
        !due.isAfter(DateTime.now()) &&
        string(row, 'status') != 'CANCELLED';
    return TravelNotificationCard(
      delivery: row,
      unread: unread,
      sender: sender.isEmpty ? null : TravelerName(accountId: sender),
      onOpen:
          string(row, 'tripId').isNotEmpty ||
              string(row, 'kind') == 'chat.direct-message'
          ? () => openNotification(row)
          : null,
      actions: [
        if (unread)
          TextButton.icon(
            onPressed: () =>
                notificationAction(() => repo.readNotification(id)),
            icon: const Icon(Icons.done_all_rounded, size: 16),
            label: Text(context.isKhmer ? 'សម្គាល់ថាបានអាន' : 'Mark as read'),
          ),
        if (pending) ...[
          TextButton(
            onPressed: () => form(
              'edit',
              [
                InputSpec('title', initial: string(row, 'title')),
                InputSpec(
                  'dueAt',
                  kind: InputKind.instant,
                  initial: string(row, 'dueAt'),
                ),
              ],
              (body, _) =>
                  repo.updateReminder(id, body['title'], body['dueAt']),
            ),
            child: Text(context.t('edit')),
          ),
          TextButton(
            onPressed: () async {
              if (await confirmDialog(
                    context,
                    context.t('cancel'),
                    string(row, 'title'),
                  ) &&
                  mounted) {
                await notificationAction(() => repo.cancelReminder(id));
              }
            },
            child: Text(context.t('cancel')),
          ),
        ],
      ],
    );
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
  Future<Json> _group() async {
    final members = await repo.members(tripId);
    final own = members.any(
      (member) =>
          string(member, 'role') == 'OWNER' &&
          string(member, 'accountId') == string(widget.profile, 'id'),
    );
    return {
      'members': members,
      'locations': await repo.locations(tripId),
      if (own) 'invitations': await repo.sentInvitations(tripId),
    };
  }

  String _memberName(Json member, int index) {
    if (string(member, 'accountId') == widget.profile['id']) {
      final ownName = string(widget.profile, 'name');
      if (ownName.isNotEmpty) return ownName;
    }
    for (final key in ['displayName', 'name', 'fullName', 'email']) {
      final value = string(member, key).trim();
      if (value.isNotEmpty) return value;
    }
    return '${context.isKhmer ? 'សមាជិក' : 'Traveler'} ${index + 1}';
  }

  String _equalShare(String amount, int count, int index) {
    final normalized = decimalAmount(amount);
    final parts = normalized.split('.');
    final cents =
        BigInt.parse(parts.first) * BigInt.from(100) +
        BigInt.parse(
          (parts.length > 1 ? parts[1] : '').padRight(2, '0').substring(0, 2),
        );
    final divisor = BigInt.from(count);
    final share =
        cents ~/ divisor +
        (BigInt.from(index) < cents % divisor ? BigInt.one : BigInt.zero);
    return '${share ~/ BigInt.from(100)}.${(share % BigInt.from(100)).toString().padLeft(2, '0')}';
  }

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
        for (final (index, m) in members.indexed)
          InputSpec(
            'split_${string(m, 'accountId')}',
            label:
                '${context.isKhmer ? 'ចំណែក' : 'Share'} · ${_memberName(m, index)}',
            kind: InputKind.amount,
            optional: true,
            initial: _equalShare(amount, members.length, index),
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
          ? repo.manualReservation({
              'tripId': tripId,
              ...body,
              'timezone': widget.trip!.timezone,
            }, key)
          : repo.confirmReservation(string(document, 'documentId'), {
              ...body,
              'timezone': widget.trip!.timezone,
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

  Widget action(String label, VoidCallback? run, {IconData icon = Icons.add}) =>
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
          if (widget.tool == 'calendar' && widget.trip != null)
            TravelHero(
              title: widget.trip!.title,
              subtitle: context.t('calendarJourney'),
              icon: Icons.calendar_month_outlined,
            )
          else if (widget.trip != null) ...[
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
                  ref
                              .watch(guideCapabilitiesProvider)
                              .asData
                              ?.value['receipt'] ==
                          true
                      ? receipt
                      : null,
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
                action(
                  'extraction',
                  ref
                              .watch(guideCapabilitiesProvider)
                              .asData
                              ?.value['reservation'] ==
                          true
                      ? extractBooking
                      : null,
                  icon: Icons.upload_file,
                ),
              ],
              if (widget.tool == 'group') ...[
                action(
                  'inviteMember',
                  () => form(
                    'inviteMember',
                    [
                      InputSpec(
                        'accountId',
                        label: context.isKhmer
                            ? 'លេខគណនីអ្នកធ្វើដំណើរ'
                            : 'Traveler account code',
                      ),
                      const InputSpec(
                        'role',
                        initial: 'VIEWER',
                        choices: ['VIEWER', 'EDITOR'],
                      ),
                    ],
                    (b, _) async {
                      final account = await repo.traveler(
                        b['accountId'].toString().trim(),
                      );
                      if (!context.mounted) return null;
                      final name = string(
                        account,
                        'displayName',
                        string(account, 'id'),
                      );
                      if (!await confirmDialog(
                        context,
                        context.t('inviteMember'),
                        name,
                      )) {
                        return null;
                      }
                      return repo.invite(
                        tripId,
                        string(account, 'id'),
                        b['role'],
                      );
                    },
                    notice: context.isKhmer
                        ? 'ការអញ្ជើញតាម API បច្ចុប្បន្នត្រូវការលេខគណនី Anajak របស់អ្នកធ្វើដំណើរ។'
                        : 'The current invitation API requires the traveler’s Anajak account code.',
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
                  () => form(
                    'addEvent',
                    [const InputSpec('title'), ...times()],
                    (b, _) => repo.event(tripId, {
                      ...b,
                      'timezone': widget.trip!.timezone,
                    }),
                  ),
                ),
                action('syncCalendar', () async {
                  if (await confirmDialog(
                        context,
                        context.t('syncCalendar'),
                        context.t('confirm'),
                      ) &&
                      context.mounted) {
                    final result = await runRequest(
                      context,
                      () => repo.syncCalendar(tripId, ApiClient.operationId()),
                    );
                    if (result != null && context.mounted) {
                      final mocked =
                          string(object(result), 'status') == 'MOCK_SYNCED' ||
                          object(result)['mock'] == true;
                      await inform(
                        context,
                        context.t('syncCalendar'),
                        mocked
                            ? (context.isKhmer
                                  ? 'ការសាកល្បងប៉ុណ្ណោះ៖ មិនមានការផ្លាស់ប្តូរក្នុងប្រតិទិនខាងក្រៅទេ។'
                                  : 'Test simulation only: no external calendar was changed.')
                            : (context.isKhmer
                                  ? 'បានផ្ញើសំណើសមកាលកម្មទៅសេវាប្រតិទិន។'
                                  : 'The calendar sync request was accepted by the configured provider.'),
                      );
                    }
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
                  () => form(
                    'addJourney',
                    [
                      const InputSpec('origin'),
                      const InputSpec('destination'),
                      const InputSpec('departure', kind: InputKind.instant),
                      const InputSpec('arrival', kind: InputKind.instant),
                      const InputSpec('transferDetails'),
                      const InputSpec('source'),
                    ],
                    (b, _) => repo.saveJourney({
                      'tripId': tripId,
                      ...b,
                      'timezone': widget.trip!.timezone,
                    }),
                  ),
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
          if ((widget.tool == 'expenses' &&
                  ref
                          .watch(guideCapabilitiesProvider)
                          .asData
                          ?.value['receipt'] !=
                      true) ||
              (widget.tool == 'reservations' &&
                  ref
                          .watch(guideCapabilitiesProvider)
                          .asData
                          ?.value['reservation'] !=
                      true)) ...[
            Notice(
              context.isKhmer
                  ? 'ការអានឯកសារដោយ AI មិនទាន់បានកំណត់រចនាសម្ព័ន្ធទេ។ អ្នកអាចបញ្ចូលព័ត៌មានដោយខ្លួនឯងបាន។'
                  : 'AI document scanning is not configured yet. You can add the details manually.',
              icon: Icons.edit_note_rounded,
            ),
            const SizedBox(height: 12),
          ],
          if (widget.tool == 'notifications')
            ExpansionTile(
              key: const PageStorageKey('device-notification-controls'),
              tilePadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.notifications_active_outlined,
                size: 20,
              ),
              title: Text(
                context.isKhmer
                    ? 'ការកំណត់ការជូនដំណឹង'
                    : 'Phone notification settings',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              children: [DeviceNotificationSettings(scope: scope)],
            ),
          if (widget.tool == 'notifications')
            ExpansionTile(
              key: const PageStorageKey('notification-delivery-information'),
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.info_outline, size: 20),
              title: Text(
                context.isKhmer
                    ? 'អំពីការជូនដំណឹង'
                    : 'About notification delivery',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    context.isKhmer
                        ? 'សារថ្មីត្រូវការកម្មវិធីភ្ជាប់អ៊ីនធឺណិត។ ការរំលឹកដែលបានកំណត់លើទូរសព្ទអាចបង្ហាញនៅពេលបិទកម្មវិធី។ ប្រព័ន្ធជំរុញត្រូវការការកំណត់សេវា។'
                        : 'Messages need the app to be connected. Reminders scheduled on this phone can appear when it is closed. Remote push needs a configured delivery service.',
                  ),
                ),
              ],
            ),
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
          ] else if (widget.tool == 'calendar') ...[
            CalendarPanel(data: object(data), zone: widget.trip!.timezone),
          ] else if (widget.tool == 'group') ...[
            if (objects(object(data)['invitations']).isNotEmpty) ...[
              Section(
                context.isKhmer ? 'ការអញ្ជើញដែលបានផ្ញើ' : 'Sent invitations',
              ),
              for (final invite in objects(object(data)['invitations']))
                Card(
                  child: ListTile(
                    title: TravelerName(accountId: string(invite, 'accountId')),
                    subtitle: Text(string(invite, 'status')),
                    trailing: string(invite, 'status') == 'PENDING'
                        ? TextButton(
                            onPressed: () async {
                              final cancelled = await runRequest(
                                context,
                                () => repo.cancelInvite(
                                  tripId,
                                  string(invite, 'accountId'),
                                ),
                              );
                              if (cancelled != null) refresh();
                            },
                            child: Text(context.t('cancel')),
                          )
                        : null,
                  ),
                ),
            ],
            Section(context.isKhmer ? 'សមាជិកដំណើរ' : 'Trip members'),
            for (final (index, member) in objects(
              object(data)['members'],
            ).indexed)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(_memberName(member, index)),
                  subtitle: Text(switch (string(member, 'role').toUpperCase()) {
                    'OWNER' =>
                      context.isKhmer
                          ? 'ម្ចាស់ · គ្រប់គ្រងដំណើរ និងសមាជិក'
                          : 'Owner · manages trip and members',
                    'EDITOR' =>
                      context.isKhmer
                          ? 'អ្នកកែសម្រួល · អាចកែប្រែដំណើរ'
                          : 'Editor · can change trip details',
                    _ =>
                      context.isKhmer
                          ? 'អ្នកមើល · មើលព័ត៌មានដំណើរ'
                          : 'Viewer · can view trip details',
                  }),
                  trailing: string(member, 'role') == 'OWNER'
                      ? const Icon(Icons.workspace_premium_outlined)
                      : IconButton(
                          tooltip: context.t('removeMember'),
                          onPressed: () async {
                            final name = _memberName(member, index);
                            if (await confirmDialog(
                                  context,
                                  context.t('removeMember'),
                                  name,
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
                          icon: const Icon(Icons.person_remove_alt_1_outlined),
                        ),
                ),
              ),
            if (objects(object(data)['members']).isEmpty)
              VisualEmpty(
                icon: Icons.people_outline,
                title: context.t('empty'),
              ),
            Section(context.isKhmer ? 'ការចែករំលែកទីតាំង' : 'Location sharing'),
            if (objects(object(data)['locations']).isEmpty)
              VisualEmpty(
                icon: Icons.location_disabled_outlined,
                title: context.isKhmer
                    ? 'មិនមានទីតាំងកំពុងចែករំលែកទេ'
                    : 'No locations are being shared',
              ),
            if (objects(object(data)['locations']).isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.my_location),
                  title: Text(
                    context.isKhmer
                        ? 'អ្នកធ្វើដំណើរ ${objects(object(data)['locations']).length} នាក់កំពុងចែករំលែកទីតាំង'
                        : '${objects(object(data)['locations']).length} travelers are sharing locations',
                  ),
                  subtitle: Text(
                    context.isKhmer
                        ? 'អ្នកចែករំលែក និងសមាជិកដំណើរអាចមើលទីតាំងរហូតដល់ផុតកំណត់។'
                        : 'Shared locations are visible to trip members until they expire.',
                  ),
                ),
              ),
          ] else if (widget.tool == 'contacts') ...[
            if (objects(data).isEmpty) Text(context.t('empty')),
            for (final contact in objects(data))
              EmergencyContactCard(contact: contact),
          ] else if (widget.tool == 'notifications') ...[
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => openScreen(context, const TripInvitations()),
                  child: Text(
                    context.isKhmer
                        ? 'ការអញ្ជើញចូលរួមដំណើរ'
                        : 'Trip invitations',
                  ),
                ),
                TextButton(
                  onPressed: () => notificationAction(repo.readNotifications),
                  child: Text(
                    context.isKhmer
                        ? 'សម្គាល់ទាំងអស់ថាបានអាន'
                        : 'Mark all as read',
                  ),
                ),
              ],
            ),
            if (objects(data).isEmpty) Text(context.t('empty')),
            for (final delivery in {
              for (final item in objects(data)) string(item, 'id'): item,
            }.values)
              notificationCard(delivery),
          ] else ...[
            const SizedBox(height: 16),
            ServerResult(data),
          ],
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
      TravelHero(
        title: context.t('aiTitle'),
        subtitle: context.t('tagline'),
        icon: Icons.auto_awesome,
      ),
      const SizedBox(height: 16),
      const AiServiceStatus(),
      const SizedBox(height: 20),
      Column(
        spacing: 8,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VisualAction(
            horizontal: true,
            icon: Icons.travel_explore,
            label: context.t('recommendTitle'),
            onTap: () =>
                openScreen(context, TripRecommendations(profile: profile)),
          ),
          for (final task in [
            'generate',
            'translate',
            'vision',
            'voice',
            'chat',
          ])
            VisualAction(
              horizontal: true,
              icon: featureIcon(task),
              label: context.t(task),
              subtitle:
                  ((task == 'voice' || task == 'vision') &&
                      ref
                              .watch(guideCapabilitiesProvider)
                              .asData
                              ?.value[task] !=
                          true)
                  ? (ref.watch(guideCapabilitiesProvider).isLoading
                        ? (context.isKhmer ? 'កំពុងពិនិត្យ…' : 'Checking…')
                        : ref.watch(guideCapabilitiesProvider).hasError
                        ? (context.isKhmer
                              ? 'សូមពិនិត្យការតភ្ជាប់'
                              : 'Check connection above')
                        : (context.isKhmer
                              ? 'មិនទាន់មាននៅឡើយ'
                              : 'Not available yet'))
                  : null,
              onTap:
                  ((task == 'voice' || task == 'vision') &&
                      ref
                              .watch(guideCapabilitiesProvider)
                              .asData
                              ?.value[task] !=
                          true)
                  ? null
                  : () async {
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
                          task == 'chat'
                              ? const CompanionChat()
                              : AssistanceTask(task: task, profile: profile),
                        );
                      }
                    },
            ),
        ],
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
  bool submitting = false;
  String? conversationId;
  @override
  Widget build(BuildContext context) => widget.task == 'voice'
      ? const VoiceAssistanceScreen()
      : Scaffold(
          appBar: AppBar(title: Text(context.t(widget.task))),
          body: PageBody(
            children: [
              TravelHero(
                title: context.t(widget.task),
                subtitle: context.t(
                  widget.task == 'translate' ? 'translateBody' : 'aiSubtitle',
                ),
                icon: featureIcon(widget.task),
              ),
              const AiServiceStatus(),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed:
                    submitting ||
                        (widget.task == 'vision' &&
                            ref
                                    .watch(guideCapabilitiesProvider)
                                    .asData
                                    ?.value['vision'] !=
                                true)
                    ? null
                    : () async {
                        final repo = ref.read(repositoryProvider);
                        if (widget.task == 'vision' || widget.task == 'voice') {
                          if (submitting) return;
                          setState(() => submitting = true);
                          if (widget.task == 'vision') {
                            final consent = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: Text(
                                  context.isKhmer
                                      ? 'ចែករំលែករូបថតជាមួយ AI?'
                                      : 'Share a photo with AI?',
                                ),
                                content: Text(
                                  context.isKhmer
                                      ? 'រូបថតដែលអ្នកជ្រើសរើស និងទិន្នន័យភ្ជាប់របស់វា នឹងផ្ញើទៅម៉ាស៊ីនមេ និង Google Gemini។ ជៀសវាងមុខមនុស្ស ឯកសារឯកជន និងព័ត៌មានរសើប។ លទ្ធផលអាចខុស។'
                                      : 'Your selected photo, including any embedded metadata, will be uploaded to our backend and Google Gemini. Avoid faces, private documents and sensitive information. Recognition can be wrong.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, false),
                                    child: Text(context.t('cancel')),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext, true),
                                    child: Text(
                                      context.isKhmer
                                          ? 'យល់ព្រម និងជ្រើសរូបថត'
                                          : 'Agree and choose photo',
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (consent != true || !context.mounted) {
                              if (mounted) setState(() => submitting = false);
                              return;
                            }
                          }
                          setState(() => submitting = true);
                          try {
                            final media = await uploadMedia(
                              context,
                              'guide/media',
                              audio: widget.task == 'voice',
                              imagesOnly: widget.task == 'vision',
                            );
                            if (media == null || !context.mounted) {
                              return;
                            }
                            final data = await runRequest(
                              context,
                              () => repo.guide(widget.task, {
                                'mediaId': media['mediaId'],
                                if (widget.task == 'vision')
                                  'shareWithProvider': true,
                                'language': context.isKhmer ? 'km' : 'en',
                              }),
                            );
                            if (mounted) {
                              setState(() => result = data);
                            }
                          } finally {
                            if (mounted) setState(() => submitting = false);
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
                                conversationId ??= string(
                                  await repo.conversation(),
                                  'id',
                                );
                                return repo.message(
                                  conversationId!,
                                  body['text'],
                                );
                              }
                              return repo.guide('translation', body);
                            },
                          );
                          if (mounted && data != null) {
                            setState(() => result = data);
                          }
                        }
                      },
                icon: Icon(
                  widget.task == 'translate'
                      ? Icons.translate
                      : widget.task == 'chat'
                      ? Icons.chat_bubble_outline
                      : featureIcon(widget.task),
                ),
                label: Text(
                  context.t(
                    widget.task == 'vision' || widget.task == 'voice'
                        ? 'chooseFile'
                        : 'next',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (result != null) ...[
                CompanionAnswer(data: object(result)),
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
                    ConnectedTools(
                      tool: 'translation',
                      profile: widget.profile,
                    ),
                  ),
                  child: Text(context.t('savedPhrases')),
                ),
            ],
          ),
        );
}
