import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/theme/theme.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/features/authentication/auth_controller.dart';
import 'package:anajak_travel/features/authentication/auth_models.dart';
import 'package:anajak_travel/features/rpg/adventure_controller.dart';
import 'package:anajak_travel/features/rpg/adventure_repository.dart';
import 'package:anajak_travel/features/rpg/adventure_screen.dart';
import 'connected_contract_test.dart'
    show MemoryCredentials, Transport, response;

Json session([String status = 'active']) => {
  'id': 'battle-1',
  'revision': status == 'active' ? 0 : 1,
  'status': status,
  'expiresAt': DateTime.now()
      .add(const Duration(minutes: 15))
      .toUtc()
      .toIso8601String(),
  'battle': {
    'ally': {
      'speciesId': 'mossling',
      'level': 1,
      'hp': 66,
      'energy': 3,
      'poison': 0,
    },
    'enemy': {'speciesId': 'amberhorn', 'level': 1, 'hp': 30},
    'crystals': 3,
    'potions': 2,
    'log': ['Encounter started'],
  },
};

class AdventureFixture extends AdventureRepository {
  AdventureFixture()
    : super(ApiClient('http://localhost/api/v1/', MemoryCredentials()));
  Json? active;
  bool failNext = false;
  Completer<void>? gate;
  final calls = <(String, Json, String)>[];
  @override
  Future<Json> capabilities() async => {'practiceEnabled': true};
  @override
  Future<List<Json>> world(String realm) async => [
    {
      'ID': 'palace',
      'NAME': 'Royal Palace',
      'HABITAT': 'temple',
      'APPROVED': 0,
      'ACCESSIBLE': 0,
      'MIN_LEVEL': 1,
      'RADIUS_M': 100,
      'COOLDOWN_SECONDS': 300,
      'DAILY_LIMIT': 10,
    },
  ];
  @override
  Future<AdventureSnapshot> profile(String realm) async => AdventureSnapshot({
    'profile': {'XP': 0, 'GOLD': 0},
    'monsters': [
      {'ID': 'owned-1', 'SPECIES_ID': 'mossling', 'XP': 0, 'VARIATION': 2},
    ],
    'species': [
      {
        'id': 'mossling',
        'name': 'Mossling',
        'habitat': 'temple',
        'rarity': 'Common',
        'element': 'earth',
        'weight': 60,
        'hp': 60,
        'attack': 16,
        'defense': 10,
        'speed': 12,
      },
    ],
    'quests': [
      {
        'id': 'first-win',
        'completed': false,
        'claimed': false,
        'xp': 50,
        'gold': 20,
      },
    ],
    'ledger': [],
    'activeSession': active,
  });
  @override
  Future<Json> mutate(String path, Json body, String key) async {
    calls.add((path, body, key));
    if (gate != null) await gate!.future;
    if (failNext) {
      failNext = false;
      throw const ApiFailure('NETWORK', 'Connection lost');
    }
    if (path.endsWith('encounters')) {
      active = session();
      return active!;
    }
    active = null;
    return session('captured');
  }
}

class SignedIn extends AuthController {
  @override
  AuthState build() => const AuthState(
    phase: AuthPhase.authenticated,
    session: AuthSession(AuthUser({'id': 'alice'})),
  );
}

void main() {
  test(
    'account adventure is protected and destination survives authentication',
    () {
      const auth = AuthState(phase: AuthPhase.unauthenticated);
      final redirect = Uri.parse(
        authRedirect(auth, Uri.parse('/adventure?destination=palace'))!,
      );
      expect(redirect.path, '/auth');
      expect(redirect.queryParameters['from'], '/adventure?destination=palace');
      expect(
        safeAuthDestination('https://evil.example/adventure'),
        '/connected',
      );
    },
  );
  test(
    'repository uses authenticated RPG contract and preserves Oracle fields',
    () async {
      final api = ApiClient('http://localhost/api/v1/', MemoryCredentials());
      await api.acceptTokens({
        'accessToken': 'test-access',
        'refreshToken': 'test-refresh',
      });
      api.dio.httpClientAdapter = Transport((request) async {
        expect(request.path, 'rpg/practice/encounters');
        expect(request.headers['Authorization'], 'Bearer test-access');
        expect(request.headers['Idempotency-Key'], 'operation-123');
        expect(request.data['monsterId'], 'owned-1');
        return response(session());
      });
      final result = await AdventureRepository(api).mutate(
        'practice/encounters',
        {'monsterId': 'owned-1'},
        'operation-123',
      );
      expect(result['id'], 'battle-1');
    },
  );
  test(
    'duplicate submissions blocked and network replay retains key and body',
    () async {
      final repo = AdventureFixture();
      final c = ProviderContainer(
        overrides: [adventureRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      final p = adventureProvider(('alice', 'practice'));
      final sub = c.listen(p, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      final controller = c.read(p.notifier);
      repo.failNext = true;
      repo.gate = Completer<void>();
      final first = controller.start('palace', 'owned-1', true);
      await controller.start('palace', 'owned-1', true);
      expect(repo.calls, hasLength(1));
      repo.gate!.complete();
      await first;
      expect(c.read(p).pending, isTrue);
      expect(c.read(p).active, isFalse);
      await controller.retry();
      expect(repo.calls, hasLength(2));
      expect(repo.calls[0], repo.calls[1]);
      expect(c.read(p).active, isTrue);
      expect(c.read(p).pending, isFalse);
      await controller.move('capture');
      expect(c.read(p).session!['status'], 'captured');
      await controller.move('capture');
      expect(repo.calls, hasLength(3));
    },
  );
  test(
    'restores active session and requests GPS only on explicit field start',
    () async {
      final repo = AdventureFixture()..active = session();
      var gps = 0;
      final c = ProviderContainer(
        overrides: [
          adventureRepositoryProvider.overrideWithValue(repo),
          adventureLocationProvider.overrideWithValue(() async {
            gps++;
            throw const ApiFailure('GPS', 'Permission denied');
          }),
        ],
      );
      addTearDown(c.dispose);
      final p = adventureProvider(('alice', 'field'));
      final sub = c.listen(p, (_, _) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(p).active, isTrue);
      expect(gps, 0);
      repo.active = null;
      await c.read(p.notifier).load();
      await c.read(p.notifier).start('palace', 'owned-1', false);
      expect(gps, 0);
      await c.read(p.notifier).start('palace', 'owned-1', true);
      expect(gps, 1);
      expect(repo.calls, isEmpty);
      expect(c.read(p).failure!.code, 'GPS');
    },
  );
  for (final locale in ['en', 'km']) {
    for (final brightness in Brightness.values) {
      testWidgets('adventure $locale $brightness small screen 200% text', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = AdventureFixture()..active = session();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(SignedIn.new),
              adventureRepositoryProvider.overrideWithValue(repo),
            ],
            child: MaterialApp(
              theme: Tokens.theme(brightness),
              locale: Locale(locale),
              supportedLocales: const [Locale('en'), Locale('km')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: const AdventureScreen(destinationId: 'palace'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final capture = find.widgetWithText(
          OutlinedButton,
          locale == 'en' ? 'Capture' : 'ចាប់',
        );
        await tester.scrollUntilVisible(
          capture.hitTestable(),
          250,
          maxScrolls: 35,
        );
        await tester.tap(capture);
        await tester.pumpAndSettle();
        expect(repo.calls.single.$2['move'], 'capture');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
