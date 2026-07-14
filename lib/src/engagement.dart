import 'dart:async';

import 'package:flutter/widgets.dart';

import 'collect_payload.dart';
import 'device_meta.dart';
import 'identity.dart' as identity;
import 'session.dart';
import 'transport.dart';

const Duration _tickInterval = Duration(seconds: 1);
const Duration _heartbeatInterval = Duration(seconds: 60);

/// `active_seconds` counter, 60s heartbeat, and `session_ping` /
/// `session_end` driven by [WidgetsBindingObserver] app lifecycle
/// callbacks. Mirrors `packages/react-native/src/engagement.ts` — Flutter's
/// [AppLifecycleState] has the same shape as React Native's `AppState`.
class Engagement with WidgetsBindingObserver {
  Engagement({
    required this.collectUrl,
    required this.appId,
    required this.apiToken,
    this.client,
  });

  final String collectUrl;
  final String appId;
  final String apiToken;
  final String? client;

  int _activeSeconds = 0;
  bool _sessionContextSent = false;
  bool _appActive = true;
  Timer? _tickTimer;
  Timer? _heartbeatTimer;
  bool _observing = false;

  void start() {
    stop();
    _appActive = true;
    _tickTimer = Timer.periodic(_tickInterval, (_) {
      if (_appActive) _activeSeconds++;
    });
    _sendHeartbeat();
    _heartbeatTimer =
        Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  void stop() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
    if (_activeSeconds > 0) {
      _send('session_end', 'lifecycle', {'active_seconds': _activeSeconds});
      _activeSeconds = 0;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _appActive = false;
        if (_activeSeconds > 0) {
          _send(
              'session_ping', 'lifecycle', {'active_seconds': _activeSeconds});
        }
      case AppLifecycleState.resumed:
        _appActive = true;
        if (!identity.isPrivacyMode()) {
          unawaited(touchSession());
        }
      case AppLifecycleState.detached:
        _appActive = false;
    }
  }

  void _sendHeartbeat() {
    if (!_appActive) return;
    Map<String, Object?>? sessionContext;
    if (!_sessionContextSent) {
      _sessionContextSent = true;
      sessionContext = collectSessionMeta();
    }
    _send(
      'heartbeat',
      'lifecycle',
      {'active_seconds': _activeSeconds},
      sessionContext: sessionContext,
    );
  }

  void _send(
    String eventName,
    String eventType,
    Map<String, Object?> data, {
    Map<String, Object?>? sessionContext,
  }) {
    final payload = buildCollectPayload(
      TrackEventInput(
        credentials: IngestCredentials(appId: appId, apiToken: apiToken),
        eventName: eventName,
        eventType: eventType,
        client: client,
        privacyMode: identity.isPrivacyMode(),
        context: collectEventMeta(),
        data: data,
        sessionContext: sessionContext,
      ),
    );
    sendPayload(collectUrl, payload);
  }
}
