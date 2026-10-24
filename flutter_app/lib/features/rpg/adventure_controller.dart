import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import 'adventure_repository.dart';

final adventureRepositoryProvider = Provider(
  (ref) => AdventureRepository(ref.watch(apiProvider)),
);
final adventureLocationProvider = Provider<Future<Json> Function()>(
  (ref) => () async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const ApiFailure(
        'GPS',
        'Enable location services to check proximity.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const ApiFailure(
        'GPS',
        'Location permission is required for field encounters. Enable it in device settings.',
      );
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return {
      'latitude': p.latitude,
      'longitude': p.longitude,
      'accuracy': p.accuracy,
      'measuredAt': p.timestamp.toUtc().toIso8601String(),
      'mocked': p.isMocked,
    };
  },
);

class AdventureState {
  const AdventureState({
    this.busy = false,
    this.snapshot,
    this.world = const [],
    this.capabilities = const {},
    this.session,
    this.failure,
    this.pending = false,
    this.needsRefresh = false,
    this.retryAt,
  });
  final bool busy, pending, needsRefresh;
  final AdventureSnapshot? snapshot;
  final List<Json> world;
  final Json capabilities;
  final Json? session;
  final ApiFailure? failure;
  final DateTime? retryAt;
  bool get active => session?['status'] == 'active';
  bool expiredAt(DateTime now) {
    if (!active) return false;
    final end = DateTime.tryParse(session?['expiresAt']?.toString() ?? '');
    return end == null || !end.isAfter(now);
  }

  bool get expired => expiredAt(DateTime.now());
  bool get canAct =>
      !busy &&
      !pending &&
      !needsRefresh &&
      !expired &&
      !(retryAt?.isAfter(DateTime.now()) ?? false);
}

class _Pending {
  _Pending(this.path, this.body) : key = ApiClient.operationId();
  final String path, key;
  final Json body;
}

// Account is part of the provider identity so sign-out cannot expose another player's state.
final adventureProvider = NotifierProvider.autoDispose
    .family<AdventureController, AdventureState, (String, String)>(
      AdventureController.new,
    );

class AdventureController extends Notifier<AdventureState> {
  AdventureController(this.scope);
  final (String, String) scope;
  String get realm => scope.$2;
  _Pending? _pending;
  Timer? _expiry;
  void _watchExpiry() {
    _expiry?.cancel();
    if (!state.active) return;
    final end = DateTime.tryParse(
      state.session?['expiresAt']?.toString() ?? '',
    );
    final delay = end?.difference(DateTime.now()) ?? Duration.zero;
    _expiry = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (ref.mounted && state.expired) {
        state = _state(
          busy: state.busy,
          failure: state.failure,
          needsRefresh: true,
        );
      }
    });
  }

  AdventureRepository get repo => ref.read(adventureRepositoryProvider);
  @override
  AdventureState build() {
    ref.onDispose(() => _expiry?.cancel());
    scheduleMicrotask(load);
    return const AdventureState(busy: true);
  }

  AdventureState _state({
    bool busy = false,
    ApiFailure? failure,
    bool needsRefresh = false,
    DateTime? retryAt,
  }) => AdventureState(
    busy: busy,
    snapshot: state.snapshot,
    world: state.world,
    capabilities: state.capabilities,
    session: state.session,
    failure: failure,
    pending: _pending != null,
    needsRefresh: needsRefresh,
    retryAt: retryAt ?? state.retryAt,
  );
  Future<void> load() async {
    if (!ref.mounted) return;
    if (_pending != null) return retry();
    state = _state(busy: true);
    try {
      final caps = await repo.capabilities();
      final world = await repo.world(realm);
      final snapshot = await repo.profile(realm);
      if (ref.mounted) {
        state = AdventureState(
          snapshot: snapshot,
          world: world,
          capabilities: caps,
          session: snapshot.active,
        );
        _watchExpiry();
      }
    } catch (e) {
      if (ref.mounted) state = _state(failure: _failure(e), needsRefresh: true);
    }
  }

  ApiFailure _failure(Object e) => e is ApiFailure
      ? e
      : const ApiFailure(
          'UNAVAILABLE',
          'Adventure unavailable. Refresh and try again.',
        );
  Future<void> start(
    String destination,
    String monster,
    bool safe, {
    bool boss = false,
  }) async {
    if (!state.canAct || state.active || !safe) return;
    state = _state(busy: true);
    try {
      final location = realm == 'field'
          ? await ref.read(adventureLocationProvider)()
          : null;
      if (!ref.mounted) return;
      _pending = _Pending('$realm/encounters', {
        'destinationId': destination,
        'monsterId': monster,
        'safeConfirmed': safe,
        'location': location,
        'kind': boss ? 'boss' : 'wild',
      });
      await _send();
    } catch (e) {
      if (ref.mounted) state = _state(failure: _failure(e));
    }
  }

  Future<void> move(String move, {String? monsterId}) async {
    if (!state.canAct || !state.active) return;
    _pending = _Pending('$realm/battles/${state.session!['id']}/actions', {
      'revision': state.session!['revision'],
      'move': move,
      'monsterId': ?monsterId,
    });
    await _send();
  }

  Future<void> claim(String id) async {
    if (!state.canAct) return;
    _pending = _Pending('$realm/quests/$id/claim', {});
    await _send();
  }

  Future<void> manage(String operation, Json body) async {
    if (!state.canAct || state.active) return;
    _pending = _Pending('$realm/$operation', body);
    await _send();
  }

  Future<void> retry() async {
    if (state.busy ||
        _pending == null ||
        (state.retryAt?.isAfter(DateTime.now()) ?? false)) {
      return;
    }
    await _send();
  }

  Future<void> _send() async {
    final pending = _pending!;
    state = _state(busy: true);
    try {
      final result = await repo.mutate(pending.path, pending.body, pending.key);
      final snapshot = await repo.profile(realm);
      if (!ref.mounted) return;
      _pending = null;
      state = AdventureState(
        snapshot: snapshot,
        world: state.world,
        capabilities: state.capabilities,
        session:
            snapshot.active ??
            (result.containsKey('battle') ? result : state.session),
      );
      _watchExpiry();
    } catch (e) {
      if (!ref.mounted) return;
      final failure = _failure(e);
      // Unknown network/5xx outcomes keep the exact request/key for a safe replay.
      final definitive =
          failure.status != null &&
          failure.status! >= 400 &&
          failure.status! < 500;
      if (definitive) _pending = null;
      state = _state(
        failure: failure,
        needsRefresh: definitive,
        retryAt: failure.retryAfterSeconds == null
            ? null
            : DateTime.now().add(Duration(seconds: failure.retryAfterSeconds!)),
      );
    }
  }
}
