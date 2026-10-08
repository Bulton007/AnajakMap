import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anajak_travel/app/app.dart';
import 'package:anajak_travel/app/router/router.dart';
import 'package:anajak_travel/core/storage/app_state.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/storage/travel_database.dart';
import 'package:anajak_travel/shared/components/record_form.dart';

Future<ProviderContainer> launch(
  WidgetTester tester, {
  String locale = 'en',
  ThemeMode theme = ThemeMode.light,
  String route = '/home',
  double scale = 1,
  Size size = const Size(390, 844),
  Environment environment = const Environment(mode: 'demo'),
  ApiClient? api,
  TravelDatabase? database,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({
    'anajak.demo.v1': jsonEncode(
      AppController.seed()
          .copyWith(onboarded: true, locale: locale, theme: theme)
          .toJson(),
    ),
  });
  final prefs = await SharedPreferences.getInstance();
  final font = FontLoader('NotoSansKhmer')
    ..addFont(rootBundle.load('assets/fonts/NotoSansKhmer.ttf'));
  await font.load();
  final serif = FontLoader('CormorantGaramond')
    ..addFont(rootBundle.load('assets/fonts/CormorantGaramond.ttf'));
  await serif.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  final container = ProviderContainer(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      environmentProvider.overrideWithValue(environment),
      if (api != null) apiProvider.overrideWithValue(api),
      if (database != null) databaseProvider.overrideWithValue(database),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AnajakApp()),
  );
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/images/angkor.jpg'),
      tester.element(find.byType(AnajakApp)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
  container.read(routerProvider).go(route);
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final screen in [
    ('explore', '/explore'),
    ('companion', '/companion'),
    ('itinerary', '/trip/sample'),
  ]) {
    testWidgets('${screen.$1} visual preview', (tester) async {
      await launch(tester, route: screen.$2);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(AnajakApp),
        matchesGoldenFile('goldens/${screen.$1}.png'),
      );
    });
  }
  testWidgets('place confirmation updates selected trip itinerary', (
    tester,
  ) async {
    final c = await launch(tester, route: '/place/angkor');
    await tester.ensureVisible(find.text('Add to itinerary'));
    await tester.tap(find.text('Add to itinerary'));
    await tester.pumpAndSettle();
    expect(c.read(appStateProvider).trips.single.activities.length, 4);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pumpAndSettle();
    expect(c.read(appStateProvider).trips.single.activities.length, 5);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'create trip reviews sample then explicitly approves saved itinerary',
    (tester) async {
      final c = await launch(tester, route: '/trip/new');
      await tester.enterText(
        find.byType(TextFormField).first,
        'A quiet weekend',
      );
      await tester.tap(find.text('Travel dates'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      final dateFields = find.descendant(
        of: find.byType(DateRangePickerDialog),
        matching: find.byType(TextField),
      );
      final today = DateFormat.yMd('en').format(DateTime.now());
      await tester.enterText(dateFields.at(0), today);
      await tester.enterText(dateFields.at(1), today);
      await tester.tap(find.text('OK').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('preview-trip')));
      await tester.tap(find.byKey(const Key('preview-trip')));
      await tester.pumpAndSettle();
      expect(c.read(appStateProvider).trips.length, 1);
      expect(find.text('SAMPLE PROPOSAL'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('approve-trip')));
      await tester.tap(find.byKey(const Key('approve-trip')));
      await tester.pumpAndSettle();
      expect(c.read(appStateProvider).trips.length, 2);
      expect(find.text('A quiet weekend'), findsOneWidget);
      expect(find.text('Itinerary'), findsWidgets);
    },
  );
  testWidgets('small screen with large text has no clipped layout', (
    tester,
  ) async {
    final c = await launch(tester, size: const Size(360, 800), scale: 2);
    for (final route in [
      '/home',
      '/profile',
      '/trip/new',
      '/trip/sample',
      '/explore',
    ]) {
      c.read(routerProvider).go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: route);
    }
  });
  testWidgets('home visual English light', (tester) async {
    await launch(tester);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(AnajakApp),
      matchesGoldenFile('goldens/home_en_light.png'),
    );
  });
  testWidgets('home visual Khmer dark', (tester) async {
    await launch(tester, locale: 'km', theme: ThemeMode.dark);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(AnajakApp),
      matchesGoldenFile('goldens/home_km_dark.png'),
    );
  });
  testWidgets('all tabs navigate and map gives honest configuration state', (
    tester,
  ) async {
    await launch(tester);
    for (final icon in [
      Icons.work_outline_rounded,
      Icons.explore_outlined,
      Icons.auto_awesome_outlined,
      Icons.person_outline_rounded,
      Icons.home_outlined,
    ]) {
      await tester.tap(find.byIcon(icon).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byIcon(Icons.explore_outlined).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Your map, coming into focus'), findsOneWidget);
  });
  testWidgets('receipt stays draft until review and confirmation', (
    tester,
  ) async {
    final container = await launch(tester, route: '/trip/sample/expenses');
    await tester.tap(find.text('Review sample receipt'));
    await tester.pumpAndSettle();
    expect(container.read(appStateProvider).records, isEmpty);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save'),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordForm), findsNothing);
    expect(container.read(appStateProvider).records.single.cents, 1250);
  });
  testWidgets('locale and appearance can change without losing trip form', (
    tester,
  ) async {
    final container = await launch(tester, route: '/trip/new');
    await tester.enterText(find.byType(TextFormField).first, 'My journey');
    await container
        .read(appStateProvider.notifier)
        .settings(locale: 'km', theme: ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(find.text('My journey'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('all primary and detail screens render in Khmer', (tester) async {
    final c = await launch(tester, locale: 'km');
    for (final route in [
      '/trips',
      '/explore',
      '/companion',
      '/profile',
      '/trip/sample',
      '/trip/sample/expenses',
      '/trip/sample/reservations',
      '/trip/sample/group',
      '/trip/sample/journal',
      '/trip/sample/offline',
      '/translation',
      '/gallery',
      '/welcome',
    ]) {
      c.read(routerProvider).go(route);
      if (route == '/gallery') {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      } else {
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull, reason: route);
    }
  });
}
