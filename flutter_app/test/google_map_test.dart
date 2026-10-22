import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/features/maps/google_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('invalid coordinates cannot create misleading markers', () {
    expect(const MapPlace('1', 'A', 91, 0).valid, isFalse);
    expect(const MapPlace('2', 'B', 0, 181).valid, isFalse);
    expect(const MapPlace('3', 'C', double.nan, 1).valid, isFalse);
    expect(const MapPlace('4', 'D', 11.55, 104.92).valid, isTrue);
  });
  test('reads native configuration without returning a key', () async {
    const channel = MethodChannel('anajak/maps_config');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'configured');
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(mapsConfiguredProvider.future), isTrue);
  });
  testWidgets('missing key shows setup instead of opening a native map', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mapsConfiguredProvider.overrideWith((ref) async => false)],
        child: const MaterialApp(home: GoogleMapScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Google Maps needs setup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
