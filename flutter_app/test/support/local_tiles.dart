import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Bundled fixture image: automated tests never contact public tile servers.
class LocalTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      const AssetImage('assets/images/angkor.jpg');
}
