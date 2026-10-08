import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/localization/strings.dart';
import '../../core/storage/app_state.dart';
import '../../shared/components/components.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    return PageBody(
      children: [
        const SizedBox(height: 12),
        Text(
          context.t('profile'),
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 10),
        Text(context.t('settings')),
        const SizedBox(height: 26),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                  child: Icon(
                    Icons.person_outline,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t('traveler'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        context.t('guest'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Section(context.t('preferences')),
        const PreferencesControls(),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              _Setting(
                icon: Icons.account_circle_outlined,
                title: context.t('account'),
                onTap: () => inform(
                  context,
                  context.t('account'),
                  context.t('accountBody'),
                ),
              ),
              _Setting(
                icon: Icons.payments_outlined,
                title: context.t('currency'),
                subtitle: context.t('currencyBody'),
                onTap: () => inform(
                  context,
                  context.t('currency'),
                  context.t('currencyBody'),
                ),
              ),
              _Setting(
                icon: Icons.notifications_none,
                title: context.t('notifications'),
                onTap: () => inform(
                  context,
                  context.t('notifications'),
                  context.t('notConnected'),
                ),
              ),
              _Setting(
                icon: Icons.shield_outlined,
                title: context.t('privacy'),
                onTap: () => inform(
                  context,
                  context.t('privacy'),
                  context.t('privacyBody'),
                ),
              ),
              _Setting(
                icon: Icons.offline_pin_outlined,
                title: context.t('offline'),
                onTap: () {
                  if (state.trips.isNotEmpty) {
                    context.push('/trip/${state.trips.last.id}/offline');
                  } else {
                    inform(
                      context,
                      context.t('offline'),
                      context.t('offlineBody'),
                    );
                  }
                },
              ),
              _Setting(
                icon: Icons.palette_outlined,
                title: context.t('gallery'),
                onTap: () => context.push('/gallery'),
              ),
              _Setting(
                icon: Icons.help_outline,
                title: context.t('help'),
                onTap: () =>
                    inform(context, context.t('help'), context.t('helpBody')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
            if (await confirmDialog(
                  context,
                  context.t('clearData'),
                  context.t('clearConfirm'),
                ) &&
                context.mounted) {
              await persist(
                context,
                () => ref.read(appStateProvider.notifier).reset(),
              );
            }
          },
          icon: const Icon(Icons.restart_alt),
          label: Text(context.t('clearData')),
        ),
        const SizedBox(height: 12),
        Notice(context.t('demoNotice')),
      ],
    );
  }
}

class _Setting extends StatelessWidget {
  const _Setting({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    minVerticalPadding: 14,
    leading: Icon(icon, size: 22),
    title: Text(title),
    subtitle: subtitle == null
        ? null
        : Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: onTap,
  );
}

class PreferencesControls extends ConsumerWidget {
  const PreferencesControls({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('language'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            for (final item in [('en', 'English'), ('km', 'ភាសាខ្មែរ')])
              ChoiceChip(
                label: Text(item.$2),
                selected: state.locale == item.$1,
                onSelected: (_) => persist(
                  context,
                  () => ref
                      .read(appStateProvider.notifier)
                      .settings(locale: item.$1),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          context.t('appearance'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in ThemeMode.values)
              ChoiceChip(
                label: Text(context.t(mode.name)),
                avatar: Icon(
                  mode == ThemeMode.dark
                      ? Icons.dark_mode_outlined
                      : mode == ThemeMode.light
                      ? Icons.light_mode_outlined
                      : Icons.brightness_auto_outlined,
                  size: 17,
                ),
                selected: state.theme == mode,
                onSelected: (_) => persist(
                  context,
                  () =>
                      ref.read(appStateProvider.notifier).settings(theme: mode),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

Future<void> showPreferences(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => const Padding(
        padding: EdgeInsets.all(24),
        child: SingleChildScrollView(child: PreferencesControls()),
      ),
    );
