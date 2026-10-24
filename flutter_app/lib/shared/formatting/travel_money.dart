import 'package:intl/intl.dart';

/// Exact decimal display only: never changes balances or API payloads.
String travelMoney(Object? value, String currency, {String locale = 'en'}) {
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch('$value');
  if (match == null) return '— $currency';
  final scale = currency == 'KHR' ? 0 : 2;
  final fraction = match[3] ?? '';
  final factor = BigInt.from(10).pow(scale);
  var units = BigInt.parse(match[2]!) * factor;
  if (scale > 0) {
    units += BigInt.parse(fraction.padRight(scale, '0').substring(0, scale));
  }
  if (fraction.length > scale && int.parse(fraction[scale]) >= 5) {
    units += BigInt.one;
  }
  final symbols = NumberFormat.decimalPattern(locale).symbols;
  final whole = (units ~/ factor).toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}${symbols.GROUP_SEP}',
  );
  final decimal = scale == 0
      ? ''
      : '${symbols.DECIMAL_SEP}${(units % factor).toString().padLeft(scale, '0')}';
  return '${match[1] == '-' && units != BigInt.zero ? '-' : ''}$whole$decimal $currency';
}

String readableAccountId(String id) => id.length > 16
    ? '${id.substring(0, 8).toUpperCase()}…${id.substring(id.length - 4).toUpperCase()}'
    : id;
