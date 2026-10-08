// Opt-in: flutter test test/live_backend_test.dart --dart-define=RUN_LIVE=true
// Uses a dedicated pre-verified test account and creates disposable travel records.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/shared/models/server_models.dart';
import 'connected_contract_test.dart' show MemoryCredentials;

void main() {
  test(
    'Flutter repositories communicate with all backend domains and Oracle',
    () async {
      const url = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://127.0.0.1:8080/api/v1/',
      );
      final api = ApiClient(url, MemoryCredentials());
      addTearDown(() => api.dio.close());
      final repo = TravelRepository(api);
      const email = String.fromEnvironment('AUTH_TEST_EMAIL');
      const password = String.fromEnvironment('AUTH_TEST_PASSWORD');
      expect(
        email,
        isNotEmpty,
        reason:
            'Provide a dedicated, already email-verified test account. Codes are no longer exposed by the app API.',
      );
      expect(password, isNotEmpty);
      await repo.auth('login', {'email': email, 'password': password});
      final profile = await repo.profile();
      expect(profile['email'], email.toLowerCase());
      expect((await repo.runtime())['developmentProviders'], true);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final key = ApiClient.operationId(),
          body = {
            'title': 'Flutter integration verification',
            'destination': 'Phnom Penh',
            'timezone': 'Asia/Phnom_Penh',
            'startDate': today,
            'endDate': today,
          };
      final trip = await repo.createTrip(body, key);
      expect((await repo.createTrip(body, key)).id, trip.id);
      await repo.budget(trip.id, '100.00', 'USD', 0);
      final started = await repo.generate(trip.id, {
        'pace': 'relaxed',
      }, ApiClient.operationId());
      GenerationJob? job;
      for (var i = 0; i < 60; i++) {
        job = await repo.job(string(started, 'jobId'));
        if (job.finished) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      expect(job!.status, 'SUCCEEDED');
      expect(job.tripId, trip.id);
      expect(job.activities, isNotEmpty);
      expect(
        objects((await repo.calendar(trip.id))['activities']),
        isEmpty,
        reason: 'Generation must not auto-approve.',
      );
      final draft = await repo.draft(
        trip.id,
        job.activities,
        string(job.result, 'source'),
        ApiClient.operationId(),
      );
      await expectLater(
        repo.approve(trip.id, string(draft, 'itineraryId'), 0, 99),
        throwsA(isA<ApiFailure>().having((e) => e.conflict, 'conflict', true)),
      );
      await repo.approve(
        trip.id,
        string(draft, 'itineraryId'),
        0,
        trip.version,
      );
      expect(objects((await repo.calendar(trip.id))['activities']), isNotEmpty);
      expect(await repo.map(trip.id), isNotEmpty);
      final updated = await repo.trip(trip.id);
      await expectLater(
        repo.syncTrip(trip.id, trip.version, body),
        throwsA(
          isA<ApiFailure>().having((e) => e.conflict, 'stale trip', true),
        ),
      );
      final expenseKey = ApiClient.operationId(),
          expense = {
            'tripId': trip.id,
            'description': 'Lunch',
            'amount': '12.50',
            'currency': 'USD',
            'splits': {profile['id'].toString(): '12.50'},
          };
      final saved = await repo.addExpense(expense, expenseKey);
      expect((await repo.addExpense(expense, expenseKey))['id'], saved['id']);
      expect(await repo.splits(string(saved, 'id')), hasLength(1));
      expect(
        objects((await repo.summary(trip.id))['spentByCurrency']),
        isNotEmpty,
      );
      final start = '${today}T15:00:00Z', end = '${today}T16:00:00Z';
      final booking = await repo.manualReservation({
        'tripId': trip.id,
        'provider': 'Traveler entry',
        'reference': 'FLUTTER-TEST',
        'timezone': 'Asia/Phnom_Penh',
        'startsAt': start,
        'endsAt': end,
      }, ApiClient.operationId());
      expect(booking['status'], 'CONFIRMED');
      expect(await repo.reservations(trip.id), isNotEmpty);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2ioAAAAASUVORK5CYII=',
      );
      final receipt = await repo.upload(
        'expenses/receipts',
        png,
        'receipt.png',
        'image/png',
        tripId: trip.id,
      );
      expect(
        (await repo.extractReceipt(
          string(receipt, 'id'),
        ))['requiresConfirmation'],
        true,
      );
      final doc = await repo.upload(
        'reservations/documents',
        png,
        'booking.png',
        'image/png',
        tripId: trip.id,
      );
      expect(
        (await repo.extractReservation(
          string(doc, 'documentId'),
        ))['extraction'],
        isNotNull,
      );
      final entry = await repo.saveJournal({
        'tripId': trip.id,
        'title': 'First day',
        'content': 'Visited the palace',
        'recap': '',
        'version': 0,
      }, ApiClient.operationId());
      final photo = await repo.upload(
        'journal/${entry['id']}/photos',
        png,
        'travel.png',
        'image/png',
      );
      expect(await repo.media('journal/photos/${photo['id']}/content'), png);
      expect(await repo.journal(trip.id), hasLength(1));
      await repo.guide('recap', {'text': 'Visited the palace'});
      expect(
        string((await repo.journal(trip.id)).first, 'recap'),
        isEmpty,
        reason: 'A recap suggestion must not overwrite the journal.',
      );
      expect(await repo.places('Phnom Penh'), isNotEmpty);
      await repo.guide('translation', {
        'text': 'Hello',
        'targetLanguage': 'km',
      });
      await repo.savePhrase('សួស្តី');
      expect(await repo.phrases(), isNotEmpty);
      await repo.contact(trip.id, 'Hotel', '+85512345678');
      expect(objects((await repo.snapshot(trip.id))['contacts']), isNotEmpty);
      expect(await repo.members(trip.id), hasLength(1));
      await repo.location(trip.id, true, 11.56, 104.93);
      expect(await repo.locations(trip.id), isNotEmpty);
      await repo.location(trip.id, false, 0, 0);
      expect(await repo.locations(trip.id), isEmpty);
      await repo.saveJourney({
        'tripId': trip.id,
        'origin': 'Airport',
        'destination': 'Hotel',
        'departure': start,
        'arrival': end,
        'timezone': 'Asia/Phnom_Penh',
        'transferDetails': 'Meet at arrivals',
        'source': 'Traveler',
      });
      expect(await repo.journeys(trip.id), isNotEmpty);
      await repo.reminder(
        'Review itinerary',
        DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String(),
      );
      expect(await repo.deliveries(), isNotEmpty);
      expect(updated.version, greaterThan(trip.version));
      await api.logout();
      expect(api.authenticated, false);
    },
    skip: !const bool.fromEnvironment('RUN_LIVE'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
