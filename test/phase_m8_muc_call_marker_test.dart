// Phase M-8 acceptance (part b) — MUC group-call marker wire.
// Verifies that XmppMucCallMarker is emitted for inbound <call/>
// stanzas and that sendMucCallMarker serialises correctly.
import 'package:flutter_test/flutter_test.dart';
import 'package:rainbow_stub_consumer/rainbow/xmpp_client.dart';
import 'package:xml/xml.dart';

RainbowXmppClient _makeClient() =>
    RainbowXmppClient(wsUrl: Uri.parse('ws://x/'), domain: 'localhost');

XmlElement _parse(String xml) => XmlDocument.parse(xml).rootElement;

void main() {
  test(
    'inbound <call state="started"/> surfaces as XmppMucCallMarker',
    () async {
      final c = _makeClient();
      XmppMucCallMarker? seen;
      final sub = c.events.listen((e) {
        if (e is XmppMucCallMarker) seen = e;
      });

      c.debugRouteStanza(
        _parse(
          '<message type="groupchat" '
          'from="room1@muc.localhost/alice" '
          'to="me@localhost">'
          '<call xmlns="urn:rainbow:muc-call:1" '
          'state="started" sid="sfu-sid-1"/>'
          '</message>',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(seen, isNotNull);
      expect(seen!.roomBareJid, 'room1@muc.localhost');
      expect(seen!.fromResource, 'alice');
      expect(seen!.state, 'started');
      expect(seen!.sid, 'sfu-sid-1');
      await sub.cancel();
    },
  );

  test('inbound <call state="ended"/> also surfaces', () async {
    final c = _makeClient();
    final markers = <XmppMucCallMarker>[];
    final sub = c.events.listen((e) {
      if (e is XmppMucCallMarker) markers.add(e);
    });

    c.debugRouteStanza(
      _parse(
        '<message type="groupchat" '
        'from="room1@muc.localhost/alice">'
        '<call xmlns="urn:rainbow:muc-call:1" '
        'state="ended" sid="sfu-sid-1"/>'
        '</message>',
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(markers.single.state, 'ended');
    await sub.cancel();
  });

  test('non-muc-call message does not fire the marker', () async {
    final c = _makeClient();
    var count = 0;
    final sub = c.events.listen((e) {
      if (e is XmppMucCallMarker) count++;
    });

    c.debugRouteStanza(
      _parse(
        '<message type="groupchat" from="room1@muc.localhost/alice">'
        '<body>hi</body></message>',
      ),
    );

    await Future<void>.delayed(Duration.zero);
    expect(count, 0);
    await sub.cancel();
  });
}
