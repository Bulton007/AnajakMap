import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/network/api_client.dart';
import '../maps/map_location.dart';
import 'adventure_controller.dart';

final journeyPositionStreamProvider = Provider<Stream<Position> Function()>(
  (ref) =>
      () =>
          Geolocator.getPositionStream(locationSettings: journeyGpsSettings()),
);

Json journeyPosition(Position p) => {
  'latitude': p.latitude,
  'longitude': p.longitude,
  'accuracy': p.accuracy,
  'measuredAt': p.timestamp.toUtc().toIso8601String(),
  'mocked': p.isMocked,
};

class JourneyState {
  const JourneyState({
    this.journey = const {},
    this.points = const [],
    this.places = const [],
    this.position,
    this.tracking = false,
    this.busy = false,
    this.issue,
    this.destinationId,
  });
  final Json journey;
  final List<Json> points, places;
  final Position? position;
  final bool tracking, busy;
  final String? issue, destinationId;
  String get id => string(journey, 'id');
  bool get active => id.isNotEmpty && field(journey, 'endedAt') == null;
  double get distance => (field(journey, 'distanceM') as num?)?.toDouble() ?? 0;
}

final journeyProvider = NotifierProvider.autoDispose
    .family<JourneyController, JourneyState, String>(JourneyController.new);

class JourneyController extends Notifier<JourneyState> {
  JourneyController(this.account);
  final String account;
  StreamSubscription<Position>? _subscription;
  Future<void>? _upload;
  DateTime? _lastUpload;
  int _generation = 0;
  @override
  JourneyState build() {
    ref.onDispose(() {
      _generation++;
      unawaited(_subscription?.cancel());
    });
    scheduleMicrotask(load);
    return const JourneyState(busy: true);
  }

  JourneyState copy({
    Json? journey,
    List<Json>? points,
    List<Json>? places,
    Position? position,
    bool? tracking,
    bool busy = false,
    String? issue,
    String? destinationId,
  }) => JourneyState(
    journey: journey ?? state.journey,
    points: points ?? state.points,
    places: places ?? state.places,
    position: position ?? state.position,
    tracking: tracking ?? state.tracking,
    busy: busy,
    issue: issue,
    destinationId: destinationId ?? state.destinationId,
  );
  Future<void> load() async {
    try {
      final response = await ref.read(adventureRepositoryProvider).journey();
      final places = await ref.read(adventureRepositoryProvider).world('field');
      if (!ref.mounted) return;
      state = JourneyState(
        journey: object(response['journey']),
        points: objects(response['points']),
        places: places,
      );
    } catch (e) {
      if (ref.mounted) state = copy(issue: _issue(e));
    }
  }

  String _issue(Object e) => e is MapLocationIssue
      ? e.kind
      : e is ApiFailure
      ? (e.status == 404 ? 'unavailable' : 'sync')
      : 'location';
  Future<Json> _post(String path, Json body) => ref
      .read(adventureRepositoryProvider)
      .mutate(path, body, ApiClient.operationId());

  Future<void> start() async {
    if (state.busy || state.tracking) return;
    state = copy(busy: true);
    final generation = ++_generation;
    try {
      final position = await ref.read(gpsLocationProvider).current();
      if (!ref.mounted || generation != _generation) return;
      _validate(position);
      final response = await _post('journey/start', {});
      if (!ref.mounted || generation != _generation) return;
      state = copy(
        journey: object(response['journey']),
        points: objects(response['points']),
        position: position,
        tracking: true,
      );
      _lastUpload = null;
      await _sample(position);
      if (!ref.mounted || generation != _generation || !state.tracking) return;
      _subscription = ref
          .read(journeyPositionStreamProvider)()
          .listen(
            (p) {
              if (ref.mounted && generation == _generation) {
                unawaited(_sample(p));
              }
            },
            onError: (Object error) {
              if (!ref.mounted || generation != _generation) return;
              pause();
              state = copy(issue: _issue(error));
            },
            onDone: () {
              if (ref.mounted && generation == _generation) pause();
            },
          );
    } catch (e) {
      if (ref.mounted && generation == _generation) {
        state = copy(tracking: false, issue: _issue(e));
      }
    }
  }

  void _validate(Position p) {
    validatedMapPosition(p);
    if (p.isMocked) throw const MapLocationIssue('mocked');
    if (p.accuracy <= 0 || p.accuracy > 50) {
      throw const MapLocationIssue('accuracy');
    }
    final age = DateTime.now().difference(p.timestamp);
    if (age > const Duration(seconds: 60) ||
        age < const Duration(seconds: -5)) {
      throw const MapLocationIssue('stale');
    }
  }

  Future<void> _sample(Position p) async {
    if (!state.tracking || !ref.mounted) return;
    try {
      _validate(p);
    } catch (e) {
      state = copy(issue: _issue(e));
      return;
    }
    state = copy(position: p, issue: state.issue == 'sync' ? 'sync' : null);
    if (_upload != null ||
        (_lastUpload != null &&
            p.timestamp.difference(_lastUpload!) <
                const Duration(seconds: 15))) {
      return;
    }
    final id = state.id;
    final previous = _lastUpload;
    _lastUpload = p.timestamp;
    final body = journeyPosition(p);
    final future = () async {
      try {
        final result = await _post('journey/$id/points', body);
        if (!ref.mounted || state.id != id) return;
        if (result['accepted'] != true) return;
        var places = state.places;
        final destination = result['destinationId']?.toString();
        if (destination != null &&
            !places.any((place) => string(place, 'id') == destination)) {
          places = await ref.read(adventureRepositoryProvider).world('field');
          if (!ref.mounted || state.id != id) return;
        }
        state = copy(
          journey: {...state.journey, 'DISTANCE_M': result['distanceM']},
          points: [...state.points, body],
          places: places,
          destinationId: destination,
        );
      } catch (e) {
        if (ref.mounted && state.id == id) {
          _lastUpload = previous;
          state = copy(issue: _issue(e));
        }
      }
    }();
    _upload = future;
    await future;
    _upload = null;
  }

  void pause() {
    _generation++;
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (ref.mounted) state = copy(tracking: false);
  }

  Future<void> stop() async {
    if (state.busy || !state.active) return;
    pause();
    state = copy(busy: true);
    try {
      await _upload;
      final response = await _post('journey/${state.id}/stop', {});
      if (ref.mounted) {
        state = copy(
          journey: object(response['journey']),
          points: objects(response['points']),
        );
      }
    } catch (e) {
      if (ref.mounted) state = copy(issue: _issue(e));
    }
  }
}
