import 'package:anajak_travel/shared/formatting/travel_dates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('km'));

  test('conversation dates use Cambodia day boundaries and local time', () {
    final now = DateTime.utc(2026, 10, 31, 18);
    expect(conversationDay('2026-10-31T17:30:00Z', now: now), 'Today');
    expect(conversationDay('2026-10-31T16:30:00Z', now: now), 'Yesterday');
    expect(conversationDay('2025-11-01T01:00:00Z', now: now), contains('2025'));
    expect(conversationTime('2026-10-31T17:30:00Z'), '12:30\u202fAM');
    expect(
      inboxDateTime('2026-10-31T17:30:00Z', now: now),
      'Today · 12:30\u202fAM',
    );
  });

  test('Khmer dates and missing timestamps have readable fallbacks', () {
    final now = DateTime.utc(2026, 10, 31, 18);
    expect(
      conversationDay('2026-10-31T17:30:00Z', locale: 'km', now: now),
      'ថ្ងៃនេះ',
    );
    expect(
      conversationDay('2026-10-31T16:30:00Z', locale: 'km', now: now),
      'ម្សិលមិញ',
    );
    expect(conversationTime('2026-10-31T17:30:00Z', locale: 'km'), isNot('—'));
    expect(inboxDateTime('invalid'), '—');
    expect(conversationTime(''), '—');
  });
}
