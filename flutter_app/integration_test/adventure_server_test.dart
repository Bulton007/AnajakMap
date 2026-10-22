import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/features/authentication/auth_controller.dart';
import 'package:anajak_travel/features/authentication/auth_models.dart';
import 'package:anajak_travel/features/authentication/auth_repository.dart';
import 'package:anajak_travel/features/rpg/adventure_controller.dart';
import 'package:anajak_travel/features/rpg/adventure_screen.dart';

class _MemoryCredentials implements CredentialStore {
  Json? data;
  @override
  Future<Json?> read() async => data;
  @override
  Future<void> write(Json tokens) async {
    data = tokens;
  }

  @override
  Future<void> clear() async {
    data = null;
  }
}

class _ConfirmedAuth extends AuthController {
  _ConfirmedAuth(this.session);
  final AuthSession session;
  @override
  AuthState build() =>
      AuthState(phase: AuthPhase.authenticated, session: session);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real gateway: login, encounter, battle and persisted account state',
    (tester) async {
      const email = String.fromEnvironment('RPG_TEST_EMAIL');
      const password = String.fromEnvironment('RPG_TEST_PASSWORD');
      expect(
        email,
        isNotEmpty,
        reason: 'Provide the isolated test account configuration.',
      );
      final api = ApiClient(
        const Environment().normalizedUrl,
        _MemoryCredentials(),
      );
      final session = await AuthRepository(api).login(email, password);
      final container = ProviderContainer(
        overrides: [
          apiProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(() => _ConfirmedAuth(session)),
        ],
      );
      addTearDown(() async {
        await api.logout();
        container.dispose();
        api.dio.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            theme: Tokens.theme(Brightness.light),
            home: const AdventureScreen(destinationId: '4b9f991fa8c7bb8f'),
          ),
        ),
      );
      Future<void> settled((String, String) scope) async {
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (!container.read(adventureProvider(scope)).busy) {
            await tester.pumpAndSettle();
            return;
          }
        }
        fail('Adventure request did not settle');
      }

      final field = (session.user.id, 'field'),
          practice = (session.user.id, 'practice');
      await settled(field);
      expect(container.read(adventureProvider(field)).failure, isNull);
      await tester.tap(find.text('Server practice'));
      await settled(practice);
      final consent = find.byKey(const Key('adventure-safety-consent'));
      await tester.scrollUntilVisible(
        consent.hitTestable(),
        250,
        maxScrolls: 40,
      );
      await tester.tap(consent);
      await tester.pumpAndSettle();
      final start = find.widgetWithText(FilledButton, 'Start test encounter');
      await tester.scrollUntilVisible(start.hitTestable(), 180);
      await tester.tap(start);
      await settled(practice);
      final p = adventureProvider(practice);
      expect(container.read(p).failure, isNull);
      expect(container.read(p).active, isTrue);
      final id = container.read(p).session!['id'];
      final strike = find.widgetWithText(OutlinedButton, 'Strike');
      await tester.scrollUntilVisible(
        strike.hitTestable(),
        -220,
        maxScrolls: 40,
      );
      await tester.tap(strike);
      await settled(practice);
      expect(container.read(p).session!['revision'], 1);
      await container.read(p.notifier).load();
      await tester.pumpAndSettle();
      expect(container.read(p).session!['id'], id);
      expect(container.read(p).session!['revision'], 1);
      // Complete the real battle; all outcomes and rewards come from the backend.
      for (var turn = 0; turn < 50 && container.read(p).active; turn++) {
        await container.read(p.notifier).move('strike');
        await tester.pumpAndSettle();
        expect(container.read(p).failure, isNull);
      }
      final result = container.read(p);
      expect(['won', 'lost', 'escaped'], contains(result.session!['status']));
      expect(
        result.snapshot!.ledger.length,
        result.session!['status'] == 'won' ? 1 : 0,
      );
      expect(result.snapshot!.party, hasLength(1));
      expect(result.snapshot!.inventory, hasLength(2));
      expect(result.snapshot!.quests.length, greaterThan(2));
      expect(result.snapshot!.history, hasLength(1));
      if (result.session!['status'] == 'won') {
        final gold = integer(result.snapshot!.profile, 'gold');
        final potions = integer(
          result.snapshot!.inventory.firstWhere(
            (i) => string(i, 'item') == 'potion',
          ),
          'quantity',
        );
        await container.read(p.notifier).manage('inventory/purchase', {
          'item': 'potion',
          'quantity': 1,
        });
        await tester.pumpAndSettle();
        expect(container.read(p).failure, isNull);
        expect(integer(container.read(p).snapshot!.profile, 'gold'), gold - 10);
        expect(
          integer(
            container
                .read(p)
                .snapshot!
                .inventory
                .firstWhere((i) => string(i, 'item') == 'potion'),
            'quantity',
          ),
          potions + 1,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
