import '../../shared/formatting/travel_dates.dart';
import 'package:go_router/go_router.dart';
import '../../shared/components/visual.dart';
import 'package:flutter/material.dart';
import 'trip_chat.dart';
import 'trip_invitations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/models/server_models.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';
import 'connected_generation.dart';
import 'connected_tools.dart';
import 'connected_offline.dart';
import 'connected_map.dart';
import 'itinerary_activity_card.dart';
import '../../shared/components/travel_panels.dart';

class ConnectedTrips extends ConsumerStatefulWidget {
  const ConnectedTrips({super.key, required this.profile, this.home = false});
  final Json profile;
  final bool home;
  @override
  ConsumerState<ConnectedTrips> createState() => _ConnectedTripsState();
}

class _ConnectedTripsState extends ConsumerState<ConnectedTrips> {
  List<ServerTrip> trips = [];
  bool busy = true, more = true, development = false;
  Object? error;
  int page = 0;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      if (reset) {
        page = 0;
        final runtime = await repo.runtime();
        development = runtime['developmentProviders'] == true;
      }
      final result = await repo.trips(page: page);
      if (mounted) {
        setState(() {
          trips = reset ? result : [...trips, ...result];
          more = result.length == 20;
          busy = false;
          page++;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          busy = false;
        });
      }
    }
  }

  Future<void> create() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final result = await remoteForm(
      context,
      'createTrip',
      [
        const InputSpec('title', label: 'tripName'),
        const InputSpec('destination', initial: 'Phnom Penh'),
        const InputSpec('timezone', initial: 'Asia/Phnom_Penh'),
        InputSpec(
          'startDate',
          label: 'dates',
          initial: today,
          kind: InputKind.date,
        ),
        InputSpec(
          'endDate',
          label: 'endsAt',
          initial: today,
          kind: InputKind.date,
        ),
        const InputSpec(
          'amount',
          label: 'budgetAmount',
          initial: '350.00',
          kind: InputKind.amount,
        ),
        const InputSpec(
          'currency',
          label: 'currencyCode',
          initial: 'USD',
          choices: ['USD', 'KHR', 'EUR'],
        ),
      ],
      submitLabel: 'createTrip',
      submit: (body, key) async {
        if (DateTime.parse(
          body['endDate'],
        ).isBefore(DateTime.parse(body['startDate']))) {
          throw FormatException(context.t('dates'));
        }
        final repo = ref.read(repositoryProvider);
        final trip = await repo.createTrip({
          for (final key in [
            'title',
            'destination',
            'timezone',
            'startDate',
            'endDate',
          ])
            key: body[key],
        }, key);
        final summary = await repo.summary(trip.id);
        if (objects(summary['budgets']).isEmpty) {
          await repo.budget(trip.id, body['amount'], body['currency'], 0);
        }
        return trip;
      },
    );
    if (result is ServerTrip && mounted) {
      openScreen(
        context,
        ConnectedGeneration(trip: result, profile: widget.profile),
      );
      load(reset: true);
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              widget.home
                  ? '${context.isKhmer ? 'សួស្ដី' : 'Hello'}, ${string(widget.profile, 'name', context.t('appName'))}'
                  : context.t('tripsTitle'),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
          ),
          IconButton(
            tooltip: context.t('refresh'),
            onPressed: busy ? null : () => load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Notice(
        context.t(
          error != null
              ? 'connectionError'
              : busy
              ? 'loading'
              : development
              ? 'developmentData'
              : 'connected',
        ),
        icon: Icons.cloud_outlined,
      ),
      const SizedBox(height: 20),
      if (widget.home) ...[
        VisualHero(
          title: context.t('homeTitle'),
          caption: context.t('cambodia'),
          action: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF8DB9B),
              foregroundColor: const Color(0xFF0C2926),
            ),
            onPressed: create,
            icon: const Icon(Icons.add),
            label: Text(context.t('createTrip')),
          ),
        ),
        const SizedBox(height: 16),
        VisualActions(
          children: [
            VisualAction(
              icon: Icons.map_rounded,
              label: context.t('map'),
              onTap: () => context.push('/map'),
            ),
            VisualAction(
              icon: Icons.pets_rounded,
              label: context.isKhmer ? 'ដំណើរសត្វវេទមន្ត' : 'Creature trails',
              onTap: () => context.push('/adventure'),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
      if (!widget.home)
        FilledButton.icon(
          onPressed: create,
          icon: const Icon(Icons.add),
          label: Text(context.t('createTrip')),
        ),
      const SizedBox(height: 18),
      if (error != null) ...[
        Notice('$error', error: true),
        TextButton(
          onPressed: () => load(reset: true),
          child: Text(context.t('retry')),
        ),
      ],
      if (busy) const LinearProgressIndicator(),
      if (!busy && trips.isEmpty && error == null)
        EmptyState(
          title: context.t('emptyTrips'),
          body: context.t('emptyTripsBody'),
        ),
      for (final trip in trips)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: DestinationCard(
            title: trip.title,
            subtitle:
                '${trip.destination} · ${travelDateRange(trip.startDate, trip.endDate, locale: context.isKhmer ? 'km' : 'en')}',
            onTap: () => openScreen(
              context,
              ConnectedTripDetail(tripId: trip.id, profile: widget.profile),
            ),
          ),
        ),
      if (more && !busy && trips.isNotEmpty)
        TextButton(onPressed: load, child: Text(context.t('loadMore'))),
      const SizedBox(height: 16),
      OutlinedButton(
        onPressed: () => openScreen(
          context,
          TripInvitations(
            onAccepted: () {
              if (mounted) load(reset: true);
            },
          ),
        ),
        child: Text(
          context.isKhmer ? 'ការអញ្ជើញចូលរួមដំណើរ' : 'Trip invitations',
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () =>
            openScreen(context, ConnectedOffline(profile: widget.profile)),
        child: Text(context.t('offline')),
      ),
    ],
  );
}

