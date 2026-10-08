import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';
import '../../shared/models/travel.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});
  @override
  ConsumerState<TripsScreen> createState() => _TripsState();
}

class _TripsState extends ConsumerState<TripsScreen> {
  String filter = 'upcoming';
  @override
  Widget build(BuildContext context) {
    final trips = ref
        .watch(appStateProvider)
        .trips
        .where(
          (t) => filter == 'drafts'
              ? false
              : filter == 'past'
              ? t.end.isBefore(DateTime.now().subtract(const Duration(days: 1)))
              : !t.end.isBefore(
                  DateTime.now().subtract(const Duration(days: 1)),
                ),
        )
        .toList();
    return PageBody(
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                context.t('trips'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
            ),
            IconButton.filled(
              onPressed: () => context.push('/trip/new'),
              tooltip: context.t('createTrip'),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(context.t('tripsTitle')),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          children: [
            for (final f in ['upcoming', 'past', 'drafts'])
              ChoiceChip(
                label: Text(context.t(f)),
                selected: f == filter,
                onSelected: (_) => setState(() => filter = f),
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (trips.isEmpty)
          EmptyState(
            title: context.t('emptyTrips'),
            body: context.t(filter == 'drafts' ? 'noDrafts' : 'emptyTripsBody'),
            action: FilledButton.icon(
              onPressed: () => context.push('/trip/new'),
              icon: const Icon(Icons.add),
              label: Text(context.t('createTrip')),
            ),
          ),
        for (final trip in trips)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: TripCard(trip: trip, large: true),
          ),
        const SizedBox(height: 8),
        Notice(context.t('demoNotice')),
      ],
    );
  }
}

class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.large = false});
  final Trip trip;
  final bool large;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => context.push('/trip/${trip.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (large)
            Photo(
              height: 190,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Pill(context.t(trip.destination), onDark: true),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tripDates(context, trip),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const Icon(Icons.arrow_outward, size: 20),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  context.t(trip.name),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '${context.t(trip.destination)}  ·  ${trip.days} ${context.t('days')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Pill(
                  context.t('localOnly'),
                  icon: Icons.phone_android_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
