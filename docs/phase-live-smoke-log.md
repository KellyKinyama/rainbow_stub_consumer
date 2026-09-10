# Phase live-smoke session log — Android + web real-device enablement, cross-JID chat fix, call overlay hoist

**Date:** 2026-09-10
**Branches:** `feat/chat-ui-rearch` (client), `main` (stub)
**Scope:** Take the rearch/flutter_chat_ui + Jingle stack off the pure
offline-test loop and prove it live on real hardware / a real browser.
Started with an Android platform scaffold, ended with confirmed audio
flowing browser ↔ browser through the stub. Also fixed two blocker
bugs surfaced by the live run and documented one deferred.

## Stub side (`c:\www\dart\rainbow-stub`, HEAD `59c8266`)

| # | Action | Notes |
|---|---|---|
| 1 | Add `config/rainbow-stub-smoke.yaml` | Same defaults as `rainbow-stub.yaml` but `port: 8080`, `tls.enabled: false`, `logs.format: text`. Real Android/iOS devices can't ergonomically trust the self-signed dev cert, and the Android manifest already whitelists cleartext — HTTP on :8080 is the path of least resistance for smoke runs. Kept as a separate file so the default TLS-on config still ships. |
| 2 | (temporary) inline logs to walk the wire during triage | `_handleFrame` `RX <bytes> from=<jid>`, `send()` `TX <bytes> to=<jid>`, `router.fanOut` `→ N sessions`, `_handleJingle` `jingle action=X sid=Y`. All reverted before final commit — they surface only when the wire flow is under investigation. |
| 3 | `dart test` | 41/41 pass (multipart-avatar Windows flake unchanged). Only real change is the new smoke config; no behavioural code. |

## Client side (`c:\www\flutter\rainbow_stub_consumer`, branch `feat/chat-ui-rearch`, HEAD `aa0f3ed`)

### 1. Android platform scaffold + runtime config injection

| # | Action | Notes |
|---|---|---|
| 1 | `flutter create --platforms=android .` | 24 files under `android/`. Kotlin DSL (`build.gradle.kts`). Wrote the placeholder `test/widget_test.dart` and immediately deleted it — the workspace already has its own test suite. |
| 2 | Edit `android/app/src/main/AndroidManifest.xml` | Added CAMERA, RECORD_AUDIO, MODIFY_AUDIO_SETTINGS, ACCESS_NETWORK_STATE, CHANGE_NETWORK_STATE, CHANGE_WIFI_STATE, BLUETOOTH{,\_ADMIN,\_CONNECT}, READ_MEDIA_IMAGES. `<uses-feature required="false">` for camera + microphone. Set `android:usesCleartextTraffic="true"` so a debug build can hit the HTTP-only smoke stub. |
| 3 | Edit `android/app/build.gradle.kts` | Pin `minSdk = 24`. flutter_webrtc requires 21+, image_picker some paths need 24 — 24 covers both without pushing the emulator/device requirement further. |
| 4 | Rework `lib/config.dart` to read `--dart-define` overrides | `String.fromEnvironment('STUB_SCHEME'|'STUB_HOST'|'STUB_PORT'|'SFU_URL')`. Falls back to previous `https://localhost:8443` defaults when unset. Endpoints can now be re-pointed at build time — no source edit required for the LAN case. |
| 5 | `docs/live-smoke-test.md` | Runbook: firewall commands, `--dart-define` invocation template, 18-row functional matrix (sign-in through XEP-0198 resume), reporting template. Referenced from the AndroidManifest edit rationale. |

### 2. On-device diagnostics overlay

| # | Action | Notes |
|---|---|---|
| 6 | New `lib/ui/diagnostics_overlay.dart` | `RearchConsumer` that renders a semi-transparent, drag-friendly panel top-left in debug builds. Reads xmpp / config / push / call-manager / group-call-manager capsules. Shows `XMPP OK/DOWN`, current full JID, SM `hOut / hIn / pending`, REST + SFU URLs, push status + first 6 chars of the token, count of active 1:1 and group calls. Long-press hides; tap the bug icon to bring back; ticks every second so the SM counters aren't stale. |
| 7 | Add overlay to `lib/app.dart` behind `kDebugMode` | Stacked over the auth-gated home in the `RainbowConsumerApp` widget — needs `import 'package:flutter/foundation.dart' show kDebugMode;`. |
| 8 | `// ignore_for_file: invalid_use_of_visible_for_testing_member` in the overlay | The overlay reads `debugHOut / debugHIn / debugPendingAckCount` from `RainbowXmppClient` — those are `@visibleForTesting`. Widening them into full public getters felt like weakening a real contract; the overlay is dev-only so the ignore is scoped to the file. |

### 3. Web sign-in fix — conditional-import WebSocket

**Symptom:** signing in as Bob on Chrome landed on `UnsupportedError` immediately after the REST login returned. Stub log confirmed `login ok`, then no WebSocket upgrade — flow bailed client-side.

