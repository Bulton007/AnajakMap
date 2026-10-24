import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/providers.dart';
import 'place_photo.dart';

class OfflinePlacePhoto extends ConsumerStatefulWidget {
  const OfflinePlacePhoto({
    super.key,
    required this.scope,
    required this.name,
    this.photo,
  });
  final String scope, name;
  final Map<String, dynamic>? photo;
  @override
  ConsumerState<OfflinePlacePhoto> createState() => _OfflinePhotoState();
}

class _OfflinePhotoState extends ConsumerState<OfflinePlacePhoto> {
  late Future<Uint8List?> image = load();
  Future<Uint8List?> load() => widget.photo?['url'] is String
      ? ref
            .read(placePhotoCacheProvider)
            .load(widget.scope, widget.photo!['url'])
      : Future.value(null);
  @override
  void didUpdateWidget(OfflinePlacePhoto old) {
    super.didUpdateWidget(old);
    if (old.scope != widget.scope ||
        old.photo?['url'] != widget.photo?['url']) {
      image = load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: image,
    builder: (_, snapshot) => PlacePhoto(
      name: widget.name,
      photo: widget.photo,
      loading: snapshot.connectionState != ConnectionState.done,
      imageProvider: snapshot.data == null ? null : MemoryImage(snapshot.data!),
    ),
  );
}
