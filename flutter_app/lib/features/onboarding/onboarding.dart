import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingScreen> {
  int step = 0;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    return Scaffold(
      appBar: AppBar(
        leading: step > 0
            ? BackButton(onPressed: () => setState(() => step--))
            : null,
        title: Text(context.t('appName')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Pill(context.t('demo')),
          ),
        ],
      ),
      body: SafeArea(
        child: PageBody(
          children: [
            if (step == 0) ...[
              Photo(
                height: 320,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Pill(
                      context.t('cambodia'),
                      icon: Icons.location_on_outlined,
                      onDark: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                context.t('welcome'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              Text(context.t('welcomeBody')),
            ],
            if (step == 1) ...[
              const SizedBox(height: 40),
              const Icon(Icons.language, size: 48),
              const SizedBox(height: 24),
              Text(
                context.t('languageTitle'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(context.t('languageBody')),
              const SizedBox(height: 30),
              for (final item in [('en', 'English'), ('km', 'ភាសាខ្មែរ')])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: ListTile(
                      minVerticalPadding: 18,
                      title: Text(item.$2),
                      trailing: Icon(
                        state.locale == item.$1
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                      ),
                      onTap: () => persist(
                        context,
                        () => ref
                            .read(appStateProvider.notifier)
                            .settings(locale: item.$1),
                      ),
                    ),
                  ),
                ),
            ],
            if (step == 2) ...[
              const SizedBox(height: 40),
              const Icon(Icons.favorite_border, size: 48),
              const SizedBox(height: 24),
              Text(
                context.t('preferences'),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(context.t('preferencesBody')),
              const SizedBox(height: 30),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final key in ['culture', 'food', 'nature', 'relax'])
                    FilterChip(
                      label: Text(context.t(key)),
                      selected: state.interests.contains(key),
                      onSelected: (v) => persist(
                        context,
                        () => ref
                            .read(appStateProvider.notifier)
                            .settings(
                              interests: v
                                  ? [...state.interests, key]
                                  : state.interests
                                        .where((e) => e != key)
                                        .toList(),
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Notice(context.t('demoNotice')),
            ],
            const SizedBox(height: 32),
            Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.only(right: 7),
                    height: 5,
                    width: i == step ? 30 : 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: i == step
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  if (step < 2) {
                    setState(() => step++);
                  } else {
                    final ok = await persist(
                      context,
                      () => ref
                          .read(appStateProvider.notifier)
                          .settings(onboarded: true),
                    );
                    if (ok && context.mounted) {
                      context.go('/home');
                    }
                  }
                },
                child: Text(
                  context.t(
                    step == 0
                        ? 'getStarted'
                        : step == 1
                        ? 'next'
                        : 'finish',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
