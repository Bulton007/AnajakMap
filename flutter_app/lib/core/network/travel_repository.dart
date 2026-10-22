import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../../shared/models/server_models.dart';
import 'api_client.dart';

/// Matches the Spring controllers. JSON is retained for provider-defined metadata;
/// trip/activity/job boundaries are typed and Oracle projection casing is normalized.
class TravelRepository {
  TravelRepository(this.client);
  final ApiClient client;
  Future<Json> auth(String operation, Json input) async {
    final data = object(
      await client.request('POST', 'auth/$operation', body: input, auth: false),
    );
    if (operation == 'login') {
      await client.acceptTokens(data);
    }
    return data;
  }

  Future<Json> runtime() async =>
      object(await client.request('GET', 'runtime'));
  Future<Json> recommendations(Json preferences) async => object(
    await client.request('POST', 'guide/recommendations', body: preferences),
  );
  Future<Json> profile() async =>
      object(await client.request('GET', 'profile'));
  Future<Json> preferences(Json preferences, int version) async => object(
    await client.request(
      'PUT',
      'profile/preferences',
      body: {'preferences': preferences, 'version': version},
    ),
  );
  Future<List<ServerTrip>> trips({int page = 0}) async => objects(
    await client.request('GET', 'trips', query: {'page': page, 'size': 20}),
  ).map(ServerTrip.fromJson).toList();
  Future<ServerTrip> trip(String id) async =>
      ServerTrip.fromJson(object(await client.request('GET', 'trips/$id')));
  Future<ServerTrip> createTrip(Json input, String key) async =>
      ServerTrip.fromJson(
        object(await client.request('POST', 'trips', body: input, key: key)),
      );
  Future<ServerTrip> syncTrip(String id, int version, Json input) async =>
      ServerTrip.fromJson(
        object(
          await client.request(
            'PUT',
            'trips/$id/sync',
            body: {'baseVersion': version, 'trip': input},
          ),
        ),
      );
  Future<Json> snapshot(String id) async =>
      object(await client.request('GET', 'trips/$id/offline'));
  Future<Json> calendar(String id) async =>
      object(await client.request('GET', 'trips/$id/calendar'));
  Future<List<Json>> map(String id) async =>
      objects(await client.request('GET', 'trips/$id/map'));
  Future<List<Json>> itineraries(String id) async =>
      objects(await client.request('GET', 'trips/$id/itineraries'));
  Future<Json> itinerary(String tripId, String id) async =>
      object(await client.request('GET', 'trips/$tripId/itineraries/$id'));
  Future<Json> draft(
    String tripId,
    List<ServerActivity> activities,
    String source,
    String key,
  ) async => object(
    await client.request(
      'POST',
      'trips/$tripId/itineraries',
      key: key,
      body: {
        'activities': activities.map((a) => a.toDraft()).toList(),
        'source': source,
      },
    ),
  );
  Future<Json> editDraft(
    String tripId,
    String id,
    int version,
    List<ServerActivity> activities,
    String source,
  ) async => object(
    await client.request(
      'PUT',
      'trips/$tripId/itineraries/$id',
      body: {
        'version': version,
        'itinerary': {
          'activities': activities.map((a) => a.toDraft()).toList(),
          'source': source,
        },
      },
    ),
  );
  Future<Json> approve(
    String tripId,
    String id,
    int version,
    int baseVersion,
  ) async => object(
    await client.request(
      'POST',
      'trips/$tripId/itineraries/approve',
      body: {'itineraryId': id, 'version': version, 'baseVersion': baseVersion},
    ),
  );
  Future<Json> generate(
    String tripId,
    Json preferences,
    String key, {
    bool replan = false,
  }) async => object(
    await client.request(
      'POST',
      'guide/${replan ? 'replanning' : 'itinerary'}-jobs',
      key: key,
      body: {'tripId': tripId, 'preferences': preferences},
    ),
  );
  Future<GenerationJob> job(String id, {CancelToken? cancel}) async =>
      GenerationJob.fromJson(
        object(await client.request('GET', 'guide/jobs/$id', cancel: cancel)),
      );
  Future<Json> saveJob(String id, String key, {bool replan = false}) async =>
      object(
        await client.request(
          'POST',
          'guide/jobs/$id/${replan ? 'save-proposal' : 'save-draft'}',
          body: <String, dynamic>{},
          key: key,
        ),
      );
  Future<Json> proposal(
    String tripId,
    int version,
    List<ServerActivity> activities,
    String source,
    String key,
  ) async => object(
    await client.request(
      'POST',
      'trips/$tripId/replanning-proposals',
      key: key,
      body: {
        'baseVersion': version,
        'reason': 'Traveler reviewed changes',
        'itinerary': {
          'activities': activities.map((a) => a.toDraft()).toList(),
          'source': source,
        },
      },
    ),
  );
  Future<List<Json>> proposals(String id) async =>
      objects(await client.request('GET', 'trips/$id/replanning-proposals'));
  Future<Json> decideProposal(
    String tripId,
    String id,
    bool approve,
  ) async => object(
    await client.request(
      'POST',
      'trips/$tripId/replanning-proposals/$id/${approve ? 'approve' : 'reject'}',
      body: <String, dynamic>{},
    ),
  );
  Future<List<Json>> places(
    String query, {
    int page = 0,
    CancelToken? cancel,
  }) async => objects(
    await client.request(
      'GET',
      'discovery/places',
      query: {'query': query, 'page': page, 'size': 20},
      cancel: cancel,
    ),
  );
  Future<Object?> discovery(String operation, Json query) =>
      client.request('GET', 'discovery/$operation', query: query);
  Future<Object?> guide(String operation, Json input) =>
      client.request('POST', 'guide/$operation', body: {'input': input});
  Future<Json> conversation() async => object(
    await client.request(
      'POST',
      'guide/conversations',
      body: <String, dynamic>{},
    ),
  );
  Future<Object?> message(String id, String text) => client.request(
    'POST',
    'guide/conversations/$id/messages',
    body: {'text': text},
  );
  Future<List<Json>> messages(String id, {int page = 0}) async => objects(
    await client.request(
      'GET',
      'guide/conversations/$id/messages',
      query: {'page': page},
    ),
  );
  Future<List<Json>> phrases() async =>
      objects(await client.request('GET', 'guide/phrases'));
  Future<Object?> savePhrase(String text) =>
      client.request('POST', 'guide/phrases', body: {'text': text});
  Future<Json> budget(
    String tripId,
    String amount,
    String currency,
    int version,
  ) async => object(
    await client.request(
      'PUT',
      'expenses/budget',
      body: {
        'tripId': tripId,
        'amount': decimalAmount(amount),
        'currency': currency,
        'version': version,
      },
    ),
  );
  Future<Json> summary(String tripId) async => object(
    await client.request('GET', 'expenses/summary', query: {'tripId': tripId}),
  );
  Future<List<Json>> expenses(String tripId, {int page = 0}) async => objects(
    await client.request(
      'GET',
      'expenses',
      query: {'tripId': tripId, 'page': page, 'size': 20},
    ),
  );
  Future<Json> addExpense(Json expense, String key) async =>
      object(await client.request('POST', 'expenses', body: expense, key: key));
  Future<List<Json>> splits(String id) async =>
      objects(await client.request('GET', 'expenses/$id/splits'));
  Future<Object?> currency(String from, String to, String amount) =>
      client.request(
        'GET',
        'expenses/currency',
        query: {'from': from, 'to': to, 'amount': decimalAmount(amount)},
      );
  Future<Json> upload(
    String path,
    Uint8List bytes,
    String name,
    String mime, {
    String? tripId,
    CancelToken? cancel,
    ProgressCallback? progress,
  }) async => object(
    await client.request(
      'POST',
      path,
      query: tripId == null ? null : {'tripId': tripId},
      cancel: cancel,
      progress: progress,
      body: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: name,
          contentType: DioMediaType.parse(mime),
        ),
      }),
    ),
  );
  Future<Json> extractReceipt(String id) async => object(
    await client.request(
      'POST',
      'expenses/receipts/$id/extract',
      body: <String, dynamic>{},
    ),
  );
  Future<Json> extractReservation(String id) async => object(
    await client.request(
      'POST',
      'reservations/documents/$id/extract',
      body: <String, dynamic>{},
    ),
  );
  Future<Json> confirmReservation(String id, Json body) async => object(
    await client.request(
      'POST',
      'reservations/documents/$id/confirm',
      body: body,
    ),
  );
  Future<Json> manualReservation(Json body, String key) async => object(
    await client.request('POST', 'reservations', body: body, key: key),
  );
  Future<List<Json>> reservations(String tripId, {int page = 0}) async =>
      objects(
        await client.request(
          'GET',
          'reservations',
          query: {'tripId': tripId, 'page': page},
        ),
      );
  Future<Uint8List> media(String path) async =>
      (await client.request('GET', path, binary: true)) as Uint8List;
  Future<List<Json>> members(String tripId) async =>
      objects(await client.request('GET', 'trips/$tripId/members'));
  Future<Object?> invite(String tripId, String accountId, String role) =>
      client.request(
        'POST',
        'trips/$tripId/invitations',
        body: {'accountId': accountId, 'role': role},
      );
  Future<Object?> acceptInvite(String tripId) => client.request(
    'POST',
    'trips/$tripId/invitations/accept',
    body: <String, dynamic>{},
  );
  Future<Object?> removeMember(String tripId, String accountId) =>
      client.request('DELETE', 'trips/$tripId/members/$accountId');
  Future<Object?> vote(String tripId, String activityId, int value) =>
      client.request(
        'POST',
        'trips/$tripId/votes',
        body: {'activityId': activityId, 'value': value},
      );
  Future<Object?> location(
    String tripId,
    bool enabled,
    double lat,
    double lon,
  ) => client.request(
    'PUT',
    'trips/$tripId/location',
    body: {'enabled': enabled, 'latitude': lat, 'longitude': lon},
  );
  Future<List<Json>> locations(String tripId) async =>
      objects(await client.request('GET', 'trips/$tripId/locations'));
  Future<Object?> contact(String tripId, String label, String phone) =>
      client.request(
        'POST',
        'trips/$tripId/contacts',
        body: {'label': label, 'phone': phone},
      );
  Future<List<Json>> journal(String tripId, {int page = 0}) async => objects(
    await client.request(
      'GET',
      'journal',
      query: {'tripId': tripId, 'page': page},
    ),
  );
  Future<Json> saveJournal(Json entry, String key, {String? id}) async =>
      object(
        await client.request(
          id == null ? 'POST' : 'PUT',
          id == null ? 'journal' : 'journal/$id',
          body: entry,
          key: id == null ? key : null,
        ),
      );
  Future<List<Json>> photos(String id) async =>
      objects(await client.request('GET', 'journal/$id/photos'));
  Future<Object?> visit(Json body) =>
      client.request('POST', 'journal/visits', body: body);
  Future<Object?> event(String tripId, Json body) =>
      client.request('POST', 'trips/$tripId/calendar/events', body: body);
  Future<Object?> syncCalendar(String tripId, String key) => client.request(
    'POST',
    'trips/$tripId/calendar/sync',
    body: <String, dynamic>{},
    key: key,
  );
  Future<List<Json>> journeys(String tripId) async => objects(
    await client.request(
      'GET',
      'discovery/journeys',
      query: {'tripId': tripId},
    ),
  );
  Future<Object?> saveJourney(Json body) =>
      client.request('POST', 'discovery/journeys', body: body);
  Future<List<Json>> deliveries({int page = 0}) async => objects(
    await client.request(
      'GET',
      'notifications/deliveries',
      query: {'page': page},
    ),
  );
  Future<Object?> reminder(String title, String dueAt) => client.request(
    'POST',
    'notifications/reminders',
    body: {'title': title, 'dueAt': dueAt},
  );
  Future<Object?> registerDevice(String token, String platform) =>
      client.request(
        'POST',
        'notifications/devices',
        body: {'token': token, 'platform': platform},
      );
  Future<Object?> unregisterDevice(String id) =>
      client.request('DELETE', 'notifications/devices/$id');
}
