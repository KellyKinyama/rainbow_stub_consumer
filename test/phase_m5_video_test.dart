// Phase M-5 acceptance — video calling plumbing.
//   1. startCall(video: true) → session.createOffer(video: true),
//      ActiveCall.hasVideo == true.
//   2. Incoming SDP containing 'm=video' → ActiveCall.hasVideo == true.
//   3. Camera controls: setCameraEnabled + switchCamera are forwarded
//      to the session.
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

  bool offerVideo = false;
  bool answerVideo = false;
  int cameraEnabledCalls = 0;
  int? lastCameraEnabled;
  int switchCameraCalls = 0;

  @override
  Stream<RtcSessionEvent> get events => _events.stream;

  @override
  MediaStream? get localMediaStream => null;

  @override
  MediaStream? get remoteMediaStream => null;

  @override
  Future<String> createOffer({bool audio = true, bool video = false}) async {
    offerVideo = video;
    return video
        ? 'v=0\r\nm=audio 9 UDP\r\nm=video 9 UDP\r\n'
        : 'v=0\r\nm=audio 9 UDP\r\n';
  }

  @override
  Future<String> createAnswer({bool audio = true, bool video = false}) async {
    answerVideo = video;
    return 'v=0\r\nanswer\r\n';
  }

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
  Future<void> setCameraEnabled(bool enabled) async {
    cameraEnabledCalls++;
    lastCameraEnabled = enabled ? 1 : 0;
  }

  @override
  Future<void> switchCamera() async {
    switchCameraCalls++;
  }

  @override
  Future<void> setSpeakerphoneEnabled(bool enabled) async {}

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

CallManager _makeManager({
  required _FakeXmpp xmpp,
  required _FakeAdapter adapter,
}) => CallManager(
  adapter: adapter,
  xmpp: xmpp,
  sidGen: _sidGen,
  ringer: _SilentRinger(),
);

void main() {
  setUp(() => _sidCounter = 0);

  test(
    'startCall(video: true) marks the call video and offers with video',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final manager = _makeManager(xmpp: xmpp, adapter: adapter);

      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
      final sid = await manager.startCall(
        peer: peer,
        peerFullJid: 'bob@localhost/laptop',
        video: true,
      );

      expect(manager.calls[sid]!.hasVideo, isTrue);
      expect(adapter.sessions.single.offerVideo, isTrue);
      await manager.dispose();
    },
  );

  test(
    'incoming SDP containing m=video promotes ActiveCall.hasVideo',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final manager = _makeManager(xmpp: xmpp, adapter: adapter);

      xmpp.pushIncoming(
        const XmppJingle(
          fromFullJid: 'bob@localhost/laptop',
          iqId: 'iq-vin',
          sid: 'v1',
          action: 'session-initiate',
          jingleXml:
              '<jingle xmlns="urn:xmpp:jingle:1" action="session-initiate" '
              'sid="v1"><content name="rtp" creator="initiator">'
              '<rainbow-sdp xmlns="urn:rainbow:jingle:sdp:1">'
              '<![CDATA[v=0\r\nm=audio 9\r\nm=video 9\r\n]]>'
              '</rainbow-sdp></content></jingle>',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final call = manager.calls['v1']!;
      expect(call.hasVideo, isTrue);

      await manager.answer('v1');
      expect(adapter.sessions.single.answerVideo, isTrue);
      await manager.dispose();
    },
  );

  test(
    'incoming SDP without m=video keeps ActiveCall.hasVideo=false',
    () async {
      final xmpp = _FakeXmpp();
      final adapter = _FakeAdapter();
      final manager = _makeManager(xmpp: xmpp, adapter: adapter);

      xmpp.pushIncoming(
        const XmppJingle(
          fromFullJid: 'bob@localhost/laptop',
          iqId: 'iq-a',
          sid: 'a1',
          action: 'session-initiate',
          jingleXml:
              '<jingle xmlns="urn:xmpp:jingle:1" action="session-initiate" '
              'sid="a1"><content name="rtp" creator="initiator">'
              '<rainbow-sdp xmlns="urn:rainbow:jingle:sdp:1">'
              '<![CDATA[v=0\r\nm=audio 9\r\n]]>'
              '</rainbow-sdp></content></jingle>',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(manager.calls['a1']!.hasVideo, isFalse);
      await manager.dispose();
    },
  );

  test('session exposes setCameraEnabled + switchCamera controls', () async {
    final xmpp = _FakeXmpp();
    final adapter = _FakeAdapter();
    final manager = _makeManager(xmpp: xmpp, adapter: adapter);

    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
    final sid = await manager.startCall(
      peer: peer,
      peerFullJid: 'bob@localhost/laptop',
      video: true,
    );

    final session = manager.calls[sid]!.session;
    await session.setCameraEnabled(false);
    await session.setCameraEnabled(true);
    await session.switchCamera();

    final fake = adapter.sessions.single;
    expect(fake.cameraEnabledCalls, 2);
    expect(fake.lastCameraEnabled, 1);
    expect(fake.switchCameraCalls, 1);
    await manager.dispose();
  });
}
