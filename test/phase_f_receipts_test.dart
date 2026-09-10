// Phase F acceptance — receipts (XEP-0184 / XEP-0333) + chat states
// (XEP-0085). Verifies: outbound sendChat requests receipts + markers;
// incoming <received> stamps deliveredAt; incoming <displayed> stamps
// seenAt; incoming <composing/> flips typingCapsule true; auto-send of
// receipt + read marker on inbound 1:1 messages.
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
  final List<({String to, String stanzaId})> deliveryReceipts = [];
  final List<({String to, String stanzaId})> readMarkers = [];
  final List<({String to, String state})> chatStates = [];

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
    sent.add((to: toBareJid, body: body, id: id));
  }

  @override
  void sendDeliveryReceipt({
    required String toBareJid,
    required String stanzaId,
  }) {
    deliveryReceipts.add((to: toBareJid, stanzaId: stanzaId));
  }

  @override
  void sendReadMarker({required String toBareJid, required String stanzaId}) {
    readMarkers.add((to: toBareJid, stanzaId: stanzaId));
  }

  @override
  void sendChatState({required String toBareJid, required String state}) {
    chatStates.add((to: toBareJid, state: state));
  }

  @override
  void queryMamWith(String peerBareJid, {int max = 50}) {}

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
    'incoming 1:1 message triggers auto-send of delivery receipt + read marker',
    () async {
      const threadKey = 'bob@localhost';
      container.read(chatControllerCapsule(threadKey));

      fakeXmpp.pushIncoming(
        const XmppChatMessage(
          from: 'bob@localhost/laptop',
          to: 'alice@localhost',
          body: 'hi alice',
          stanzaId: 'incoming-1',
          isGroupChat: false,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeXmpp.deliveryReceipts, hasLength(1));
      expect(fakeXmpp.deliveryReceipts.single.to, 'bob@localhost');
      expect(fakeXmpp.deliveryReceipts.single.stanzaId, 'incoming-1');
      expect(fakeXmpp.readMarkers, hasLength(1));
      expect(fakeXmpp.readMarkers.single.stanzaId, 'incoming-1');
    },
  );

  test('XmppDeliveryReceipt stamps deliveredAt on my sent message', () async {
    const threadKey = 'bob@localhost';
    final controller = container.read(chatControllerCapsule(threadKey));
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

    container.read(chatActionsCapsule).sendPeer(peer, 'ping');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final myStanzaId = fakeXmpp.sent.single.id!;

    fakeXmpp.pushIncoming(
      XmppDeliveryReceipt(fromBare: threadKey, stanzaId: myStanzaId),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final m = controller.messages.single as TextMessage;
    expect(m.sentAt, isNotNull);
    expect(m.deliveredAt, isNotNull);
    expect(m.seenAt, isNull);
  });

  test('XmppReadMarker stamps seenAt on my sent message', () async {
    const threadKey = 'bob@localhost';
    final controller = container.read(chatControllerCapsule(threadKey));
    final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

    container.read(chatActionsCapsule).sendPeer(peer, 'ping');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final myStanzaId = fakeXmpp.sent.single.id!;

    fakeXmpp.pushIncoming(
      XmppReadMarker(fromBare: threadKey, stanzaId: myStanzaId),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final m = controller.messages.single as TextMessage;
    expect(m.seenAt, isNotNull);
  });

  test(
    'typingCapsule flips true on <composing/> and back on <paused/>',
    () async {
      const threadKey = 'bob@localhost';
      expect(container.read(typingCapsule(threadKey)), isFalse);

      fakeXmpp.pushIncoming(
        const XmppChatState(fromBare: 'bob@localhost', state: 'composing'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(typingCapsule(threadKey)), isTrue);

      fakeXmpp.pushIncoming(
        const XmppChatState(fromBare: 'bob@localhost', state: 'paused'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(typingCapsule(threadKey)), isFalse);
    },
  );

  test('typingCapsule ignores composing from a different peer', () async {
    const threadKey = 'bob@localhost';
    container.read(typingCapsule(threadKey));

    fakeXmpp.pushIncoming(
      const XmppChatState(fromBare: 'carol@localhost', state: 'composing'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(container.read(typingCapsule(threadKey)), isFalse);
  });

  test(
    'chatActions.sendChatState dispatches to XMPP with the peer JID',
    () async {
      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
      container.read(chatActionsCapsule).sendChatState(peer, 'composing');

      expect(fakeXmpp.chatStates.single.to, 'bob@localhost');
      expect(fakeXmpp.chatStates.single.state, 'composing');
    },
  );
}
