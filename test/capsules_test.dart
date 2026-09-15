// Phase B acceptance tests — prove the capsules compose, drive state
// transitions, and react to injected XMPP events without touching a
// real network.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/config.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';
import 'package:rainbow_stub_consumer/rainbow/rest_client.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:rainbow_stub_consumer/state/capsules/auth_controller_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/auth_state_capsule.dart';
import 'package:rainbow_stub_consumer/state/models/auth_state.dart';
import 'package:rainbow_stub_consumer/state/capsules/bubbles_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/messages_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/muc_occupants_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/presence_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/rest_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/room_subject_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/roster_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/xmpp_capsule.dart';
import 'package:rearch/rearch.dart';

/// In-memory fake — extends the real client so it satisfies the capsule
/// return type without touching the network. Only the methods exercised
/// by the capsules are overridden.
class FakeRestClient extends RainbowRestClient {
  FakeRestClient() : super(AppConfig.dev);

  final List<RosterEntry> roster = [];
  final List<RainbowBubble> bubbles = [];
  int loginCalls = 0;
  int logoutCalls = 0;

  @override
  Future<LoginResult> login(String email, String password) async {
    loginCalls++;
    return LoginResult(
      token: 'tkn-$loginCalls',
      expiresIn: 3600,
      loggedInUser: RainbowUser(
        id: 'u-alice',
        loginEmail: email,
        firstName: 'Alice',
      ),
    );
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
  }

  @override
  Future<List<RosterEntry>> networks() async => List.unmodifiable(roster);

  @override
  Future<List<RainbowBubble>> rooms() async => List.unmodifiable(bubbles);

  @override
  void close() {}
}

/// Fake XMPP client with a controllable event stream.
class FakeXmppClient extends RainbowXmppClient {
  FakeXmppClient()
    : super(wsUrl: Uri.parse('ws://localhost/'), domain: 'localhost');

  final StreamController<XmppEvent> _fakeEvents =
      StreamController<XmppEvent>.broadcast();
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Stream<XmppEvent> get events => _fakeEvents.stream;

