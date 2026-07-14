import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around `shared_preferences` with an in-memory fallback so
/// the SDK does not hard-crash if the plugin cannot initialize (tests,
/// early startup before plugin registration). Mirrors the defensive
/// pattern in `packages/react-native/src/storage.ts`.
final Map<String, String> _memory = {};

SharedPreferences? _prefs;
bool _loadAttempted = false;

Future<SharedPreferences?> _loadPrefs() async {
  if (_prefs != null) return _prefs;
  if (_loadAttempted) return null;
  _loadAttempted = true;
  try {
    _prefs = await SharedPreferences.getInstance();
    return _prefs;
  } catch (_) {
    debugPrint(
      '[Nexly] shared_preferences is unavailable; visitor/session IDs will not persist.',
    );
    return null;
  }
}

Future<String?> storageGet(String key) async {
  final prefs = await _loadPrefs();
  if (prefs == null) return _memory[key];
  try {
    return prefs.getString(key);
  } catch (_) {
    return null;
  }
}

Future<void> storageSet(String key, String value) async {
  final prefs = await _loadPrefs();
  if (prefs == null) {
    _memory[key] = value;
    return;
  }
  try {
    await prefs.setString(key, value);
  } catch (_) {
    // ignore — analytics storage must never throw into the host app
  }
}
