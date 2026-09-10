import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

import 'webrtc_adapter.dart';

/// Concrete [WebRtcAdapter] backed by the `flutter_webrtc` plugin.
/// Constructed once via [FlutterWebRtcAdapter.new] (or the
/// `webRtcAdapterCapsule`), then handed to the call layer.
class FlutterWebRtcAdapter implements WebRtcAdapter {
  FlutterWebRtcAdapter({required this.iceServers});

  /// Passed to every [RTCPeerConnection] in the shape flutter_webrtc
  /// expects: `[{ 'urls': 'stun:…' }, ...]`.
  final List<Map<String, dynamic>> iceServers;

  @override
  Future<RtcSession> createSession({required CallDirection direction}) async {
    final pc = await rtc.createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    return _FlutterWebRtcSession(pc: pc, direction: direction);
  }
}

class _FlutterWebRtcSession implements RtcSession {
  _FlutterWebRtcSession({required this.pc, required this.direction}) {
    _wire();
  }

  final rtc.RTCPeerConnection pc;
  final CallDirection direction;

  final _events = StreamController<RtcSessionEvent>.broadcast();
  CallState _state = CallState.idle;
  rtc.MediaStream? _localStream;
  rtc.MediaStream? _remoteStream;
  bool _closed = false;

  @override
  Stream<RtcSessionEvent> get events => _events.stream;

  @override
  CallState get state => _state;

  @override
  MediaStream? get localMediaStream => _localStream;

  @override
  MediaStream? get remoteMediaStream => _remoteStream;

  void _emit(RtcSessionEvent e) {
    if (_closed) return;
    if (e is RtcStateChanged) _state = e.state;
    _events.add(e);
  }

  void _wire() {
    _emit(
      RtcStateChanged(
        direction == CallDirection.outgoing
            ? CallState.dialing
            : CallState.ringing,
      ),
    );

    pc.onIceCandidate = (candidate) {
      final c = candidate.candidate;
      if (c == null || c.isEmpty) return;
      _emit(
        RtcLocalIceCandidate(
          candidate: c,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ),
      );
    };

    pc.onConnectionState = (s) {
      switch (s) {
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          _emit(const RtcStateChanged(CallState.connecting));
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _emit(const RtcStateChanged(CallState.connected));
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _emit(const RtcStateChanged(CallState.disconnected));
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _emit(const RtcStateChanged(CallState.failed));
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _emit(const RtcStateChanged(CallState.ended));
        case rtc.RTCPeerConnectionState.RTCPeerConnectionStateNew:
          break;
      }
    };

    pc.onTrack = (event) {
      final stream = event.streams.firstOrNull;
      if (stream == null) return;
      _remoteStream = stream;
      _emit(
        RtcRemoteTrackAdded(
          streamId: stream.id,
          kind: event.track.kind ?? '',
          stream: stream,
        ),
      );
    };
  }

  Future<void> _attachLocalMedia({
    required bool audio,
    required bool video,
  }) async {
    if (_localStream != null) return;
    _localStream = await rtc.navigator.mediaDevices.getUserMedia({
      'audio': audio,
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 640},
              'height': {'ideal': 480},
              'frameRate': {'ideal': 24},
            }
          : false,
    });
    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }
    _emit(RtcLocalMediaReady(_localStream));
  }

  @override
  Future<String> createOffer({bool audio = true, bool video = false}) async {
    await _attachLocalMedia(audio: audio, video: video);
    final offer = await pc.createOffer({
      'offerToReceiveAudio': audio ? 1 : 0,
      'offerToReceiveVideo': video ? 1 : 0,
    });
    await pc.setLocalDescription(offer);
    return offer.sdp ?? '';
  }

  @override
  Future<String> createAnswer({bool audio = true, bool video = false}) async {
    await _attachLocalMedia(audio: audio, video: video);
    final answer = await pc.createAnswer({});
    await pc.setLocalDescription(answer);
    return answer.sdp ?? '';
  }

  @override
  Future<void> setRemoteDescription(String sdp, {required bool isOffer}) async {
    await pc.setRemoteDescription(
      rtc.RTCSessionDescription(sdp, isOffer ? 'offer' : 'answer'),
    );
  }

  @override
  Future<void> addRemoteIceCandidate({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) async {
    await pc.addCandidate(
      rtc.RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
    );
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {
    final tracks = _localStream?.getAudioTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = !muted;
    }
  }

  @override
  Future<void> setCameraEnabled(bool enabled) async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    for (final t in tracks) {
      t.enabled = enabled;
    }
  }

  @override
  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const [];
    for (final t in tracks) {
      await rtc.Helper.switchCamera(t);
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    try {
      await pc.close();
    } catch (_) {}
    _state = CallState.ended;
    await _events.close();
  }
}
