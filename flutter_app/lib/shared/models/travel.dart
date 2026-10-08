import 'package:flutter/material.dart';

@immutable
class Activity {
  const Activity({required this.place, required this.day, this.time = '08:00'});
  final String place;
  final int day;
  final String time;
  Map<String, dynamic> toJson() => {'place': place, 'day': day, 'time': time};
  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
    place: j['place'] as String,
    day: j['day'] as int,
    time: j['time'] as String,
  );
}

@immutable
class Trip {
  Trip({
    required this.id,
    required this.name,
    required this.destination,
    required this.start,
    required this.end,
    required this.budgetCents,
    required List<Activity> activities,
    this.revision = 0,
  }) : activities = List.unmodifiable(activities);
  final String id, name, destination;
  final DateTime start, end;
  final int budgetCents, revision;
  final List<Activity> activities;
  int get days =>
      DateTime.utc(
        end.year,
        end.month,
        end.day,
      ).difference(DateTime.utc(start.year, start.month, start.day)).inDays +
      1;
  Trip withActivities(List<Activity> value) => Trip(
    id: id,
    name: name,
    destination: destination,
    start: start,
    end: end,
    budgetCents: budgetCents,
    activities: value,
    revision: revision + 1,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'destination': destination,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'budgetCents': budgetCents,
    'revision': revision,
    'activities': activities.map((e) => e.toJson()).toList(),
  };
  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
    id: j['id'] as String,
    name: j['name'] as String,
    destination: j['destination'] as String,
    start: DateTime.parse(j['start'] as String),
    end: DateTime.parse(j['end'] as String),
    budgetCents: j['budgetCents'] as int,
    revision: j['revision'] as int? ?? 0,
    activities: (j['activities'] as List)
        .map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

enum ProposalPhase { ready, applying, completed, discarded, stale, failed }

class TripProposal {
  TripProposal(this.trip);
  final Trip trip;
  ProposalPhase phase = ProposalPhase.ready;
  Future<void> approve(Future<void> Function(Trip) commit) async {
    if (phase != ProposalPhase.ready && phase != ProposalPhase.failed) {
      throw StateError('Proposal is not approvable');
    }
    phase = ProposalPhase.applying;
    try {
      await commit(trip);
      phase = ProposalPhase.completed;
    } catch (_) {
      phase = ProposalPhase.failed;
      rethrow;
    }
  }

  void discard() {
    if (phase == ProposalPhase.ready || phase == ProposalPhase.failed) {
      phase = ProposalPhase.discarded;
    }
  }
}

@immutable
class TravelRecord {
  const TravelRecord({
    required this.id,
    required this.tripId,
    required this.kind,
    required this.title,
    this.detail = '',
    this.cents = 0,
    this.photo = false,
  });
  final String id, tripId, kind, title, detail;
  final int cents;
  final bool photo;
  Map<String, dynamic> toJson() => {
    'id': id,
    'tripId': tripId,
    'kind': kind,
    'title': title,
    'detail': detail,
    'cents': cents,
    'photo': photo,
  };
  factory TravelRecord.fromJson(Map<String, dynamic> j) => TravelRecord(
    id: j['id'] as String,
    tripId: j['tripId'] as String,
    kind: j['kind'] as String,
    title: j['title'] as String,
    detail: j['detail'] as String,
    cents: j['cents'] as int,
    photo: j['photo'] as bool,
  );
}

int? parseMoney(String input) {
  final value = input.trim();
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final cents =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  return cents > 0 ? cents : null;
}

const placeKeys = ['angkor', 'taProhm', 'market', 'river'];
const placeCategories = {
  'angkor': 'culture',
  'taProhm': 'culture',
  'market': 'food',
  'river': 'nature',
};
