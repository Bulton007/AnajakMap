import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/localization/strings.dart';
import '../../app/theme/theme.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/components/place_photo.dart';
import '../../shared/components/travel_success.dart';
import '../../shared/components/remote.dart';
import '../../shared/components/travel_panels.dart';
import '../../shared/formatting/travel_dates.dart';
import '../../shared/models/server_models.dart';
import 'connected_explore.dart';
import 'connected_generation.dart';

class TripRecommendations extends ConsumerStatefulWidget {
  const TripRecommendations({super.key, required this.profile});
  final Json profile;
  @override
  ConsumerState<TripRecommendations> createState() => _RecommendationsState();
}

class _RecommendationsState extends ConsumerState<TripRecommendations> {
  final destination = TextEditingController(text: 'Siem Reap');
  String interest = 'culture', pace = 'balanced';
  ServerTrip? trip;
  Json? result;
  List<Json> items = [];
  String? error;
  bool busy = false;
  int revision = 0;
  @override
  void dispose() {
    destination.dispose();
    super.dispose();
  }

  void clearResults() {
    revision++;
    setState(() {
      result = null;
      items = [];
      error = null;
      busy = false;
    });
  }

  Future<void> find({bool useAi = false}) async {
    if (busy) return;
    final query = destination.text.trim();
    if (query.length < 2 || query.length > 120) {
      setState(() => error = context.t('recommendDestinationRequired'));
      return;
    }
    final version = ++revision;
    setState(() {
      busy = true;
      error = null;
      if (!useAi) {
        result = null;
        items = [];
      }
    });
    try {
      final data = await ref.read(repositoryProvider).recommendations({
        'destination': query,
        'interests': [interest],
        'pace': pace,
        'language': context.isKhmer ? 'km' : 'en',
        'useAi': useAi,
      });
      if (!mounted || version != revision) return;
      setState(() {
        result = data;
        items = objects(data['items']);
        busy = false;
      });
      // Search results remain usable while optional licensed images arrive.
      try {
        final photos = object(
          await ref.read(repositoryProvider).discovery('photos', {
            'query': data['query'],
            'page': 0,
          }),
        );
        if (!mounted || version != revision) return;
        setState(
          () => items = [
            for (final p in items)
              if (photos[p['id']] is Map)
                {...p, 'photo': object(photos[p['id']])}
              else
                p,
          ],
        );
      } catch (_) {
        /* A missing photograph never creates or replaces a place. */
      }
    } catch (e) {
      if (mounted && version == revision) {
        setState(() {
          busy = false;
          error = e is ApiFailure
              ? e.message
              : context.t('recommendUnavailable');
        });
      }
    }
  }

