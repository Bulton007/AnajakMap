import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

typedef Json = Map<String, dynamic>;
Json object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Json> objects(Object? value) =>
    value is List ? value.map(object).toList() : [];
Object? field(Json json, String key) =>
    json[key] ??
    json[key.toUpperCase()] ??
    json[key
        .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]}')
        .toUpperCase()];
String string(Json json, String key, [String fallback = '']) =>
    field(json, key)?.toString() ?? fallback;
int integer(Json json, String key) => (field(json, key) as num?)?.toInt() ?? 0;

class ApiFailure implements Exception {
  const ApiFailure(
    this.code,
    this.message, {
    this.status,
    this.traceId,
    this.retryAfterSeconds,
  });
  final String code, message;
  final int? status;
  final String? traceId;
  final int? retryAfterSeconds;
  bool get conflict => status == 409;
  bool get offline => code == 'NETWORK';
  @override
  String toString() => '$message${traceId == null ? '' : ' · $traceId'}';
}

abstract interface class CredentialStore {
  Future<Json?> read();
  Future<void> write(Json tokens);
  Future<void> clear();
}

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore(this.origin);
  final String origin;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String get key => 'anajak.session.${Uri.encodeComponent(origin)}';
  @override
  Future<Json?> read() async {
    final data = await _storage.read(key: key);
    return data == null ? null : object(jsonDecode(data));
  }

  @override
  Future<void> write(Json tokens) =>
      _storage.write(key: key, value: jsonEncode(tokens));
  @override
  Future<void> clear() => _storage.delete(key: key);
}

class ApiClient {
  ApiClient(String baseUrl, this.credentials, {Dio? transport})
    : dio =
          transport ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
            ),
          ) {
    dio.options.baseUrl = baseUrl;
  }
  final Dio dio;
  final CredentialStore credentials;
  Json? _tokens;
  Future<void>? _refreshing;
  void Function()? onSessionExpired;
  bool get authenticated => _tokens != null;
  Json? get cachedProfile =>
      _tokens?['profile'] is Map ? object(_tokens!['profile']) : null;
  Future<void> rememberProfile(Json profile) async {
    if (_tokens == null) {
      return;
    }
    _tokens = {..._tokens!, 'profile': profile};
    await credentials.write(_tokens!);
  }

  static String operationId() => const Uuid().v4();
  Future<void> restore() async {
    _tokens = await credentials.read();
  }

  Future<void> acceptTokens(Json tokens) async {
    if (tokens['accessToken'] is! String || tokens['refreshToken'] is! String) {
      throw const ApiFailure('CONTRACT', 'Invalid authentication response');
    }
    await credentials.write(tokens);
    _tokens = tokens;
  }

  Future<void> clearSession() async {
    _tokens = null;
    await credentials.clear();
    onSessionExpired?.call();
  }

  Future<void> _refresh() async {
    try {
      final refresh = _tokens?['refreshToken'];
      if (refresh == null) {
        throw const ApiFailure('SESSION', 'Please sign in again.');
      }
      final response = await dio.post<Object?>(
        'auth/refresh',
        data: {'refreshToken': refresh},
      );
      final profile = cachedProfile;
      await acceptTokens({
        ...object(object(response.data)['data']),
        'profile': ?profile,
      });
    } on DioException catch (e) {
      if ([400, 401, 403].contains(e.response?.statusCode)) {
        await clearSession();
      }
      throw _failure(e);
    }
  }

  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Json? query,
    String? key,
    CancelToken? cancel,
    ProgressCallback? progress,
    bool auth = true,
    bool binary = false,
  }) async {
    Future<Response<Object?>> send() => dio.request<Object?>(
      path.replaceFirst(RegExp(r'^/+'), ''),
      data: body,
      queryParameters: query,
      cancelToken: cancel,
      onSendProgress: progress,
      options: Options(
        method: method,
        responseType: binary ? ResponseType.bytes : ResponseType.json,
        headers: {
          if (auth && _tokens != null)
            'Authorization': 'Bearer ${_tokens!['accessToken']}',
          'Idempotency-Key': ?key,
        },
      ),
    );
    try {
      Response<Object?> response;
      try {
        response = await send();
      } on DioException catch (e) {
        if (e.response?.statusCode != 401 || !auth || _tokens == null) {
          rethrow;
        }
        _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
        await _refreshing;
        if (body is FormData) {
          throw const ApiFailure(
            'UPLOAD_RETRY',
            'Session renewed. Select the file again to retry the upload.',
          );
        }
        response = await send();
      }
      if (binary) {
        return Uint8List.fromList((response.data as List).cast<int>());
      }
      if (response.statusCode == 204 ||
          response.data == null ||
          response.data == '') {
        return null;
      }
      final envelope = object(response.data);
      if (!envelope.containsKey('data')) {
        throw const ApiFailure(
          'CONTRACT',
          'The server returned an unexpected response.',
        );
      }
      return envelope['data'];
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  ApiFailure _failure(DioException e) {
    final data = object(e.response?.data);
    final status = e.response?.statusCode;
    return ApiFailure(
      string(
        data,
        'code',
        e.type == DioExceptionType.cancel
            ? 'CANCELLED'
            : status == null
            ? 'NETWORK'
            : 'HTTP',
      ),
      string(
        data,
        'message',
        status == null
            ? 'Cannot reach the server. Check your connection and retry.'
            : 'Request failed ($status).',
      ),
      status: status,
      traceId: data['traceId'] as String?,
      retryAfterSeconds: int.tryParse(
        e.response?.headers.value('retry-after') ?? '',
      ),
    );
  }

  Future<void> logout() async {
    try {
      if (_tokens != null) {
        await request(
          'POST',
          'auth/logout',
          body: {'refreshToken': _tokens!['refreshToken']},
          auth: false,
        );
      }
    } finally {
      // Device sign-out must work even when server-side revocation is unreachable.
      await clearSession();
    }
  }
}
