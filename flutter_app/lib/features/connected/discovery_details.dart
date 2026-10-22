import 'package:flutter/material.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/components/visual.dart';
import '../../shared/components/place_photo.dart';
import '../maps/open_map_screen.dart';

class PlaceFacts extends StatelessWidget {
  const PlaceFacts({super.key, required this.place});
  final Json place;
  @override
  Widget build(BuildContext context) {
    final lat = field(place, 'latitude'), lon = field(place, 'longitude');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (place['photo'] is Map) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: PlacePhoto(
              name: string(place, 'name'),
              photo: object(place['photo']),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (lat is num && lon is num)
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 220,
              child: TravelOpenMap(
                places: [
                  MapPlace(
                    string(place, 'id'),
                    string(place, 'name'),
                    lat.toDouble(),
                    lon.toDouble(),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        _Fact(
          icon: Icons.category_outlined,
          title: string(
            place,
            'category',
            context.t('destination'),
          ).replaceAll('_', ' '),
        ),
        if (string(place, 'address').isNotEmpty)
          _Fact(
            icon: Icons.location_on_outlined,
            title: string(place, 'address'),
          ),
        if (field(place, 'mock') == true)
          _Fact(
            icon: Icons.science_outlined,
            title: context.isKhmer ? 'ទិន្នន័យគំរូ' : 'Sample destination',
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            string(place, 'source', context.t('sourceUnknown')),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class DiscoveryDetails extends StatelessWidget {
  const DiscoveryDetails({
    super.key,
    required this.operation,
    required this.query,
    required this.data,
  });
  final String operation, query;
  final Object? data;
  @override
  Widget build(BuildContext context) {
    final value = object(data);
    final sample = field(value, 'mock') == true;
    return PageBody(
      children: [
        if (operation == 'culture')
          SizedBox(
            width: double.infinity,
            child: VisualHero(
              title: context.t('culture'),
              caption: context.t('cambodia'),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Icon(
                  featureIcon(operation),
                  size: 64,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
                const SizedBox(height: 12),
                Text(query, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        const SizedBox(height: 20),
        if (sample)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Pill(
              context.isKhmer
                  ? 'ទិន្នន័យគំរូ · មិនមែនទិន្នន័យផ្ទាល់'
                  : 'Sample information · not live local data',
              icon: Icons.science_outlined,
            ),
          ),
        if (field(value, 'guidance') != null)
          _Fact(
            icon: Icons.temple_buddhist_outlined,
            title: string(value, 'guidance'),
          ),
        for (final dish in (field(value, 'dishes') as List? ?? const []))
          _Fact(icon: Icons.restaurant_rounded, title: '$dish'),
        if (field(value, 'dietaryGuidance') != null)
          _Fact(
            icon: Icons.info_outline,
            title: string(value, 'dietaryGuidance'),
          ),
        if (field(value, 'temperatureCelsius') != null)
          _Fact(
            icon: Icons.thermostat_rounded,
            title: '${field(value, 'temperatureCelsius')} °C',
            subtitle: string(value, 'condition'),
          ),
        if (field(value, 'durationMinutes') != null)
          _Fact(
            icon: Icons.schedule_rounded,
            title:
                '${field(value, 'durationMinutes')} ${context.isKhmer ? 'នាទី' : 'minutes'}',
            subtitle: context.isKhmer
                ? 'រយៈពេលប៉ាន់ស្មាន'
                : 'Estimated duration',
          ),
        if (field(value, 'estimatedCost') != null)
          _Fact(
            icon: Icons.payments_outlined,
            title:
                '${field(value, 'estimatedCost')} ${string(value, 'currency')}',
            subtitle: context.isKhmer ? 'តម្លៃប៉ាន់ស្មាន' : 'Estimated cost',
          ),
        if (value.isEmpty)
          _Fact(icon: Icons.search_off_rounded, title: context.t('noResults')),
        if (string(value, 'source').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              string(value, 'source'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
