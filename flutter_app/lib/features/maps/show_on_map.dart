import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import 'open_map_screen.dart';

MapPlace? exploredMapPlace(Json place) {
  double? coordinate(String key) {
    final value = field(place, key);
    return value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
  }

  final latitude = coordinate('latitude');
  final longitude = coordinate('longitude');
  if (latitude == null || longitude == null) return null;
  final target = MapPlace(
    string(place, 'id'),
    string(place, 'name'),
    latitude,
    longitude,
  );
  return target.valid ? target : null;
}

class ShowOnMap extends StatelessWidget {
  const ShowOnMap({super.key, required this.place});
  final Json place;

  @override
  Widget build(BuildContext context) {
    final target = exploredMapPlace(place);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          icon: const Icon(Icons.map_outlined, size: 20),
          label: Text(
            context.isKhmer ? 'បើកដោយផ្ទាល់ក្នុងផែនទី' : 'Open directly in map',
          ),
          onPressed: target == null
              ? null
              : () => context.push('/map', extra: target),
        ),
        if (target == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.isKhmer
                  ? 'ទីតាំងនេះមិនមានកូអរដោនេត្រឹមត្រូវទេ។'
                  : 'Map location is unavailable for this place.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
