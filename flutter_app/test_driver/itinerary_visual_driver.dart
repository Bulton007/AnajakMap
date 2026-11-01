import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('../.local/itinerary-visual-check');
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^itinerary-(en|km)-(light|dark)$').hasMatch(name)) {
        return false;
      }
      if (bytes.length < 8 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        return false;
      }
      await File('${output.path}/$name.png').writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: (data) {
      // Screenshots are already written as PNGs; keep their large byte arrays
      // out of the compact response JSON.
      final compact = Map<String, dynamic>.from(data ?? {})
        ..remove('screenshots');
      return writeResponseData(
        compact,
        destinationDirectory: output.path,
      );
    },
    writeResponseOnFailure: true,
  );
}
