# Live smoke test — real-device checklist

This document is the runbook for taking `rainbow_stub_consumer` off the
Windows / web dev loop and onto real Android hardware (or a physical
iOS device), talking to the Dart stub over the LAN. It supersedes the
per-phase feature docs when what you want is a **cross-cutting
functional check** on hardware.

The overlay in the top-left corner (`DiagnosticsOverlay`) shows XMPP,
SM counters, push and call state live. Long-press to hide, tap the
bug icon to bring it back, drag anywhere. It only renders when the
Flutter build is in debug mode (`flutter run` / `flutter run --profile`
without `--release`).

## 0 — Prereqs

- **Stub reachable from the phone.** Run `ipconfig` on the dev box,
  note the LAN IPv4 (say `192.168.1.42`). The stub already binds
  `0.0.0.0`; nothing to change server-side.
- **TLS or cleartext?** The stub's default is HTTPS on :8443 with a
  self-signed cert, which the phone will refuse. Easiest is to run
  the stub on plain HTTP :8080 for smoke tests — the manifest already
  has `usesCleartextTraffic="true"`. Set `STUB_INSECURE=1` (or
  whatever your stub flag is) before starting it.
- **Firewall exception on the dev box:**
  ```powershell
  New-NetFirewallRule -DisplayName "Rainbow stub 8080" -Direction Inbound `
      -Protocol TCP -LocalPort 8080 -Action Allow
  # if ion-sfu is running for group calls:
  New-NetFirewallRule -DisplayName "ion-sfu 7000" -Direction Inbound `
      -Protocol TCP -LocalPort 7000 -Action Allow
  New-NetFirewallRule -DisplayName "ion-sfu 5000-5200/udp" -Direction Inbound `
      -Protocol UDP -LocalPort 5000-5200 -Action Allow
  ```
- **Android device** in developer mode, USB debugging enabled,
  connected. Verify with `flutter devices`.
- **Wi-Fi on both machines is the same subnet.** Cellular data or
  guest-Wi-Fi isolation will make the phone see nothing.

## 1 — Point the app at the LAN stub

Endpoints are driven by `--dart-define` flags at build time (see
`lib/config.dart`). No source edit required:

```powershell
flutter run -d <device-id> `
  --dart-define=STUB_SCHEME=http `
  --dart-define=STUB_HOST=192.168.1.42 `
  --dart-define=STUB_PORT=8080 `
  --dart-define=SFU_URL=ws://192.168.1.42:7000/ws
```

- Omit `SFU_URL` if you're not smoke-testing group calls; the group
  banner will hide itself.
- Android **emulator** users can set `STUB_HOST=10.0.2.2` instead of
  the LAN IP.
- iOS device: same. `NSAppTransportSecurity.NSAllowsArbitraryLoads`
  must be set on `Info.plist` if you scaffold iOS (not covered here).

## 2 — Sanity: raw HTTP from the phone

Before installing the Flutter build, open the phone's browser:

```
http://192.168.1.42:8080/api/rainbow/health
```

(Substitute the port you actually chose for the stub.) You should
get `{"ok":true}`. If not, the firewall rule or Wi-Fi subnet is
wrong — no point running the app yet.

## 3 — Install and launch

```powershell
Set-Location c:\www\flutter\rainbow_stub_consumer
flutter run -d <device-id> `
  --dart-define=STUB_SCHEME=http `
  --dart-define=STUB_HOST=192.168.1.42 `
  --dart-define=STUB_PORT=8080
```

Watch the diagnostics overlay:

- `XMPP OK` should appear within ~2 s of sign-in.
- `sm` counters must both be > 0 within a few seconds (means the
  server confirmed SM enable and started acking).
- `push` should read `registered · <first-6-of-token>` on Android
  once the FCM token has been posted to the stub.

## 4 — Functional matrix

Run each row on the device. `stub` = watch the stub console for the
expected log line.

| # | Feature | Steps | Expected UI | Stub check |
|---|---------|-------|-------------|------------|
| 1 | Sign-in | Enter creds, hit Sign in | Home page, roster loads | `POST /api/rainbow/authentication/login` 200 |
| 2 | Roster | Scroll contact list | 50+ contacts render | `GET /users/networks` 200 |
| 3 | 1:1 send | Open a contact, send "hi" | Bubble appears, ✓ appears | `POST /users/{id}/messages` 200 |
| 4 | 1:1 recv | Send from second client | Bubble arrives < 1 s | XMPP push, no polling |
| 5 | Reactions | Long-press bubble, tap 👍 | Reaction chip visible | XEP-0444 stanza |
| 6 | Edits | Long-press own bubble → Edit → send | Bubble text updates | correction stanza |
| 7 | Retract | Long-press own → Delete | "message removed" | XEP-0424 tombstone |
| 8 | Reply | Long-press → Reply → send | Quoted preview | fallback body |
| 9 | MAM scroll | Scroll to top of a long chat | Older page slides in | `GET /users/{id}/bubbles/…/messages?…` |
|10 | Attach file | Tap 📎 → Files → pick PDF | Bubble w/ file card | `POST …/files`, upload URL |
|11 | Attach camera | Tap 📎 → Camera → snap | Bubble w/ image | `POST …/files` |
|12 | Push (offline) | Kill the app; second client sends | Stub logs `[push] would-push …` | INFO line in stub |
|13 | 1:1 audio | Tap 📞 in a bubble | Ringing → Connected | Jingle session-init |
|14 | 1:1 video | Tap 📹 | Two-cell video | Jingle session-init |
|15 | Group audio | Two devices in same bubble, tap "Start Audio" | Both see one remote tile | ion-sfu logs `Join` + `Publish` |
|16 | Group video | "Start Video" | Adaptive grid | ion-sfu logs |
|17 | SM resume | In a chat, airplane-mode ON for 15 s, OFF | Overlay flashes DOWN → OK; queued msg delivers | `pending` counter drops to 0 |
|18 | Roster presence | Second client goes offline | Green dot fades | XMPP presence |

## 5 — What "success" looks like

- No red banners.
- No spinning progress bars for more than 5 s outside of MAM catch-up.
- Stub console shows only expected routes; no 500s.
- Diagnostics overlay `pending` returns to 0 within 30 s of any
  visible message.
- Calls: mic level indicator on the peer device moves when you speak
  (there isn't a VU meter in the app — use the phone's own mic
  indicator in the status bar as a proxy).

## 6 — Known non-blockers

- Web push notifications will not fire — the stub only records
  "would-push" INFO lines; no APNs / FCM sender is wired.
- TURN is **not** configured. On the same LAN this doesn't matter.
  Across NATs the WebRTC ICE gathering will time out; that's the
  M-7 backlog item and out of scope for this smoke pass.
- The multipart avatar test is flaky in the stub (documented in the
  Phase E log); this doesn't affect app behavior.

## 7 — Reporting a failure

For each failed row capture:

1. The row number and step that broke.
2. The last ~30 lines of `flutter logs` from the device.
3. The stub console's output for the same 30 seconds.
4. A screenshot of the diagnostics overlay at the moment of failure.

Filed in `docs/phase-live-smoke-log.md` (create on first regression),
one section per failure, so the roadmap can advance to the next phase
with a clean baseline.
