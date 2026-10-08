import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';
import '../../shared/models/travel.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreState();
}

class _ExploreState extends ConsumerState<ExploreScreen> {
  String query = '', category = 'all';
  bool map = false;
  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(appStateProvider).savedPlaces;
    final places = placeKeys
        .where(
          (p) =>
              (category == 'all' ||
                  (category == 'saved'
                      ? saved.contains(p)
                      : placeCategories[p] == category)) &&
              (context.t(p).toLowerCase().contains(query.toLowerCase()) ||
                  p.toLowerCase().contains(query.toLowerCase())),
        )
        .toList();
    return PageBody(
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                context.t('explore'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            Pill(context.t('cambodia'), icon: Icons.location_on_outlined),
          ],
        ),
        const SizedBox(height: 8),
        Text(context.t('handpicked')),
        const SizedBox(height: 24),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(
            hintText: context.t('search'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final key in ['all', 'culture', 'food', 'nature', 'saved'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(context.t(key)),
                    selected: category == key,
                    onSelected: (_) => setState(() => category = key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              icon: const Icon(Icons.view_list_outlined),
              label: Text(context.t('list')),
            ),
            ButtonSegment(
              value: true,
              icon: const Icon(Icons.map_outlined),
              label: Text(context.t('map')),
            ),
          ],
          selected: {map},
          onSelectionChanged: (v) => setState(() => map = v.first),
        ),
        const SizedBox(height: 22),
        if (map)
          EmptyState(
            title: context.t('mapTitle'),
            body: context.t('mapBody'),
            icon: Icons.map_outlined,
            action: FilledButton(
              onPressed: () => setState(() => map = false),
              child: Text(context.t('backToList')),
            ),
          )
        else ...[
          if (places.isEmpty)
            EmptyState(
              title: context.t('noResults'),
              body: context.t('trySearch'),
            ),
          for (final p in places)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: PlaceCard(place: p),
            ),
        ],
        Notice(context.t('sourceDetail')),
      ],
    );
  }
}

class PlaceCard extends ConsumerWidget {
  const PlaceCard({super.key, required this.place});
  final String place;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(appStateProvider).savedPlaces.contains(place);
    return Card(
      child: InkWell(
        onTap: () => context.push('/place/$place'),
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (place == 'angkor' || place == 'taProhm')
              Photo(
                height: 190,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Pill(context.t('culture'), onDark: true),
                  ),
                ),
              )
            else
              Container(
                height: 110,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                ),
                child: Center(
                  child: Icon(
                    place == 'market'
                        ? Icons.ramen_dining_outlined
                        : Icons.water_outlined,
                    size: 46,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t(place),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${context.t('siemReap')} · ${context.t(placeCategories[place]!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: context.t('savePlace'),
                    isSelected: saved,
                    selectedIcon: const Icon(Icons.bookmark),
                    icon: const Icon(Icons.bookmark_border),
                    onPressed: () => persist(
                      context,
                      () => ref
                          .read(appStateProvider.notifier)
                          .togglePlace(place),
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
}

class PlaceScreen extends ConsumerWidget {
  const PlaceScreen({super.key, required this.place});
  final String place;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!placeKeys.contains(place)) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          title: context.t('noResults'),
          body: context.t('trySearch'),
        ),
      );
    }
    final saved = ref.watch(appStateProvider).savedPlaces.contains(place);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('explore')),
        actions: [
          IconButton(
            tooltip: context.t('savePlace'),
            onPressed: () => persist(
              context,
              () => ref.read(appStateProvider.notifier).togglePlace(place),
            ),
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_outline),
          ),
        ],
      ),
      body: PageBody(
        children: [
          if (place == 'angkor' || place == 'taProhm') const Photo(height: 300),
          const SizedBox(height: 24),
          Pill(context.t(placeCategories[place]!)),
          const SizedBox(height: 12),
          Text(
            context.t(place),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 6),
          Text('${context.t('siemReap')}, ${context.t('cambodia')}'),
          Section(context.t('aboutPlace')),
          Text(
            context.t(
              place == 'angkor' || place == 'taProhm'
                  ? 'templeDescription'
                  : 'heroSubtitle',
            ),
          ),
          Section(context.t('source')),
          Notice(context.t('sourceDetail')),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => chooseTripDay(context, ref, place),
              icon: const Icon(Icons.add),
              label: Text(context.t('addToTrip')),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> chooseTripDay(
  BuildContext context,
  WidgetRef ref,
  String place,
) async {
  final trips = ref.read(appStateProvider).trips;
  if (trips.isEmpty) {
    context.push('/trip/new');
    return;
  }
  var trip = trips.last;
  var day = 0;
  var busy = false;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, update) => Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sheet.t('addToTrip'),
                style: Theme.of(sheet).textTheme.headlineMedium,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: trip.id,
                isExpanded: true,
                decoration: InputDecoration(labelText: sheet.t('chooseTrip')),
                items: trips
                    .map(
                      (t) => DropdownMenuItem(
                        value: t.id,
                        child: Text(
                          sheet.t(t.name),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) => update(() {
                        trip = trips.firstWhere((t) => t.id == v);
                        day = 0;
                      }),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<int>(
                key: ValueKey(trip.id),
                initialValue: day,
                decoration: InputDecoration(labelText: sheet.t('chooseDay')),
                items: [
                  for (var i = 0; i < trip.days; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('${sheet.t('day')} ${i + 1}'),
                    ),
                ],
                onChanged: busy ? null : (v) => update(() => day = v!),
              ),
              const SizedBox(height: 20),
              Notice('${sheet.t(place)} · ${sheet.t('walk')}'),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          update(() => busy = true);
                          final ok = await persist(
                            sheet,
                            () => ref
                                .read(appStateProvider.notifier)
                                .updateActivities(trip.id, trip.revision, [
                                  ...trip.activities,
                                  Activity(place: place, day: day, time: '—'),
                                ]),
                          );
                          if (sheet.mounted) {
                            if (ok) {
                              Navigator.pop(sheet);
                              context.push('/trip/${trip.id}');
                            } else {
                              update(() => busy = false);
                            }
                          }
                        },
                  child: Text(sheet.t(busy ? 'loading' : 'confirm')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
