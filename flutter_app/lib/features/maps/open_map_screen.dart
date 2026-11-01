import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:url_launcher/url_launcher.dart';
import 'google_map_screen.dart' show MapPlace;
import 'search_results.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/models/map_route.dart';
import 'map_location.dart';
import '../../app/theme/theme.dart';
import 'route_guide.dart';
import 'map_layers.dart';
export 'google_map_screen.dart' show MapPlace;

// Keep server retry deadlines based on elapsed wall time (including app resume),
// while allowing widget tests to advance the same clock as their timers.
final mapClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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
    appBar: AppBar(
      title: Text(
        Localizations.localeOf(context).languageCode == 'km' ? 'ផែនទី' : 'Map',
      ),
    ),
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
  Position? position;
  LatLng? routeOrigin;
  MapRoute? route;
  String? selected, selectedOrigin, problem, locationIssue;
  MapPlace? pinnedStart, pinnedDestination;
  MapLayerId activeLayerId = MapLayerId.standard;
  bool? pickingStart;
  DateTime? retryAt;
  Timer? retryTimer;
  bool locating = false,
      awaitingLocationConsent = false,
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
    for (final place in [pinnedStart, pinnedDestination]) {
      if (place != null) unique[place.id] = place;
    }
    return unique.values.toList();
  }

  void clearRoute() {
    route = null;
    routeOrigin = null;
    routeRevision++;
    routing = false;
    problem = null;
  }

  void pinOnMap(LatLng point) {
    if (!widget.navigation || pickingStart == null) return;
    final start = pickingStart!;
    setState(() {
      clearRoute();
      final place = MapPlace(
        start ? '__pinned_start' : '__pinned_destination',
        start
            ? t('Pinned start', 'ចំណុចចាប់ផ្ដើមដែលបានជ្រើស')
            : t('Pinned destination', 'គោលដៅដែលបានជ្រើស'),
        point.latitude,
        point.longitude,
      );
      if (start) {
        pinnedStart = place;
        selectedOrigin = place.id;
        tracking?.cancel();
        tracking = null;
      } else {
        pinnedDestination = place;
        selected = place.id;
      }
      pickingStart = null;
    });
  }

  Future<void> searchDestination() async {
    final selectedPlace = await showSearch<MapPlace?>(
      context: context,
      delegate: _DestinationSearch(
        search: (query) => ref.read(repositoryProvider).places(query),
        khmer: km,
      ),
    );
    if (!mounted || selectedPlace == null) return;
    setState(() {
      pinnedDestination = selectedPlace;
      selected = selectedPlace.id;
      pickingStart = null;
      clearRoute();
    });
    if (routeReady) {
      map.move(
        LatLng(selectedPlace.latitude, selectedPlace.longitude),
        math.max(14, map.camera.zoom),
      );
    }
  }

  MapPlace? get destination {
    for (final place in validPlaces) {
      if (place.id == selected) return place;
    }
    if (pinnedDestination != null) return pinnedDestination;
    for (final place in widget.places) {
      if (place.valid) return place;
    }
    return null;
  }

  MapPlace? get placeOrigin {
    for (final place in validPlaces) {
      if (place.id == selectedOrigin) return place;
    }
    return null;
  }

  int get retrySeconds => retryAt == null
      ? 0
      : ((retryAt!.difference(ref.read(mapClockProvider)()).inMilliseconds /
                    1000)
                .ceil())
            .clamp(0, 2147483647);

  void waitToRetry(int seconds) {
    retryTimer?.cancel();
    retryAt = ref.read(mapClockProvider)().add(Duration(seconds: seconds));
    retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || retrySeconds == 0) timer.cancel();
      if (mounted) setState(() {});
    });
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
    retryTimer?.cancel();
    map.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      resumeTracking = tracking != null || resumeTracking;
      tracking?.cancel();
      tracking = null;
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached) {
        routeRevision++;
        routing = false;
      }
    } else if (resumeTracking && widget.navigation) {
      resumeTracking = false;
      locate(explain: false);
    }
  }

  Future<bool> locate({bool explain = true}) async {
    if (locating) return false;
    final revision = routeRevision;
    final needsConsent = explain && position == null;
    setState(() {
      locating = true;
      awaitingLocationConsent = needsConsent;
      problem = null;
      locationIssue = null;
    });
    try {
      if (needsConsent) {
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
        if (allowed != true || !mounted || revision != routeRevision) {
          return false;
        }
        setState(() => awaitingLocationConsent = false);
      }
      final access = ref.read(mapLocationProvider);
      final current = validatedMapPosition(
        await access.current(requestPermission: explain),
      );
      if (!mounted || revision != routeRevision) return false;
      setState(() => position = current);
      if (routeReady) map.move(LatLng(current.latitude, current.longitude), 14);
      // A fresh one-shot fix can reuse the active foreground stream. Waiting
      // for platform stream cancellation here can leave Directions stuck, and
      // reopening the channel is unnecessary for the same map/location source.
      tracking ??= access.watch().listen(
        (next) {
          if (!mounted) return;
          try {
            validatedMapPosition(next);
          } on MapLocationIssue {
            return;
          }
          setState(() => position = next);
          if (route != null &&
              routeOrigin != null &&
              placeOrigin == null &&
              !routing &&
              DateTime.now().difference(lastRoute!).inSeconds >= 30 &&
              Geolocator.distanceBetween(
                    routeOrigin!.latitude,
                    routeOrigin!.longitude,
                    next.latitude,
                    next.longitude,
                  ) >=
                  100) {
            directions(refreshLocation: false);
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
      return true;
    } catch (error) {
      if (mounted && revision == routeRevision) {
        setState(() {
          position = null;
          route = null;
          routeRevision++;
          routing = false;
          locationIssue = error is MapLocationIssue ? error.kind : null;
          problem = switch (locationIssue) {
            'stale' => t(
              'Your GPS fix is old. Move somewhere with a clear signal and try again.',
              'ទីតាំង GPS ចាស់ហើយ។ សូមទៅកន្លែងដែលមានសញ្ញាច្បាស់ ហើយព្យាយាមម្ដងទៀត។',
            ),
            'accuracy' => t(
              'Your location is too approximate for directions. Enable precise location and try again.',
              'ទីតាំងមិនទាន់ច្បាស់សម្រាប់ទិសដៅ។ សូមបើកទីតាំងច្បាស់លាស់ ហើយព្យាយាមម្ដងទៀត។',
            ),
            _ => t(
              'Location unavailable. Check permission and device location services.',
              'មិនអាចប្រើទីតាំងបាន។ សូមពិនិត្យការអនុញ្ញាត និងសេវាទីតាំង។',
            ),
          };
        });
        final previousTracking = tracking;
        tracking = null;
        if (previousTracking != null) unawaited(previousTracking.cancel());
      }
    } finally {
      if (mounted) {
        setState(() {
          locating = false;
          awaitingLocationConsent = false;
        });
      }
    }
    return false;
  }

  Future<void> directions({bool refreshLocation = true}) async {
    if (routing || locating || retrySeconds > 0 || destination == null) return;
    final start = placeOrigin, revision = ++routeRevision;
    setState(() {
      route = null;
      routeOrigin = null;
      problem = null;
    });
    if (start == null && (refreshLocation || position == null)) {
      if (!await locate()) return;
    }
    if (!mounted ||
        revision != routeRevision ||
        destination == null ||
        (start == null && position == null)) {
      return;
    }
    final target = destination!;
    final origin = start == null
        ? LatLng(position!.latitude, position!.longitude)
        : LatLng(start.latitude, start.longitude);
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
    } catch (error) {
      if (mounted && revision == routeRevision) {
        setState(() {
          route = null;
          final failure = error is ApiFailure ? error : null;
          if (failure?.status == 429) {
            waitToRetry(failure?.retryAfterSeconds ?? 1);
          }
          problem = switch (failure?.status) {
            404 => t(
              'No driving route connects your start and destination. Check your device location or choose another start. Routes cannot cross disconnected road networks or oceans.',
              'មិនមានផ្លូវបើកបរភ្ជាប់ចំណុចចាប់ផ្ដើម និងគោលដៅទេ។ ពិនិត្យទីតាំងឧបករណ៍ ឬជ្រើសចំណុចផ្សេង។ ផ្លូវមិនអាចឆ្លងបណ្ដាញផ្លូវដាច់ពីគ្នា ឬមហាសមុទ្របានទេ។',
            ),
            422 => t(
              'This route is outside the routing service limits. Choose a nearer start or destination.',
              'ផ្លូវនេះលើសដែនកំណត់សេវាផ្លូវ។ សូមជ្រើសចំណុចចាប់ផ្ដើម ឬគោលដៅដែលជិតជាងនេះ។',
            ),
            400 => t(
              'The route request was not accepted. Check your start and destination, then try again.',
              'សំណើផ្លូវមិនត្រូវបានទទួលយកទេ។ សូមពិនិត្យចំណុចចាប់ផ្ដើម និងគោលដៅ ហើយព្យាយាមម្ដងទៀត។',
            ),
            429 => t(
              'The route service is busy. Wait for the retry countdown.',
              'សេវាផ្លូវកំពុងរវល់។ សូមរង់ចាំរហូតដល់អាចព្យាយាមម្ដងទៀត។',
            ),
            503 => t(
              'Driving routes are not configured on this backend yet.',
              'ម៉ាស៊ីនមេនេះមិនទាន់បានកំណត់សេវាផ្លូវបើកបរទេ។',
            ),
            _ => t(
              'Could not retrieve road directions. Check your connection and selected locations, then retry. No estimate is shown.',
              'មិនអាចភ្ជាប់សេវាផ្លូវបាន។ សូមពិនិត្យអ៊ីនធឺណិត ហើយព្យាយាមម្ដងទៀត។',
            ),
          };
        });
      }
    } finally {
      if (mounted && revision == routeRevision) setState(() => routing = false);
    }
  }

  bool failed = false;

  Future<void> chooseLayer(
    List<MapLayerDefinition> definitions,
    MapLayerDefinition active,
  ) async {
    final selected = await showMapLayerPicker(
      context,
      layers: definitions,
      selected: active.id,
    );
    if (!mounted ||
        selected == null ||
        !selected.available ||
        selected.id == activeLayerId) {
      return;
    }
    setState(() {
      activeLayerId = selected.id;
      failed = false;
      tileRevision++;
      tiles = ref.read(mapTileFactoryProvider)();
    });
  }

  void tileFailed() {
    if (failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !failed) setState(() => failed = true);
    });
  }

  Widget _pickPointButton({required bool start}) => OutlinedButton.icon(
    key: ValueKey(start ? 'map-pick-start' : 'map-pick-destination'),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      visualDensity: VisualDensity.standard,
    ),
    onPressed: () => setState(() => pickingStart = start),
    icon: Icon(
      start ? Icons.trip_origin : Icons.add_location_alt_outlined,
      size: 20,
    ),
    label: Text(
      start
          ? t('Choose start', 'ជ្រើសចំណុចចាប់ផ្ដើម')
          : t('Choose destination', 'ជ្រើសគោលដៅ'),
      textAlign: TextAlign.center,
    ),
  );

  Widget _placeSelector(
    List<MapPlace> valid, {
    required bool origin,
  }) => DropdownButtonFormField<String>(
    key: ValueKey(origin ? 'map-route-origin' : 'map-route-destination'),
    initialValue: origin ? placeOrigin?.id ?? '' : destination?.id,
    isExpanded: true,
    itemHeight: null,
    menuMaxHeight: 360,
    style: Theme.of(context).textTheme.bodyMedium,
    decoration: InputDecoration(
      labelText: origin
          ? t('Start from', 'ចាប់ផ្ដើមពី')
          : t('Destination', 'គោលដៅ'),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      prefixIcon: Icon(
        origin ? Icons.trip_origin : Icons.place_outlined,
        size: 20,
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 48),
    ),
    items: [
      if (origin)
        DropdownMenuItem(
          value: '',
          child: Text(
            t('My location', 'ទីតាំងខ្ញុំ'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      for (final p in valid)
        DropdownMenuItem(
          value: p.id,
          child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) {
      setState(() {
        if (origin) {
          selectedOrigin = value;
        } else {
          selected = value;
        }
        route = null;
        routeOrigin = null;
        routeRevision++;
        routing = false;
        problem = null;
        if (origin && value != '') {
          tracking?.cancel();
          tracking = null;
        }
      });
      if (!origin && value != null && routeReady) {
        for (final place in valid) {
          if (place.id == value) {
            map.move(
              LatLng(place.latitude, place.longitude),
              math.max(14, map.camera.zoom),
            );
            break;
          }
        }
      }
    },
  );

  Widget _placeSelectors(List<MapPlace> valid) => LayoutBuilder(
    builder: (context, constraints) {
      // Keep the normal phone controls short. Larger text gets full-width
      // selectors inside the scrollable panel instead of unreadable fields.
      final sideBySide =
          constraints.maxWidth >= 280 &&
          MediaQuery.textScalerOf(context).scale(14) <= 21;
      final origin = _placeSelector(valid, origin: true);
      final destination = _placeSelector(valid, origin: false);
      return sideBySide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: origin),
                const SizedBox(width: 10),
                Expanded(child: destination),
              ],
            )
          : Column(children: [origin, const SizedBox(height: 10), destination]);
    },
  );

  Widget _routeControls(List<MapPlace> valid) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (failed) ...[
        Text(
          t('Some map tiles could not load.', 'មិនអាចផ្ទុកផែនទីមួយចំនួនបាន។'),
          key: const ValueKey('map-load-error'),
        ),
        TextButton.icon(
          onPressed: () => setState(() {
            failed = false;
            tileRevision++;
            tiles = ref.read(mapTileFactoryProvider)();
          }),
          icon: const Icon(Icons.refresh),
          label: Text(t('Retry map', 'ព្យាយាមផែនទីម្ដងទៀត')),
        ),
      ],
      if (widget.navigation) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('map-search-destination'),
            onPressed: routing ? null : searchDestination,
            icon: const Icon(Icons.search),
            label: Text(t('Search destination', 'ស្វែងរកគោលដៅ')),
          ),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            key: const ValueKey('map-pick-actions-row'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _pickPointButton(start: true)),
              const SizedBox(width: 10),
              Expanded(child: _pickPointButton(start: false)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (valid.isNotEmpty) ...[
          _placeSelectors(valid),
          const SizedBox(height: 10),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton.outlined(
              onPressed: locating || routing
                  ? null
                  : () {
                      setState(() {
                        selectedOrigin = '';
                        clearRoute();
                      });
                      locate();
                    },
              tooltip: t('My location', 'ទីតាំងខ្ញុំ'),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.my_location),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('map-directions'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onPressed:
                    routing ||
                        locating ||
                        destination == null ||
                        retrySeconds > 0
                    ? null
                    : () => directions(),
                icon: Icon(locating ? Icons.gps_fixed : Icons.directions_car),
                label: Text(
                  t(
                    retrySeconds > 0
                        ? 'Retry in ${retrySeconds}s'
                        : locating
                        ? 'Finding your location…'
                        : routing
                        ? 'Finding route…'
                        : 'Directions · Driving',
                    retrySeconds > 0
                        ? 'ព្យាយាមម្ដងទៀតក្នុង $retrySeconds វិនាទី'
                        : locating
                        ? 'កំពុងរកទីតាំងរបស់អ្នក…'
                        : routing
                        ? 'កំពុងរកផ្លូវ…'
                        : 'ទិសដៅ · បើកបរ',
                  ),
                ),
              ),
            ),
          ],
        ),
        if ((locating && !awaitingLocationConsent) || routing) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (valid.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              t(
                'Choose a destination on the map, or search for a place in Explore.',
                'ជ្រើសគោលដៅលើផែនទី ឬស្វែងរកទីកន្លែងនៅក្នុងរុករក។',
              ),
            ),
          ),
        if (placeOrigin != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              t(
                'Directions share the selected start and destination with the routing service.',
                'ទិសដៅផ្ញើចំណុចចាប់ផ្តើម និងគោលដៅដែលបានជ្រើសទៅសេវាផ្លូវ។',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (route != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.flag_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            destination!.name,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(route!.meters / 1000).toStringAsFixed(1)} km · ${(route!.seconds / 60).ceil()} min',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t(
                        'Estimate · no live traffic',
                        'ប៉ាន់ស្មាន · គ្មានចរាចរណ៍ផ្ទាល់',
                      ),
                    ),
                    if (route!.source.contains('public demo'))
                      Text(
                        t('Public test routing', 'សេវាផ្លូវសាកល្បងសាធារណៈ'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      key: const ValueKey('map-ai-guide'),
                      onPressed: () => showRouteGuide(
                        context,
                        originName:
                            placeOrigin?.name ??
                            t('My location', 'ទីតាំងខ្ញុំ'),
                        destinationName: destination!.name,
                        route: route!,
                      ),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: Text(t('AI travel tips', 'គន្លឹះធ្វើដំណើរពី AI')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Semantics(
              liveRegion: true,
              child: Text(
                problem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        if (problem != null &&
            position != null &&
            placeOrigin == null &&
            destination != null &&
            Geolocator.distanceBetween(
                  position!.latitude,
                  position!.longitude,
                  destination!.latitude,
                  destination!.longitude,
                ) >
                1000000)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              t(
                'Your GPS start is over 1,000 km from this destination. Check your device location; an emulator may use a virtual location. Driving routes cannot connect across oceans.',
                'ទីតាំង GPS ចាប់ផ្ដើមឆ្ងាយជាង ១,០០០ គីឡូម៉ែត្រពីគោលដៅ។ ពិនិត្យទីតាំងឧបករណ៍ ព្រោះកម្មវិធីត្រាប់តាមអាចប្រើទីតាំងសិប្បនិម្មិត។ ផ្លូវបើកបរមិនអាចភ្ជាប់ឆ្លងមហាសមុទ្របានទេ។',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (locationIssue == 'settings' ||
            locationIssue == 'service' ||
            locationIssue == 'accuracy')
          TextButton.icon(
            onPressed: () => ref
                .read(mapLocationProvider)
                .settings(locationIssue == 'service'),
            icon: const Icon(Icons.settings_outlined),
            label: Text(t('Open settings', 'បើកការកំណត់')),
          ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final environment = ref.watch(environmentProvider);
    final standardUrl = environment.tileUrl.isEmpty
        ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
        : environment.tileUrl;
    final standardAttribution = environment.tileAttribution.isEmpty
        ? '© OpenStreetMap contributors'
        : environment.tileAttribution;
    final layers = buildMapLayerDefinitions(
      standardUrl: standardUrl,
      standardAttribution: standardAttribution,
      standardProviderName: environment.tileUrl.isEmpty
          ? 'OpenStreetMap'
          : t('Configured map provider', 'សេវាផែនទីដែលបានកំណត់'),
    );
    final activeLayer = layers.firstWhere((layer) => layer.id == activeLayerId);
    final valid = validPlaces;
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelHeight = constraints.maxHeight.isFinite
            ? math.max(64.0, math.min(272.0, constraints.maxHeight * .38))
            : 272.0;
        return Column(
          children: [
            if (widget.navigation || failed)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: panelHeight),
                child: SingleChildScrollView(
                  key: const ValueKey('map-controls-scroll'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: _routeControls(valid),
                ),
              ),
            Expanded(
              child: Stack(
                key: const ValueKey('map-viewport'),
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: map,
                      options: MapOptions(
                        onMapReady: () => routeReady = true,
                        onTap: (_, point) => pinOnMap(point),
                        initialCenter: valid.isEmpty
                            ? const LatLng(12.5657, 104.9910)
                            : LatLng(
                                valid.first.latitude,
                                valid.first.longitude,
                              ),
                        initialZoom: valid.isEmpty ? 7 : 12,
                        minZoom: 2,
                        maxZoom: 19,
                      ),
                      children: [
                        TileLayer(
                          key: ValueKey(tileRevision),
                          urlTemplate: activeLayer.tileUrl,
                          userAgentPackageName: 'com.anajak.anajak_travel',
                          tileProvider: tiles,
                          maxNativeZoom: activeLayer.maxNativeZoom,
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
                                point: routeOrigin!,
                                width: 40,
                                height: 40,
                                child: Tooltip(
                                  message: t(
                                    'Route origin',
                                    'ចំណុចចាប់ផ្ដើមផ្លូវ',
                                  ),
                                  child: const Icon(
                                    Icons.trip_origin,
                                    color: Tokens.mapRoute,
                                    size: 26,
                                  ),
                                ),
                              ),
                            if (position != null)
                              Marker(
                                point: LatLng(
                                  position!.latitude,
                                  position!.longitude,
                                ),
                                width: 40,
                                height: 40,
                                child: Semantics(
                                  label: t('My location', 'ទីតាំងខ្ញុំ'),
                                  child: const _MapLocationDot(),
                                ),
                              ),
                            for (final p in valid)
                              Marker(
                                point: LatLng(p.latitude, p.longitude),
                                width: 48,
                                height: p.id == placeOrigin?.id ? 48 : 56,
                                alignment: p.id == placeOrigin?.id
                                    ? Alignment.center
                                    : Alignment.topCenter,
                                child: IconButton(
                                  style: IconButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(48, 48),
                                  ),
                                  tooltip: p.name,
                                  icon: p.id == placeOrigin?.id
                                      ? const Icon(
                                          Icons.trip_origin,
                                          color: Tokens.mapRoute,
                                          size: 30,
                                        )
                                      : Align(
                                          alignment: Alignment.bottomCenter,
                                          child: CustomPaint(
                                            key: ValueKey('map-pin-${p.id}'),
                                            size: const Size(34, 46),
                                            painter: const _MapPinPainter(),
                                          ),
                                        ),
                                  onPressed: () {
                                    setState(() {
                                      selected = p.id;
                                      route = null;
                                      routeOrigin = null;
                                      routeRevision++;
                                      routing = false;
                                      problem = null;
                                    });
                                    if (widget.onPlaceSelected != null) {
                                      widget.onPlaceSelected!(p);
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(content: Text(p.name)),
                                      );
                                    }
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (pickingStart == null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: MapLayersButton(
                        onPressed: () => chooseLayer(layers, activeLayer),
                      ),
                    ),
                  if (pickingStart != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Material(
                        elevation: 3,
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                          child: Row(
                            children: [
                              const Icon(Icons.touch_app_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pickingStart!
                                      ? t(
                                          'Tap the map to set your start',
                                          'ចុចលើផែនទីដើម្បីជ្រើសចំណុចចាប់ផ្ដើម',
                                        )
                                      : t(
                                          'Tap the map to set your destination',
                                          'ចុចលើផែនទីដើម្បីជ្រើសគោលដៅ',
                                        ),
                                ),
                              ),
                              IconButton(
                                tooltip: t(
                                  'Cancel selection',
                                  'បោះបង់ការជ្រើសរើស',
                                ),
                                onPressed: () =>
                                    setState(() => pickingStart = null),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: math.max(0.0, constraints.maxWidth - 16),
                      ),
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(12),
                        child: TextButton(
                          key: const ValueKey('map-attribution'),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            textStyle: Theme.of(context).textTheme.labelSmall,
                          ),
                          onPressed: () async {
                            final opened = await launchUrl(
                              Uri.parse(activeLayer.attributionUrl),
                              mode: LaunchMode.externalApplication,
                            );
                            if (!opened && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    t(
                                      'Could not open attribution link.',
                                      'មិនអាចបើកតំណបានទេ។',
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                          child: Text(
                            activeLayer.attribution,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The tip sits on the geographic point; the 48dp button around it stays easy
/// to tap without adding the oversized circular background of a filled button.
class _MapPinPainter extends CustomPainter {
  const _MapPinPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..cubicTo(
        size.width * .42,
        size.height * .74,
        size.width * .06,
        size.height * .53,
        size.width * .06,
        size.height * .34,
      )
      ..cubicTo(
        size.width * .06,
        -size.height * .06,
        size.width * .94,
        -size.height * .06,
        size.width * .94,
        size.height * .34,
      )
      ..cubicTo(
        size.width * .94,
        size.height * .53,
        size.width * .58,
        size.height * .74,
        size.width / 2,
        size.height,
      )
      ..close();
    canvas.drawShadow(path, Colors.black.withValues(alpha: .28), 2, false);
    canvas.drawPath(path, Paint()..color = Tokens.mapDestination);
    canvas.drawCircle(
      Offset(size.width / 2, size.height * .31),
      size.width * .16,
      Paint()..color = const Color(0xFF741B16),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPinPainter oldDelegate) => false;
}

class _MapLocationDot extends StatelessWidget {
  const _MapLocationDot();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Tokens.mapRoute.withValues(alpha: .18),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Tokens.mapRoute,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
          ),
        ),
      ),
    ),
  );
}

class _DestinationSearch extends SearchDelegate<MapPlace?> {
  _DestinationSearch({required this.search, required this.khmer});
  final Future<List<Json>> Function(String query) search;
  final bool khmer;

  @override
  String get searchFieldLabel =>
      khmer ? 'ស្វែងរកទីកន្លែងនៅកម្ពុជា' : 'Search places in Cambodia';

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(
        tooltip: khmer ? 'សម្អាត' : 'Clear search',
        onPressed: () => query = '',
        icon: const Icon(Icons.clear),
      ),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    tooltip: khmer ? 'ត្រឡប់ក្រោយ' : 'Back',
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_back),
  );

  @override
  Widget buildSuggestions(BuildContext context) => buildResults(context);

  @override
  Widget buildResults(BuildContext context) {
    final value = query.trim();
    if (value.length < 2) {
      return Center(
        child: Text(
          khmer
              ? 'វាយឈ្មោះទីកន្លែងដើម្បីស្វែងរក។'
              : 'Type a place name to search.',
        ),
      );
    }
    return FutureBuilder<List<Json>>(
      future: search(value),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              khmer
                  ? 'មិនអាចស្វែងរកបានទេ។ សូមព្យាយាមម្ដងទៀត។'
                  : 'Place search failed. Try again.',
            ),
          );
        }
        final rows = snapshot.data ?? const <Json>[];
        final places = rows
            .where(
              (row) =>
                  field(row, 'latitude') is num &&
                  field(row, 'longitude') is num,
            )
            .toList();
        if (places.isEmpty) {
          return Center(
            child: Text(khmer ? 'រកមិនឃើញទីកន្លែងទេ។' : 'No places found.'),
          );
        }
        return ListView.separated(
          itemCount: places.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = places[index];
            final name = string(
              row,
              'name',
              string(row, 'title', khmer ? 'ទីកន្លែង' : 'Place'),
            );
            return ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(name),
              subtitle: Text(string(row, 'province', string(row, 'city'))),
              onTap: () {
                final lat = (field(row, 'latitude') as num).toDouble();
                final lon = (field(row, 'longitude') as num).toDouble();
                close(
                  context,
                  MapPlace(string(row, 'id', 'search-$index'), name, lat, lon),
                );
              },
            );
          },
        );
      },
    );
  }
}
