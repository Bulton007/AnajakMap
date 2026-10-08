import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/core/storage/travel_database.dart';
import 'package:anajak_travel/shared/models/server_models.dart';

class MemoryCredentials implements CredentialStore {
  Json? value;
  @override
  Future<Json?> read() async => value;
  @override
  Future<void> write(Json tokens) async {
    value = tokens;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class Transport implements HttpClientAdapter {
  Transport(this.handler);
  final Future<ResponseBody> Function(RequestOptions) handler;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) => handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody response(Object? data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(status == 200 ? {'data': data} : data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

void main() {
  test(
    'exact decimals and Oracle projections preserve money and coordinates',
    () {
      expect(decimalAmount('00012.5'), '12.50');
      expect(decimalAmount('999999999999.99'), '999999999999.99');
      for (final value in ['0', '-1', 'NaN', '1.234', '1e3']) {
        expect(() => decimalAmount(value), throwsFormatException);
      }
      final a = ServerActivity.fromJson({
        'ID': 'a',
        'TITLE': 'Palace',
        'STARTS_AT': '2026-10-04T01:00:00Z',
        'ENDS_AT': '2026-10-04T02:00:00Z',
        'LATITUDE': 11.5,
        'LONGITUDE': 104.9,
        'SOURCE': 'Fixture',
      });
      expect(a.toDraft()['latitude'], 11.5);
      expect(a.startsAt, '2026-10-04T01:00:00Z');
      expect(
        GenerationJob.fromJson({
          'job': {'ID': 'j', 'TRIP_ID': 't', 'STATUS': 'SUCCEEDED'},
          'result': {'activities': []},
        }).tripId,
        't',
      );
    },
  );
  test(
    'API configuration rejects insecure remote hosts and embedded credentials',
    () {
      expect(
        const Environment(apiUrl: 'http://10.0.2.2:8080/api/v1').normalizedUrl,
        'http://10.0.2.2:8080/api/v1/',
      );
      for (final url in [
        'http://example.com/api/v1',
        'https://user:pass@example.com',
        'https://example.com?q=secret',
      ]) {
        expect(
          () => Environment(apiUrl: url).normalizedUrl,
          throwsFormatException,
        );
      }
    },
  );
  test(
    'concurrent expiry refreshes once and preserves the account offline profile',
    () async {
      int refreshes = 0;
      final dio = Dio();
      dio.httpClientAdapter = Transport((request) async {
        if (request.path == 'auth/refresh') {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return response({'accessToken': 'new', 'refreshToken': 'rotated'});
        }
        if (request.headers['Authorization'] == 'Bearer old') {
          return response({'message': 'Expired'}, status: 401);
        }
        return response({'id': 'account'});
      });
      final store = MemoryCredentials();
      final api = ApiClient(
        'https://example.test/api/v1/',
        store,
        transport: dio,
      );
      await api.acceptTokens({'accessToken': 'old', 'refreshToken': 'refresh'});
      await api.rememberProfile({'id': 'account'});
      final result = await Future.wait([
        api.request('GET', 'profile'),
        api.request('GET', 'profile'),
      ]);
      expect(refreshes, 1);
      expect(result.length, 2);
      expect(api.cachedProfile?['id'], 'account');
      expect(store.value?['refreshToken'], 'rotated');
    },
  );
  test(
    'approval sends both draft and trip versions; failures stay failures',
    () async {
      Json? sent;
      final dio = Dio();
      dio.httpClientAdapter = Transport((request) async {
        sent = object(request.data);
        return response({
          'code': 'VERSION_CONFLICT',
          'message': 'Changed',
          'traceId': 'trace',
        }, status: 409);
      });
      final repo = TravelRepository(
        ApiClient(
          'https://example.test/api/v1/',
          MemoryCredentials(),
          transport: dio,
        ),
      );
      await expectLater(
        repo.approve('trip', 'draft', 3, 8),
        throwsA(isA<ApiFailure>().having((e) => e.conflict, 'conflict', true)),
      );
      expect(sent, {'itineraryId': 'draft', 'version': 3, 'baseVersion': 8});
    },
  );
  test('outbox preserves conflicts and isolates accounts', () async {
    final db = TravelDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.cache('server|a', 'trip:one', {
      'trip': {'id': 'one'},
    });
    await db.queue('server|a', 'operation', 'trip', 'one', {
      'baseVersion': 4,
      'trip': {'title': 'Local'},
    });
    await db.mark('server|a', 'operation', 'conflict', 'Changed elsewhere');
    expect(await db.pending('server|b'), isEmpty);
    expect(await db.cached('other-server|a', 'trip:one'), isNull);
    final pending = await db.pending('server|a');
    expect(pending.single['state'], 'conflict');
    expect(object(pending.single['body'])['baseVersion'], 4);
    await db.remove('server|b', 'operation');
    expect(await db.pending('server|a'), hasLength(1));
    await db.remove('server|a', 'operation');
    expect(await db.pending('server|a'), isEmpty);
  });
  test('offline sign-out clears device credentials even if revocation fails',()async{
    final dio=Dio();dio.httpClientAdapter=Transport((r)async=>throw DioException(requestOptions:r,type:DioExceptionType.connectionError));
    final store=MemoryCredentials();final api=ApiClient('https://example.test/api/v1/',store,transport:dio);
    await api.acceptTokens({'accessToken':'access','refreshToken':'refresh'});
    await expectLater(api.logout(),throwsA(isA<ApiFailure>()));
    expect(api.authenticated,false);expect(store.value,isNull);
  });
}
