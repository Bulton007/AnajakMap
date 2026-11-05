import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/formatting/travel_money.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../core/network/live_socket.dart';
import '../../core/notifications/device_notifications.dart';
import '../../shared/components/components.dart';
import '../../shared/components/anajak_bottom_bar.dart';
import '../../shared/components/remote.dart';
import '../authentication/authentication.dart';
import '../authentication/auth_controller.dart';
import '../profile/profile.dart';
import 'connected_trips.dart';
import 'connected_explore.dart';
import 'connected_tools.dart';
import 'connected_offline.dart';
import 'direct_messages.dart';
import '../rpg/rpg_screen.dart';
import 'package:go_router/go_router.dart';

class ConnectedGate extends ConsumerWidget {
  const ConnectedGate({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth.authenticated) {
      return ConnectedShell(
        key: ValueKey(string(auth.session!.user.profile, 'id')),
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
  int unread = 0;
  Timer? notificationsTimer;
  WebSocket? notificationsSocket;
  bool checking = false, connecting = false;
  final seenAlerts = <String>{};
  StreamSubscription<Json>? notificationTaps;
  late final DeviceNotifications _deviceNotifications;
  late final String notificationScope;

  @override
  void initState() {
    super.initState();
    _deviceNotifications = ref.read(deviceNotificationsProvider);
    notificationScope =
        '${ref.read(environmentProvider).normalizedUrl}|${string(widget.profile, 'id')}';
    notificationTaps = ref.read(deviceNotificationsProvider).taps.stream.listen(
      (payload) {
        if (!mounted || string(payload, 'scope') != notificationScope) return;
        openNotifications(initialNotification: payload);
      },
    );
    ref.listenManual(notificationUpdateProvider, (_, _) {
      if (mounted) unawaited(checkNotifications());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(startDeviceNotifications());
    });
    notificationsTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(checkNotifications());
      }
    });
  }

  Future<void> startDeviceNotifications() async {
    try {
      await ref.read(deviceNotificationsProvider).activate(notificationScope);
    } catch (_) {
      // The inbox remains available when phone notifications cannot initialize.
    }
    if (mounted) await checkNotifications();
  }

  Future<void> connectNotifications() async {
    if (connecting || notificationsSocket != null) return;
    connecting = true;
    try {
      final socket = await openLiveSocket(
        ref.read(apiProvider),
        'notifications/live',
      );
      if (socket == null) return;
      if (!mounted) {
        await socket.close();
        return;
      }
      notificationsSocket = socket;
      void disconnected() {
        if (notificationsSocket == socket) notificationsSocket = null;
      }

      socket.listen(
        (event) {
          if (mounted && (event == 'changed' || event == 'ready')) {
            ref.invalidate(notificationUpdateProvider);
          }
        },
        onDone: disconnected,
        onError: (Object _) => disconnected(),
      );
    } catch (_) {
      // Periodic refresh stays active if the socket cannot connect.
    } finally {
      connecting = false;
    }
  }

  Future<void> checkNotifications() async {
    if (checking || widget.profile['offlineSession'] == true) return;
    checking = true;
    try {
      final repo = ref.read(repositoryProvider);
      final count = await repo.unreadNotifications();
      if (!mounted) return;
      if (count != unread) setState(() => unread = count);
      unawaited(connectNotifications());
      final rows = await repo.deliveries();
      if (!mounted) return;
      final device = ref.read(deviceNotificationsProvider);
      for (final row in rows) {
        if (!mounted) return;
        final status = string(row, 'status');
        if (status == 'CANCELLED' || field(row, 'readAt') != null) {
          await device.cancel(notificationScope, string(row, 'id'));
        } else if (string(row, 'kind') == 'REMINDER' && status == 'PENDING') {
          await device.reminder(notificationScope, row);
        }
      }
      final now = DateTime.now();
      final newAlerts = rows.where((row) {
        final due = DateTime.tryParse(string(row, 'dueAt'));
        return field(row, 'readAt') == null &&
            string(row, 'status') != 'CANCELLED' &&
            due != null &&
            !due.isAfter(now) &&
            (string(row, 'kind') != 'REMINDER' ||
                now.difference(due) < const Duration(minutes: 2)) &&
            seenAlerts.add(string(row, 'id'));
      }).toList();
      for (final alert in newAlerts) {
        if (!mounted) return;
        var body = string(alert, 'detail');
        final actor = string(alert, 'actorId');
        if (actor.isNotEmpty) {
          try {
            final sender = string(await repo.traveler(actor), 'displayName');
            body = [
              if (sender.isNotEmpty) sender,
              if (body.isNotEmpty) body,
            ].join(' · ');
          } catch (_) {
            // The notification can still be delivered if a profile lookup fails.
          }
        }
        if (!mounted) return;
        await device.show(notificationScope, {...alert, 'detail': body});
      }
    } catch (_) {
      // Keep the last known badge when connectivity is interrupted.
    } finally {
      checking = false;
    }
  }

