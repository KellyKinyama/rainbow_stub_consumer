// Phase G acceptance — file attachments end-to-end. Verifies the two-
// step upload path in RainbowRestClient, the wire format of the
// XMPP <file> extension, sender-side echo as Message.image / Message.file,
// and the receive-side parse.
import 'dart:async';
import 'dart:convert';

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

  final List<({String peer, String name, String mime, int size})> uploads = [];

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
  Future<FileDescriptor> uploadFile({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    required String peerJid,
    String peerType = 'user',
  }) async {
    uploads.add((
      peer: peerJid,
      name: fileName,
      mime: mimeType,
      size: bytes.length,
    ));
    return FileDescriptor(
      id: 'file-${uploads.length}',
      fileName: fileName,
      mimeType: mimeType,
      size: bytes.length,
      downloadUrl: 'https://stub/files/file-${uploads.length}/data',
    );
  }

  @override
  void close() {}
}

class _FakeXmpp extends RainbowXmppClient {
  _FakeXmpp() : super(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');
  final _events = StreamController<XmppEvent>.broadcast();
  final List<({String to, String body, String? id, XmppAttachment? attachment})>
  sent = [];

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
    sent.add((to: toBareJid, body: body, id: id, attachment: attachment));
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
    'sendPeerFile uploads bytes then sends XMPP with a <file> attachment',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));
      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');
      final bytes = utf8.encode('hello file');

      await container
          .read(chatActionsCapsule)
          .sendPeerFile(
            peer,
            bytes: bytes,
            fileName: 'note.txt',
            mimeType: 'text/plain',
          );

      expect(fakeRest.uploads.single.peer, threadKey);
      expect(fakeRest.uploads.single.name, 'note.txt');
      expect(fakeRest.uploads.single.mime, 'text/plain');

      final s = fakeXmpp.sent.single;
      expect(s.to, threadKey);
      expect(s.attachment, isNotNull);
      expect(s.attachment!.fileName, 'note.txt');
      expect(s.attachment!.mimeType, 'text/plain');
      expect(s.attachment!.url, 'https://stub/files/file-1/data');

      // Local echo renders as a FileMessage (non-image mime).
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final m = controller.messages.single as FileMessage;
      expect(m.name, 'note.txt');
      expect(m.source, 'https://stub/files/file-1/data');
    },
  );

  test(
    'sendPeerFile with an image mime renders as Message.image locally',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));
      final peer = RainbowUser(id: 'bob', loginEmail: 'bob@localhost');

      await container
          .read(chatActionsCapsule)
          .sendPeerFile(
            peer,
            bytes: List.filled(64, 0),
            fileName: 'photo.jpg',
            mimeType: 'image/jpeg',
          );

      await Future<void>.delayed(const Duration(milliseconds: 5));

      final m = controller.messages.single;
      expect(m, isA<ImageMessage>());
      expect((m as ImageMessage).source, contains('/files/'));
    },
  );

  test('incoming XMPP <file> attachment surfaces as ImageMessage', () async {
    const threadKey = 'bob@localhost';
    final controller = container.read(chatControllerCapsule(threadKey));

    fakeXmpp.pushIncoming(
      const XmppChatMessage(
        from: 'bob@localhost/laptop',
        to: 'alice@localhost',
        body: '[File: pic.png]',
        stanzaId: 'inc-1',
        isGroupChat: false,
        attachment: XmppAttachment(
          id: 'f-42',
          url: 'https://stub/files/f-42/data',
          fileName: 'pic.png',
          mimeType: 'image/png',
          size: 1024,
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));

    final m = controller.messages.single as ImageMessage;
    expect(m.source, 'https://stub/files/f-42/data');
    expect(m.authorId, 'bob');
  });
}
