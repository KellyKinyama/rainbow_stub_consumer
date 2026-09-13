# rainbow_stub_consumer

Flutter reference client for the [rainbow-stub](../../dart/rainbow-stub)
server. Demonstrates a full Rainbow-style CPaaS UX — 1:1 + group chat,
reactions, edits, retracts, MAM pagination, file + camera attachments,
Jingle-signaled 1:1 audio/video calls, and ion-sfu group calls — talking
to the hand-rolled Dart stub over REST + XMPP-over-WebSocket + JSON-RPC.

Built on:

- **[rearch](https://pub.dev/packages/rearch)** capsules for state
- **[flutter_chat_ui](https://pub.dev/packages/flutter_chat_ui)** for the
  message list + composer
- **[flutter_webrtc](https://pub.dev/packages/flutter_webrtc)** for calls

## Quick start

```powershell
# Terminal 1 — start the stub (see the stub's README for TLS vs HTTP options)
cd c:\www\dart\rainbow-stub
dart run bin/server.dart

# Terminal 2 — run this app pointing at the default TLS stub
cd c:\www\flutter\rainbow_stub_consumer
flutter pub get
flutter run -d windows           # or: flutter run -d chrome
```

Sign in as `alice@rainbow-stub.local` / `password` (seeded on stub boot).

### Pointing at a LAN / real-device stub

Endpoints are driven at build time by `--dart-define`:

```powershell
flutter run -d <device> `
  --dart-define=STUB_SCHEME=http `
  --dart-define=STUB_HOST=192.168.1.42 `
  --dart-define=STUB_PORT=8080 `
  --dart-define=SFU_URL=ws://192.168.1.42:7000/ws
```

Use `10.0.2.2` as `STUB_HOST` for the Android emulator. `SFU_URL` is
optional — group-call UI stays hidden when it's unset. Real device /
emulator smoke runbook: [docs/live-smoke-test.md](docs/live-smoke-test.md).

## Testing

```powershell
flutter test                                        # 115 offline tests
flutter test test/live_stub_integration_test.dart   # 8 tests, needs stub
```

The live-integration file skips automatically if the stub isn't
reachable at the configured base URL.

## Feature status

### Chat

- [x] 1:1 + group (MUC) messages
- [x] XEP-0313 MAM with scroll-triggered load-older
- [x] XEP-0444 reactions (tap chip to toggle)
- [x] XEP-0308 corrections ("Edit")
- [x] XEP-0424 retracts ("Delete for everyone")
- [x] XEP-0461 replies with quoted preview
- [x] XEP-0184 delivery receipts + XEP-0333 chat-marker `displayed`
- [x] XEP-0085 chat states (composing / paused)
- [x] XEP-0198 stream management (enable + ack + resume)
- [x] Files (attach + upload) + camera capture

### Calls

- [x] XEP-0166 Jingle signaling (session-initiate / -accept /
      -terminate + transport-info trickle ICE) — verified live web ↔ web
- [x] 1:1 audio + video with mute / hang-up / camera flip
- [x] `CallOverlay` incoming-call banner above every route
- [x] Group calls via ion-sfu JSON-RPC signaling
- [x] MUC group-call marker (`urn:rainbow:muc-call:1`) so bubble members
      see who's in the call
- [ ] TURN relay (deferred, M-7) — media between the Android emulator
      and the host browser needs this
- [ ] Camera / mic tracks properly stopped on hang-up
      (see `docs/webrtc-roadmap.md` — Known bugs)

### Auth + platform

- [x] REST login / logout / renew / self-register / reset-password
- [x] Roster + presence with live green-dot updates
- [x] Push token registration (fake token, "would-push" hook on stub)
- [x] Windows + web + Android platform scaffolds
- [x] Debug-only `DiagnosticsOverlay` (drag / long-press to hide) —
      XMPP + SM counters + push status + active calls
- [ ] iOS scaffold (not yet — `flutter create --platforms=ios .`)

## Docs

- [webrtc-roadmap.md](docs/webrtc-roadmap.md) — WebRTC phase plan,
  M-1..M-8, known bugs
- [live-smoke-test.md](docs/live-smoke-test.md) — Real-device / emulator
  smoke runbook with an 18-row functional matrix
- [ion-sfu-wsl.md](docs/ion-sfu-wsl.md) — Local ion-sfu recipe for group
  calls
- [camera-testing.md](docs/camera-testing.md) — Camera / `image_picker`
  smoke notes
- [phase-a-log.md](docs/phase-a-log.md) … [phase-i-log.md](docs/phase-i-log.md),
  [phase-live-smoke-log.md](docs/phase-live-smoke-log.md) — per-phase
  session logs

Full setup, TLS trust, and endpoint reference for the backend:
**[c:\www\dart\rainbow-stub\RUNBOOK.md](../../dart/rainbow-stub/RUNBOOK.md)**.

## Layout

```
lib/
├── main.dart                     → RearchBootstrapper + RainbowConsumerApp
├── app.dart                      → MaterialApp + AuthGate + CallOverlay
├── config.dart                   → AppConfig, --dart-define overrides
├── rainbow/
│   ├── rest_client.dart          → HTTP with self-signed cert accept
│   ├── xmpp_client.dart          → RFC 7395 XMPP-over-WS + SM + Jingle
│   ├── _xmpp_socket.dart         → Web / VM conditional WebSocket factory
│   ├── webrtc_adapter.dart       → RtcSession / MediaStream abstraction
│   ├── webrtc_adapter_impl.dart  → flutter_webrtc-backed impl
│   ├── sdp_to_jingle.dart        → SDP ⇄ rainbow-sdp Jingle payload
│   ├── sfu_signaling.dart        → ion-sfu JSON-RPC 2.0 client
│   ├── sfu_group_call.dart       → SFU session glue
│   ├── ringer.dart               → Haptic ringer
│   └── models.dart               → RainbowUser / Roster / Bubble
├── state/
│   ├── capsules/                 → rearch capsules (auth, xmpp, rest,
│   │                               presence, roster, messages, bubbles,
│   │                               push, call_manager, group_call,
│   │                               chat_actions, config, …)
│   └── models/
└── ui/
    ├── login_page.dart           → sign-in
    ├── home_page.dart            → Contacts + Bubbles tabs
    ├── contacts_tab.dart         → live presence dots
    ├── chat_page.dart            → 1:1 chat
    ├── chat_widgets.dart         → shared long-press sheet, reply banner
    ├── bubbles_tab.dart          → rooms list + create FAB
    ├── bubble_chat_page.dart     → MUC join + groupchat + call banner
    ├── call_overlay.dart         → incoming-call banner
    ├── call_screen.dart          → full-screen 1:1 with RTCVideoView
    ├── group_call_screen.dart    → adaptive video grid
    ├── group_call_banner.dart    → bubble-side start/join controls
    ├── attachment_picker.dart    → file + camera sheet
    └── diagnostics_overlay.dart  → dev-only state HUD
```
