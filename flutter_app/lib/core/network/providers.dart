import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/environment.dart';
import '../storage/travel_database.dart';
import '../storage/place_photo_cache.dart';
import 'api_client.dart';
import 'travel_repository.dart';

final environmentProvider = Provider((ref) => const Environment());
final apiProvider = Provider((ref) {
  final url = ref.watch(environmentProvider).normalizedUrl;
  final client = ApiClient(url, SecureCredentialStore(url));
  ref.onDispose(() => client.dio.close());
  return client;
});
final repositoryProvider = Provider(
  (ref) => TravelRepository(ref.watch(apiProvider)),
);
final guideCapabilitiesProvider = FutureProvider.autoDispose<Json>((ref) async {
  try {
    return object(await ref.watch(repositoryProvider).guideCapabilities());
  } catch (_) {
    return {'vision': false, 'voice': false};
  }
});
final databaseProvider = Provider((ref) {
  final db = TravelDatabase();
  ref.onDispose(() => db.close());
  return db;
});
final placePhotoCacheProvider = Provider((ref) {
  final cache = PlacePhotoCache(ref.watch(databaseProvider));
  ref.onDispose(cache.dispose);
  return cache;
});
String accountScope(Ref ref, String accountId) =>
    '${ref.read(environmentProvider).normalizedUrl}|$accountId';
