import 'package:flutter/material.dart';
import '../../shared/formatting/travel_dates.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../shared/components/components.dart';
import '../../shared/components/visual.dart';
import '../../shared/components/place_photo.dart';
import '../maps/open_map_screen.dart';
import 'package:url_launcher/url_launcher.dart';

String weatherSummary(Object? value, bool khmer) {
  final code = value is num ? value.toInt() : -1;
  final pair = switch (code) {
    0 => ('Clear sky', 'មេឃស្រឡះ'),
    1 || 2 => ('Partly cloudy', 'មានពពកខ្លះ'),
    3 => ('Overcast', 'មេឃពពក'),
    45 || 48 => ('Fog', 'អ័ព្ទ'),
    51 || 53 || 55 || 56 || 57 => ('Drizzle', 'ភ្លៀងរលឹម'),
    61 || 63 || 65 || 66 || 67 || 80 || 81 || 82 => ('Rain', 'ភ្លៀង'),
    71 || 73 || 75 || 77 || 85 || 86 => ('Snow', 'ព្រិល'),
    95 || 96 || 99 => ('Thunderstorm', 'ព្យុះផ្គររន្ទះ'),
    _ => ('Weather information unavailable', 'មិនមានព័ត៌មានអាកាសធាតុ'),
  };
  return khmer ? pair.$2 : pair.$1;
}

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
        if (field(value, 'weatherCode') != null)
          _Fact(
            icon: Icons.cloud_outlined,
            title: weatherSummary(field(value, 'weatherCode'), context.isKhmer),
          ),
        if (operation == 'weather' && string(value, 'updatedAt').isNotEmpty)
          _Fact(
            icon: Icons.update,
            title: travelDateTime(
              string(value, 'updatedAt'),
              locale: context.isKhmer ? 'km' : 'en',
            ),
            subtitle: context.isKhmer
                ? 'ទិន្នន័យពីអ្នកផ្ដល់សេវា · ឃ្លាំងសម្ងាត់រហូតដល់ ១៥ នាទី'
                : 'Provider observation · cached for up to 15 minutes',
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
        if (operation == 'weather' &&
            string(value, 'sourceUrl') == 'https://open-meteo.com/')
          TextButton.icon(
            onPressed: () => launchUrl(
              Uri.parse('https://open-meteo.com/'),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Weather data: Open-Meteo'),
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
