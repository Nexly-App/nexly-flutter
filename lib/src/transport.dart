import 'dart:convert';

import 'package:http/http.dart' as http;

/// Synthetic `Origin` header — native apps don't send one by default, but
/// the collector enforces an allowlist. Enabling the **Mobile apps**
/// channel for the app in the Nexly dashboard authorizes this origin.
const String nativeOrigin = 'nexlyflutter://device';

/// Fire-and-forget JSON POST to the collector. The response is never
/// awaited on the hot path and errors are swallowed — analytics must not
/// crash or block the host app. Mirrors
/// `packages/react-native/src/transport.ts`.
bool sendPayload(String url, Map<String, Object?> payload) {
  if (url.isEmpty) return false;
  final Uri endpoint;
  try {
    endpoint = Uri.parse(url);
  } on FormatException {
    return false;
  }
  try {
    http
        .post(
          endpoint,
          headers: const {
            'Content-Type': 'application/json',
            'Origin': nativeOrigin,
          },
          body: jsonEncode(payload),
        )
        .ignore();
    return true;
  } catch (_) {
    return false;
  }
}
