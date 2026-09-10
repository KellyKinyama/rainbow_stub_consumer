// Phase K acceptance — XEP-0313 "load older" MAM pagination on the
// client. Exercises the MamPageState cursor + [loadOlderMessages]
// helper offline via injected XmppMamMessage / XmppMamFin events.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/config.dart';
import 'package:rainbow_stub_consumer/rainbow/models.dart';
import 'package:rainbow_stub_consumer/rainbow/rest_client.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:rainbow_stub_consumer/state/capsules/auth_controller_capsule.dart';
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
  }) {}

  final List<({String peer, int max, String? before, String qid})> mamQueries =
      [];
  int _mamCounter = 0;

  @override
  String queryMamWith(
    String peerBareJid, {
    int max = 50,
    String? beforeStanzaId,
  }) {
    final qid = 'mam-${_mamCounter++}';
    mamQueries.add((
      peer: peerBareJid,
      max: max,
      before: beforeStanzaId,
      qid: qid,
    ));
    return qid;
  }

  void pushIncoming(XmppEvent e) => _events.add(e);
}

XmppMamMessage _mam({
  required String id,
  required String body,
  required DateTime sentAt,
  String from = 'bob@localhost/laptop',
  String to = 'alice@localhost',
}) =>
    XmppMamMessage(
      from: from,
      to: to,
      body: body,
      stanzaId: id,
      sentAt: sentAt,
      isGroupChat: false,
    );

