import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/app/app.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/features/authentication/auth_controller.dart';
import 'package:anajak_travel/features/authentication/auth_components.dart';
import 'package:anajak_travel/features/authentication/auth_models.dart';
import 'package:anajak_travel/features/authentication/auth_repository.dart';
import 'connected_contract_test.dart'
    show MemoryCredentials, Transport, response;
import 'ui_test.dart' show launch;

const config = {
  'emailDelivery': true,
  'registration': true,
  'termsUrl': 'https://example.test/terms',
  'privacyUrl': 'https://example.test/privacy',
  'policyVersion': 'v1',
  'google': false,
  'apple': false,
};

class ControlledAuth extends AuthRepository {
  ControlledAuth(super.api);
  int calls = 0;
  Completer<AuthSession>? loginResult;
  Object? failure;
  @override
  Future<AuthSession?> restore() async => null;
  @override
  Future<AuthSession> login(String email, String password) async {
    calls++;
    if (failure != null) throw failure!;
    return loginResult!.future;
  }

  @override
  Future<Json> register(
    String name,
    String email,
    String password,
    bool consent,
    String version,
  ) async => {'retryAfterSeconds': 60};
  @override
  Future<Json> verify(String email, String code) async => {'verified': true};
  @override
  Future<Json> recover(String email) async => {
    'delivery': 'generic',
    'retryAfterSeconds': 60,
  };
  @override
  Future<Json> reset(String email, String code, String password) async {
    if (failure != null) throw failure!;
    return {'reset': true};
  }

  @override
  Future<AuthSession> social(String provider) async =>
      throw const ApiFailure('CANCELLED', 'cancelled');
}

