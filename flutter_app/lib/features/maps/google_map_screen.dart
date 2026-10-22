import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

final mapsConfiguredProvider = FutureProvider<bool>((ref) async {
  if (kIsWeb ||
      ![
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform)) {
    return false;
  }
  try {
    return await const MethodChannel(
          'anajak/maps_config',
        ).invokeMethod<bool>('configured') ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
});

class MapPlace {
  const MapPlace(this.id, this.name, this.latitude, this.longitude);
  final String id, name;
  final double latitude, longitude;
  bool get valid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

class GoogleMapScreen extends StatelessWidget {
  const GoogleMapScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Google Maps')),
    body: const SafeArea(child: TravelGoogleMap()),
  );
}

class TravelGoogleMap extends ConsumerWidget {
  const TravelGoogleMap({
    super.key,
    this.places = const [],
    this.onPlaceSelected,
  });
  final List<MapPlace> places;
  final ValueChanged<MapPlace>? onPlaceSelected;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final km = Localizations.localeOf(context).languageCode == 'km';
    Widget unavailable() => Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              km ? 'Google Maps មិនទាន់បានកំណត់' : 'Google Maps needs setup',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              km
                  ? 'ត្រូវការសោ Google Maps សម្រាប់ Android ឬ iOS។ ផែនទីពិតមិនទាន់អាចបង្ហាញបានទេ។'
                  : 'A Google Maps key for Android or iOS is required. Live maps are not available in this build.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
    return ref
        .watch(mapsConfiguredProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => unavailable(),
          data: (configured) {
            if (!configured) return unavailable();
            final valid = places.where((p) => p.valid).toList();
            return GoogleMap(
              initialCameraPosition: CameraPosition(
                target: valid.isEmpty
                    ? const LatLng(12.5657, 104.9910)
                    : LatLng(valid.first.latitude, valid.first.longitude),
                zoom: valid.isEmpty ? 7 : 12,
              ),
              markers: {
                for (final p in valid)
                  Marker(
                    markerId: MarkerId(p.id),
                    position: LatLng(p.latitude, p.longitude),
                    infoWindow: InfoWindow(title: p.name),
                    onTap: onPlaceSelected == null
                        ? null
                        : () => onPlaceSelected!(p),
                  ),
              },
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
            );
          },
        );
  }
}
