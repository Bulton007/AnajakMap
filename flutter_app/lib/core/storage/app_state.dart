import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/models/travel.dart';

final preferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Initialize preferences in main'),
);
final appStateProvider = NotifierProvider<AppController, TravelState>(
  AppController.new,
);

@immutable
class TravelState {
  TravelState({
    this.locale = 'en',
    this.theme = ThemeMode.system,
    this.onboarded = false,
    this.offline = false,
    List<String> interests = const ['culture', 'food'],
    List<String> savedPlaces = const [],
    List<String> phrases = const [],
    List<Trip> trips = const [],
    List<TravelRecord> records = const [],
  }) : interests = List.unmodifiable(interests),
       savedPlaces = List.unmodifiable(savedPlaces),
       phrases = List.unmodifiable(phrases),
       trips = List.unmodifiable(trips),
       records = List.unmodifiable(records);
  final String locale;
  final ThemeMode theme;
  final bool onboarded, offline;
  final List<String> interests, savedPlaces, phrases;
  final List<Trip> trips;
  final List<TravelRecord> records;
  TravelState copyWith({
    String? locale,
    ThemeMode? theme,
    bool? onboarded,
    bool? offline,
    List<String>? interests,
    List<String>? savedPlaces,
    List<String>? phrases,
    List<Trip>? trips,
    List<TravelRecord>? records,
  }) => TravelState(
    locale: locale ?? this.locale,
    theme: theme ?? this.theme,
    onboarded: onboarded ?? this.onboarded,
    offline: offline ?? this.offline,
    interests: interests ?? this.interests,
    savedPlaces: savedPlaces ?? this.savedPlaces,
    phrases: phrases ?? this.phrases,
    trips: trips ?? this.trips,
    records: records ?? this.records,
  );
  Map<String, dynamic> toJson() => {
    'locale': locale,
    'theme': theme.name,
    'onboarded': onboarded,
    'interests': interests,
    'savedPlaces': savedPlaces,
    'phrases': phrases,
    'trips': trips.map((e) => e.toJson()).toList(),
    'records': records.map((e) => e.toJson()).toList(),
  };
  factory TravelState.fromJson(Map<String, dynamic> j) => TravelState(
    locale: j['locale'] as String,
    theme: ThemeMode.values.byName(j['theme'] as String),
    onboarded: j['onboarded'] as bool,
    interests: List<String>.from(j['interests'] as List),
    savedPlaces: List<String>.from(j['savedPlaces'] as List),
    phrases: List<String>.from(j['phrases'] as List),
    trips: (j['trips'] as List)
        .map((e) => Trip.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    records: (j['records'] as List)
        .map((e) => TravelRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

class AppController extends Notifier<TravelState> {
  @override
  TravelState build() {
    final raw = ref.read(preferencesProvider).getString('anajak.demo.v1');
    if (raw != null) {
      return TravelState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
    return seed();
  }

  static TravelState seed() => TravelState(
    trips: [
      Trip(
        id: 'sample',
        name: 'sampleTrip',
        destination: 'siemReap',
        start: DateTime(2026, 11, 12),
        end: DateTime(2026, 11, 14),
        budgetCents: 35000,
        activities: const [
          Activity(place: 'angkor', day: 0, time: '05:30'),
          Activity(place: 'market', day: 0, time: '12:00'),
          Activity(place: 'taProhm', day: 1, time: '08:00'),
          Activity(place: 'river', day: 2, time: '16:30'),
        ],
      ),
    ],
  );
  Future<void> _write(TravelState next) async {
    final ok = await ref
        .read(preferencesProvider)
        .setString('anajak.demo.v1', jsonEncode(next.toJson()));
    if (!ok) {
      throw StateError('Storage failed');
    }
    state = next;
  }

  Future<void> settings({
    String? locale,
    ThemeMode? theme,
    bool? onboarded,
    List<String>? interests,
  }) => _write(
    state.copyWith(
      locale: locale,
      theme: theme,
      onboarded: onboarded,
      interests: interests,
    ),
  );
  void offline(bool value) => state = state.copyWith(offline: value);
  Future<void> saveTrip(Trip trip) => _write(
    state.copyWith(trips: [...state.trips.where((e) => e.id != trip.id), trip]),
  );
  Future<void> updateActivities(
    String id,
    int expectedRevision,
    List<Activity> activities,
  ) async {
    final trip = state.trips.firstWhere((e) => e.id == id);
    if (trip.revision != expectedRevision) {
      throw StateError('Stale proposal');
    }
    await saveTrip(trip.withActivities(activities));
  }

  Future<void> addRecord(TravelRecord record) =>
      _write(state.copyWith(records: [...state.records, record]));
  Future<void> togglePlace(String key) => _write(
    state.copyWith(
      savedPlaces: state.savedPlaces.contains(key)
          ? state.savedPlaces.where((e) => e != key).toList()
          : [...state.savedPlaces, key],
    ),
  );
  Future<void> savePhrase(String key) =>
      _write(state.copyWith(phrases: {...state.phrases, key}.toList()));
  Future<void> reset() => _write(
    seed().copyWith(locale: state.locale, theme: state.theme, onboarded: true),
  );
}
