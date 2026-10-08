import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(ref.watch(apiProvider)),
);
final authConfigurationProvider = FutureProvider(
  (ref) => ref.watch(authRepositoryProvider).configuration(),
);
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final api = ref.read(apiProvider);
    api.onSessionExpired = () {
      if (ref.mounted && !state.busy) {
        state = const AuthState(
          phase: AuthPhase.unauthenticated,
          failure: AuthFailure('authExpired'),
        );
      }
    };
    scheduleMicrotask(restore);
    return const AuthState();
  }

  Future<void> restore() async {
    if (!ref.mounted) return;
    state = const AuthState();
    final repo = ref.read(authRepositoryProvider);
    try {
      final session = await repo.restore();
      if (ref.mounted) {
        state = AuthState(
          phase: session == null
              ? AuthPhase.unauthenticated
              : AuthPhase.authenticated,
          session: session,
        );
      }
    } catch (e) {
      if (ref.mounted) {
        state = AuthState(
          phase: AuthPhase.error,
          failure: AuthFailure.from(e, AuthFlow.signIn),
        );
      }
    }
  }

  void flow(AuthFlow flow, {String? email}) {
    if (state.busy) return;
    state = AuthState(
      phase: AuthPhase.unauthenticated,
      flow: flow,
      email: email ?? state.email,
      retryAt: state.retryAt,
    );
  }

  void guest() {
    if (!state.busy) state = const AuthState(phase: AuthPhase.guest);
  }

  void acceptLink(AuthLink link) {
    if (state.busy || state.authenticated) return;
    if (AuthValidation.email(link.email) != null ||
        AuthValidation.code(link.code) != null) {
      state = AuthState(
        phase: AuthPhase.error,
        flow: link.flow,
        failure: const AuthFailure('authInvalidCode'),
      );
      return;
    }
    state = AuthState(
      phase: link.flow == AuthFlow.verify
          ? AuthPhase.verification
          : AuthPhase.resetRequired,
      flow: link.flow,
      email: link.email,
    );
  }

  Future<void> _perform(
    Future<AuthState> Function(AuthRepository repo) action,
  ) async {
    if (state.busy ||
        (state.failure?.retryAt?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    final before = state;
    final repo = ref.read(authRepositoryProvider);
    state = AuthState(
      phase: AuthPhase.loading,
      flow: before.flow,
      email: before.email,
      retryAt: before.retryAt,
    );
    try {
      final result = await action(repo);
      if (ref.mounted) state = result;
    } catch (e) {
      if (!ref.mounted) return;
      final failure = AuthFailure.from(e, before.flow);
      state = AuthState(
        phase: failure.key == 'authUnverified'
            ? AuthPhase.verification
            : AuthPhase.error,
        flow: failure.key == 'authUnverified' ? AuthFlow.verify : before.flow,
        email: before.email,
        failure: failure,
        retryAt: failure.retryAt ?? before.retryAt,
      );
    }
  }

  void rememberEmail(String email) {
    if (!state.busy) {
      state = AuthState(
        phase: state.phase,
        flow: state.flow,
        session: state.session,
        failure: state.failure,
        email: email.trim(),
        retryAt: state.retryAt,
      );
    }
  }

  DateTime? _cooldown(Json data) {
    final seconds = data['retryAfterSeconds'];
    return seconds is num
        ? DateTime.now().add(Duration(seconds: seconds.toInt()))
        : null;
  }

  Future<void> login(String email, String password) {
    rememberEmail(email);
    return _perform((repo) async {
      if (AuthValidation.email(email) != null ||
          AuthValidation.password(password) != null) {
        throw const AuthFailure('authValidation');
      }
      return AuthState(
        phase: AuthPhase.authenticated,
        session: await repo.login(email, password),
      );
    });
  }

  Future<void> register(
    String name,
    String email,
    String password,
    bool consent,
    String version,
  ) {
    rememberEmail(email);
    return _perform((repo) async {
      if (AuthValidation.name(name) != null ||
          AuthValidation.email(email) != null ||
          AuthValidation.password(password) != null ||
          !consent ||
          version.isEmpty) {
        throw const AuthFailure('authValidation');
      }
      final data = await repo.register(name, email, password, consent, version);
      return AuthState(
        phase: AuthPhase.verification,
        flow: AuthFlow.verify,
        email: email.trim(),
        retryAt: _cooldown(data),
      );
    });
  }

  Future<void> verify(String email, String code) => _perform((repo) async {
    if (AuthValidation.code(code) != null) {
      throw const AuthFailure('authCodeInvalid');
    }
    final data = await repo.verify(email, code);
    if (data['verified'] != true) throw const AuthFailure('authFailed');
    return AuthState(phase: AuthPhase.verified, email: email);
  });
  Future<void> resend(String email) async {
    if (state.retryAt?.isAfter(DateTime.now()) ?? false) return;
    await _perform((repo) async {
      final data = await repo.resend(email);
      return AuthState(
        phase: AuthPhase.verification,
        flow: AuthFlow.verify,
        email: email,
        retryAt: _cooldown(data),
      );
    });
  }

  Future<void> recover(String email) {
    rememberEmail(email);
    return _perform((repo) async {
      if (AuthValidation.email(email) != null) {
        throw const AuthFailure('authEmailInvalid');
      }
      final data = await repo.recover(email);
      return AuthState(
        phase: AuthPhase.recoverySent,
        flow: AuthFlow.reset,
        email: email,
        retryAt: _cooldown(data),
      );
    });
  }

  Future<void> reset(String email, String code, String password) =>
      _perform((repo) async {
        if (AuthValidation.password(password) != null ||
            AuthValidation.code(code) != null) {
          throw const AuthFailure('authValidation');
        }
        final data = await repo.reset(email, code, password);
        if (data['reset'] != true) throw const AuthFailure('authFailed');
        return AuthState(phase: AuthPhase.resetComplete, email: email);
      });
  Future<void> social(String provider) => _perform(
    (repo) async => AuthState(
      phase: AuthPhase.authenticated,
      session: await repo.social(provider),
    ),
  );
  Future<void> logout() async {
    if (state.busy) return;
    final repo = ref.read(authRepositoryProvider);
    state = const AuthState(phase: AuthPhase.loading);
    AuthFailure? failure;
    try {
      await repo.logout();
    } catch (_) {
      failure = const AuthFailure('authLogoutOffline');
    }
    if (ref.mounted) {
      state = AuthState(phase: AuthPhase.unauthenticated, failure: failure);
    }
  }
}

String safeAuthDestination(String? value) {
  final uri = Uri.tryParse(value ?? '');
  return uri != null &&
          !uri.hasScheme &&
          !uri.hasAuthority &&
          uri.path == '/connected' &&
          uri.fragment.isEmpty
      ? uri.toString()
      : '/connected';
}

String? authRedirect(AuthState auth, Uri uri) {
  final path = uri.path;
  if (auth.authenticated) {
    return path == '/auth' || path == '/guest'
        ? safeAuthDestination(uri.queryParameters['from'])
        : null;
  }
  if (path == '/auth') return null;
  if (path == '/guest' && auth.phase == AuthPhase.guest) return null;
  return Uri(
    path: '/auth',
    queryParameters: {'from': safeAuthDestination(uri.toString())},
  ).toString();
}