  Future<void> openNotifications({Json? initialNotification}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ConnectedTools(
          tool: 'notifications',
          profile: widget.profile,
          initialNotification: initialNotification,
        ),
      ),
    );
    if (mounted) unawaited(checkNotifications());
  }

  @override
  void dispose() {
    unawaited(notificationTaps?.cancel());
    unawaited(
      _deviceNotifications
          .deactivate(notificationScope)
          .catchError((Object _) {}),
    );
    notificationsTimer?.cancel();
    unawaited(notificationsSocket?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBody: true,
    appBar: AppBar(
      title: Text(context.t('appName')),
      actions: [
        IconButton(
          tooltip: context.t('notifications'),
          onPressed: openNotifications,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
        ),
        IconButton(
          tooltip: context.isKhmer ? 'ផែនទី' : 'Map',
          onPressed: () => context.push('/map'),
          icon: const Icon(Icons.map_outlined),
        ),
        IconButton(
          tooltip: rpgText(
            context,
            'Creature trails',
            'ដំណើរស្វែងរកសត្វវេទមន្ត',
          ),
          onPressed: () => context.push('/adventure'),
          icon: const Icon(Icons.sports_esports_outlined),
        ),
        IconButton(
          tooltip: context.t('language'),
          onPressed: () => showPreferences(context),
          icon: const Icon(Icons.tune),
        ),
      ],
    ),
    body: SafeArea(
      bottom: true,
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
    bottomNavigationBar: AnajakBottomBar(
      index: tab,
      onTap: (i) => setState(() => tab = i),
    ),
  );
}

class ConnectedProfile extends ConsumerWidget {
  const ConnectedProfile({super.key, required this.profile});
  final Json profile;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PageBody(
    children: [
      Text(context.t('profile'), style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer,
                child: const Icon(Icons.person_outline_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      string(profile, 'name', context.t('profile')),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    SelectableText(
                      string(profile, 'email'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: Text(
              '${context.t('accountId')}: ${readableAccountId(string(profile, 'id'))}',
            ),
          ),
          IconButton(
            tooltip: context.isKhmer
                ? 'ចម្លងលេខសម្គាល់គណនីពេញ'
                : 'Copy full account ID',
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: string(profile, 'id')),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.isKhmer
                          ? 'បានចម្លងលេខសម្គាល់គណនី'
                          : 'Account ID copied',
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Card(
        child: ExpansionTile(
          key: const PageStorageKey('profile-appearance'),
          leading: const Icon(Icons.palette_outlined),
          title: Text(
            '${context.t('language')} · ${context.t('appearance')}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: const [PreferencesControls()],
        ),
      ),
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
        dense: true,
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
        dense: true,
        icon: Icons.forum_outlined,
        title: context.isKhmer ? 'សារឯកជន' : 'Private messages',
        subtitle: context.isKhmer
            ? 'ជជែកជាមួយអ្នកធ្វើដំណើរ'
            : 'Chat with travelers',
        onTap: () => openScreen(
          context,
          DirectMessages(accountId: string(profile, 'id')),
        ),
      ),
      const SizedBox(height: 12),
      ActionCard(
        dense: true,
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
