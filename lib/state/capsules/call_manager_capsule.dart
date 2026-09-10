import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/sdp_to_jingle.dart';
import '../../rainbow/webrtc_adapter.dart';
import '../../rainbow/xmpp_client.dart';
import 'call_capsule.dart';
import 'config_capsule.dart';
import 'xmpp_capsule.dart';

/// End-to-end call orchestration: outgoing offer flow, incoming
/// session-initiate flow, transport-info trickle, session-terminate.
/// The M-3a slice does not spin any UI — the UI arrives in M-3b as
/// `CallScreen`.
class CallManager extends ChangeNotifier {
  CallManager({
    required WebRtcAdapter adapter,
    required RainbowXmppClient xmpp,
    required String xmppDomain,
    required String myFullJid,
    required Stream<XmppEvent> events,
  })  : _adapter = adapter,
        _xmpp = xmpp,
        _domain = xmppDomain,
        _myFullJid = myFullJid {
    _sub = events.where((e) => e is XmppJingle).cast<XmppJingle>().listen(
      _onJingle,
    );
  }

  final WebRtcAdapter _adapter;
  final RainbowXmppClient _xmpp;
  final String _domain;
  final String _myFullJid;
  late final StreamSubscription<XmppJingle> _sub;

  final Map<String, _ActiveCall> _calls = {};

  /// Snapshot of every currently-active call. Suitable for a UI
  /// list. Order is insertion.
  List<CallSnapshot> get activeCalls =>
      _calls.values.map((c) => c.snapshot).toList(growable: false);

  /// Starts an outgoing 1:1 call to [peer]. Constructs a peer
  /// connection, mints a fresh sid, creates an SDP offer, and
  /// serialises it as a `session-initiate` Jingle iq. Returns the
  /// sid so a caller can drive `hangUp` / observe state later.
  Future<String> startCall(RainbowUser peer) async {
    final sid = _newSid();
    final peerFullJid = '${peer.id}@$_domain/flutter';
    final session = await _adapter.createSession(
      direction: CallDirection.outgoing,
    );
    final call = _ActiveCall(
      sid: sid,
      remoteFullJid: peerFullJid,
      direction: CallDirection.outgoing,
      session: session,
    );
    _calls[sid] = call;
    _wire(call);
    _publish();

    final sdp = await session.createOffer();
    final content = SdpToJingle.encode(
      sdp: sdp,
      contentName: 'audio',
      creator: 'initiator',
      media: 'audio',
    );
    _xmpp.sendJingle(
      toFullJid: peerFullJid,
      action: 'session-initiate',
      sid: sid,
      contentXml: content,
      initiator: _myFullJid,
    );
    return sid;
  }

  /// Called by the UI when the local user picks up an incoming call.
  /// Sends a `session-accept` with an SDP answer.
  Future<void> answer(String sid) async {
    final call = _calls[sid];
    if (call == null) return;
    if (call.direction != CallDirection.incoming) return;
    final sdp = await call.session.createAnswer();
    final content = SdpToJingle.encode(
      sdp: sdp,
      contentName: 'audio',
      creator: 'initiator',
      media: 'audio',
    );
    _xmpp.sendJingle(
      toFullJid: call.remoteFullJid,
      action: 'session-accept',
      sid: sid,
      contentXml: content,
      initiator: call.remoteFullJid,
      responder: _myFullJid,
    );
    call.snapshot = call.snapshot.copyWith(state: CallState.connecting);
    _publish();
  }

  /// Emits `session-terminate` and closes the local session.
  Future<void> hangUp(String sid, {String? reason}) async {
    final call = _calls.remove(sid);
    if (call == null) return;
    try {
      _xmpp.sendJingle(
        toFullJid: call.remoteFullJid,
        action: 'session-terminate',
        sid: sid,
        contentXml:
            '<reason><${_termReason(reason)}/></reason>',
      );
    } on Exception catch (_) {
      // Ignore — the WS may already be dead.
    }
    await call.dispose();
    _publish();
  }

  @override
  void dispose() {
    _sub.cancel();
    for (final c in _calls.values) {
      unawaited(c.dispose());
    }
    _calls.clear();
    super.dispose();
  }

  // ------- internals ------------------------------------------------------

  Future<void> _onJingle(XmppJingle e) async {
    switch (e.action) {
      case 'session-initiate':
        await _handleInitiate(e);
      case 'session-accept':
        await _handleAccept(e);
      case 'transport-info':
        await _handleTransportInfo(e);
      case 'session-terminate':
        await _handleTerminate(e);
    }
  }

