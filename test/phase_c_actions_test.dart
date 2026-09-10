// Phase C acceptance — verifies chatActionsCapsule.sendPeer echoes locally
// through the messagesCapsule family (send round-trip without a network).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/config.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';
import 'package:rainbow_stub_consumer/rainbow/rest_client.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:rainbow_stub_consumer/state/capsules/auth_controller_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/chat_actions_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/messages_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/rest_capsule.dart';
import 'package:rainbow_stub_consumer/state/capsules/xmpp_capsule.dart';
import 'package:rearch/rearch.dart';

class _FakeRest extends RainbowRestClient {
  _FakeRest() : super(AppConfig.dev);

  @override
  Future<LoginResult> login(String email, String password) async {
    return LoginResult(
      token: 'tkn',
      expiresIn: 3600,
      loggedInUser: RainbowUser(id: 'alice', loginEmail: email),
    );
  }

  @override
  Future<void> logout() async {}

  @override
  void close() {}
}

class _FakeXmpp extends RainbowXmppClient {
  _FakeXmpp() : super(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');
  final _events = StreamController<XmppEvent>.broadcast();
  final List<({String to, String body})> sent = [];

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
  void sendChat({required String toBareJid, required String body, String? id}) {
    sent.add((to: toBareJid, body: body));
  }
}

void main() {
  test(
    'chatActionsCapsule.sendPeer dispatches to XMPP and echoes to messagesCapsule',
    () async {
      resetMessagesCapsuleCache();

      final rest = _FakeRest();
      final xmpp = _FakeXmpp();

      final container = MockableContainer();
      container.mock(restCapsule).apply((use) => rest);
      container.mock(xmppCapsule).apply((use) => xmpp);

      // Log in so authCapsule flips to SignedIn (needed for isMine derivation).
      final auth = container.read(authControllerCapsule);
      await auth.signIn('alice@rainbow-stub.local', 'pw');

      // Prime the messages capsule so its effect registers the appender.
      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@rainbow-stub.local');
      final threadKey = 'bob@localhost';
      final cap = messagesCapsule(threadKey);
      expect(container.read(cap), isEmpty);

      // Send via the actions capsule.
      final actions = container.read(chatActionsCapsule);
      actions.sendPeer(peer, 'hello');

      // Yield one microtask so the ValueWrapper mutation propagates.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(xmpp.sent.single.to, threadKey);
      expect(xmpp.sent.single.body, 'hello');

      final msgs = container.read(cap);
      expect(msgs, hasLength(1));
      expect(msgs.single.body, 'hello');
      expect(msgs.single.isMine, isTrue);

      container.dispose();
    },
  );
}
