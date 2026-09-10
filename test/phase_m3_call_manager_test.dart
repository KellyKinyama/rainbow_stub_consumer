// Phase M-3 acceptance — CallManager glues XmppJingle events to the
// M-2 WebRtcAdapter. Fake XMPP + fake adapter drive:
//   1. startCall → session-initiate sent with SDP wrapped by
//      JingleSdpCodec.
//   2. Local ICE candidate → transport-info sent.
//   3. Inbound session-accept → remote SDP applied.
//   4. Inbound transport-info → remote candidate applied.
//   5. Inbound session-terminate → local session closed.
//   6. Inbound session-initiate → incoming ActiveCall registered with
//      pendingRemoteSdp populated.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/config.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';
import 'package:rainbow_stub_consumer/rainbow/rest_client.dart';
import 'package:rainbow_stub_consumer/rainbow/ringer.dart';
import 'package:rainbow_stub_consumer/rainbow/sdp_to_jingle.dart';
import 'package:rainbow_stub_consumer/rainbow/webrtc_adapter.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:rainbow_stub_consumer/state/capsules/auth_controller_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/call_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/call_manager_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/rest_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/xmpp_capsule.dart';
import 'package:rearch/rearch.dart';

class _FakeRest extends RainbowRestClient {
  _FakeRest() : super(AppConfig.dev);

  @override
  Future<LoginResult> login(String email, String password) async => LoginResult(
    token: 'tkn',
    expiresIn: 3600,
    loggedInUser: RainbowUser(id: 'alice', loginEmail: email),
  );

  @override
  Future<void> logout() async {}

  @override
  void close() {}
}

