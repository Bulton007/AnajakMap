import '../maps/search_results.dart';
import 'discovery_details.dart';
import '../../shared/components/visual.dart';
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
import 'package:go_router/go_router.dart';
import '../rpg/rpg_screen.dart';
import 'recommendations.dart';
import '../../shared/components/travel_success.dart';
import '../../shared/components/offline_place_photo.dart';
import 'cached_discovery.dart';

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
  int page = 0, requestVersion = 0;
  String submittedQuery = '';
  void changed(String _) {
    requestVersion++;
    setState(() {
      places = [];
      more = false;
      busy = false;
      error = null;
      submittedQuery = '';
    });
    ref.read(searchResultsProvider.notifier).replace([]);
  }

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
    final term = query.text.trim();
    if (term.isEmpty) {
      changed('');
      return;
    }
    final version = ++requestVersion;
    setState(() {
      busy = true;
      error = null;
      if (!append) {
        places = [];
        more = false;
      }
    });
    try {
      final result = await ref
          .read(repositoryProvider)
          .places(term, page: append ? page : 0);
      if (mounted && version == requestVersion) {
        setState(() {
          places = append ? [...places, ...result] : result;
          page = append ? page + 1 : 1;
          more = result.length == 20;
          busy = false;
          submittedQuery = term;
        });
        ref.read(searchResultsProvider.notifier).replace(places);
        loadPhotos(term, page - 1, version);
      }
    } catch (e) {
      if (mounted && version == requestVersion) {
        setState(() {
          error = e;
          busy = false;
        });
      }
    }
  }

  Future<void> loadPhotos(String term, int resultPage, int version) async {
    try {
      final photos = object(
        await ref.read(repositoryProvider).discovery('photos', {
          'query': term,
          'page': resultPage,
        }),
      );
      if (!mounted || version != requestVersion) return;
      setState(() {
        places = [
          for (final p in places)
            if (photos[p['id']] is Map)
              {...p, 'photo': object(photos[p['id']])}
            else
              p,
        ];
      });
      ref.read(searchResultsProvider.notifier).replace(places);
    } catch (_) {
      // Optional photos must never hide otherwise usable search results.
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
        onChanged: changed,
        textInputAction: TextInputAction.search,
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
          ActionChip(
            avatar: const Icon(Icons.travel_explore, size: 20),
            label: Text(context.t('recommendTitle')),
            onPressed: () => openScreen(
              context,
              TripRecommendations(profile: widget.profile),
            ),
          ),
          for (final key in [
            'food',
            'culture',
            'weather',
            'routes',
            'transport',
          ])
            ActionChip(
              avatar: Icon(featureIcon(key), size: 20),
              label: Text(context.t(key)),
              onPressed: busy || submittedQuery.isEmpty
                  ? null
                  : () => key == 'routes'
                        ? openScreen(context, ConnectedMap(places: places))
                        : openScreen(
                            context,
                            Scaffold(
                              appBar: AppBar(title: Text(context.t(key))),
                              body: CachedDiscoveryInformation(
                                operation: key,
                                query: submittedQuery,
                                profile: widget.profile,
                              ),
                            ),
                          ),
            ),
          ActionChip(
            avatar: const Icon(Icons.map_rounded, size: 20),
            label: Text(context.t('map')),
            onPressed: places.isEmpty
                ? null
                : () => openScreen(context, ConnectedMap(places: places)),
          ),
          ActionChip(
            avatar: const Icon(Icons.bookmark_rounded, size: 20),
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
      if (!busy && places.isEmpty && error == null)
        EmptyState(title: context.t('noResults'), body: context.t('trySearch')),
      if (places.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            '${context.isKhmer ? 'លទ្ធផល' : 'Results for'} $submittedQuery · © OpenStreetMap contributors',
          ),
        ),
      for (final place in places)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DestinationCard(
            photoWidget: place['photo'] is Map
                ? OfflinePlacePhoto(
                    scope:
                        '${ref.read(environmentProvider).normalizedUrl}|${widget.profile['id']}',
                    name: string(place, 'name'),
                    photo: object(place['photo']),
                  )
                : null,
            title: string(place, 'name'),
            photo: place['photo'] is Map ? object(place['photo']) : null,
            subtitle: string(
              place,
              'address',
              string(place, 'source', context.t('sourceUnknown')),
            ),
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
        PlaceFacts(place: place),
        Wrap(
          spacing: 8,
          children: [
            for (final operation in ['weather', 'culture'])
              ActionChip(
                avatar: Icon(featureIcon(operation), size: 20),
                label: Text(context.t(operation)),
                onPressed: () => openScreen(
                  context,
                  Scaffold(
                    appBar: AppBar(title: Text(context.t(operation))),
                    body: CachedDiscoveryInformation(
                      operation: operation,
                      query: string(place, 'name'),
                      profile: profile,
                      parameters: {
                        if (field(place, 'latitude') is num &&
                            field(place, 'longitude') is num) ...{
                          'latitude': field(place, 'latitude'),
                          'longitude': field(place, 'longitude'),
                        },
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (place['rpgEligible'] != false)
          OutlinedButton.icon(
            onPressed: () => context.push(
              Uri(
                path: '/adventure',
                queryParameters: {'destination': string(place, 'id')},
              ).toString(),
            ),
            icon: const Icon(Icons.auto_awesome),
            label: Text(
              rpgText(context, 'Explore creature trails', 'ស្វែងរកសត្វវេទមន្ត'),
            ),
          ),
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
            final saved = await runRequest(context, () async {
              await ref
                  .read(databaseProvider)
                  .cache(scope, 'place:${place['id']}', place);
              return true;
            });
            if (saved == true && context.mounted) {
              showTravelSuccess(
                context,
                message: context.t('savedPlacesLocal'),
              );
            }
          },
          child: Text(context.t('savePlace')),
        ),
      ],
    ),
  );
}
