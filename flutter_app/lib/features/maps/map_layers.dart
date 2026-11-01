import 'dart:math' as math;
import 'package:flutter/material.dart';

enum MapLayerId { standard, terrain, traffic, transit, biking }

/// A map style is selectable only when it has real tiles and their attribution.
/// Unavailable styles never replace the current map or imply a live data feed.
@immutable
class MapLayerDefinition {
  const MapLayerDefinition({
    required this.id,
    this.tileUrl,
    this.attribution = '',
    this.attributionUrl = 'https://www.openstreetmap.org/copyright',
    this.providerName = '',
    this.maxNativeZoom = 19,
  });

  final MapLayerId id;
  final String? tileUrl;
  final String attribution, attributionUrl, providerName;
  final int maxNativeZoom;

  bool get available {
    final template = tileUrl;
    final uri = template == null ? null : Uri.tryParse(template);
    final credit = Uri.tryParse(attributionUrl);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        ['{z}', '{x}', '{y}'].every(template!.contains) &&
        attribution.trim().isNotEmpty &&
        credit != null &&
        credit.scheme == 'https' &&
        credit.hasAuthority &&
        credit.userInfo.isEmpty &&
        maxNativeZoom > 0;
  }
}

List<MapLayerDefinition> buildMapLayerDefinitions({
  required String standardUrl,
  required String standardAttribution,
  String standardAttributionUrl = 'https://www.openstreetmap.org/copyright',
  String standardProviderName = 'OpenStreetMap',
  String terrainUrl = 'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
  String terrainAttribution =
      '© OpenStreetMap contributors · SRTM · © OpenTopoMap (CC-BY-SA)',
  String terrainAttributionUrl = 'https://opentopomap.org/about',
  String terrainProviderName = 'OpenTopoMap',
  int terrainMaxNativeZoom = 17,
  String bikingUrl =
      'https://a.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
  String bikingAttribution = '© CyclOSM · © OpenStreetMap contributors',
  String bikingAttributionUrl = 'https://www.cyclosm.org/',
  String bikingProviderName = 'CyclOSM',
  int bikingMaxNativeZoom = 19,
}) => [
  MapLayerDefinition(
    id: MapLayerId.standard,
    tileUrl: standardUrl,
    attribution: standardAttribution,
    attributionUrl: standardAttributionUrl,
    providerName: standardProviderName,
  ),
  MapLayerDefinition(
    id: MapLayerId.terrain,
    tileUrl: terrainUrl,
    attribution: terrainAttribution,
    attributionUrl: terrainAttributionUrl,
    providerName: terrainProviderName,
    maxNativeZoom: terrainMaxNativeZoom,
  ),
  const MapLayerDefinition(id: MapLayerId.traffic),
  const MapLayerDefinition(id: MapLayerId.transit),
  MapLayerDefinition(
    id: MapLayerId.biking,
    tileUrl: bikingUrl,
    attribution: bikingAttribution,
    attributionUrl: bikingAttributionUrl,
    providerName: bikingProviderName,
    maxNativeZoom: bikingMaxNativeZoom,
  ),
];

String mapLayerLabel(BuildContext context, MapLayerId id) {
  final khmer = Localizations.localeOf(context).languageCode == 'km';
  return switch (id) {
    MapLayerId.standard => khmer ? 'ផែនទី' : 'Map',
    MapLayerId.terrain => khmer ? 'ភូមិសាស្ត្រ' : 'Terrain',
    MapLayerId.traffic => khmer ? 'ចរាចរណ៍' : 'Traffic',
    MapLayerId.transit => khmer ? 'ដឹកជញ្ជូន' : 'Transit',
    MapLayerId.biking => khmer ? 'ជិះកង់' : 'Biking',
  };
}