class ConnectedTripDetail extends ConsumerWidget {
  const ConnectedTripDetail({
    super.key,
    required this.tripId,
    required this.profile,
  });
  final String tripId;
  final Json profile;

  Future<Object?> scheduleReminder(
    BuildContext context,
    WidgetRef ref,
    String title, [
    String dueAt = '',
  ]) => remoteForm(
    context,
    'addReminder',
    [
      InputSpec('title', initial: title),
      InputSpec('dueAt', kind: InputKind.instant, initial: dueAt),
    ],
    submit: (body, _) =>
        ref.read(repositoryProvider).reminder(body['title'], body['dueAt']),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(context.t('itinerary'))),
    body: RemoteContent<(ServerTrip, Json)>(
      load: () async {
        final repo = ref.read(repositoryProvider);
        return (await repo.trip(tripId), await repo.calendar(tripId));
      },
      builder: (data, refresh) {
        final trip = data.$1;
        final activities = objects(
          data.$2['activities'],
        ).map(ServerActivity.fromJson).toList();
        return PageBody(
          children: [
            TravelHero(
              title: trip.title,
              subtitle:
                  '${trip.destination} · ${travelDateRange(trip.startDate, trip.endDate, locale: context.isKhmer ? 'km' : 'en')}',
              icon: Icons.route_rounded,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.forum_outlined, size: 20),
                  label: Text(context.isKhmer ? 'ជជែកក្នុងដំណើរ' : 'Trip chat'),
                  onPressed: () => openScreen(
                    context,
                    TripChat(tripId: trip.id, accountId: string(profile, 'id')),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.notifications_outlined, size: 20),
                  label: Text(context.t('addReminder')),
                  onPressed: () => scheduleReminder(context, ref, trip.title),
                ),
                for (final tool in [
                  'expenses',
                  'reservations',
                  'group',
                  'journal',
                  'calendar',
                  'transport',
                  'contacts',
                ])
                  ActionChip(
                    avatar: Icon(featureIcon(tool), size: 20),
                    label: Text(context.t(tool)),
                    onPressed: () => openScreen(
                      context,
                      ConnectedTools(tool: tool, trip: trip, profile: profile),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(
                    Icons.download_for_offline_rounded,
                    size: 20,
                  ),
                  label: Text(context.t('offline')),
                  onPressed: () => openScreen(
                    context,
                    ConnectedOffline(profile: profile, trip: trip),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.map_rounded, size: 20),
                  label: Text(context.t('map')),
                  onPressed: () =>
                      openScreen(context, ConnectedMap(trip: trip)),
                ),
              ],
            ),
            Section(
              context.t('itinerary'),
              action: context.t('refresh'),
              onAction: refresh,
            ),
            if (activities.isEmpty)
              VisualEmpty(icon: Icons.route_rounded, title: context.t('empty')),
            for (var i = 0; i < activities.length; i++)
              ItineraryActivityCard(
                activity: activities[i],
                zone: trip.timezone,
                order: i,
                action: Wrap(
                  children: [
                    IconButton(
                      tooltip: context.t('addReminder'),
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () => scheduleReminder(
                        context,
                        ref,
                        activities[i].title,
                        activities[i].startsAt,
                      ),
                    ),
                    IconButton(
                      tooltip: context.t('confirm'),
                      icon: const Icon(Icons.thumb_up_outlined),
                      onPressed: () => runRequest(
                        context,
                        () => ref
                            .read(repositoryProvider)
                            .vote(trip.id, activities[i].id, 1),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => openScreen(
                context,
                ConnectedGeneration(
                  trip: trip,
                  profile: profile,
                  replan: activities.isNotEmpty,
                  current: activities,
                ),
              ),
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                context.t(activities.isEmpty ? 'generateNow' : 'replan'),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () =>
                  editConnectedTrip(context, ref, trip).then((_) => refresh()),
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.t('editTrip')),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => openScreen(
                context,
                ConnectedDrafts(trip: trip, profile: profile),
              ),
              icon: const Icon(Icons.drafts_outlined),
              label: Text(context.t('drafts')),
            ),
          ],
        );
      },
    ),
  );
}

