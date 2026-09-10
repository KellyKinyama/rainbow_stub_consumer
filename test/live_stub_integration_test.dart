// Live integration test: expects a running rainbow-stub on
//   https://localhost:8443
// with the default seed (alice + bob + roster). Run:
//   flutter test test/live_stub_integration_test.dart
//
// Skipped automatically if the stub isn't reachable.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/config.dart';
import 'package:rainbow_stub_consumer/rainbow/rest_client.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';

const _pingUrl = 'https://localhost:8443/health';

Future<bool> _stubUp() async {
  final client = HttpClient();
  client.badCertificateCallback = (_, __, ___) => true;
  client.connectionTimeout = const Duration(seconds: 1);
  try {
    final req = await client.getUrl(Uri.parse(_pingUrl));
    final resp = await req.close();
    await resp.drain<void>();
    return resp.statusCode == 200;
  } on Exception {
    return false;
  } finally {
    client.close(force: true);
  }
}

void main() {
  final config = AppConfig.dev;

  setUpAll(() async {
    final up = await _stubUp();
    if (!up) {
      markTestSkipped(
        'rainbow-stub is not reachable at $_pingUrl — start it with '
        '`dart run bin/server.dart` in c:\\www\\dart\\rainbow-stub',
      );
    }
  });

  test('REST login as alice returns a bearer token and loggedInUser', () async {
    if (!await _stubUp()) return;
    final rest = RainbowRestClient(config);
    final r = await rest.login('alice@rainbow-stub.local', 'password');
    expect(r.token, isNotEmpty);
    expect(r.loggedInUser.loginEmail, 'alice@rainbow-stub.local');
    expect(r.loggedInUser.id, hasLength(24));
    rest.close();
  });

  test('REST /networks returns the seeded roster (>= 4 entries)', () async {
    if (!await _stubUp()) return;
    final rest = RainbowRestClient(config);
    await rest.login('alice@rainbow-stub.local', 'password');
    final roster = await rest.networks();
    expect(roster.length, greaterThanOrEqualTo(4));
    expect(
      roster.map((e) => e.peer.loginEmail).toSet(),
      containsAll(['bob@rainbow-stub.local']),
    );
    rest.close();
  });

  test(
    'XMPP connect (SASL PLAIN with bearer) → 1:1 message reaches bob',
    () async {
      if (!await _stubUp()) return;
      final restAlice = RainbowRestClient(config);
      final restBob = RainbowRestClient(config);
      final aliceLogin = await restAlice.login(
        'alice@rainbow-stub.local',
        'password',
      );
      final bobLogin = await restBob.login(
        'bob@rainbow-stub.local',
        'password',
      );

      final alice = RainbowXmppClient(
        wsUrl: config.wsUrl,
        domain: config.xmppDomain,
      );
      final bob = RainbowXmppClient(
        wsUrl: config.wsUrl,
        domain: config.xmppDomain,
      );

      await alice.connect(
        email: 'alice@rainbow-stub.local',
        saslPassword: aliceLogin.token,
        resource: 'flutter-int',
      );
      await bob.connect(
        email: 'bob@rainbow-stub.local',
        saslPassword: bobLogin.token,
        resource: 'flutter-int',
      );

      final delivered = Completer<XmppChatMessage>();
      final sub = bob.events.listen((e) {
        if (e is XmppChatMessage && !delivered.isCompleted) {
          delivered.complete(e);
        }
      });

      alice.sendChat(
        toBareJid: '${bobLogin.loggedInUser.id}@${config.xmppDomain}',
        body: 'hello from flutter integration',
      );

      final msg = await delivered.future.timeout(const Duration(seconds: 5));
      expect(msg.body, 'hello from flutter integration');
      expect(msg.from, startsWith(aliceLogin.loggedInUser.id));

      await sub.cancel();
      await alice.disconnect();
      await bob.disconnect();
      restAlice.close();
      restBob.close();
    },
  );

  test(
    'XEP-0198 stream management: sendChat causes XmppSentAck via <a h=…/>',
    () async {
      if (!await _stubUp()) return;
      final restAlice = RainbowRestClient(config);
      final restBob = RainbowRestClient(config);
      final aliceLogin = await restAlice.login(
        'alice@rainbow-stub.local',
        'password',
      );
      final bobLogin = await restBob.login(
        'bob@rainbow-stub.local',
        'password',
      );

      final alice = RainbowXmppClient(
        wsUrl: config.wsUrl,
        domain: config.xmppDomain,
      );
      await alice.connect(
        email: 'alice@rainbow-stub.local',
        saslPassword: aliceLogin.token,
        resource: 'flutter-sm',
      );

      final acked = Completer<XmppSentAck>();
      final sub = alice.events.listen((e) {
        if (e is XmppSentAck && !acked.isCompleted) acked.complete(e);
      });

      const outboundId = 'sm-live-1';
      alice.sendChat(
        toBareJid: '${bobLogin.loggedInUser.id}@${config.xmppDomain}',
        body: 'sm-ack ping',
        id: outboundId,
      );

      final ack = await acked.future.timeout(const Duration(seconds: 5));
      expect(ack.stanzaId, outboundId);

      await sub.cancel();
      await alice.disconnect();
      restAlice.close();
      restBob.close();
    },
  );

  test('MUC reactions persist across signout via MAM replay', () async {
    if (!await _stubUp()) return;
    final restAlice = RainbowRestClient(config);
    final aliceLogin = await restAlice.login(
      'alice@rainbow-stub.local',
      'password',
    );

    // Create a fresh bubble owned by alice; she's auto-added as
    // accepted owner so she can send + react immediately.
    final bubble = await restAlice.createRoom(
      'sm-i-${DateTime.now().microsecondsSinceEpoch}',
    );

    final roomJid = '${bubble.id}@muc.${config.xmppDomain}';

    // First session: alice sends a message, then a reaction on it.
    final alice1 = RainbowXmppClient(
      wsUrl: config.wsUrl,
      domain: config.xmppDomain,
    );
    await alice1.connect(
      email: 'alice@rainbow-stub.local',
      saslPassword: aliceLogin.token,
      resource: 'flutter-muc-a',
    );
    alice1.joinMuc(roomJid, aliceLogin.loggedInUser.id);

    final ownEcho = Completer<XmppChatMessage>();
    final sub1 = alice1.events.listen((e) {
      if (e is XmppChatMessage &&
          e.isGroupChat &&
          e.body == 'muc-persist-target' &&
          !ownEcho.isCompleted) {
        ownEcho.complete(e);
      }
    });

    const targetId = 'muc-persist-1';
    alice1.sendGroupChat(
      roomJid: roomJid,
      body: 'muc-persist-target',
      id: targetId,
    );
    await ownEcho.future.timeout(const Duration(seconds: 5));

    alice1.sendReactions(
      toBareJid: roomJid,
      targetStanzaId: targetId,
      emojis: const ['🔥'],
      isGroupChat: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    await sub1.cancel();
    await alice1.disconnect();

    // Second session: alice re-connects, queries MAM for the room —
    // reactions should be replayed as a live <message><reactions>/>.
    final alice2 = RainbowXmppClient(
      wsUrl: config.wsUrl,
      domain: config.xmppDomain,
    );
    await alice2.connect(
      email: 'alice@rainbow-stub.local',
      saslPassword: aliceLogin.token,
      resource: 'flutter-muc-b',
    );

    final replayed = Completer<XmppReactions>();
    final sub2 = alice2.events.listen((e) {
      if (e is XmppReactions &&
          e.targetStanzaId == targetId &&
          !replayed.isCompleted) {
        replayed.complete(e);
      }
    });
    alice2.queryMamWith(roomJid, max: 20);

    final r = await replayed.future.timeout(const Duration(seconds: 5));
    expect(r.emojis, contains('🔥'));

    await sub2.cancel();
    await alice2.disconnect();
    restAlice.close();
  });

  test(
    'XEP-0198 resume: after WS drop, resume() picks up where we left off',
    () async {
      if (!await _stubUp()) return;
      final restAlice = RainbowRestClient(config);
      final restBob = RainbowRestClient(config);
      final aliceLogin = await restAlice.login(
        'alice@rainbow-stub.local',
        'password',
      );
      final bobLogin = await restBob.login(
        'bob@rainbow-stub.local',
        'password',
      );

      final alice = RainbowXmppClient(
        wsUrl: config.wsUrl,
        domain: config.xmppDomain,
      );
      await alice.connect(
        email: 'alice@rainbow-stub.local',
        saslPassword: aliceLogin.token,
        resource: 'flutter-resume',
      );
      expect(alice.canResume, isTrue);

      // Send one message and wait for the ack so we have some SM state.
      final preDropAck = Completer<XmppSentAck>();
      final sub0 = alice.events.listen((e) {
        if (e is XmppSentAck && !preDropAck.isCompleted) {
          preDropAck.complete(e);
        }
      });
      alice.sendChat(
        toBareJid: '${bobLogin.loggedInUser.id}@${config.xmppDomain}',
        body: 'pre-drop',
        id: 'resume-pre-1',
      );
      await preDropAck.future.timeout(const Duration(seconds: 5));
      await sub0.cancel();

      // Simulate an unclean WS drop (no <close/>). SM state is kept.
      await alice.debugSimulateDrop();

      // Resume — reuses the same JID, so the parked server session
      // picks us back up. If the server had reaped it we'd get
      // <failed/> and resume() would throw.
      await alice.resume(
        email: 'alice@rainbow-stub.local',
        saslPassword: aliceLogin.token,
      );

      // A new send after resume should still round-trip.
      final bob = RainbowXmppClient(
        wsUrl: config.wsUrl,
        domain: config.xmppDomain,
      );
      await bob.connect(
        email: 'bob@rainbow-stub.local',
        saslPassword: bobLogin.token,
        resource: 'flutter-resume-bob',
      );

      final delivered = Completer<XmppChatMessage>();
      final sub = bob.events.listen((e) {
        if (e is XmppChatMessage &&
            e.body == 'post-resume' &&
            !delivered.isCompleted) {
          delivered.complete(e);
        }
      });

      alice.sendChat(
        toBareJid: '${bobLogin.loggedInUser.id}@${config.xmppDomain}',
        body: 'post-resume',
        id: 'resume-post-1',
      );

      final msg = await delivered.future.timeout(const Duration(seconds: 5));
      expect(msg.body, 'post-resume');

      await sub.cancel();
      await alice.disconnect();
      await bob.disconnect();
      restAlice.close();
      restBob.close();
    },
  );

  test('XEP-0313 pagination: initial fin anchors oldest; load-older '
      'returns empty at archive boundary', () async {
    if (!await _stubUp()) return;
    final restAlice = RainbowRestClient(config);
    final restBob = RainbowRestClient(config);
    final aliceLogin = await restAlice.login(
      'alice@rainbow-stub.local',
      'password',
    );
    final bobLogin = await restBob.login('bob@rainbow-stub.local', 'password');

    // Session 1: alice seeds the archive with 55 messages so a
    // max=50 query returns a saturated page (<fin complete=false>).
    final aliceSeed = RainbowXmppClient(
      wsUrl: config.wsUrl,
      domain: config.xmppDomain,
    );
    await aliceSeed.connect(
      email: 'alice@rainbow-stub.local',
      saslPassword: aliceLogin.token,
      resource: 'flutter-mam-seed',
    );
    final peerBare = '${bobLogin.loggedInUser.id}@${config.xmppDomain}';
    for (var i = 0; i < 55; i++) {
      aliceSeed.sendChat(
        toBareJid: peerBare,
        body: 'seed-$i',
        id: 'mam-seed-$i',
      );
    }
    // Give the stub a beat to persist all 55 before we tear down.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await aliceSeed.disconnect();

    // Session 2: fresh connect, drive an initial MAM query + a
    // load-older query directly on the wire.
    final alice = RainbowXmppClient(
      wsUrl: config.wsUrl,
      domain: config.xmppDomain,
    );
    await alice.connect(
      email: 'alice@rainbow-stub.local',
      saslPassword: aliceLogin.token,
      resource: 'flutter-mam-page',
    );

    final firstPageIds = <String>[];
    final finEvents = <XmppMamFin>[];
    final sub = alice.events.listen((e) {
      if (e is XmppMamMessage) firstPageIds.add(e.stanzaId);
      if (e is XmppMamFin) finEvents.add(e);
    });

    final initialQid = alice.queryMamWith(peerBare, max: 50);
    await Future<void>.delayed(const Duration(seconds: 1));

    // Initial page returns the OLDEST 50 (stub orders ASC).
    expect(firstPageIds, hasLength(50));
    final initialFin = finEvents.firstWhere(
      (f) => f.queryId == initialQid,
      orElse: () => throw StateError('no fin for initial query'),
    );
    expect(initialFin.first.isNotEmpty, isTrue);
    // page 50 == max 50 → stub says complete=false ("there might be more").
    expect(initialFin.complete, isFalse);
    expect(initialFin.count, greaterThanOrEqualTo(55));

    // Load older, anchored at the initial page's `first` id.
    final olderQid = alice.queryMamWith(
      peerBare,
      max: 50,
      beforeStanzaId: initialFin.first,
    );
    final beforeMsgCount = firstPageIds.length;
    await Future<void>.delayed(const Duration(seconds: 1));

    final olderFin = finEvents.firstWhere(
      (f) => f.queryId == olderQid,
      orElse: () => throw StateError('no fin for older query'),
    );
    // No older messages exist beyond the initial `first`.
    expect(firstPageIds.length, beforeMsgCount);
    expect(olderFin.complete, isTrue);

    await sub.cancel();
    await alice.disconnect();
    restAlice.close();
    restBob.close();
  });
}
