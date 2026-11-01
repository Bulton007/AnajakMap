import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/shared/components/place_photo.dart';

void main() {
  testWidgets('missing photos have accessible fallback', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PlacePhoto(name: 'Kampot')),
      ),
    );
    expect(find.byIcon(Icons.landscape_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('image failures retain credit and license detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PlacePhoto(
            name: 'Kampot',
            photo: {
              'url': 'https://upload.wikimedia.org/unavailable.jpg',
              'artist': 'Photographer',
              'license': 'CC BY-SA 4.0',
              'credit': 'Own work',
              'sourceUrl': 'https://commons.wikimedia.org/wiki/File:Kampot.jpg',
              'licenseUrl': 'https://creativecommons.org/licenses/by-sa/4.0/',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Photo credit: Kampot'));
    await tester.pumpAndSettle();
    expect(find.text('Photo credit'), findsOneWidget);
    expect(find.textContaining('Own work'), findsOneWidget);
    expect(find.text('License'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'photo credits stay accessible without a separate row in ${brightness.name} mode',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: SizedBox(
                  width: 320,
                  child: PlacePhoto(
                    name: 'Kampot',
                    imageProvider: MemoryImage(
                      base64Decode(
                        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5ioAAAAASUVORK5CYII=',
                      ),
                    ),
                    photo: const {
                      'url': 'https://upload.wikimedia.org/kampot.jpg',
                      'artist': 'Photographer',
                      'license': 'CC BY-SA 4.0',
                      'credit': 'Own work',
                      'sourceUrl':
                          'https://commons.wikimedia.org/wiki/File:Kampot.jpg',
                      'licenseUrl':
                          'https://creativecommons.org/licenses/by-sa/4.0/',
                    },
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pumpAndSettle();

          expect(tester.getSize(find.byType(PlacePhoto)), const Size(320, 170));
          expect(find.textContaining('Photographer'), findsNothing);
          expect(find.textContaining('CC BY-SA'), findsNothing);
          final credit = find.byTooltip('Photo credit: Kampot');
          expect(tester.getSize(credit), const Size(48, 48));
          expect(
            tester.getSemantics(credit).getSemanticsData().tooltip,
            'Photo credit: Kampot',
          );
          await tester.tap(credit);
          await tester.pumpAndSettle();
          expect(find.text('Photo credit'), findsOneWidget);
          expect(
            find.text('Photographer\nCC BY-SA 4.0\nOwn work'),
            findsOneWidget,
          );
          expect(find.text('Wikimedia Commons'), findsOneWidget);
          expect(find.text('License'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