Future<Object?> editConnectedTrip(
  BuildContext context,
  WidgetRef ref,
  ServerTrip trip,
) => remoteForm(
  context,
  'editTrip',
  [
    for (final key in [
      'title',
      'destination',
      'timezone',
      'startDate',
      'endDate',
    ])
      InputSpec(
        key,
        label: key == 'title'
            ? 'tripName'
            : key == 'startDate'
            ? 'dates'
            : key == 'endDate'
            ? 'endsAt'
            : key,
        initial: trip.editable[key],
        kind: key.endsWith('Date') ? InputKind.date : InputKind.text,
      ),
  ],
  submit: (body, _) =>
      ref.read(repositoryProvider).syncTrip(trip.id, trip.version, body),
);

class ConnectedDrafts extends ConsumerWidget {
  const ConnectedDrafts({super.key, required this.trip, required this.profile});
  final ServerTrip trip;
  final Json profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(context.t('drafts'))),
    body: RemoteContent<List<Json>>(
      load: () => ref.read(repositoryProvider).itineraries(trip.id),
      builder: (rows, refresh) => PageBody(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActionCard(
                icon: Icons.route,
                title: string(row, 'status'),
                subtitle: string(row, 'source'),
                onTap: () async {
                  final result = await runRequest(
                    context,
                    () => ref
                        .read(repositoryProvider)
                        .itinerary(trip.id, string(row, 'id')),
                  );
                  if (result != null && context.mounted) {
                    openScreen(
                      context,
                      ConnectedGeneration(
                        trip: trip,
                        profile: profile,
                        draft: result,
                      ),
                    );
                  }
                },
              ),
            ),
          if (rows.isEmpty) Text(context.t('empty')),
        ],
      ),
    ),
  );
}