  @override
  Future<void> connect({
    required String email,
    required String saslPassword,
    String resource = 'flutter',
  }) async {
    connectCalls++;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  void push(XmppEvent event) => _fakeEvents.add(event);

  Future<void> dispose() => _fakeEvents.close();
}

void main() {
  late FakeRestClient fakeRest;
  late FakeXmppClient fakeXmpp;
  late MockableContainer container;

  setUp(() {
    fakeRest = FakeRestClient();
    fakeXmpp = FakeXmppClient();
    resetMessagesCapsuleCache();

    container = MockableContainer();
    container.mock(restCapsule).apply((use) => fakeRest);
    container.mock(xmppCapsule).apply((use) => fakeXmpp);
  });

  tearDown(() async {
    container.dispose();
    await fakeXmpp.dispose();
  });

  test(
    'auth capsule starts SignedOut, transitions to SignedIn on signIn',
    () async {
      expect(container.read(authCapsule), isA<SignedOut>());

      final controller = container.read(authControllerCapsule);
      await controller.signIn('alice@rainbow-stub.local', 'pw');

      final after = container.read(authCapsule);
      expect(after, isA<SignedIn>());
      expect(after.me?.loginEmail, 'alice@rainbow-stub.local');
      expect(after.token, 'tkn-1');
      expect(fakeRest.loginCalls, 1);
      expect(fakeXmpp.connectCalls, 1);
    },
  );

  test('signOut resets state and calls disconnect + logout', () async {
    final controller = container.read(authControllerCapsule);
    await controller.signIn('alice@rainbow-stub.local', 'pw');
    // Re-read to pick up mutated slot; capsule value is snapshot-per-read.
    final again = container.read(authControllerCapsule);
    await again.signOut();

    expect(container.read(authCapsule), isA<SignedOut>());
    expect(fakeXmpp.disconnectCalls, 1);
    expect(fakeRest.logoutCalls, 1);
  });

  test('signOut clears the messages capsule family cache', () async {
    final controller = container.read(authControllerCapsule);
    await controller.signIn('alice@rainbow-stub.local', 'pw');
    // Prime a family capsule so its closure is stored.
    final capBefore = messagesCapsule('bob@localhost');
    container.read(capBefore);

    final again = container.read(authControllerCapsule);
    await again.signOut();

    // After sign-out the family cache is cleared, so a new call for the
    // same threadKey returns a fresh Capsule<T> instance (different
    // identity — critical because rearch keys managers by identity).
    final capAfter = messagesCapsule('bob@localhost');
    expect(identical(capBefore, capAfter), isFalse);
  });

  test('rosterCapsule loads once auth flips to SignedIn', () async {
    fakeRest.roster.add(
      RosterEntry(
        userId: 'u-bob',
        peer: RainbowUser(id: 'u-bob', loginEmail: 'bob@rainbow-stub.local'),
        status: 'accepted',
      ),
    );

    // Before signin: capsule is loading OR returns empty AsyncData.
    final controller = container.read(authControllerCapsule);
    await controller.signIn('alice@rainbow-stub.local', 'pw');

    // Rearch runs the future synchronously in the microtask queue after
    // the auth slot flips; yield until it resolves.
    for (var i = 0; i < 20; i++) {
      final v = container.read(rosterCapsule);
      if (v is AsyncData<List<RosterEntry>> && v.data.isNotEmpty) {
        expect(v.data.single.peer.loginEmail, 'bob@rainbow-stub.local');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('rosterCapsule never produced AsyncData with entries');
  });

  test('bubblesCapsule loads once auth flips to SignedIn', () async {
    fakeRest.bubbles.add(
      RainbowBubble(id: 'b-1', name: 'ops', members: const []),
    );

    final controller = container.read(authControllerCapsule);
    await controller.signIn('alice@rainbow-stub.local', 'pw');

    for (var i = 0; i < 20; i++) {
      final v = container.read(bubblesCapsule);
      if (v is AsyncData<List<RainbowBubble>> && v.data.isNotEmpty) {
        expect(v.data.single.id, 'b-1');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('bubblesCapsule never produced AsyncData with entries');
  });

  test(
    'presenceCapsule accumulates presence updates from the XMPP stream',
    () async {
      // Prime the capsule so the effect subscribes.
      expect(container.read(presenceCapsule), isEmpty);

      fakeXmpp.push(
        const XmppPresenceUpdate(fromBare: 'bob@localhost', show: 'away'),
      );
      fakeXmpp.push(
        const XmppPresenceUpdate(
          fromBare: 'bob@localhost',
          show: 'chat',
          status: 'hi',
        ),
      );
      fakeXmpp.push(
        const XmppPresenceUpdate(fromBare: 'carol@localhost', show: 'dnd'),
      );

      // Let the stream deliver + rearch rebuild.
      for (var i = 0; i < 20; i++) {
        final m = container.read(presenceCapsule);
        if (m.length == 2 && m['bob@localhost']?.show == 'chat') {
          expect(m['bob@localhost']?.status, 'hi');
          expect(m['carol@localhost']?.show, 'dnd');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('presenceCapsule never reached the expected state');
    },
  );

  test('mucOccupantsCapsule tracks joins and drops on unavailable', () async {
    const room = 'ops@muc.localhost';
    // Prime the capsule so the effect subscribes.
    expect(container.read(mucOccupantsCapsule), isEmpty);

    fakeXmpp.push(
      const XmppMucOccupant(
        roomBareJid: room,
        nick: 'alice',
        available: true,
        affiliation: 'owner',
        role: 'moderator',
      ),
    );
    fakeXmpp.push(
      const XmppMucOccupant(roomBareJid: room, nick: 'bob', available: true),
    );

    // Wait for both occupants to land.
    var reached = false;
    for (var i = 0; i < 20; i++) {
      final r = container.read(mucOccupantsCapsule)[room];
      if (r != null && r.length == 2 && r['alice']?.isOwner == true) {
        reached = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(reached, isTrue, reason: 'both occupants never joined');

    // Bob leaves — the room drops to a single occupant.
    fakeXmpp.push(
      const XmppMucOccupant(roomBareJid: room, nick: 'bob', available: false),
    );
    for (var i = 0; i < 20; i++) {
      final r = container.read(mucOccupantsCapsule)[room];
      if (r != null && r.length == 1 && r.containsKey('alice')) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('mucOccupantsCapsule never dropped the departed occupant');
  });

  test(
    'roomSubjectCapsule tracks the room subject and clears on empty',
    () async {
      const room = 'ops@muc.localhost';
      expect(container.read(roomSubjectCapsule), isEmpty);

      fakeXmpp.push(
        const XmppRoomSubject(roomBareJid: room, subject: 'Daily standup'),
      );
      var reached = false;
      for (var i = 0; i < 20; i++) {
        if (container.read(roomSubjectCapsule)[room] == 'Daily standup') {
          reached = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(reached, isTrue, reason: 'subject never landed');

      fakeXmpp.push(const XmppRoomSubject(roomBareJid: room, subject: ''));
      for (var i = 0; i < 20; i++) {
        if (!container.read(roomSubjectCapsule).containsKey(room)) return;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('roomSubjectCapsule never cleared the subject');
    },
  );

  test(
    'messagesCapsule(threadKey) appends only messages for that thread',
    () async {
      final thread = 'bob@localhost';
      final capsule = messagesCapsule(thread);
      // Prime — first read subscribes the effect.
      expect(container.read(capsule), isEmpty);

      fakeXmpp.push(
        const XmppChatMessage(
          from: 'bob@localhost/laptop',
          to: 'alice@localhost/flutter',
          body: 'hey',
          stanzaId: 'm1',
          isGroupChat: false,
        ),
      );
      // Off-thread — must NOT be appended.
      fakeXmpp.push(
        const XmppChatMessage(
          from: 'carol@localhost/laptop',
          to: 'alice@localhost/flutter',
          body: 'unrelated',
          stanzaId: 'm2',
          isGroupChat: false,
        ),
      );
      fakeXmpp.push(
        const XmppChatMessage(
          from: 'alice@localhost/flutter',
          to: 'bob@localhost/laptop',
          body: 'yo',
          stanzaId: 'm3',
          isGroupChat: false,
        ),
      );

      for (var i = 0; i < 20; i++) {
        final ms = container.read(capsule);
        if (ms.length == 2) {
          expect(ms.map((m) => m.body).toList(), ['hey', 'yo']);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('messagesCapsule never accumulated the expected pair');
    },
  );
}
