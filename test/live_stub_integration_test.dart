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
}
