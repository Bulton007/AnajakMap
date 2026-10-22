import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:anajak_travel/core/storage/travel_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/core/config/environment.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/app/app.dart';
import 'connected_contract_test.dart'
    show MemoryCredentials, Transport, response;
import 'ui_test.dart' show launch;

void main() {
  for (final locale in ['en', 'km']) {
    testWidgets('connected sign-in renders in $locale', (tester) async {
      final api = ApiClient(
        'https://example.test/api/v1/',
        MemoryCredentials(),
        transport: Dio()
          ..httpClientAdapter = Transport(
            (r) async => response({'emailDelivery': false}),
          ),
      );
      await launch(
        tester,
        route: '/connected',
        locale: locale,
        environment: const Environment(),
        api: api,
      );
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(AnajakApp),
        matchesGoldenFile('goldens/connected_login_$locale.png'),
      );
    });
  }
  testWidgets(
    'connected trip requires explicit approval and displays server errors',
    (tester) async {
      var drafts = 0, approvals = 0;
      final generationKeys = <String>[];
      final dio = Dio();
      final trip = {
        'id': 'trip',
        'title': 'Test trip',
        'destination': 'Phnom Penh',
        'timezone': 'Asia/Phnom_Penh',
        'startDate': '2026-10-04',
        'endDate': '2026-10-04',
        'version': 0,
      };
      dio.httpClientAdapter = Transport((r) async {
        if (r.path == 'auth/config') return response({'emailDelivery': false});
        if (r.path == 'profile') {
          return response({
            'id': 'account',
            'email': 'test@example.com',
            'preferences': {},
            'version': 0,
          });
        }
        if (r.path == 'runtime') {
          return response({'developmentProviders': true});
        }
        if (r.path == 'trips') {
          return response([trip]);
        }
        if (r.path == 'trips/trip') {
          return response(trip);
        }
        if (r.path == 'trips/trip/calendar') {
          return response({'activities': []});
        }
        if (r.path == 'discovery/places' || r.path == 'reservations') {
          return response([]);
        }
        if (r.path == 'guide/itinerary-jobs') {
          generationKeys.add(r.headers['Idempotency-Key'].toString());
          return response({
            'jobId': generationKeys.length == 1 ? 'failed-job' : 'job',
            'status': 'QUEUED',
          });
        }
        if (r.path == 'guide/jobs/failed-job') {
          return response({
            'job': {
              'ID': 'failed-job',
              'TRIP_ID': 'trip',
              'STATUS': 'FAILED',
              'ERROR_CODE': 'PROVIDER_FAILURE',
            },
            'result': {},
          });
        }
        if (r.path == 'guide/jobs/job') {
          return response({
            'job': {'ID': 'job', 'TRIP_ID': 'trip', 'STATUS': 'SUCCEEDED'},
            'result': {
              'source': 'Development fixture',
              'mock': true,
              'activities': [
                {
                  'title': 'Royal Palace',
                  'startsAt': '2026-10-04T02:00:00Z',
                  'endsAt': '2026-10-04T03:00:00Z',
                  'latitude': 11.5,
                  'longitude': 104.9,
                  'source': 'Fixture',
                },
              ],
            },
          });
        }
        if (r.path == 'trips/trip/itineraries') {
          drafts++;
          return response({'itineraryId': 'draft', 'version': 0});
        }
        if (r.path == 'trips/trip/itineraries/approve') {
          approvals++;
          return response({
            'code': 'VERSION_CONFLICT',
            'message': 'Trip changed elsewhere',
          }, status: 409);
        }
        if (r.path == 'trips/trip/itineraries/draft') {
          return response({
            'itinerary': {'STATUS': 'DRAFT'},
          });
        }
        throw StateError('Unexpected test request ${r.path}');
      });
      final store = MemoryCredentials()
        ..value = {'accessToken': 'access', 'refreshToken': 'refresh'};
      final api = ApiClient(
        'https://example.test/api/v1/',
        store,
        transport: dio,
      );
      final database = TravelDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await launch(
        tester,
        route: '/connected',
        environment: const Environment(),
        api: api,
        database: database,
      );
      await tester.ensureVisible(find.text('Test trip').first);
      await tester.tap(find.text('Test trip').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Request itinerary'));
      await tester.tap(find.text('Request itinerary'));
      await tester.pumpAndSettle();
      expect(drafts, 0);
      expect(approvals, 0);
      expect(find.text('Request itinerary'), findsOneWidget);
      await tester.tap(find.text('Request itinerary'));
      await tester.pumpAndSettle();
      expect(find.text('Generation failed'), findsOneWidget);
      expect(find.text('Back to my trip'), findsOneWidget);
      expect(drafts, 0);
      expect(approvals, 0);
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(generationKeys.length, 2);
      expect(generationKeys[0], isNot(generationKeys[1]));
      expect(find.text('Royal Palace'), findsOneWidget);
      expect(find.textContaining('Generation request:'), findsNothing);
      expect(find.text('Your itinerary is ready to review'), findsOneWidget);
      expect(drafts, 0);
      expect(approvals, 0);
      await tester.ensureVisible(find.text('Approve itinerary'));
      await tester.tap(find.text('Approve itinerary'));
      await tester.pumpAndSettle();
      expect(drafts, 1);
      expect(approvals, 1);
      expect(find.text('Trip changed elsewhere'), findsOneWidget);
      expect(find.text('The server confirmed your changes.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
