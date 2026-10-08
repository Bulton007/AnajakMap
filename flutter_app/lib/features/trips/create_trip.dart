import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';
import '../../shared/models/travel.dart';
import '../profile/profile.dart';

class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});
  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripState();
}

class _CreateTripState extends ConsumerState<CreateTripScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final budget = TextEditingController(text: '350');
  DateTimeRange? dates;
  final interests = <String>{'culture', 'food'};
  TripProposal? proposal;
  final selected = <int>{};
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    budget.dispose();
    super.dispose();
  }

  void preview() {
    if (!form.currentState!.validate()) {
      return;
    }
    if (dates == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.t('dates'))));
      return;
    }
    final count = dates!.end.difference(dates!.start).inDays + 1;
    final keys = interests.contains('food')
        ? ['angkor', 'market', 'taProhm', 'river']
        : ['angkor', 'taProhm', 'river'];
    final activities = [
      for (var d = 0; d < count; d++)
        Activity(
          place: keys[d % keys.length],
          day: d,
          time: d == 0 ? '05:30' : '09:00',
        ),
    ];
    setState(() {
      proposal = TripProposal(
        Trip(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: name.text.trim(),
          destination: 'siemReap',
          start: dates!.start,
          end: dates!.end,
          budgetCents: parseMoney(budget.text)!,
          activities: activities,
        ),
      );
      selected.clear();
      selected.addAll(List.generate(activities.length, (i) => i));
    });
  }

  Future<void> approve() async {
    if (busy || selected.isEmpty || proposal == null) {
      return;
    }
    setState(() => busy = true);
    final original = proposal!.trip;
    final filtered = original.withActivities([
      for (var i = 0; i < original.activities.length; i++)
        if (selected.contains(i)) original.activities[i],
    ]);
    final ok = await persist(
      context,
      () => proposal!.approve(
        (_) => ref.read(appStateProvider.notifier).saveTrip(filtered),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => busy = false);
    if (ok) {
      context.replace('/trip/${original.id}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = proposal;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.t(p == null ? 'createTrip' : 'changes')),
          actions: [
            IconButton(
              onPressed: busy ? null : () => showPreferences(context),
              tooltip: context.t('appearance'),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        body: PageBody(
          children: [
            Pill(
              context.t(p == null ? 'demo' : 'proposalLabel'),
              icon: Icons.auto_awesome,
            ),
            const SizedBox(height: 20),
            Text(
              context.t(p == null ? 'tripBasics' : 'proposal'),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 10),
            Text(context.t(p == null ? 'tripBasicsBody' : 'proposalBody')),
            const SizedBox(height: 24),
            if (p == null)
              Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: context.t('tripName'),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 80,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? context.t('required')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: 'siemReap',
                      decoration: InputDecoration(
                        labelText: context.t('destination'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'siemReap',
                          child: Text(context.t('siemReap')),
                        ),
                      ],
                      onChanged: (_) {},
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final today = DateTime.now();
                        final range = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(
                            today.year,
                            today.month,
                            today.day,
                          ),
                          lastDate: DateTime(today.year + 3),
                          initialDateRange: dates,
                        );
                        if (range != null && context.mounted) {
                          if (range.end.difference(range.start).inDays >= 14) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.t('dateRangeLimit')),
                              ),
                            );
                          } else {
                            setState(() => dates = range);
                          }
                        }
                      },
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(
                        dates == null
                            ? context.t('dates')
                            : '${MaterialLocalizations.of(context).formatShortDate(dates!.start)} – ${MaterialLocalizations.of(context).formatShortDate(dates!.end)}',
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: budget,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.t('budgetHint'),
                        prefixIcon: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                      ),
                      validator: (v) => parseMoney(v ?? '') == null
                          ? context.t('invalidAmount')
                          : null,
                    ),
                    Section(context.t('preferences')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final key in [
                          'culture',
                          'food',
                          'nature',
                          'relax',
                        ])
                          FilterChip(
                            label: Text(context.t(key)),
                            selected: interests.contains(key),
                            onSelected: (v) => setState(
                              () => v
                                  ? interests.add(key)
                                  : interests.remove(key),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Notice(context.t('sourceDetail')),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const Key('preview-trip'),
                        onPressed: preview,
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: Text(context.t('previewProposal')),
                      ),
                    ),
                  ],
                ),
              ),
            if (p != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.trip.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${context.t(p.trip.destination)} · ${tripDates(context, p.trip)}',
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${context.t('budget')}: ${money(context, p.trip.budgetCents)}',
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: interests
                            .map((k) => Chip(label: Text(context.t(k))))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Notice(
                context.t('sourceDetail'),
                icon: Icons.verified_user_outlined,
              ),
              const SizedBox(height: 20),
              for (var i = 0; i < p.trip.activities.length; i++) ...[
                Text(
                  '${context.t('day')} ${i + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ActivityRow(
                  p.trip.activities[i],
                  trailing: Checkbox(
                    semanticLabel: context.t(p.trip.activities[i].place),
                    value: selected.contains(i),
                    onChanged: busy
                        ? null
                        : (v) => setState(
                            () => v! ? selected.add(i) : selected.remove(i),
                          ),
                  ),
                ),
              ],
              Text(
                context.t('estimate'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('approve-trip'),
                  onPressed: busy || selected.isEmpty ? null : approve,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(context.t(busy ? 'loading' : 'approve')),
                ),
              ),
              Center(
                child: TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await confirmDialog(
                                context,
                                context.t('discard'),
                                context.t('discardConfirm'),
                              ) &&
                              mounted) {
                            setState(() {
                              p.discard();
                              proposal = null;
                            });
                          }
                        },
                  child: Text(context.t('discard')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
