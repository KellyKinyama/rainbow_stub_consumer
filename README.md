# rainbow_stub_consumer

Flutter consumer for the [rainbow-stub](../../dart/rainbow-stub) server
— demonstrates REST + XMPP-over-WS integration.

## Quick start

```powershell
# Terminal 1 — start the stub
cd c:\www\dart\rainbow-stub
dart run tool/seed.dart          # first time only
dart run bin/server.dart

# Terminal 2 — run this app
cd c:\www\flutter\rainbow_stub_consumer
flutter pub get
flutter run -d windows           # or: flutter run -d chrome
```

Sign in with the pre-filled defaults: `alice@rainbow-stub.local` /
`password`.

## Testing

```powershell
flutter test                                        # 3 unit tests
flutter test test/live_stub_integration_test.dart   # requires stub running
```

The integration test **skips automatically** if the stub isn't reachable
at `https://localhost:8443/health`.

## Full runbook

For seed data, Android emulator config, TLS trust setup, and details of
every stub endpoint, see:

- **[c:\www\dart\rainbow-stub\RUNBOOK.md](../../dart/rainbow-stub/RUNBOOK.md)**

## Layout

```
lib/
├── main.dart                 → boots RainbowConsumerApp(AppConfig.dev)
├── app.dart                  → MaterialApp + AuthGate + Provider
├── config.dart               → AppConfig (base URL, WS URL, app auth)
├── rainbow/
│   ├── rest_client.dart      → HTTP with self-signed-cert accept
│   ├── xmpp_client.dart      → RFC 7395 XMPP-over-WS + SASL PLAIN + bind
│   └── models.dart           → RainbowUser / RosterEntry / RainbowBubble
├── state/
│   └── rainbow_session.dart  → ChangeNotifier owning REST + XMPP
└── ui/
    ├── login_page.dart
    ├── home_page.dart        → Contacts + Bubbles NavBar
    ├── contacts_tab.dart     → Live presence dots
    ├── chat_page.dart        → 1:1 chat
    ├── bubbles_tab.dart      → Rooms list + create FAB
    └── bubble_chat_page.dart → MUC join + groupchat
```
