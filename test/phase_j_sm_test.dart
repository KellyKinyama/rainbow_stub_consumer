// Phase J acceptance — XEP-0198 stream-management state machine on the
// XmppClient side. The live integration test covers wire-level ack; this
// suite exercises the pure state transitions offline via
// `debug*` hooks on `RainbowXmppClient`.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:xml/xml.dart';

RainbowXmppClient _makeClient() =>
    RainbowXmppClient(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');

XmlElement _parse(String xml) => XmlDocument.parse(xml).rootElement;

XmlElement _ack(int h) => _parse('<a xmlns="urn:xmpp:sm:3" h="$h"/>');

XmlElement _incomingChat({
  required String from,
  required String to,
  required String id,
  required String body,
}) => _parse(
  '<message from="$from" to="$to" id="$id" type="chat"><body>$body</body></message>',
);

void main() {
  test(
    'sendChat with SM enabled increments _hOut and queues pending ack',
    () async {
      final c = _makeClient()..debugEnableSm();
      expect(c.debugHOut, 0);
      expect(c.debugPendingAckCount, 0);

      c.sendChat(toBareJid: 'bob@localhost', body: 'ping', id: 'stanza-1');

      expect(c.debugHOut, 1);
      expect(c.debugPendingAckCount, 1);
    },
  );

  test(
    '<a h=N/> drains pending entries with hOut <= N and emits XmppSentAck',
    () async {
      final c = _makeClient()..debugEnableSm();
      final acks = <String>[];
      final sub = c.events.listen((e) {
        if (e is XmppSentAck) acks.add(e.stanzaId);
      });

      c.sendChat(toBareJid: 'bob@localhost', body: 'a', id: 'a1');
      c.sendChat(toBareJid: 'bob@localhost', body: 'b', id: 'b2');
      c.sendChat(toBareJid: 'bob@localhost', body: 'c', id: 'c3');
      expect(c.debugPendingAckCount, 3);

      // Server has seen 2 of my 3 stanzas so far.
      c.debugRouteStanza(_ack(2));
      await Future<void>.delayed(Duration.zero);

      expect(acks, ['a1', 'b2']);
      expect(c.debugPendingAckCount, 1);

      // Later ack catches the rest.
      c.debugRouteStanza(_ack(3));
      await Future<void>.delayed(Duration.zero);
      expect(acks, ['a1', 'b2', 'c3']);
      expect(c.debugPendingAckCount, 0);

      await sub.cancel();
    },
  );

  test('<a h=N/> below the smallest pending hOut is a no-op', () async {
    final c = _makeClient()..debugEnableSm();
    var acks = 0;
    final sub = c.events.listen((e) {
      if (e is XmppSentAck) acks++;
    });

    c.sendChat(toBareJid: 'bob@localhost', body: 'ping', id: 'x1');
    c.debugRouteStanza(_ack(0));
    await Future<void>.delayed(Duration.zero);

    expect(acks, 0);
    expect(c.debugPendingAckCount, 1);
    await sub.cancel();
  });

  test('inbound counted stanzas advance _hIn only when SM is enabled', () {
    final c = _makeClient();
    // SM disabled: _hIn stays put.
    c.debugRouteStanza(
      _incomingChat(
        from: 'bob@localhost/x',
        to: 'alice@localhost',
        id: 'in1',
        body: 'hi',
      ),
    );
    expect(c.debugHIn, 0);

    c.debugEnableSm();
    c.debugRouteStanza(
      _incomingChat(
        from: 'bob@localhost/x',
        to: 'alice@localhost',
        id: 'in2',
        body: 'hi',
      ),
    );
    c.debugRouteStanza(
      _incomingChat(
        from: 'bob@localhost/x',
        to: 'alice@localhost',
        id: 'in3',
        body: 'hi',
      ),
    );
    expect(c.debugHIn, 2);
  });

  test('SM control stanzas are NOT counted for _hIn', () {
    final c = _makeClient()..debugEnableSm();
    c.debugRouteStanza(_ack(0));
    c.debugRouteStanza(_parse('<r xmlns="urn:xmpp:sm:3"/>'));
    expect(c.debugHIn, 0);
  });

  test('sendChat with SM DISABLED does not track pending acks', () {
    final c = _makeClient();
    c.sendChat(toBareJid: 'bob@localhost', body: 'no-sm', id: 'p1');
    expect(c.debugHOut, 0);
    expect(c.debugPendingAckCount, 0);
  });

  test(
    'sendGroupChat also registers a pending ack when SM is enabled',
    () async {
      final c = _makeClient()..debugEnableSm();
      final acks = <String>[];
      final sub = c.events.listen((e) {
        if (e is XmppSentAck) acks.add(e.stanzaId);
      });

      c.sendGroupChat(
        roomJid: 'room1@muc.localhost',
        body: 'muc-hi',
        id: 'muc-1',
      );
      expect(c.debugPendingAckCount, 1);

      c.debugRouteStanza(_ack(1));
      await Future<void>.delayed(Duration.zero);
      expect(acks, ['muc-1']);

      await sub.cancel();
    },
  );
}
