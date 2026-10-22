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
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Photo credit'), findsOneWidget);
    expect(find.textContaining('Own work'), findsOneWidget);
    expect(find.text('License'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
