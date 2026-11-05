import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class MapLocationIssue implements Exception {
  const MapLocationIssue(this.kind);
  final String kind;
}

Position validatedMapPosition(Position value, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(value.timestamp);
  if (!value.latitude.isFinite ||
      !value.longitude.isFinite ||
      value.latitude.abs() > 90 ||
      value.longitude.abs() > 180 ||
      !value.accuracy.isFinite ||
      value.accuracy < 0) {
    throw const MapLocationIssue('invalid');
  }
  if (age > const Duration(minutes: 2) || age < const Duration(minutes: -1)) {
    throw const MapLocationIssue('stale');
  }
  if (value.accuracy > 1000) throw const MapLocationIssue('accuracy');
  return value;
}

abstract class MapLocationAccess {
  Future<Position> current({bool requestPermission = true});
  Stream<Position> watch();
  Future<bool> settings(bool service);
}

final mapLocationProvider = Provider<MapLocationAccess>(
  (ref) => _DeviceLocation(),
);
// GPS journeys must not require enrolling in an optional network-location service.
LocationSettings journeyGpsSettings({Duration? timeLimit}) =>
    defaultTargetPlatform == TargetPlatform.android
    ? AndroidSettings(
        forceLocationManager: true,
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        timeLimit: timeLimit,
      )
    : LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        timeLimit: timeLimit,
      );

final gpsLocationProvider = Provider<MapLocationAccess>(
  (ref) => _DeviceLocation(gpsOnly: true),
);

class _DeviceLocation implements MapLocationAccess {
  _DeviceLocation({this.gpsOnly = false});
  final bool gpsOnly;
  @override
  Future<Position> current({bool requestPermission = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const MapLocationIssue('service');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const MapLocationIssue('settings');
    }
    if (permission == LocationPermission.denied) {
      throw const MapLocationIssue('denied');
    }
    return validatedMapPosition(
      await Geolocator.getCurrentPosition(
        locationSettings: gpsOnly
            ? journeyGpsSettings(timeLimit: const Duration(seconds: 20))
            : const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 20),
              ),
      ),
    );
  }

  @override
  Stream<Position> watch() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25,
    ),
  );
  @override
  Future<bool> settings(bool service) => service
      ? Geolocator.openLocationSettings()
      : Geolocator.openAppSettings();
}
