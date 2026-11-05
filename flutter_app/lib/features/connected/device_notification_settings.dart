import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/localization/strings.dart';
import '../../core/network/providers.dart';
import '../../core/notifications/device_notifications.dart';

class DeviceNotificationSettings extends ConsumerStatefulWidget {
  const DeviceNotificationSettings({super.key, required this.scope});
  final String scope;

  @override
  ConsumerState<DeviceNotificationSettings> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<DeviceNotificationSettings>
    with WidgetsBindingObserver {
  bool busy = false;
  String? result;

  String t(String en, String km) => context.isKhmer ? km : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(ref.read(deviceNotificationsProvider).permission());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(deviceNotificationsProvider).permission());
    }
  }

  Future<void> run(Future<void> Function() operation, String message) async {
    if (busy) return;
    setState(() {
      busy = true;
      result = null;
    });
    try {
      await operation();
      if (!mounted) return;
      final enabled =
          ref.read(deviceNotificationsProvider).state.value ==
          DeviceNotificationState.enabled;
      setState(
        () => result = enabled
            ? message
            : t(
                'Allow notifications in your phone settings.',
                'អនុញ្ញាតការជូនដំណឹងនៅការកំណត់ទូរសព្ទ។',
              ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => result = t(
            'Could not show the notification. Check phone settings and try again.',
            'មិនអាចបង្ហាញការជូនដំណឹងបាន។ សូមពិនិត្យការកំណត់ទូរសព្ទ។',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final device = ref.watch(deviceNotificationsProvider);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder(
          valueListenable: device.state,
          builder: (context, status, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    status == DeviceNotificationState.enabled
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      status == DeviceNotificationState.enabled
                          ? t(
                              'Phone notifications on',
                              'បានបើកការជូនដំណឹងទូរសព្ទ',
                            )
                          : t(
                              'Enable phone notifications',
                              'បើកការជូនដំណឹងទូរសព្ទ',
                            ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: t(
                      'Phone notification settings',
                      'ការកំណត់ការជូនដំណឹងទូរសព្ទ',
                    ),
                    onPressed: Geolocator.openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(
                            () => device.test(widget.scope),
                            t(
                              'Check your phone notification tray.',
                              'សូមមើលថតការជូនដំណឹងទូរសព្ទ។',
                            ),
                          ),
                    icon: const Icon(Icons.notifications_outlined, size: 18),
                    label: Text(t('Test notification', 'សាកល្បងការជូនដំណឹង')),
                  ),
                  OutlinedButton(
                    onPressed: busy
                        ? null
                        : () => run(
                            () => device.test(widget.scope, scheduled: true),
                            t(
                              'Reminder set for 15 seconds. Android may delay it unless precise timing is allowed.',
                              'បានកំណត់រំលឹកក្នុង ១៥ វិនាទី។ អ្នកអាចចាកចេញពីកម្មវិធី។',
                            ),
                          ),
                    child: Text(t('Test reminder', 'សាកល្បងការរំលឹក')),
                  ),
                  if (Theme.of(context).platform == TargetPlatform.android)
                    TextButton(
                      onPressed: busy ? null : () => device.preciseReminders(),
                      child: Text(
                        t('Precise reminder timing', 'ពេលវេលារំលឹកជាក់លាក់'),
                      ),
                    ),
                ],
              ),
              if (result != null) ...[
                const SizedBox(height: 8),
                Text(result!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
