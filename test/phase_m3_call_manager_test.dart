// Phase M-3a acceptance — CallManager drives a fake SIP call between
// two peers using two fake WebRtcAdapters + a fake XmppClient that
// swaps stanzas between them. Also covers the SdpToJingle codec.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';
import 'package:rainbow_stub_consumer/rainbow/sdp_to_jingle.dart';
import 'package:rainbow_stub_consumer/rainbow/webrtc_adapter.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:rainbow_stub_consumer/state/capsules/call_manager_capsule.dart';

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
  String? remoteSdp;
  bool isOfferRemote = false;
  final List<String> remoteCandidates = [];
  bool closed = false;

  @override
  Stream<RtcSessionEvent> get events => _events.stream;

  void push(RtcSessionEvent e) {
    if (e is RtcStateChanged) state = e.state;
    _events.add(e);
  }

  @override
  Future<String> createOffer({bool audio = true, bool video = false}) async =>
      _mockSdp('offer-${_hash()}');

  @override
  Future<String> createAnswer({bool audio = true, bool video = false}) async =>
      _mockSdp('answer-${_hash()}');

  @override
  Future<void> setRemoteDescription(String sdp, {required bool isOffer}) async {
    remoteSdp = sdp;
    isOfferRemote = isOffer;
  }

  @override
  Future<void> addRemoteIceCandidate({
    required String candidate,
    String? sdpMid,
    int? sdpMLineIndex,
  }) async {
    remoteCandidates.add(candidate);
  }

  @override
  Future<void> setMicrophoneMuted(bool muted) async {}

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    if (!_events.isClosed) await _events.close();
  }

  static int _seed = 0;
  int _hash() => _seed++;
  String _mockSdp(String tag) =>
      'v=0\r\no=- 0 0 IN IP4 0.0.0.0\r\ns=$tag\r\nt=0 0\r\n';
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

