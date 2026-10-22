import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'google_map_screen.dart' show MapPlace;
import 'search_results.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
export 'google_map_screen.dart' show MapPlace;

// A factory gives each map its own provider lifetime. Tests supply local images.
final mapTileFactoryProvider = Provider<TileProvider Function()>(
  (ref) =>
      () => NetworkTileProvider(
        headers: {
          'User-Agent':
              'AnajakMap/1.0 (com.anajak.anajak_travel; contact: forusea168@gmail.com)',
        },
      ),
);

class OpenMapScreen extends ConsumerWidget {
  const OpenMapScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('OpenStreetMap')),
    body: SafeArea(
      child: TravelOpenMap(
        places: [
          for (final p in ref.watch(searchResultsProvider))
            if (field(p, 'latitude') is num && field(p, 'longitude') is num)
              MapPlace(
                string(p, 'id'),
                string(p, 'name'),
                (field(p, 'latitude') as num).toDouble(),
                (field(p, 'longitude') as num).toDouble(),
              ),
        ],
      ),
    ),
  );
}

class TravelOpenMap extends ConsumerStatefulWidget {
  const TravelOpenMap({
    super.key,
    this.places = const [],
    this.onPlaceSelected,
  });
  final List<MapPlace> places;
  final ValueChanged<MapPlace>? onPlaceSelected;
  @override
  ConsumerState<TravelOpenMap> createState() => _TravelOpenMapState();
}

class _TravelOpenMapState extends ConsumerState<TravelOpenMap> {
  late final TileProvider tiles = ref.read(mapTileFactoryProvider)();
  bool failed = false;
  void tileFailed() {
    if (failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !failed) setState(() => failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final km = Localizations.localeOf(context).languageCode == 'km';
    final environment = ref.watch(environmentProvider);
    final tileUrl = environment.tileUrl.isEmpty
        ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
        : environment.tileUrl;
    final attribution = environment.tileAttribution.isEmpty
        ? '© OpenStreetMap contributors'
        : environment.tileAttribution;
    final valid = widget.places.where((p) => p.valid).toList();
    return Column(
      children: [
        if (failed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              km
                  ? 'មិនអាចផ្ទុកផែនទីមួយចំនួនបាន។ សូមពិនិត្យអ៊ីនធឺណិត ហើយបើកផែនទីម្ដងទៀត។'
                  : 'Some map tiles could not load. Check your connection and reopen the map.',
              key: const ValueKey('map-load-error'),
            ),
          ),
        Expanded(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: valid.isEmpty
                  ? const LatLng(12.5657, 104.9910)
                  : LatLng(valid.first.latitude, valid.first.longitude),
              initialZoom: valid.isEmpty ? 7 : 12,
              minZoom: 2,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: tileUrl,
                userAgentPackageName: 'com.anajak.anajak_travel',
                tileProvider: tiles,
                maxNativeZoom: 19,
                panBuffer: 0,
                errorTileCallback: (_, _, _) => tileFailed(),
              ),
              MarkerLayer(
                markers: [
                  for (final p in valid)
                    Marker(
                      point: LatLng(p.latitude, p.longitude),
                      width: 48,
                      height: 48,
                      child: IconButton.filled(
                        tooltip: p.name,
                        icon: const Icon(Icons.place),
                        onPressed: () {
                          if (widget.onPlaceSelected != null) {
                            widget.onPlaceSelected!(p);
                          } else {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(p.name)));
                          }
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () async {
            final opened = await launchUrl(
              Uri.parse('https://www.openstreetmap.org/copyright'),
              mode: LaunchMode.externalApplication,
            );
            if (!opened && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    km
                        ? 'មិនអាចបើកតំណបានទេ។'
                        : 'Could not open attribution link.',
                  ),
                ),
              );
            }
          },
          child: Text(attribution),
        ),
      ],
    );
  }
}
