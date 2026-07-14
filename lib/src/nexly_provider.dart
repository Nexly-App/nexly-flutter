import 'package:flutter/widgets.dart';

import 'nexly.dart';

/// Initializes the [Nexly] singleton asynchronously (device-storage
/// prewarm) and rebuilds descendants once it is ready. Mirrors the prop
/// surface of `NexlyProvider` in `@nexly/react-native` so the two SDKs
/// stay conceptually interchangeable.
///
/// ```dart
/// void main() {
///   runApp(NexlyProvider(
///     appId: 'app_...',
///     ingestKey: 'nx_...',
///     child: const MyApp(),
///   ));
/// }
/// ```
///
/// `NexlyProvider.of(context)` returns `true` once init completed with
/// valid credentials. Because [Nexly]'s tracking methods are static and
/// no-op until initialized, using them without the provider (after a
/// manual [Nexly.init]) is equally supported.
class NexlyProvider extends StatefulWidget {
  const NexlyProvider({
    super.key,
    required this.appId,
    required this.ingestKey,
    this.collectUrl = Nexly.defaultCollectUrl,
    this.autoEngagement = true,
    this.initialScreen,
    this.privacyMode = false,
    required this.child,
  });

  /// App identifier from the dashboard.
  final String appId;

  /// Ingest API token from the dashboard (maps to `key` on [Nexly.init]).
  final String ingestKey;

  /// Override the ingest endpoint. Defaults to the Nexly production
  /// gateway.
  final String collectUrl;

  /// Attach app-lifecycle-driven engagement tracking (active seconds,
  /// heartbeat, session_ping).
  final bool autoEngagement;

  /// Initial screen name used as `path` for events sent before any
  /// [Nexly.setScreen] call.
  final String? initialScreen;

  /// Privacy mode: never read or write device storage for visitor /
  /// session identifiers. The collector derives a daily-rotating visit
  /// fingerprint server-side instead.
  final bool privacyMode;

  final Widget child;

  /// `true` once the surrounding provider finished initializing with valid
  /// credentials.
  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_NexlyScope>();
    return scope?.ready ?? false;
  }

  @override
  State<NexlyProvider> createState() => _NexlyProviderState();
}

class _NexlyProviderState extends State<NexlyProvider> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ok = await Nexly.init(
      appId: widget.appId,
      key: widget.ingestKey,
      collectUrl: widget.collectUrl,
      privacyMode: widget.privacyMode,
      autoEngagement: widget.autoEngagement,
    );
    if (ok && widget.initialScreen != null) {
      Nexly.setScreen(widget.initialScreen!);
    }
    if (mounted) setState(() => _ready = ok);
  }

  @override
  void dispose() {
    Nexly.stopEngagement();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _NexlyScope(ready: _ready, child: widget.child);
  }
}

class _NexlyScope extends InheritedWidget {
  const _NexlyScope({required this.ready, required super.child});

  final bool ready;

  @override
  bool updateShouldNotify(_NexlyScope oldWidget) => ready != oldWidget.ready;
}
