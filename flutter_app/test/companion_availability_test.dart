import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/features/connected/connected_tools.dart';
import 'package:anajak_travel/shared/models/server_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'connected_contract_test.dart'
    show MemoryCredentials, Transport, response;

void main() {
  for (final tool in ['expenses', 'reservations']) {
    testWidgets(
      '$tool keeps manual entry while unavailable AI scanning is disabled',
      (tester) async {
        await tester.runAsync(() => Strings.delegate.load(const Locale('en')));
        var guideRequests = 0;
        final api = ApiClient(
          'https://example.test/api/v1/',
          MemoryCredentials(),
          transport: Dio()
            ..httpClientAdapter = Transport((request) async {
              if (request.path.startsWith('guide/')) guideRequests++;
              if (request.path == 'expenses/summary') {
                return response({'budgets': [], 'balances': []});
              }
              return response([]);
            }),
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              repositoryProvider.overrideWithValue(TravelRepository(api)),
              guideCapabilitiesProvider.overrideWith(
                (ref) async => {'receipt': false, 'reservation': false},
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: [
                Strings.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: ConnectedTools(
                tool: tool,
                profile: const {'id': 'test'},
                trip: ServerTrip.fromJson({
                  'id': 'trip',
                  'title': 'Test trip',
                  'destination': 'Kampot',
                  'startDate': '2026-10-24',
                  'endDate': '2026-10-25',
                  'timezone': 'Asia/Phnom_Penh',
                  'version': 0,
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final actions = tester
            .widgetList<OutlinedButton>(find.byType(OutlinedButton))
            .toList();
        expect(actions.first.onPressed, isNotNull);
        expect(actions[1].onPressed, isNull);
        expect(
          find.textContaining('AI document scanning is not configured yet'),
          findsOneWidget,
        );
        expect(guideRequests, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
