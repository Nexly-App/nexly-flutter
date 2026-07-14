import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'collect_payload.dart';
import 'device_meta.dart';
import 'engagement.dart';
import 'identity.dart' as identity;
import 'session.dart';
import 'transport.dart';

/// Wire identifiers this SDK reports as `client`. Mirror the
/// `flutter-ios` / `flutter-android` entries in the server-side allowlist
/// (`cmd/public-api/main.go` in the `trackers` monorepo).
String _defaultClient() {
  if (!kIsWeb && Platform.isAndroid) return 'flutter-android';
  // iOS, and any other Apple platform (macOS) — report as flutter-ios.
  return 'flutter-ios';
}

/// Nexly analytics client for Flutter.
///
/// Call [Nexly.init] once (e.g. from `main()` before `runApp`, or wrap the
/// app in a `NexlyProvider`), then use the static tracking methods
/// anywhere in the app:
///
/// ```dart
/// await Nexly.init(appId: 'app_...', key: 'nx_...');
/// Nexly.pageview();
/// Nexly.customEvent('checkout_started', cdata: {'cart_value_cents': 4200});
/// ```
class Nexly {
  Nexly._({
    required this.collectUrl,
    required this.appId,
    required String apiToken,
  }) : _apiToken = apiToken;

  /// Nexly production ingest gateway. Override only for local development
  /// — do not surface `collectUrl` in application UI or public docs.
  static const String defaultCollectUrl = 'https://gate.nexly.to/v1/collect';

  static Nexly? _current;

  final String collectUrl;
  final String appId;
  final String _apiToken;
  String _currentScreen = '/';
  String? _sentSessionContextFor;
  Engagement? _engagement;

  bool get _disabled => appId.isEmpty || _apiToken.isEmpty;

  // Setup

  /// Configures the shared client **and awaits ID prewarming** (device
  /// storage is asynchronous). Calling it again replaces the previous
  /// instance and stops any engagement tracking it had started.
  ///
  /// - [appId] — app identifier from the dashboard.
  /// - [key] — ingest API token from the dashboard.
  /// - [collectUrl] — override the ingest endpoint. Defaults to the Nexly
  ///   production gateway; only override for local development.
  /// - [privacyMode] — when `true`, the SDK never reads or writes device
  ///   storage for visitor / session identifiers; the collector derives a
  ///   short-lived, daily-rotating visit fingerprint server-side instead.
  ///   Can be flipped later with [setPrivacyMode].
  /// - [autoEngagement] — automatically tracks active seconds, a 60s
  ///   heartbeat, and `session_ping` / `session_end` driven by app
  ///   lifecycle callbacks. Defaults to `true`.
  ///
  /// Returns `false` when [appId] or [key] is empty (tracking stays
  /// disabled — every call is then a silent no-op).
  static Future<bool> init({
    required String appId,
    required String key,
    String collectUrl = defaultCollectUrl,
    bool privacyMode = false,
    bool autoEngagement = true,
  }) async {
    _current?._engagement?.stop();
    identity.configure(privacyMode: privacyMode);

    final instance = Nexly._(
      collectUrl: collectUrl.trim(),
      appId: appId.trim(),
      apiToken: key.trim(),
    );
    _current = instance;

    if (instance._disabled) {
      if (instance.appId.isEmpty) {
        debugPrint('[Nexly] Missing appId — tracking is disabled.');
      }
      if (instance._apiToken.isEmpty) {
        debugPrint('[Nexly] Missing key — tracking is disabled.');
      }
      return false;
    }

    if (!privacyMode) {
      await prewarmIds();
    }
    if (autoEngagement) {
      instance._restartEngagement();
    }
    return true;
  }

  // Screens

  /// Sets the current screen name used as `path` for subsequent events.
  static void setScreen(String name) {
    final trimmed = name.trim();
    _current?._currentScreen = trimmed.isEmpty ? '/' : trimmed;
  }

  /// Convenience: sets the screen and sends a pageview in one call.
  static bool screenview(String name) {
    setScreen(name);
    return pageview(_current?._currentScreen);
  }

  // Tracking

  /// Sends a page view (`event_name` / `event_type`: `pageview`) with full
  /// context.
  static bool pageview([String? path]) {
    final instance = _current;
    if (instance == null || instance._disabled) return false;
    final context = collectEventMeta();
    context['path'] = path ?? instance._currentScreen;
    return instance._dispatch(
      eventName: 'pageview',
      eventType: 'pageview',
      context: context,
    );
  }