  Future<void> add(Json place) async {
    if (busy) return;
    final selected = trip ?? await selectTrip(context, ref);
    if (selected == null || !mounted) return;
    final data = await remoteForm(context, 'addActivity', [
      InputSpec(
        'title',
        label: 'activityTitle',
        initial: string(place, 'name'),
      ),
      InputSpec(
        'startsAt',
        kind: InputKind.instant,
        initial: '${selected.startDate}T09:00:00+07:00',
      ),
      InputSpec(
        'endsAt',
        kind: InputKind.instant,
        initial: '${selected.startDate}T10:00:00+07:00',
      ),
    ], submitLabel: 'reviewDraft');
    if (data is! Map || !mounted) return;
    final calendar = await runRequest(
      context,
      () => ref.read(repositoryProvider).calendar(selected.id),
    );
    if (calendar == null || !mounted) return;
    final rows = [
      ...objects(
        calendar['activities'],
      ).map((a) => ServerActivity.fromJson(a).toDraft()),
      {
        ...object(data),
        'latitude': field(place, 'latitude'),
        'longitude': field(place, 'longitude'),
        'source': string(place, 'source', context.t('sourceUnknown')),
      },
    ];
    rows.sort(
      (a, b) => DateTime.parse(
        a['startsAt'] as String,
      ).compareTo(DateTime.parse(b['startsAt'] as String)),
    );
    openScreen(
      context,
      ConnectedGeneration(
        trip: selected,
        profile: widget.profile,
        draft: {
          'itinerary': {
            'status': 'DRAFT',
            'source': string(place, 'source', context.t('sourceUnknown')),
          },
          'activities': rows,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.t('recommendTitle'))),
    body: PageBody(
      children: [
        TravelHero(
          title: context.t('recommendHero'),
          subtitle: context.t('recommendIntro'),
          icon: Icons.travel_explore,
        ),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final selected = await selectTrip(context, ref);
                  if (selected != null && mounted) {
                    clearResults();
                    setState(() {
                      trip = selected;
                      destination.text = selected.destination;
                    });
                  }
                },
          icon: const Icon(Icons.luggage_outlined),
          label: Text(trip?.title ?? context.t('recommendChooseTrip')),
        ),
        if (trip != null)
          IconFact(
            Icons.calendar_month,
            travelDateRange(
              trip!.startDate,
              trip!.endDate,
              locale: context.isKhmer ? 'km' : 'en',
            ),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: destination,
          maxLength: 120,
          onChanged: (_) {
            trip = null;
            clearResults();
          },
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => find(),
          decoration: InputDecoration(
            labelText: context.t('destination'),
            prefixIcon: const Icon(Icons.location_on_outlined),
          ),
        ),
        Section(context.t('recommendInterests')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in [
              ('culture', Icons.temple_buddhist_outlined),
              ('food', Icons.restaurant),
              ('nature', Icons.forest_outlined),
              ('beach', Icons.beach_access_outlined),
              ('city', Icons.location_city),
            ])
              ChoiceChip(
                avatar: Icon(entry.$2, size: 20),
                label: Text(context.t(entry.$1)),
                selected: interest == entry.$1,
                onSelected: busy
                    ? null
                    : (_) {
                        clearResults();
                        setState(() => interest = entry.$1);
                      },
              ),
          ],
        ),
        Section(context.t('pace')),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in ['relaxed', 'balanced', 'active'])
              ChoiceChip(
                label: Text(context.t(p)),
                selected: pace == p,
                onSelected: busy
                    ? null
                    : (_) {
                        clearResults();
                        setState(() => pace = p);
                      },
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : find,
          icon: const Icon(Icons.explore_outlined),
          label: Text(context.t(busy ? 'loading' : 'recommendFind')),
        ),
        if (busy) ...[
          const SizedBox(height: 16),
          const LinearProgressIndicator(),
        ],
        if (error != null) ...[
          const SizedBox(height: 16),
          Notice(error!, error: true),
        ],
        if (result != null) ...[
          Section(context.t('recommendResults')),
          Notice(
            context.t(
              result!['mode'] == 'ai_grounded'
                  ? 'recommendAiMode'
                  : 'recommendMatchMode',
            ),
            icon: result!['mode'] == 'ai_grounded'
                ? Icons.auto_awesome
                : Icons.tune,
          ),
          if (result!['aiStatus'] == 'rate_limited' ||
              result!['aiStatus'] == 'unavailable') ...[
            const SizedBox(height: 12),
            Notice(
              context.t('recommendAiUnavailable'),
              icon: Icons.cloud_off_outlined,
            ),
          ],
          if (result!['retryAt'] is String)
            IconFact(
              Icons.schedule,
              '${context.t('retryAvailable')} · ${travelDateTime(result!['retryAt'] as String, locale: context.isKhmer ? 'km' : 'en')}',
            ),
          if (items.isNotEmpty && result!['mode'] != 'ai_grounded')
            TextButton.icon(
              onPressed:
                  busy ||
                      (DateTime.tryParse(
                            string(result!, 'retryAt'),
                          )?.isAfter(DateTime.now().toUtc()) ??
                          false)
                  ? null
                  : () => find(useAi: true),
              icon: const Icon(Icons.auto_awesome),
              label: Text(context.t('recommendAskAi')),
            ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            VisualEmpty(
              icon: Icons.search_off,
              title: context.t('recommendNoResults'),
            ),
          for (var i = 0; i < items.length; i++)
            RecommendationCard(
              place: items[i],
              index: i,
              retrievedAt: string(result!, 'retrievedAt'),
              ai: result!['mode'] == 'ai_grounded',
              onDetails: () => openScreen(
                context,
                ConnectedPlace(place: items[i], profile: widget.profile),
              ),
              onAdd: () => add(items[i]),
              onSave: () async {
                final p = items[i];
                final saved = await runRequest(context, () async {
                  await ref
                      .read(databaseProvider)
                      .cache(
                        '${ref.read(environmentProvider).normalizedUrl}|${widget.profile['id']}',
                        'place:${p['id']}',
                        p,
                      );
                  return true;
                });
                if (saved == true && context.mounted) {
                  showTravelSuccess(
                    context,
                    message: context.t('savedPlacesLocal'),
                  );
                }
              },
            ),
        ],
      ],
    ),
  );
}

