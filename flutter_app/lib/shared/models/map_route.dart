import 'package:latlong2/latlong.dart';
import '../../core/network/api_client.dart';

class MapRoute {
  const MapRoute(this.points, this.meters, this.seconds, this.source);
  final List<LatLng> points;
  final double meters, seconds;
  final String source;
  factory MapRoute.fromJson(Json data) {
    final meters = data['distanceMeters'], seconds = data['durationSeconds'];
    if (meters is! num ||
        seconds is! num ||
        !meters.isFinite ||
        !seconds.isFinite ||
        meters < 0 ||
        seconds < 0) {
      throw const FormatException('Invalid route estimates');
    }
    final points = <LatLng>[];
    for (final point in data['coordinates'] as List? ?? []) {
      if (point is! List ||
          point.length < 2 ||
          point[0] is! num ||
          point[1] is! num) {
        throw const FormatException('Invalid route geometry');
      }
      final lon = (point[0] as num).toDouble(),
          lat = (point[1] as num).toDouble();
      if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
        throw const FormatException('Invalid route coordinates');
      }
      points.add(LatLng(lat, lon));
    }
    if (points.length < 2 || points.length > 50000) {
      throw const FormatException('Missing route geometry');
    }
    return MapRoute(
      points,
      meters.toDouble(),
      seconds.toDouble(),
      string(data, 'source'),
    );
  }
}
