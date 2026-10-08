import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';
import '../../shared/models/travel.dart';

class ItineraryScreen extends ConsumerStatefulWidget {
  const ItineraryScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<ItineraryScreen> createState() => _ItineraryState();
}

class _ItineraryState extends ConsumerState<ItineraryScreen> {
  int day = 0;
  @override
  Widget build(BuildContext context) {
    final trips = ref
        .watch(appStateProvider)
        .trips
        .where((t) => t.id == widget.id);
    if (trips.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          title: context.t('emptyTrips'),
          body: context.t('emptyTripsBody'),
          action: FilledButton(
            onPressed: () => context.go('/trips'),
            child: Text(context.t('trips')),
          ),
        ),
      );
    }
    final trip = trips.first;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('itinerary')),
        actions: [
          IconButton(
            tooltip: context.t('offline'),
            onPressed: () => context.push('/trip/${trip.id}/offline'),
            icon: const Icon(Icons.offline_pin_outlined),
          ),
        ],
      ),
      body: PageBody(
        children: [
          Photo(
            height: 220,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Pill(context.t('demo'), onDark: true),
                  const Spacer(),
                  Text(
                    context.t(trip.name),
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium!.copyWith(color: Colors.white),
                  ),
                  Text(
                    tripDates(context, trip),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in [
                ('expenses', Icons.account_balance_wallet_outlined),
                ('reservations', Icons.confirmation_number_outlined),
                ('group', Icons.people_outline),
                ('journal', Icons.menu_book_outlined),
              ])
                ActionChip(
                  avatar: Icon(item.$2, size: 18),
                  label: Text(context.t(item.$1)),
                  onPressed: () => context.push('/trip/${trip.id}/${item.$1}'),
                ),
            ],
          ),
          Section(context.t('itinerary')),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var d = 0; d < trip.days; d++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${context.t('day')} ${d + 1}'),
                      selected: d == day,
                      onSelected: (_) => setState(() => day = d),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (!trip.activities.any((a) => a.day == day))
            EmptyState(
              title: context.t('empty'),
              body: context.t('handpicked'),
            ),
          for (final activity in trip.activities.where((a) => a.day == day))
            ActivityRow(
              activity,
              trailing: IconButton(
                tooltip: context.t('aboutPlace'),
                icon: const Icon(Icons.chevron_right),
                onPressed: () => context.push('/place/${activity.place}'),
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.go('/explore'),
              icon: const Icon(Icons.add),
              label: Text(context.t('addToTrip')),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: trip.activities.any((a) => a.day == day)
                  ? () => showReplan(context, ref, trip, day)
                  : null,
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(context.t('replan')),
            ),
          ),
          const SizedBox(height: 20),
          Notice(context.t('localOnly'), icon: Icons.phone_android_outlined),
        ],
      ),
    );
  }
}

Future<void> showReplan(
  BuildContext context,
  WidgetRef ref,
  Trip trip,
  int day,
) async {
  final original = trip.activities.firstWhere((a) => a.day == day);
  final changed = Activity(
    place: original.place,
    day: day,
    time: original.time == '10:00' ? '09:00' : '10:00',
  );
  bool selected = true;
  bool busy = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, update) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Pill(sheet.t('proposalLabel')),
              const SizedBox(height: 16),
              Text(
                sheet.t('replanTitle'),
                style: Theme.of(sheet).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(sheet.t('replanBody')),
              const SizedBox(height: 18),
              Text(sheet.t('before')),
              ActivityRow(original),
              Text(sheet.t('after')),
              ActivityRow(
                changed,
                trailing: Checkbox(
                  value: selected,
                  onChanged: busy ? null : (v) => update(() => selected = v!),
                ),
              ),
              Notice(sheet.t('reservationImpact')),
              const SizedBox(height: 12),
              Text(
                sheet.t('sourceDetail'),
                style: Theme.of(sheet).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: !selected || busy
                      ? null
                      : () async {
                          update(() => busy = true);
                          final ok = await persist(
                            sheet,
                            () => ref
                                .read(appStateProvider.notifier)
                                .updateActivities(
                                  trip.id,
                                  trip.revision,
                                  trip.activities
                                      .map(
                                        (a) => identical(a, original)
                                            ? changed
                                            : a,
                                      )
                                      .toList(),
                                ),
                          );
                          if (sheet.mounted) {
                            if (ok) {
                              Navigator.pop(sheet);
                            } else {
                              update(() => busy = false);
                            }
                          }
                        },
                  child: Text(sheet.t(busy ? 'loading' : 'approveChanges')),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: busy ? null : () => Navigator.pop(sheet),
                  child: Text(sheet.t('discard')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
