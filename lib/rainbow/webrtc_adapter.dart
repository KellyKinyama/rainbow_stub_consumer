/// Thin adapter over the parts of `flutter_webrtc` this app uses.
///
/// The real implementation ([FlutterWebRtcAdapter]) lives in
/// `webrtc_adapter_impl.dart`. Tests use a `FakeWebRtcAdapter` (see
/// `test/phase_m2_call_capsule_test.dart`) so unit tests never call
/// into native WebRTC.
library;

import 'dart:async';

/// Direction of a call from the local user's point of view.
enum CallDirection { outgoing, incoming }

/// Lifecycle state of an [RtcSession]. Maps loosely onto
/// `RTCPeerConnectionState` from flutter_webrtc, plus higher-level
/// states the UI needs (dialing / ringing).
enum CallState {
  idle,
  dialing,
  ringing,
  connecting,
  connected,
  disconnected,
  failed,
  ended,
}

/// One event emitted on the [RtcSession.events] stream.
sealed class RtcSessionEvent {
  const RtcSessionEvent();
}

class RtcStateChanged extends RtcSessionEvent {
  const RtcStateChanged(this.state);
  final CallState state;
}

class RtcLocalIceCandidate extends RtcSessionEvent {
  const RtcLocalIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
}

class RtcRemoteTrackAdded extends RtcSessionEvent {
  const RtcRemoteTrackAdded({required this.streamId, required this.kind});
  final String streamId;
  final String kind;
}

/// A single peer-connection lifecycle, one per call.
abstract class RtcSession {
  /// Merged event stream — state changes, local ICE candidates,
  /// remote track additions. Broadcast so the capsule can subscribe
  /// multiple times without stalling the source.
  Stream<RtcSessionEvent> get events;

  /// Most recent state observed. Cheap synchronous accessor.
  CallState get state;

  /// Creates a local SDP offer for a fresh outgoing call. Sets it as
  /// the local description.
  Future<String> createOffer({bool audio = true, bool video = false});

  /// Creates a local SDP answer AFTER a remote offer was set via
  /// [setRemoteDescription].
  Future<String> createAnswer({bool audio = true, bool video = false});

  /// Applies the peer's SDP.
  Future<void> setRemoteDescription(String sdp, {required bool isOffer});

  /// Adds a remote ICE candidate received via signaling.
  Future<void> addRemoteIceCandidate({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  });

  /// Toggles the local audio track's `enabled` flag. No-op before an
  /// offer has been created.
  Future<void> setMicrophoneMuted(bool muted);

  /// Closes the peer connection and releases native resources. Idempotent.
  Future<void> close();
}

/// Adapter factory. Implementations own the ICE server list — the
/// caller doesn't hand out `iceServers` to individual sessions.
abstract class WebRtcAdapter {
  Future<RtcSession> createSession({required CallDirection direction});
}