class MapLayersButton extends StatelessWidget {
  const MapLayersButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 3,
    shadowColor: Colors.black26,
    color: Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: IconButton(
      key: const ValueKey('map-layer-toggle'),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      tooltip: Localizations.localeOf(context).languageCode == 'km'
          ? 'ស្រទាប់ផែនទី'
          : 'Map layers',
      onPressed: onPressed,
      icon: const Icon(Icons.layers_outlined),
    ),
  );
}

Future<MapLayerDefinition?> showMapLayerPicker(
  BuildContext context, {
  required List<MapLayerDefinition> layers,
  required MapLayerId selected,
}) => showModalBottomSheet<MapLayerDefinition>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => MapLayerTray(layers: layers, selected: selected),
);

/// Horizontal previews keep the map-style picker compact on a phone. The
/// previews are illustrations, not fetched tiles or simulated live traffic.
class MapLayerTray extends StatefulWidget {
  const MapLayerTray({
    super.key,
    required this.layers,
    required this.selected,
    this.onSelected,
  });
  final List<MapLayerDefinition> layers;
  final MapLayerId selected;
  final ValueChanged<MapLayerDefinition>? onSelected;

  @override
  State<MapLayerTray> createState() => _MapLayerTrayState();
}

class _MapLayerTrayState extends State<MapLayerTray> {
  MapLayerId? unavailable;
  bool details = false;
  bool get khmer => Localizations.localeOf(context).languageCode == 'km';
  String text(String en, String km) => khmer ? km : en;

