import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/shared/components/visual.dart';

void main() {
  testWidgets('Companion rows fit narrow screens with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 580));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const VisualAction(
                  horizontal: true,
                  icon: Icons.mic_rounded,
                  label: 'Voice assistance',
                  subtitle: 'Service not enabled',
                  onTap: null,
                ),
                VisualAction(
                  horizontal: true,
                  icon: Icons.forum_rounded,
                  label: 'Ask your companion',
                  onTap: () => opened = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    await tester.tap(find.text('Ask your companion'));
    expect(opened, isTrue);
  });

  for (final scale in [1.0, 2.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'action cards align and remain readable at $scale $brightness',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(360, 640));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: VisualActions(
                        children: [
                          VisualAction(
                            key: const Key('first'),
                            icon: Icons.route,
                            label: 'Build an itinerary with your companion',
                            onTap: () {},
                          ),
                          VisualAction(
                            key: const Key('second'),
                            icon: Icons.translate,
                            label: 'Say it in Khmer',
                            onTap: () {},
                          ),
                          VisualAction(
                            icon: Icons.chat,
                            label: 'Ask your companion',
                            onTap: () {},
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          final first = tester.getRect(find.byKey(const Key('first')));
          final second = tester.getRect(find.byKey(const Key('second')));
          if (scale == 1) {
            expect(first.top, second.top);
            expect(first.height, second.height);
          } else {
            expect(second.top, greaterThan(first.bottom));
          }
          await tester.scrollUntilVisible(find.text('Ask your companion'), 200);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