/// A pair of fake XMPP clients that route Jingle stanzas between each
/// other so a single test can drive both sides of a call.
class _FakeXmpp extends RainbowXmppClient {
  _FakeXmpp({required String jid})
      : _fullJid = jid,
        super(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');

  final _events = StreamController<XmppEvent>.broadcast();
  final String _fullJid;
  _FakeXmpp? peer;

  final List<({String action, String sid, String contentXml})> sent = [];

  @override
  Stream<XmppEvent> get events => _events.stream;

  @override
  String get fullJid => _fullJid;

  @override
  String sendJingle({
    required String toFullJid,
    required String action,
    required String sid,
    required String contentXml,
    String? initiator,
    String? responder,
  }) {
    sent.add((action: action, sid: sid, contentXml: contentXml));
    // Wrap in a <jingle> element so the receiver's parser sees the
    // real shape.
    final jingleXml =
        '<jingle xmlns="urn:xmpp:jingle:1" action="$action" sid="$sid">'
        '$contentXml'
        '</jingle>';
    peer?._events.add(
      XmppJingle(
        fromFullJid: _fullJid,
        iqId: 'iq-${sent.length}',
        sid: sid,
        action: action,
        jingleXml: jingleXml,
      ),
    );
    return 'iq-${sent.length}';
  }

  void close$() => _events.close();
}

CallManager _mkManager(
  _FakeAdapter adapter,
  _FakeXmpp xmpp, {
  String myFullJid = 'alice@localhost/flutter',
}) {
  return CallManager(
    adapter: adapter,
    xmpp: xmpp,
    xmppDomain: 'localhost',
    myFullJid: myFullJid,
    events: xmpp.events,
  );
}

void main() {
  group('SdpToJingle', () {
    test('encode + decode round-trip preserves the SDP verbatim', () {
      const sdp = 'v=0\r\no=- 0 0 IN IP4 0.0.0.0\r\ns=t\r\nt=0 0\r\n';
      final xml = SdpToJingle.encode(
        sdp: sdp,
        contentName: 'audio',
        creator: 'initiator',
        media: 'audio',
      );
      expect(xml, contains('media="audio"'));
      final decoded = SdpToJingle.decode(xml);
      expect(decoded, sdp);
    });

    test('candidate encode + decode round-trip', () {
      final xml = SdpToJingle.encodeCandidate(
        candidate: 'candidate:1 1 UDP 2130706431 10.0.0.1 54321 typ host',
        sdpMid: '0',
        sdpMLineIndex: 0,
      );
      final decoded = SdpToJingle.decodeCandidate(xml);
      expect(decoded, isNotNull);
      expect(decoded!.candidate, contains('10.0.0.1 54321'));
      expect(decoded.sdpMid, '0');
      expect(decoded.sdpMLineIndex, 0);
    });

    test('decode returns null on malformed payloads', () {
      expect(SdpToJingle.decode('<not-a-content/>'), isNull);
      expect(SdpToJingle.decode('gibberish'), isNull);
    });
  });

  group('CallManager', () {
    test(
      'startCall sends session-initiate carrying the SDP offer',
      () async {
        final aliceAdapter = _FakeAdapter();
        final alice = _FakeXmpp(jid: 'alice@localhost/flutter');
        final mgr = _mkManager(aliceAdapter, alice);

        final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
        final sid = await mgr.startCall(peer);

        expect(alice.sent, hasLength(1));
        expect(alice.sent.single.action, 'session-initiate');
        expect(alice.sent.single.sid, sid);
        final decoded = SdpToJingle.decode(alice.sent.single.contentXml);
        expect(decoded, contains('s=offer-'));

        expect(mgr.activeCalls, hasLength(1));
        expect(mgr.activeCalls.single.direction, CallDirection.outgoing);

        mgr.dispose();
      },
    );

    test(
      'incoming session-initiate creates a matching call in ringing state',
      () async {
        final bobAdapter = _FakeAdapter();
        final bob = _FakeXmpp(jid: 'bob@localhost/flutter');
        final mgr = _mkManager(
          bobAdapter,
          bob,
          myFullJid: 'bob@localhost/flutter',
        );

        final offerXml = SdpToJingle.encode(
          sdp: 'v=0\r\ns=offer-inbound\r\n',
          contentName: 'audio',
          creator: 'initiator',
          media: 'audio',
        );
        final jingleXml =
            '<jingle xmlns="urn:xmpp:jingle:1" action="session-initiate" '
            'sid="sid-in-1">$offerXml</jingle>';
        bob._events.add(
          XmppJingle(
            fromFullJid: 'alice@localhost/flutter',
            iqId: 'iq-42',
            sid: 'sid-in-1',
            action: 'session-initiate',
            jingleXml: jingleXml,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(mgr.activeCalls, hasLength(1));
        expect(mgr.activeCalls.single.direction, CallDirection.incoming);
        expect(mgr.activeCalls.single.state, CallState.ringing);

        expect(bobAdapter.sessions.single.remoteSdp, contains('offer-inbound'));
        expect(bobAdapter.sessions.single.isOfferRemote, isTrue);

        mgr.dispose();
      },
    );

    test('full offer/answer/trickle round-trip across two peers', () async {
      final aliceAdapter = _FakeAdapter();
      final bobAdapter = _FakeAdapter();
      final alice = _FakeXmpp(jid: 'alice@localhost/flutter');
      final bob = _FakeXmpp(jid: 'bob@localhost/flutter');
      alice.peer = bob;
      bob.peer = alice;

      final mgrAlice = _mkManager(aliceAdapter, alice);
      final mgrBob = _mkManager(bobAdapter, bob, myFullJid: bob.fullJid);

      final sid = await mgrAlice.startCall(
        RainbowUser(id: 'bob', loginEmail: 'bob@localhost'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Bob's manager saw the offer, created a session, set remote
      // description.
      expect(mgrBob.activeCalls, hasLength(1));
      expect(bobAdapter.sessions.single.remoteSdp, isNotNull);

      await mgrBob.answer(sid);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Alice's manager saw the answer and set remote description.
      expect(aliceAdapter.sessions.single.remoteSdp, isNotNull);
      expect(aliceAdapter.sessions.single.isOfferRemote, isFalse);

      // Trickle an ICE candidate from alice → bob.
      aliceAdapter.sessions.single.push(
        const RtcLocalIceCandidate(
          candidate: 'candidate:1 1 UDP 100 192.168.1.2 4444 typ host',
          sdpMid: '0',
          sdpMLineIndex: 0,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bobAdapter.sessions.single.remoteCandidates, hasLength(1));
      expect(
        bobAdapter.sessions.single.remoteCandidates.single,
        contains('192.168.1.2'),
      );

      // Alice hangs up.
      await mgrAlice.hangUp(sid);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(mgrAlice.activeCalls, isEmpty);
      expect(mgrBob.activeCalls, isEmpty);
      expect(aliceAdapter.sessions.single.closed, isTrue);
      expect(bobAdapter.sessions.single.closed, isTrue);

      mgrAlice.dispose();
      mgrBob.dispose();
    });
  });
}
