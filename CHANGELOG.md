# Changelog

## 1.0.0

Initial release, aligned with `@nexly/*` v1.0.0 (see the versioning policy
in `README.md`).

- `Nexly.init` / `NexlyProvider` setup with `appId` + ingest key.
- `pageview`, `screenview` / `setScreen`, `event`, `customEvent` tracking.
- Automatic engagement tracking: active seconds, 60s heartbeat,
  `session_ping` / `session_end` around app backgrounding.
- Persistent visitor id and 30-minute rolling session id via
  `shared_preferences`.
- Privacy mode (init-time and runtime-switchable) and manual visitor /
  session id overrides.
- Reports `client=flutter-ios` / `client=flutter-android`.
