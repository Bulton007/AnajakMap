import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/core/config/environment.dart';

void main() {
  test('custom map configuration requires HTTPS template and attribution', () {
    for (final config in [
      const Environment(
        tileUrl: 'http://tiles.example.com/{z}/{x}/{y}.png',
        tileAttribution: 'Maps',
      ),
      const Environment(tileUrl: 'https://tiles.example.com/{z}/{x}/{y}.png'),
      const Environment(
        tileUrl: 'https://tiles.example.com/map.png',
        tileAttribution: 'Maps',
      ),
    ]) {
      expect(() => config.normalizedUrl, throwsFormatException);
    }
  });
  test(
    'release refuses development defaults, demo mode and insecure gateways',
    () {
      for (final config in [
        const Environment(release: true),
        const Environment(
          release: true,
          mode: 'demo',
          apiUrl: 'https://api.example.com/api/v1',
        ),
        for (final url in [
          'http://api.example.com/api/v1',
          'https://localhost/api/v1',
          'https://127.0.0.1/api/v1',
          'https://[::1]/api/v1',
          'https://api.example.com/wrong-path',
          'https://name:password@api.example.com/api/v1',
        ])
          Environment(release: true, apiUrl: url),
      ]) {
        expect(() => config.normalizedUrl, throwsFormatException);
      }
      expect(
        const Environment(
          release: true,
          apiUrl: 'https://api.example.com/api/v1',
        ).normalizedUrl,
        'https://api.example.com/api/v1/',
      );
    },
  );
}
