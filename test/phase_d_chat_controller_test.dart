// Phase D acceptance — verifies chatControllerCapsule builds an
// InMemoryChatController that mirrors both live XMPP messages AND
// local send-echo, without emitting duplicates.
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
  final List<({String to, String body, String? id})> sent = [];

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
  void sendChat({required String toBareJid, required String body, String? id, XmppAttachment? attachment}) {
    sent.add((to: toBareJid, body: body, id: id));
  }

  final List<({String peer, int max})> mamQueries = [];

  @override
  void queryMamWith(String peerBareJid, {int max = 50}) {
    mamQueries.add((peer: peerBareJid, max: max));
  }

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
    'chatControllerCapsule renders local echo as flutter_chat_core Message',
    () async {
      final threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));
      expect(controller.messages, isEmpty);

      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
      container.read(chatActionsCapsule).sendPeer(peer, 'hello');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.messages, hasLength(1));
      final m = controller.messages.single;
      expect(m, isA<TextMessage>());
      expect((m as TextMessage).text, 'hello');
      expect(m.authorId, 'alice');
    },
  );

  test(
    'chatControllerCapsule appends incoming XMPP messages for the thread',
    () async {
      final threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));

      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'bob@localhost/laptop',
          to: 'alice@localhost/flutter',
          body: 'hi from bob',
          stanzaId: 'stanza-1',
          isGroupChat: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.messages, hasLength(1));
      final m = controller.messages.single as TextMessage;
      expect(m.text, 'hi from bob');
      expect(m.authorId, 'bob');
      expect(m.id, 'stanza-1');
    },
  );

  test(
    'dedupes when a local send is echoed back as a carbon with the same id',
    () async {
      final threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));
      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

      container.read(chatActionsCapsule).sendPeer(peer, 'ping');
      final stanzaId = fakeXmpp.sent.single.id!;

      fakeXmpp.pushIncoming(
        XmppChatMessage(
          from: 'alice@localhost/flutter',
          to: 'bob@localhost',
          body: 'ping',
          stanzaId: stanzaId,
          isGroupChat: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.id, stanzaId);
    },
  );

  test(
    'messagesCapsule and chatControllerCapsule stay in sync across the same thread',
    () async {
      final threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));
      final listSnapshot = container.read(messagesCapsule(threadKey));
      expect(controller.messages, isEmpty);
      expect(listSnapshot, isEmpty);

      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'bob@localhost/laptop',
          to: 'alice@localhost/flutter',
          body: 'multi-listener',
          stanzaId: 'sx',
          isGroupChat: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.messages, hasLength(1));
      final replayedList = container.read(messagesCapsule(threadKey));
      expect(replayedList, hasLength(1));
      expect(replayedList.single.body, 'multi-listener');
    },
  );

  test(
    'chatControllerCapsule fires a one-shot MAM query for 1:1 threads',
    () async {
      const threadKey = 'bob@localhost';
      container.read(chatControllerCapsule(threadKey));

      // Timer.run schedules the query on the microtask queue.
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(fakeXmpp.mamQueries, hasLength(1));
      expect(fakeXmpp.mamQueries.single.peer, threadKey);
    },
  );

  test(
    'MAM messages hydrate in chronological order at the top of the list',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));

      // Push three MAM messages oldest-first (per XEP-0313), then a live
      // message. The MAM block must stay above the live message.
      fakeXmpp.pushIncoming(
        XmppMamMessage(
          from: 'alice@localhost/x',
          to: 'bob@localhost',
          body: 'first',
          stanzaId: 'm1',
          sentAt: DateTime.utc(2026, 1, 1, 10),
          isGroupChat: false,
        ),
      );
      fakeXmpp.pushIncoming(
        XmppMamMessage(
          from: 'bob@localhost/y',
          to: 'alice@localhost',
          body: 'second',
          stanzaId: 'm2',
          sentAt: DateTime.utc(2026, 1, 1, 11),
          isGroupChat: false,
        ),
      );
      fakeXmpp.pushIncoming(
        XmppMamMessage(
          from: 'alice@localhost/x',
          to: 'bob@localhost',
          body: 'third',
          stanzaId: 'm3',
          sentAt: DateTime.utc(2026, 1, 1, 12),
          isGroupChat: false,
        ),
      );
      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'bob@localhost/y',
          to: 'alice@localhost',
          body: 'live',
          stanzaId: 'live-1',
          isGroupChat: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final texts = controller.messages
          .whereType<TextMessage>()
          .map((m) => m.text)
          .toList();
      expect(texts, ['first', 'second', 'third', 'live']);
    },
  );

  test(
    'MAM result with same stanza id as a live message deduplicates',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));

      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'bob@localhost/y',
          to: 'alice@localhost',
          body: 'shared',
          stanzaId: 'dup-id',
          isGroupChat: false,
        ),
      );
      fakeXmpp.pushIncoming(
        XmppMamMessage(
          from: 'bob@localhost/y',
          to: 'alice@localhost',
          body: 'shared',
          stanzaId: 'dup-id',
          sentAt: DateTime.utc(2026, 1, 1, 9),
          isGroupChat: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.messages, hasLength(1));
      expect(controller.messages.single.id, 'dup-id');
    },
  );
}
