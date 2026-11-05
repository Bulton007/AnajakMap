import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../network/api_client.dart';

enum DeviceNotificationState { unknown, enabled, denied, unavailable, failed }

/// Displays server inbox events and schedules the user's reminders on this device.
class DeviceNotifications {
  DeviceNotifications({FlutterLocalNotificationsPlugin? plugin})
    : plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin plugin;
  final state = ValueNotifier(DeviceNotificationState.unknown);
  final taps = StreamController<Json>.broadcast();
  Future<void>? _initializing;
  Future<void> _queue = Future.value();
  String? _scope;
  Json? _pendingTap;

  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);

  Future<void> initialize() => _initializing ??= _initialize();

  Future<void> _initialize() async {
    if (!supported) {
      state.value = DeviceNotificationState.unavailable;
      return;
    }
    timezone_data.initializeTimeZones();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _receive(response.payload),
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      _receive(launch?.notificationResponse?.payload);
    }
  }

  void _receive(String? value) {
    try {
      final payload = object(jsonDecode(value ?? ''));
      if (string(payload, 'scope') != _scope) {
        _pendingTap = payload;
        return;
      }
      taps.add(payload);
    } on FormatException {
      // Ignore an expired or malformed launch payload.
    }
  }

  Future<void> activate(String scope) => _serialize(() async {
    await initialize();
    if (!supported) return;
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString('notifications.activeScope');
    if (previous != scope) {
      await plugin.cancelAll();
      await prefs.remove('notifications.scheduled.$scope');
    }
    _scope = scope;
    await prefs.setString('notifications.activeScope', scope);
    await permission(
      request: !prefs.containsKey('notifications.permissionAsked'),
    );
    final pending = _pendingTap;
    _pendingTap = null;
    if (pending != null && string(pending, 'scope') == scope) taps.add(pending);
  });

  Future<bool> permission({bool request = false}) async {
    try {
      await initialize();
      if (!supported) return false;
      bool granted = false;
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final ios = plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        granted =
            (request
                ? await android.requestNotificationsPermission()
                : await android.areNotificationsEnabled()) ??
            false;
      } else if (ios != null) {
        granted = request
            ? await ios.requestPermissions(
                    alert: true,
                    badge: true,
                    sound: true,
                  ) ??
                  false
            : (await ios.checkPermissions())?.isEnabled ?? false;
      }
      if (request) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('notifications.permissionAsked', true);
      }
      state.value = granted
          ? DeviceNotificationState.enabled
          : DeviceNotificationState.denied;
      return granted;
    } catch (_) {
      state.value = DeviceNotificationState.failed;
      return false;
    }
  }

  Future<void> preciseReminders() async {
    await initialize();
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  Future<void> deactivate(String scope) => _serialize(() async {
    if (_scope != scope) return;
    _scope = null;
    if (supported) await plugin.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notifications.activeScope');
    await prefs.remove('notifications.scheduled.$scope');
  });

  Future<void> _serialize(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.catchError((Object _) {
      state.value = DeviceNotificationState.failed;
    });
    return _queue;
  }

  static Json payload(String scope, Json row) => {
    'scope': scope,
    'id': string(row, 'id'),
    'kind': string(row, 'kind'),
    'tripId': string(row, 'tripId'),
    'actorId': string(row, 'actorId'),
  };

  Future<int> _id(SharedPreferences prefs, String scope, String id) async {
    final ids = object(
      jsonDecode(prefs.getString('notifications.ids') ?? '{}'),
    );
    final key = '$scope|$id';
    if (ids[key] case final int value) return value;
    final next = (prefs.getInt('notifications.nextId') ?? 0) + 1;
    ids[key] = next;
    await prefs.setString('notifications.ids', jsonEncode(ids));
    await prefs.setInt('notifications.nextId', next);
    return next;
  }

  NotificationDetails get details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'anajak_updates_v1',
      'Messages, invitations and reminders',
      channelDescription: 'Updates for your Anajak trips and conversations',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF244D3E),
      icon: 'ic_notification',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
    ),
  );

  Future<void> show(String scope, Json row) => _serialize(() async {
    if (_scope != scope || !await permission()) return;
    final id = string(row, 'id');
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getStringList('notifications.seen.$scope') ?? [];
    final schedules = object(
      jsonDecode(prefs.getString('notifications.scheduled.$scope') ?? '{}'),
    );
    if (seen.contains(id) || schedules.containsKey(id)) return;
    await plugin.show(
      id: await _id(prefs, scope, id),
      title: string(row, 'title'),
      body: string(row, 'detail').isEmpty ? 'Anajak' : string(row, 'detail'),
      notificationDetails: details,
      payload: jsonEncode(payload(scope, row)),
    );
    await prefs.setStringList('notifications.seen.$scope', [...seen, id]);
  });

  Future<void> reminder(String scope, Json row) => _serialize(() async {
    if (_scope != scope || !await permission()) return;
    final due = DateTime.tryParse(string(row, 'dueAt'));
    final id = string(row, 'id');
    if (id.isEmpty || due == null || !due.isAfter(DateTime.now())) return;
    final prefs = await SharedPreferences.getInstance();
    final schedules = object(
      jsonDecode(prefs.getString('notifications.scheduled.$scope') ?? '{}'),
    );
    final fingerprint = jsonEncode([
      string(row, 'title'),
      due.toUtc().toIso8601String(),
    ]);
    if (schedules[id] == fingerprint) return;
    final exact =
        await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.canScheduleExactNotifications() ??
        false;
    await plugin.zonedSchedule(
      id: await _id(prefs, scope, id),
      title: string(row, 'title'),
      body: 'Anajak',
      scheduledDate: tz.TZDateTime.from(due, tz.UTC),
      notificationDetails: details,
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode(payload(scope, {...row, 'kind': 'REMINDER'})),
    );
    schedules[id] = fingerprint;
    await prefs.setString(
      'notifications.scheduled.$scope',
      jsonEncode(schedules),
    );
  });

  Future<void> cancel(String scope, String id) => _serialize(() async {
    if (_scope != scope || !supported) return;
    final prefs = await SharedPreferences.getInstance();
    await plugin.cancel(id: await _id(prefs, scope, id));
    final schedules = object(
      jsonDecode(prefs.getString('notifications.scheduled.$scope') ?? '{}'),
    );
    schedules.remove(id);
    await prefs.setString(
      'notifications.scheduled.$scope',
      jsonEncode(schedules),
    );
    final seen = prefs.getStringList('notifications.seen.$scope') ?? [];
    if (!seen.contains(id)) {
      await prefs.setStringList('notifications.seen.$scope', [...seen, id]);
    }
  });

  Future<void> test(String scope, {bool scheduled = false}) async {
    if (!await permission(request: true)) return;
    final row = <String, dynamic>{
      'id': 'device-test-${DateTime.now().microsecondsSinceEpoch}',
      'title': scheduled ? 'Anajak reminder test' : 'Anajak notification test',
      'detail': 'Phone notifications are working',
      'kind': 'TEST',
      'dueAt': DateTime.now()
          .add(const Duration(seconds: 15))
          .toUtc()
          .toIso8601String(),
    };
    if (scheduled) {
      await reminder(scope, row);
    } else {
      await show(scope, row);
    }
  }
}
