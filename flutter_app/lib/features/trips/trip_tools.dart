import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';
import '../../shared/components/record_form.dart';
import '../groups/invitation.dart';
import '../offline/conflict_preview.dart';

class TripToolsScreen extends ConsumerWidget {
  const TripToolsScreen({super.key, required this.tripId, required this.tool});
  final String tripId, tool;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    final trips = state.trips.where((t) => t.id == tripId);
    if (trips.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          title: context.t('emptyTrips'),
          body: context.t('emptyTripsBody'),
        ),
      );
    }
    final trip = trips.first;
    final records = state.records
        .where((r) => r.tripId == tripId && r.kind == tool)
        .toList();
    final spent = records.fold(0, (sum, r) => sum + r.cents);
    return Scaffold(
      appBar: AppBar(title: Text(context.t(tool))),
      body: PageBody(
        children: [
          Pill(context.t('demo')),
          const SizedBox(height: 18),
          Text(
            context.t(trip.name),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          if (tool == 'expenses') ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('spent')),
                    const SizedBox(height: 8),
                    Text(
                      money(context, spent),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: (spent / trip.budgetCents).clamp(0, 1),
                      minHeight: 7,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${context.t('remaining')}  ${money(context, trip.budgetCents - spent)}',
                    ),
                    Text(
                      '${context.t('budget')}  ${money(context, trip.budgetCents)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => showRecordForm(context, ref, tripId, tool),
                  icon: const Icon(Icons.add),
                  label: Text(context.t('addExpense')),
                ),
                OutlinedButton.icon(
                  onPressed: () => showRecordForm(
                    context,
                    ref,
                    tripId,
                    tool,
                    extraction: true,
                  ),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: Text(context.t('scanExpense')),
                ),
              ],
            ),
            if (records.isEmpty)
              EmptyState(
                title: context.t('emptyExpenses'),
                body: context.t('emptyExpensesBody'),
                icon: Icons.account_balance_wallet_outlined,
              ),
          ],
          if (tool == 'reservations') ...[
            Notice(context.t('noReservationsBody')),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => showRecordForm(context, ref, tripId, tool),
                  icon: const Icon(Icons.add),
                  label: Text(context.t('addReservation')),
                ),
                OutlinedButton(
                  onPressed: () => showRecordForm(
                    context,
                    ref,
                    tripId,
                    tool,
                    extraction: true,
                  ),
                  child: Text(context.t('extraction')),
                ),
              ],
            ),
            if (records.isEmpty)
              EmptyState(
                title: context.t('noReservations'),
                body: context.t('timeZone'),
                icon: Icons.confirmation_number_outlined,
              ),
          ],
          if (tool == 'journal') ...[
            Text(context.t('journalBody')),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => showRecordForm(context, ref, tripId, tool),
              icon: const Icon(Icons.edit_outlined),
              label: Text(context.t('newEntry')),
            ),
            if (records.isEmpty)
              EmptyState(
                title: context.t('empty'),
                body: context.t('journalBody'),
                icon: Icons.menu_book_outlined,
              ),
          ],
          if (tool == 'group') ...[
            Notice(context.t('inviteBody'), icon: Icons.people_outline),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => showRecordForm(context, ref, tripId, tool),
              icon: const Icon(Icons.group_add_outlined),
              label: Text(context.t('createGroup')),
            ),
          ],
          const SizedBox(height: 22),
          for (final r in records)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (r.photo) ...[
                        const Photo(height: 180),
                        const SizedBox(height: 16),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (tool == 'expenses')
                            Text(
                              money(context, r.cents),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                        ],
                      ),
                      if (r.detail.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(r.detail),
                      ],
                      if (tool == 'reservations') ...[
                        const SizedBox(height: 8),
                        Text(
                          context.t('timeZone'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (tool == 'group') ...[
                        const SizedBox(height: 16),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(context.t('you')),
                          subtitle: Text(context.t('owner')),
                        ),
                        OutlinedButton(
                          onPressed: () => showInvite(context),
                          child: Text(context.t('invite')),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        context.t('localOnly'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (tool == 'offline') ...[
            const Icon(Icons.offline_pin_outlined, size: 54),
            const SizedBox(height: 20),
            Text(
              context.t('cached'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            Text(context.t('offlineBody')),
            const SizedBox(height: 20),
            Notice(context.t('localOnly'), icon: Icons.phone_android_outlined),
            const SizedBox(height: 14),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.t('offlinePreview')),
              value: state.offline,
              onChanged: (v) => ref.read(appStateProvider.notifier).offline(v),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => showConflict(context),
              icon: const Icon(Icons.sync_problem_outlined),
              label: Text(context.t('conflictPreview')),
            ),
          ],
        ],
      ),
    );
  }
}
