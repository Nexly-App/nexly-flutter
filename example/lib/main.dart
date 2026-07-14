import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:nexly/nexly.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'funnel_demo.dart';

/// Local public-api during development. Android emulators can't resolve
/// the host's `localhost`, hence the loopback alias.
final String collectUrl = Platform.isAndroid
    ? 'http://10.0.2.2:3781/v1/collect'
    : 'http://127.0.0.1:3781/v1/collect';

const String _appIdKey = 'nexly-example-app-id';
const String _ingestKeyKey = 'nexly-example-ingest-key';

const List<String> screens = ['Home', 'Pricing', 'Settings'];

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nexly Flutter test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF18181B)),
        scaffoldBackgroundColor: const Color(0xFFF6F6F7),
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _appIdController = TextEditingController();
  final _ingestKeyController = TextEditingController();

  bool _hydrated = false;
  bool _initialized = false;
  bool _savedHint = false;

  final List<String> _sent = [];
  String _screen = 'Home';
  String? _funnelBusy;
  final List<FunnelStepUpdate> _funnelLog = [];
  String? _funnelHint;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _appIdController.dispose();
    _ingestKeyController.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _appIdController.text = prefs.getString(_appIdKey) ?? '';
    _ingestKeyController.text = prefs.getString(_ingestKeyKey) ?? '';
    setState(() => _hydrated = true);
    if (_appIdController.text.isNotEmpty &&
        _ingestKeyController.text.isNotEmpty) {
      await _initNexly();
    }
  }

  Future<void> _initNexly() async {
    final ok = await Nexly.init(
      appId: _appIdController.text.trim(),
      key: _ingestKeyController.text.trim(),
      collectUrl: collectUrl,
    );
    if (ok) Nexly.setScreen(_screen);
    if (mounted) setState(() => _initialized = ok);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appIdKey, _appIdController.text.trim());
    await prefs.setString(_ingestKeyKey, _ingestKeyController.text.trim());
    await _initNexly();
    setState(() => _savedHint = true);
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _savedHint = false);
    });
  }

  void _record(String label) {
    setState(() {
      _sent.insert(0, label);
      if (_sent.length > 8) _sent.removeRange(8, _sent.length);
    });
  }

  void _fireCustom(String name, CData cdata) {
    if (!_initialized) return;
    Nexly.customEvent(name, cdata: cdata);
    _record(name);
  }

  void _fireEngagement(String name, CData cdata) {
    if (!_initialized) return;
    Nexly.event(name: name, type: 'engagement', cdata: cdata);
    _record(name);
  }

  void _goToScreen(String next) {
    if (!_initialized) return;
    Nexly.screenview(next);
    setState(() => _screen = next);
    _record('screenview $next');
  }

  Future<void> _playFunnel(String kind) async {
    if (!_initialized || _funnelBusy != null) return;
    setState(() {
      _funnelBusy = kind;
      _funnelLog.clear();
      _funnelHint = null;
    });
    void onStep(FunnelStepUpdate u) => setState(() => _funnelLog.add(u));
    if (kind == 'client') {
      await playClientOnlyFunnel(onStep);
    } else {
      final outcome = await playServerLinkedFunnel(onStep);
      if (outcome == ServerFunnelOutcome.nodeUnreachable) {
        setState(() {
          _funnelHint = 'Could not reach the node example. '
              'Start it with: PORT=3776 npm run dev -w @nexly-examples/node';
        });
      }
    }
    setState(() => _funnelBusy = null);
  }

  @override
  Widget build(BuildContext context) {
    final status = !_hydrated
        ? 'loading…'
        : _initialized
            ? 'initialized'
            : 'missing credentials';

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 60, 16, 24),
        children: [
          Text('Nexly Flutter test',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Wired to package:nexly with autoEngagement. Events go to $collectUrl.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF52525B)),
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Credentials',
            children: [
              const _Muted(
                'App ID and API token from the dashboard. Saved in SharedPreferences. '
                'Enable the Mobile apps channel for the app (Ingest tab) so the '
                'collector accepts SDK events.',
              ),
              _Field(
                  label: 'App ID',
                  controller: _appIdController,
                  placeholder: 'app_…'),
              _Field(
                  label: 'API token',
                  controller: _ingestKeyController,
                  placeholder: 'nx_…'),
              _Button(label: 'Save', onPressed: _save),
              if (_savedHint)
                const Text('Saved.',
                    style: TextStyle(color: Color(0xFF15803D), fontSize: 12)),
              _Muted('Status: $status'),
            ],
          ),
          _Section(
            title: 'Play a funnel',
            children: [
              const _Muted(
                'Fires the exact event sequence configured for each funnel on the app, '
                'with a short delay between steps.',
              ),
              _Button(
                label: _funnelBusy == 'client'
                    ? 'Playing…'
                    : 'Play: Checkout (client-only)',
                onPressed: _initialized && _funnelBusy == null
                    ? () => _playFunnel('client')
                    : null,
              ),
              _Button(
                label: _funnelBusy == 'server'
                    ? 'Playing…'
                    : 'Play: Checkout → subscription (server-linked)',
                onPressed: _initialized && _funnelBusy == null
                    ? () => _playFunnel('server')
                    : null,
              ),
              for (final u in _funnelLog)
                Text(
                  '${u.status == FunnelStepStatus.failed ? '✗' : '✓'} ${u.label}',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: u.status == FunnelStepStatus.failed
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF15803D),
                  ),
                ),
              if (_funnelHint != null)
                Text(_funnelHint!,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFB91C1C))),
            ],
          ),
          _Section(
            title: 'Demo events',
            children: [
              _Button(
                label: 'pricing_cta_clicked',
                onPressed: _initialized
                    ? () => _fireCustom(
                        'pricing_cta_clicked', {'placement': 'hero'})
                    : null,
              ),
              _Button(
                label: 'newsletter_subscribed',
                onPressed: _initialized
                    ? () => _fireCustom(
                        'newsletter_subscribed', {'placement': 'modal'})
                    : null,
              ),
              _Button(
                label: 'checkout_started',
                onPressed: _initialized
                    ? () => _fireCustom(
                        'checkout_started', {'cart_value_cents': 4200})
                    : null,
              ),
              _Button(
                label: 'search_submitted (engagement)',
                onPressed: _initialized
                    ? () =>
                        _fireEngagement('search_submitted', {'query_length': 7})
                    : null,
              ),
            ],
          ),
          _Section(
            title: 'Screens (current: $_screen)',
            children: [
              const _Muted(
                  'Calls Nexly.screenview(name) — records a screen view with path={name}.'),
              for (final s in screens)
                _Button(
                    label: 'Go to $s',
                    onPressed: _initialized ? () => _goToScreen(s) : null),
            ],
          ),
          _Section(
            title: 'Recent sends',
            children: [
              if (_sent.isEmpty)
                const _Muted('no events yet')
              else
                for (final id in _sent) _Muted('• $id'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          ...children.expand((w) => [w, const SizedBox(height: 8)]),
        ],
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(color: Color(0xFF71717A), fontSize: 12));
  }
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.label,
      required this.controller,
      required this.placeholder});

  final String label;
  final TextEditingController controller;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF52525B))),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          autocorrect: false,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: placeholder,
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFD4D4D8)),
            ),
          ),
        ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF18181B),
        disabledBackgroundColor: const Color(0xFFE4E4E7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
    );
  }
}
