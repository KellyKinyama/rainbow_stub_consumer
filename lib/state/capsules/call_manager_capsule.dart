import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/sdp_to_jingle.dart';
import '../../rainbow/webrtc_adapter.dart';
import '../../rainbow/xmpp_client.dart';
import 'auth_state_capsule.dart';
import 'call_capsule.dart';
import 'config_capsule.dart';
import 'xmpp_capsule.dart';

/// Snapshot of one active call held by [CallManager].
class ActiveCall {
  ActiveCall({
    required this.sid,
    required this.direction,
    required this.peerFullJid,
    required this.peerId,
    required this.session,
    this.state = CallState.idle,
  });
  final String sid;
  final CallDirection direction;
  final String peerFullJid;
  final String peerId;
  final RtcSession session;
  CallState state;
  String? pendingRemoteSdp;
}

/// App-wide call coordinator. Subscribes to `XmppJingle` events on the
/// XMPP stream and routes them to the matching [RtcSession]; also
/// serialises the local peer's offer/answer/candidates back onto the
/// wire via [RainbowXmppClient.sendJingle].
///
/// M-3 only knows about audio 1:1 calls. MUC / video / hold / DTMF
/// arrive in later phases.
class CallManager extends ChangeNotifier {
  CallManager({
    required WebRtcAdapter adapter,
    required RainbowXmppClient xmpp,
    required String Function() sidGen,
  }) : _adapter = adapter,
       _xmpp = xmpp,
       _sidGen = sidGen {
    _sub = _xmpp.events
        .where((e) => e is XmppJingle)
        .cast<XmppJingle>()
        .listen(_onJingle);
  }

  final WebRtcAdapter _adapter;
  final RainbowXmppClient _xmpp;
  final String Function() _sidGen;
  StreamSubscription<XmppJingle>? _sub;
  final Map<String, ActiveCall> _calls = {};
  final Map<String, StreamSubscription<RtcSessionEvent>> _sessionSubs = {};

  Map<String, ActiveCall> get calls => Map.unmodifiable(_calls);
  ActiveCall? get activeCall =>
      _calls.values.isEmpty ? null : _calls.values.last;

  /// Initiates an outgoing call to [peer] at [peerFullJid]. Creates a
  /// fresh [RtcSession] via the adapter, extracts an SDP offer,
  /// and fires `<jingle action="session-initiate"/>` at the peer.
  Future<String> startCall({
    required RainbowUser peer,
    required String peerFullJid,
  }) async {
    final sid = _sidGen();
    final session = await _adapter.createSession(
      direction: CallDirection.outgoing,
    );
    final call = ActiveCall(
      sid: sid,
      direction: CallDirection.outgoing,
      peerFullJid: peerFullJid,
      peerId: peer.id,
      session: session,
      state: session.state,
    );
    _calls[sid] = call;
    _wireSession(call);
    notifyListeners();

    final sdp = await session.createOffer();
    _xmpp.sendJingle(
      toFullJid: peerFullJid,
      action: 'session-initiate',
      sid: sid,
      contentXml: JingleSdpCodec.encodeContentWithSdp(sdp: sdp),
      initiator: _xmpp.fullJid,
    );
    return sid;
  }

  /// Accepts an incoming call identified by [sid]. Applies the peer's
  /// SDP offer that we buffered on `session-initiate`, generates a
  /// local answer, and sends `<jingle action="session-accept"/>`.
  Future<void> answer(String sid) async {
    final call = _calls[sid];
    if (call == null) return;
    final offer = call.pendingRemoteSdp;
    if (offer == null) return;
    await call.session.setRemoteDescription(offer, isOffer: true);
    final answer = await call.session.createAnswer();
    _xmpp.sendJingle(
      toFullJid: call.peerFullJid,
      action: 'session-accept',
      sid: sid,
      contentXml: JingleSdpCodec.encodeContentWithSdp(sdp: answer),
      responder: _xmpp.fullJid,
    );
    call.pendingRemoteSdp = null;
  }

  /// Terminates a call, notifies the peer, and closes the local
  /// session.
  Future<void> hangUp(String sid) async {
    final call = _calls[sid];
    if (call == null) return;
    _xmpp.sendJingle(
      toFullJid: call.peerFullJid,
      action: 'session-terminate',
      sid: sid,
      contentXml: '<reason><success/></reason>',
    );
    await _dropCall(sid);
  }

