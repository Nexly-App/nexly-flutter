import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:nexly/nexly.dart';

/// Local dev server for the `@nexly-examples/node` example in the
/// `trackers` monorepo — only reachable while that example is running
/// separately (`PORT=3776 npm run dev -w @nexly-examples/node`). Android
/// emulators can't resolve the host's `localhost`, hence the loopback
/// alias — same pattern as the collect URL in `main.dart`.
final String nodeExampleUrl =
    Platform.isAndroid ? 'http://10.0.2.2:3776' : 'http://localhost:3776';

enum FunnelStepStatus { sent, failed }

class FunnelStepUpdate {
  const FunnelStepUpdate(this.label, this.status);

  final String label;
  final FunnelStepStatus status;
}

Future<void> _wait() => Future<void>.delayed(const Duration(milliseconds: 500));

/// Funnel 1 — "Checkout (client-only)": every step fires straight from the
/// app SDK. Matches the `pageview -> pricing_cta_clicked ->
/// checkout_started` funnel configured on the app.
Future<void> playClientOnlyFunnel(
    void Function(FunnelStepUpdate) onStep) async {
  final steps = <(String, bool Function())>[
    ('Landing (pageview)', () => Nexly.pageview()),
    (
      'Pricing CTA',
      () => Nexly.customEvent('pricing_cta_clicked',
          cdata: {'placement': 'hero', 'variant': 'A'}),
    ),
    (
      'Checkout started',
      () => Nexly.customEvent('checkout_started', cdata: {
            'cart_value_cents': 4200,
            'currency': 'USD',
            'item_count': 2
          }),
    ),
  ];

  for (final (label, send) in steps) {
    final ok = send();
    onStep(FunnelStepUpdate(
        label, ok ? FunnelStepStatus.sent : FunnelStepStatus.failed));
    await _wait();
  }
}

enum ServerFunnelOutcome { ok, nodeUnreachable }

/// Funnel 2 — "Checkout to paid subscription (server-linked)": the first
/// two steps fire from the app, then the visitor id is handed to the node
/// example so its `subscription_created` server event lands on the same
/// timeline. Requires the node example running locally and reachable from
/// the device/emulator.
Future<ServerFunnelOutcome> playServerLinkedFunnel(
  void Function(FunnelStepUpdate) onStep,
) async {
  final okCta = Nexly.customEvent('pricing_cta_clicked',
      cdata: {'placement': 'comparison_table', 'variant': 'B'});
  onStep(FunnelStepUpdate(
      'Pricing CTA', okCta ? FunnelStepStatus.sent : FunnelStepStatus.failed));
  await _wait();

  final okCheckout = Nexly.customEvent('checkout_started',
      cdata: {'cart_value_cents': 8900, 'currency': 'USD', 'item_count': 1});
  onStep(FunnelStepUpdate('Checkout started',
      okCheckout ? FunnelStepStatus.sent : FunnelStepStatus.failed));
  await _wait();

  final visitorId = getCachedVisitorId() ?? '';
  final shortId = (visitorId.isEmpty ? 'anon' : visitorId);
  final userId =
      'demo_user_${shortId.substring(0, shortId.length < 12 ? shortId.length : 12)}';

  try {
    await http.post(
      Uri.parse('$nodeExampleUrl/api/link-visitor'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'visitorId': visitorId}),
    );
    final res = await http.post(
      Uri.parse('$nodeExampleUrl/webhook/subscription-created'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'userId': userId, 'plan': 'pro', 'amountCents': 4900}),
    );
    if (res.statusCode >= 400) {
      throw http.ClientException('node example rejected the request');
    }
    onStep(const FunnelStepUpdate(
        'Subscription created (server)', FunnelStepStatus.sent));
    return ServerFunnelOutcome.ok;
  } catch (_) {
    onStep(const FunnelStepUpdate(
        'Subscription created (server)', FunnelStepStatus.failed));
    return ServerFunnelOutcome.nodeUnreachable;
  }
}
