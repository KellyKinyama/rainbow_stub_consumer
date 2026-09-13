// Phase H acceptance — reactions (XEP-0444), edits (XEP-0308), and
// replies (XEP-0461) round-trip through the capsule + flutter_chat_ui
// Message model.
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
  final List<({String to, String targetId, List<String> emojis})> reactions =
      [];
  final List<({String to, String origId, String body})> corrections = [];

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
  void sendReactions({
    required String toBareJid,
    required String targetStanzaId,
    required List<String> emojis,
    bool isGroupChat = false,
  }) {
    reactions.add((to: toBareJid, targetId: targetStanzaId, emojis: emojis));
  }

  @override
  void sendChatCorrection({
    required String toBareJid,
    required String originalStanzaId,
    required String newBody,
    String? id,
    bool isGroupChat = false,
  }) {
    corrections.add((to: toBareJid, origId: originalStanzaId, body: newBody));
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

  test('reactToPeer sends XEP-0444 reactions and echoes locally', () async {
    const threadKey = 'bob@localhost';
    final controller = container.read(chatControllerCapsule(threadKey));
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

    // Seed a target message.
    fakeXmpp.pushIncoming(
      const XmppChatMessage(
        from: 'bob@localhost/x',
        to: 'alice@localhost',
        body: 'hey',
        stanzaId: 't1',
        isGroupChat: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    container
        .read(chatActionsCapsule)
        .reactToPeer(peer, targetStanzaId: 't1', emojis: ['🔥']);

    expect(fakeXmpp.reactions.single.targetId, 't1');
    expect(fakeXmpp.reactions.single.emojis, ['🔥']);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    final m = controller.messages.single as TextMessage;
    expect(m.reactions?['🔥'], ['alice']);
  });

  test(
    'incoming XmppReactions merges into the target message reactions',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));

      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'alice@localhost/flutter',
          to: 'bob@localhost',
          body: 'yo',
          stanzaId: 'mine-1',
          isGroupChat: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      fakeXmpp.pushIncoming(
        const XmppReactions(
          fromBare: 'bob@localhost',
          targetStanzaId: 'mine-1',
          emojis: ['❤️', '😂'],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final m = controller.messages.single as TextMessage;
      expect(m.reactions?['❤️'], ['bob']);
      expect(m.reactions?['😂'], ['bob']);
    },
  );

  test('editPeer replaces body and stamps editedAt', () async {
    const threadKey = 'bob@localhost';
    final controller = container.read(chatControllerCapsule(threadKey));
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

    container.read(chatActionsCapsule).sendPeer(peer, 'origginal');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final origId = fakeXmpp.sent.single.id!;

    container
        .read(chatActionsCapsule)
        .editPeer(peer, originalStanzaId: origId, newBody: 'original');

    expect(fakeXmpp.corrections.single.origId, origId);
    expect(fakeXmpp.corrections.single.body, 'original');

    await Future<void>.delayed(const Duration(milliseconds: 10));
    final m = controller.messages.single as TextMessage;
    expect(m.text, 'original');
    expect(m.editedAt, isNotNull);
  });

  test('incoming XmppMessageCorrection replaces the original body', () async {
    const threadKey = 'bob@localhost';
    final controller = container.read(chatControllerCapsule(threadKey));

    fakeXmpp.pushIncoming(
      const XmppChatMessage(
        from: 'bob@localhost/x',
        to: 'alice@localhost',
        body: 'typo',
        stanzaId: 'b1',
        isGroupChat: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    fakeXmpp.pushIncoming(
      const XmppMessageCorrection(
        fromBare: 'bob@localhost',
        originalStanzaId: 'b1',
        newBody: 'no typo',
        newStanzaId: 'b1-fix',
        isGroupChat: false,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(controller.messages, hasLength(1));
    final m = controller.messages.single as TextMessage;
    expect(m.text, 'no typo');
  });

  test(
    'sendPeer with replyToStanzaId propagates through XMPP and Message',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));
      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

      container
          .read(chatActionsCapsule)
          .sendPeer(peer, 'thanks', replyToStanzaId: 'target-99');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeXmpp.sent.single.replyTo, 'target-99');

      final m = controller.messages.single as TextMessage;
      expect(m.replyToMessageId, 'target-99');
    },
  );

  test('incoming <reply> child surfaces as Message.replyToMessageId', () async {
    const threadKey = 'bob@localhost';
    final controller = container.read(chatControllerCapsule(threadKey));

    fakeXmpp.pushIncoming(
      const XmppChatMessage(
        from: 'bob@localhost/x',
        to: 'alice@localhost',
        body: 'sure',
        stanzaId: 'reply-1',
        isGroupChat: false,
        replyToStanzaId: 'orig-42',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final m = controller.messages.single as TextMessage;
    expect(m.replyToMessageId, 'orig-42');
  });
}