**Root cause:** `xmpp_client.dart` opened the XMPP WS through `package:web_socket_channel/io.dart`'s `IOWebSocketChannel.connect(...)`, which pulls `dart:io` transitively. On Flutter web the `HttpClient()` constructor throws `UnsupportedError: Platform._operatingSystem`, and the whole XMPP `connect()` future rejected before the socket handshake started.

| # | Action | Notes |
|---|---|---|
| 9 | Add `lib/rainbow/_xmpp_socket.dart` | Public helper `openXmppSocket(uri, {acceptSelfSignedCerts, protocols})` with a conditional import: `_xmpp_socket_io.dart` by default, `_xmpp_socket_web.dart` when `dart.library.html` or `dart.library.js_interop` is present. |
| 10 | Add `lib/rainbow/_xmpp_socket_io.dart` | Native impl: `HttpClient()..badCertificateCallback = (...) => true` when the caller asks for it, then `IOWebSocketChannel.connect(uri, protocols: protocols, customClient: io)`. Preserves the self-signed-cert override. |
| 11 | Add `lib/rainbow/_xmpp_socket_web.dart` | Browser impl: plain `WebSocketChannel.connect(uri, protocols: protocols)` — the browser controls TLS trust and the self-signed flag is irrelevant. |
| 12 | Rewrite the two `connect()` / `resume()` bodies in `xmpp_client.dart` to call `openXmppSocket(...)` | Drop `import 'dart:io'`, drop `import 'package:web_socket_channel/io.dart'`, drop the two ad-hoc `HttpClient?` blocks. Both paths now share one entry point. |
| 13 | `flutter test --no-pub` | 115/115 pass (1 skipped). No changes to the SM / bind / resume state machines. |

### 4. Bob (web) → Alice (Android) silent-drop fix — domain-tolerant thread matching

**Symptom:** After the web fix, Alice → Bob chat worked; Bob → Alice was silently dropped on Alice's side. Stub `TX` log confirmed the stanza reached Alice's socket, so the bug was on Alice's client.

**Root cause:** `ThreadKey`s in `messages_capsule.dart` are built as `'${peer.id}@${config.xmppDomain}'`. Alice's Android build had `xmppDomain=10.0.2.2` (STUB_HOST for the emulator); Bob's web build had `xmppDomain=localhost`. The server registers every session under its own `publicHost=localhost`, so Alice's incoming stanzas carry `from=bob-id@localhost/flutter`, which doesn't equal Alice's local thread key `bob-id@10.0.2.2`. Every `_belongsToThread`, `_belongsToMamThread`, and each of six `.where((e) => e.fromBare == threadKey)` filters silently dropped the message.

Alice → Bob worked because Bob's `xmppDomain=localhost` did happen to match the server's stamped domain.

| # | Action | Notes |
|---|---|---|
| 14 | Introduce `_matchesThread(fromBare, threadKey)` helper | For MUC (thread key contains `@muc.`): full bare-JID equality. For 1:1: local-part equality (= user id). MUC rooms have to preserve full-JID matching because their local-part is a bubble id, not a user id, and stamping happens against `muc.<publicHost>`. |
| 15 | Rewrite `_belongsToThread` + `_belongsToMamThread` | Same fork: use bare JID for MUC, local-part for 1:1. |
| 16 | Replace `e.fromBare == threadKey` with `_matchesThread(...)` in 6 subscription filters | Delivery receipt (`XmppDeliveryReceipt`), read marker (`XmppReadMarker`), reactions (`XmppReactions`), correction (`XmppMessageCorrection`), retract (`XmppRetract` on the 1:1 path only — the MUC branch already used `_bareJid(e.fromBare) == threadKey` which is correct), chat state (`XmppChatState`). |
| 17 | `flutter test --no-pub` | 115/115 pass. All existing tests use `@localhost` on both sides so the JID collision that revealed the bug isn't exercised — the fix is behaviour-preserving for the covered cases. |

### 5. Missing incoming-call banner — hoist `CallOverlay` above every route

**Symptom:** Live smoke reported the call ringing was invisible on Alice's emulator even though the stub confirmed a Jingle `session-initiate` had arrived. On-device `print`-based debug (temporary) showed `_handleIncomingInitiate` did run to completion and `_calls[e.sid]` was populated with `state=ringing`.

**Root cause:** `CallOverlay` was stacked only inside `HomePage`'s Scaffold body. When the user was inside a `ChatPage` / `BubbleChatPage` (pushed on top of HomePage — which is exactly when a call is most likely to arrive), the overlay was covered by the pushed route and invisible.

