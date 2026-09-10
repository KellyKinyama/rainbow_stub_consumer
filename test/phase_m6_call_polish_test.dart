// Phase M-6 acceptance — in-call polish:
//   1. On end-of-call the manager writes a CallLogPayload capturing
//      direction, state (answered / missed / declined / failed),
//      media type, and duration.
//   2. State transitions through connecting → connected populate
//      ActiveCall.connectedAt so the duration is computed correctly.
//   3. A CallState.disconnected event kicks off an auto-hangup grace
//      timer; recovery (back to connected) cancels it.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';
import 'package:rainbow_stub_consumer/rainbow/ringer.dart';
import 'package:rainbow_stub_consumer/rainbow/webrtc_adapter.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:rainbow_stub_consumer/state/capsules/call_manager_capsule.dart';

class _FakeXmpp extends RainbowXmppClient {
  _FakeXmpp() : super(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');
  final _events = StreamController<XmppEvent>.broadcast();
  final List<({String action, String sid})> sentJingles = [];

  @override
  Stream<XmppEvent> get events => _events.stream;

  @override
  String get fullJid => 'alice@localhost/flutter';

  @override
  String sendJingle({
    required String toFullJid,
    required String action,
    required String sid,
    required String contentXml,
    String? initiator,
    String? responder,
  }) {
    sentJingles.add((action: action, sid: sid));
    return 'iq-fake';
  }

  void pushIncoming(XmppEvent e) => _events.add(e);
}

class _FakeSession implements RtcSession {
  _FakeSession({required this.direction})
    : state = direction == CallDirection.outgoing
          ? CallState.dialing
          : CallState.ringing {
    _events.add(RtcStateChanged(state));
  }

  final CallDirection direction;
  final _events = StreamController<RtcSessionEvent>.broadcast();

  @override
  CallState state;

  void push(RtcSessionEvent e) {
    if (e is RtcStateChanged) state = e.state;
    _events.add(e);
  }

  @override
  Stream<RtcSessionEvent> get events => _events.stream;

  @override
  MediaStream? get localMediaStream => null;

  @override
  MediaStream? get remoteMediaStream => null;

  @override
  Future<String> createOffer({bool audio = true, bool video = false}) async =>
      'v=0\r\n';

  @override
  Future<String> createAnswer({bool audio = true, bool video = false}) async =>
      'v=0\r\nanswer\r\n';

  @override
  Future<void> setRemoteDescription(String sdp, {required bool isOffer}) async {}

  @override
  Future<void> addRemoteIceCandidate({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) async {}

  @override
  Future<void> setMicrophoneMuted(bool muted) async {}

  @override
  Future<void> setCameraEnabled(bool enabled) async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> close() async {
    if (!_events.isClosed) await _events.close();
  }
}

class _FakeAdapter implements WebRtcAdapter {
  final sessions = <_FakeSession>[];

  @override
  Future<RtcSession> createSession({required CallDirection direction}) async {
    final s = _FakeSession(direction: direction);
    sessions.add(s);
    return s;
  }
}

class _SilentRinger implements Ringer {
  bool _on = false;
  @override
  bool get isRinging => _on;
  @override
  void start() => _on = true;
  @override
  void stop() => _on = false;
}

int _sidCounter = 0;
String _sidGen() => 'sid-${_sidCounter++}';

void main() {
  setUp(() => _sidCounter = 0);

  test(
    'answered outgoing call writes state=answered with duration on hangUp',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final logs = <CallLogPayload>[];
      final manager = CallManager(
        adapter: adapter,
        xmpp: xmpp,
        sidGen: _sidGen,
        ringer: _SilentRinger(),
        writeCallLog: (p) async => logs.add(p),
      );

      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
      final sid = await manager.startCall(
        peer: peer,
        peerFullJid: 'bob@localhost/laptop',
      );

      adapter.sessions.single.push(const RtcStateChanged(CallState.connected));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await manager.hangUp(sid);

      expect(logs, hasLength(1));
      expect(logs.single.direction, 'outgoing');
      expect(logs.single.state, 'answered');
      expect(logs.single.media, 'audio');
      expect(logs.single.durationMs, greaterThanOrEqualTo(0));
      expect(logs.single.peerJid, 'bob@localhost/laptop');
      await manager.dispose();
    },
  );