class _FakeXmpp extends RainbowXmppClient {
  _FakeXmpp() : super(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');
  final _events = StreamController<XmppEvent>.broadcast();
  final List<({String to, String action, String sid, String content})>
  sentJingles = [];

  @override
  Stream<XmppEvent> get events => _events.stream;

  @override
  String get fullJid => 'alice@localhost/flutter';

  @override
  Future<void> connect({
    required String email,
    required String saslPassword,
    String resource = 'flutter',
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  String sendJingle({
    required String toFullJid,
    required String action,
    required String sid,
    required String contentXml,
    String? initiator,
    String? responder,
  }) {
    sentJingles.add((
      to: toFullJid,
      action: action,
      sid: sid,
      content: contentXml,
    ));
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
  final remoteSdps = <({String sdp, bool isOffer})>[];
  final remoteCandidates =
      <({String candidate, String? sdpMid, int? sdpMLineIndex})>[];
  int offersCreated = 0;
  int answersCreated = 0;
  bool closed = false;

  void push(RtcSessionEvent e) {
    if (e is RtcStateChanged) state = e.state;
    _events.add(e);
  }

  @override
  Stream<RtcSessionEvent> get events => _events.stream;

  @override
  Future<String> createOffer({bool audio = true, bool video = false}) async {
    offersCreated++;
    return 'v=0\r\no=fake-offer\r\n';
  }

  @override
  Future<String> createAnswer({bool audio = true, bool video = false}) async {
    answersCreated++;
    return 'v=0\r\no=fake-answer\r\n';
  }

  @override
  Future<void> setRemoteDescription(String sdp, {required bool isOffer}) async {
    remoteSdps.add((sdp: sdp, isOffer: isOffer));
  }

  @override
  Future<void> addRemoteIceCandidate({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) async {
    remoteCandidates.add((
      candidate: candidate,
      sdpMid: sdpMid,
      sdpMLineIndex: sdpMLineIndex,
    ));
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {}

  @override
  Future<void> setCameraEnabled(bool enabled) async {}

  @override
  Future<void> switchCamera() async {}

  @override
  MediaStream? get localMediaStream => null;

  @override
  MediaStream? get remoteMediaStream => null;

  @override
  Future<void> close() async {
    closed = true;
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

void main() {
  late _FakeRest fakeRest;
  late _FakeXmpp fakeXmpp;
  late _FakeAdapter fakeAdapter;
  late MockableContainer container;

  setUp(() async {
    fakeRest = _FakeRest();
    fakeXmpp = _FakeXmpp();
    fakeAdapter = _FakeAdapter();
    container = MockableContainer();
    container.mock(restCapsule).apply((use) => fakeRest);
    container.mock(xmppCapsule).apply((use) => fakeXmpp);
    container.mock(webRtcAdapterCapsule).apply((use) => fakeAdapter);
    container.mock(ringerCapsule).apply((use) => _SilentRinger());
    final auth = container.read(authControllerCapsule);
    await auth.signIn('alice@rainbow-stub.local', 'pw');
  });

  tearDown(() {
    container.dispose();
  });

  test(
    'startCall opens a session, sends session-initiate carrying the SDP',
    () async {
      final manager = container.read(callManagerCapsule);
      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

      final sid = await manager.startCall(
        peer: peer,
        peerFullJid: 'bob@localhost/laptop',
      );

      expect(fakeAdapter.sessions, hasLength(1));
      expect(fakeAdapter.sessions.single.direction, CallDirection.outgoing);
      expect(fakeAdapter.sessions.single.offersCreated, 1);

      final initiate = fakeXmpp.sentJingles.singleWhere(
        (s) => s.action == 'session-initiate',
      );
      expect(initiate.sid, sid);
      expect(initiate.to, 'bob@localhost/laptop');
      final embeddedSdp = JingleSdpCodec.decodeSdp(
        '<jingle xmlns="urn:xmpp:jingle:1" action="session-initiate">'
        '${initiate.content}</jingle>',
      );
      expect(embeddedSdp, contains('fake-offer'));

      expect(manager.calls[sid]!.direction, CallDirection.outgoing);
      expect(manager.calls[sid]!.peerId, 'bob');
    },
  );

  test('local ICE candidate fires transport-info', () async {
    final manager = container.read(callManagerCapsule);
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
    final sid = await manager.startCall(
      peer: peer,
      peerFullJid: 'bob@localhost/laptop',
    );

    fakeAdapter.sessions.single.push(
      const RtcLocalIceCandidate(
        candidate: 'candidate:1 1 udp 1 10.0.0.1 55555 typ host',
        sdpMid: 'audio',
        sdpMLineIndex: 0,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final ti = fakeXmpp.sentJingles.singleWhere(
      (s) => s.action == 'transport-info',
    );
    expect(ti.sid, sid);
    final decoded = JingleSdpCodec.decodeCandidate(
      '<jingle xmlns="urn:xmpp:jingle:1" action="transport-info">'
      '${ti.content}</jingle>',
    );
    expect(decoded, isNotNull);
    expect(decoded!.candidate, contains('10.0.0.1'));
    expect(decoded.sdpMid, 'audio');
    expect(decoded.sdpMLineIndex, 0);
  });

  test('inbound session-accept applies remote SDP', () async {
    final manager = container.read(callManagerCapsule);
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
    final sid = await manager.startCall(
      peer: peer,
      peerFullJid: 'bob@localhost/laptop',
    );

    fakeXmpp.pushIncoming(
      XmppJingle(
        fromFullJid: 'bob@localhost/laptop',
        iqId: 'iq-bob-1',
        sid: sid,
        action: 'session-accept',
        jingleXml:
            '<jingle xmlns="urn:xmpp:jingle:1" action="session-accept" sid="$sid">'
            '<content name="rtp" creator="initiator">'
            '<rainbow-sdp xmlns="urn:rainbow:jingle:sdp:1">'
            '<![CDATA[v=0\r\no=peer-answer\r\n]]>'
            '</rainbow-sdp>'
            '</content>'
            '</jingle>',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(fakeAdapter.sessions.single.remoteSdps, hasLength(1));
    expect(fakeAdapter.sessions.single.remoteSdps.single.isOffer, isFalse);
    expect(
      fakeAdapter.sessions.single.remoteSdps.single.sdp,
      contains('peer-answer'),
    );
  });

  test('inbound transport-info applies remote candidate', () async {
    final manager = container.read(callManagerCapsule);
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
    final sid = await manager.startCall(
      peer: peer,
      peerFullJid: 'bob@localhost/laptop',
    );

    // Trickle-ICE candidates that arrive before the remote description
    // is set must be buffered (the browser throws InvalidStateError
    // otherwise). Push the candidate first, then session-accept, and
    // expect the candidate to land on the adapter after the drain.
    fakeXmpp.pushIncoming(
      XmppJingle(
        fromFullJid: 'bob@localhost/laptop',
        iqId: 'iq-bob-2',
        sid: sid,
        action: 'transport-info',
        jingleXml:
            '<jingle xmlns="urn:xmpp:jingle:1" action="transport-info" sid="$sid">'
            '<content name="rtp" creator="initiator">'
            '<rainbow-candidate xmlns="urn:rainbow:jingle:sdp:1" '
            'line="candidate:9 1 udp 2 172.16.0.5 44444 typ srflx" '
            'sdp-mid="audio" sdp-m-line-index="0"/>'
            '</content>'
            '</jingle>',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      fakeAdapter.sessions.single.remoteCandidates,
      isEmpty,
      reason: 'candidate must be buffered until remote description is set',
    );

    fakeXmpp.pushIncoming(
      XmppJingle(
        fromFullJid: 'bob@localhost/laptop',
        iqId: 'iq-bob-3',
        sid: sid,
        action: 'session-accept',
        jingleXml:
            '<jingle xmlns="urn:xmpp:jingle:1" action="session-accept" sid="$sid">'
            '<content name="rtp" creator="initiator">'
            '<rainbow-sdp xmlns="urn:rainbow:jingle:sdp:1">'
            '<![CDATA[v=0\r\no=peer-answer\r\n]]>'
            '</rainbow-sdp>'
            '</content>'
            '</jingle>',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(fakeAdapter.sessions.single.remoteCandidates, hasLength(1));
    expect(
      fakeAdapter.sessions.single.remoteCandidates.single.candidate,
      contains('172.16.0.5'),
    );
  });

  test('inbound session-terminate closes local session', () async {
    final manager = container.read(callManagerCapsule);
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
    final sid = await manager.startCall(
      peer: peer,
      peerFullJid: 'bob@localhost/laptop',
    );

    fakeXmpp.pushIncoming(
      XmppJingle(
        fromFullJid: 'bob@localhost/laptop',
        iqId: 'iq-bob-3',
        sid: sid,
        action: 'session-terminate',
        jingleXml:
            '<jingle xmlns="urn:xmpp:jingle:1" action="session-terminate" '
            'sid="$sid"/>',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(fakeAdapter.sessions.single.closed, isTrue);
    expect(manager.calls, isEmpty);
  });

  test('inbound session-initiate registers an incoming ActiveCall with '
      'pending SDP; answer() sends session-accept', () async {
    final manager = container.read(callManagerCapsule);

    fakeXmpp.pushIncoming(
      const XmppJingle(
        fromFullJid: 'bob@localhost/laptop',
        iqId: 'iq-in-1',
        sid: 'incoming-sid-1',
        action: 'session-initiate',
        jingleXml:
            '<jingle xmlns="urn:xmpp:jingle:1" action="session-initiate" '
            'sid="incoming-sid-1">'
            '<content name="rtp" creator="initiator">'
            '<rainbow-sdp xmlns="urn:rainbow:jingle:sdp:1">'
            '<![CDATA[v=0\r\no=peer-offer\r\n]]>'
            '</rainbow-sdp>'
            '</content>'
            '</jingle>',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final call = manager.calls['incoming-sid-1']!;
    expect(call.direction, CallDirection.incoming);
    expect(call.state, CallState.ringing);
    expect(call.pendingRemoteSdp, contains('peer-offer'));

    await manager.answer('incoming-sid-1');

    expect(fakeAdapter.sessions.single.remoteSdps.first.isOffer, isTrue);
    expect(
      fakeAdapter.sessions.single.remoteSdps.first.sdp,
      contains('peer-offer'),
    );
    expect(fakeAdapter.sessions.single.answersCreated, 1);

    final accept = fakeXmpp.sentJingles.singleWhere(
      (s) => s.action == 'session-accept',
    );
    expect(accept.sid, 'incoming-sid-1');
    final answerSdp = JingleSdpCodec.decodeSdp(
      '<jingle xmlns="urn:xmpp:jingle:1" action="session-accept">'
      '${accept.content}</jingle>',
    );
    expect(answerSdp, contains('fake-answer'));
  });

  test('hangUp sends session-terminate and closes locally', () async {
    final manager = container.read(callManagerCapsule);
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
    final sid = await manager.startCall(
      peer: peer,
      peerFullJid: 'bob@localhost/laptop',
    );

    await manager.hangUp(sid);

    expect(
      fakeXmpp.sentJingles.any((s) => s.action == 'session-terminate'),
      isTrue,
    );
    expect(fakeAdapter.sessions.single.closed, isTrue);
    expect(manager.calls, isEmpty);
  });
}
