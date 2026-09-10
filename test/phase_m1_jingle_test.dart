// Phase M-1 acceptance — XEP-0166 Jingle signaling passthrough. The
// stub is exercised by the live suite; here we cover the client-side
// parser: an inbound `<iq><jingle .../></iq>` produces an [XmppJingle]
// event with the raw payload preserved for later SDP decoding.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:xml/xml.dart';

RainbowXmppClient _makeClient() =>
    RainbowXmppClient(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');

XmlElement _parse(String xml) => XmlDocument.parse(xml).rootElement;

void main() {
  test('inbound session-initiate iq surfaces as XmppJingle', () async {
    final c = _makeClient();
    XmppJingle? seen;
    final sub = c.events.listen((e) {
      if (e is XmppJingle) seen = e;
    });

    c.debugRouteStanza(
      _parse(
        '<iq type="set" id="j1" '
        'from="bob@localhost/laptop" '
        'to="alice@localhost/flutter">'
        '<jingle xmlns="urn:xmpp:jingle:1" '
        'action="session-initiate" sid="s-1" '
        'initiator="bob@localhost/laptop">'
        '<content name="audio" creator="initiator">'
        '<description xmlns="urn:xmpp:jingle:apps:rtp:1" media="audio"/>'
        '<transport xmlns="urn:xmpp:jingle:transports:ice-udp:1"/>'
        '</content>'
        '</jingle></iq>',
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(seen, isNotNull);
    expect(seen!.action, 'session-initiate');
    expect(seen!.sid, 's-1');
    expect(seen!.iqId, 'j1');
    expect(seen!.fromFullJid, 'bob@localhost/laptop');
    expect(seen!.jingleXml, contains('urn:xmpp:jingle:apps:rtp:1'));

    await sub.cancel();
  });

  test('inbound transport-info iq surfaces as XmppJingle', () async {
    final c = _makeClient();
    final events = <XmppJingle>[];
    final sub = c.events.listen((e) {
      if (e is XmppJingle) events.add(e);
    });

    c.debugRouteStanza(
      _parse(
        '<iq type="set" id="j2" from="bob@localhost/laptop">'
        '<jingle xmlns="urn:xmpp:jingle:1" '
        'action="transport-info" sid="s-1">'
        '<content name="audio" creator="initiator">'
        '<transport xmlns="urn:xmpp:jingle:transports:ice-udp:1">'
        '<candidate id="1" component="1" foundation="1" '
        'ip="10.0.0.1" port="55555" priority="1" type="host"/>'
        '</transport>'
        '</content>'
        '</jingle></iq>',
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, hasLength(1));
    expect(events.first.action, 'transport-info');
    expect(events.first.sid, 's-1');

    await sub.cancel();
  });

  test('non-jingle iq is silently ignored', () async {
    final c = _makeClient();
    var count = 0;
    final sub = c.events.listen((e) {
      if (e is XmppJingle) count++;
    });

    c.debugRouteStanza(
      _parse('<iq type="result" id="ping-1" from="localhost"/>'),
    );

    await Future<void>.delayed(Duration.zero);
    expect(count, 0);
    await sub.cancel();
  });
}
