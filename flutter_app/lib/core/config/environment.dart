import 'package:flutter/foundation.dart';

class Environment {
  const Environment({
    this.mode = const String.fromEnvironment(
      'APP_MODE',
      defaultValue: 'connected',
    ),
    String apiUrl = const String.fromEnvironment('API_BASE_URL'),
    this.tileUrl = const String.fromEnvironment('MAP_TILE_URL'),
    this.tileAttribution = const String.fromEnvironment('MAP_ATTRIBUTION'),
    this.release = kReleaseMode,
  }) : _configuredApiUrl = apiUrl;
  final String mode, _configuredApiUrl, tileUrl, tileAttribution;
  final bool release;
  String get apiUrl {
    if (_configuredApiUrl.isNotEmpty) return _configuredApiUrl;
    // Android emulator localhost belongs to the emulator, not the host PC.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api/v1/';
    }
    return 'http://localhost:8080/api/v1/';
  }

  bool get connected => mode == 'connected';
  String get normalizedUrl {
    if (release && (mode != 'connected' || _configuredApiUrl.isEmpty)) {
      throw const FormatException(
        'Release builds require connected mode and an explicit HTTPS API_BASE_URL.',
      );
    }
    final uri = Uri.tryParse(apiUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Configure API_BASE_URL with your gateway URL ending in /api/v1.',
      );
    }
    final local = ['localhost', '127.0.0.1', '10.0.2.2'].contains(uri.host);
    if (release &&
        (uri.scheme != 'https' ||
            local ||
            uri.host == '::1' ||
            uri.host.contains('_') ||
            uri.host.toLowerCase().contains('replace') ||
            uri.path.replaceFirst(RegExp(r'/+$'), '') != '/api/v1')) {
      throw const FormatException(
        'Release builds require an HTTPS gateway ending in /api/v1.',
      );
    }
    if (tileUrl.isNotEmpty &&
        (!tileUrl.startsWith('https://') ||
            !tileUrl.contains('{z}') ||
            !tileUrl.contains('{x}') ||
            !tileUrl.contains('{y}') ||
            tileAttribution.trim().isEmpty)) {
      throw const FormatException(
        'Custom maps require an HTTPS tile template with {z}/{x}/{y} and MAP_ATTRIBUTION.',
      );
    }
    if (uri.scheme != 'https' && !local) {
      throw const FormatException(
        'HTTPS is required outside localhost and the Android emulator.',
      );
    }
    return '${apiUrl.replaceFirst(RegExp(r'/+$'), '')}/';
  }
}
