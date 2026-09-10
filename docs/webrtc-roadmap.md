# WebRTC calling roadmap

Scope: 1:1 audio + video calls between two Rainbow users, signaled via
XMPP Jingle over the existing rainbow-stub, using
[`flutter_webrtc`](https://pub.dev/packages/flutter_webrtc) on the
client and Google's public STUN server for NAT traversal.

## Constraints and non-goals

**In scope**
- 1:1 audio and video calls between signed-in users on the same
  rainbow-stub instance.
- Google STUN (`stun:stun.l.google.com:19302`) for NAT traversal.
- Basic in-call UX: mute, hang up, camera flip.
- Wire-compatible Jingle stanzas (XEP-0166 / XEP-0167 / XEP-0176) so
  the flow could later plug into a real Rainbow / ejabberd server.

**Out of scope for this roadmap**
- **TURN relay.** Google STUN alone is enough to gather server-
  reflexive candidates. If BOTH peers sit behind symmetric NATs, ICE
  will fail with no fallback. Fine for LAN demos, unreliable for
  cross-network calls. Adding coturn is a follow-up (M-7).
- Group calls / conferences. Rainbow's real product uses a mixer
  (Selective Forwarding Unit); replicating that in the stub is a
  separate project.
- Call recording, call logs beyond the existing REST log endpoint,
  push-to-ring on locked devices, screen-sharing.
- Actual PSTN / SIP interop. The stub already has
  `AsteriskConfig` fields but they're placeholders; real interop needs
  a live Asterisk instance.

## Acceptance evidence rules

Each phase must ship with:

1. `dart test` (stub) — new tests for the wire changes, and existing
   tests still pass.
2. `flutter analyze --no-pub` — no new warnings or errors.
3. `flutter test --exclude-tags=live` — no regressions.
4. A live smoke run against a running stub. Where possible, an
   automated live test in `test/live_stub_integration_test.dart`.
5. A short log in `docs/phase-<letter>-log.md`.

## Phases

### M-1 — Jingle signaling passthrough (S)

**Scope**
- New `<iq>` handler in the stub for stanzas whose first-child element
  is `<jingle xmlns="urn:xmpp:jingle:1" action="…"/>`.
- Routes `session-initiate`, `session-accept`, `session-terminate`,
  `transport-info` from the caller's session to the callee's session
  (`router.fanOut`). No persistence, no schema.
- Returns an empty `<iq type="result">` immediately to the sender so
  the client's iq bookkeeping doesn't stall.
- Ignores unknown Jingle actions with an iq error (`feature-not-
  implemented`).
- New `XmppJingle` event on the client — parses the `<iq>` payload and
  emits a raw sealed variant per action so higher layers don't have to
  re-parse.

**Acceptance**
- Stub test: alice sends a well-formed `session-initiate`, bob's
  session receives it verbatim (allowing for `from=` rewrite), and
  alice receives the empty `<iq type=result>`.
- Client offline test: parser turns a synthetic `<iq><jingle
  action="session-initiate">…</jingle></iq>` into an `XmppJingle`
  event.
- Live: none yet (no media at this layer).

**Out of M-1**
- No SDP work. Any `<description>` / `<transport>` payload is passed
  through opaquely.
- No ICE trickle correlation. Every `transport-info` is a fresh
  routing event.

### M-2 — Client Jingle senders + `flutter_webrtc` scaffold (S)

**Scope**
- `flutter_webrtc: ^0.13.x` added to `pubspec.yaml`. Android needs
  `CAMERA` + `RECORD_AUDIO` + `INTERNET` in the manifest; iOS needs
  `NSCameraUsageDescription` + `NSMicrophoneUsageDescription`
  (documented in `docs/camera-testing.md` alongside push permissions).
- New `AppConfig.iceServers` list; default:
  `[{ 'urls': 'stun:stun.l.google.com:19302' }]`.
- `RainbowXmppClient.sendJingle({toBareJid, action, sid, contentXml})`
  writes a validated `<iq type="set">` around the caller-provided
  Jingle payload.
- `RTCPeerConnection` lifecycle capsule — capsule takes a peer JID +
  direction (`incoming|outgoing`), spins up an `RTCPeerConnection`
  with `AppConfig.iceServers`, wires:
  - Local ICE candidate → `sendJingle(action: 'transport-info', ...)`.
  - `onTrack` → exposes remote `MediaStream` for the UI.
  - `onConnectionState` → surfaces `CallState.{ringing, connecting,
    connected, ended}`.
- No UI yet.

**Acceptance**
- Offline test: capsule constructs a peer connection against a
  synthetic config and its state stream transitions to `ended` when
  disposed, no dangling native handles.
- `flutter build windows --debug` succeeds.
- Manual smoke on desktop: mic permission prompt fires, capsule
  publishes local candidates.

**Out of M-2**
- No UI. No incoming ring. No audio actually flows yet because we
  haven't wired offer/answer end-to-end.

### M-3 — Loopback audio call (M)

**Scope**
- New `CallScreen` widget: outgoing dial screen (calling…) + in-call
  screen (mute, hangup).
- New `CallActionsCapsule`: `startCall(peer)`, `answer(sid)`,
  `hangUp(sid)`.
- Wire the full Jingle offer/answer:
  - Caller creates `RTCPeerConnection`, `createOffer()`, sets local
    description, extracts SDP, converts to Jingle content XML
    (helper: `SdpToJingle.encode(sdp)`; XEP-0167 minimal mapping —
    single audio content, single transport, single candidate list).
  - Sends `<iq type=set><jingle action="session-initiate" sid="…">`.
  - Callee parses payload, constructs peer connection, sets remote
    description, `createAnswer()`, sends `session-accept`.
  - Both sides then trickle ICE candidates as `transport-info`.
- Loopback validation: alice signs in as two resources
  (`alice/phone`, `alice/laptop`); one calls the other. Same-device,
  same-account — works because the stub routes by user id and each
  session is a distinct XMPP resource.

**Acceptance**
- Live smoke on Windows or a dev laptop: two Chrome tabs signed in as
  alice hear each other's mic.
- Live automated test: not feasible (needs real audio pipeline). We
  document manual steps in `docs/phase-<letter>-log.md`.
- Wire test: an integration test in `xmpp_batch_test.dart` asserts
  Jingle stanzas round-trip through the router in the expected
  sequence.

**Known limitations**
- Same-network only. Cross-NAT calls will silently fail because we
  don't have TURN.
- Chrome tabs on the same machine bypass most NAT paths, so this
  proves the signaling and codec setup but does NOT prove the ICE
  gathering works in the field.

### M-4 — Two-device 1:1 audio calling (M)

**Scope**
- Alice on device A calls Bob on device B, both signed into the same
  rainbow-stub over LAN.
- No new protocol work; this is a scale test of what M-3 shipped.
- Add proper `AppLifecycleState` handling so a backgrounded call
  doesn't drop the peer connection.
- Add ringtone (`audioplayers` or `just_audio`) for the incoming call
  UX.
- Add "who's calling" resolution — reuses roster / user REST endpoints
  to fetch the caller's display name + avatar.

**Acceptance**
- Manual smoke: alice on a Windows dev box, bob on an Android phone
  connected to the same LAN. Two-way audio verified.
- Live integration test that asserts `session-initiate` fan-outs to
  the ringing device and a `session-accept` closes the loop, even if
  we can't assert on media.

**Known limitations**
- Cross-NAT still broken. Documented in the phase log.

### M-5 — Video (M)

**Scope**
- Flip the peer connection's constraints to request video too.
- Add `RTCVideoView` widgets to the call screen. Two views: remote
  (main) + local (small overlay).
- Wire "flip camera" action via `helper.switchCamera(track)`.
- Downscale local capture on low-end devices via
  `MediaStreamConstraints`.

**Acceptance**
- Manual smoke: video appears both directions on Android + Chrome.
- Regression: audio still works.

### M-6 — In-call UX polish (S)

**Scope**
- Mute microphone (toggles `track.enabled`).
- Disable video (same pattern).
- End-of-call summary → writes an entry to the existing call-log REST
  endpoint (`POST /rainbow/enduser/v1.0/users/:id/calllogs`) so the
  history page reflects the call.
- Handle call-terminate on connection drop (auto-hangup after N
  seconds of `ConnectionState.disconnected`).
- Optional: draggable local video, tap to hide UI chrome.

### M-7 — TURN + cross-NAT calling (deferred)

**Scope**
- Add a `TurnConfig { url, username, credential }` to the app config
  and the ICE server list.
- Ship a docker-compose recipe for a local coturn instance in
  `docs/coturn-dev.md`.
- No client code changes beyond the config plumbing — `flutter_webrtc`
  handles TURN natively.

## Known bugs (post live-smoke)

- **Camera / mic tracks not stopped on hang-up.** After a video call
  ends, the local `MediaStream` from `getUserMedia` isn't fully torn
  down — the browser tab's camera indicator stays on until reload;
  same on physical Android devices with the LED. `RTCPeerConnection`
  closes fine, but `_localStream.getTracks()` is never iterated with
  `track.stop()`. Fix in `FlutterWebRtcAdapter.dispose()` and on the
  `session-terminate` path: iterate every track, call `stop()`, then
  null out `_localStream`. Repro: browser ↔ browser video call, tap
  hang-up, watch the tab indicator.

**Deferred because**
- Requires infrastructure we don't need for the day-to-day dev loop.
- Nothing else in this roadmap unblocks until we hit the "call fails
  across networks" problem, which is a M-4/M-5 field failure.

### M-8 — Group / conference calling (deferred, out of current scope)

Requires an SFU (media server) — Rainbow's real product uses one
internally. Documenting for symmetry with the ROADMAP file but not
planned here.

## Testing strategy summary

- **Stub-level Jingle routing** is tested at the wire in
  `xmpp_batch_test.dart` (M-1, M-3).
- **Client-level state machine** (peer connection lifecycle, capsule
  transitions) is tested with a fake `RTCPeerConnection` — the
  `flutter_webrtc` API is small enough to wrap behind an
  `WebRtcAdapter` interface, so tests inject a fake and drive state
  without native side effects.
- **Media / audio** cannot be automated on Windows CI; documented as
  manual smoke steps in each phase log.

## Rollback plan per phase

Every phase is a separate commit on `feat/webrtc`. If M-3 turns out to
be a rabbit hole (SDP-to-Jingle mapping is genuinely fiddly), we
revert to M-2, keep the client scaffold + config, and defer live
calling.

## Open questions we'll answer while executing

- Do we want incoming-call push via APNs/FCM in M-4, or stay in-app
  only?  (Answer defines whether the push scaffolding capsule needs a
  call-specific payload.)
- Does the app run on iOS at all yet? Right now the workspace only
  scaffolds Windows + web. iOS gets added when M-2 lands so mic
  permissions work.
- What's the acceptable fallback UX when TURN isn't configured and
  the ICE gathering times out?