  String get unavailableText => switch (unavailable) {
    MapLayerId.traffic => text(
      'Live traffic is not available. Driving times are estimates without live traffic.',
      'មិនមានចរាចរណ៍ផ្ទាល់ទេ។ ពេលវេលាបើកបរជាការប៉ាន់ស្មានដោយគ្មានចរាចរណ៍ផ្ទាល់។',
    ),
    MapLayerId.transit => text(
      'Transit maps are not available. Directions currently support driving.',
      'មិនមានផែនទីដឹកជញ្ជូនទេ។ ទិសដៅបច្ចុប្បន្នគាំទ្រការបើកបរ។',
    ),
    _ => text(
      'This map style is not available yet. Your current map stays selected.',
      'ស្រទាប់ផែនទីនេះមិនទាន់មានទេ។ ផែនទីបច្ចុប្បន្ននៅតែត្រូវបានជ្រើស។',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final itemWidth = math.max(84.0, scaler.scale(84).clamp(84.0, 200.0));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            key: const ValueKey('map-layer-tray'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      text('Map layers', 'ស្រទាប់ផែនទី'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('map-layer-close'),
                    tooltip: text('Close', 'បិទ'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                key: const ValueKey('map-layer-options-scroll'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final layer in widget.layers)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _LayerChoice(
                          width: itemWidth,
                          layer: layer,
                          selected: widget.selected == layer.id,
                          onPressed: () {
                            if (!layer.available) {
                              setState(() {
                                unavailable = layer.id;
                                details = false;
                              });
                              return;
                            }
                            if (widget.onSelected != null) {
                              widget.onSelected!(layer);
                            } else {
                              Navigator.of(context).pop(layer);
                            }
                          },
                        ),
                      ),
                    SizedBox(
                      width: itemWidth,
                      child: _MoreChoice(
                        expanded: details,
                        onPressed: () => setState(() {
                          details = !details;
                          unavailable = null;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              if (unavailable != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    key: const ValueKey('map-layer-unavailable'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 10),
                        Expanded(child: Text(unavailableText)),
                      ],
                    ),
                  ),
                ),
              ],
              if (details) ...[
                const SizedBox(height: 16),
                Text(
                  text(
                    'Map styles change the view, not the calculated driving route.',
                    'ស្រទាប់ផែនទីផ្លាស់ប្ដូរទិដ្ឋភាព មិនមែនផ្លូវបើកបរដែលបានគណនាទេ។',
                  ),
                ),
                for (final layer in widget.layers.where((l) => l.available))
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.copyright_outlined, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${mapLayerLabel(context, layer.id)}${layer.providerName.isEmpty ? '' : ' · ${layer.providerName}'}\n${layer.attribution}',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LayerChoice extends StatelessWidget {
  const _LayerChoice({
    required this.width,
    required this.layer,
    required this.selected,
    required this.onPressed,
  });
  final double width;
  final MapLayerDefinition layer;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = mapLayerLabel(context, layer.id);
    final unavailable = Localizations.localeOf(context).languageCode == 'km'
        ? 'មិនទាន់មាន'
        : 'Unavailable';
    return Semantics(
      selected: selected,
      button: true,
      onTap: onPressed,
      label: '$label${layer.available ? '' : ', $unavailable'}',
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('map-layer-${layer.id.name}'),
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 64,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: selected ? colors.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(painter: _LayerPreview(layer.id)),
                          if (!layer.available)
                            ColoredBox(
                              color: colors.surface.withValues(alpha: .7),
                              child: Icon(
                                Icons.block_outlined,
                                color: colors.onSurfaceVariant,
                                size: 22,
                              ),
                            ),
                          if (selected)
                            Align(
                              alignment: Alignment.bottomRight,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check,
                                  size: 16,
                                  color: colors.onPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? colors.primary : colors.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (!layer.available)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        unavailable,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreChoice extends StatelessWidget {
  const _MoreChoice({required this.expanded, required this.onPressed});
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      key: const ValueKey('map-layer-more'),
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(expanded ? Icons.expand_less : Icons.layers_outlined),
            ),
            const SizedBox(height: 4),
            Text(
              Localizations.localeOf(context).languageCode == 'km'
                  ? 'បន្ថែម'
                  : 'More',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

class _LayerPreview extends CustomPainter {
  const _LayerPreview(this.layer);
  final MapLayerId layer;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final terrain = layer == MapLayerId.terrain;
    canvas.drawRect(
      rect,
      Paint()
        ..color = terrain ? const Color(0xFFD4DBC4) : const Color(0xFFE8EEE8),
    );
    if (terrain) {
      for (var i = 0; i < 5; i++) {
        final contour = Path()
          ..moveTo(-8 + i * 7, size.height)
          ..cubicTo(
            size.width * .8,
            size.height * .7,
            -4 + i * 5,
            size.height * .3,
            size.width + 12,
            -8 + i * 9,
          );
        canvas.drawPath(
          contour,
          Paint()
            ..color = i.isEven
                ? const Color(0xFF9EAD86)
                : const Color(0xFFB8C29D)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8,
        );
      }
    } else {
      canvas.drawCircle(
        Offset(size.width * .8, size.height * .2),
        size.width * .32,
        Paint()..color = const Color(0xFFCAE5D5),
      );
      final river = Path()
        ..moveTo(size.width * .72, -4)
        ..cubicTo(
          size.width * .35,
          size.height * .4,
          size.width * .9,
          size.height * .65,
          size.width * .6,
          size.height + 4,
        );
      canvas.drawPath(
        river,
        Paint()
          ..color = const Color(0xFF9BCFDE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8,
      );
    }
    final road = Path()
      ..moveTo(-4, size.height * .8)
      ..lineTo(size.width * .47, size.height * .44)
      ..lineTo(size.width * .52, -4);
    canvas.drawPath(
      road,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );
    canvas.drawPath(
      road,
      Paint()
        ..color = layer == MapLayerId.biking
            ? const Color(0xFF61A27A)
            : const Color(0xFFBFC8CD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    if (layer == MapLayerId.biking) {
      canvas.drawCircle(
        Offset(size.width * .57, size.height * .58),
        12,
        Paint()..color = Colors.white,
      );
      final icon = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.pedal_bike.codePoint),
          style: TextStyle(
            color: const Color(0xFF277245),
            fontSize: 19,
            fontFamily: Icons.pedal_bike.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      icon.paint(
        canvas,
        Offset(size.width * .57 - 9.5, size.height * .58 - 9.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LayerPreview oldDelegate) =>
      oldDelegate.layer != layer;
}
