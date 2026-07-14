# Nexly

Official Flutter SDK for [Nexly](https://nexly.to) analytics on iOS and
Android. Pure Dart on top of `package:http` and `shared_preferences`, no
native code.

## Install

```bash
flutter pub add nexly
```

## Setup

Wrap your app in `NexlyProvider`:

```dart
import 'package:nexly/nexly.dart';

void main() {
  runApp(NexlyProvider(
    appId: 'app_...',
    ingestKey: 'nx_...',
    child: const MyApp(),
  ));
}
```

Or initialize manually before `runApp`:

```dart
WidgetsFlutterBinding.ensureInitialized();
await Nexly.init(appId: 'app_...', key: 'nx_...');
```

`appId` and the ingest key come from the Nexly dashboard. By default the SDK
also starts engagement tracking (active seconds, a 60s heartbeat, and
`session_ping` / `session_end` around app backgrounding) — pass
`autoEngagement: false` to opt out and call `Nexly.startEngagement()` /
`Nexly.stopEngagement()` manually.

Enable the **Mobile apps** channel for the app in the Nexly dashboard (SDK
options in the setup wizard, or the Ingest settings tab later) so the
collector accepts events from this SDK.

## Usage

```dart
Nexly.setScreen('Settings');
Nexly.pageview();

// Or in one call:
Nexly.screenview('Pricing');

Nexly.customEvent('checkout_started', cdata: {'cart_value_cents': 4200});

Nexly.event(name: 'search_submitted', type: 'engagement', cdata: {'query_length': 7});
```

### Privacy mode

When enabled, the SDK never reads or writes device storage for visitor /
session identifiers; the collector derives a short-lived, daily-rotating
visit fingerprint server-side instead.

```dart
await Nexly.init(appId: 'app_...', key: 'nx_...', privacyMode: true);

// Can also be toggled at runtime, e.g. from a settings switch:
await Nexly.setPrivacyMode(true);
```

### Custom visitor / session id

Works in both modes. In privacy mode this is the only way to get a stable
visitor id or control visit grouping client-side.

```dart
Nexly.setVisitorId('user_42');
Nexly.setSessionId('checkout-flow-1');

// Clear an override:
Nexly.setVisitorId('');
```

## Versioning

This package's version is kept **in lockstep with the `@nexly/*` JS
packages** in the `trackers` monorepo (`packages/core`, `packages/web`,
`packages/react-native`, etc. — all released together via changesets). When
those packages bump to e.g. `1.1.0`, this package gets a matching `1.1.0`
release once the wire-contract changes have been ported, so the version
number alone tells you which JS release a given SDK build's behavior
corresponds to. See `CHANGELOG.md` for what changed in each release.

## Development

```bash
flutter pub get
flutter test
```

The `example/` app consumes the package via a local path dependency:

```bash
cd example
flutter run
```
