import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'travel_database.dart';

/// Public Wikimedia thumbnails only. Never uses the authenticated backend Dio.
class PlacePhotoCache {
  PlacePhotoCache(this.database, {this.fetch})
    : client = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
          followRedirects: false,
          headers: {
            'User-Agent': 'AnajakMap/1.0 (contact: forusea168@gmail.com)',
          },
        ),
      );
  final TravelDatabase database;
  final Future<Uint8List?> Function(Uri)? fetch;
  final Dio client;
  static const maxBytes = 512 * 1024;
  void dispose() => client.close();
  bool valid(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes.length <= maxBytes &&
      ((bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4e &&
              bytes[3] == 0x47 &&
              bytes[4] == 13 &&
              bytes[5] == 10 &&
              bytes[6] == 26 &&
              bytes[7] == 10) ||
          (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff));
  Future<Uint8List?> load(String scope, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'upload.wikimedia.org' ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final key = 'photo:$url';
    try {
      final prior = await database.cached(scope, key);
      final value = prior?['data'];
      if (value is Map && value['bytes'] is String) {
        final bytes = base64Decode(value['bytes']);
        if (valid(bytes)) return bytes;
      }
    } catch (_) {
      /* A corrupt/missing public cache must not break discovery. */
    }
    try {
      final bytes = fetch != null ? await fetch!(uri) : await download(uri);
      if (bytes == null || !valid(bytes)) return null;
      await database.cache(scope, key, {'bytes': base64Encode(bytes)});
      await database.pruneCache(scope, 'photo:', 32);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> download(Uri uri) async {
    final cancel = CancelToken();
    final response = await client.get<ResponseBody>(
      uri.toString(),
      options: Options(responseType: ResponseType.stream),
      cancelToken: cancel,
    );
    final body = response.data;
    if (body == null) return null;
    final output = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (output.length + chunk.length > maxBytes) {
        cancel.cancel('Thumbnail cache size limit');
        return null;
      }
      output.add(chunk);
    }
    return output.takeBytes();
  }
}
