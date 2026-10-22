import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/models/server_models.dart';
import '../../shared/components/remote.dart';
import '../maps/open_map_screen.dart';
import 'discovery_details.dart';

class ConnectedMap extends ConsumerWidget {
  const ConnectedMap({super.key, this.trip, this.places = const []});
  final ServerTrip? trip;
  final List<Json> places;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(context.t('map'))),
    body: SafeArea(
      child: RemoteContent<List<Json>>(
        load: () => trip == null
            ? Future.value(places)
            : ref.read(repositoryProvider).map(trip!.id),
        builder: (rows, _) => TravelOpenMap(
          onPlaceSelected: (place) => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (_) => Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    PlaceFacts(place: rows[int.parse(place.id)]),
                  ],
                ),
              ),
            ),
          ),
          places: [
            for (final (index, row) in rows.indexed)
              if (field(row, 'latitude') is num &&
                  field(row, 'longitude') is num)
                MapPlace(
                  '$index',
                  string(row, 'name', string(row, 'title')),
                  (field(row, 'latitude') as num).toDouble(),
                  (field(row, 'longitude') as num).toDouble(),
                ),
          ],
        ),
      ),
    ),
  );
}
