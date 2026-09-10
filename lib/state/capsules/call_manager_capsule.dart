import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:rearch/rearch.dart';

import '../../rainbow/models.dart';
import '../../rainbow/ringer.dart';
import '../../rainbow/sdp_to_jingle.dart';
import '../../rainbow/webrtc_adapter.dart';
import '../../rainbow/xmpp_client.dart';
import 'auth_state_capsule.dart';
import 'call_capsule.dart';
import 'config_capsule.dart';
import 'rest_capsule.dart';
import 'roster_capsule.dart';
import 'xmpp_capsule.dart';

/// Snapshot of one active call held by [CallManager].
class ActiveCall {
  ActiveCall({
    required this.sid,
    required this.direction,
    required this.peerFullJid,
    required this.peerId,
    required this.session,
    required this.hasVideo,
    this.peerDisplayName,
    this.state = CallState.idle,
  });
  final String sid;
  final CallDirection direction;
  final String peerFullJid;
  final String peerId;
  final RtcSession session;
  final bool hasVideo;
  String? peerDisplayName;
  CallState state;
  String? pendingRemoteSdp;

  /// Timestamp of the first `CallState.connected` transition, if
  /// any. Used to compute the call-log duration and to distinguish
  /// answered vs missed/declined calls.
  DateTime? connectedAt;

  /// Preferred label for the UI: display name if we've resolved one,
  /// otherwise the JID's local-part.
  String get displayLabel => peerDisplayName ?? peerId;
}

