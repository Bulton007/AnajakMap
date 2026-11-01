import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PlacePhoto extends StatefulWidget {
  const PlacePhoto({
    super.key,
    required this.name,
    this.photo,
    this.imageProvider,
    this.loading = false,
  });
  final String name;
  final Map<String, dynamic>? photo;
  final ImageProvider<Object>? imageProvider;
  final bool loading;
  @override
  State<PlacePhoto> createState() => _PlacePhotoState();
}

class _PlacePhotoState extends State<PlacePhoto> {
  int revision = 0;
  String get name => widget.name;
  Map<String, dynamic>? get photo => widget.photo;

  Widget fallback(
    BuildContext context, {
    bool loading = false,
    VoidCallback? retry,
  }) => Container(
    height: 170,
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.landscape_outlined, size: 32),
          const SizedBox(height: 8),
          Text(
            Localizations.localeOf(context).languageCode == 'km'
                ? (loading ? 'កំពុងផ្ទុករូបថត' : 'មិនមានរូបថត')
                : (loading ? 'Loading photo' : 'Photo unavailable'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (retry != null)
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(
                Localizations.localeOf(context).languageCode == 'km'
                    ? 'ព្យាយាមម្ដងទៀត'
                    : 'Retry photo',
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.loading) return fallback(context, loading: true);
    final data = photo;
    final uri = Uri.tryParse('${data?['url'] ?? ''}');
    if (data == null ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      return fallback(context);
    }
    final image =
        widget.imageProvider ??
        ResizeImage(
          NetworkImage(
            uri.toString(),
            headers: const {
              'User-Agent':
                  'AnajakMap/1.0 (https://github.com/Bulton007/AnajakMap)',
            },
          ),
          width: 1200,
        );
    return Stack(
      children: [
        Image(
          key: ValueKey('${uri.toString()}:$revision'),
          image: image,
          width: double.infinity,
          height: 170,
          fit: BoxFit.cover,
          semanticLabel: name,
          frameBuilder: (context, child, frame, synchronous) =>
              synchronous || frame != null
              ? child
              : fallback(context, loading: true),
          errorBuilder: (context, error, stack) => fallback(
            context,
            retry: () async {
              await image.evict();
              if (mounted) setState(() => revision++);
            },
          ),
        ),
        PositionedDirectional(
          end: 8,
          bottom: 8,
          child: IconButton.filledTonal(
            tooltip: Localizations.localeOf(context).languageCode == 'km'
                ? 'ប្រភពរូបថត៖ $name'
                : 'Photo credit: $name',
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              fixedSize: const Size(48, 48),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: .94),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            icon: const Icon(Icons.info_outline_rounded, size: 20),
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
                        [data['artist'], data['license'], data['credit']]
                            .whereType<String>()
                            .where((value) => value.trim().isNotEmpty)
                            .join('\n'),
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
        ),
      ],
    );
  }

  static Future<void> _open(BuildContext context, Object? value) async {
    final uri = Uri.tryParse('$value');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not open link.')));
    }
  }
}
