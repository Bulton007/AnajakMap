import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/environment.dart';
import '../storage/travel_database.dart';
import '../storage/place_photo_cache.dart';
import 'api_client.dart';
import 'travel_repository.dart';
import '../notifications/device_notifications.dart';

final environmentProvider = Provider((ref) => const Environment());
final apiProvider = Provider((ref) {
  final url = ref.watch(environmentProvider).normalizedUrl;
  final client = ApiClient(url, SecureCredentialStore(url));
  ref.onDispose(() => client.dio.close());
  return client;
});
final notificationUpdateProvider = Provider<Object>((ref) => Object());
final deviceNotificationsProvider = Provider((ref) => DeviceNotifications());
final travelerProvider = FutureProvider.autoDispose.family<Json, String>(
  (ref, id) => ref.watch(repositoryProvider).traveler(id),
);
final repositoryProvider = Provider(
  (ref) => TravelRepository(
    ref.watch(apiProvider),
    deviceNotifications: ref.watch(deviceNotificationsProvider),
  ),
);
final guideCapabilitiesProvider = FutureProvider.autoDispose<Json>(
  retry: (count, error) => null,
  (ref) async {
    // A failed status request is not evidence that a feature is unconfigured.
    // Preserve the error so the UI can offer a connection retry.
    return object(await ref.watch(repositoryProvider).guideCapabilities());
  },
);
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
