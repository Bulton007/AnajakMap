import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';
import '../authentication/authentication.dart';
import '../authentication/auth_controller.dart';
import '../profile/profile.dart';
import 'connected_trips.dart';
import 'connected_explore.dart';
import 'connected_tools.dart';
import 'connected_offline.dart';

class ConnectedGate extends ConsumerWidget {
  const ConnectedGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth.authenticated) {
      return ConnectedShell(
        profile: {
          ...auth.session!.user.profile,
          if (auth.session!.offline) 'offlineSession': true,
        },
      );
    }
    return const AuthenticationScreen();
  }
}

class ConnectedShell extends ConsumerStatefulWidget {
  const ConnectedShell({super.key, required this.profile});
  final Json profile;
  @override
  ConsumerState<ConnectedShell> createState() => _ConnectedShellState();
}

class _ConnectedShellState extends ConsumerState<ConnectedShell> {
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t('appName')),
      actions: [
        IconButton(
          tooltip: context.t('language'),
          onPressed: () => showPreferences(context),
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (widget.profile['offlineSession'] == true)
            Notice(context.t('offlineSession')),
          Expanded(
            child: IndexedStack(
              index: tab,
              children: [
                ConnectedTrips(profile: widget.profile, home: true),
                ConnectedTrips(profile: widget.profile),
                ConnectedExplore(profile: widget.profile),
                CompanionTasks(profile: widget.profile),
                ConnectedProfile(profile: widget.profile),
              ],
            ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (i) => setState(() => tab = i),
      destinations: [
        for (final item in [
          ('home', Icons.home_outlined),
          ('trips', Icons.work_outline),
          ('explore', Icons.explore_outlined),
          ('ai', Icons.auto_awesome_outlined),
          ('profile', Icons.person_outline),
        ])
          NavigationDestination(icon: Icon(item.$2), label: context.t(item.$1)),
      ],
    ),
  );
}

class ConnectedProfile extends ConsumerWidget {
  const ConnectedProfile({super.key, required this.profile});
  final Json profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    children: [
      Text(
        context.t('profile'),
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      SelectableText(string(profile, 'email')),
      SelectableText('${context.t('accountId')}: ${profile['id']}'),
      const SizedBox(height: 20),
      const PreferencesControls(),
      Section(context.t('preferences')),
      OutlinedButton(
        onPressed: () => remoteForm(
          context,
          'preferences',
          [
            const InputSpec(
              'pace',
              label: 'pace',
              initial: 'relaxed',
              choices: ['relaxed', 'balanced', 'active'],
            ),
            const InputSpec('dietary', kind: InputKind.text, optional: true),
          ],
          submit: (body, _) async {
            final language = Localizations.localeOf(context).languageCode;
            final repo = ref.read(repositoryProvider);
            final current = await repo.profile();
            return repo.preferences({
              ...object(current['preferences']),
              'pace': body['pace'],
              'dietary': body['dietary'] == null
                  ? <String>[]
                  : [body['dietary']],
              'language': language,
            }, integer(current, 'version'));
          },
        ),
        child: Text(context.t('edit')),
      ),
      const SizedBox(height: 16),
      ActionCard(
        icon: Icons.notifications_outlined,
        title: context.t('notifications'),
        subtitle: context.t('reminders'),
        onTap: () => openScreen(
          context,
          ConnectedTools(tool: 'notifications', profile: profile),
        ),
      ),
      const SizedBox(height: 12),
      ActionCard(
        icon: Icons.sync,
        title: context.t('offline'),
        subtitle: context.t('pendingOperations'),
        onTap: () => openScreen(context, ConnectedOffline(profile: profile)),
      ),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: () async {
          final result = await runRequest(
            context,
            () => ref.read(repositoryProvider).runtime(),
          );
          if (context.mounted && result != null) {
            openScreen(
              context,
              Scaffold(
                appBar: AppBar(title: Text(context.t('detailedStatus'))),
                body: PageBody(children: [ServerResult(result)]),
              ),
            );
          }
        },
        child: Text(context.t('detailedStatus')),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: () async {
          if (await confirmDialog(
                context,
                context.t('signOut'),
                context.t('pendingOperations'),
              ) &&
              context.mounted) {
            await runRequest(
              context,
              () => ref.read(authControllerProvider.notifier).logout(),
            );
          }
        },
        child: Text(context.t('signOut')),
      ),
    ],
  );
}
