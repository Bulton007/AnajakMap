import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

Future<WebSocket?> openLiveSocket(ApiClient api, String path) async {
  if (kIsWeb || !api.authenticated) return null;
  final uri = Uri.parse(api.dio.options.baseUrl).resolve(path);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final socket = await WebSocket.connect(
      uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString(),
      headers: api.realtimeHeaders,
      customClient: client,
    );
    socket.pingInterval = const Duration(seconds: 25);
    return socket;
  } finally {
    client.close();
  }
}
