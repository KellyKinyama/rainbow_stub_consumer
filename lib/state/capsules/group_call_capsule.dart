import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rearch/rearch.dart';
import 'package:web_socket_channel/io.dart';

import '../../rainbow/models.dart';
import '../../rainbow/sfu_group_call.dart';
import '../../rainbow/sfu_signaling.dart';
import '../../rainbow/webrtc_adapter.dart';
import '../../rainbow/xmpp_client.dart';
import 'auth_state_capsule.dart';
import 'call_capsule.dart';
import 'config_capsule.dart';
import 'xmpp_capsule.dart';

/// Factory that produces an [SfuSignaling] transport for [sfuUrl].
/// Overridable in tests so unit specs use an in-memory pipe.
typedef SfuSignalingFactory = Future<SfuSignaling> Function(Uri sfuUrl);

/// One live group-call membership.
class ActiveGroupCall {
  ActiveGroupCall({
    required this.roomBareJid,
    required this.sid,
    required this.session,
  });
  final String roomBareJid;
  final String sid;
  final SfuGroupCallSession session;

  /// Local moderator-set flag. The stub has no real "lock" wire
  /// concept, so this is a client-side UI toggle for parity with the
  /// RN sample's `LockConfButton`.
  bool locked = false;
}

/// Global coordinator for MUC group calls. Tracks which bubbles have
/// an open call (based on inbound `<call state="started"/>` markers)
/// and owns the [SfuGroupCallSession] instances for calls we've
/// joined.
class GroupCallManager extends ChangeNotifier {
  GroupCallManager({
    required WebRtcAdapter adapter,
    required RainbowXmppClient xmpp,
    required this.uid,
    required this.xmppDomain,
    required SfuSignalingFactory signalingFactory,
    Uri? sfuUrl,
    String Function()? sidGen,
  }) : _adapter = adapter,
       _xmpp = xmpp,
       _signalingFactory = signalingFactory,
       _sfuUrl = sfuUrl,
       _sidGen = sidGen ?? _defaultSidGen {
    _sub = _xmpp.events
        .where((e) => e is XmppMucCallMarker)
        .cast<XmppMucCallMarker>()
        .listen(_onMarker);
  }

  final WebRtcAdapter _adapter;
  final RainbowXmppClient _xmpp;
  final SfuSignalingFactory _signalingFactory;
  final Uri? _sfuUrl;
  final String Function() _sidGen;

  /// Local user id — used as the SFU `uid` and to skip our own
  /// broadcast markers when they echo back off the MUC.
  final String uid;
  final String xmppDomain;

  StreamSubscription<XmppMucCallMarker>? _sub;
  final Map<String, XmppMucCallMarker> _openMarkers = {};
  final Map<String, ActiveGroupCall> _joined = {};

  /// True when [sfuUrl] was configured — the UI hides all group-call
  /// controls otherwise.
  bool get isEnabled => _sfuUrl != null;

  Map<String, ActiveGroupCall> get joinedCalls => Map.unmodifiable(_joined);

  /// Returns the "call is happening in this room right now" marker,
  /// or null if none. Used by the UI to show a "Join call" chip.
  XmppMucCallMarker? openCallIn(String roomBareJid) =>
      _openMarkers[roomBareJid];

  /// Initiates a new group call in [bubble]. Announces the sid over
  /// MUC and joins the SFU room.
  Future<ActiveGroupCall> startGroupCall({
    required RainbowBubble bubble,
    bool video = false,
  }) async {
    if (_sfuUrl == null) {
      throw StateError('AppConfig.sfuUrl is not configured');
    }
    final sid = _sidGen();
    final roomJid = _mucJidOf(bubble);
    _xmpp.sendMucCallMarker(roomBareJid: roomJid, state: 'started', sid: sid);
    return _joinSfuRoom(roomJid: roomJid, sid: sid, video: video);
  }

  /// Joins an existing group call that someone else already announced.
  Future<ActiveGroupCall> joinGroupCall({
    required String roomBareJid,
    required String sid,
    bool video = false,
  }) async {
    if (_sfuUrl == null) {
      throw StateError('AppConfig.sfuUrl is not configured');
    }
    return _joinSfuRoom(roomJid: roomBareJid, sid: sid, video: video);
  }

  /// Leaves the local user's active membership in [roomBareJid]. If
  /// this was the last member the marker on the wire will remain
  /// "started" until whoever hangs up last announces "ended".
  Future<void> leaveGroupCall(
    String roomBareJid, {
    bool announceEnd = false,
  }) async {
    final call = _joined.remove(roomBareJid);
    if (call == null) return;
    if (announceEnd) {
      _xmpp.sendMucCallMarker(
        roomBareJid: roomBareJid,
        state: 'ended',
        sid: call.sid,
      );
    }
    await call.session.close();
    notifyListeners();
  }

  /// Client-side moderator lock. RN parity only \u2014 no wire effect
  /// against this stub; the flag drives UI on all participants that
  /// share the manager instance (i.e. the local one only).
  void setRoomLocked(String roomBareJid, bool locked) {
    final call = _joined[roomBareJid];
    if (call == null || call.locked == locked) return;
    call.locked = locked;
    notifyListeners();
  }

  Future<ActiveGroupCall> _joinSfuRoom({
    required String roomJid,
    required String sid,
    required bool video,
  }) async {
    final signaling = await _signalingFactory(_sfuUrl!);
    final session = SfuGroupCallSession(
      signaling: signaling,
      adapter: _adapter,
      sid: sid,
      uid: uid,
    );
    try {
      await session.connect(video: video);
    } on Object {
      await session.close();
      rethrow;
    }
    final call = ActiveGroupCall(
      roomBareJid: roomJid,
      sid: sid,
      session: session,
    );
    _joined[roomJid] = call;
    notifyListeners();
    return call;
  }

  void _onMarker(XmppMucCallMarker m) {
    // Skip our own echoed markers so we don't re-render a "Join call"
    // chip for a call we just initiated.
    if (m.fromResource == uid) return;
    switch (m.state) {
      case 'started':
        _openMarkers[m.roomBareJid] = m;
      case 'ended':
        final open = _openMarkers[m.roomBareJid];
        if (open?.sid == m.sid) _openMarkers.remove(m.roomBareJid);
    }
    notifyListeners();
  }

  String _mucJidOf(RainbowBubble b) => '${b.id}@muc.$xmppDomain';

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    for (final c in _joined.values) {
      await c.session.close();
    }
    _joined.clear();
    super.dispose();
  }
}

Future<SfuSignaling> _defaultSignalingFactory(Uri sfuUrl) async {
  final channel = IOWebSocketChannel.connect(
    sfuUrl,
    protocols: const ['json-rpc-2.0'],
  );
  await channel.ready;
  return JsonRpcSfuSignaling(channel);
}

String _defaultSidGen() => 'gc-${DateTime.now().microsecondsSinceEpoch}';

GroupCallManager groupCallManagerCapsule(CapsuleHandle use) {
  final adapter = use(webRtcAdapterCapsule);
  final xmpp = use(xmppCapsule);
  final me = use(authCapsule).me;
  final config = use(configCapsule);
  return use.disposable<GroupCallManager>(
    () => GroupCallManager(
      adapter: adapter,
      xmpp: xmpp,
      uid: me?.id ?? 'me',
      xmppDomain: config.xmppDomain,
      sfuUrl: config.sfuUrl,
      signalingFactory: _defaultSignalingFactory,
    ),
    (m) => m.dispose(),
    [adapter, xmpp, me?.id, config.sfuUrl?.toString()],
  );
}
