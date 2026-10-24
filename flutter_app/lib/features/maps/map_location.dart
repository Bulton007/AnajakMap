import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class MapLocationIssue implements Exception {
  const MapLocationIssue(this.kind);
  final String kind;
}

abstract class MapLocationAccess {
  Future<Position> current({bool requestPermission = true});
  Stream<Position> watch();
  Future<bool> settings(bool service);
}

final mapLocationProvider = Provider<MapLocationAccess>(
  (ref) => _DeviceLocation(),
);

class _DeviceLocation implements MapLocationAccess {
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
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
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