| # | Action | Notes |
|---|---|---|
| 18 | Move `CallOverlay` into `MaterialApp.builder` in `lib/app.dart` | `builder: (context, child) => Stack(children: [if (child != null) Positioned.fill(child: child), const Align(alignment: Alignment.topCenter, child: CallOverlay())])`. The builder wraps every route (including modals / pushed pages), so the banner is above chat, bubble, group-call, everything. |
| 19 | Remove the duplicate `CallOverlay` from `HomePage` | Body becomes `pages[tab]` again; the `call_overlay.dart` import goes with it. |
| 20 | `flutter test --no-pub` | 115/115 pass — the widget tests still exercise the CallOverlay via the CallManager's ChangeNotifier fan-out. |

### 6. Bug logged for follow-up

| # | Action | Notes |
|---|---|---|
| 21 | Append "Known bugs (post live-smoke)" to `docs/webrtc-roadmap.md` | Camera / mic tracks aren't stopped on hang-up — the `RTCPeerConnection` closes but `_localStream.getTracks()` is never iterated with `stop()`. Browser tab camera indicator + physical-device LED stay on until page reload. Fix location: `FlutterWebRtcAdapter.dispose()` and the `session-terminate` path. |

## Live evidence captured

- Signaling: `session-initiate` + trickle `transport-info` + `session-accept` + `session-terminate` all observed on the stub's `xmpp.session` logger for both directions (web → emulator and emulator → web). `fanOut user=<id> → 1 session(s)` on every hop.
- Media: browser ↔ browser 1:1 audio confirmed by ear (both Chrome tabs on `http://localhost:54321`, both pointing at the same stub over loopback).
- Emulator ↔ browser media does NOT complete. Root cause is the Android emulator's NAT gateway (10.0.2.15 internal), not client code. `logcat --pid=<app>` shows `onConnectionChangeCLOSED` and never `CONNECTED` after ICE gathering completes. Requires TURN — same story as the M-7 deferred item.

## Deviations

- No new tests. The live-smoke enablement is orthogonal to unit coverage; the two behavioural fixes (web WS, domain-tolerant matching, call overlay hoist) are subtle at the composition layer (rebuilds, imports, routing) where the existing capsule-level tests use `@localhost` on both sides and can't reproduce the JID collision, or use a fake WS transport that never hits `dart:io`. Follow-ups worth adding:
  - `phase_web_conditional_import_test.dart` — Compile-only smoke on `flutter test -d chrome --no-pub` that just imports `_xmpp_socket.dart`. Guards against future accidental `dart:io` leaks into `xmpp_client.dart`.
  - `phase_matches_thread_test.dart` — Exercises `_belongsToThread` / `_matchesThread` with mismatched-domain fixtures to lock in the local-part rule for 1:1 and the bare-JID rule for MUC.
- No iOS scaffold. The user is on Windows + Android + web; iOS gets `flutter create --platforms=ios .` + `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` / `NSAppTransportSecurity.NSAllowsArbitraryLoads=true` in a later pass.
- No coturn container. The M-7 TURN item stays deferred; the workaround is either browser ↔ browser (loopback) or a physical Android device on the same Wi-Fi as the host browser.

## API confirmations recorded

- Flutter's conditional-import syntax accepts multiple `if (...)` branches; both `dart.library.html` and `dart.library.js_interop` route to the web impl for future-compat (Flutter web is transitioning off `dart:html` to `package:web` + `dart:js_interop`).
- `WebSocketChannel.connect(uri, protocols: [...])` works uniformly on the browser via `package:web_socket_channel/web_socket_channel.dart` — no need for a browser-specific `HtmlWebSocketChannel` import.
- `MaterialApp.builder` sits above the `Navigator`, so a `Stack` there is above every pushed route. `child` is nullable when `home` is null; guard with `if (child != null) Positioned.fill(child: child)`.
- Rearch capsules resolve fine from a `MaterialApp.builder` context — the `RearchBootstrapper` sits above `MaterialApp` in `main.dart`, so `use(callManagerCapsule)` inside the overlay hits the same capsule instance the rest of the tree sees.
- Android emulator's `10.0.2.2` maps to the host loopback for outbound traffic only; inbound WebRTC media from the host browser back into the emulator's internal `10.0.2.15` fails without a TURN relay. This is emulator NAT behaviour, not a flutter_webrtc quirk.
- `flutter run -d chrome --web-port=<port>` pins the DevTools dart-vm-service and the app-serve port. Useful for hot-restart while a second incognito window points at the same port to simulate a second user.

## Next pointers

- Fix the camera/mic tracks-not-stopped bug at `FlutterWebRtcAdapter.dispose()` and on `session-terminate`. Iterate `_localStream.getTracks()`, call `track.stop()`, null out `_localStream`, notify the UI. ~10 lines.
- If a live media path off the emulator is needed, either wire coturn (see M-7 sketch in `docs/webrtc-roadmap.md`) or run the same client on a physical Android on the same Wi-Fi as the browser.
- Consider a config toggle so the diagnostics overlay can be enabled in release builds too — useful for QA smoke runs where debug builds are impractical.
