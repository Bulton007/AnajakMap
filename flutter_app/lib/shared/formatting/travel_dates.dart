import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as data;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;
DateTime? tripTime(String value, String zone) {
  if (!_initialized) {
    data.initializeTimeZones();
    _initialized = true;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  try {
    final location = tz.getLocation(zone);
    return parsed.isUtc
        ? tz.TZDateTime.from(parsed, location)
        : tz.TZDateTime(
            location,
            parsed.year,
            parsed.month,
            parsed.day,
            parsed.hour,
            parsed.minute,
          );
  } catch (_) {
    return parsed.toUtc();
  }
}

String travelDate(String value, {String locale = 'en'}) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? '—' : DateFormat.yMMMd(locale).format(parsed);
}

String travelDateTime(
  String value, {
  String zone = 'Asia/Phnom_Penh',
  String locale = 'en',
}) {
  final date = tripTime(value, zone);
  return date == null
      ? '—'
      : '${DateFormat.yMMMd(locale).add_jm().format(date)} (${date is tz.TZDateTime ? date.timeZoneName : 'UTC'})';
}

/// Compact local dates for conversations and the notification inbox.
String conversationDay(
  String value, {
  String locale = 'en',
  String zone = 'Asia/Phnom_Penh',
  DateTime? now,
}) {
  final date = tripTime(value, zone);
  final today = tripTime(
    (now ?? DateTime.now()).toUtc().toIso8601String(),
    zone,
  );
  if (date == null || today == null) return '—';
  final day = DateTime.utc(date.year, date.month, date.day);
  final current = DateTime.utc(today.year, today.month, today.day);
  final days = current.difference(day).inDays;
  if (days == 0) return locale == 'km' ? 'ថ្ងៃនេះ' : 'Today';
  if (days == 1) return locale == 'km' ? 'ម្សិលមិញ' : 'Yesterday';
  return date.year == today.year
      ? DateFormat.MMMd(locale).format(date)
      : DateFormat.yMMMd(locale).format(date);
}

String conversationTime(
  String value, {
  String locale = 'en',
  String zone = 'Asia/Phnom_Penh',
}) {
  final date = tripTime(value, zone);
  return date == null ? '—' : DateFormat.jm(locale).format(date);
}

String inboxDateTime(
  String value, {
  String locale = 'en',
  String zone = 'Asia/Phnom_Penh',
  DateTime? now,
}) {
  if (tripTime(value, zone) == null) return '—';
  return '${conversationDay(value, locale: locale, zone: zone, now: now)} · '
      '${conversationTime(value, locale: locale, zone: zone)}';
}

String travelDateRange(String start, String end, {String locale = 'en'}) =>
    start == end
    ? travelDate(start, locale: locale)
    : '${travelDate(start, locale: locale)} – ${travelDate(end, locale: locale)}';
String travelTimeRange(
  String start,
  String end, {
  String zone = 'Asia/Phnom_Penh',
  String locale = 'en',
}) {
  final a = tripTime(start, zone), b = tripTime(end, zone);
  if (a == null || b == null) return '—';
  final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
  final result =
      '${DateFormat.MMMd(locale).format(a)} · ${DateFormat.jm(locale).format(a)} – ${sameDay ? '' : '${DateFormat.MMMd(locale).format(b)} · '}${DateFormat.jm(locale).format(b)}';
  return '$result (${a is tz.TZDateTime ? a.timeZoneName : 'UTC'})';
}
