import '../../core/network/api_client.dart';

class ServerTrip {
  ServerTrip.fromJson(Json json)
    : id = string(json, 'id'),
      title = string(json, 'title'),
      destination = string(json, 'destination'),
      timezone = string(json, 'timezone'),
      startDate = string(json, 'startDate'),
      endDate = string(json, 'endDate'),
      version = integer(json, 'version');
  final String id, title, destination, timezone, startDate, endDate;
  final int version;
  Json get editable => {
    'title': title,
    'destination': destination,
    'timezone': timezone,
    'startDate': startDate,
    'endDate': endDate,
  };
  Json toJson() => {'id': id, ...editable, 'version': version};
}

class ServerActivity {
  ServerActivity.fromJson(Json json)
    : id = string(json, 'id'),
      title = string(json, 'title'),
      startsAt = string(json, 'startsAt'),
      endsAt = string(json, 'endsAt'),
      source = string(json, 'source'),
      latitude = (field(json, 'latitude') as num?)?.toDouble(),
      longitude = (field(json, 'longitude') as num?)?.toDouble();
  final String id, title, startsAt, endsAt, source;
  final double? latitude, longitude;
  Json toDraft() => {
    'title': title,
    'startsAt': startsAt,
    'endsAt': endsAt,
    'latitude': latitude,
    'longitude': longitude,
    'source': source,
  };
}

class GenerationJob {
  GenerationJob.fromJson(Json json)
    : id = string(object(json['job']), 'id'),
      tripId = string(object(json['job']), 'tripId'),
      status = string(object(json['job']), 'status'),
      error = string(object(json['job']), 'errorCode'),
      retryAt = string(object(json['job']), 'retryAt'),
      result = Map.unmodifiable(object(json['result']));
  final String id, tripId, status, error, retryAt;
  final Json result;
  bool get finished => status == 'SUCCEEDED' || status == 'FAILED';
  List<ServerActivity> get activities =>
      objects(result['activities']).map(ServerActivity.fromJson).toList();
}

String decimalAmount(String value) {
  if (!RegExp(r'^\d{1,12}(\.\d{1,2})?$').hasMatch(value.trim())) {
    throw const FormatException(
      'Enter a positive amount with up to two decimal places.',
    );
  }
  final parts = value.trim().split('.');
  final cents =
      BigInt.parse(parts.first) * BigInt.from(100) +
      BigInt.parse(parts.length == 1 ? '0' : parts.last.padRight(2, '0'));
  if (cents <= BigInt.zero) {
    throw const FormatException('Amount must be greater than zero.');
  }
  return '${cents ~/ BigInt.from(100)}.${(cents % BigInt.from(100)).toString().padLeft(2, '0')}';
}
