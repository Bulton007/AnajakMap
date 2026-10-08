import 'dart:convert';
import '../../core/network/api_client.dart';

enum AuthPhase {
  restoring,
  unauthenticated,
  loading,
  verification,
  verified,
  recoverySent,
  resetRequired,
  resetComplete,
  authenticated,
  guest,
  error,
}

enum AuthFlow { signIn, register, forgot, reset, verify }

class AuthUser {
  const AuthUser(this.profile);
  final Json profile;
  String get id => string(profile, 'id');
  String get email => string(profile, 'email');
  String get name => string(profile, 'name');
}

class AuthSession {
  const AuthSession(this.user, {this.offline = false});
  final AuthUser user;
  final bool offline;
}

class AuthFailure implements Exception {
  const AuthFailure(this.key, {this.retryAt});
  final String key;
  final DateTime? retryAt;
  factory AuthFailure.from(Object error, AuthFlow flow) {
    if (error is AuthFailure) return error;
    if (error is ApiFailure) {
      final key = error.code == 'CANCELLED'
          ? 'authCancelled'
          : error.offline
          ? 'authNetwork'
          : error.status == 429
          ? 'authRateLimit'
          : error.message == 'EMAIL_UNVERIFIED'
          ? 'authUnverified'
          : error.status == 503
          ? 'authUnavailable'
          : flow == AuthFlow.verify || flow == AuthFlow.reset
          ? 'authInvalidCode'
          : error.status == 401
          ? 'authInvalidCredentials'
          : error.status == 409
          ? 'authRegistrationFailed'
          : 'authFailed';
      return AuthFailure(
        key,
        retryAt: error.retryAfterSeconds == null
            ? null
            : DateTime.now().add(Duration(seconds: error.retryAfterSeconds!)),
      );
    }
    return const AuthFailure('authFailed');
  }
}

class AuthState {
  const AuthState({
    this.phase = AuthPhase.restoring,
    this.flow = AuthFlow.signIn,
    this.session,
    this.failure,
    this.email = '',
    this.retryAt,
  });
  final AuthPhase phase;
  final AuthFlow flow;
  final AuthSession? session;
  final AuthFailure? failure;
  final String email;
  final DateTime? retryAt;
  bool get busy => phase == AuthPhase.loading || phase == AuthPhase.restoring;
  bool get authenticated => phase == AuthPhase.authenticated && session != null;
}

class AuthConfiguration {
  const AuthConfiguration(this.data);
  final Json data;
  bool get emailDelivery => data['emailDelivery'] == true;
  bool get registration => data['registration'] == true && legalReady;
  String get policyVersion => string(data, 'policyVersion');
  Uri? legal(String key) {
    final uri = Uri.tryParse(string(data, key));
    return uri?.scheme == 'https' &&
            uri!.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  bool get legalReady =>
      legal('termsUrl') != null &&
      legal('privacyUrl') != null &&
      policyVersion.isNotEmpty;
}

abstract final class AuthValidation {
  static String? email(String? value) =>
      value != null &&
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? null
      : 'authEmailInvalid';
  static String? password(String? value) =>
      value != null &&
          value.length >= 12 &&
          value.length <= 72 &&
          utf8.encode(value).length <= 72 &&
          value.trim().isNotEmpty
      ? null
      : 'authPasswordRule';
  static String? name(String? value) =>
      value != null && value.trim().isNotEmpty && value.trim().length <= 120
      ? null
      : 'authNameInvalid';
  static String? code(String? value) =>
      value != null && RegExp(r'^\d{6}$').hasMatch(value.trim())
      ? null
      : 'authCodeInvalid';
}

/// Only accepts links from the explicitly configured HTTPS origin and path.
class AuthLink {
  const AuthLink(this.flow, this.email, this.code);
  final AuthFlow flow;
  final String email, code;
  static AuthLink? parse(Uri uri, String configuredBase) {
    final base = Uri.tryParse(configuredBase);
    if (base == null ||
        uri.scheme != 'https' ||
        !uri.hasAuthority ||
        base.scheme != 'https' ||
        uri.origin != base.origin ||
        uri.path != base.path) {
      return null;
    }
    final fragment = Uri.tryParse(uri.fragment);
    if (fragment == null || !['verify', 'reset'].contains(fragment.path)) {
      return null;
    }
    final email = fragment.queryParameters['email'] ?? '';
    final code = fragment.queryParameters['code'] ?? '';
    if (AuthValidation.email(email) != null ||
        AuthValidation.code(code) != null) {
      return null;
    }
    return AuthLink(
      fragment.path == 'verify' ? AuthFlow.verify : AuthFlow.reset,
      email,
      code,
    );
  }
}
