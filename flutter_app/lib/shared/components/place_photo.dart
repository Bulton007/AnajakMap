import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PlacePhoto extends StatelessWidget {
  const PlacePhoto({super.key, required this.name, this.photo});
  final String name;
  final Map<String, dynamic>? photo;

  Widget fallback(BuildContext context) => Container(
    height: 150,
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Center(
      child: Icon(
        Icons.landscape_outlined,
        size: 56,
        semanticLabel: Localizations.localeOf(context).languageCode == 'km'
            ? 'មិនមានរូបថត'
            : 'Photo unavailable',
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = photo;
    if (data == null || data['url'] is! String) return fallback(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Image.network(
          data['url'] as String,
          height: 170,
          fit: BoxFit.cover,
          semanticLabel: name,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback(context),
          errorBuilder: (context, error, stack) => fallback(context),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          icon: const Icon(Icons.photo_camera_outlined, size: 16),
          label: Text(
            '${data['artist']} · ${data['license']}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(
                Localizations.localeOf(c).languageCode == 'km'
                    ? 'ប្រភពរូបថត'
                    : 'Photo credit',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data['artist']}\n${data['license']}\n${data['credit'] ?? ''}',
                    ),
                    TextButton(
                      onPressed: () => _open(c, data['sourceUrl']),
                      child: const Text('Wikimedia Commons'),
                    ),
                    TextButton(
                      onPressed: () => _open(c, data['licenseUrl']),
                      child: Text(
                        Localizations.localeOf(c).languageCode == 'km'
                            ? 'អាជ្ញាបណ្ណ'
                            : 'License',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(MaterialLocalizations.of(c).closeButtonLabel),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Future<void> _open(BuildContext context, Object? value) async {
    final uri = Uri.tryParse('$value');
    if (uri == null || uri.scheme != 'https') return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link.')));
    }
  }
}
