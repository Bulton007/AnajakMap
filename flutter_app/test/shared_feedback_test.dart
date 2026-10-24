import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/shared/components/place_photo.dart';
import 'package:anajak_travel/shared/components/travel_success.dart';

void main() {
  testWidgets('success waits for confirmation and automatically dismisses', (
    tester,
  ) async {
    final saved = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                await saved.future;
                if (context.mounted) {
                  showTravelSuccess(context, message: 'Trip saved');
                }
              },
              child: const Text('Save'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Trip saved'), findsNothing);
    saved.complete();
    await tester.pumpAndSettle();
    expect(find.text('Trip saved'), findsOneWidget);
    expect(find.byType(TempleSuccessIllustration), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Trip saved'), findsNothing);
  });
  testWidgets('reduced motion success remains visible and accessible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            disableAnimations: true,
            accessibleNavigation: true,
          ),
          child: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showTravelSuccess(context, message: 'Saved'),
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('missing and invalid photo URLs use a stable labeled fallback', (
    tester,
  ) async {
    for (final photo in [
      null,
      {'url': 'http://invalid.test/image.jpg'},
      {'url': ''},
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: PlacePhoto(name: 'Kep', photo: photo),
            ),
          ),
        ),
      );
      expect(find.text('Photo unavailable'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.getSize(find.byType(PlacePhoto)).height, 170);
    }
  });
  testWidgets('image decode failure offers retry and preserves attribution', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: PlacePhoto(
              name: 'Kep',
              photo: const {
                'url': 'https://example.test/kep.jpg',
                'artist': 'Artist',
                'license': 'CC BY-SA',
              },
              imageProvider: MemoryImage(Uint8List.fromList([0])),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('Retry photo'), findsOneWidget);
    expect(find.text('Artist · CC BY-SA'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
