import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anajak_travel/app/app.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/storage/app_state.dart';
import 'package:anajak_travel/app/router/router.dart';
import 'package:anajak_travel/features/maps/open_map_screen.dart';
import '../test/support/local_tiles.dart';
import 'package:anajak_travel/features/rpg/rpg_controller.dart';
import 'package:anajak_travel/features/rpg/rpg_game.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('emulator: RPG battle and keyless map with local test tiles', (
    tester,
  ) async {
    // Keep smoke-test progress isolated from the user's local collection.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        mapTileFactoryProvider.overrideWithValue(LocalTiles.new),
        preferencesProvider.overrideWithValue(prefs),
        environmentProvider.overrideWithValue(const Environment(mode: 'demo')),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AnajakApp()),
    );
    container.read(routerProvider).go('/rpg');
    await tester.pumpAndSettle();
    final habitat = find.widgetWithIcon(OutlinedButton, Icons.account_balance);
    await tester.scrollUntilVisible(habitat.hitTestable(), 180);
    await tester.tap(habitat);
    await tester.pumpAndSettle();
    expect(container.read(rpgProvider).phase, BattlePhase.battling);
    final strike = find.widgetWithIcon(FilledButton, Icons.flash_on);
    await tester.scrollUntilVisible(strike.hitTestable(), 180);
    await tester.tap(strike);
    await tester.pumpAndSettle();
    expect(container.read(rpgProvider).playerHp, lessThan(100));
    container.read(routerProvider).go('/map');
    await tester.pumpAndSettle();
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
