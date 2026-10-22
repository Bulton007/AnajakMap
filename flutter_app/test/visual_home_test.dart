import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/features/connected/connected_trips.dart';
import 'connected_contract_test.dart'
    show MemoryCredentials, Transport, response;
import 'ui_test.dart' show launch;
import 'package:anajak_travel/shared/components/visual.dart';

void main() {
  testWidgets(
    'visual actions remain usable at 200 percent text in Khmer dark',
    (tester) async {
      await launch(
        tester,
        locale: 'km',
        theme: ThemeMode.dark,
        scale: 2,
        size: const Size(320, 640),
      );
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: VisualActions(
                    children: [
                      VisualAction(
                        icon: Icons.pets,
                        label: 'ដំណើរសត្វវេទមន្ត',
                        onTap: () => tapped = true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ដំណើរសត្វវេទមន្ត'));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('connected home visual preview and trip creation', (
    tester,
  ) async {
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
    final api = ApiClient(
      'https://example.test/api/v1/',
      MemoryCredentials(),
      transport: Dio()
        ..httpClientAdapter = Transport(
          (r) async => response(
            r.path == 'runtime' ? {'developmentProviders': true} : [],
          ),
        ),
    );
    final key = GlobalKey();
    await tester.runAsync(() => Strings.delegate.load(const Locale('en')));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: MaterialApp(
          localizationsDelegates: const [Strings.delegate],
          theme: Tokens.theme(Brightness.light),
          home: RepaintBoundary(
            key: key,
            child: const Scaffold(
              body: ConnectedTrips(profile: {'name': 'Nagumo'}, home: true),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () async => precacheImage(
        const AssetImage('assets/images/angkor.jpg'),
        tester.element(find.byType(ConnectedTrips)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('.local').create(recursive: true);
      await File(
        '.local/visual-home.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    final create = find.widgetWithIcon(FilledButton, Icons.add);
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