class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.place,
    required this.index,
    required this.retrievedAt,
    required this.ai,
    required this.onDetails,
    required this.onAdd,
    required this.onSave,
  });
  final Json place;
  final int index;
  final String retrievedAt;
  final bool ai;
  final VoidCallback onDetails, onAdd, onSave;
  @override
  Widget build(BuildContext context) {
    final accent = Tokens.accent(context, index);
    final reason = string(place, 'reason'),
        match = string(place, 'matchedInterest');
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (place['photo'] is Map)
            PlacePhoto(
              name: string(place, 'name'),
              photo: object(place['photo']),
            )
          else
            Container(
              height: 130,
              color: accent.background,
              child: Icon(
                switch (match) {
                  'culture' => Icons.temple_buddhist_outlined,
                  'food' => Icons.restaurant,
                  'nature' => Icons.forest_outlined,
                  'beach' => Icons.beach_access_outlined,
                  _ => Icons.travel_explore,
                },
                size: 60,
                color: accent.foreground,
                semanticLabel: context.t('recommendNoPhoto'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  string(place, 'name'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (string(place, 'address').isNotEmpty)
                  IconFact(Icons.place_outlined, string(place, 'address')),
                IconFact(
                  ai ? Icons.auto_awesome : Icons.favorite_outline,
                  ai && reason.isNotEmpty
                      ? reason
                      : match.isNotEmpty
                      ? '${context.t('recommendMatches')} ${context.t(match)}'
                      : context.t('recommendDestinationMatch'),
                ),
                Text(
                  context.t('recommendUnverified'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (field(place, 'mock') == true)
                  Notice(context.t('mock'), icon: Icons.science_outlined),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onDetails,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(context.t('recommendDetails')),
                    ),
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: Text(context.t('addToTrip')),
                    ),
                    IconButton(
                      onPressed: onSave,
                      tooltip: context.t('savePlace'),
                      icon: const Icon(Icons.bookmark_add_outlined),
                    ),
                  ],
                ),
                ExpansionTile(
                  key: PageStorageKey('recommendation-source-${place['id']}'),
                  tilePadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fact_check_outlined),
                  title: Text(context.t('recommendReferences')),
                  children: [
                    Text(string(place, 'source', context.t('sourceUnknown'))),
                    if (DateTime.tryParse(retrievedAt) != null)
                      IconFact(
                        Icons.update,
                        '${context.t('recommendRetrieved')} · ${travelDateTime(retrievedAt, locale: context.isKhmer ? 'km' : 'en')}',
                      ),
                    Text(
                      context.t('recommendSourceScope'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final source in objects(place['references']))
                      TextButton.icon(
                        onPressed: () async {
                          final uri = Uri.tryParse(string(source, 'url'));
                          if (uri == null ||
                              uri.scheme != 'https' ||
                              uri.host != 'www.openstreetmap.org') {
                            return;
                          }
                          final opened = await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                          if (!opened && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.t('recommendLinkError')),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(string(source, 'title')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
