// Phase I acceptance — XEP-0424 message retraction ("Delete for
// everyone") round-trips through the capsule + InMemoryChatController.
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
  final List<({String to, String body, String? id, String? replyTo})> sent = [];
  final List<({String to, String targetId, bool isGroupChat})> retracts = [];

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
  void sendChat({
    required String toBareJid,
    required String body,
    String? id,
    XmppAttachment? attachment,
    String? replyToStanzaId,
  }) {
    sent.add((to: toBareJid, body: body, id: id, replyTo: replyToStanzaId));
  }

  @override
  void sendRetract({
    required String toBareJid,
    required String targetStanzaId,
    bool isGroupChat = false,
  }) {
    retracts.add((
      to: toBareJid,
      targetId: targetStanzaId,
      isGroupChat: isGroupChat,
    ));
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

  test(
    'retractPeer sends XEP-0424 <retract> and removes the message locally',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));
      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

      container.read(chatActionsCapsule).sendPeer(peer, 'oops');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final myStanzaId = fakeXmpp.sent.single.id!;
      expect(controller.messages, hasLength(1));

      container
          .read(chatActionsCapsule)
          .retractPeer(peer, targetStanzaId: myStanzaId);

      expect(fakeXmpp.retracts.single.to, threadKey);
      expect(fakeXmpp.retracts.single.targetId, myStanzaId);
      expect(fakeXmpp.retracts.single.isGroupChat, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.messages, isEmpty);
    },
  );

  test(
    'incoming XmppRetract removes the target message from the controller',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));

      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'bob@localhost/laptop',
          to: 'alice@localhost',
          body: 'delete me',
          stanzaId: 'bob-1',
          isGroupChat: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.messages, hasLength(1));

      fakeXmpp.pushIncoming(
        const XmppRetract(
          fromBare: threadKey,
          targetStanzaId: 'bob-1',
          isGroupChat: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.messages, isEmpty);
    },
  );

  test(
    'XmppRetract from a foreign thread does NOT touch this controller',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));

      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'bob@localhost/laptop',
          to: 'alice@localhost',
          body: 'keep me',
          stanzaId: 'bob-2',
          isGroupChat: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.messages, hasLength(1));

      // Retract targeting the same stanzaId, but coming from a different
      // peer — the membership predicate on `retractSub` must reject it.
      fakeXmpp.pushIncoming(
        const XmppRetract(
          fromBare: 'eve@localhost',
          targetStanzaId: 'bob-2',
          isGroupChat: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.messages, hasLength(1));
    },
  );

  test('retractGroup sends XEP-0424 to the MUC bare JID', () async {
    const bubbleJid = 'room1@muc.localhost';
    final bubble = RainbowBubble(
      id: 'room1',
      name: 'Room 1',
      members: const [],
    );

    container
        .read(chatActionsCapsule)
        .retractGroup(bubble, targetStanzaId: 'muc-msg-1');

    expect(fakeXmpp.retracts.single.to, bubbleJid);
    expect(fakeXmpp.retracts.single.targetId, 'muc-msg-1');
    expect(fakeXmpp.retracts.single.isGroupChat, isTrue);
  });

  test('XmppSentAck stamps sentAt and clears MessageStatus.sending', () async {
    const threadKey = 'bob@localhost';
    final controller = container.read(chatControllerCapsule(threadKey));
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

    container.read(chatActionsCapsule).sendPeer(peer, 'ping');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final myStanzaId = fakeXmpp.sent.single.id!;

    final pending = controller.messages.single as TextMessage;
    expect(pending.status, MessageStatus.sending);
    expect(pending.sentAt, isNull);

    fakeXmpp.pushIncoming(XmppSentAck(stanzaId: myStanzaId));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final acked = controller.messages.single as TextMessage;
    expect(acked.status, isNull);
    expect(acked.sentAt, isNotNull);
  });
}
