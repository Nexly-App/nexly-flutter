import 'session.dart' as session;

/// Central switchboard between the storage-backed identifiers ([session])
/// and privacy mode / manual overrides. Every code path that attaches
/// `visitor_id` / `session_id` to an event reads through this module.
///
/// Mirrors `Identity.swift` in `nexly-ios`: `privacyMode` is a mutable
/// runtime flag (safe to flip from a settings toggle), unlike the JS SDKs
/// where it is fixed at init time.
bool _privacyMode = false;
String _manualVisitorId = '';
String _manualSessionId = '';

/// Called from `Nexly.init`.
void configure({required bool privacyMode}) {
  _privacyMode = privacyMode;
}

/// Enables or disables privacy mode at runtime. In privacy mode the SDK
/// never reads or writes device storage for visitor / session identifiers
/// (unless a manual override is set); the collector derives a short-lived,
/// daily-rotating visit fingerprint server-side instead.
///
/// Turning privacy mode off lazily prewarms the storage-backed IDs so the
/// next event carries them.
Future<void> setPrivacyMode(bool enabled) async {
  _privacyMode = enabled;
  if (!enabled && session.getCachedVisitorId() == null) {
    await session.prewarmIds();
  }
}

bool isPrivacyMode() => _privacyMode;

/// Overrides the visitor id attached to subsequent events. Works in both
/// modes; in privacy mode it is the only way to get a stable cross-visit
/// visitor id. Pass an empty string to clear the override.
void setVisitorId(String id) {
  _manualVisitorId = id.trim();
}

/// Overrides the session id attached to subsequent events. Works in both
/// modes; in privacy mode it is the only way to control visit grouping
/// client-side. Pass an empty string to clear the override.
void setSessionId(String id) {
  _manualSessionId = id.trim();
}

/// Resolved visitor id: manual override, else (outside privacy mode) the
/// prewarmed persistent id, else empty.
String resolvedVisitorId() {
  if (_manualVisitorId.isNotEmpty) return _manualVisitorId;
  if (_privacyMode) return '';
  return session.getCachedVisitorId() ?? '';
}

/// Resolved session id: manual override, else (outside privacy mode) the
/// prewarmed 30-minute rolling session id, else empty.
String resolvedSessionId() {
  if (_manualSessionId.isNotEmpty) return _manualSessionId;
  if (_privacyMode) return '';
  return session.getCachedSessionId() ?? '';
}
