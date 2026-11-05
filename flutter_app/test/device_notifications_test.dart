import 'package:anajak_travel/core/notifications/device_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  var allowed = true;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    allowed = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'initialize' => true,
            'getNotificationAppLaunchDetails' => null,
            'areNotificationsEnabled' ||
            'requestNotificationsPermission' => allowed,
            'canScheduleExactNotifications' => true,
            _ => null,
          };
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'server event creates one native notification and survives restart deduplication',
    () async {
      final device = DeviceNotifications();
      const row = {
        'id': 'event',
        'title': 'Trip invitation',
        'kind': 'group.invited',
      };
      await device.activate('origin|account-a');
      await device.show('origin|account-a', row);
      await device.show('origin|account-a', row);
      final restarted = DeviceNotifications();
      await restarted.activate('origin|account-a');
      await restarted.show('origin|account-a', row);
      expect(calls.where((call) => call.method == 'show'), hasLength(1));
      final args =
          calls.singleWhere((call) => call.method == 'show').arguments as Map;
      expect(args['title'], 'Trip invitation');
      expect(args['payload'], contains('origin|account-a'));
    },
  );

  test(
    'editing uses the same native reminder ID and cancellation prevents duplicate due alert',
    () async {
      final device = DeviceNotifications();
      await device.activate('scope');
      final row = {
        'id': 'reminder',
        'title': 'Pack bags',
        'dueAt': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      };
      await device.reminder('scope', row);
      await device.reminder('scope', row);
      await device.reminder('scope', {...row, 'title': 'Pack passport'});
      final scheduled = calls
          .where((call) => call.method == 'zonedSchedule')
          .toList();
      expect(scheduled, hasLength(2));
      expect(
        (scheduled[0].arguments as Map)['id'],
        (scheduled[1].arguments as Map)['id'],
      );
      await device.show('scope', {...row, 'kind': 'REMINDER'});
      expect(calls.where((call) => call.method == 'show'), isEmpty);
      await device.cancel('scope', 'reminder');
      expect(calls.where((call) => call.method == 'cancel'), hasLength(1));
      await device.show('scope', row);
      expect(calls.where((call) => call.method == 'show'), isEmpty);
    },
  );

  test(
    'denied permission and switching accounts prevent private notification leaks',
    () async {
      final device = DeviceNotifications();
      allowed = false;
      await device.activate('account-a');
      await device.show('account-a', {
        'id': 'private',
        'title': 'Private message',
      });
      expect(device.state.value, DeviceNotificationState.denied);
      expect(calls.where((call) => call.method == 'show'), isEmpty);
      allowed = true;
      await device.activate('account-b');
      await device.show('account-a', {
        'id': 'private',
        'title': 'Private message',
      });
      expect(calls.where((call) => call.method == 'show'), isEmpty);
      await device.deactivate('account-b');
      expect(calls.where((call) => call.method == 'cancelAll'), hasLength(3));
    },
  );
}