XmppMamFin _fin({
  required String queryId,
  required String first,
  required String last,
  bool complete = false,
  int count = 0,
}) =>
    XmppMamFin(
      queryId: queryId,
      complete: complete,
      first: first,
      last: last,
      count: count,
    );

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
    'initial MAM <fin/> populates the oldest-anchor for load-older',
    () async {
      const threadKey = 'bob@localhost';
      container.read(chatControllerCapsule(threadKey));

      // Simulate a hydration page of 2 messages then the fin.
      fakeXmpp.pushIncoming(
        _mam(id: 'msg-10', body: 'ten', sentAt: DateTime(2026, 1, 10)),
      );
      fakeXmpp.pushIncoming(
        _mam(id: 'msg-11', body: 'eleven', sentAt: DateTime(2026, 1, 11)),
      );
      fakeXmpp.pushIncoming(
        _fin(
          queryId: 'ignored-initial',
          first: 'msg-10',
          last: 'msg-11',
          complete: false,
          count: 200,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final state = mamPageStateOf(threadKey);
      expect(state.oldestStanzaId, 'msg-10');
      expect(state.complete, isFalse);
      expect(state.canLoadMore, isTrue);
    },
  );

  test(
    'loadOlderMessages fires a MAM query anchored <before> the top',
    () async {
      const threadKey = 'bob@localhost';
      container.read(chatControllerCapsule(threadKey));

      // Seed the initial anchor.
      fakeXmpp.pushIncoming(
        _mam(id: 'msg-10', body: 'ten', sentAt: DateTime(2026, 1, 10)),
      );
      fakeXmpp.pushIncoming(
        _fin(
          queryId: 'initial',
          first: 'msg-10',
          last: 'msg-10',
          complete: false,
          count: 100,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final started = loadOlderMessages(fakeXmpp, threadKey, max: 25);
      expect(started, isTrue);

      final q = fakeXmpp.mamQueries.last;
      expect(q.peer, threadKey);
      expect(q.max, 25);
      expect(q.before, 'msg-10');
      expect(mamPageStateOf(threadKey).loadingQueryId, q.qid);
    },
  );

  test('loadOlderMessages is a no-op while a page is in flight', () async {
    const threadKey = 'bob@localhost';
    container.read(chatControllerCapsule(threadKey));
    fakeXmpp.pushIncoming(
      _mam(id: 'msg-10', body: 'x', sentAt: DateTime(2026, 1, 10)),
    );
    fakeXmpp.pushIncoming(
      _fin(queryId: 'initial', first: 'msg-10', last: 'msg-10'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(loadOlderMessages(fakeXmpp, threadKey), isTrue);
    // Second call while first is in flight should refuse.
    expect(loadOlderMessages(fakeXmpp, threadKey), isFalse);
  });

  test('loadOlderMessages is a no-op once fin.complete=true is seen', () async {
    const threadKey = 'bob@localhost';
    container.read(chatControllerCapsule(threadKey));
    fakeXmpp.pushIncoming(
      _mam(id: 'msg-10', body: 'x', sentAt: DateTime(2026, 1, 10)),
    );
    fakeXmpp.pushIncoming(
      _fin(
        queryId: 'initial',
        first: 'msg-10',
        last: 'msg-10',
        complete: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(mamPageStateOf(threadKey).complete, isTrue);
    expect(loadOlderMessages(fakeXmpp, threadKey), isFalse);
  });

  test(
    'a load-older page piles ABOVE the existing hydrated slice',
    () async {
      const threadKey = 'bob@localhost';
      final controller = container.read(chatControllerCapsule(threadKey));

      // Initial hydration: 2 messages.
      fakeXmpp.pushIncoming(
        _mam(id: 'msg-50', body: 'fifty', sentAt: DateTime(2026, 1, 50)),
      );
      fakeXmpp.pushIncoming(
        _mam(id: 'msg-51', body: 'fiftyone', sentAt: DateTime(2026, 1, 51)),
      );
      fakeXmpp.pushIncoming(
        _fin(
          queryId: 'initial',
          first: 'msg-50',
          last: 'msg-51',
          complete: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.messages.map((m) => m.id), ['msg-50', 'msg-51']);

      // Kick off load-older; drives a fresh page anchored at msg-50.
      loadOlderMessages(fakeXmpp, threadKey, max: 3);
      final qid = fakeXmpp.mamQueries.last.qid;

      // Server returns 3 older ones in ASC order.
      fakeXmpp.pushIncoming(
        _mam(id: 'msg-47', body: 'A', sentAt: DateTime(2026, 1, 47)),
      );
      fakeXmpp.pushIncoming(
        _mam(id: 'msg-48', body: 'B', sentAt: DateTime(2026, 1, 48)),
      );
      fakeXmpp.pushIncoming(
        _mam(id: 'msg-49', body: 'C', sentAt: DateTime(2026, 1, 49)),
      );
      fakeXmpp.pushIncoming(
        _fin(
          queryId: qid,
          first: 'msg-47',
          last: 'msg-49',
          complete: false,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        controller.messages.map((m) => m.id).toList(),
        ['msg-47', 'msg-48', 'msg-49', 'msg-50', 'msg-51'],
      );
      expect(mamPageStateOf(threadKey).oldestStanzaId, 'msg-47');
      expect(mamPageStateOf(threadKey).canLoadMore, isTrue);
    },
  );

  test(
    'load-older marks the thread complete when server ends with '
    'fin.complete=true',
    () async {
      const threadKey = 'bob@localhost';
      container.read(chatControllerCapsule(threadKey));

      fakeXmpp.pushIncoming(
        _mam(id: 'msg-5', body: 'x', sentAt: DateTime(2026, 1, 5)),
      );
      fakeXmpp.pushIncoming(
        _fin(queryId: 'initial', first: 'msg-5', last: 'msg-5', complete: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      loadOlderMessages(fakeXmpp, threadKey);
      final qid = fakeXmpp.mamQueries.last.qid;

      fakeXmpp.pushIncoming(
        _mam(id: 'msg-1', body: 'first', sentAt: DateTime(2026, 1, 1)),
      );
      fakeXmpp.pushIncoming(
        _fin(queryId: qid, first: 'msg-1', last: 'msg-1', complete: true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(mamPageStateOf(threadKey).complete, isTrue);
      expect(mamPageStateOf(threadKey).canLoadMore, isFalse);
    },
  );
}
