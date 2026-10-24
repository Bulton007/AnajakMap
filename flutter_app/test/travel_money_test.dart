import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/shared/formatting/travel_money.dart';

void main() {
  test('money display uses exact decimal rounding without binary floats', () {
    expect(travelMoney('123456789012.345', 'USD'), '123,456,789,012.35 USD');
    expect(travelMoney('4000.49', 'KHR'), '4,000 KHR');
    expect(travelMoney('4000.50', 'KHR'), '4,001 KHR');
    expect(travelMoney('-12.345', 'USD'), '-12.35 USD');
    expect(travelMoney('not-money', 'USD'), '— USD');
  });
  test('readable account IDs never replace the original identifier', () {
    const original = '12345678-1234-1234-1234-abcdef123456';
    expect(readableAccountId(original), '12345678…3456');
    expect(original, '12345678-1234-1234-1234-abcdef123456');
  });
}
