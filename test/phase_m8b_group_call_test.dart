// Phase M-8b acceptance — SfuGroupCallSession + GroupCallManager
// wired against fake signaling + fake WebRTC adapter.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';
import 'package:rainbow_stub_consumer/rainbow/sfu_group_call.dart';
import 'package:rainbow_stub_consumer/rainbow/sfu_signaling.dart';
import 'package:rainbow_stub_consumer/rainbow/webrtc_adapter.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:rainbow_stub_consumer/state/capsules/group_call_capsule.dart';

class _FakeXmpp extends RainbowXmppClient {
  _FakeXmpp() : super(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');
  final _events = StreamController<XmppEvent>.broadcast();
  final markers = <({String room, String state, String sid})>[];

  @override
  Stream<XmppEvent> get events => _events.stream;

  @override
  String get fullJid => 'alice@localhost/flutter';

  @override
  void sendMucCallMarker({
    required String roomBareJid,
    required String state,
    required String sid,
  }) => markers.add((room: roomBareJid, state: state, sid: sid));

  void pushIncoming(XmppEvent e) => _events.add(e);
}

class _FakeSession implements RtcSession {
  _FakeSession()
    : state = CallState.dialing {
    _events.add(RtcStateChanged(state));
  }
  final _events = StreamController<RtcSessionEvent>.broadcast();
  @override
  CallState state;
  bool offerVideoRequested = false;
  final remoteSdps = <({String sdp, bool isOffer})>[];
  int answersCreated = 0;
  final remoteCandidates =
      <({String candidate, String? sdpMid, int? sdpMLineIndex})>[];
  bool closed = false;

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
  Future<String> createOffer({bool audio = true, bool video = false}) async {
    offerVideoRequested = video;
    return 'sfu-offer-sdp';
  }

  @override
  Future<String> createAnswer({bool audio = true, bool video = false}) async {
    answersCreated++;
    return 'sfu-answer-sdp';
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
  Future<void> close() async {
    closed = true;
    if (!_events.isClosed) await _events.close();
  }
}

class _FakeAdapter implements WebRtcAdapter {
  final sessions = <_FakeSession>[];
  @override
  Future<RtcSession> createSession({required CallDirection direction}) async {
    final s = _FakeSession();
    sessions.add(s);
    return s;
  }
}

class _FakeSignaling implements SfuSignaling {
  _FakeSignaling();

  static const String answerSdp = 'sfu-final-answer';
  final _messages = StreamController<SfuServerMessage>.broadcast();
  final joinCalls = <({String sid, String uid, String offerSdp})>[];
  final answers = <({String sid, String sdp})>[];
  final trickles = <({String candidate, String? sdpMid, int? sdpMLineIndex, int target})>[];
  bool closed = false;

  @override
  Stream<SfuServerMessage> get messages => _messages.stream;

  @override
  Future<String> join({
    required String sid,
    required String uid,
    required String offerSdp,
  }) async {
    joinCalls.add((sid: sid, uid: uid, offerSdp: offerSdp));
    return answerSdp;
  }

  @override
  Future<String> sendOffer({required String sid, required String offerSdp}) async =>
      throw UnimplementedError();

  @override
  Future<void> sendAnswer({required String sid, required String answerSdp}) async {
    answers.add((sid: sid, sdp: answerSdp));
  }

  @override
  Future<void> sendTrickle({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
    required int target,
  }) async {
    trickles.add((
      candidate: candidate,
      sdpMid: sdpMid,
      sdpMLineIndex: sdpMLineIndex,
      target: target,
    ));
  }

  void pushFromServer(SfuServerMessage m) => _messages.add(m);

