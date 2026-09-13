import 'dart:async';

import 'sfu_signaling.dart';
import 'webrtc_adapter.dart';

/// One membership in an ion-sfu group call. Wraps a single peer
/// connection (client publishes local media, subscribes to whatever the
/// SFU forwards). Reflects the simple "unified-plan sendrecv" mode of
/// ion-sfu where one PC handles both directions; the two-PC subscribe /
/// publish split from ion-sdk-flutter is a follow-up if needed.
class SfuGroupCallSession {
  SfuGroupCallSession({
    required this.signaling,
    required this.adapter,
    required this.sid,
    required this.uid,
  });

  final SfuSignaling signaling;
  final WebRtcAdapter adapter;
  final String sid;
  final String uid;

  RtcSession? _session;
  StreamSubscription<RtcSessionEvent>? _sessionSub;
  StreamSubscription<SfuServerMessage>? _sigSub;
  final _remoteStreams = <MediaStream>[];
  final _remoteStreamsController =
      StreamController<List<MediaStream>>.broadcast();
  bool _closed = false;

  /// Emits the current list of remote streams whenever a peer joins
  /// or leaves the SFU room.
  Stream<List<MediaStream>> get remoteStreams =>
      _remoteStreamsController.stream;

  /// Most recent snapshot of remote streams; cheap synchronous access
  /// for one-shot reads by the UI.
  List<MediaStream> get currentRemoteStreams =>
      List.unmodifiable(_remoteStreams);

  /// The underlying peer session. Non-null after [connect] returns.
  RtcSession? get session => _session;

  /// Publishes local media, joins the room via
  /// `signaling.join(sid, uid, offerSdp)`, and applies the SFU's
  /// answer. Wires the trickle plumbing in both directions.
  Future<void> connect({bool video = false}) async {
    if (_closed) {
      throw StateError('SfuGroupCallSession closed');
    }
    final session = await adapter.createSession(
      direction: CallDirection.outgoing,
    );
    _session = session;
    _sessionSub = session.events.listen(_onSessionEvent);
    _sigSub = signaling.messages.listen(_onServerMessage);
    final offer = await session.createOffer(video: video);
    final answer = await signaling.join(sid: sid, uid: uid, offerSdp: offer);
    await session.setRemoteDescription(answer, isOffer: false);
  }

  void _onSessionEvent(RtcSessionEvent e) {
    if (_closed) return;
    switch (e) {
      case RtcLocalIceCandidate(
        :final candidate,
        :final sdpMid,
        :final sdpMLineIndex,
      ):
        // target=0 is the publisher connection in ion-sfu's protocol.
        signaling.sendTrickle(
          candidate: candidate,
          sdpMid: sdpMid,
          sdpMLineIndex: sdpMLineIndex,
          target: 0,
        );
      case RtcRemoteTrackAdded(:final stream):
        if (stream != null && !_remoteStreams.contains(stream)) {
          _remoteStreams.add(stream);
          _remoteStreamsController.add(List.of(_remoteStreams));
        }
      case RtcStateChanged():
      case RtcLocalMediaReady():
        break;
    }
  }

  Future<void> _onServerMessage(SfuServerMessage m) async {
    if (_closed) return;
    switch (m) {
      case SfuOfferFromServer(:final sdp):
        final session = _session;
        if (session == null) return;
        await session.setRemoteDescription(sdp, isOffer: true);
        final answer = await session.createAnswer();
        await signaling.sendAnswer(sid: sid, answerSdp: answer);
      case SfuTrickleFromServer(
        :final candidate,
        :final sdpMid,
        :final sdpMLineIndex,
      ):
        await _session?.addRemoteIceCandidate(
          candidate: candidate,
          sdpMid: sdpMid,
          sdpMLineIndex: sdpMLineIndex,
        );
    }
  }

  /// Mutes / unmutes the local microphone. No-op before [connect].
  Future<void> setMicrophoneMuted(bool muted) =>
      _session?.setMicrophoneMuted(muted) ?? Future.value();

  /// Toggles the local camera track's `enabled` flag. No-op if this
  /// session was created audio-only.
  Future<void> setCameraEnabled(bool enabled) =>
      _session?.setCameraEnabled(enabled) ?? Future.value();

  /// Cycles between front and rear cameras.
  Future<void> switchCamera() => _session?.switchCamera() ?? Future.value();

  /// Routes audio through the loudspeaker (true) or the earpiece
  /// (false) on mobile. No-op on desktop / web.
  Future<void> setSpeakerphoneEnabled(bool enabled) =>
      _session?.setSpeakerphoneEnabled(enabled) ?? Future.value();

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sessionSub?.cancel();
    await _sigSub?.cancel();
    if (!_remoteStreamsController.isClosed) {
      await _remoteStreamsController.close();
    }
    await _session?.close();
    await signaling.close();
  }
}
