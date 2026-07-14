import 'dart:math';

import 'storage.dart';

const String _visitorKey = 'trk_visitor_id';
const String _sessionKey = 'trk_session_id';
const String _sessionTsKey = 'trk_session_ts';

const Duration _sessionTimeout = Duration(minutes: 30);

final Random _random = Random.secure();

/// RFC 4122 version-4 UUID, lowercase. Hand-rolled on `Random.secure()`
/// to avoid a package dependency for one function.
String generateId() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// In-memory cache prewarmed by [prewarmIds]; safe to read synchronously
/// after init. Mirrors `packages/react-native/src/session.ts`.
String? _cachedVisitorId;
String? _cachedSessionId;

/// Loads (or generates) the persistent visitor ID and current session ID
/// from storage. Call once before sending any event; subsequent calls are
/// idempotent.
Future<void> prewarmIds() async {
  final now = DateTime.now().millisecondsSinceEpoch;

  var visitorId = _cachedVisitorId ?? await storageGet(_visitorKey);
  if (visitorId == null || visitorId.isEmpty) {
    visitorId = generateId();
    await storageSet(_visitorKey, visitorId);
  }
  _cachedVisitorId = visitorId;

  final existing = await storageGet(_sessionKey);
  final tsRaw = await storageGet(_sessionTsKey);
  final lastTs = tsRaw != null ? (int.tryParse(tsRaw) ?? 0) : 0;
  String sessionId;
  if (existing != null &&
      existing.isNotEmpty &&
      lastTs > 0 &&
      now - lastTs < _sessionTimeout.inMilliseconds) {
    sessionId = existing;
  } else {
    sessionId = generateId();
    await storageSet(_sessionKey, sessionId);
  }
  await storageSet(_sessionTsKey, '$now');
  _cachedSessionId = sessionId;
}

/// Touch the session timestamp; if the session expired, roll a new
/// session ID.
Future<void> touchSession() async {
  final now = DateTime.now().millisecondsSinceEpoch;
  final tsRaw = await storageGet(_sessionTsKey);
  final lastTs = tsRaw != null ? (int.tryParse(tsRaw) ?? 0) : 0;
  if (_cachedSessionId != null &&
      lastTs > 0 &&
      now - lastTs < _sessionTimeout.inMilliseconds) {
    await storageSet(_sessionTsKey, '$now');
    return;
  }
  final id = generateId();
  _cachedSessionId = id;
  await storageSet(_sessionKey, id);
  await storageSet(_sessionTsKey, '$now');
}

/// Persistent visitor ID from the prewarmed cache, or `null` before
/// [prewarmIds] completes (or in privacy mode, which skips prewarming).
String? getCachedVisitorId() => _cachedVisitorId;

/// Current session ID from the prewarmed cache, or `null` before
/// [prewarmIds] completes (or in privacy mode, which skips prewarming).
String? getCachedSessionId() => _cachedSessionId;
