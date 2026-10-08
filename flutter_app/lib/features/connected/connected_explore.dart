import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';
import '../../shared/models/server_models.dart';
import 'connected_generation.dart';
import 'connected_map.dart';

Future<ServerTrip?> selectTrip(BuildContext context, WidgetRef ref) async {
  final trips = await runRequest(
    context,
    () => ref.read(repositoryProvider).trips(),
  );
  if (trips == null || !context.mounted) {
    return null;
  }
  if (trips.isEmpty) {
    await inform(context, context.t('trips'), context.t('noSavedTrip'));
    return null;
  }
  return showModalBottomSheet<ServerTrip>(
    context: context,
    showDragHandle: true,
    builder: (c) => ListView(
      shrinkWrap: true,
      children: [
        for (final trip in trips)
          ListTile(
            title: Text(trip.title),
            subtitle: Text(trip.destination),
            onTap: () => Navigator.pop(c, trip),
          ),
      ],
    ),
  );
}

class ConnectedExplore extends ConsumerStatefulWidget {
  const ConnectedExplore({super.key, required this.profile});
  final Json profile;
  @override
  ConsumerState<ConnectedExplore> createState() => _ExploreState();
}

class _ExploreState extends ConsumerState<ConnectedExplore> {
  final query = TextEditingController(text: 'Phnom Penh');
  List<Json> places = [];
  bool busy = false, more = false;
  int page = 0;
  Object? error;
  @override
  void initState() {
    super.initState();
    search();
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search({bool append = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await ref
          .read(repositoryProvider)
          .places(query.text.trim(), page: append ? page : 0);
      if (mounted) {
        setState(() {
          places = append ? [...places, ...result] : result;
          page = append ? page + 1 : 1;
          more = result.length == 20;
          busy = false;
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

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      Text(
        context.t('explore'),
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 18),
      TextField(
        controller: query,
        onSubmitted: (_) => search(),
        decoration: InputDecoration(
          labelText: context.t('search'),
          suffixIcon: IconButton(
            tooltip: context.t('search'),
            onPressed: busy ? null : search,
            icon: const Icon(Icons.search),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final key in [
            'food',
            'culture',
            'weather',
            'routes',
            'transport',
          ])
            ActionChip(
              label: Text(context.t(key)),
              onPressed: () => openScreen(
                context,
                Scaffold(
                  appBar: AppBar(title: Text(context.t(key))),
                  body: RemoteContent<Object?>(
                    load: () => ref.read(repositoryProvider).discovery(key, {
                      'query': query.text,
                    }),
                    builder: (result, _) =>
                        PageBody(children: [ServerResult(result)]),
                  ),
                ),
              ),
            ),
          ActionChip(
            label: Text(context.t('map')),
            onPressed: () => openScreen(context, ConnectedMap(places: places)),
          ),
          ActionChip(
            label: Text(context.t('savedPlaces')),
            onPressed: () => openScreen(
              context,
              Scaffold(
                appBar: AppBar(title: Text(context.t('savedPlaces'))),
                body: RemoteContent<List<Json>>(
                  load: () => ref
                      .read(databaseProvider)
                      .cachedEntries(
                        '${ref.read(environmentProvider).normalizedUrl}|${widget.profile['id']}',
                        'place:',
                      ),
                  builder: (rows, _) => PageBody(
                    children: [
                      Notice(context.t('savedPlacesLocal')),
                      for (final row in rows)
                        ListTile(
                          title: Text(string(object(row['data']), 'name')),
                          onTap: () => openScreen(
                            context,
                            ConnectedPlace(
                              place: object(row['data']),
                              profile: widget.profile,
                            ),
                          ),
                        ),
                      if (rows.isEmpty) Text(context.t('empty')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Notice('$error', error: true),
      if (!busy && places.isEmpty)
        EmptyState(title: context.t('noResults'), body: context.t('trySearch')),
      for (final place in places)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ActionCard(
            icon: Icons.location_on_outlined,
            title: string(place, 'name'),
            subtitle: string(place, 'source', context.t('sourceUnknown')),
            onTap: () => openScreen(
              context,
              ConnectedPlace(place: place, profile: widget.profile),
            ),
          ),
        ),
      if (more && !busy)
        TextButton(
          onPressed: () => search(append: true),
          child: Text(context.t('loadMore')),
        ),
    ],
  );
}

class ConnectedPlace extends ConsumerWidget {
  const ConnectedPlace({super.key, required this.place, required this.profile});
  final Json place, profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(string(place, 'name'))),
    body: PageBody(
      children: [
        Text(
          string(place, 'name'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 18),
        ServerResult(place),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () async {
            final trip = await selectTrip(context, ref);
            if (trip == null || !context.mounted) {
              return;
            }
            final result = await remoteForm(context, 'addActivity', [
              InputSpec(
                'title',
                label: 'activityTitle',
                initial: string(place, 'name'),
              ),
              InputSpec(
                'startsAt',
                kind: InputKind.instant,
                initial: '${trip.startDate}T09:00:00+07:00',
              ),
              InputSpec(
                'endsAt',
                kind: InputKind.instant,
                initial: '${trip.startDate}T10:00:00+07:00',
              ),
            ], submitLabel: 'reviewDraft');
            if (result is! Map || !context.mounted) {
              return;
            }
            final calendar = await runRequest(
              context,
              () => ref.read(repositoryProvider).calendar(trip.id),
            );
            if (calendar == null || !context.mounted) {
              return;
            }
            final rows = [
              ...objects(
                calendar['activities'],
              ).map((a) => ServerActivity.fromJson(a).toDraft()),
              ...<Json>[
                {
                  ...object(result),
                  'latitude': field(place, 'latitude'),
                  'longitude': field(place, 'longitude'),
                  'source': string(place, 'source', 'User selected place'),
                },
              ],
            ];
            rows.sort(
              (a, b) => DateTime.parse(
                a['startsAt'],
              ).compareTo(DateTime.parse(b['startsAt'])),
            );
            openScreen(
              context,
              ConnectedGeneration(
                trip: trip,
                profile: profile,
                draft: {
                  'itinerary': {
                    'status': 'DRAFT',
                    'source': 'Traveler reviewed addition',
                  },
                  'activities': rows,
                },
              ),
            );
          },
          icon: const Icon(Icons.add),
          label: Text(context.t('addToTrip')),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () async {
            final scope =
                '${ref.read(environmentProvider).normalizedUrl}|${profile['id']}';
            await runRequest(
              context,
              () => ref
                  .read(databaseProvider)
                  .cache(scope, 'place:${place['id']}', place),
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.t('savedPlacesLocal'))),
              );
            }
          },
          child: Text(context.t('savePlace')),
        ),
      ],
    ),
  );
}
