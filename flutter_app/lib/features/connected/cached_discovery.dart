import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/formatting/travel_dates.dart';
import 'discovery_details.dart';

class CachedDiscoveryInformation extends ConsumerStatefulWidget {
  const CachedDiscoveryInformation({
    super.key,
    required this.operation,
    required this.query,
    required this.profile,
    this.parameters = const {},
  });
  final String operation, query;
  final Json profile, parameters;
  @override
  ConsumerState<CachedDiscoveryInformation> createState() =>
      _CachedDiscoveryState();
}

class _CachedDiscoveryState extends ConsumerState<CachedDiscoveryInformation> {
  Object? data;
  String? savedAt, error;
  bool busy = true;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(CachedDiscoveryInformation old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query ||
        old.operation != widget.operation ||
        old.profile['id'] != widget.profile['id'] ||
        jsonEncode(old.parameters) != jsonEncode(widget.parameters)) {
      load();
    }
  }

  Future<void> load() async {
    final version = ++revision;
    final parameters = {'query': widget.query, ...widget.parameters};
    final operation = widget.operation;
    final key = 'discovery:$operation:${jsonEncode(parameters)}';
    final scope =
        '${ref.read(environmentProvider).normalizedUrl}|${widget.profile['id']}';
    final db = ref.read(databaseProvider);
    setState(() {
      busy = true;
      data = null;
      savedAt = null;
      error = null;
    });
    try {
      final value = await ref
          .read(repositoryProvider)
          .discovery(operation, parameters);
      if (field(object(value), 'mock') != true) {
        try {
          await db.cache(scope, key, value);
          await db.pruneCache(scope, 'discovery:', 40);
        } catch (_) {}
      }
      if (mounted && version == revision) {
        setState(() {
          data = value;
          busy = false;
        });
      }
    } catch (_) {
      Json? cached;
      try {
        cached = await db.cached(scope, key);
      } catch (_) {}
      if (mounted && version == revision) {
        setState(() {
          busy = false;
          if (cached != null) {
            data = cached['data'];
            savedAt = string(cached, 'savedAt');
          } else {
            error = context.isKhmer
                ? 'មិនអាចផ្ទុកព័ត៌មានគោលដៅបាន ហើយគ្មានច្បាប់ចម្លងរក្សាទុកទេ។'
                : 'Destination information is unavailable and no saved copy exists.';
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (busy) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return PageBody(
        children: [
          Notice(error!, error: true),
          FilledButton(onPressed: load, child: Text(context.t('retry'))),
        ],
      );
    }
    return Column(
      children: [
        if (savedAt != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Notice(
                  '${context.isKhmer ? 'ព័ត៌មានរក្សាទុក · អាចហួសសម័យ' : 'Saved information · may be outdated'}\n${travelDateTime(savedAt!, locale: context.isKhmer ? 'km' : 'en')}',
                  icon: Icons.offline_pin_outlined,
                ),
                TextButton.icon(
                  onPressed: load,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.t('retry')),
                ),
              ],
            ),
          ),
        Expanded(
          child: DiscoveryDetails(
            operation: widget.operation,
            query: widget.query,
            data: data,
          ),
        ),
      ],
    );
  }
}
