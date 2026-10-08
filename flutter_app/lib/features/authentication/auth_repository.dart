import '../../core/network/api_client.dart';
import 'auth_models.dart';

class AuthRepository {
  AuthRepository(this.api);
  final ApiClient api;
  Future<AuthConfiguration> configuration() async => AuthConfiguration(
    object(await api.request('GET', 'auth/config', auth: false)),
  );
  Future<Json> _post(String operation, Json body) async => object(
    await api.request('POST', 'auth/$operation', body: body, auth: false),
  );
  Future<AuthUser> currentUser() async =>
      AuthUser(object(await api.request('GET', 'profile')));
  Future<AuthSession?> restore() async {
    await api.restore();
    if (!api.authenticated) return null;
    try {
      final user = await currentUser();
      await api.rememberProfile(user.profile);
      return AuthSession(user);
    } on ApiFailure catch (error) {
      if (error.offline && api.cachedProfile != null) {
        return AuthSession(AuthUser(api.cachedProfile!), offline: true);
      }
      if ([400, 401, 403].contains(error.status)) {
        await api.clearSession();
        throw const AuthFailure('authExpired');
      }
      rethrow;
    }
  }

  Future<AuthSession> login(String email, String password) async {
    final tokens = await _post('login', {
      'email': email.trim(),
      'password': password,
    });
    await api.acceptTokens(tokens);
    try {
      final user = await currentUser();
      await api.rememberProfile(user.profile);
      return AuthSession(user);
    } catch (_) {
      await api.clearSession();
      rethrow;
    }
  }

  Future<Json> register(
    String name,
    String email,
    String password,
    bool consent,
    String version,
  ) => _post('register', {
    'name': name.trim(),
    'email': email.trim(),
    'password': password,
    'legalConsent': consent,
    'policyVersion': version,
  });
  Future<Json> verify(String email, String code) =>
      _post('verify', {'email': email.trim(), 'code': code.trim()});
  Future<Json> resend(String email) =>
      _post('resend-verification', {'email': email.trim()});
  Future<Json> recover(String email) =>
      _post('forgot-password', {'email': email.trim()});
  Future<Json> reset(String email, String code, String password) => _post(
    'reset-password',
    {'email': email.trim(), 'code': code.trim(), 'password': password},
  );
  Future<void> logout() => api.logout();
  // No provider exchange endpoint exists. Never accept a provider token as an app session.
  Future<AuthSession> social(String provider) async =>
      throw const AuthFailure('authProviderUnavailable');
}
