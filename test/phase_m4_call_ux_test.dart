// Phase M-4 acceptance — call UX layer built on top of the M-3
// CallManager. Verifies:
//   1. Incoming ringing state starts a ringer; ringer stops on
//      answer/hangup/session-terminate.
//   2. App lifecycle transitions silence the ringer while paused
//      and re-arm it when resumed with an incoming call still ringing.
//   3. Roster-based display name flows into ActiveCall.
import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';
import 'package:rainbow_stub_consumer/rainbow/ringer.dart';
import 'package:rainbow_stub_consumer/rainbow/webrtc_adapter.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:rainbow_stub_consumer/state/capsules/call_manager_capsule.dart';

class _FakeXmpp extends RainbowXmppClient {
  _FakeXmpp() : super(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');
  final _events = StreamController<XmppEvent>.broadcast();

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
  }) => 'iq-fake';

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
  Future<String> createOffer({bool audio = true, bool video = false}) async =>
      'v=0\r\no=fake\r\n';

  @override
  Future<String> createAnswer({bool audio = true, bool video = false}) async =>
      'v=0\r\no=fake-answer\r\n';

  @override
  Future<void> setRemoteDescription(
    String sdp, {
    required bool isOffer,
  }) async {}

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
  Future<void> setSpeakerphoneEnabled(bool enabled) async {}

  @override
  MediaStream? get localMediaStream => null;

  @override
  MediaStream? get remoteMediaStream => null;

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
  int startCount = 0;
  int stopCount = 0;
  bool _on = false;

  @override
  bool get isRinging => _on;

  @override
  void start() {
    if (_on) return;
    _on = true;
    startCount++;
  }

  @override
  void stop() {
    if (!_on) return;
    _on = false;
    stopCount++;
  }
}

int _sidCounter = 0;
String _sidGen() => 'sid-${_sidCounter++}';

CallManager _makeManager({
  required _FakeXmpp xmpp,
  required _FakeAdapter adapter,
  required Ringer ringer,
  PeerNameResolver? resolvePeerName,
}) => CallManager(
  adapter: adapter,
  xmpp: xmpp,
  sidGen: _sidGen,
  ringer: ringer,
  resolvePeerName: resolvePeerName,
);

XmppJingle _incomingInitiate({
  required String sid,
  String from = 'bob@localhost/laptop',
}) => XmppJingle(
  fromFullJid: from,
  iqId: 'iq-in-$sid',
  sid: sid,
  action: 'session-initiate',
  jingleXml:
      '<jingle xmlns="urn:xmpp:jingle:1" action="session-initiate" sid="$sid">'
      '<content name="rtp" creator="initiator">'
      '<rainbow-sdp xmlns="urn:rainbow:jingle:sdp:1">'
      '<![CDATA[v=0\r\no=peer\r\n]]></rainbow-sdp>'
      '</content></jingle>',
);

void main() {
  setUp(() => _sidCounter = 0);

  test('incoming ringing call starts the ringer; answer stops it', () async {
    final xmpp = _FakeXmpp();
    final adapter = _FakeAdapter();
    final ringer = _SilentRinger();
    final manager = _makeManager(xmpp: xmpp, adapter: adapter, ringer: ringer);

    xmpp.pushIncoming(_incomingInitiate(sid: 'r1'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(ringer.isRinging, isTrue);
    expect(ringer.startCount, 1);

    await manager.answer('r1');
    // answer() triggers state changes downstream — the fake session
    // is still 'ringing' by our contract, so we simulate the transition.
    adapter.sessions.single.push(const RtcStateChanged(CallState.connecting));
    await Future<void>.delayed(Duration.zero);

    expect(ringer.isRinging, isFalse);
    expect(ringer.stopCount, 1);

    await manager.dispose();
  });

  test(
    'session-terminate on a ringing incoming call stops the ringer',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final ringer = _SilentRinger();
      final manager = _makeManager(
        xmpp: xmpp,
        adapter: adapter,
        ringer: ringer,
      );

      xmpp.pushIncoming(_incomingInitiate(sid: 'r2'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(ringer.isRinging, isTrue);

      xmpp.pushIncoming(
        const XmppJingle(
          fromFullJid: 'bob@localhost/laptop',
          iqId: 'iq-term',
          sid: 'r2',
          action: 'session-terminate',
          jingleXml:
              '<jingle xmlns="urn:xmpp:jingle:1" '
              'action="session-terminate" sid="r2"/>',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(ringer.isRinging, isFalse);
      expect(manager.calls, isEmpty);
      await manager.dispose();
    },
  );

  test('lifecycle=paused silences the ringer; resumed re-arms it if still '
      'ringing', () async {
    final xmpp = _FakeXmpp();
    final adapter = _FakeAdapter();
    final ringer = _SilentRinger();
    final manager = _makeManager(xmpp: xmpp, adapter: adapter, ringer: ringer);

    xmpp.pushIncoming(_incomingInitiate(sid: 'r3'));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(ringer.isRinging, isTrue);

    manager.onAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(ringer.isRinging, isFalse);

    manager.onAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(ringer.isRinging, isTrue);

    await manager.dispose();
  });

  test(
    'resolvePeerName populates ActiveCall.peerDisplayName on incoming',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final ringer = _SilentRinger();
      final manager = _makeManager(
        xmpp: xmpp,
        adapter: adapter,
        ringer: ringer,
        resolvePeerName: (id) => id == 'bob' ? 'Bob Sample' : null,
      );

      xmpp.pushIncoming(_incomingInitiate(sid: 'r4'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final call = manager.calls['r4']!;
      expect(call.peerDisplayName, 'Bob Sample');
      expect(call.displayLabel, 'Bob Sample');
      await manager.dispose();
    },
  );

  test('startCall carries the RainbowUser.display when non-empty', () async {
    final xmpp = _FakeXmpp();
    final adapter = _FakeAdapter();
    final ringer = _SilentRinger();
    final manager = _makeManager(
      xmpp: xmpp,
      adapter: adapter,
      ringer: ringer,
      // Resolver would return null; the user object's display wins.
      resolvePeerName: (id) => null,
    );

    final peer = RainbowUser(
      id: 'carol',
      firstName: 'Carol',
      lastName: 'Danvers',
      loginEmail: 'carol@localhost',
    );
    final sid = await manager.startCall(
      peer: peer,
      peerFullJid: 'carol@localhost/laptop',
    );

    expect(manager.calls[sid]!.displayLabel, 'Carol Danvers');
    await manager.dispose();
  });
}