  Future<void> _dropCall(String sid) async {
    final call = _calls.remove(sid);
    await _sessionSubs.remove(sid)?.cancel();
    await call?.session.close();
    notifyListeners();
  }

  void _wireSession(ActiveCall call) {
    _sessionSubs[call.sid] = call.session.events.listen((e) {
      if (e is RtcStateChanged) {
        call.state = e.state;
        notifyListeners();
        if (e.state == CallState.ended) {
          unawaited(_dropCall(call.sid));
        }
      } else if (e is RtcLocalIceCandidate) {
        _xmpp.sendJingle(
          toFullJid: call.peerFullJid,
          action: 'transport-info',
          sid: call.sid,
          contentXml: JingleSdpCodec.encodeCandidateContent(
            candidate: e.candidate,
            sdpMid: e.sdpMid,
            sdpMLineIndex: e.sdpMLineIndex,
          ),
        );
      }
    });
  }

  Future<void> _onJingle(XmppJingle e) async {
    switch (e.action) {
      case 'session-initiate':
        await _handleIncomingInitiate(e);
      case 'session-accept':
        await _handleIncomingAccept(e);
      case 'transport-info':
        await _handleIncomingTransportInfo(e);
      case 'session-terminate':
        await _dropCall(e.sid);
      default:
        // Everything else (content-add, description-info, ...) is
        // ignored for M-3.
        break;
    }
  }

  Future<void> _handleIncomingInitiate(XmppJingle e) async {
    if (_calls.containsKey(e.sid)) return;
    final sdp = JingleSdpCodec.decodeSdp(e.jingleXml);
    if (sdp == null) return;
    final session = await _adapter.createSession(
      direction: CallDirection.incoming,
    );
    final peerBare = _bareOf(e.fromFullJid);
    final call = ActiveCall(
      sid: e.sid,
      direction: CallDirection.incoming,
      peerFullJid: e.fromFullJid,
      peerId: _localPart(peerBare),
      session: session,
      state: session.state,
    )..pendingRemoteSdp = sdp;
    _calls[e.sid] = call;
    _wireSession(call);
    notifyListeners();
  }

  Future<void> _handleIncomingAccept(XmppJingle e) async {
    final call = _calls[e.sid];
    if (call == null) return;
    final sdp = JingleSdpCodec.decodeSdp(e.jingleXml);
    if (sdp == null) return;
    await call.session.setRemoteDescription(sdp, isOffer: false);
  }

  Future<void> _handleIncomingTransportInfo(XmppJingle e) async {
    final call = _calls[e.sid];
    if (call == null) return;
    final c = JingleSdpCodec.decodeCandidate(e.jingleXml);
    if (c == null) return;
    await call.session.addRemoteIceCandidate(
      candidate: c.candidate,
      sdpMid: c.sdpMid,
      sdpMLineIndex: c.sdpMLineIndex,
    );
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    for (final s in _sessionSubs.values) {
      await s.cancel();
    }
    _sessionSubs.clear();
    for (final c in _calls.values) {
      await c.session.close();
    }
    _calls.clear();
    super.dispose();
  }
}

CallManager callManagerCapsule(CapsuleHandle use) {
  final adapter = use(webRtcAdapterCapsule);
  final xmpp = use(xmppCapsule);
  // Reads are for lifecycle only — auth+config are supplied so the
  // manager can be torn down + rebuilt when the user changes.
  final me = use(authCapsule).me;
  use(configCapsule);
  return use.disposable<CallManager>(
    () => CallManager(adapter: adapter, xmpp: xmpp, sidGen: _newSid),
    (m) => m.dispose(),
    [adapter, xmpp, me?.id],
  );
}

String _newSid() => 'sid-${DateTime.now().microsecondsSinceEpoch}';

String _bareOf(String jid) {
  final slash = jid.indexOf('/');
  return slash == -1 ? jid : jid.substring(0, slash);
}

String _localPart(String bareJid) {
  final at = bareJid.indexOf('@');
  return at == -1 ? bareJid : bareJid.substring(0, at);
}
