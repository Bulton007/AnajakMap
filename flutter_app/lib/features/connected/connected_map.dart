import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/models/server_models.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';

class ConnectedMap extends ConsumerWidget {
  const ConnectedMap({super.key, this.trip, this.places = const []});
  final ServerTrip? trip;
  final List<Json> places;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(environmentProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('map'))),
      body: env.tileUrl.isEmpty || env.tileAttribution.isEmpty
          ? PageBody(
              children: [
                Notice(context.t('mapConfig')),
                const SizedBox(height: 20),
                ServerResult(places),
              ],
            )
          : RemoteContent<List<Json>>(
              load: () => trip == null
                  ? Future.value(places)
                  : ref.read(repositoryProvider).map(trip!.id),
              builder: (rows, _) {
                final valid = rows
                    .where(
                      (r) =>
                          field(r, 'latitude') is num &&
                          field(r, 'longitude') is num,
                    )
                    .toList();
                if (valid.isEmpty) {
                  return EmptyState(
                    title: context.t('noResults'),
                    body: context.t('trySearch'),
                  );
                }
                LatLng point(Json p) => LatLng(
                  (field(p, 'latitude') as num).toDouble(),
                  (field(p, 'longitude') as num).toDouble(),
                );
                return Column(
                  children: [
                    Expanded(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: point(valid.first),
                          initialZoom: 12,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: env.tileUrl,
                            userAgentPackageName: 'com.anajak.anajak_travel',
                          ),
                          MarkerLayer(
                            markers: [
                              for (final p in valid)
                                Marker(
                                  point: point(p),
                                  width: 48,
                                  height: 48,
                                  child: IconButton.filled(
                                    tooltip: string(
                                      p,
                                      'name',
                                      string(p, 'title'),
                                    ),
                                    onPressed: () => showModalBottomSheet<void>(
                                      context: context,
                                      showDragHandle: true,
                                      builder: (_) => Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: SingleChildScrollView(
                                          child: ServerResult(p),
                                        ),
                                      ),
                                    ),
                                    icon: const Icon(Icons.place),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        env.tileAttribution,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
