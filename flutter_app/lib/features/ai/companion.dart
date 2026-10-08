import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';

class CompanionScreen extends ConsumerWidget {
  const CompanionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    void openTool(String tool) {
      if (state.trips.isEmpty) {
        context.push('/trip/new');
      } else {
        context.push('/trip/${state.trips.last.id}/$tool');
      }
    }

    return PageBody(
      children: [
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.auto_awesome, size: 30),
        ),
        const SizedBox(height: 24),
        Text(
          context.t('aiTitle'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(context.t('aiSubtitle')),
        const SizedBox(height: 20),
        Pill(context.t('demo')),
        const SizedBox(height: 22),
        if (state.offline) ...[
          Notice(context.t('connectionRequired'), icon: Icons.cloud_off),
          const SizedBox(height: 16),
        ],
        for (final item in [
          (
            'generate',
            'generateBody',
            Icons.route_outlined,
            () => context.push('/trip/new'),
          ),
          (
            'discover',
            'discoverBody',
            Icons.explore_outlined,
            () => context.go('/explore'),
          ),
          (
            'translate',
            'translateBody',
            Icons.translate,
            () => context.push('/translation'),
          ),
          (
            'receipt',
            'receiptBody',
            Icons.receipt_long_outlined,
            () => openTool('expenses'),
          ),
          (
            'reservations',
            'receiptBody',
            Icons.confirmation_number_outlined,
            () => openTool('reservations'),
          ),
          (
            'summarize',
            'summarizeBody',
            Icons.notes_rounded,
            () {
              if (state.trips.isEmpty) {
                context.push('/trip/new');
              } else {
                context.push('/trip/${state.trips.last.id}');
              }
            },
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ActionCard(
              icon: item.$3,
              title: context.t(item.$1),
              subtitle: context.t(item.$2),
              onTap: item.$4,
            ),
          ),
        Section(context.t('aiTrust')),
        Notice(context.t('aiTrustBody'), icon: Icons.verified_user_outlined),
      ],
    );
  }
}
