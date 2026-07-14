import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'identity.dart' as identity;

/// Device / session metadata collection. Mirrors
/// `packages/react-native/src/device-meta.ts` and `DeviceMeta.swift` in
/// `nexly-ios`.
T? _safe<T>(T Function() fn) {
  try {
    return fn();
  } catch (_) {
    return null;
  }
}

/// Session-stable metadata: OS, screen, locale, timezone. Collected once
/// per session and sent as `session_context`.
Map<String, Object?> collectSessionMeta() {
  final out = <String, Object?>{};

  final os = _safe(() => Platform.operatingSystem);
  if (os != null) out['platform'] = os;
  final osVersion = _safe(() => Platform.operatingSystemVersion);
  if (osVersion != null && osVersion.isNotEmpty) out['os_version'] = osVersion;

  final dispatcher = _safe(() => WidgetsBinding.instance.platformDispatcher) ??
      PlatformDispatcher.instance;

  final view =
      _safe(() => dispatcher.views.isNotEmpty ? dispatcher.views.first : null);
  if (view != null) {
    final ratio = view.devicePixelRatio;
    out['screen_width'] = view.physicalSize.width.round();
    out['screen_height'] = view.physicalSize.height.round();
    out['viewport_width'] = (view.physicalSize.width / ratio).round();
    out['viewport_height'] = (view.physicalSize.height / ratio).round();
    out['device_pixel_ratio'] = ratio;
  }

  final locale = _safe(() => dispatcher.locale.toLanguageTag());
  if (locale != null && locale.isNotEmpty) {
    out['language'] = locale;
    out['locale'] = locale;
  }
  final timezone = _safe(() => DateTime.now().timeZoneName);
  if (timezone != null && timezone.isNotEmpty) out['timezone'] = timezone;

  out['user_agent'] =
      'nexly-flutter/${os ?? 'unknown'} ${osVersion ?? ''}'.trim();

  return out;
}

/// Per-event volatile metadata: resolved visitor / session ids. `path` is
/// set by the caller from the current screen name.
Map<String, Object?> collectEventMeta() {
  final out = <String, Object?>{};
  final visitorId = identity.resolvedVisitorId();
  final sessionId = identity.resolvedSessionId();
  if (visitorId.isNotEmpty) out['visitor_id'] = visitorId;
  if (sessionId.isNotEmpty) out['session_id'] = sessionId;
  return out;
}
