import '../../core/network/api_client.dart';

/// Server-owned account progress. Never imports device-local practice balances.
class AdventureSnapshot {
  AdventureSnapshot(this.data) {
    if (data['profile'] is! Map || data['monsters'] is! List) {
      throw const ApiFailure('CONTRACT', 'Invalid adventure response.');
    }
  }
  final Json data;
  Json get profile => object(data['profile']);
  List<Json> get monsters => objects(data['monsters']);
  List<Json> get species => objects(data['species']);
  List<Json> get quests => objects(data['quests']);
  List<Json> get ledger => objects(data['ledger']);
  List<Json> get party => objects(data['party']);
  List<Json> get inventory => objects(data['inventory']);
  List<Json> get achievements => objects(data['achievements']);
  List<Json> get exploration => objects(data['exploration']);
  List<Json> get history => objects(data['history']);
  Json? get active =>
      data['activeSession'] == null ? null : object(data['activeSession']);
  Json speciesFor(String id) =>
      species.firstWhere((s) => string(s, 'id') == id, orElse: () => {});
}

class AdventureRepository {
  AdventureRepository(this.api);
  final ApiClient api;
  Future<Json> capabilities() async =>
      object(await api.request('GET', 'rpg/capabilities'));
  Future<List<Json>> world(String realm) async =>
      objects(await api.request('GET', 'rpg/$realm/world'));
  Future<AdventureSnapshot> profile(String realm) async =>
      AdventureSnapshot(object(await api.request('GET', 'rpg/$realm/profile')));
  Future<Json> mutate(String path, Json body, String key) async =>
      object(await api.request('POST', 'rpg/$path', body: body, key: key));
}