void main() {
  test(
    'backend password byte limit handles Khmer; required name/email/code',
    () {
      expect(AuthValidation.password('LongPassword!2026'), isNull);
      expect(AuthValidation.password('short'), isNotNull);
      expect(AuthValidation.password(List.filled(25, 'ក').join()), isNotNull);
      expect(AuthValidation.password(List.filled(24, 'ក').join()), isNull);
      expect(AuthValidation.email(' a@example.com '), isNull);
      expect(AuthValidation.email('bad@'), isNotNull);
      expect(AuthValidation.name('  '), isNotNull);
      expect(AuthValidation.code('123456'), isNull);
      expect(AuthValidation.code('12345a'), isNotNull);
    },
  );
  test('guards preserve safe destination and restrict guests', () {
    const guest = AuthState(phase: AuthPhase.guest);
    expect(authRedirect(guest, Uri.parse('/guest')), isNull);
    expect(
      authRedirect(guest, Uri.parse('/connected?tab=trips')),
      '/auth?from=%2Fconnected%3Ftab%3Dtrips',
    );
    expect(safeAuthDestination('//evil.test'), '/connected');
    expect(safeAuthDestination('https://evil.test'), '/connected');
    expect(safeAuthDestination('/connected?tab=trips'), '/connected?tab=trips');
    final signedIn = AuthState(
      phase: AuthPhase.authenticated,
      session: AuthSession(AuthUser({'id': 'a'})),
    );
    expect(
      authRedirect(
        signedIn,
        Uri.parse('/auth?from=%2Fconnected%3Ftab%3Dtrips'),
      ),
      '/connected?tab=trips',
    );
  });
  test('only configured HTTPS fragment links are accepted', () {
    const base = 'https://travel.example/auth/link';
    expect(
      AuthLink.parse(
        Uri.parse('$base#reset?email=a%40b.com&code=123456'),
        base,
      )?.flow,
      AuthFlow.reset,
    );
    expect(
      AuthLink.parse(
        Uri.parse(
          'https://evil.example/auth/link#reset?email=a%40b.com&code=123456',
        ),
        base,
      ),
      isNull,
    );
    expect(
      AuthLink.parse(Uri.parse('$base#reset?email=a%40b.com&code=wrong'), base),
      isNull,
    );
  });
  test(
    'restoration rejects revoked refresh and clears secure credentials',
    () async {
      final store = MemoryCredentials()
        ..value = {'accessToken': 'expired', 'refreshToken': 'revoked'};
      final dio = Dio()
        ..httpClientAdapter = Transport(
          (r) async => response({'message': 'Expired'}, status: 401),
        );
      final repo = AuthRepository(
        ApiClient('https://test/api/v1/', store, transport: dio),
      );
      await expectLater(
        repo.restore(),
        throwsA(isA<AuthFailure>().having((e) => e.key, 'key', 'authExpired')),
      );
      expect(store.value, isNull);
    },
  );
  test(
    'offline restoration uses only previously cached account; login never succeeds offline',
    () async {
      final store = MemoryCredentials()
        ..value = {
          'accessToken': 'token',
          'refreshToken': 'refresh',
          'profile': {'id': 'account'},
        };
      final dio = Dio()
        ..httpClientAdapter = Transport(
          (r) async => throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
          ),
        );
      final repo = AuthRepository(
        ApiClient('https://test/api/v1/', store, transport: dio),
      );
      expect((await repo.restore())!.offline, true);
      await expectLater(
        repo.login('a@example.com', 'PasswordLong!2026'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test('Retry-After preserved from backend response', () async {
    final dio = Dio()
      ..httpClientAdapter = Transport(
        (r) async => ResponseBody.fromString(
          jsonEncode({'message': 'Rate limit exceeded'}),
          429,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
            'retry-after': ['42'],
          },
        ),
      );
    final api = ApiClient(
      'https://test/api/v1/',
      MemoryCredentials(),
      transport: dio,
    );
    await expectLater(
      api.request('POST', 'auth/login', auth: false),
      throwsA(
        isA<ApiFailure>().having((e) => e.retryAfterSeconds, 'retry', 42),
      ),
    );
  });

  late ProviderContainer container;
  late ControlledAuth repo;
  Future<AuthController> controller() async {
    final api = ApiClient('https://test/api/v1/', MemoryCredentials());
    repo = ControlledAuth(api);
    container = ProviderContainer(
      overrides: [
        apiProvider.overrideWithValue(api),
        authRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(authControllerProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    return controller;
  }

  test(
    'duplicate submits only send one login; no success before confirmation',
    () async {
      final auth = await controller();
      repo.loginResult = Completer<AuthSession>();
      final pending = auth.login('a@example.com', 'PasswordLong!2026');
      await auth.login('a@example.com', 'PasswordLong!2026');
      expect(repo.calls, 1);
      expect(container.read(authControllerProvider).phase, AuthPhase.loading);
      repo.loginResult!.complete(AuthSession(AuthUser({'id': 'user'})));
      await pending;
      expect(container.read(authControllerProvider).authenticated, true);
    },
  );
  test('provider cancellation remains unauthenticated', () async {
    final auth = await controller();
    await auth.social('google');
    final state = container.read(authControllerProvider);
    expect(state.authenticated, false);
    expect(state.failure!.key, 'authCancelled');
  });
  test(
    'malformed trusted link exposes recovery without authentication',
    () async {
      final auth = await controller();
      auth.acceptLink(const AuthLink(AuthFlow.reset, '', ''));
      expect(
        container.read(authControllerProvider).failure!.key,
        'authInvalidCode',
      );
      expect(container.read(authControllerProvider).authenticated, false);
    },
  );
  test(
    'registration requires consent; verification never auto signs in',
    () async {
      final auth = await controller();
      auth.flow(AuthFlow.register);
      await auth.register(
        'Name',
        'a@example.com',
        'PasswordLong!2026',
        false,
        'v1',
      );
      expect(container.read(authControllerProvider).phase, AuthPhase.error);
      await auth.register(
        'Name',
        'a@example.com',
        'PasswordLong!2026',
        true,
        'v1',
      );
      expect(
        container.read(authControllerProvider).phase,
        AuthPhase.verification,
      );
      await auth.verify('a@example.com', '123456');
      expect(container.read(authControllerProvider).phase, AuthPhase.verified);
      expect(container.read(authControllerProvider).authenticated, false);
    },
  );
  test('recovery acknowledgement and invalid/expired reset states', () async {
    final auth = await controller();
    auth.flow(AuthFlow.forgot);
    await auth.recover('a@example.com');
    expect(
      container.read(authControllerProvider).phase,
      AuthPhase.recoverySent,
    );
    repo.failure = const ApiFailure(
      'INVALID',
      'Invalid or expired code',
      status: 400,
    );
    await auth.reset('a@example.com', '123456', 'PasswordLong!2026');
    expect(
      container.read(authControllerProvider).failure!.key,
      'authInvalidCode',
    );
    repo.failure = null;
    await auth.reset('a@example.com', '123456', 'PasswordLong!2026');
    expect(
      container.read(authControllerProvider).phase,
      AuthPhase.resetComplete,
    );
    expect(container.read(authControllerProvider).authenticated, false);
  });
  for (final refreshByResume in [false, true]) {
    testWidgets(
      'registration refreshes server availability ${refreshByResume ? 'on resume' : 'on request'} without losing inputs',
      (tester) async {
        var available = false;
        var requests = 0;
        final dio = Dio()
          ..httpClientAdapter = Transport((r) async {
            requests++;
            return response({
              ...config,
              'emailDelivery': available,
              'registration': available,
            });
          });
        final container = await launch(
          tester,
          route: '/auth',
          environment: const Environment(),
          api: ApiClient(
            'https://test/api/v1/',
            MemoryCredentials(),
            transport: dio,
          ),
        );
        container.read(authControllerProvider.notifier).flow(AuthFlow.register);
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.enterText(fields.at(0), 'Traveler');
        await tester.enterText(fields.at(1), 'traveler@example.test');
        expect(
          container.read(authConfigurationProvider).requireValue.registration,
          false,
        );
        final before = requests;
        available = true;
        if (refreshByResume) {
          for (final lifecycle in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(lifecycle);
          }
        } else {
          await tester.ensureVisible(find.text('Check again'));
          await tester.tap(find.text('Check again'));
        }
        await tester.pumpAndSettle();
        expect(requests, greaterThan(before));
        expect(
          container.read(authConfigurationProvider).requireValue.registration,
          true,
        );
        expect(find.text('Check again'), findsNothing);
        expect(find.text('Traveler'), findsOneWidget);
        expect(find.text('traveler@example.test'), findsOneWidget);
        expect(container.read(authControllerProvider).authenticated, false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final locale in ['en', 'km']) {
    testWidgets(
      'registration $locale keeps consent explicit and fields reachable',
      (tester) async {
        final dio = Dio()
          ..httpClientAdapter = Transport((r) async => response(config));
        final container = await launch(
          tester,
          route: '/auth',
          locale: locale,
          size: const Size(320, 640),
          scale: 2,
          environment: const Environment(),
          api: ApiClient(
            'https://test/api/v1/',
            MemoryCredentials(),
            transport: dio,
          ),
        );
        container.read(authControllerProvider.notifier).flow(AuthFlow.register);
        await tester.pumpAndSettle();
        expect(find.byType(TextFormField), findsNWidgets(3));
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          false,
        );
        final button = find.descendant(
          of: find.byType(AuthPrimaryButton),
          matching: find.byType(FilledButton),
        );
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets(
        'auth $locale ${theme.name} large text small screen keyboard',
        (tester) async {
          final dio = Dio()
            ..httpClientAdapter = Transport((r) async => response(config));
          await launch(
            tester,
            route: '/auth',
            locale: locale,
            theme: theme,
            size: const Size(320, 640),
            scale: 2,
            environment: const Environment(),
            api: ApiClient(
              'https://test/api/v1/',
              MemoryCredentials(),
              transport: dio,
            ),
          );
          expect(find.byType(NavigationBar), findsNothing);
          expect(find.byType(AuthModeSelector), findsOneWidget);
          final field = find.byType(TextFormField).first;
          await tester.ensureVisible(field);
          await tester.tap(field);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.byType(AuthPrimaryButton));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
      testWidgets('auth $locale ${theme.name} golden', (tester) async {
        final dio = Dio()
          ..httpClientAdapter = Transport((r) async => response(config));
        await launch(
          tester,
          route: '/auth',
          locale: locale,
          theme: theme,
          environment: const Environment(),
          api: ApiClient(
            'https://test/api/v1/',
            MemoryCredentials(),
            transport: dio,
          ),
        );
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(AnajakApp),
          matchesGoldenFile('goldens/auth_${locale}_${theme.name}.png'),
        );
      });
    }
  }
}
