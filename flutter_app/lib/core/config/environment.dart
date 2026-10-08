class Environment {
  const Environment({
    this.mode = const String.fromEnvironment(
      'APP_MODE',
      defaultValue: 'connected',
    ),
    this.apiUrl = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8080/api/v1/',
    ),
    this.tileUrl = const String.fromEnvironment('MAP_TILE_URL'),
    this.tileAttribution = const String.fromEnvironment('MAP_ATTRIBUTION'),
  });
  final String mode, apiUrl, tileUrl, tileAttribution;
  bool get connected => mode == 'connected';
  String get normalizedUrl {
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
    if (uri.scheme != 'https' && !local) {
      throw const FormatException(
        'HTTPS is required outside localhost and the Android emulator.',
      );
    }
    return '${apiUrl.replaceFirst(RegExp(r'/+$'), '')}/';
  }
}