  test(
    'missed incoming call writes state=missed on session-terminate before answer',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final logs = <CallLogPayload>[];
      final manager = CallManager(
        adapter: adapter,
        xmpp: xmpp,
        sidGen: _sidGen,
        ringer: _SilentRinger(),
        writeCallLog: (p) async => logs.add(p),
      );

      xmpp.pushIncoming(
        const XmppJingle(
          fromFullJid: 'bob@localhost/laptop',
          iqId: 'iq-in',
          sid: 'm1',
          action: 'session-initiate',
          jingleXml:
              '<jingle xmlns="urn:xmpp:jingle:1" action="session-initiate" '
              'sid="m1"><content name="rtp" creator="initiator">'
              '<rainbow-sdp xmlns="urn:rainbow:jingle:sdp:1">'
              '<![CDATA[v=0]]></rainbow-sdp></content></jingle>',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      xmpp.pushIncoming(
        const XmppJingle(
          fromFullJid: 'bob@localhost/laptop',
          iqId: 'iq-term',
          sid: 'm1',
          action: 'session-terminate',
          jingleXml: '<jingle xmlns="urn:xmpp:jingle:1" '
              'action="session-terminate" sid="m1"/>',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(logs, hasLength(1));
      expect(logs.single.direction, 'incoming');
      expect(logs.single.state, 'missed');
      expect(logs.single.durationMs, 0);
      await manager.dispose();
    },
  );

  test(
    'CallState.disconnected auto-hangs up after the grace window',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final logs = <CallLogPayload>[];
      final manager = CallManager(
        adapter: adapter,
        xmpp: xmpp,
        sidGen: _sidGen,
        ringer: _SilentRinger(),
        writeCallLog: (p) async => logs.add(p),
        disconnectedGrace: const Duration(milliseconds: 50),
      );

      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
      final sid = await manager.startCall(
        peer: peer,
        peerFullJid: 'bob@localhost/laptop',
      );

      adapter.sessions.single.push(const RtcStateChanged(CallState.connected));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      adapter.sessions.single.push(
        const RtcStateChanged(CallState.disconnected),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Auto-hangup fired: session-terminate sent, ActiveCall cleared,
      // call log recorded.
      expect(
        xmpp.sentJingles.any((s) => s.action == 'session-terminate'),
        isTrue,
      );
      expect(manager.calls, isEmpty);
      expect(logs, hasLength(1));
      expect(logs.single.state, 'answered');
      expect(logs.single.direction, 'outgoing');
      await manager.dispose();
      expect(sid, isNotNull);
    },
  );

  test(
    'recovery from disconnected within grace cancels auto-hangup',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final logs = <CallLogPayload>[];
      final manager = CallManager(
        adapter: adapter,
        xmpp: xmpp,
        sidGen: _sidGen,
        ringer: _SilentRinger(),
        writeCallLog: (p) async => logs.add(p),
        disconnectedGrace: const Duration(milliseconds: 100),
      );

      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
      final sid = await manager.startCall(
        peer: peer,
        peerFullJid: 'bob@localhost/laptop',
      );

      adapter.sessions.single.push(const RtcStateChanged(CallState.connected));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      adapter.sessions.single.push(
        const RtcStateChanged(CallState.disconnected),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      adapter.sessions.single.push(const RtcStateChanged(CallState.connected));
      // Wait past the original grace window; auto-hangup should be off.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(manager.calls.containsKey(sid), isTrue);
      expect(
        xmpp.sentJingles.any((s) => s.action == 'session-terminate'),
        isFalse,
      );
      expect(logs, isEmpty);
      await manager.hangUp(sid);
      await manager.dispose();
    },
  );

  test(
    'video call writes media=video',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final logs = <CallLogPayload>[];
      final manager = CallManager(
        adapter: adapter,
        xmpp: xmpp,
        sidGen: _sidGen,
        ringer: _SilentRinger(),
        writeCallLog: (p) async => logs.add(p),
      );

      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
      final sid = await manager.startCall(
        peer: peer,
        peerFullJid: 'bob@localhost/laptop',
        video: true,
      );
      await manager.hangUp(sid);

      expect(logs.single.media, 'video');
      await manager.dispose();
    },
  );
}
