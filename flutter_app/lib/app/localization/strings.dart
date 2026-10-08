import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Strings {
  const Strings(this.locale, this.values);
  final Locale locale;
  final Map<String, dynamic> values;
  String get(String key) => values[key] as String? ?? key;
  static const delegate = _StringsDelegate();
}

class _StringsDelegate extends LocalizationsDelegate<Strings> {
  const _StringsDelegate();
  static final _cache = <String, Strings>{};
  @override
  bool isSupported(Locale locale) => ['en', 'km'].contains(locale.languageCode);
  @override
  Future<Strings> load(Locale locale) {
    final cached = _cache[locale.languageCode];
    if (cached != null) {
      return SynchronousFuture(cached);
    }
    return _read(locale);
  }

  Future<Strings> _read(Locale locale) async {
    final strings = Strings(
      locale,
      jsonDecode(
            await rootBundle.loadString(
              'lib/app/localization/app_${locale.languageCode}.arb',
            ),
          )
          as Map<String, dynamic>,
    );
    _cache[locale.languageCode] = strings;
    return strings;
  }

  @override
  bool shouldReload(_StringsDelegate old) => false;
}

extension Translation on BuildContext {
  String t(String key) => Localizations.of<Strings>(this, Strings)!.get(key);
  bool get isKhmer => Localizations.localeOf(this).languageCode == 'km';
}