/// Resolves a peer's display name from an id (JID local-part).
/// Injected by the capsule so [CallManager] doesn't need to know
/// about the roster or user REST endpoints.
typedef PeerNameResolver = String? Function(String peerId);

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
    PeerNameResolver? resolvePeerName,
    Ringer? ringer,
    Future<void> Function(CallLogPayload)? writeCallLog,
    Duration disconnectedGrace = const Duration(seconds: 20),
  }) : _adapter = adapter,
       _xmpp = xmpp,
       _sidGen = sidGen,
       _resolvePeerName = resolvePeerName,
       _ringer = ringer ?? HapticRinger(),
       _writeCallLog = writeCallLog,
       _disconnectedGrace = disconnectedGrace {
    _sub = _xmpp.events
        .where((e) => e is XmppJingle)
        .cast<XmppJingle>()
        .listen(_onJingle);
  }

  final WebRtcAdapter _adapter;
  final PeerNameResolver? _resolvePeerName;
  final Ringer _ringer;
  final Future<void> Function(CallLogPayload)? _writeCallLog;
  final Duration _disconnectedGrace;
  final Map<String, Timer> _disconnectedTimers = {};
  bool _paused = false;
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
    bool video = false,
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
      peerDisplayName: peer.display.isNotEmpty
          ? peer.display
          : _resolvePeerName?.call(peer.id),
      session: session,
      hasVideo: video,
      state: session.state,
    );
    _calls[sid] = call;
    _wireSession(call);
    notifyListeners();

    final sdp = await session.createOffer(video: video);
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
    final answer = await call.session.createAnswer(video: call.hasVideo);
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
    _disconnectedTimers.remove(sid)?.cancel();
    await _sessionSubs.remove(sid)?.cancel();
    await call?.session.close();
    if (call != null) unawaited(_recordCallLog(call));
    _updateRinger();
    notifyListeners();
  }

  Future<void> _recordCallLog(ActiveCall call) async {
    if (_writeCallLog == null) return;
    final now = DateTime.now();
    final started = call.connectedAt ?? now;
    final durationMs = call.connectedAt == null
        ? 0
        : now.difference(call.connectedAt!).inMilliseconds;
    final state = _classifyState(call);
    try {
      await _writeCallLog(
        CallLogPayload(
          peerJid: call.peerFullJid,
          peerDisplay: call.peerDisplayName,
          direction: call.direction == CallDirection.outgoing
              ? 'outgoing'
              : 'incoming',
          state: state,
          media: call.hasVideo ? 'video' : 'audio',
          durationMs: durationMs,
          startedAt: started,
        ),
      );
    } on Object {
      // Best-effort — a failed call-log write shouldn't spam the UI.
    }
  }

  String _classifyState(ActiveCall call) {
    if (call.connectedAt != null) return 'answered';
    if (call.state == CallState.failed) return 'failed';
    return call.direction == CallDirection.incoming ? 'missed' : 'declined';
  }

  void _wireSession(ActiveCall call) {
    _sessionSubs[call.sid] = call.session.events.listen((e) {
      if (e is RtcStateChanged) {
        call.state = e.state;
        if (e.state == CallState.connected) {
          call.connectedAt ??= DateTime.now();
          _disconnectedTimers.remove(call.sid)?.cancel();
        } else if (e.state == CallState.disconnected) {
          // Give the peer connection a grace window to recover before
          // we auto-hang up. Timer restarts if we bounce back.
          _disconnectedTimers[call.sid]?.cancel();
          _disconnectedTimers[call.sid] = Timer(_disconnectedGrace, () {
            if (_calls.containsKey(call.sid)) {
              unawaited(hangUp(call.sid));
            }
          });
        } else if (e.state == CallState.failed) {
          _disconnectedTimers.remove(call.sid)?.cancel();
        }
        _updateRinger();
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
    // ignore: avoid_print
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
    final peerId = _localPart(peerBare);
    final call = ActiveCall(
      sid: e.sid,
      direction: CallDirection.incoming,
      peerFullJid: e.fromFullJid,
      peerId: peerId,
      peerDisplayName: _resolvePeerName?.call(peerId),
      session: session,
      hasVideo: sdp.contains('m=video'),
      state: session.state,
    )..pendingRemoteSdp = sdp;
    _calls[e.sid] = call;
    _wireSession(call);
    _updateRinger();
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

  /// Called by the top-level lifecycle observer whenever the app
  /// moves between resumed / paused / detached. M-4 uses it only to
  /// silence the ringer when the app is backgrounded — the peer
  /// connection itself is not disturbed (native flutter_webrtc handles
  /// audio session juggling on iOS / Android).
  void onAppLifecycleStateChanged(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    _updateRinger();
  }

  /// Starts the ringer iff we have an incoming call in the [ringing]
  /// state AND the app is currently resumed. Stops it in every other
  /// combination.
  void _updateRinger() {
    final shouldRing =
        !_paused &&
        _calls.values.any(
          (c) =>
              c.direction == CallDirection.incoming &&
              c.state == CallState.ringing,
        );
    if (shouldRing && !_ringer.isRinging) {
      _ringer.start();
    } else if (!shouldRing && _ringer.isRinging) {
      _ringer.stop();
    }
  }

  @override
  Future<void> dispose() async {
    _ringer.stop();
    for (final t in _disconnectedTimers.values) {
      t.cancel();
    }
    _disconnectedTimers.clear();
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
  final ringer = use(ringerCapsule);
  final rest = use(restCapsule);
  // Reads are for lifecycle only — auth+config are supplied so the
  // manager can be torn down + rebuilt when the user changes.
  final me = use(authCapsule).me;
  use(configCapsule);
  final roster = use(rosterCapsule);
  final rosterEntries = switch (roster) {
    AsyncData<List<RosterEntry>>(:final data) => data,
    _ => const <RosterEntry>[],
  };
  String? resolvePeerName(String peerId) {
    for (final r in rosterEntries) {
      if (r.peer.id == peerId) return r.peer.display;
    }
    return null;
  }

  Future<void> writeCallLog(CallLogPayload p) async {
    final userId = me?.id;
    if (userId == null) return;
    await rest.insertCallLog(
      userId: userId,
      peerJid: p.peerJid,
      peerDisplay: p.peerDisplay,
      direction: p.direction,
      state: p.state,
      media: p.media,
      durationMs: p.durationMs,
    );
  }

  return use.disposable<CallManager>(
    () => CallManager(
      adapter: adapter,
      xmpp: xmpp,
      sidGen: _newSid,
      resolvePeerName: resolvePeerName,
      ringer: ringer,
      writeCallLog: writeCallLog,
    ),
    (m) => m.dispose(),
    [adapter, xmpp, me?.id],
  );
}

/// Ringer factory capsule — overridable by tests via
/// `container.mock(ringerCapsule)`. The production default rings
/// via haptic feedback; a test can inject a no-op or scripted fake.
Ringer ringerCapsule(CapsuleHandle use) => HapticRinger();

/// Payload written by the CallManager to REST when a call ends.
/// Exposed for tests; not intended for UI consumers.
class CallLogPayload {
  const CallLogPayload({
    required this.peerJid,
    required this.peerDisplay,
    required this.direction,
    required this.state,
    required this.media,
    required this.durationMs,
    required this.startedAt,
  });
  final String peerJid;
  final String? peerDisplay;
  final String direction;
  final String state;
  final String media;
  final int durationMs;
  final DateTime startedAt;
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
