import 'package:flutter/material.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'google_map_screen.dart' show MapPlace;
import 'search_results.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/models/map_route.dart';
import 'map_location.dart';
import '../../app/theme/theme.dart';
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
        navigation: true,
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
    this.navigation = false,
  });
  final List<MapPlace> places;
  final ValueChanged<MapPlace>? onPlaceSelected;
  final bool navigation;
  @override
  ConsumerState<TravelOpenMap> createState() => _TravelOpenMapState();
}

class _TravelOpenMapState extends ConsumerState<TravelOpenMap>
    with WidgetsBindingObserver {
  late TileProvider tiles = ref.read(mapTileFactoryProvider)();
  final map = MapController();
  StreamSubscription<Position>? tracking;
  Position? position, routeOrigin;
  MapRoute? route;
  String? selected, problem, locationIssue;
  bool locating = false,
      routing = false,
      routeReady = false,
      resumeTracking = false;
  int routeRevision = 0, tileRevision = 0;
  DateTime? lastRoute;
  bool get km => Localizations.localeOf(context).languageCode == 'km';
  String t(String en, String kh) => km ? kh : en;
  List<MapPlace> get validPlaces {
    final unique = <String, MapPlace>{};
    for (final place in widget.places.where((p) => p.valid)) {
      unique.putIfAbsent(place.id, () => place);
    }
    return unique.values.toList();
  }

  MapPlace? get destination {
    final valid = validPlaces;
    return valid.isEmpty
        ? null
        : valid.firstWhere((p) => p.id == selected, orElse: () => valid.first);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled && tracking != null) {
      tracking?.cancel();
      tracking = null;
      resumeTracking = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tracking?.cancel();
    map.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      resumeTracking = tracking != null || resumeTracking;
      tracking?.cancel();
      tracking = null;
    } else if (resumeTracking && widget.navigation) {
      resumeTracking = false;
      locate(explain: false);
    }
  }

  Future<void> locate({bool explain = true}) async {
    if (locating) return;
    if (explain && position == null) {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(t('Use your location?', 'ប្រើទីតាំងរបស់អ្នក?')),
          content: Text(
            t(
              'Location is used while this map is open. Directions send your origin and destination to the backend and configured router. No background location is requested.',
              'ទីតាំងត្រូវបានប្រើពេលបើកផែនទីនេះ។ ទិសដៅផ្ញើទីតាំងចាប់ផ្តើម និងគោលដៅទៅម៉ាស៊ីនមេ និងសេវាផ្លូវដែលបានកំណត់។ មិនស្នើទីតាំងនៅផ្ទៃខាងក្រោយទេ។',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(t('Cancel', 'បោះបង់')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(t('Continue', 'បន្ត')),
            ),
          ],
        ),
      );
      if (allowed != true || !mounted) return;
    }
    setState(() {
      locating = true;
      problem = null;
      locationIssue = null;
    });
    try {
      final access = ref.read(mapLocationProvider);
      final current = await access.current(requestPermission: explain);
      if (!mounted) return;
      setState(() => position = current);
      if (routeReady) map.move(LatLng(current.latitude, current.longitude), 14);
      await tracking?.cancel();
      tracking = access.watch().listen(
        (next) {
          if (!mounted) return;
          setState(() => position = next);
          if (route != null &&
              routeOrigin != null &&
              !routing &&
              DateTime.now().difference(lastRoute!).inSeconds >= 30 &&
              Geolocator.distanceBetween(
                    routeOrigin!.latitude,
                    routeOrigin!.longitude,
                    next.latitude,
                    next.longitude,
                  ) >=
                  100) {
            directions();
          }
        },
        onError: (_) {
          if (mounted) {
            setState(
              () => problem = t(
                'Location updates stopped. Tap My location to retry.',
                'ទីតាំងបានឈប់ធ្វើបច្ចុប្បន្នភាព។ សូមចុចទីតាំងខ្ញុំ ដើម្បីព្យាយាមម្ដងទៀត។',
              ),
            );
          }
          tracking?.cancel();
          tracking = null;
        },
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          position = null;
          route = null;
          routeRevision++;
          routing = false;
          locationIssue = error is MapLocationIssue ? error.kind : null;
          problem = t(
            'Location unavailable. Check permission and device location services.',
            'មិនអាចប្រើទីតាំងបាន។ សូមពិនិត្យការអនុញ្ញាត និងសេវាទីតាំង។',
          );
        });
      }
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> directions() async {
    if (routing || destination == null) return;
    if (position == null) await locate();
    if (!mounted || position == null) return;
    final target = destination!, origin = position!, revision = ++routeRevision;
    setState(() {
      routing = true;
      problem = null;
    });
    lastRoute = DateTime.now();
    try {
      final result = await ref
          .read(repositoryProvider)
          .route(
            origin.latitude,
            origin.longitude,
            target.latitude,
            target.longitude,
          );
      if (!mounted || revision != routeRevision) return;
      setState(() {
        route = result;
        routeOrigin = origin;
      });
      if (routeReady) {
        map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(result.points),
            padding: const EdgeInsets.all(36),
          ),
        );
      }
    } catch (_) {
      if (mounted && revision == routeRevision) {
        setState(() {
          route = null;
          problem = t(
            'No route available. Check your connection or the configured routing provider. No estimate is shown.',
            'មិនមានផ្លូវ។ សូមពិនិត្យអ៊ីនធឺណិត ឬសេវាផ្លូវ។ មិនបង្ហាញការប៉ាន់ស្មានទេ។',
          );
        });
      }
    } finally {
      if (mounted && revision == routeRevision) setState(() => routing = false);
    }
  }

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
    final valid = validPlaces;
    return Column(
      children: [
        if (failed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              km
                  ? 'មិនអាចផ្ទុកផែនទីមួយចំនួនបាន។'
                  : 'Some map tiles could not load.',
              key: const ValueKey('map-load-error'),
            ),
          ),
        if (failed)
          TextButton(
            onPressed: () => setState(() {
              failed = false;
              tileRevision++;
              tiles = ref.read(mapTileFactoryProvider)();
            }),
            child: Text(t('Retry map', 'ព្យាយាមផែនទីម្ដងទៀត')),
          ),
        if (widget.navigation)
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    if (valid.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: destination?.id,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t('Destination', 'គោលដៅ'),
                        ),
                        items: [
                          for (final p in valid)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          selected = value;
                          route = null;
                          routeRevision++;
                          routing = false;
                        }),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: locating ? null : locate,
                          icon: const Icon(Icons.my_location),
                          label: Text(t('My location', 'ទីតាំងខ្ញុំ')),
                        ),
                        FilledButton.icon(
                          onPressed: routing || locating || valid.isEmpty
                              ? null
                              : directions,
                          icon: const Icon(Icons.directions_car),
                          label: Text(
                            t(
                              routing
                                  ? 'Finding route…'
                                  : 'Directions · Driving',
                              routing ? 'កំពុងរកផ្លូវ…' : 'ទិសដៅ · បើកបរ',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (locating) const LinearProgressIndicator(),
                    if (route != null)
                      Text(
                        '${(route!.meters / 1000).toStringAsFixed(1)} km · ${(route!.seconds / 60).ceil()} min · ${route!.source}\n${t('Estimate · no live traffic', 'ប៉ាន់ស្មាន · គ្មានចរាចរណ៍ផ្ទាល់')}',
                      ),
                    if (problem != null)
                      Text(
                        problem!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (locationIssue == 'settings' ||
                        locationIssue == 'service')
                      TextButton(
                        onPressed: () => ref
                            .read(mapLocationProvider)
                            .settings(locationIssue == 'service'),
                        child: Text(t('Open settings', 'បើកការកំណត់')),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: FlutterMap(
            mapController: map,
            options: MapOptions(
              onMapReady: () => routeReady = true,
              initialCenter: valid.isEmpty
                  ? const LatLng(12.5657, 104.9910)
                  : LatLng(valid.first.latitude, valid.first.longitude),
              initialZoom: valid.isEmpty ? 7 : 12,
              minZoom: 2,
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                key: ValueKey(tileRevision),
                urlTemplate: tileUrl,
                userAgentPackageName: 'com.anajak.anajak_travel',
                tileProvider: tiles,
                maxNativeZoom: 19,
                panBuffer: 0,
                errorTileCallback: (_, _, _) => tileFailed(),
              ),
              if (route != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route!.points,
                      color: Tokens.mapRoute,
                      strokeWidth: 6,
                      borderColor: Colors.white,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (route != null && routeOrigin != null)
                    Marker(
                      point: LatLng(
                        routeOrigin!.latitude,
                        routeOrigin!.longitude,
                      ),
                      width: 40,
                      height: 40,
                      child: Tooltip(
                        message: t('Route origin', 'ចំណុចចាប់ផ្ដើមផ្លូវ'),
                        child: const Icon(
                          Icons.trip_origin,
                          color: Tokens.mapRoute,
                          size: 26,
                        ),
                      ),
                    ),
                  if (position != null)
                    Marker(
                      point: LatLng(position!.latitude, position!.longitude),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.my_location,
                        color: Tokens.mapRoute,
                        size: 32,
                      ),
                    ),
                  for (final p in valid)
                    Marker(
                      point: LatLng(p.latitude, p.longitude),
                      width: 48,
                      height: 48,
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Tokens.mapDestination,
                          foregroundColor: Colors.white,
                        ),
                        tooltip: p.name,
                        icon: const Icon(Icons.place),
                        onPressed: () {
                          setState(() {
                            selected = p.id;
                            route = null;
                            routeRevision++;
                            routing = false;
                          });
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
