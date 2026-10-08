import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anajak_travel/app/app.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/core/storage/app_state.dart';
import 'package:anajak_travel/core/storage/travel_database.dart';
import 'package:anajak_travel/features/connected/connected_shell.dart';
import 'package:anajak_travel/shared/models/server_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Samsung: UI sign-in, live backend and native persistence',
    (tester) async {
      const url = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8080/api/v1/',
      );
      // Separate credential key and cache scope protect any existing user session.
      final run = ApiClient.operationId();
      final store = SecureCredentialStore('device-test-$run');
      final api = ApiClient(url, store);
      final repo = TravelRepository(api);
      var db = TravelDatabase();
      final scope = 'device-test-$run';
      addTearDown(() async {
        await store.clear();
        await db.clear(scope);
        await db.close();
        api.dio.close();
      });
      const email = String.fromEnvironment('AUTH_TEST_EMAIL');
      const password = String.fromEnvironment('AUTH_TEST_PASSWORD');
      expect(
        email,
        isNotEmpty,
        reason:
            'Use a dedicated email-verified test account. Verification codes are delivered by email, never returned by the app API.',
      );
      expect(password, isNotEmpty);
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(preferences),
            apiProvider.overrideWithValue(api),
            databaseProvider.overrideWithValue(db),
          ],
          child: const AnajakApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), email);
      await tester.enterText(find.byType(TextField).at(1), password);
      final signIn = find.byType(FilledButton).first;
      await tester.ensureVisible(signIn);
      await tester.tap(signIn);
      for (
        var i = 0;
        i < 80 && find.byType(ConnectedShell).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.byType(ConnectedShell), findsOneWidget);
      expect(tester.takeException(), isNull);
      final profile = await repo.profile();
      expect((await repo.runtime())['developmentProviders'], true);
      expect(profile['email'], email.toLowerCase());
      final restored = ApiClient(url, store);
      await restored.restore();
      expect((await TravelRepository(restored).profile())['id'], profile['id']);
      restored.dio.close();

      final today = DateTime.now().toIso8601String().substring(0, 10);
      final body = <String, dynamic>{
        'title': 'Samsung device verification',
        'destination': 'Phnom Penh',
        'timezone': 'Asia/Phnom_Penh',
        'startDate': today,
        'endDate': today,
      };
      final key = ApiClient.operationId();
      final trip = await repo.createTrip(body, key);
      expect((await repo.createTrip(body, key)).id, trip.id);
      await repo.budget(trip.id, '100.00', 'USD', 0);
      final started = await repo.generate(trip.id, {
        'pace': 'relaxed',
      }, ApiClient.operationId());
      GenerationJob? job;
      for (var i = 0; i < 60; i++) {
        job = await repo.job(string(started, 'jobId'));
        if (job.finished) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(job!.status, 'SUCCEEDED');
      expect(job.tripId, trip.id);
      expect(job.activities, isNotEmpty);
      expect(objects((await repo.calendar(trip.id))['activities']), isEmpty);
      final draft = await repo.draft(
        trip.id,
        job.activities,
        string(job.result, 'source'),
        ApiClient.operationId(),
      );
      await expectLater(
        repo.approve(trip.id, string(draft, 'itineraryId'), 0, 99),
        throwsA(
          isA<ApiFailure>().having((e) => e.conflict, 'version conflict', true),
        ),
      );
      await repo.approve(
        trip.id,
        string(draft, 'itineraryId'),
        0,
        trip.version,
      );
      expect(objects((await repo.calendar(trip.id))['activities']), isNotEmpty);
      expect(await repo.map(trip.id), isNotEmpty);
      final expenseKey = ApiClient.operationId();
      final expense = <String, dynamic>{
        'tripId': trip.id,
        'description': 'Samsung test lunch',
        'amount': '12.50',
        'currency': 'USD',
        'splits': {profile['id'].toString(): '12.50'},
      };
      final saved = await repo.addExpense(expense, expenseKey);
      expect((await repo.addExpense(expense, expenseKey))['id'], saved['id']);
      expect(await repo.splits(string(saved, 'id')), hasLength(1));
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2ioAAAAASUVORK5CYII=',
      );
      final receipt = await repo.upload(
        'expenses/receipts',
        png,
        'device-receipt.png',
        'image/png',
        tripId: trip.id,
      );
      expect(
        (await repo.extractReceipt(
          string(receipt, 'id'),
        ))['requiresConfirmation'],
        true,
      );
      final booking = await repo.manualReservation({
        'tripId': trip.id,
        'provider': 'Device test',
        'reference': 'SAMSUNG-TEST',
        'timezone': 'Asia/Phnom_Penh',
        'startsAt': '${today}T15:00:00Z',
        'endsAt': '${today}T16:00:00Z',
      }, ApiClient.operationId());
      expect(booking['status'], 'CONFIRMED');
      final journal = await repo.saveJournal({
        'tripId': trip.id,
        'title': 'Samsung test',
        'content': 'Native Android verified',
        'recap': '',
        'version': 0,
      }, ApiClient.operationId());
      final photo = await repo.upload(
        'journal/${journal['id']}/photos',
        png,
        'device.png',
        'image/png',
      );
      expect(await repo.media('journal/photos/${photo['id']}/content'), png);
      expect(await repo.places('Phnom Penh'), isNotEmpty);

      final snapshot = await repo.snapshot(trip.id);
      await db.cache(scope, 'snapshot:${trip.id}', snapshot);
      final operation = ApiClient.operationId();
      await db.queue(scope, operation, 'expense', trip.id, expense);
      // Close and reopen the native SQLite database to verify durable offline data.
      await tester.pumpWidget(const SizedBox());
      await db.close();
      db = TravelDatabase();
      expect(
        (await db.cached(scope, 'snapshot:${trip.id}'))!['data'],
        snapshot,
      );
      expect(await db.pending(scope), hasLength(1));
      expect(await db.pending('$scope-other-user'), isEmpty);
      await db.remove(scope, operation);
      expect(await db.pending(scope), isEmpty);
      await api.logout();
      expect(await store.read(), isNull);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