  /// Sends a generic event. [context] is merged on top of the default
  /// platform context (current screen, visitor/session ids); application
  /// payload belongs in [cdata]. Prefer [customEvent] for the ergonomic
  /// custom-analytics API.
  static bool event({
    required String name,
    required String type,
    CData? cdata,
    Map<String, Object?>? context,
  }) {
    final instance = _current;
    if (instance == null || instance._disabled) return false;
    final merged = collectEventMeta();
    merged['path'] = instance._currentScreen;
    if (context != null) merged.addAll(context);
    return instance._dispatch(
      eventName: name,
      eventType: type,
      context: merged,
      cdata: cdata,
    );
  }

  /// Sends a custom analytics event. [cdata] carries the user-defined
  /// scalar payload validated server-side against the per-app "Custom
  /// data" registry. The optional [context] overrides standard attribution
  /// keys (`utm_*`, `gclid`, …) when the SDK cannot infer them (deep
  /// links, post-navigation clicks).
  static bool customEvent(
    String name, {
    CData? cdata,
    StandardContextOverride? context,
  }) {
    final instance = _current;
    if (instance == null || instance._disabled) return false;
    final merged = collectEventMeta();
    merged['path'] = instance._currentScreen;
    if (context != null) merged.addAll(context.asContext());
    return instance._dispatch(
      eventName: name,
      eventType: 'custom',
      context: merged,
      cdata: cdata,
    );
  }

  bool _dispatch({
    required String eventName,
    required String eventType,
    required Map<String, Object?> context,
    CData? cdata,
  }) {
    final privacyMode = identity.isPrivacyMode();
    final sessionId =
        context['session_id'] is String ? context['session_id']! as String : '';
    // In privacy mode the session id may be derived server-side, so the
    // SDK cannot key "session_context sent once" off it. Fall back to a
    // sentinel: send session_context once per client instance (≈ once per
    // app launch, or until `init` is called again).
    final sessionContextKey =
        sessionId.isNotEmpty ? sessionId : (privacyMode ? '\u0000privacy' : '');

    Map<String, Object?>? sessionContext;
    if (sessionContextKey.isNotEmpty &&
        sessionContextKey != _sentSessionContextFor) {
      final collected = collectSessionMeta();
      if (collected.isNotEmpty) {
        sessionContext = collected;
        _sentSessionContextFor = sessionContextKey;
      }
    }

    final payload = buildCollectPayload(
      TrackEventInput(
        credentials: IngestCredentials(appId: appId, apiToken: _apiToken),
        eventName: eventName,
        eventType: eventType,
        client: _defaultClient(),
        privacyMode: privacyMode,
        context: context,
        data: const {},
        cdata: cdata,
        sessionContext: sessionContext,
      ),
    );
    return sendPayload(collectUrl, payload);
  }

  // Engagement

  /// (Re)starts app-lifecycle-driven engagement tracking. Idempotent:
  /// calling it again stops the previous subscription first. Automatically
  /// started by [init] unless `autoEngagement` was passed as `false`.
  static bool startEngagement() {
    final instance = _current;
    if (instance == null || instance._disabled) return false;
    instance._restartEngagement();
    return true;
  }

  /// Stops engagement tracking started by [startEngagement] or
  /// `init(autoEngagement: true)`.
  static void stopEngagement() {
    _current?._engagement?.stop();
    _current?._engagement = null;
  }

  void _restartEngagement() {
    _engagement?.stop();
    final engagement = Engagement(
      collectUrl: collectUrl,
      appId: appId,
      apiToken: _apiToken,
      client: _defaultClient(),
    );
    _engagement = engagement;
    engagement.start();
  }

  // Identity

  /// Enables or disables privacy mode at runtime — safe to flip from a
  /// settings toggle. Turning it off prewarms the storage-backed IDs so
  /// the next event carries them.
  static Future<void> setPrivacyMode(bool enabled) =>
      identity.setPrivacyMode(enabled);

  /// `true` when privacy mode is currently enabled.
  static bool isPrivacyMode() => identity.isPrivacyMode();

  /// Overrides the visitor id attached to subsequent events. Pass an empty
  /// string to clear the override and fall back to the stored (or, in
  /// privacy mode, absent) id.
  static void setVisitorId(String id) => identity.setVisitorId(id);

  /// Overrides the session id attached to subsequent events. Pass an empty
  /// string to clear the override.
  static void setSessionId(String id) => identity.setSessionId(id);

  /// The visitor id that would be attached to the next event right now —
  /// useful for displaying current identity state in debug UI.
  static String currentVisitorId() => identity.resolvedVisitorId();

  /// The session id that would be attached to the next event right now.
  static String currentSessionId() => identity.resolvedSessionId();
}