  @override
  Future<void> close() async {
    closed = true;
    if (!_messages.isClosed) await _messages.close();
  }
}

void main() {
  test(
    'SfuGroupCallSession.connect joins the SFU with the local offer and '
    'applies the returned answer',
    () async {
      final signaling = _FakeSignaling();
      final adapter = _FakeAdapter();
      final session = SfuGroupCallSession(
        signaling: signaling,
        adapter: adapter,
        sid: 'room-1',
        uid: 'alice',
      );

      await session.connect(video: true);

      expect(signaling.joinCalls.single.sid, 'room-1');
      expect(signaling.joinCalls.single.uid, 'alice');
      expect(signaling.joinCalls.single.offerSdp, 'sfu-offer-sdp');
      final rtc = adapter.sessions.single;
      expect(rtc.offerVideoRequested, isTrue);
      expect(rtc.remoteSdps.single.sdp, 'sfu-final-answer');
      expect(rtc.remoteSdps.single.isOffer, isFalse);

      await session.close();
    },
  );

  test('local ICE candidate is trickled with target=0', () async {
    final signaling = _FakeSignaling();
    final adapter = _FakeAdapter();
    final session = SfuGroupCallSession(
      signaling: signaling,
      adapter: adapter,
      sid: 'r',
      uid: 'u',
    );
    await session.connect();

    adapter.sessions.single.push(
      const RtcLocalIceCandidate(
        candidate: 'candidate:1 1 udp 1 10.0.0.1 55555 typ host',
        sdpMid: 'audio',
        sdpMLineIndex: 0,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(signaling.trickles.single.target, 0);
    expect(signaling.trickles.single.candidate, contains('10.0.0.1'));
    await session.close();
  });

  test(
    'SFU-initiated offer triggers answer + sendAnswer',
    () async {
      final signaling = _FakeSignaling();
      final adapter = _FakeAdapter();
      final session = SfuGroupCallSession(
        signaling: signaling,
        adapter: adapter,
        sid: 'r',
        uid: 'u',
      );
      await session.connect();

      signaling.pushFromServer(const SfuOfferFromServer('server-side-sdp'));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final rtc = adapter.sessions.single;
      // remoteSdps: [initial answer from join, server offer]
      expect(rtc.remoteSdps.last.sdp, 'server-side-sdp');
      expect(rtc.remoteSdps.last.isOffer, isTrue);
      expect(rtc.answersCreated, 1);
      expect(signaling.answers.single.sdp, 'sfu-answer-sdp');
      await session.close();
    },
  );

  test('SFU trickle is applied as a remote ICE candidate', () async {
    final signaling = _FakeSignaling();
    final adapter = _FakeAdapter();
    final session = SfuGroupCallSession(
      signaling: signaling,
      adapter: adapter,
      sid: 'r',
      uid: 'u',
    );
    await session.connect();

    signaling.pushFromServer(
      const SfuTrickleFromServer(
        candidate: 'candidate:9 1 udp 2 172.16.0.5 44444 typ srflx',
        sdpMid: 'audio',
        sdpMLineIndex: 0,
        target: 1,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(adapter.sessions.single.remoteCandidates.single.candidate,
        contains('172.16.0.5'));
    await session.close();
  });

  test('GroupCallManager.startGroupCall announces marker and joins SFU',
      () async {
    final xmpp = _FakeXmpp();
    final adapter = _FakeAdapter();
    final signaling = _FakeSignaling();
    final manager = GroupCallManager(
      adapter: adapter,
      xmpp: xmpp,
      uid: 'alice',
      xmppDomain: 'localhost',
      sfuUrl: Uri.parse('ws://sfu/'),
      signalingFactory: (_) async => signaling,
      sidGen: () => 'gc-1',
    );

    final bubble = RainbowBubble(id: 'room1', name: 'Room 1', members: const []);
    await manager.startGroupCall(bubble: bubble, video: true);

    expect(xmpp.markers.single.state, 'started');
    expect(xmpp.markers.single.sid, 'gc-1');
    expect(xmpp.markers.single.room, 'room1@muc.localhost');
    expect(signaling.joinCalls.single.sid, 'gc-1');
    expect(signaling.joinCalls.single.uid, 'alice');
    expect(manager.joinedCalls['room1@muc.localhost']?.sid, 'gc-1');
    await manager.dispose();
  });

  test(
    'incoming XmppMucCallMarker(started) populates openCallIn; ended clears it',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final manager = GroupCallManager(
        adapter: adapter,
        xmpp: xmpp,
        uid: 'alice',
        xmppDomain: 'localhost',
        sfuUrl: Uri.parse('ws://sfu/'),
        signalingFactory: (_) async => _FakeSignaling(),
      );

      xmpp.pushIncoming(
        const XmppMucCallMarker(
          roomBareJid: 'room1@muc.localhost',
          fromResource: 'bob',
          state: 'started',
          sid: 'gc-bob-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(manager.openCallIn('room1@muc.localhost')?.sid, 'gc-bob-1');

      xmpp.pushIncoming(
        const XmppMucCallMarker(
          roomBareJid: 'room1@muc.localhost',
          fromResource: 'bob',
          state: 'ended',
          sid: 'gc-bob-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(manager.openCallIn('room1@muc.localhost'), isNull);
      await manager.dispose();
    },
  );

  test('markers from our own uid are ignored to avoid self-echo', () async {
    final xmpp = _FakeXmpp();
    final adapter = _FakeAdapter();
    final manager = GroupCallManager(
      adapter: adapter,
      xmpp: xmpp,
      uid: 'alice',
      xmppDomain: 'localhost',
      sfuUrl: Uri.parse('ws://sfu/'),
      signalingFactory: (_) async => _FakeSignaling(),
    );

    xmpp.pushIncoming(
      const XmppMucCallMarker(
        roomBareJid: 'room1@muc.localhost',
        fromResource: 'alice',
        state: 'started',
        sid: 'self-echo',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(manager.openCallIn('room1@muc.localhost'), isNull);
    await manager.dispose();
  });

  test('manager without sfuUrl is disabled and rejects startGroupCall',
      () async {
    final xmpp = _FakeXmpp();
    final adapter = _FakeAdapter();
    final manager = GroupCallManager(
      adapter: adapter,
      xmpp: xmpp,
      uid: 'alice',
      xmppDomain: 'localhost',
      sfuUrl: null,
      signalingFactory: (_) async => _FakeSignaling(),
    );

    expect(manager.isEnabled, isFalse);
    final bubble = RainbowBubble(id: 'x', name: 'x', members: const []);
    await expectLater(
      manager.startGroupCall(bubble: bubble),
      throwsA(isA<StateError>()),
    );
    await manager.dispose();
  });

  test('leaveGroupCall closes session; announceEnd sends ended marker',
      () async {
    final xmpp = _FakeXmpp();
    final adapter = _FakeAdapter();
    final signaling = _FakeSignaling();
    final manager = GroupCallManager(
      adapter: adapter,
      xmpp: xmpp,
      uid: 'alice',
      xmppDomain: 'localhost',
      sfuUrl: Uri.parse('ws://sfu/'),
      signalingFactory: (_) async => signaling,
      sidGen: () => 'gc-2',
    );

    final bubble = RainbowBubble(id: 'r', name: 'r', members: const []);
    await manager.startGroupCall(bubble: bubble);
    await manager.leaveGroupCall('r@muc.localhost', announceEnd: true);

    expect(adapter.sessions.single.closed, isTrue);
    expect(signaling.closed, isTrue);
    expect(manager.joinedCalls, isEmpty);
    expect(
      xmpp.markers.last,
      (room: 'r@muc.localhost', state: 'ended', sid: 'gc-2'),
    );
    await manager.dispose();
  });
}
