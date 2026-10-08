import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/localization/strings.dart';
import '../../app/theme/theme.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';
import '../trips/trips.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    return PageBody(
      children: [
        Row(
          children: [
            Icon(
              Icons.spa_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 27,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.t('appName'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge!.copyWith(letterSpacing: -1),
              ),
            ),
            Pill(context.t('demo')),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.t('profile'),
              onPressed: () => context.go('/profile'),
              icon: const CircleAvatar(
                radius: 18,
                backgroundColor: Color(0xFFE1E8D7),
                child: Icon(
                  Icons.person_outline,
                  color: Tokens.forest,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          context.t('greeting'),
          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.t('homeTitle'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        Text(
          context.t('homeSubtitle'),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 26),
        Semantics(
          button: true,
          label: context.t('exploreDestination'),
          child: InkWell(
            onTap: () => context.go('/explore'),
            borderRadius: BorderRadius.circular(24),
            child: Photo(
              height: 310,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Pill(
                      context.t('cambodia').toUpperCase(),
                      icon: Icons.location_on_outlined,
                      onDark: true,
                    ),
                    const Spacer(),
                    Text(
                      context.t('discoverCambodia'),
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium!.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      context.t('heroSubtitle'),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.t('exploreDestination'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Section(
          context.t('yourNextTrip'),
          action: context.t('seeAll'),
          onAction: () => context.go('/trips'),
        ),
        if (state.trips.isNotEmpty)
          TripCard(trip: state.trips.last)
        else
          ActionCard(
            icon: Icons.add_rounded,
            title: context.t('createTrip'),
            subtitle: context.t('emptyTripsBody'),
            onTap: () => context.push('/trip/new'),
          ),
        Section(context.t('madeForYou')),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    context.t('ai'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                context.t('aiHomeTitle'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(context.t('aiHomeBody')),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.push('/trip/new'),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(context.t('planWithAi')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Notice(context.t('demoNotice'), icon: Icons.devices_outlined),
      ],
    );
  }
}
