import 'package:crystal_navigation_bar/crystal_navigation_bar.dart';
import 'package:anajak_travel/shared/components/anajak_bottom_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ui_test.dart' show launch;
import 'package:anajak_travel/app/router/router.dart';

void main() {
  testWidgets('crystal navigation follows taps and external route changes', (
    tester,
  ) async {
    final container = await launch(tester);
    expect(find.byType(CrystalNavigationBar), findsOneWidget);
    await tester.tap(
      find
          .descendant(
            of: find.byType(CrystalNavigationBar),
            matching: find.byType(InkWell),
          )
          .at(2),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnajakBottomBar>(find.byType(AnajakBottomBar)).index,
      2,
    );
    container.read(routerProvider).go('/profile');
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnajakBottomBar>(find.byType(AnajakBottomBar)).index,
      4,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large Khmer text has accessible native navigation', (
    tester,
  ) async {
    await launch(tester, locale: 'km', scale: 2, size: const Size(360, 800));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(CrystalNavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
