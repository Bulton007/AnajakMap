import 'package:anajak_travel/app/localization/strings.dart';
import 'package:anajak_travel/core/network/api_client.dart';
import 'package:anajak_travel/core/network/providers.dart';
import 'package:anajak_travel/core/network/travel_repository.dart';
import 'package:anajak_travel/features/connected/trip_chat.dart';
import 'package:anajak_travel/features/connected/trip_invitations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'connected_contract_test.dart' show MemoryCredentials;

class TestRepository extends TravelRepository {
  TestRepository()
    : super(ApiClient('https://example.test/api/v1/', MemoryCredentials()));

  bool pending = true;
  final chatRows = <Json>[];

  @override
  Future<List<Json>> pendingInvitations() async => [
    if (pending)
      {'TRIP_ID': 'trip', 'TITLE': 'Weekend trip', 'DESTINATION': 'Kampot'},
  ];

  @override
  Future<Object?> acceptInvite(String tripId) async {
    expect(tripId, 'trip');
    pending = false;
    return {'status': 'JOINED'};
  }

  @override
  Future<List<Json>> tripMessages(String tripId, {int page = 0}) async =>
      List.of(chatRows);

  @override
  Future<Object?> sendTripMessage(
    String tripId,
    String text,
    String key,
  ) async {
    expect(tripId, 'trip');
    chatRows.insert(0, {'SENDER_ID': 'owner', 'MESSAGE': text});
    return {'id': 'message'};
  }
}

Future<void> show(WidgetTester tester, TestRepository repo, Widget page) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          apiProvider.overrideWithValue(repo.client),
        ],
        child: MaterialApp(
          localizationsDelegates: const [Strings.delegate],
          home: page,
        ),
      ),
    );

void main() {
  testWidgets('accepts a listed invitation without typing a trip ID', (
    tester,
  ) async {
    final repo = TestRepository();
    var accepted = 0;
    await show(tester, repo, TripInvitations(onAccepted: () => accepted++));
    await tester.pumpAndSettle();
    expect(find.text('Weekend trip'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(accepted, 1);
    expect(find.text('No pending invitations'), findsOneWidget);
  });

  testWidgets('sends a message and shows it in chat history', (tester) async {
    final repo = TestRepository();
    await show(
      tester,
      repo,
      const TripChat(tripId: 'trip', accountId: 'owner'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Meet at the station');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(find.text('Meet at the station'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
