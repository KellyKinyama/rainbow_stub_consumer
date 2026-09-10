// Phase E acceptance — verifies chatControllerCapsule works for MUC
// (group) threads: MAM query is issued, incoming XMPP groupchat is
// filtered correctly, sender nick becomes the message authorId, and
// local group send-echo appears with isMine=me.
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
  final List<({String room, String body, String? id})> groupSent = [];
  final List<({String room, String nick})> mucJoins = [];
  final List<({String peer, int max})> mamQueries = [];

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
  void sendGroupChat({
    required String roomJid,
    required String body,
    String? id,
    XmppAttachment? attachment,
  }) {
    groupSent.add((room: roomJid, body: body, id: id));
  }

  @override
  void joinMuc(String roomJid, String nick) {
    mucJoins.add((room: roomJid, nick: nick));
  }

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
  const roomJid = 'ops@muc.localhost';

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
    'MUC chatControllerCapsule fires a one-shot MAM query for the room JID',
    () async {
      container.read(chatControllerCapsule(roomJid));
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(fakeXmpp.mamQueries, hasLength(1));
      expect(fakeXmpp.mamQueries.single.peer, roomJid);
    },
  );

  test(
    'incoming groupchat uses the resource part (nick) as authorId',
    () async {
      final controller = container.read(chatControllerCapsule(roomJid));

      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'ops@muc.localhost/bob',
          to: 'ops@muc.localhost',
          body: 'hi ops',
          stanzaId: 'g1',
          isGroupChat: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.messages, hasLength(1));
      final m = controller.messages.single as TextMessage;
      expect(m.text, 'hi ops');
      // For MUC the sender's user id lives in the RESOURCE part, not the
      // local part (which is the room id itself).
      expect(m.authorId, 'bob');
    },
  );

  test(
    'local group send-echo attributes authorship to the signed-in user',
    () async {
      final controller = container.read(chatControllerCapsule(roomJid));
      final bubble = RainbowBubble(id: 'ops', name: 'Ops', members: const []);

      container.read(chatActionsCapsule).sendGroup(bubble, 'from me');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeXmpp.groupSent.single.room, roomJid);
      expect(fakeXmpp.groupSent.single.body, 'from me');
      expect(controller.messages, hasLength(1));
      final m = controller.messages.single as TextMessage;
      expect(m.text, 'from me');
      expect(m.authorId, 'alice');
    },
  );

  test(
    'MAM MUC hydration inserts oldest-first with the correct nick author',
    () async {
      final controller = container.read(chatControllerCapsule(roomJid));

      fakeXmpp.pushIncoming(
        XmppMamMessage(
          from: 'ops@muc.localhost/bob',
          to: 'ops@muc.localhost',
          body: 'hello team',
          stanzaId: 'g-old-1',
          sentAt: DateTime.utc(2026, 1, 1, 9),
          isGroupChat: true,
        ),
      );
      fakeXmpp.pushIncoming(
        XmppMamMessage(
          from: 'ops@muc.localhost/carol',
          to: 'ops@muc.localhost',
          body: 'morning',
          stanzaId: 'g-old-2',
          sentAt: DateTime.utc(2026, 1, 1, 10),
          isGroupChat: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final texts = controller.messages
          .whereType<TextMessage>()
          .map((m) => (m.text, m.authorId))
          .toList();
      expect(texts, [('hello team', 'bob'), ('morning', 'carol')]);
    },
  );

  test(
    'resetMessagesCapsuleCache bumps generation so old capsules go dormant',
    () async {
      // First-user capsule for a 1:1 thread.
      final capBefore = chatControllerCapsule('bob@localhost');
      final controllerA = container.read(capBefore);

      // Simulate the same signout->signin flow the app takes: bump the
      // generation, then push a MAM event on the stream.
      resetMessagesCapsuleCache();

      fakeXmpp.pushIncoming(
        XmppMamMessage(
          from: 'bob@localhost/x',
          to: 'alice@localhost',
          body: 'stale',
          stanzaId: 's1',
          sentAt: DateTime.utc(2026, 1, 1, 8),
          isGroupChat: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // The old (stale) capsule ignored the event thanks to the generation
      // guard, so no phantom insert.
      expect(controllerA.messages, isEmpty);
    },
  );
}
