// Phase M-2 acceptance — RtcSession lifecycle capsule wired through a
// fake WebRtcAdapter. Proves that the capsule (a) constructs a session
// with the direction-appropriate initial state, (b) reflects
// RtcStateChanged events, and (c) closes the session on dispose.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/webrtc_adapter.dart';
import 'package:rainbow_stub_consumer/state/capsules/call_capsule.dart';
import 'package:rearch/rearch.dart';

class _FakeSession implements RtcSession {
  _FakeSession({required CallDirection direction})
    : _state = direction == CallDirection.outgoing
          ? CallState.dialing
          : CallState.ringing {
    _events.add(RtcStateChanged(_state));
  }

  final _events = StreamController<RtcSessionEvent>.broadcast();
  CallState _state;
  bool closed = false;

  void push(RtcSessionEvent e) {
    if (e is RtcStateChanged) _state = e.state;
    _events.add(e);
  }

  @override
  Stream<RtcSessionEvent> get events => _events.stream;

  @override
  CallState get state => _state;

  @override
  Future<String> createOffer({bool audio = true, bool video = false}) async =>
      'fake-offer';

  @override
  Future<String> createAnswer({bool audio = true, bool video = false}) async =>
      'fake-answer';

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

void main() {
  setUp(resetCallCapsuleCache);

  test(
    'outgoing call: initial snapshot is dialing; RtcStateChanged flows through',
    () async {
      final adapter = _FakeAdapter();
      final container = MockableContainer();
      container.mock(webRtcAdapterCapsule).apply((use) => adapter);

      final snap1 = container.read(
        callCapsule(sid: 'sid-1', direction: CallDirection.outgoing),
      );
      expect(snap1.connectionState.name, 'waiting');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final snap2 = container.read(
        callCapsule(sid: 'sid-1', direction: CallDirection.outgoing),
      );
      expect(snap2.hasData, isTrue);
      expect(snap2.data!.snapshot.sid, 'sid-1');
      expect(snap2.data!.snapshot.direction, CallDirection.outgoing);
      expect(snap2.data!.snapshot.state, CallState.dialing);
      expect(adapter.sessions, hasLength(1));

      adapter.sessions.single.push(const RtcStateChanged(CallState.connecting));
      await Future<void>.delayed(Duration.zero);
      final snap3 = container.read(
        callCapsule(sid: 'sid-1', direction: CallDirection.outgoing),
      );
      expect(snap3.data!.snapshot.state, CallState.connecting);

      adapter.sessions.single.push(const RtcStateChanged(CallState.connected));
      await Future<void>.delayed(Duration.zero);
      final snap4 = container.read(
        callCapsule(sid: 'sid-1', direction: CallDirection.outgoing),
      );
      expect(snap4.data!.snapshot.state, CallState.connected);

      container.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(adapter.sessions.single.closed, isTrue);
    },
  );

  test('incoming call: initial snapshot is ringing', () async {
    final adapter = _FakeAdapter();
    final container = MockableContainer();
    container.mock(webRtcAdapterCapsule).apply((use) => adapter);

    container.read(
      callCapsule(sid: 'sid-2', direction: CallDirection.incoming),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final snap = container.read(
      callCapsule(sid: 'sid-2', direction: CallDirection.incoming),
    );
    expect(snap.data!.snapshot.state, CallState.ringing);

    container.dispose();
  });
}
