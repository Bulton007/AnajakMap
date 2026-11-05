import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../maps/open_map_screen.dart' show mapTileFactoryProvider;
import 'journey_controller.dart';
import 'rpg_screen.dart' show rpgText;

LatLng? journeyCoordinate(Json p) {
  final lat = field(p, 'latitude'), lng = field(p, 'longitude');
  return lat is num &&
          lng is num &&
          lat.isFinite &&
          lng.isFinite &&
          lat.abs() <= 90 &&
          lng.abs() <= 180
      ? LatLng(lat.toDouble(), lng.toDouble())
      : null;
}

/// Paused tracking leaves a gap, rather than drawing an invented route across it.
List<List<LatLng>> journeyRouteSegments(List<Json> points) {
  final segments = <List<LatLng>>[];
  DateTime? previous;
  for (final point in points) {
    final coordinate = journeyCoordinate(point);
    final time = DateTime.tryParse(string(point, 'measuredAt'));
    if (coordinate == null || time == null) {
      previous = null;
      continue;
    }
    if (previous == null ||
        time.difference(previous) > const Duration(seconds: 45)) {
      segments.add([]);
    }
    segments.last.add(coordinate);
    previous = time;
  }
  return segments.where((s) => s.length > 1).toList();
}

class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key, required this.account});
  final String account;
  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen>
    with WidgetsBindingObserver {
  final map = MapController();
  late final TileProvider tiles;
  bool ready = false, following = true;
  String t(String en, String km) => rpgText(context, en, km);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tiles = ref.read(mapTileFactoryProvider)();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.paused ||
        value == AppLifecycleState.hidden ||
        value == AppLifecycleState.detached) {
      ref.read(journeyProvider(widget.account).notifier).pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    map.dispose();
    super.dispose();
  }

  LatLng? point(Json p) {
    return journeyCoordinate(p);
  }

  String issueText(String issue) => switch (issue) {
    'service' => t(
      'Turn on location services to track your journey.',
      'បើកសេវាទីតាំង ដើម្បីតាមដានដំណើររបស់អ្នក។',
    ),
    'denied' || 'settings' => t(
      'Allow location access in device settings, then resume.',
      'អនុញ្ញាតការចូលប្រើទីតាំងក្នុងការកំណត់ឧបករណ៍ រួចបន្ត។',
    ),
    'mocked' => t(
      'Real GPS is required. Simulated locations cannot earn rewards.',
      'ត្រូវការ GPS ពិត។ ទីតាំងសាកល្បងមិនអាចទទួលរង្វាន់បានទេ។',
    ),
    'accuracy' || 'stale' => t(
      'Waiting for a fresh, accurate GPS fix. No location is being saved yet.',
      'កំពុងរង់ចាំ GPS ថ្មី និងត្រឹមត្រូវ។ មិនទាន់រក្សាទុកទីតាំងទេ។',
    ),
    'unavailable' => t(
      'Journey tracking is unavailable on this server.',
      'ការតាមដានដំណើរមិនអាចប្រើបានលើម៉ាស៊ីនមេនេះទេ។',
    ),
    'sync' => t(
      'Could not save the latest location. Check your connection; tracking will retry.',
      'មិនអាចរក្សាទុកទីតាំងថ្មីបានទេ។ ពិនិត្យការតភ្ជាប់ ការតាមដាននឹងព្យាយាមម្ដងទៀត។',
    ),
    _ => t(
      'Location is unavailable. Try resuming your journey.',
      'មិនអាចរកទីតាំងបានទេ។ សូមព្យាយាមបន្តដំណើរ។',
    ),
  };
  @override
  Widget build(BuildContext context) {
    final provider = journeyProvider(widget.account);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);
    final theme = Theme.of(context);
    final environment = ref.watch(environmentProvider);
    final route = state.points.map(point).whereType<LatLng>().toList();
    final segments = journeyRouteSegments(state.points);
    final p = state.position;
    final location = p == null ? null : LatLng(p.latitude, p.longitude);
    final center = location ?? route.lastOrNull;
    final visits = state.places
        .where(
          (place) => integer(place, 'visited') == 1 && point(place) != null,
        )
        .toList();
    Json? nearby;
    if (p != null &&
        DateTime.now().difference(p.timestamp) < const Duration(seconds: 60)) {
      for (final visit in visits) {
        final v = point(visit)!;
        if (Geolocator.distanceBetween(
                  p.latitude,
                  p.longitude,
                  v.latitude,
                  v.longitude,
                ) +
                p.accuracy <=
            100) {
          nearby = visit;
          break;
        }
      }
    }
    ref.listen(provider, (previous, next) {
      final position = next.position;
      if (ready &&
          following &&
          position != null &&
          position != previous?.position) {
        map.move(
          LatLng(position.latitude, position.longitude),
          map.camera.zoom,
        );
      }
    });
    return Scaffold(
      appBar: AppBar(title: Text(t('My journey', 'ដំណើររបស់ខ្ញុំ'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            state.tracking
                                ? Icons.gps_fixed
                                : Icons.pause_circle_outline,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              state.tracking
                                  ? t('Live tracking', 'កំពុងតាមដានផ្ទាល់')
                                  : t('Tracking paused', 'ផ្អាកការតាមដាន'),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t(
                          'Your route saves privately to your account. Tracking pauses when this screen closes or the app goes into the background.',
                          'ផ្លូវរបស់អ្នករក្សាទុកជាឯកជនក្នុងគណនី។ ការតាមដានផ្អាកពេលបិទទំព័រនេះ ឬចាកចេញពីកម្មវិធី។',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          Chip(
                            avatar: const Icon(Icons.route, size: 18),
                            label: Text(
                              '${(state.distance / 1000).toStringAsFixed(2)} km',
                            ),
                          ),
                          Chip(
                            avatar: const Icon(Icons.pets, size: 18),
                            label: Text(
                              '${visits.length} ${t(visits.length == 1 ? 'visited stop' : 'visited stops', 'ទីតាំងបានទៅដល់')}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (state.busy) const LinearProgressIndicator(),
              if (state.issue != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    issueText(state.issue!),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              if (center == null)
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      t(
                        'Start tracking to see your actual location and route.',
                        'ចាប់ផ្ដើមតាមដាន ដើម្បីមើលទីតាំង និងផ្លូវពិតរបស់អ្នក។',
                      ),
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 330,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: map,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: 16,
                            minZoom: 2,
                            maxZoom: 19,
                            onMapReady: () => ready = true,
                            onPositionChanged: (_, gesture) {
                              if (gesture && following) {
                                setState(() => following = false);
                              }
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: environment.tileUrl.isEmpty
                                  ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                                  : environment.tileUrl,
                              tileProvider: tiles,
                              userAgentPackageName: 'com.anajak.anajak_travel',
                            ),
                            if (segments.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  for (final segment in segments)
                                    Polyline(
                                      points: segment,
                                      strokeWidth: 5,
                                      color: theme.colorScheme.primary,
                                    ),
                                ],
                              ),
                            MarkerLayer(
                              markers: [
                                for (final visit in visits)
                                  Marker(
                                    point: point(visit)!,
                                    width: 44,
                                    height: 44,
                                    alignment: Alignment.bottomCenter,
                                    child: Tooltip(
                                      message: t(
                                        'Visited encounter location',
                                        'ទីតាំងជួបសត្វដែលបានទៅដល់',
                                      ),
                                      child: Icon(
                                        Icons.pets,
                                        color: theme.colorScheme.tertiary,
                                        size: 28,
                                      ),
                                    ),
                                  ),
                                if (location != null)
                                  Marker(
                                    point: location,
                                    width: 32,
                                    height: 32,
                                    child: Tooltip(
                                      message: t(
                                        'Your live location',
                                        'ទីតាំងផ្ទាល់របស់អ្នក',
                                      ),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 4,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            RichAttributionWidget(
                              attributions: [
                                TextSourceAttribution(
                                  environment.tileAttribution.isEmpty
                                      ? '© OpenStreetMap contributors'
                                      : environment.tileAttribution,
                                  onTap: () => launchUrl(
                                    Uri.parse(
                                      'https://www.openstreetmap.org/copyright',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Card(
                            child: IconButton(
                              tooltip: t(
                                'Follow my location',
                                'តាមទីតាំងរបស់ខ្ញុំ',
                              ),
                              icon: Icon(
                                following
                                    ? Icons.gps_fixed
                                    : Icons.gps_not_fixed,
                              ),
                              onPressed: location == null
                                  ? null
                                  : () {
                                      setState(() => following = true);
                                      if (ready) {
                                        map.move(location, map.camera.zoom);
                                      }
                                    },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const Key('journey-track'),
                onPressed: state.busy
                    ? null
                    : state.tracking
                    ? controller.pause
                    : controller.start,
                icon: Icon(state.tracking ? Icons.pause : Icons.play_arrow),
                label: Text(
                  state.tracking
                      ? t('Pause tracking', 'ផ្អាកការតាមដាន')
                      : state.active
                      ? t('Resume journey', 'បន្តដំណើរ')
                      : t('Start journey', 'ចាប់ផ្ដើមដំណើរ'),
                ),
              ),
              if (state.active)
                OutlinedButton.icon(
                  onPressed: state.busy ? null : controller.stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(t('End journey', 'បញ្ចប់ដំណើរ')),
                ),
              if (nearby != null)
                FilledButton.tonalIcon(
                  key: const Key('journey-encounter'),
                  icon: const Icon(Icons.pets),
                  onPressed: state.busy
                      ? null
                      : () => Navigator.of(context).pop(string(nearby!, 'id')),
                  label: Text(
                    t('Look for creatures here', 'ស្វែងរកសត្វនៅទីនេះ'),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    t(
                      'Stop safely for about 15 seconds to discover a visited location. Creatures are selected randomly when you start an encounter; cooldowns apply.',
                      'ឈប់នៅកន្លែងសុវត្ថិភាពប្រហែល ១៥ វិនាទី ដើម្បីសម្គាល់ទីតាំងបានទៅដល់។ សត្វត្រូវបានជ្រើសដោយចៃដន្យពេលចាប់ផ្ដើមជួប ហើយមានពេលរង់ចាំ។',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
