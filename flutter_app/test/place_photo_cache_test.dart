import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/core/storage/travel_database.dart';
import 'package:anajak_travel/core/storage/place_photo_cache.dart';

void main() {
  late TravelDatabase db;
  setUp(() => db = TravelDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  final image = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  const url = 'https://upload.wikimedia.org/test.png';
  test('offline copy is isolated by backend and account', () async {
    var calls = 0;
    final cache = PlacePhotoCache(
      db,
      fetch: (_) async {
        calls++;
        return image;
      },
    );
    addTearDown(cache.dispose);
    expect(await cache.load('server|alice', url), image);
    expect(await cache.load('server|alice', url), image);
    expect(calls, 1);
    await cache.load('server|bob', url);
    expect(calls, 2);
    final offline = PlacePhotoCache(
      db,
      fetch: (_) async => throw Exception('offline'),
    );
    addTearDown(offline.dispose);
    expect(await offline.load('server|alice', url), image);
    expect(await offline.load('other-server|alice', url), isNull);
  });
  test(
    'unsafe hosts, oversized and corrupt images are not persisted',
    () async {
      var calls = 0;
      final cache = PlacePhotoCache(
        db,
        fetch: (_) async {
          calls++;
          return Uint8List(PlacePhotoCache.maxBytes + 1);
        },
      );
      addTearDown(cache.dispose);
      expect(
        await cache.load('s', 'http://upload.wikimedia.org/x.png'),
        isNull,
      );
      expect(await cache.load('s', 'https://private.example/x.png'), isNull);
      expect(calls, 0);
      expect(await cache.load('s', url), isNull);
      expect(await db.cached('s', 'photo:$url'), isNull);
      expect(cache.valid(Uint8List(20)), isFalse);
    },
  );
  test(
    'thumbnail cache stays bounded without deleting trip snapshots',
    () async {
      final cache = PlacePhotoCache(db, fetch: (_) async => image);
      addTearDown(cache.dispose);
      await db.cache('s', 'trip:keep', {'title': 'Keep'});
      for (var i = 0; i < 35; i++) {
        await cache.load('s', 'https://upload.wikimedia.org/$i.png');
      }
      expect((await db.cachedEntries('s', 'photo:')).length, 32);
      expect(await db.cached('s', 'trip:keep'), isNotNull);
    },
  );
}