  Future<void> _handleInitiate(XmppJingle e) async {
    if (_calls.containsKey(e.sid)) return;
    final sdp = SdpToJingle.decode(e.jingleXml);
    if (sdp == null) return;
    final session = await _adapter.createSession(
      direction: CallDirection.incoming,
    );
    final call = _ActiveCall(
      sid: e.sid,
      remoteFullJid: e.fromFullJid,
      direction: CallDirection.incoming,
      session: session,
    );
    _calls[e.sid] = call;
    _wire(call);
    await session.setRemoteDescription(sdp, isOffer: true);
    _publish();
  }

  Future<void> _handleAccept(XmppJingle e) async {
    final call = _calls[e.sid];
    if (call == null) return;
    final sdp = SdpToJingle.decode(e.jingleXml);
    if (sdp == null) return;
    await call.session.setRemoteDescription(sdp, isOffer: false);
    call.snapshot = call.snapshot.copyWith(state: CallState.connecting);
    _publish();
  }

  Future<void> _handleTransportInfo(XmppJingle e) async {
    final call = _calls[e.sid];
    if (call == null) return;
    final cand = SdpToJingle.decodeCandidate(e.jingleXml);
    if (cand == null) return;
    await call.session.addRemoteIceCandidate(
      candidate: cand.candidate,
      sdpMid: cand.sdpMid,
      sdpMLineIndex: cand.sdpMLineIndex,
    );
  }

  Future<void> _handleTerminate(XmppJingle e) async {
    final call = _calls.remove(e.sid);
    if (call == null) return;
    await call.dispose();
    _publish();
  }

  void _wire(_ActiveCall call) {
    call.session.events.listen((event) {
      switch (event) {
        case RtcStateChanged(:final state):
          call.snapshot = call.snapshot.copyWith(state: state);
          if (state == CallState.ended || state == CallState.failed) {
            _calls.remove(call.sid);
          }
          _publish();
        case RtcLocalIceCandidate(
              :final candidate,
              :final sdpMid,
              :final sdpMLineIndex,
            ):
          final content = SdpToJingle.encodeCandidate(
            candidate: candidate,
            sdpMid: sdpMid,
            sdpMLineIndex: sdpMLineIndex,
          );
          _xmpp.sendJingle(
            toFullJid: call.remoteFullJid,
            action: 'transport-info',
            sid: call.sid,
            contentXml: content,
          );
        case RtcRemoteTrackAdded():
          break;
      }
    });
  }

  void _publish() => notifyListeners();

  String _newSid() {
    final r = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buf.write(r.nextInt(16).toRadixString(16));
    }
    return 'sid-$buf';
  }

  String _termReason(String? reason) {
    switch (reason) {
      case 'busy':
        return 'busy';
      case 'decline':
        return 'decline';
      case 'timeout':
        return 'timeout';
      default:
        return 'success';
    }
  }
}

class _ActiveCall {
  _ActiveCall({
    required this.sid,
    required this.remoteFullJid,
    required this.direction,
    required this.session,
  }) : snapshot = CallSnapshot(
         sid: sid,
         direction: direction,
         state: direction == CallDirection.outgoing
             ? CallState.dialing
             : CallState.ringing,
       );

  final String sid;
  final String remoteFullJid;
  final CallDirection direction;
  final RtcSession session;
  CallSnapshot snapshot;

  Future<void> dispose() => session.close();
}

/// Long-lived singleton (per rearch container). The UI reads the
/// returned [CallManager] to call `startCall` / `answer` / `hangUp`
/// and to observe `activeCalls` reactively via `ListenableBuilder`.
CallManager callManagerCapsule(CapsuleHandle use) {
  final adapter = use(webRtcAdapterCapsule);
  final events = use(xmppEventsCapsule);
  final xmpp = use(xmppCapsule);
  final config = use(configCapsule);

  final slot = use.data<CallManager?>(null);
  use.effect(() {
    final mgr = CallManager(
      adapter: adapter,
      xmpp: xmpp,
      xmppDomain: config.xmppDomain,
      myFullJid: xmpp.fullJid,
      events: events,
    );
    slot.value = mgr;
    return mgr.dispose;
  }, [adapter, xmpp, events, config.xmppDomain]);

  return slot.value ??
      CallManager(
        adapter: adapter,
        xmpp: xmpp,
        xmppDomain: config.xmppDomain,
        myFullJid: xmpp.fullJid,
        events: events,
      );
}
