// Phase O acceptance — XEP-0425 message moderation: the moderator IQ is
// sent, and an incoming <moderated> tombstone replaces the target message
// with a "removed by a moderator" placeholder in the controller.
import 'dart:async';

import 'package:flutter_chat_core/flutter_chat_core.dart';
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
  final List<({String room, String targetId, String? reason})> moderations = [];

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
  void sendModeration({
    required String roomBareJid,
    required String targetStanzaId,
    String? reason,
  }) {
    moderations.add((room: roomBareJid, targetId: targetStanzaId, reason: reason));
  }

  @override
  String queryMamWith(
    String peerBareJid, {
    int max = 50,
    String? beforeStanzaId,
  }) => 'fake-mam-qid';

  void pushIncoming(XmppEvent e) => _events.add(e);
}

void main() {
  late _FakeRest fakeRest;
  late _FakeXmpp fakeXmpp;
  late MockableContainer container;

  setUp(() async {
    resetMessagesCapsuleCache();
    fakeRest = _FakeRest();
    fakeXmpp = _FakeXmpp();
    container = MockableContainer();
    container.mock(restCapsule).apply((use) => fakeRest);
    container.mock(xmppCapsule).apply((use) => fakeXmpp);
    final auth = container.read(authControllerCapsule);
    await auth.signIn('alice@rainbow-stub.local', 'pw');
  });

  tearDown(() {
    container.dispose();
  });

  test('moderateGroup sends the XEP-0425 moderation IQ', () {
    final bubble = RainbowBubble(id: 'ops', name: 'Ops', members: const []);
    container
        .read(chatActionsCapsule)
        .moderateGroup(bubble, targetStanzaId: 'g-1', reason: 'spam');

    expect(fakeXmpp.moderations, hasLength(1));
    expect(fakeXmpp.moderations.single.room, 'ops@muc.localhost');
    expect(fakeXmpp.moderations.single.targetId, 'g-1');
    expect(fakeXmpp.moderations.single.reason, 'spam');
  });

  test('incoming XmppModeration replaces the target with a tombstone',
      () async {
    const roomJid = 'ops@muc.localhost';
    final controller = container.read(chatControllerCapsule(roomJid));

    fakeXmpp.pushIncoming(
      const XmppChatMessage(
        from: 'ops@muc.localhost/bob',
        to: 'ops@muc.localhost',
        body: 'spam spam spam',
        stanzaId: 'g-1',
        isGroupChat: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.messages, hasLength(1));

    fakeXmpp.pushIncoming(
      const XmppModeration(
        fromBare: roomJid,
        targetStanzaId: 'g-1',
        byBare: 'alice@localhost',
        reason: 'spam',
        isGroupChat: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // The message stays in place but becomes a moderation tombstone.
    expect(controller.messages, hasLength(1));
    final only = controller.messages.single;
    expect(only, isA<TextMessage>());
    expect((only as TextMessage).text, contains('removed by a moderator'));
    expect(only.text, contains('spam'));
    expect(only.metadata?['moderated'], isTrue);
  });

  test('XmppModeration from a foreign room does NOT touch this controller',
      () async {
    const roomJid = 'ops@muc.localhost';
    final controller = container.read(chatControllerCapsule(roomJid));

    fakeXmpp.pushIncoming(
      const XmppChatMessage(
        from: 'ops@muc.localhost/bob',
        to: 'ops@muc.localhost',
        body: 'keep me',
        stanzaId: 'g-2',
        isGroupChat: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.messages, hasLength(1));

    fakeXmpp.pushIncoming(
      const XmppModeration(
        fromBare: 'other@muc.localhost',
        targetStanzaId: 'g-2',
        byBare: 'alice@localhost',
        reason: null,
        isGroupChat: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final only = controller.messages.single;
    expect(only, isA<TextMessage>());
    expect((only as TextMessage).text, 'keep me');
  });
}
