# Nexly Flutter example

Minimal demo app wired to the `nexly` package via a local path dependency.
Mirrors the React Native example in the `trackers` monorepo
(`examples/react-native`): credential input, demo events, screen views, and
the two demo funnels.

## Run

With the `trackers` local stand running (`make dev` — public-api on `:3781`):

```bash
flutter run
```

Events go to the local public-api: `127.0.0.1:3781` on the iOS simulator,
`10.0.2.2:3781` on the Android emulator. Enter an App ID and API token from
a local app and enable the Mobile apps channel for it (Ingest tab).

The server-linked funnel additionally needs the node example running:
`PORT=3776 npm run dev -w @nexly-examples/node`.
