import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/features/connected/discovery_details.dart';

void main() {
  testWidgets('culture details use photo and accessible cards', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final name in ['NotoSansKhmer', 'CormorantGaramond']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await tester.runAsync(() => Strings.delegate.load(const Locale('en')));
    final key = GlobalKey();
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [Strings.delegate],
          theme: Tokens.theme(brightness),
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              appBar: AppBar(title: const Text('Culture')),
              body: const DiscoveryDetails(
                operation: 'culture',
                query: 'Kampot',
                data: {
                  'guidance': 'Dress respectfully at religious sites',
                  'mock': true,
                },
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/images/angkor.jpg'),
          tester.element(find.byType(DiscoveryDetails)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsWidgets);
      expect(find.byIcon(Icons.temple_buddhist_outlined), findsOneWidget);
      expect(
        find.text('Sample information · not live local data'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (brightness == Brightness.light) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('.local').create(recursive: true);
          await File(
            '.local/visual-culture.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
  });
}
